// 包3 设备档案与多锁总览 — 锁档案扩展存储 + 多锁统计 (纯本地只读现有表)
// 档案字段放独立键 kf_lockmeta_<mac>, 不动 Keychain (备份包 schema 与小程序互通不受影响):
//   106 备注 / 105 符号与色标 / 774 场所副标题 / 290 电池档案 / 258 首连验证 / 292 沉睡基准
// 统计全部读既有本地表 (kf_logcache_ / kf_ledger_ / kf_snap_ / kf_keychains / kf_members),
// 不新增采集, 不碰协议。思路对标 ROADMAP 包3: 776/778/779/784/787/773/768。
import Foundation
import SwiftUI

// ---------- 锁档案 (per-lock 元数据) ----------
struct LockMeta: Codable {
    var note: String = ""             // 106 备注 (备忘录标题正文的双字段案)
    var symbol: String = ""           // 105 符号 (SF Symbol 名; 空 = 默认 lock.fill)
    var colorKey: String = ""         // 105 色标 (LockArchive.swatch 键; 空 = 跟随主题)
    var place: String = ""            // 774 场所副标题 (玄关/车库)
    var batteryModel: String = ""     // 290 电池型号
    var batteryChangedAt: Double = 0  // 290 换电日期 (Unix 秒; 0 = 未记录)
    var verifiedAt: Double = 0        // 258 首连验证时刻 (Unix 秒; 0 = 未验证)
    var lastConnectedAt: Double = 0   // 292 沉睡判定基准 (最近一次连接成功)
}

enum LockArchive {
    static func meta(_ mac: String) -> LockMeta {
        DB.get(LockMeta.self, "kf_lockmeta_" + mac) ?? LockMeta()
    }
    static func save(_ mac: String, _ m: LockMeta) {
        DB.store.setCodable("kf_lockmeta_" + mac, m)
    }
    /// 292: 连接成功即刷新基准 (开锁成功也会走到这里)
    static func touchConnected(_ mac: String) {
        guard !mac.isEmpty else { return }
        var m = meta(mac)
        m.lastConnectedAt = Date().timeIntervalSince1970
        save(mac, m)
    }
    /// 258: 首次开锁成功 = 全链路 (BLE→会话→04→日志) 跑通, 打"链路已验证"标记
    static func markVerified(_ mac: String) {
        guard !mac.isEmpty else { return }
        var m = meta(mac)
        guard m.verifiedAt == 0 else { return }
        m.verifiedAt = Date().timeIntervalSince1970
        save(mac, m)
    }
    static func isVerified(_ mac: String) -> Bool { meta(mac).verifiedAt > 0 }
    /// 292: 30 天未连接 → 沉睡
    static func isSleeping(_ mac: String) -> Bool {
        let t = meta(mac).lastConnectedAt
        guard t > 0 else { return false }   // 从未连接过的不算沉睡 (新绑定/只导入)
        return Date().timeIntervalSince1970 - t > 30 * 86400
    }
    /// 启动默认锁 (271/103: 上滑固定 / 首位), 独立键不属于单锁档案
    static var defaultMac: String { DB.store.getString("kf_default_mac") }
    static func setDefaultMac(_ mac: String) { DB.store.set("kf_default_mac", mac) }

    // 105 色标: 只走 DS 语义令牌 (不引入自定义 hex, 保证对比度闸门覆盖)
    struct Swatch: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }
    static let swatches: [Swatch] = [
        Swatch(key: "", name: "主题色"),
        Swatch(key: "ok", name: "绿"),
        Swatch(key: "warn", name: "橙"),
        Swatch(key: "danger", name: "红"),
        Swatch(key: "neutral", name: "灰"),
    ]
    static func swatchColor(_ key: String) -> Color {
        switch key {
        case "ok": return DS.Palette.ok
        case "warn": return DS.Palette.warn
        case "danger": return DS.Palette.danger
        case "neutral": return DS.Palette.textSub
        default: return DS.Palette.accent   // 空 = 跟随品牌主题
        }
    }
    // 105 符号: 与场所语义呼应的一小组, 全部为系统基础符号
    struct SymbolOption: Identifiable {
        let name: String
        let label: String
        var id: String { name }
    }
    static let symbols: [SymbolOption] = [
        SymbolOption(name: "lock.fill", label: "默认"),
        SymbolOption(name: "house.fill", label: "家"),
        SymbolOption(name: "building.2.fill", label: "楼栋"),
        SymbolOption(name: "car.fill", label: "车库"),
        SymbolOption(name: "briefcase.fill", label: "办公"),
        SymbolOption(name: "key.fill", label: "钥匙"),
        SymbolOption(name: "shield.fill", label: "布防"),
        SymbolOption(name: "bell.fill", label: "侧门"),
    ]
    static func symbolName(_ m: LockMeta) -> String { m.symbol.isEmpty ? "lock.fill" : m.symbol }
    /// 锁的显示名 (与 AppState.displayName 同规则, 供统计层/列表复用)
    static func displayName(_ kc: Keychain) -> String {
        let raw = kc.pidName
        let model = (!raw.isEmpty && !raw.contains("pid=") && !raw.contains("未知")) ? raw : PidMap.productName(kc.pid)
        return kc.name.isEmpty ? model : kc.name
    }
    /// Hero 卡副标题 (774): 场所优先, 缺省回退型号
    static func subtitle(_ kc: Keychain) -> String {
        let m = meta(kc.mac)
        return m.place.isEmpty ? PidMap.productName(kc.pid) : m.place
    }
}

// ---------- 多锁统计 ----------
/// 每把锁一行的聚合读数: 30 天窗口从日志缓存统计, 容量/电量/固件从快照读。
struct LockUsage: Identifiable {
    var mac: String
    var name: String
    var opens30d: Int = 0        // 开门类 (type 1-5)
    var alarms30d: Int = 0       // 告警类 (6 电量低/7 撬锁/10 试错锁定/13 指纹告警/224 键盘锁定)
    var lastOpenAt: String = ""  // 最近一次开门 (日志缓存内)
    var power: Int = -1          // 快照电量
    var snapAt: Double = 0       // 快照采样时刻 (291 溯源)
    var fw: String = ""          // 固件 (钥匙串优先, 快照兜底)
    var pwdUsed: Int = -1, pwdCap: Int = -1    // 773: -1 = 未知
    var fpUsed: Int = -1, fpCap: Int = -1
    var sleeping: Bool = false   // 292
    var verified: Bool = false   // 258
    var pairedAt: String = ""    // 769 绑定时间
    var id: String { mac }
    /// 778 告警率 = 告警 / (告警+开门), 万一全告警也算 100%
    var alarmRate: Double { opens30d + alarms30d == 0 ? 0 : Double(alarms30d) / Double(opens30d + alarms30d) }
}

@MainActor
enum LockStats {
    static let openTypes: Set<Int> = [1, 2, 3, 4, 5]
    static let alarmTypes: Set<Int> = [6, 7, 10, 13, 224]
    static let windowDays = 30

    /// 快照采样时刻 (291): DB.readStatus 只回状态体, 这里取信封时间
    static func snapAt(_ mac: String) -> Double {
        DB.get(StatusSnapshot.self, "kf_snap_" + mac)?.at ?? 0
    }
    static func sampleTimeText(_ at: Double) -> String {
        guard at > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return "采样于 " + f.string(from: Date(timeIntervalSince1970: at / 1000))
    }

    /// 全锁聚合 (776/778/784/773/769/292/258 的共同数据源)
    static func usage() -> [LockUsage] {
        let cutoff = Date().timeIntervalSince1970 - Double(windowDays) * 86400
        return DB.keychains().map { kc -> LockUsage in
            var u = LockUsage(mac: kc.mac, name: LockArchive.displayName(kc))
            let logs = DB.readLogs(kc.mac)
            for l in logs {
                // 日志 lockTimeStr 是本地串; 时间过滤用日志写入缓存顺序不可靠,
                // 这里按锁端秒换算 Unix 秒对齐窗口 (ProtoTime 基准 2010-01-01)
                let unixSec = Double(ZKProtocol.protoSecondsToMs(Int64(l.lockTime))) / 1000
                if unixSec >= cutoff {
                    if openTypes.contains(l.type) { u.opens30d += 1 }
                    if alarmTypes.contains(l.type) { u.alarms30d += 1 }
                }
                if u.lastOpenAt.isEmpty, openTypes.contains(l.type), !l.lockTimeStr.isEmpty {
                    u.lastOpenAt = l.lockTimeStr
                }
            }
            let snap = DB.readStatus(kc.mac)
            u.power = snap?.powerLevel ?? -1
            u.snapAt = snapAt(kc.mac)
            u.fw = kc.fw.isEmpty ? (snap?.firmware ?? "") : kc.fw
            // 773: 优先锁侧真值 (容量-剩余=已用), 台账计数兜底
            let ledger = DB.ledger(kc.mac)
            if let cap = snap?.pwdCap, cap > 0 {
                u.pwdCap = cap
                u.pwdUsed = max(cap - (snap?.pwdStock ?? 0), 0)
            } else {
                u.pwdUsed = ledger.pwds.count
            }
            if let cap = snap?.fpCap, cap > 0 {
                u.fpCap = cap
                u.fpUsed = max(cap - (snap?.fpStock ?? 0), 0)
            } else {
                u.fpUsed = ledger.fps.count
            }
            u.sleeping = LockArchive.isSleeping(kc.mac)
            u.verified = LockArchive.isVerified(kc.mac)
            u.pairedAt = kc.pairedAt
            return u
        }
    }

    /// 779 成员×锁交叉矩阵: 行成员 / 列锁 / 格内次数 — 归属只走 Attribution 可证明链
    /// (R1 临时码窗口 / R2 唯一凭证), 推不出的格子留空, 绝不猜测。
    static func memberMatrix(_ usages: [LockUsage]) -> (members: [Member], counts: [[String: Int]]) {
        var members = DB.members()
        var counts: [[String: Int]] = []
        for u in usages {
            let pwds = DB.listPwds(u.mac), fps = DB.listFps(u.mac)
            let snap = DB.readStatus(u.mac)
            let status: (fpStock: Int, pwdStock: Int, lockTime: Int64)? = snap.map {
                ($0.fpStock, $0.pwdStock, $0.lockTime)
            }
            let logs = DB.readLogs(u.mac).filter { openTypes.contains($0.type) }
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: pwds, fps: fps, status: status)
            var perMember = [String: Int]()
            for r in rows {
                guard let who = r.who else { continue }
                perMember[who, default: 0] += 1
            }
            counts.append(perMember)
        }
        // 只保留至少有一次可证明归属的成员, 空矩阵不占版面
        let active = members.enumerated().filter { i, m in
            counts.contains { $0[m.id, default: 0] > 0 }
        }
        members = active.map { $0.element }
        return (members, counts)
    }

    /// 768 待维护锁清单: 低电 / 近 30 天有告警 / 密钥未绑定, 全部来自可读证据
    struct MaintenanceItem: Identifiable {
        let usage: LockUsage
        let reasons: [String]
        var id: String { usage.mac }
    }
    static func maintenance(_ usages: [LockUsage]) -> [MaintenanceItem] {
        var out: [MaintenanceItem] = []
        for u in usages {
            var reasons: [String] = []
            if (0...20).contains(u.power) { reasons.append("电量 \(u.power)%") }
            if u.alarms30d > 0 { reasons.append("近 30 天 \(u.alarms30d) 条告警") }
            if (DB.readStatus(u.mac)?.sKeyStatus ?? 0) != 0 { reasons.append("密钥未绑定") }
            if !reasons.isEmpty { out.append(MaintenanceItem(usage: u, reasons: reasons)) }
        }
        return out
    }

    /// 787 对比结论一句话 (财报解读式模板, 只引用上方同源数字)
    static func summary(_ usages: [LockUsage]) -> String {
        let active = usages.filter { !$0.sleeping }
        guard usages.count > 1 else {
            return "当前只有一把锁, 添加更多门锁后即可在这里对比活跃度与告警。"
        }
        guard let top = active.max(by: { $0.opens30d < $1.opens30d }), top.opens30d > 0 else {
            return "近 \(windowDays) 天各锁都还没有开门记录, 连接门锁读取日志后再来看对比。"
        }
        var parts: [String] = ["近 \(windowDays) 天「\(top.name)」开门 \(top.opens30d) 次, 是最活跃的一把"]
        let rest = active.filter { $0.mac != top.mac && $0.opens30d > 0 }
        if let second = rest.max(by: { $0.opens30d < $1.opens30d }), second.opens30d > 0 {
            let ratio = Double(top.opens30d) / Double(second.opens30d)
            parts.append(String(format: "约为「%@」的 %.1f 倍", second.name, ratio))
        }
        let alarmTop = active.max(by: { $0.alarmRate < $1.alarmRate })
        if let a = alarmTop, a.alarmRate >= 0.1, a.alarms30d > 0 {
            parts.append(String(format: "「%@」告警占比最高 (%.0f%%), 建议看看告警记录", a.name, a.alarmRate * 100))
        }
        if usages.contains(where: { $0.sleeping }) {
            parts.append("另有 \(usages.filter { $0.sleeping }.count) 把锁已 30 天未连接, 归入沉睡组")
        }
        return parts.joined(separator: "; ") + "。"
    }

    /// 784 固件对照: 返回 (该锁版本是否落后于本机最任一把, 本机最新版本)
    static func fwLag(_ usages: [LockUsage]) -> (latest: String, lagging: Set<String>) {
        let vers = usages.map { $0.fw }.filter { !$0.isEmpty }
        guard !vers.isEmpty else { return ("", []) }
        let latest = vers.max { fwCmp($0, $1) < 0 } ?? ""
        var lagging = Set<String>()
        for u in usages where !u.fw.isEmpty && fwCmp(u.fw, latest) < 0 { lagging.insert(u.mac) }
        return (latest, lagging)
    }
    static func fwCmp(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
