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
    // 2026-11-01：四个格式器原来**在同一行里多次调用 `Date()`** —— 跨秒/跨天那一刻，
    // 拼出来的时间戳可能是两个瞬间的拼接（例如「23:59:59」里第二次取已到 00:00:00）。
    // 时间戳乱掉会让"按时间对齐交互流水"这件事失效，正是排查时最忌讳的。
    // 口径：**一次取，多处用**。
    static func hhmmss() -> String {
        let c = WeekCal.gregorian
        let now = Date()
        return String(format: "%02d:%02d:%02d", c.component(.hour, from: now), c.component(.minute, from: now), c.component(.second, from: now))
    }
    static func mmddHHmm() -> String {
        let c = WeekCal.gregorian
        let now = Date()
        return String(format: "%02d-%02d %02d:%02d", c.component(.month, from: now), c.component(.day, from: now), c.component(.hour, from: now), c.component(.minute, from: now))
    }
    static func mmddHHmmss() -> String {
        let c = WeekCal.gregorian
        let now = Date()
        return String(format: "%02d-%02d %02d:%02d:%02d", c.component(.month, from: now), c.component(.day, from: now), c.component(.hour, from: now), c.component(.minute, from: now), c.component(.second, from: now))
    }
    /// 纯文本备份 (753 二维码/复制用)
    static func full() -> String {
        let c = WeekCal.gregorian
        let now = Date()
        return String(format: "%d-%02d-%02d %02d:%02d", c.component(.year, from: now), c.component(.month, from: now), c.component(.day, from: now), c.component(.hour, from: now), c.component(.minute, from: now))
    }
}

// 156「本次会话操作序列」`struct DiagOp` + `enum DiagOps`：**已删除**（2026-11-01）。
// 与 `quota()` / `DiagFlags.silent` / `struct Advice` 同一族：
// `DiagOps.record` 与 `DiagOps.list` 全仓**零调用**，开关 `kf_diag_ops_on` 也**零写入** ——
// 也就是这条"操作序列"从未记录过一条，也从没被任何界面读过。
// 真要做，需要先决定"记哪些操作、给谁看、怎么脱敏"，而不是先建一个存储壳。


// ---------- 218 / 221 写入合并队列 —— 第九十二批整引擎已删 (原本就是个空转的壳) ----------
// 原 `enum WriteQueue` (入队 + 1s 合并 + flush) 的 `enqueue` 全库**零写入方**，
// 只有 `vacuum()` 里那句 `WriteQueue.flush()` 在冲一个永远为空的队列 ——
// 而头部注释写着"退后台冲刷; 221 scenePhase 接线"，等于对着一个不存在的机制做承诺。
// 为什么不接上：`DB.store.set` 是同步落盘、大量调用点紧接着就回读
// (例：凭证工坊「新增后立刻 `DB.getPwd` 做快照」那条链 —— 原注释写 `CredentialStudio.swift:1113-1115`，
//  但该文件已于 2026-10-29 拆成 8 个文件，行号失效；行为本身仍在：新增凭证后立刻回读做快照)，
// 把 set 改成 1s 合并会直接造出读后写陈旧；那不是一个"性能优化"，是拿正确性换没测过的收益。
// 结论：218/221 从 DONE 退回 MISS，要真做批量落盘得先给 Store 加"读穿透"，单独立项。
//
// 2026-10-29 补充：**诊断日志这一块**后来确实做了防抖落盘（见下面 DiagLogs 的 entryCache /
// scheduleSave / flush），但它和 Store 的情况不同 —— 诊断日志是"只追加、读侧不要求读到最新一条"
// （all() / today() 都是展示用），所以 1 秒延迟没有正确性代价；而且它原来是**每条日志
// 读一次文件 + 写一次文件**，是这轮里 IO 最重的一处。Store 仍然保持同步写，理由见上。



// ---------- 224 启动并行预热 (冷启动一次完成, 后续零成本) ----------

// ---------- 日志分级台账 (153/154/283/542/543/751 的解析与留档) ----------
struct DiagLogEntry: Codable, Identifiable {
    var date: String        // yyyy-MM-dd
    var time: String        // HH:mm:ss
    var level: String       // info / warn / error
    var msg: String
    var id: String { date + time + level + msg }

    enum CodingKeys: String, CodingKey { case date, time, level, msg }
    init(date: String, time: String, level: String, msg: String) { self.date = date; self.time = time; self.level = level; self.msg = msg }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? "info"
        msg = try c.decodeIfPresent(String.self, forKey: .msg) ?? ""
    }
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

    // ---------- 内存缓存 + 防抖落盘 (2026-10-29 性能) ----------
    /// 原来每次 `append` 都是：`entries`（= `DiagLogStore.load()`：**同步读文件 + JSON 解码**）
    /// → append → `save`（JSON 编码 + 原子写文件）。而 `LockService.log()` **每写一行日志都会调它**，
    /// 一次开锁十几行 ⇒ 十几次文件读 + 十几次整文件写。
    ///
    /// 现在：内存里留一份，`append` 只改内存并标脏；落盘由一个 1 秒防抖任务合并成一次。
    /// 另外提供 `flush()`，由 scenePhase 进后台时调用，避免最后 1 秒的日志丢在内存里。
    private static let entryCache = Locked<[DiagLogEntry]?>(nil)
    private static let savePending = Locked(false)

    private static func loadIntoCache() -> [DiagLogEntry] {
        if let c = entryCache.withLock({ $0 }) { return c }
        let loaded = DiagLogStore.load()
        entryCache.withLock { $0 = loaded }
        return loaded
    }

    static var entries: [DiagLogEntry] { loadIntoCache() }

    /// 按 751 保留策略过滤后的全量 (最新在末尾)
    static func all() -> [DiagLogEntry] {
        var list = loadIntoCache()
        if let days = retentionDays {
            let cs = localDay(WeekCal.shifted(Date(), days: -days))
            list = list.filter { $0.date >= cs }
        }
        return list
    }
    /// 751: 确认后**立即应用**保留策略 (与 append 的裁剪同一口径), 返回实际删掉的条数。
    static func today() -> [DiagLogEntry] {
        let d = localDay()
        return loadIntoCache().filter { $0.date == d }
    }
    /// 由 LockService 分级日志调用: date/time 取自行内已有时序, 落持久台账
    /// 落盘条数上限（2026-11-02 用户要求「日志解锁最大行数」）。
    /// 原来写死 500：一次开锁十几行、复现几轮就滚掉现场，排障时最需要的第一帧反而先丢。
    /// 现在由用户在「交互流水」页选档（500 / 2000 / 5000 / 不限），存在 `kf_diag_max`。
    static let maxKey = "kf_diag_max"
    /// 档位：0 = 不限（仍受保留天数约束）。
    static var maxLines: Int {
        let v = DB.store.getInt(maxKey)
        return v > 0 ? v : (DB.store.has(maxKey) ? 0 : 500)   // 未设过 = 默认 500
    }
    static let maxChoices: [(label: String, value: Int)] = [
        ("500 行", 500), ("2000 行", 2000), ("5000 行", 5000), ("不限", 0)
    ]

    /// 清空全部交互流水（内存 + 落盘）。返回清掉的条数。
    /// 用户要求：出问题时先清空再复现，日志里就只剩这一次的现场 —— 比在几百行里翻要快得多。
    @discardableResult
    static func clear() -> Int {
        let n = loadIntoCache().count
        entryCache.withLock { $0 = [] }
        DiagLogStore.save([])
        savePending.withLock { $0 = false }   // 已经写过了，别让防抖任务再写一次空表
        return n
    }

    static func append(_ level: String, _ msg: String, date: String, time: String) {
        var list = loadIntoCache()
        list.append(DiagLogEntry(date: date, time: time, level: level, msg: msg))
        let cap = maxLines
        if cap > 0, list.count > cap { list = Array(list.suffix(cap)) }
        if let days = retentionDays {
            let cs = localDay(WeekCal.shifted(Date(), days: -days))
            list = list.filter { $0.date >= cs }
        }
        entryCache.withLock { $0 = list }
        scheduleSave()
    }
    /// 立刻把内存里的日志写盘（进后台 / 退出前调用）。
    static func flush() {
        // 只有真有未落盘的改动才写 —— 否则每次切前台/后台都白写一次文件。
        let pending = savePending.withLock { v -> Bool in
            let had = v
            v = false
            return had
        }
        guard pending else { return }
        let snapshot = entryCache.withLock { $0 } ?? []
        DiagLogStore.save(snapshot)
    }
    private static func scheduleSave() {
        let already = savePending.withLock { v -> Bool in
            if v { return true }
            v = true
            return false
        }
        if already { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            flush()
        }
    }
}

// ---------- 748 BLE 事件流水与连接成败遥测 (⚠ 降级: 环形留存, 图表随积累展示) ----------
struct BleEvent: Codable, Identifiable {
    var at: String          // MM-dd HH:mm
    var what: String        // 扫描/连接成功/连接失败/断开
    var ok: Bool
    var id: String { at + what + (ok ? "Y" : "N") }

    enum CodingKeys: String, CodingKey { case at, what, ok }
    init(at: String, what: String, ok: Bool) { self.at = at; self.what = what; self.ok = ok }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
        what = try c.decodeIfPresent(String.self, forKey: .what) ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
    }
}
struct ConnAttempt: Codable {
    var t: String          // MM-dd HH:mm:ss
    var mac: String
    var ok: Bool
    var reason: String

    enum CodingKeys: String, CodingKey { case t, mac, ok, reason }
    init(t: String, mac: String, ok: Bool, reason: String) { self.t = t; self.mac = mac; self.ok = ok; self.reason = reason }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        mac = try c.decodeIfPresent(String.self, forKey: .mac) ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}
enum BleTelemetry {
    // 2026-10-29 性能：与 DiagLogs 同一套处理 ——
    // 原来每次 recordEvent / recordAttempt 都是「读整份数组 → 插入 → 整份编码 → UserDefaults 落盘」。
    // 重连失败阶梯每十几秒就会记一条，等于持续在做全量 200/300 条的编解码。
    // 现在：内存缓存 + 标脏 + 1 秒防抖合并，真正落盘一秒钟最多一次。
    private static let eventCache = Locked<[BleEvent]?>(nil)
    private static let attemptCache = Locked<[ConnAttempt]?>(nil)
    private static let eventDirty = Locked(false)
    private static let attemptDirty = Locked(false)

    // SEC-13：遥测改落 Caches 文件（排除备份），不再进 UserDefaults。
    // 理由：UserDefaults 无法单键排除备份 —— 整包随 iCloud/iTunes 出机，
    // 而台账变更记录里可能带锁名/成员名/备注（即便已去掉明文，仍是可关联信息）。
    private static let eventsFile = "kf_ble_events.json"
    private static let attemptsFile = "kf_conn_attempts.json"
    private static let legacyEventsKey = "kf_ble_events"
    private static let legacyAttemptsKey = "kf_conn_attempts"

    static func recordEvent(_ what: String, ok: Bool) {
        var list = eventCache.withLock { $0 } ?? loadEvents()
        list.insert(BleEvent(at: DiagTime.mmddHHmm(), what: what, ok: ok), at: 0)
        if list.count > 200 { list = Array(list.prefix(200)) }
        eventCache.withLock { $0 = list }
        scheduleFlush(eventDirty)
    }
    /// 2026-11-01 修复：原来写成 `eventCache.withLock { $0 } ?? loadEvents()` ——
    /// 缓存为 nil 时**每次都重新解析 JSON 文件**，且不回填缓存（性能与一致性两个问题：
    /// `recordEvent` 走的是"读缓存→改→写回"，而读路径永远看到磁盘，两者会短暂不一致）。
    /// 现在首次读回填，后续都走内存。
    static var events: [BleEvent] {
        if let c = eventCache.withLock({ $0 }) { return c }
        let loaded = loadEvents()
        eventCache.withLock { $0 = loaded }
        return loaded
    }
    static func recordAttempt(mac: String, ok: Bool, reason: String) {
        var list = attemptCache.withLock { $0 } ?? loadAttempts()
        list.insert(ConnAttempt(t: DiagTime.mmddHHmmss(), mac: mac, ok: ok, reason: reason), at: 0)
        if list.count > 300 { list = Array(list.prefix(300)) }
        attemptCache.withLock { $0 = list }
        scheduleFlush(attemptDirty)
    }
    /// 同 `events`：首次读回填缓存，避免每次重新解析 JSON 且与写路径不一致。
    static var attempts: [ConnAttempt] {
        if let c = attemptCache.withLock({ $0 }) { return c }
        let loaded = loadAttempts()
        attemptCache.withLock { $0 = loaded }
        return loaded
    }

    /// 首次读：优先文件；文件没有则把旧 UserDefaults 键搬过来并删旧键（一次性迁移）。
    private static func loadEvents() -> [BleEvent] {
        let list = DiagLogStore.readJSON([BleEvent].self, name: eventsFile)
        if list.isEmpty, let old = DB.store.get([BleEvent].self, legacyEventsKey), !old.isEmpty {
            DiagLogStore.writeJSON(old, name: eventsFile)
            DB.store.remove(legacyEventsKey)
            return old
        }
        return list
    }
    private static func loadAttempts() -> [ConnAttempt] {
        let list = DiagLogStore.readJSON([ConnAttempt].self, name: attemptsFile)
        if list.isEmpty, let old = DB.store.get([ConnAttempt].self, legacyAttemptsKey), !old.isEmpty {
            DiagLogStore.writeJSON(old, name: attemptsFile)
            DB.store.remove(legacyAttemptsKey)
            return old
        }
        return list
    }

    /// 立刻把内存里的遥测写盘（进后台 / 退出前调用）。
    static func flush() {
        if eventDirty.withLock({ d -> Bool in let h = d; d = false; return h }) {
            DiagLogStore.writeJSON(eventCache.withLock { $0 } ?? [], name: eventsFile)
        }
        if attemptDirty.withLock({ d -> Bool in let h = d; d = false; return h }) {
            DiagLogStore.writeJSON(attemptCache.withLock { $0 } ?? [], name: attemptsFile)
        }
    }
    private static func scheduleFlush(_ flag: Locked<Bool>) {
        let already = flag.withLock { d -> Bool in
            if d { return true }
            d = true
            return false
        }
        if already { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            flush()
        }
    }
    /// 每日连接成功率（诊断界面已删，但 BleTelemetry 的统计仍产出，供未来复用）。
    struct DayRate: Identifiable {
        var id: String { day }
        let day: String; let n: Int; let ok: Int; let pct: Double
    }

    /// 失败分类（同上）。
    struct FailClass { let name: String; let n: Int; let hint: String }

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
// 127「静默排查模式」`DiagFlags.silent`：**已删除**（2026-11-01）。
// 它的注释写着"消费点全在 LinkSenseKit :75/:122/:150/:237/:309/:417，逐条对过行号"，
// 但 `LinkSense.swift` 里 `kf_silent_trouble` / `DiagFlags` 的出现次数是 **0**，
// 且 `DiagFlags` 全仓零引用 —— 一个开关配一份"已逐条核对"的注释，实际什么都没停。
// 这比没有这个开关更糟：出问题时按注释去"打开静默模式复现"，什么都不会发生，
// 还会让人以为复现环境已经干净。真要静默排查，应当直接断连/关后台刷新，而不是一个空开关。







/// 1170 同步读取通知授权状态的载体。
/// 只写一次 (写完即 signal), 故 @unchecked Sendable 安全 —— 不做跨线程读写交错。
// 2026-10-28：这里原有一个悬空的 `@MainActor` 修饰 NotifyAuthBox —— 而它是 `@unchecked Sendable`
// 的跨线程载体（用 DispatchSemaphore 把 async 回调拉回同步），status 必须能从非隔离回调里写。
// 带 @MainActor 会让 `getNotificationSettings` 的闭包编译失败：
// 「main actor-isolated property 'status' can not be referenced from a nonisolated context」。
private final class NotifyAuthBox: @unchecked Sendable {
    var status: UNAuthorizationStatus = .notDetermined
}

/// 2026-10-28 补：`NotifyAuthBox` 之前是**孤儿** —— 类与注释都写好了
/// （「1170 同步读取通知授权状态」），但没有任何读取入口、也没有任何调用方。
/// 后果：用户在系统弹窗里点了「不允许」之后，App 内**看不到任何提示** ——
/// 凭证到期提醒不会送达，用户不知道为什么，只会觉得「这 App 的提醒是坏的」。
/// 而 `QuickActionDelegate` 里新加的 `requestAuthorization` 只会写 os 日志，用户看不到。
enum NotifyAuth {
    /// 同步读（把 async 的 `getNotificationSettings` 拉回同步）—— 用注释里预留的那只盒子。
    /// 超时 2 秒兜底：读不到就报「未确定」而不是卡住设置页。
    static var status: UNAuthorizationStatus {
        let box = NotifyAuthBox()
        let sem = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().getNotificationSettings { s in
            box.status = s.authorizationStatus
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 2)
        return box.status
    }

    /// 给用户看的一句话。
    static var label: String {
        switch status {
        case .authorized: return "已开启"
        case .denied: return "已拒绝"
        case .notDetermined: return "未询问"
        case .provisional: return "临时授权"
        case .ephemeral: return "会话授权"
        @unknown default: return "未知"
        }
    }

    /// 提醒送不到（被拒或还没问过）。
    static var isOff: Bool { status == .denied || status == .notDetermined }

    /// 给定状态的一句话（供 UI 读一次后缓存，避免每次 body 都走同步阻塞）。
    static func labelFor(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "已开启"
        case .denied: return "已拒绝"
        case .notDetermined: return "未询问"
        case .provisional: return "临时授权"
        case .ephemeral: return "会话授权"
        @unknown default: return "未知"
        }
    }

    /// 提醒送不到（给定状态版）。
    static func isOffFor(_ s: UNAuthorizationStatus) -> Bool {
        s == .denied || s == .notDetermined
    }
}

// MARK: - 双侧快照（锁内数据 + App 内数据）

/// 2026-11-02（用户要求）：「日志只给了 App 侧，看不出锁端到底认什么」。
///
/// 排查 rc=2 这类「凭证被拒」时，必须同时看到两边的数：
///   · **锁端**：cmd03 快照里的 PIN 容量/存量/已绑定、剩余可验证次数、剩余可开门次数、安全模式、锁钟；
///   · **本机**：本机 PIN 池条数、存的那枚 ekey 里嵌的 PIN、当前选定的 PIN、skey 指纹（不打印明文）、MAC 序裁定。
///
/// 两边一比，「锁端已用 64 / 本机池 64」这种**数量对不上**或「锁端剩余可验证次数 = 0」立刻可见 ——
/// 而只看流水时，这两条要人工从 cmd03 hex 里解 KLV 才能得到。
///
/// **安全边界**：这个快照**不含任何密钥明文** —— skey / ekey / PIN 一律只打指纹（前 4 + 后 4 位）
/// 或长度，因为它是拿来贴到聊天里求助的。要看完整帧请用「复制原始流水」那条路（90 秒剪贴板过期）。
enum DiagSnapshot {

    /// 单行 `键 = 值` 的集合，按段分组。
    ///
    /// `@MainActor`：`MobileKeyService.list` 是主线程隔离的，而本快照在 View 里同步生成。
    @MainActor
    static func build(mac: String) -> String {
        var out: [String] = []
        let kc = DB.keychain(mac)
        let st = DB.readStatus(mac)
        let stamp = DF.iso().string(from: Date())

        out.append("=== 双侧快照 \(stamp) ===")
        out.append("说明：本快照不含密钥明文，skey/ekey/PIN 只打指纹。可安全贴出求助。")
        out.append("")

        // ---------- 锁端 ----------
        // 这里读的是 `StatusSnapshotData`（cmd03 快照的子集），
        // 字段名与完整的 `LockStatus` 不同：pinCap / pwdCap / fpCap（不是 pinInfoCapacity）。
        out.append("【锁端】")
        if let st {
            out.append("  固件 = \(st.firmware.isEmpty ? "未上报" : st.firmware)")
            out.append("  电量 = \(st.powerLevel >= 0 ? "\(st.powerLevel)%" : "未读到")")
            out.append("  锁内时间 = \(st.lockTime > 0 ? TimeFormat.clock(ZKProtocol.protoSecondsToMs(st.lockTime)) : "未读到")")
            out.append("  安全模式 = verify=\(st.verifyMode) broadcast=\(st.broadcastMode) tempPwd=\(st.tempPwdMode)")
            out.append("  PIN 容量 = \(st.pinCap ?? -1)  剩余空位 = \(st.pinStock)  已绑定 = \(st.pinInfoBinding ?? -1)")
            out.append("  → **锁端已用 PIN = \(max((st.pinCap ?? 0) - st.pinStock, 0))**")
            out.append("  密码容量 = \(st.pwdCap ?? -1)  剩余空位 = \(st.pwdStock)")
            out.append("  指纹容量 = \(st.fpCap ?? -1)  剩余空位 = \(st.fpStock)")
            out.append("  sKeyStatus = \(st.sKeyStatus)  zotpPeriod = \(st.zotpPeriod.map { "\($0) 分钟" } ?? "未上报")")
            let at = DB.statusTime(mac)
            if at > 0 {
                out.append("  快照时刻 = \(DF.iso().string(from: Date(timeIntervalSince1970: at / 1000)))")
            }
        } else {
            out.append("  （还没有 cmd03 快照 —— 先连一次锁再导）")
        }
        out.append("")

        // ---------- 本机 ----------
        out.append("【本机】")
        if let kc {
            out.append("  MAC = \(DB.normalizeMac(kc.mac))  名称 = \(LockArchive.displayName(kc))")
            out.append("  skey = 长度 \(kc.skey.count) hex，指纹 \(fingerprint(kc.skey))")
            out.append("  ekey = 长度 \(kc.ekey.count) hex，指纹 \(fingerprint(kc.ekey))")
            out.append("  本机 PIN 池 = \(kc.pins.filter { !$0.isEmpty }.count) 枚（声明 \(kc.pins.count)）")
            out.append("  PIN 池指纹 = \(fingerprint(kc.pins.joined()))")
            // 2026-11-03（信息架构 QA · 安全）：这里原来是**明文 PIN**（`ekeyPin` 返回 "12345678（本机池第 3 枚）"，
            // `chosenPin` 返回裸值），而本函数开头第 436 行明确承诺
            // 「这个快照**不含任何密钥明文** … PIN 一律只打指纹 … 因为它是拿来贴到聊天里求助的」。
            // 用户会把这段文字当"安全内容"贴进工单/群聊 —— 实际等于把开锁 PIN 公开。
            // 现在只打指纹 + 位置提示：既能比对"是不是同一枚"，又不泄露可用值。
            out.append("  **存的那枚 ekey 里嵌的 PIN = \(ekeyPinMasked(kc))**")
            out.append("  当前选定的 PIN = \(chosenPinMasked(mac))")
            out.append("  MAC 字节序裁定 = \(ZKProtocol.macOrder(kc.mac).rawValue)")
            out.append("  trackid = \(kc.trackid)  fw = \(kc.fw)  pairedAt = \(kc.pairedAt)")
        } else {
            out.append("  （没有这把锁的钥匙串）")
        }
        let mkeys = MobileKeyService.list(mac)
        out.append("  手机钥匙 = \(mkeys.count) 把")
        let ledger = DB.ledger(mac)
        out.append("  台账：密码 \(ledger.pwds.count) 条 / 指纹 \(ledger.fps.count) 枚")
        out.append("")

        // ---------- 结论提示 ----------
        out.append("【自动比对】")
        if let st {
            let lockUsed = max((st.pinCap ?? 0) - st.pinStock, 0)
            let localPool = kc?.pins.filter { !$0.isEmpty }.count ?? 0
            out.append("  锁端已用 PIN \(lockUsed) vs 本机池 \(localPool)")
            if lockUsed != localPool {
                out.append("  → **数量不一致**：现签凭证必被拒。锁端存量与本机池不是同一批。")
            } else {
                // 2026-11-02 真机教训：数量相等**不能**推出「池子相同」。
                // 两边都满池（64/64）时数量恒等，而 PIN 值可能完全不同 —— 真机就是这种情况：
                // 64 vs 64 显示"一致"，但 cmd04 仍回 rc=2（解密成功、PIN 未命中）。
                out.append("  → 数量一致，但**数量相等不能证明是同一批 PIN**。")
                out.append("    判据：若开锁回 rc=2 且 skey 指纹与备份相同，则锁端 PIN 池已被换过（另一台 App 重新同步过）。")
            }
        }
        if let kc, !kc.skey.isEmpty {
            out.append("  提醒：rc=1/11 = skey 不匹配（解密失败）；rc=2 = **解密成功但 PIN 不在锁端表里**。")
            out.append("        这两者指向完全不同的处置（重新配网 vs 从当前真源重导）。")
        }
        return out.joined(separator: "\n")
    }

    /// 密钥/口令的**指纹**：前 4 + 后 4 位 + 总长。用于在两条记录之间比对「是不是同一份」，
    /// 而不泄露任何可用内容。空串返回 `(空)`。
    static func fingerprint(_ hex: String) -> String {
        guard !hex.isEmpty else { return "(空)" }
        if hex.count <= 8 { return "\(hex.prefix(2))…\(hex.suffix(2))/\(hex.count)" }
        return "\(hex.prefix(4))…\(hex.suffix(4))/\(hex.count)"
    }

    /// 解出存的 ekey 里嵌的 PIN 原文（8 hex）。解不开（skey 不配套 / ekey 为空）返回 nil。
    /// 2026-11-03 从 `ekeyPin` 拆出：开锁自愈逻辑（LockServiceOps）需要**裸 PIN 值**做比对，
    /// 不能依赖带修饰文案的展示版。
    static func rawEmbeddedPin(_ kc: Keychain) -> String? {
        guard !kc.ekey.isEmpty, !kc.skey.isEmpty else { return nil }
        // ekey = AES(skey)(88 00 MAC 4B + track 4B + vf 4B + vt 4B + cmd 1B + pin 4B + 0000)
        // 明文 PIN 在字节偏移 21..24（hex 字符 42..49）。
        guard let plain = try? AESKit.decryptHex(kc.ekey, keyHex: kc.skey), plain.count >= 50 else { return nil }
        let pin = String(plain.dropFirst(42).prefix(8))
        return pin.isEmpty ? nil : pin
    }

    /// 从**任意一枚 ekey**（不一定是钥匙串里存的那枚）解出嵌的 PIN。
    /// 自愈逻辑用它判断"刚发出去的这帧用的是哪枚 PIN"。
    static func rawEmbeddedPin(fromEkey ekeyHex: String, skey: String) -> String? {
        guard !ekeyHex.isEmpty, !skey.isEmpty else { return nil }
        guard let plain = try? AESKit.decryptHex(ekeyHex, keyHex: skey), plain.count >= 50 else { return nil }
        let pin = String(plain.dropFirst(42).prefix(8))
        return pin.isEmpty ? nil : pin
    }

    /// 从存的那枚 ekey 里解出它嵌的 PIN（只用于比对，不打印 skey）。
    static func ekeyPin(_ kc: Keychain) -> String {
        guard let pin = rawEmbeddedPin(kc) else { return "(解不开：skey 与 ekey 不配套)" }
        let idx = kc.pins.firstIndex(of: pin).map { "（本机池第 \($0 + 1) 枚）" } ?? "（**不在本机池里**）"
        return "\(pin)\(idx)"
    }

    /// **可安全展示**的「ekey 里嵌的 PIN」：只给指纹与池内位置，不给明文。
    /// 比对用途（"两边的 PIN 是不是同一枚"）完全够用。
    /// 2026-11-04（错误归因 · 截图复核发现）：`rawEmbeddedPin` 返回 nil 有**三种**原因 ——
    /// ekey 为空（没配网完成）、skey 为空（同左）、解密失败（真·不配套）。原来一律说
    /// 「skey 与 ekey 不配套」，而 God 模式页上方两行明明写着「(空)」—— 同屏自相矛盾，
    /// 用户会以为是密钥损坏去修池。
    static func ekeyPinMasked(_ kc: Keychain) -> String {
        if kc.ekey.isEmpty || kc.skey.isEmpty { return "(空 —— 这把锁还没有配网密钥)" }
        guard let pin = rawEmbeddedPin(kc) else { return "(解不开：skey 与 ekey 不配套)" }
        let idx = kc.pins.firstIndex(of: pin).map { "（本机池第 \($0 + 1) 枚）" } ?? "（**不在本机池里**）"
        return fingerprint(pin) + idx
    }

    /// **可安全展示**的「当前选定 PIN」：只给指纹，不给明文。
    static func chosenPinMasked(_ mac: String) -> String {
        guard let v = chosenPin(mac) else { return "（未选，回落配网 ekey）" }
        return fingerprint(v)
    }

    /// 当前选定的 PIN（`kf_chosen_pin_<mac>`）。
    static func chosenPin(_ mac: String) -> String? {
        let v = DB.store.getString("kf_chosen_pin_" + DB.normalizeMac(mac))
        return v.isEmpty ? nil : v
    }
}
