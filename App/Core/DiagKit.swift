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

// ---------- 215 启动预算: 冷启动各阶段打点 (本地自统计, 预算 800ms) ----------
enum StartupTrace {
    static let t0 = CFAbsoluteTimeGetCurrent()
    private static let marksLock = Locked([String: Double]())
    static func mark(_ p: String) { marksLock.withLock { $0[p] = CFAbsoluteTimeGetCurrent() - t0 } }
    /// 各阶段耗时 (ms)
    static func ms(_ p: String) -> Double? { marksLock.withLock { $0[p] }.map { ($0 * 1000).rounded() } }
    static var totalMs: Double { (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
    static var overBudget: Bool { totalMs > 800 }
}

// ---------- 218 / 221 写入合并队列 —— 第九十二批整引擎已删 (原本就是个空转的壳) ----------
// 原 `enum WriteQueue` (入队 + 1s 合并 + flush) 的 `enqueue` 全库**零写入方**，
// 只有 `vacuum()` 里那句 `WriteQueue.flush()` 在冲一个永远为空的队列 ——
// 而头部注释写着"退后台冲刷; 221 scenePhase 接线"，等于对着一个不存在的机制做承诺。
// 为什么不接上：`DB.store.set` 是同步落盘、大量调用点紧接着就回读
// (例：CredentialStudio.swift:1113-1115 新增后立刻 `DB.getPwd` 做快照)，
// 把 set 改成 1s 合并会直接造出读后写陈旧；那不是一个"性能优化"，是拿正确性换没测过的收益。
// 结论：218/221 从 DONE 退回 MISS，要真做批量落盘得先给 Store 加"读穿透"，单独立项。

// ---------- 220 热点缓存: 时间线首屏加速 (217 索引迁移未做, 它想解决的"热数据前置"由本缓存对应) ----------
// 2026-10-13 接线: 读取口 `recent` 此前全库零调用 (一份没人读的缓存常驻内存), 现在时间线首屏走它。
// 旧注释留的问题"要接得先定失效策略 (TTL? 拉完日志? 切锁?)"就定在**唯一写入口**:
// Store.writeLogs / replaceLogs 写完即作废 —— 缓存只可能比库旧一个写入动作, 而写入方自己会作废它,
// 所以不存在"比直连 defaults 更容易出陈旧"的窗口。
// 缓存整份解码结果而不是只留 50 条: 原句要的"最近 50 条加速首屏"目的已达到; 而只留 50 条时,
// 时间线的其余行仍要再读一次盘, 等于把一次解码变成两次。
enum HotCache {
    /// 读写可能跨线程 (写入口 Store.writeLogs 在 BLE 回调线程上), 所以自己带锁 ——
    /// 旧注释把线程安全推给调用方 ("刻意留主线程"), 加锁后失效点才能落在写入口上。
    // 原生互斥: Locked (NSLock + 值在临界区内) —— withLock 保证 unlock 一定执行,
    // 比手写 lock()/defer unlock 少一类"提前 return 忘了解锁"的错误。
    private static let lock = Locked(HotState())
    private struct HotState: Sendable {
        var store: [String: [CachedLog]] = [:]
        var currentMac: String = ""
    }
    static var currentMac: String { lock.withLock { $0.currentMac } }
    static func load(mac: String) {
        lock.withLock { h in
            h.currentMac = mac
            h.store[mac] = DB.readLogs(mac)
        }
    }
    /// 日志写入后作废 (惰性: 下一次 recent 重读) —— 比"写完立刻重读一遍"少一次解码。
    static func invalidate(_ mac: String) { lock.withLock { $0.store[mac] = nil } }
    static func recent(_ mac: String) -> [CachedLog] {
        lock.withLock { h -> [CachedLog] in
            if mac == h.currentMac, let v = h.store[mac] { return v }
            let v = DB.readLogs(mac)
            h.store[mac] = v
            return v
        }
    }
}

// ---------- 285 扫描时长自查: 按本地日累计 BLE 扫描秒数 (原句"诊断页统计每日扫描时长趋势并给省电建议") ----------
/// 写入点只有两个, 都在 LinkSenseKit: 冷启动扫描 (134) 与按锁扫描 (63/71)。
/// 建议句基于**真实累计**给, 不是档位科普 (285 的缺就是"只有档位说明, 没有基于用量的推算")。
enum ScanStats {
    private static let key = "kf_scan_secs"
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func record(seconds: Double) {
        guard seconds > 0 else { return }
        var m = DB.store.get([String: Double].self, key) ?? [:]
        m[fmt.string(from: Date()), default: 0] += seconds
        // 只留 30 天, 免得这个键无限长大
        if m.count > 30 { for k in m.keys.sorted().dropLast(30) { m.removeValue(forKey: k) } }
        DB.store.setCodable(key, m)
    }
    /// 近 N 天的 (日, 秒), 新在前
    static func recent(days: Int = 7) -> [(day: String, secs: Double)] {
        let m = DB.store.get([String: Double].self, key) ?? [:]
        return m.keys.sorted(by: >).prefix(days).map { ($0, m[$0] ?? 0) }
    }
    /// 省电建议: 按近 7 天日均扫描秒数说一句话 (含当前档位的单次窗口, 都是真实读数)
    static func advice() -> String {
        let r = recent(days: 7)
        guard !r.isEmpty else { return "还没有扫描时长记录 — 冷启动与连接/开锁时才会扫, 攒几天再看趋势。" }
        let avg = r.reduce(0.0) { $0 + $1.secs } / Double(r.count)
        let win = BLEService.ScanProfile.current.timeoutMs
        if avg < 5 { return "近 \(r.count) 天日均扫描 \(Int(avg)) 秒 — 已经很省 (当前档位单次窗口 \(win)ms)。" }
        if avg < 30 { return "近 \(r.count) 天日均扫描 \(Int(avg)) 秒 — 正常范围 (单次窗口 \(win)ms); 想更省可换「省电」档。" }   // 123 天日均扫描
        return "近 \(r.count) 天日均扫描 \(Int(avg)) 秒 — 偏多; 不需要即连的话换「省电」档, 或关掉预握手。"   // 97/123 天日均扫描
    }
}

// ---------- 224 启动并行预热 (冷启动一次完成, 后续零成本) ----------
@MainActor
enum Prewarm {
    static var done = false
    static func run(mac: String) {
        guard !done else { return }
        done = true
        // 224: 三项互不依赖的读取改为**并发** (原先串行顺序占启动线程), 读点只走 UserDefaults;
        // 缓存收口 (HotCache) 仍回主线程 —— 那份字典缓存不是线程安全的, 不能跟着并行。
        // (原句里的 "SQLite 连接" 在本移植版没有对应物 —— 本仓零 SQLite, 按 UserDefaults 口径如实。)
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.concurrentPerform(iterations: 3) { i in
                switch i {
                case 0: _ = DB.keychains()
                case 1: _ = DB.hasPasscode()
                default: _ = DB.store.getString("kf_theme")
                }
            }
            DispatchQueue.main.async { HotCache.load(mac: mac) }
        }
    }
}

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
    /// 立即应用保留策略并落盘，返回实际删掉的条数。
    ///
    /// 751 的原始意图：用户切了保留期，就该**当场**看到条数变少。
    /// 原先只有 append() 会裁剪，切换后要等下一次写日志才生效 —— 切完看不到任何变化。
    /// （这段注释一度错位挂在 today() 上，那个"立即应用"的函数已经不存在了。）
    @discardableResult
    static func applyRetentionNow() -> Int {
        guard let days = retentionDays else { return 0 }
        let cs = localDay(WeekCal.shifted(Date(), days: -days))
        var list = entries
        let before = list.count
        list = list.filter { $0.date >= cs }
        let removed = before - list.count
        if removed > 0 { DB.store.setCodable("kf_diag_logs", list) }
        return removed
    }

    @discardableResult
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
    /// 154/543 实体识别: 日志里可深链的引用 (密码凭证/指纹批次/成员名/MAC)
    struct EntityRef: Identifiable {
        enum Kind { case pwd(Int), fp(Int), member(String), mac(String) }
        let kind: Kind
        var id: String {
            switch kind {
            case .pwd(let a): return "pwd\(a)"
            case .fp(let b): return "fp\(b)"
            case .member(let m): return "m\(m)"
            case .mac(let m): return "mac\(m)"
            }
        }
        var text: String {
            switch kind {
            case .pwd(let a): return "钥匙 #\(a)"
            case .fp(let b): return "指纹 批次\(b)"
            case .member(let id): return DB.member(id)?.name ?? "成员"   // kind 存的是内部 id, 不能直接当标签
            case .mac(let m): return String(m.prefix(6))
            }
        }
        /// 543: 只有凭证类引用能跳到凭证页 (成员/MAC 引用只出元数据卡)
        var isCredential: Bool {
            if case .pwd = kind { return true }
            if case .fp = kind { return true }
            return false
        }
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
    /// 748 按日成功率: 只统计**真实留存**的尝试 (kf_conn_attempts 上限 300 条)。
    /// 注意 successRate() 的口径是"全部留存", 不是滚动 30 天 —— 界面不得写"近 30 天"。
    struct DayRate: Identifiable {
        var day: String
        var n: Int
        var ok: Int
        var pct: Int
        var id: String { day }
    }
    /// 756 失败原因归类 (本地词表, 给"重试建议")
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
/// 127 静默排查模式: 打开后暂停**自动连接/预热刷新/到场补发/自动重连/会话巡检/冷启动扫描**
/// 这 6 处自动动作 (消费点全在 LinkSenseKit :75/:122/:150/:237/:309/:417 —— 第九十一批逐条对过行号),
/// 便于干净复现问题。原文案还写着"暂停看门狗心跳"，那是指上面已删除的零调用副本。
enum DiagFlags {
    static var silent: Bool { DB.store.getBool("kf_silent_trouble") }
}

// ---------- 547/758 异常退出档案 (崩溃标记位 + 上次会话时长) ----------
enum CrashGuard {
    static let marker = "kf_crash_marker"
    static let lastDur = "kf_last_session"
    /// 最后打开的界面。真机闪退时，这是唯一能告诉我们"崩在哪"的线索 ——
    /// 静态分析查了多轮都没定位，所以让 App 自己记下来。
    static let lastScreenKey = "kf_last_screen"

    /// 进入一个界面时调用（幂等，值没变就不写盘）。
    static func markScreen(_ name: String) {
        if DB.store.getString(lastScreenKey) != name { DB.store.set(lastScreenKey, name) }
    }
    static var lastScreen: String { DB.store.getString(lastScreenKey) }
    /// 启动调用: 若上次没走正常退出路径 (进后台未被杀死时标记应为 false), 记异常档案
    static func checkAbnormalExit() {
        let flagged = DB.store.getBool(marker)
        if !flagged {
            DB.store.set(marker, true)   // 本次会话开始打标记
            // ⚠ kf_crash_arch_pending 原来只被设 true，**全仓没有一处清回 false** ——
            // 一次异常退出之后，诊断页会永远显示"上次是异常退出"，
            // 而实际上后面可能已经正常用了几个月。
            //
            // 走到这里说明**上次是正常退出的**，那条提示已经过了它该在的时刻。
            // 档案本身保留（archList 里还有历史），只是不再声称"上次"。
            if DB.store.getBool("kf_crash_arch_pending") {
                DB.store.set("kf_crash_arch_pending", false)
            }
            return
        }
        let prevDur = DB.store.get(lastDur, Double.self) ?? 0
        let lastDurTxt = prevDur > 0 ? String(format: "上次会话 %.1f 分钟", prevDur / 60) : "上次会话时长未记录"
        let ops = (DB.store.get([DiagOp].self, "kf_diag_ops") ?? []).prefix(5)
        let summary = ops.map { $0.t + " " + $0.label }.joined(separator: "\n")
        var arch = DB.store.get([String].self, "kf_crash_arch") ?? []
        arch.insert("异常退出于 " + DiagTime.full() + " · " + lastDurTxt
            + "\n最后操作:\n" + (summary.isEmpty ? "(无记录)" : summary), at: 0)
        if arch.count > 10 { arch = Array(arch.prefix(10)) }
        DB.store.setCodable("kf_crash_arch", arch)
        DB.store.set("kf_crash_arch_pending", true)   // 让 UI 显示"上次异常退出"入口
        DB.store.set(marker, true)                    // 本次会话继续挂标记
    }
    /// 进后台调用 (221 收尾): 记录会话时长并清标记 (正常路径)
    static func markCleanExit() {
        let started = DB.store.get("kf_session_start", Double.self) ?? 0
        if started > 0 {
            let dur = CFAbsoluteTimeGetCurrent() - started
            if dur > 1 { DB.store.set(lastDur, dur) }
        }
        DB.store.set(marker, false)
    }
    /// 会话开始: 记下启动绝对时刻
    static func markSessionStart() {
        DB.store.set("kf_session_start", CFAbsoluteTimeGetCurrent())
    }
    static var pendingAbnormal: Bool { DB.store.getBool("kf_crash_arch_pending") }
    static func archList() -> [String] { DB.store.get([String].self, "kf_crash_arch") ?? [] }
}

// ---------- 750/546/152 数据库体检·表级体积·存储构成 (UserDefaults 等价实现) ----------
enum DataHealth {
    /// 各 kf_ 键族占用估算 (546 表级体积等价), 前缀分组
    struct Family: Identifiable {
        let key: String
        let bytes: Int
        var id: String { key }
    }
    /// 存储构成条 (152): 数据台账 / 日志与遥测 / 偏好设置 三段
    struct Slice: Identifiable {
        let name: String
        let bytes: Int
        var id: String { name }
    }
    static func human(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1_000_000) }
        return String(format: "%.0f KB", Double(bytes) / 1_000)
    }
    /// 750 完整性 (等价 PRAGMA integrity_check): JSON 回环 + 台账计数核对
    /// 这些键存空串表示"默认/跟随系统"，不是空残留。
    static let emptyMeansDefault: Set<String> = ["kf_theme", "kf_accent", "kf_week_start"]

    static func integrity() -> [String] {
        var out: [String] = []
        let rep = UserDefaults.standard.dictionaryRepresentation()
        var badJson = 0, emptyStale = 0
        // ⚠ 这里的 "kf." 是**对的**，别看错。
        //
        // 调用方写的是 store.set("kf_theme", …)，而 Store.key() 会再补一个前缀
        // (private func key(_ k: String) { "kf." + k })，所以 UserDefaults 里
        // 真实键是 **"kf.kf_theme"** —— 双重前缀。
        //
        // 第一百零二批我一度把它"修"成 hasPrefix("kf_")，理由是"全仓 617 个键都用下划线"——
        // 那是数**代码里的字符串字面量**，不是 UserDefaults 里的真实键。
        // 差点把正确的代码改错，还写了一段指控不存在 bug 的注释。
        for (k, v) in rep where k.hasPrefix("kf.") {
            if let d = v as? Data {
                // jsonObject 会抛且返回非可选: 旧写法缺 try 又与 nil 比较。
                // **必须带 .fragmentsAllowed** —— 写入侧 (Store.set / setCodable) 存的就是 JSON fragment:
                // 顶层标量 (String/Bool/Int/Double) 编码后是 `true`/`1`/`"black"` 这种片段, 不带这个开关时
                // jsonObject 一律报错 ⇒ 每一个标量键都被算成"写入被截断"。
                // 真机报告 2026-10-17: 体检报"58 个数据键无法解析", 且按天递增 (19→24→49→52→54→58) ——
                // 递增的不是损坏, 是用户当天新存的标量键。这是体检自己误报, 不是数据坏了。
                if (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) == nil { badJson += 1 }
            } else if let s = v as? String, s.isEmpty, !DataHealth.emptyMeansDefault.contains(k) {
                // ⚠ 空串不一定是"残留"。下面这几个键的 "" 是**合法值**：
                //   kf_theme ""      = 跟随系统
                //   kf_accent ""     = 默认铜色
                //   kf_week_start "" = 跟随系统
                // 把它们算成残留，会让一台完全正常的机器每次体检都报
                // "发现 3 个空键残留" —— 和之前 badJson 把标量键算成"写入被截断"是同一类错。
                emptyStale += 1
            }
        }
        if badJson > 0 { out.append("发现 \(badJson) 个数据键无法解析 (可能写入被截断)") }
        if emptyStale > 0 { out.append("发现 \(emptyStale) 个空键残留") }
        let readable = DB.keychains().count
        let raw = DB.store.getDict("kf_keychains").count
        if raw - readable > 0 { out.append("钥匙串 \(raw) 条中 \(raw - readable) 条损坏不可读") }
        let orphans = scanOrphans()
        if !orphans.isEmpty { out.append("孤儿数据: " + orphans.joined(separator: "; ")) }
        if out.isEmpty { out.append("数据解析正常, 台账计数一致") }
        return out
    }
    static func scanOrphans() -> [String] {
        var out: [String] = []
        let memberIds = Set(DB.members().map { $0.id })
        var pwdOrph = 0, fpOrph = 0
        for kc in DB.keychains() {
            let l = DB.ledger(kc.mac)
            pwdOrph += l.pwds.filter { $0.owner.map { !memberIds.contains($0) } ?? false }.count
            fpOrph += l.fps.filter { $0.owner.map { !memberIds.contains($0) } ?? false }.count
        }
        if pwdOrph > 0 { out.append("\(pwdOrph) 条密码钥匙指向已删除成员 (留作无主记录)") }
        if fpOrph > 0 { out.append("\(fpOrph) 组指纹指向已删除成员 (留作无主记录)") }
        let kcs = Set(DB.keychains().map { $0.mac })
        for k in DB.store.keys() where k.hasPrefix("kf_logcache_") {
            let mac = String(k.dropFirst("kf_logcache_".count))
            if !kcs.contains(mac) {
                out.append("已删门锁 " + String(mac.prefix(6)) + " 的日志缓存残留 (\(DB.readLogs(mac).count) 条) — 「立即整理」会隔离保留 (转入 kf_logpark_, 不真删)")
                // 此处**不删**: scanOrphans 被只读的 integrity() 调用 (诊断页进页即跑),
                // 在健康检查里删数据 = 用户只是看了一眼就把某把锁的历史缓存清光了。
                // 清理动作移到显式的 vacuum()。
            }
        }
        return out
    }
    /// 451 空洞日期检测: 日志缓存覆盖区间内整天无任何条目的日期
    static func gapDays(mac: String, days: Int = 14) -> [String] {
        let logs = DB.readLogs(mac).filter { !$0.lockTimeStr.isEmpty }
        guard !logs.isEmpty else { return [] }
        let daySet = Set(logs.map { String($0.lockTimeStr.prefix(10)) })
        let cal = WeekCal.gregorian
        let today = Date()
        var gaps: [String] = []
        for i in 1...days {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let key = DiagLogs.localDay(d)   // 与 daySet (锁端墙上日期) 同一个本地口径
            if !daySet.contains(key) { gaps.insert(key, at: 0) }
        }
        // 只报"两侧都有数据"的空洞 (首尾无数据不算缺口)
        let sortedDays = Array(daySet).sorted()
        guard let first = sortedDays.first, let last = sortedDays.last else { return [] }
        return gaps.filter { $0 > first && $0 < last }
    }
    /// 223 老数据归档: 超一年的日志缓存条目移入 kf_logarch_。
    /// 旧版这里有一句 `guard !DB.store.getBool("kf_archive_off")` 并注释"可关" —— 但全仓没有任何写入方,
    /// 该 guard 恒通过 = 空转检查, 且"可关"是给不出来的承诺。归档只在手动按钮时发生, 不需要开关。
    static func archiveOldLogs() -> Int {
        let cutoffProto = ZKProtocol.protoSecondsFromMs(Int64((Date().addingTimeInterval(-365 * 86_400).timeIntervalSince1970 * 1000).rounded()))
        var moved = 0
        for kc in DB.keychains() {
            let all = DB.readLogs(kc.mac)
            let old = all.filter { $0.lockTime > 0 && $0.lockTime < cutoffProto }
            guard !old.isEmpty else { continue }
            var arch = DB.store.get([CachedLog].self, "kf_logarch_" + kc.mac) ?? []
            // 223 归档侧也要按 idxRaw 去重: 原来每次运行都把"缓存里所有超一年的行"整批 insert 进去,
            // 而这些行上一轮已经进过归档 (缓存那侧并没真的少), 于是同一条旧记录被存 N 份、
            // moved 计数每轮重复累加，"已归档 N 条"这个数就是假的。
            let archived = Set(arch.map { $0.idxRaw })
            let toMove = old.filter { !archived.contains($0.idxRaw) }
            if !toMove.isEmpty { arch.insert(contentsOf: toMove, at: 0) }
            if arch.count > 400 { arch = Array(arch.prefix(400)) }
            DB.store.setCodable("kf_logarch_" + kc.mac, arch)
            let ids = Set(old.map { $0.idxRaw })
            let kept = all.filter { !ids.contains($0.idxRaw) }
            moved += toMove.count
            // 关键: 这里必须用"替换"语义。原来走 DB.writeLogs, 而它是 新 + 旧缓存 去重合并,
            // 被移走的旧行立刻又从缓存侧并回来 ⇒ 缓存一条没少，归档成了一份副本。
            // kept 本身就是 [CachedLog] (readLogs 的返回类型), 不必再抄写成 LogEntry 往返一次。
            DB.replaceLogs(kc.mac, kept)
        }
        return moved
    }
}

// ---------- 749 记录完整性校验 (对账) — 待补拉日期段引擎 (纯函数: 只吃日志数组, 不碰 UI、不写存储) ----------
// ⚠ 为什么整份结果只能标"约" (业主拍板原话: 本地 idx/dayKey 推断, 必须标"约"):
//   **锁端不提供"缺口清单"**。协议侧权威 vendor/app/utils/status.js 实读结论:
//   · 0x16 GETLOG (Je) 响应里只有三样东西 —— rc@KLV#03、surplusLogs@KLV#04、每条日志一个 KLV#05 (status.js:100);
//   · KLV#05 条目结构 = [type 1B][len 1B][idx 4B LE][lockTime 4B LE][diffBody…] (status.js:101);
//   · 03 状态响应的键表 status.js:11-19 整张表里没有任何"日志计数"字段。
//   ⇒ **协议未提供锁内上报总数 (证据 vendor/app/utils/status.js:100-101), 本条只做本机侧待补拉清单**:
//     "逐段核对日志行数 vs 锁内上报总数"缺一个可核对的锁端被测量, 所以界面上不出现任何"锁内共 N 条"这类数字。
//   顺带把最容易被误当成"总数"的那九枚 key 的实际语义交代清楚 (status.js:15-17, 属 03 状态响应;
//   中文口径与 docs/CAPABILITY.md:52-54、本文件 754 字段字典 #21-23/#24-26/#27-29 三处一致):
//     0x21 pinInfoCapacity / 0x22 pinInfoStock / 0x23 pinInfoBinding = 数字钥匙(PIN)池 容量/剩余/绑定数;
//     0x24 pwdInfoCapacity / 0x25 pwdInfoStock / 0x26 pwdInfoMaxLen = 密码 容量/剩余/最大长度;
//     0x27 fpInfoCapacity / 0x28 fpInfoStock / 0x29 fpInfoBatchNumber = 指纹 容量/剩余/批号。
//   这九枚是**凭证槽位**计数 (JS 侧写进 pin/pwd/fp Stock 的分支见 status.js:86-88), 与日志条数无关。
//   surplusLogs 也不是总数: 它只说"本次游标之后还剩几条", 只对当前这一页成立, 而且没有落库
//   (唯一读点 LockService.getLogs 的 LogPage.surplus → RecordsView 拉日志循环里的会话内对账),
//   诊断页拿不到它。
//
// 749 两条信号分开表述, 绝不相加成一个数字:
//   A. 日期段缺失 = 那几天本机**一条都没有** (PullSegment) → 只说"本机缺 N 天";
//   B. idx 不连续 = 本机相邻两行之间空了几个序号 (IdxGap) → 可能是没拉到, 也可能是 300 行
//      缓存上限挤掉的旧行 (DB.writeLogs / DB.replaceLogs 每次写入都截 300 行), 与"哪天没日志"是两回事。
//   (Store/LockService 那两处按**符号名**引而不按行号引: 同一晚有别的批在动那几个文件, 行号会漂;
//    vendor/app/utils/status.js 是只读权威, 它的行号按实读写死。)

// ---------- 280 性能面板: 页面打开耗时 (切 Tab → 该页出现) ----------
/// 口径写死在这里，免得 UI 文案吹成"渲染耗时"：测的是 **tabSelection 变更** 到 **该页 onAppear**
/// 之间走过的墙钟时间。SwiftUI 的布局与绘制不完全落在这两点之间，所以它是一个**下界型的参考值**，
/// 不包含 BLE/网络（那本来就不在"页面打开"里）。
/// 默认关闭：这是自统计，开着等于每次切页多两次 UserDefaults 读写；
/// 而且在没有编译基线的工程里，不该用"默认改变全局行为"的方式交付一个观测功能。
struct PageOpen: Codable, Identifiable {
    let name: String
    let ms: Int
    let at: Double          // epoch 毫秒
    var id: Double { at }
}

@MainActor
enum PageTrace {
    static let onKey = "kf_page_trace_on"
    static let listKey = "kf_page_opens"
    static var isOn: Bool { DB.store.getBool(onKey, false) }
    // 起点只活在进程内：跨启动的"打开耗时"没有意义 (冷启动有它自己的 215 打点)
    private static var navAt: CFAbsoluteTime?
    private static var navName: String?


    /// RootView 只有四个 Tab，越界不可能是用户切页 → 返回空串让调用方丢弃
    static func name(forTab tab: Int) -> String {
        switch tab {
        case 0: return "设备"
        case 1: return "钥匙"
        case 2: return "记录"
        case 3: return "设置"
        default: return ""
        }
    }

    static func markNav(to tab: Int) {
        guard isOn else { return }
        let n = name(forTab: tab)
        guard !n.isEmpty else { navAt = nil; navName = nil; return }
        navName = n
        navAt = CFAbsoluteTimeGetCurrent()
    }

    /// 终点。**配不上对就丢弃，不猜**：冷启动首屏、后台回前台重放 onAppear、
    /// 以及"切页时页面本来就已在屏上"都会走到这里，此时报出来的数字一定不是打开耗时。
    static func shown(_ name: String) {
        guard isOn, let t = navAt, let from = navName else { return }
        navAt = nil
        navName = nil                       // 一次切换只配一次，重复 onAppear 不重复计数
        guard from == name else { return }
        let ms = ((CFAbsoluteTimeGetCurrent() - t) * 1000).rounded()
        guard ms >= 0, ms <= 3000 else { return }
        var list = DB.store.get([PageOpen].self, listKey) ?? []
        list.append(PageOpen(name: name, ms: Int(ms), at: Date().timeIntervalSince1970 * 1000))
        if list.count > 10 { list = Array(list.suffix(10)) }
        DB.store.setCodable(listKey, list)
    }

    static func entries() -> [PageOpen] { DB.store.get([PageOpen].self, listKey) ?? [] }
    static func clear() { DB.store.remove(listKey) }
    /// 采样时刻的时分秒。环形只留 10 条，必然是最近几分钟到几小时内的事，不带日期。
    static func clock(_ epochMs: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date(timeIntervalSince1970: epochMs / 1000))
    }
}


/// 只读数 + 给建议，**不删任何东西**：删除动作全部留在各节既有的二次确认里 (真空清理/归档/保留策略)。
/// 体积口径与 152 一致：kf_* 键值长度估算，不是磁盘真实占用 —— 这句话必须和数字一起出现。

/// 387 维护回执：把本会话做过的"本机维护"记下来，下次启动在设备页 Hero 卡下回一行。
/// 创意原文写"上次**退出期间**" —— 本 App 唯一的后台任务是 428 充电备份
/// (`BackupStudioKit.swift:237-240` 提交的 appRefresh)，它既不做这里的三类维护 (真空清理/归档/自动补发)，
/// 而且系统随时可以不执行、执行时机也不由 App 定 → "退出期间"那段窗口里没有可承诺的动作。
/// 所以按可实现口径改成"上次会话"，并在 UI 上就这么写。
enum MaintenanceLog {
    struct Act: Codable { var at: Double; var label: String }
    static let key = "kf_maint_acts"
    private static let seenKey = "kf_maint_seen_at"

    static func record(_ label: String) {
        var list = DB.store.get([Act].self, key) ?? []
        list.insert(Act(at: Date().timeIntervalSince1970, label: label), at: 0)
        DB.store.setCodable(key, Array(list.prefix(8)))
    }
    /// 本次会话开始时刻之前的动作 = "上次会话"。点过"知道了"后按 seen 水位隐藏。
    static func lastSessionLine(sessionStart: Double) -> String? {
        guard sessionStart > 0 else { return nil }
        let acts = (DB.store.get([Act].self, key) ?? []).filter { $0.at < sessionStart }
        let seen = DB.store.get(seenKey, Double.self) ?? 0
        let fresh = acts.filter { $0.at > seen }
        guard let newest = fresh.max(by: { $0.at < $1.at }) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return "上次会话本机完成 \(fresh.count) 项维护 · 最近: \(newest.label) (\(f.string(from: Date(timeIntervalSince1970: newest.at))))"
    }
    /// "知道了" = 把水位推到这批动作里最新的一条, 不删历史 (真空清理/归档的账要留着)
    static func markSeen(sessionStart: Double) {
        guard let m = (DB.store.get([Act].self, key) ?? []).filter({ $0.at < sessionStart }).max(by: { $0.at < $1.at }) else { return }
        DB.store.set(seenKey, m.at)
    }
}


// ---------- 397 本机库体自检 ----------
/// 创意原文写"解锁后在后台跑 SQLite quick_check"，但本 App 的库体在 Keychain + UserDefaults，
/// **没有 SQLite** —— 所以这一栏做的是等价的三件事，而且不叫 quick_check（叫了就是假承诺）。
/// 三项都只读、不写盘、不碰 BLE：① 库体哈希（只读比对，见 `BackupStudio.hashMismatch` 的注释）
/// ② 审计链逐条重算 ③ JSON 回环 + 台账计数核对 (750)。
struct SelfCheckLine { let name: String; let ok: Bool; let detail: String }
@MainActor
enum SelfCheck {
    static func run() -> [SelfCheckLine] {
        var out: [SelfCheckLine] = []
        let hashBad = BackupStudio.hashMismatch()
        out.append(SelfCheckLine(name: "库体哈希", ok: !hashBad,
                                 detail: hashBad ? "与上次快照不一致 — 建议立即备份" : "与上次快照一致"))   // 448/397 与上次快照不一致
        let v = AuditLog().verifyChain()
        out.append(SelfCheckLine(name: "审计链", ok: v.brokenAt < 0,
                                 detail: v.brokenAt == -2 ? "链序号异常: 有条目被截断或换序重放"   // 386 链序号异常
                                           : v.brokenAt < 0 ? "\(v.length) 条逐链重算全部通过"
                                           : "第 \(v.brokenAt + 1) 条断裂"))
        // integrity() 干净时也会返回一条"数据解析正常"，所以判 ok 必须按同一条口径过滤，
        // 直接写 `rep.isEmpty` 会永远为假 —— 一项永远说"异常"的检查和永远说"正常"的一样没用 (750)。
        let issues = DataHealth.integrity().filter { !$0.hasPrefix("数据解析正常") }
        out.append(SelfCheckLine(name: "数据完整性", ok: issues.isEmpty,
                                 detail: issues.isEmpty ? "JSON 回环与台账计数核对无异常"   // 750 回环与台账计数核对无
                                                        : issues.joined(separator: "; ")))
        return out
    }
    static func summary(_ lines: [SelfCheckLine]) -> String {
        let bad = lines.filter { !$0.ok }
        // 397 本机自检三项全部通过
        // 397 本机自检
        return bad.isEmpty ? "本机自检三项全部通过" : "本机自检 \(bad.count) 项异常 — 详情见下"
    }
}

