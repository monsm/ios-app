// 包11 诊断·性能·运维 — 数据层 (无 UI; 全部本地)
// 编号对照 docs/ROADMAP-DRAFT.md「包11」:
//   体检 149/150/151/158/160/545/760 · 日志 152-154/281/283/542/543/740 ·
//   数据健康 451/452/750/546/547/758/215/223 · 性能层 216/220/221/224 ·
//   深度诊断 544/748/749/753/754/756/661/662/762/127/299
// 已删: 217 (SQLite 索引迁移 —— 本仓没有 SQLite 也没有索引层)、218 (写队列引擎空转一整块已删)、
// 277 (Watchdog 零调用副本已删, 自愈并入 275)。这三条以前混在上面那两行"收录"清单里,
// 于是台账把**已撤回的东西**当成实现证据记了一遍 (F 档那几条就是这么来的)。
// 底层说明: 本项目"数据库"是 UserDefaults(JSON 编码) 语义封装 (Store.swift),
// VACUUM/索引类创意按其等价落地: "整理"= 清残留空键 + 写队列冲刷; "完整性"= JSON 回环 + 台账计数核对。
import Foundation
import UIKit
import Dispatch          // 1170: DispatchSemaphore (把 async 的 notificationSettings() 拉回同步体检闭包)
import CoreBluetooth
import CryptoKit
import CoreImage
import CoreHaptics
import UserNotifications

// ---------- 时间戳辅助 (locale 无关, 台账可比对) ----------
enum DiagTime {
    static func hhmmss() -> String {
        let c = WeekCal.gregorian
        return String(format: "%02d:%02d:%02d", c.component(.hour, from: Date()), c.component(.minute, from: Date()), c.component(.second, from: Date()))
    }
    static func mmddHHmm() -> String {
        let c = WeekCal.gregorian
        return String(format: "%02d-%02d %02d:%02d", c.component(.month, from: Date()), c.component(.day, from: Date()), c.component(.hour, from: Date()), c.component(.minute, from: Date()))
    }
    static func mmddHHmmss() -> String {
        let c = WeekCal.gregorian
        return String(format: "%02d-%02d %02d:%02d:%02d", c.component(.month, from: Date()), c.component(.day, from: Date()), c.component(.hour, from: Date()), c.component(.minute, from: Date()), c.component(.second, from: Date()))
    }
    /// 纯文本备份 (753 二维码/复制用)
    static func full() -> String {
        let c = WeekCal.gregorian
        return String(format: "%d-%02d-%02d %02d:%02d", c.component(.year, from: Date()), c.component(.month, from: Date()), c.component(.day, from: Date()), c.component(.hour, from: Date()), c.component(.minute, from: Date()))
    }
}

// ---------- 156 本次会话操作序列 (⚠ 降级: 仅本会话, 跨会话采集 DEFERRED) ----------
struct DiagOp: Codable, Identifiable {
    var t: String            // MM-dd HH:mm:ss
    var label: String
    var id: String { t + label }
}
enum DiagOps {
    static let on = "kf_diag_ops_on"      // 156 开关 (诊断页)
    static let maxCount = 50
    // 计算属性声明不能带参数列表 → 语法非法
    static func isOn() -> Bool { DB.store.getBool(on, true) }
    static func record(_ label: String) {
        guard isOn() else { return }
        var list = DB.store.get([DiagOp].self, "kf_diag_ops") ?? []
        list.insert(DiagOp(t: DiagTime.mmddHHmmss(), label: label), at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        DB.store.setCodable("kf_diag_ops", list)
    }
    static func list() -> [DiagOp] { DB.store.get([DiagOp].self, "kf_diag_ops") ?? [] }
}


// ---------- 218 / 221 写入合并队列 —— 第九十二批整引擎已删 (原本就是个空转的壳) ----------
// 原 `enum WriteQueue` (入队 + 1s 合并 + flush) 的 `enqueue` 全库**零写入方**，
// 只有 `vacuum()` 里那句 `WriteQueue.flush()` 在冲一个永远为空的队列 ——
// 而头部注释写着"退后台冲刷; 221 scenePhase 接线"，等于对着一个不存在的机制做承诺。
// 为什么不接上：`DB.store.set` 是同步落盘、大量调用点紧接着就回读
// (例：CredentialStudio.swift:1113-1115 新增后立刻 `DB.getPwd` 做快照)，
// 把 set 改成 1s 合并会直接造出读后写陈旧；那不是一个"性能优化"，是拿正确性换没测过的收益。
// 结论：218/221 从 DONE 退回 MISS，要真做批量落盘得先给 Store 加"读穿透"，单独立项。



// ---------- 224 启动并行预热 (冷启动一次完成, 后续零成本) ----------

// ---------- 日志分级台账 (153/154/283/542/543/751 的解析与留档) ----------
struct DiagLogEntry: Codable, Identifiable {
    var date: String        // yyyy-MM-dd
    var time: String        // HH:mm:ss
    var level: String       // info / warn / error
    var msg: String
    var id: String { date + time + level + msg }
}
enum DiagLogs {
    static let retentionKey = "kf_diag_log_retention"  // 751: "" 全部 / "365" / "90"
    static var retentionDays: Int? {
        switch DB.store.getString(retentionKey) {
        case "365": return 365
        case "90": return 90
        default: return nil
        }
    }
    /// 本地"今天"的日 key —— **不能用 `.iso8601`**：那个格式走 UTC，
    /// UTC+8 的用户在每天 00:00–08:00 之间会拿到"昨天" (第一百五十八批，见 §10.30)。
    /// 口径只留一份：`StatsKit.dayKey(_:)` (固定 `yyyy-MM-dd` + 当前时区)。
    /// 一次性代价：这次之前落盘的诊断日志是按 UTC 日期记的，改完之后当天早上看"今天"会少几条
    /// (它们属于本机意义上的昨天) —— 保留期与列表都按字符串日期比较，不会丢数据，只是分组挪了一天。
    static func localDay(_ d: Date = Date()) -> String { StatsKit.dayKey(d) }

    static var entries: [DiagLogEntry] {
        DB.store.get([DiagLogEntry].self, "kf_diag_logs") ?? []
    }
    /// 按 751 保留策略过滤后的全量 (最新在末尾)
    static func all() -> [DiagLogEntry] {
        var list = entries
        if let days = retentionDays {
            let cs = localDay(WeekCal.shifted(Date(), days: -days))
            list = list.filter { $0.date >= cs }
        }
        return list
    }
    /// 751: 切档前先算"这一刀会删掉几条" — 界面拿它做二次确认的第一行。
    static func pruneCount(days: Int?) -> Int {
        guard let days else { return 0 }
        let cs = localDay(WeekCal.shifted(Date(), days: -days))
        return entries.filter { $0.date < cs }.count
    }
    /// 751: 确认后**立即应用**保留策略 (与 append 的裁剪同一口径), 返回实际删掉的条数。
    /// 原先只从下一次写入起生效 —— 切完看不到任何变化, "显示将删条数+二次确认"也就无从谈起。
    @discardableResult
    static func pruneNow() -> Int {
        let before = entries
        guard let days = retentionDays else { return 0 }
        let cs = localDay(WeekCal.shifted(Date(), days: -days))
        let kept = before.filter { $0.date >= cs }
        guard kept.count != before.count else { return 0 }
        DB.store.setCodable("kf_diag_logs", kept)
        return before.count - kept.count
    }
    static func today() -> [DiagLogEntry] {
        let d = localDay()
        return entries.filter { $0.date == d }
    }
    /// 由 LockService 分级日志调用: date/time 取自行内已有时序, 落持久台账
    static func append(_ level: String, _ msg: String, date: String, time: String) {
        var list = entries
        list.append(DiagLogEntry(date: date, time: time, level: level, msg: msg))
        if list.count > 500 { list = Array(list.suffix(500)) }
        if let days = retentionDays {
            let cs = localDay(WeekCal.shifted(Date(), days: -days))
            list = list.filter { $0.date >= cs }
        }
        DB.store.setCodable("kf_diag_logs", list)
    }
}

// ---------- 748 BLE 事件流水与连接成败遥测 (⚠ 降级: 环形留存, 图表随积累展示) ----------
struct BleEvent: Codable, Identifiable {
    var at: String          // MM-dd HH:mm
    var what: String        // 扫描/连接成功/连接失败/断开
    var ok: Bool
    var id: String { at + what + (ok ? "Y" : "N") }
}
struct ConnAttempt: Codable {
    var t: String          // MM-dd HH:mm:ss
    var mac: String
    var ok: Bool
    var reason: String
}
enum BleTelemetry {
    static func recordEvent(_ what: String, ok: Bool) {
        var list = DB.store.get([BleEvent].self, "kf_ble_events") ?? []
        list.insert(BleEvent(at: DiagTime.mmddHHmm(), what: what, ok: ok), at: 0)
        if list.count > 200 { list = Array(list.prefix(200)) }
        DB.store.setCodable("kf_ble_events", list)
    }
    static var events: [BleEvent] { DB.store.get([BleEvent].self, "kf_ble_events") ?? [] }
    static func recordAttempt(mac: String, ok: Bool, reason: String) {
        var list = DB.store.get([ConnAttempt].self, "kf_conn_attempts") ?? []
        list.insert(ConnAttempt(t: DiagTime.mmddHHmmss(), mac: mac, ok: ok, reason: reason), at: 0)
        if list.count > 300 { list = Array(list.prefix(300)) }
        DB.store.setCodable("kf_conn_attempts", list)
    }
    static var attempts: [ConnAttempt] { DB.store.get([ConnAttempt].self, "kf_conn_attempts") ?? [] }
    /// 近 30 天成功率 (⚠ 需积累, 冷启动为 nil → UI 显示"积累中")
    static func successRate() -> (total: Int, ok: Int, pct: Int)? {
        let a = attempts
        guard !a.isEmpty else { return nil }
        let total = a.count
        let ok = a.filter { $0.ok }.count
        return (total, ok, Int(Double(ok) * 100 / Double(total)))
    }
    /// 每日连接成功率（诊断界面已删，但 BleTelemetry 的统计仍产出，供未来复用）。
    struct DayRate: Identifiable {
        var id: String { day }
        let day: String; let n: Int; let ok: Int; let pct: Double
    }

    /// 失败分类（同上）。
    struct FailClass { let name: String; let n: Int; let hint: String }

    static func dailyRates() -> [DayRate] {
        var order: [String] = []
        var bucket: [String: (n: Int, ok: Int)] = [:]
        // attempts 是新在前 (insert at 0); 按日聚合后反转成时间正序画趋势
        for a in attempts {
            let day = String(a.t.prefix(5))          // MM-dd
            if bucket[day] == nil { order.append(day) }
            var v = bucket[day] ?? (0, 0)
            v.n += 1
            if a.ok { v.ok += 1 }
            bucket[day] = v
        }
        return order.reversed().map { d in
            let v = bucket[d] ?? (0, 0)
            return DayRate(day: d, n: v.n, ok: v.ok, pct: v.n > 0 ? Double(v.ok * 100) / Double(v.n) : 0)
        }
    }
    static func failClasses() -> [FailClass] {
        func classify(_ r: String) -> String {
            if r.contains("超时") { return "超时" }
            if r.contains("未发现") || r.contains("扫描") { return "未发现设备" }
            if r.contains("断开") { return "中途断开" }
            return "其他"
        }
        let fails = attempts.filter { !$0.ok }
        let groups = Dictionary(grouping: fails) { classify($0.reason) }
        let hints: [String: String] = [
            "超时": "把手机贴近门锁、避开拥挤商场等干扰源后再试",
            "未发现设备": "确认门锁已通电、手机蓝牙已开, 距离 1 米内再扫",
            "中途断开": "走动中掉线属正常, 靠近后再试; 频繁出现先查门锁电量",
            "其他": "换个时间段重试; 仍不行请跑一次一键体检"
        ]
        return groups.map { k, v in FailClass(name: k, n: v.count, hint: hints[k] ?? "") }
            .sorted { $0.n > $1.n }
    }
}

// ---------- 277 看门狗自恢复 —— 第九十一批删除这份零调用副本 ----------
// 原 `enum Watchdog` 34 行 (45s 心跳 + 失败重连 + kf_wd_heal 计数) 在全仓**零调用点**，
// 而它想防的"连接假死"已由两处现役机制覆盖: LinkSenseKit 的自动连接/预热/补发/重连/冷启动
// (:75/:122/:150/:237/:417) 与 275/131 会话巡检 (deadbeatCheck :309, 60s 一拍、挂起 >10 分钟且有待办才重协商)。
// 按本仓既有口径"重复实现删零调用那份，不为了消清单而接线"处理。
// 为什么不反过来接线: 并发写在这仓里**确实有串行化** (BLEService:277 acquireWriteSlot 的 FIFO 写槽,
// :93 writeBusy + 等待队列)，所以"接上心跳"技术上可行 —— 但那等于把一个用户没要求的 03 读周期性插到
// 用户正在拉的日志/记录前面，改的是**所有写操作的排队节奏**；在一个从未编译、从未真机验证的工程里，
// 为一项已被现役机制覆盖的能力去动写队列节奏，风险不对等。真要主动心跳，应该带着"谁可以插队"的口径一起做，
// 而不是把这个 enum 贴回来。 (本段第一版我写成"LockService 没有串行化原语"，是错的 ——
//  我只 grep 了 LockService 就下结论，串行化在下一层 BLEService 里；已按实读改写。)
/// 127 静默排查模式: 打开后暂停**自动连接/预热刷新/到场补发/自动重连/会话巡检/冷启动扫描**
/// 这 6 处自动动作 (消费点全在 LinkSenseKit :75/:122/:150/:237/:309/:417 —— 第九十一批逐条对过行号),
/// 便于干净复现问题。原文案还写着"暂停看门狗心跳"，那是指上面已删除的零调用副本。
enum DiagFlags {
    static var silent: Bool { DB.store.getBool("kf_silent_trouble") }
}






@MainActor

/// 1170 同步读取通知授权状态的载体。
/// 只写一次 (写完即 signal), 故 @unchecked Sendable 安全 —— 不做跨线程读写交错。
private final class NotifyAuthBox: @unchecked Sendable {
    var status: UNAuthorizationStatus = .notDetermined
}
