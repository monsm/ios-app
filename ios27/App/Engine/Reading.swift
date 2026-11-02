// Reading.swift —— 「一个值 = 一处写法」的读数层（Engine）。
//
// 2026-11-02「全换系统」：这一层是为了终结全仓「同一个数在不同页各有各的写法」——
// 审计实测：电量 9 处、连接状态 8 处、固件 7 处、锁钟 6 处、安全模式 5 处，
// 其中最刺眼的是**门页同一页两个电量**（芯片直读 `lock.battery`，正文走 `BatteryCare.displayPct`，
// 两条取值规则不同，会显示两个数）。
//
// 纪律：界面**只调这里**，不再自己拼字符串。改口径只改这一个文件。
// 每个函数返回 `Reading.Value`（文字 + 可选单位 + 色调），界面按需取用。
import SwiftUI

enum Reading {
    /// 一枚读数的完整呈现：文字 / 单位 / 色调。`text` 已经包含单位之外的全部内容。
    struct Value: Equatable {
        var text: String
        var unit: String? = nil
        var tone: Tone = .neutral
        /// 无障碍朗读用的完整句子（含单位）。界面可直接喂给 accessibilityValue。
        var spoken: String { unit.map { "\(text) \($0)" } ?? text }
        static let unknown = Value(text: "未读到", tone: .neutral)
    }

    // MARK: - 电量

    /// 电量的**唯一**口径。
    ///
    /// 取值规则：`BatteryCare.displayPct`（采样表最新值与锁侧快照取较新的那个）。
    /// 展示规则：<0 未读到 → 「未读到」；>80 只报「>80%」（锁侧这个量本身是粗估档）。
    /// - Parameter snapshot: 该锁快照里的 `powerLevel`；**跨锁调用必须传 -1**，否则 A 锁电量会安到 B 锁头上。
    static func battery(_ mac: String, snapshot: Int = -1) -> Value {
        let pct = BatteryCare.displayPct(mac, snapshot: snapshot)
        guard pct >= 0 else { return Value(text: "未读到", tone: .neutral) }
        let tone: Tone = pct <= 10 ? .critical : (pct <= 20 ? .attention : .ok)
        return Value(text: BatteryCare.faceText(pct).replacingOccurrences(of: "%", with: ""), unit: "%", tone: tone)
    }

    /// 电量是否低到需要提醒（≤20%）。界面要「涂色/加一句提醒」时用这个，不要各自写阈值。
    static func batteryIsLow(_ mac: String, snapshot: Int = -1) -> Bool {
        let pct = BatteryCare.displayPct(mac, snapshot: snapshot)
        return pct >= 0 && pct <= 20
    }

    // MARK: - 连接 / 信号

    /// 连接状态。全仓原本有 8 处各自判断（`isConnected` / `phase` / `connectedMAC` 三种来源）。
    ///
    /// `@MainActor`：`LockService` 是 `@MainActor` 类（`connectedMAC` 是它的 `@Published` 属性），
    /// 从这里读它必须在主线程。本函数的所有调用点都是 SwiftUI View（`View` 的 `body` 是 `@MainActor`，
    /// 整个 struct 因此被推断为 `@MainActor`），所以调用侧不需要 await。
    @MainActor
    static func link(_ mac: String) -> Value {
        guard !mac.isEmpty else { return Value(text: "没有门锁", tone: .neutral) }
        if LockService.shared.connectedMAC == mac { return Value(text: "已连接", tone: .ok) }
        return Value(text: "未连接", tone: .neutral)
    }

    /// 信号：dBm + 一个词。`nil` = 从未测到。
    /// 档位判据只写在 `LinkSenseModel.level` 一处（≥-55 满 / ≥-65 近 / ≥-75 中 / ≥-85 远 / 更弱不可测）。
    ///
    /// `@MainActor`：`LinkSenseModel` 是 `@MainActor` 类（`savedRSSI` / `level` / `levelWord` 都挂在它上面）。
    @MainActor
    static func signal(_ mac: String) -> Value {
        rssiText(LinkSenseModel.savedRSSI(mac))
    }

    /// 任意一次 RSSI 采样 → dBm + 档位词。**不读库**，给「还没绑定的候选设备」用
    /// （配网候选列表 / 协议测试扫描 / 门页 live RSSI —— 这些设备没有 `kf_linkrssi_<mac>`）。
    ///
    /// `@MainActor`：档位判据 `LinkSenseModel.level` / `levelWord` 是 `@MainActor` 类的静态方法。
    @MainActor
    static func rssiText(_ rssi: Int?) -> Value {
        guard let rssi else { return Value(text: "未测", tone: .neutral) }
        let level = LinkSenseModel.level(rssi)
        return Value(text: "\(rssi)", unit: "dBm · \(LinkSenseModel.levelWord(level))",
                      tone: level <= 1 ? .attention : .neutral)
    }

    // MARK: - 固件 / 锁钟 / 模式

    /// 固件版本。空串 = 该固件不报这一项（不是读取失败）。
    static func firmware(_ mac: String) -> Value {
        let v = DB.readStatus(mac)?.firmware ?? ""
        return v.isEmpty ? Value(text: "未上报", tone: .neutral) : Value(text: v, tone: .neutral)
    }

    /// 锁内时间。0 = 从未同步过（**不要**把 0 当成 1970 年显示出来）。
    static func lockClock(_ mac: String) -> Value {
        let t = DB.readStatus(mac)?.lockTime ?? 0
        guard t > 0 else { return Value(text: "未读到", tone: .neutral) }
        // ⚠ lockTime 是**协议秒**（StatusParser KLV#04，2010-01-01 起算），不是毫秒 epoch。
        // 直接当毫秒用会显示成 1970-01-07、偏差约 -57 年 —— 这正是 SyncTimeScreen 注释里
        // 那条用户实测过的「531260264 秒」bug，别在这里重新引入。
        let ms = ZKProtocol.protoSecondsToMs(t)
        let drift = Int(Date(timeIntervalSince1970: Double(ms) / 1000).timeIntervalSinceNow)
        let tone: Tone = abs(drift) > 60 ? .attention : .ok
        return Value(text: TimeFormat.clock(ms), tone: tone)
    }

    /// 锁钟与手机的偏差（秒）。界面要「偏差 N 秒」时用这个，不要各算一遍。
    static func clockDrift(_ mac: String) -> Value {
        let t = DB.readStatus(mac)?.lockTime ?? 0
        guard t > 0 else { return Value(text: "未知", tone: .neutral) }
        // 同上：协议秒 → 毫秒，再比时间差。
        let ms = ZKProtocol.protoSecondsToMs(t)
        let drift = Int(Date(timeIntervalSince1970: Double(ms) / 1000).timeIntervalSinceNow)
        let tone: Tone = abs(drift) > 60 ? .attention : .ok
        return Value(text: "\(abs(drift))", unit: "秒", tone: tone)
    }

    /// 安全模式 A/B/C。文案唯一来源是 `LockMode`（`LockStatusScreen.swift`）。
    static func lockMode(_ mac: String) -> Value {
        let s = DB.readStatus(mac)
        let text = LockMode.text(verifyMode: Int(s?.verifyMode ?? -1),
                                 broadcastMode: Int(s?.broadcastMode ?? 0))
        return Value(text: text, tone: .neutral)
    }
}
