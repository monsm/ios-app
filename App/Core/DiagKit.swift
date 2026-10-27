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
            case .pwd(let a): return "凭证 #\(a)"
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
    /// 识别器按 LockService 实际写出的词表匹配 (`凭证#N` / `指纹#N` / `MAC=…`)。
    /// 旧版匹配 `pwd:` / `fp:` —— 全仓没有任何日志生产者写过这个前缀, 接上 UI 也永远是空数组 (空跑)。
    static func entities(in msg: String) -> [EntityRef] {
        let s = msg
        var out: [EntityRef] = []
        // range(of:options:range:) 要 Range<String.Index>; `...` 推成 ClosedRange → 类型不符
        var rng = s.startIndex..<s.endIndex
        while let r = s.range(of: "凭证#(\\d+)", options: .regularExpression, range: rng) {
            // "凭证#" = 3 字符, dropFirst(4) 会把首位数字一起吃掉
            if let a = Int(String(s[r].dropFirst(3))) { out.append(EntityRef(kind: .pwd(a))) }
            rng = r.upperBound..<s.endIndex
        }
        rng = s.startIndex..<s.endIndex
        while let r = s.range(of: "指纹#(\\d+)", options: .regularExpression, range: rng) {
            if let b = Int(String(s[r].dropFirst(3))) { out.append(EntityRef(kind: .fp(b))) }
            rng = r.upperBound..<s.endIndex
        }
        for m in DB.members() where !m.name.isEmpty && s.contains(m.name) {
            out.append(EntityRef(kind: .member(m.id)))
        }
        // 只认 `MAC=` 后面的整串 12 位: 裸 [0-9a-f]{12} 会从 debugRaw 的长 hex dump 里
        // 任意截一段当 MAC, 点进去是凭空的设备
        rng = s.startIndex..<s.endIndex
        while let r = s.range(of: "MAC=([0-9a-fA-F]{12})(?![0-9a-fA-F])", options: .regularExpression, range: rng) {
            out.append(EntityRef(kind: .mac(String(s[r].dropFirst(4)))))   // "MAC=" 4 字符
            rng = r.upperBound..<s.endIndex
        }
        return out
    }
    /// 543 实体详情文案: 只给台账元数据。pwd 字段存的是口令明文 (Store:109), 绝不进这里。
    static func entityDetail(_ e: EntityRef, mac: String) -> String {
        switch e.kind {
        case .pwd(let alias):
            if let p = DB.ledger(mac).pwds.first(where: { $0.alias == alias }) {
                return "台账内 · 备注 \(p.note.isEmpty ? "(无)" : p.note)"
                    + " · \(p.temp ? "临时凭证" : "长期凭证")"
                    + " · 属主 " + (p.owner.flatMap { DB.member($0)?.name } ?? "未指派")
                    + " · 有效期 \(p.from) ~ \(p.to)"
            }
            return "本机台账没有该凭证 —— 可能是锁端自行添加或其它 App 写入, 建议拉一次凭证清单"   // 734 本机台账没有该凭证
        case .fp(let batch):
            if let f = DB.ledger(mac).fps.first(where: { $0.batch == batch }) {
                return "台账内 · 名称 \(f.name.isEmpty ? "(未命名)" : f.name)"
                    + " · 属主 " + (f.owner.flatMap { DB.member($0)?.name } ?? "未指派")
                    + (f.isAlarm == true ? " · 告警指纹" : "")
            }
            return "本机台账没有该指纹批次 —— 建议拉一次凭证清单"   // 734 本机台账没有该指纹批
        case .member(let id):
            guard let m = DB.member(id) else { return "成员档案已删除" }
            return "成员 \(m.name) · \(m.relation.isEmpty ? "关系未填" : m.relation)"
        case .mac(let m):
            let shown = DB.keychains().first { $0.mac.uppercased() == m.uppercased() }
            return shown.map { "本机设备档案: \($0.name)" } ?? "MAC 出现在日志里, 但不在本机设备清单中"
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
    /// 近 30 天成功率 (⚠ 需积累, 冷启动为 nil → UI 显示"积累中")
    static func successRate() -> (total: Int, ok: Int, pct: Int)? {
        let a = attempts
        guard !a.isEmpty else { return nil }
        let total = a.count
        let ok = a.filter { $0.ok }.count
        return (total, ok, Int(Double(ok) * 100 / Double(total)))
    }
    /// 748 按日成功率: 只统计**真实留存**的尝试 (kf_conn_attempts 上限 300 条)。
    /// 注意 successRate() 的口径是"全部留存", 不是滚动 30 天 —— 界面不得写"近 30 天"。
    struct DayRate: Identifiable {
        var day: String
        var n: Int
        var ok: Int
        var pct: Int
        var id: String { day }
    }
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
            return DayRate(day: d, n: v.n, ok: v.ok, pct: v.n > 0 ? v.ok * 100 / v.n : 0)
        }
    }
    /// 756 失败原因归类 (本地词表, 给"重试建议")
    struct FailClass { let name: String; let n: Int; let hint: String }
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


// ---------- 750/546/152 数据库体检·表级体积·存储构成 (UserDefaults 等价实现) ----------
enum DataHealth {
    static func bytesOf(_ v: Any) -> Int {
        if let d = v as? Data { return d.count }
        if let s = v as? String { return s.utf8.count }
        return 16
    }
    /// 各 kf_ 键族占用估算 (546 表级体积等价), 前缀分组
    struct Family: Identifiable {
        let key: String
        let bytes: Int
        var id: String { key }
    }
    static func families() -> [Family] {
        let rep = UserDefaults.standard.dictionaryRepresentation()
        var byPrefix: [String: Int] = [:]
        for (k, v) in rep where k.hasPrefix("kf.") {
            let kk = String(k.dropFirst(3))
            // 键族: 去掉 mac 后缀段 (kf_ledger_aabbccddeeff → kf_ledger_)
            var prefix = kk
            if let idx = kk.lastIndex(of: "_") {
                let tail = String(kk.suffix(kk.distance(from: kk.index(idx, offsetBy: 1), to: kk.endIndex)))
                if tail.count == 12 || tail.count == 8 { prefix = String(kk.prefix(upTo: kk.index(after: idx))) }   // String.Index 无 + 运算符
            }
            byPrefix[prefix, default: 0] += bytesOf(v)
        }
        return byPrefix.map { Family(key: $0.key, bytes: $0.value) }.sorted { $0.bytes > $1.bytes }
    }
    /// 存储构成条 (152): 数据台账 / 日志与遥测 / 偏好设置 三段
    struct Slice: Identifiable {
        let name: String
        let bytes: Int
        var id: String { name }
    }
    static func composition() -> [Slice] {
        let rep = UserDefaults.standard.dictionaryRepresentation()
        var data = 0, logT = 0, pref = 0
        let dataPrefix = ["keychains", "ledger_", "snap_", "logcache_", "members", "keychain_dongles",
                          "kf_gateways", "kf_cbin_", "kf_ccred", "kf_cseq_", "kf_clists_", "kf_calert_", "kf_fevents_"]
        let logPrefix = ["diag_logs", "ble_events", "conn_attempts", "crash_", "wd_"]
        for (k, v) in rep where k.hasPrefix("kf.") {
            let b = bytesOf(v)
            let kk = String(k.dropFirst(3))
            if dataPrefix.contains(where: { kk.hasPrefix($0) }) { data += b }
            else if logPrefix.contains(where: { kk.hasPrefix($0) }) { logT += b }
            else { pref += b }
        }
        return [Slice(name: "数据台账", bytes: data), Slice(name: "日志与遥测", bytes: logT), Slice(name: "偏好设置", bytes: pref)]
    }
    static func human(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1_000_000) }
        return String(format: "%.0f KB", Double(bytes) / 1_000)
    }
    /// 750 完整性 (等价 PRAGMA integrity_check): JSON 回环 + 台账计数核对
    static func integrity() -> [String] {
        var out: [String] = []
        let rep = UserDefaults.standard.dictionaryRepresentation()
        var badJson = 0, emptyStale = 0
        for (k, v) in rep where k.hasPrefix("kf.") {
            if let d = v as? Data {
                // jsonObject 会抛且返回非可选: 旧写法缺 try 又与 nil 比较。
                // **必须带 .fragmentsAllowed** —— 写入侧 (Store.set / setCodable) 存的就是 JSON fragment:
                // 顶层标量 (String/Bool/Int/Double) 编码后是 `true`/`1`/`"black"` 这种片段, 不带这个开关时
                // jsonObject 一律报错 ⇒ 每一个标量键都被算成"写入被截断"。
                // 真机报告 2026-10-17: 体检报"58 个数据键无法解析", 且按天递增 (19→24→49→52→54→58) ——
                // 递增的不是损坏, 是用户当天新存的标量键。这是体检自己误报, 不是数据坏了。
                if (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) == nil { badJson += 1 }
            } else if let s = v as? String, s.isEmpty {
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
    /// 750 "立即整理" (等价 VACUUM): 清残留空键 + 冲刷写队列 + 校验回显
    static func vacuum() -> String {
        var removed = 0
        let rep = UserDefaults.standard.dictionaryRepresentation()
        for (k, v) in rep where k.hasPrefix("kf.") {
            if let s = v as? String, s.isEmpty {
                UserDefaults.standard.removeObject(forKey: k); removed += 1
            }
        }
        let issues = integrity().filter { !$0.hasPrefix("数据解析正常") }
        return (issues.isEmpty ? "整理完成: 数据解析正常" : "整理完成, 仍待处理: " + issues.joined(separator: "; "))
            + " · 清理 \(removed) 个残留键"
    }
    /// 452 无主凭证隔离: owner 指向已删成员的密码/指纹移入回收站 (kf_cbin_), owner 清空。
    /// 只由诊断页显式按钮调用, 只读自检 (integrity) 里绝不删数据;
    /// 入回收站而非真删 (reclaimDays 内可 365/504 取回), 所以这一支不套 752 的备份闸。
    @discardableResult
    static func quarantineOrphanCredentials() -> Int {
        let memberIds = Set(DB.members().map { $0.id })
        var n = 0
        for kc in DB.keychains() {
            let mac = kc.mac
            for p in DB.listPwds(mac) where (p.owner.map { !memberIds.contains($0) } ?? false) {
                var cp = p
                cp.owner = nil
                DB.delPwd(mac, p.alias)
                n += 1
            }
            for f in DB.listFps(mac) where (f.owner.map { !memberIds.contains($0) } ?? false) {
                var cf = f
                cf.owner = nil
                DB.delFp(mac, f.batch)
                n += 1
            }
        }
        return n
    }
    /// 452 孤儿扫描: 凭证 owner 指向不存在成员 / 已删锁的日志残留 (可一键"隔离"移除)
    static func scanOrphans() -> [String] {
        var out: [String] = []
        let memberIds = Set(DB.members().map { $0.id })
        var pwdOrph = 0, fpOrph = 0
        for kc in DB.keychains() {
            let l = DB.ledger(kc.mac)
            pwdOrph += l.pwds.filter { $0.owner.map { !memberIds.contains($0) } ?? false }.count
            fpOrph += l.fps.filter { $0.owner.map { !memberIds.contains($0) } ?? false }.count
        }
        if pwdOrph > 0 { out.append("\(pwdOrph) 条密码凭证指向已删除成员 (留作无主记录)") }
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
    static func archivedCount(_ mac: String) -> Int {
        DB.store.get([CachedLog].self, "kf_logarch_" + mac)?.count ?? 0
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
/// 749 一段连续"本机整天没有日志"的日期段 (起止都含)。
struct PullSegment: Identifiable {
    let fromDay: String        // yyyy-MM-dd 段首日 (含)
    let toDay: String          // yyyy-MM-dd 段尾日 (含)
    let missingDays: Int       // 本机缺的天数 (整天计, 不是锁端条数)
    let approximate: Bool      // 749: 恒 true — 锁端无缺口清单, 只能本机推断; 界面文案因此强制带"约"
    let basis: String          // 判据说明 (口径只写在引擎这一处, 界面直接读它)
    var id: String { fromDay + "~" + toDay }
    /// 749 界面行首: "约 <起> ~ <止> · 本机缺 N 天" (单日不重复画 "~")。
    /// "约" 这个字由 approximate 这个字段决定而不是写死在文案里 —— 这样锁端哪天真给了缺口清单,
    /// 引擎把 false 传进来就够了, 界面不会留着一句过期的谦辞, 也不会留着一条假承诺。
    var line: String {
        let span = fromDay == toDay ? fromDay : "\(fromDay) ~ \(toDay)"
        return (approximate ? "约 " : "") + span + " · 本机缺 \(missingDays) 天"
    }
}
/// 749 本机 idx 序列的相邻断档 (信号 B, 不参与日期段的任何算术)。
struct IdxGap: Identifiable {
    let lowIdx: UInt32
    let highIdx: UInt32
    let skipped: Int           // 两行之间本机看不到的序号个数 — 纯本机算术, 不等于"锁内丢了几条"
    var id: String { "\(lowIdx)-\(highIdx)" }
    var line: String { "序号 \(lowIdx) → \(highIdx) · 中间空 \(skipped) 个号" }
}
/// 749 一次推断的完整输出 (字段只增不减, 便于影子对拍时逐字段断言)
struct PullGapReport {
    let totalRows: Int          // 本机日志行数 (含无有效时刻的行)
    let clocklessRows: Int      // 被"协议纪元判据"排除的行数 (lockTime 0 那类占位值)
    let firstDay: String?       // 本机最早有日志的一天 (一天都没有 = nil)
    let lastDay: String?
    let coveredDays: Int        // 本机有日志的天数
    let segments: [PullSegment] // 待补拉日期段 (最近在前, 已按上限截断)
    let segmentsHidden: Int     // 因上限没列出来的段数
    let missingDayTotal: Int    // 全部段的缺天合计 (本机天, 不是锁端条数)
    let windowed: Bool          // 跨度超上限, 只扫了最近一段
    let tail: PullSegment?      // 最后一行之后的尾段 (单列, 不算进 segments)
    let idxGaps: [IdxGap]       // 断档样本 (最近在前, 已按上限截断)
    let idxGapTotal: Int        // 断档总处数
    let idxGapSkippedTotal: Int // 空号合计 (与"缺 N 天"分列, 不相加)
    let idxAnomalies: Int       // 跳变过大、没报号数的相邻对数
    var noLogs: Bool { totalRows == 0 }
    var singleDay: Bool { coveredDays <= 1 }
}

enum RecordReconcile {
    /// 749 相邻序号之间空号数超过这个上限就只计数、不报号数: 游标边界 (startIdx 从 0xFFFFFFFF 起)
    /// 与锁端重排会算出上亿的量, 把它当成"缺了几亿条"画出来就是假数据。
    static let idxGapCap = 5000
    /// 749 判据文案的唯一来源 (界面直接显示它, 免得两处各写一套口径)
    static let interiorBasis = "前后两侧本机都有日志, 中间这些天本机一行都没有"
    static let tailBasis = "本机最后一行之后到昨天, 只有前一侧有数据 — 这段可能只是没连过锁, 只作补拉参考"
    /// 749 扫描跨度默认上限。界面那句"超过 N 天只扫了最近一段"报的就是这个数, 所以只存在这一处。
    static let defaultMaxSpanDays = 366
    /// 749 界面入口: 读当前锁的本机缓存后喂给纯函数 (引擎本身只做"数组→结构"这一件事)
    static func pendingPull(mac: String) -> PullGapReport { pendingPull(logs: DB.readLogs(mac)) }
    /// 749 纯函数: 本机 idx 序列 + lockTime 换算的 dayKey → 待补拉的连续日期段。
    /// - Parameter logs: 已有的本机日志数组 (影子对拍直接喂同一份数据即可复现, 全程只读)
    /// - Parameter maxSpanDays: 扫描跨度上限。缓存只有 300 行, 但 223 归档之后跨度可能拉到几年,
    ///   不设上限等于拿一次页面刷新去数几千格日历。
    static func pendingPull(logs: [CachedLog], maxSpanDays: Int = RecordReconcile.defaultMaxSpanDays,
                            maxSegments: Int = 8, maxGaps: Int = 5) -> PullGapReport {
        let cal = WeekCal.gregorian
        // 749 有效时刻判据复用 StatsKit.dateOf 这一个口径 (lockTime == 0 换算后落在协议纪元
        // 2010-01-01, 那是"锁端时钟没读到/无时钟型号"的占位值 —— StatsKit.swift:13-19 与
        // Milestones.swift:504-506 已把它定成"没有锁端时刻就没有日期")。这里不另立第二个定义。
        var daySet = Set<String>()
        var lo: Date?
        var hi: Date?
        var dated = 0
        for l in logs {
            guard let d = StatsKit.dateOf(l) else { continue }
            dated += 1
            daySet.insert(StatsKit.dayKey(d))
            if lo == nil || d < lo! { lo = d }
            if hi == nil || d > hi! { hi = d }
        }
        // 749 信号 B: 序号断档与有没有时刻无关, 所以无时钟的行也照样参与 (行本身已按 idxRaw 去重)。
        var gaps: [IdxGap] = []
        var anomalies = 0
        let idxs = Array(Set(logs.map { $0.idxRaw })).sorted()
        if idxs.count >= 2 {
            for i in 1..<idxs.count {
                // Int64 中转: 排序后已保证 b > a, 但 `-1` 在 0 附近不想靠截断语义。
                let skipped = Int(Int64(idxs[i]) - Int64(idxs[i - 1]) - 1)
                if skipped <= 0 { continue }
                if skipped > idxGapCap { anomalies += 1; continue }
                gaps.append(IdxGap(lowIdx: idxs[i - 1], highIdx: idxs[i], skipped: skipped))
            }
        }
        let gapSkipped = gaps.reduce(0) { $0 + $1.skipped }
        let shownGaps = Array(gaps.suffix(maxGaps).reversed())
        // 749 信号 A: 日期段。中段空洞的定义要求两侧都有数据, 所以只在 [最早日, 最后日) 内逐日走。
        var segs: [PullSegment] = []
        var allSegs: [PullSegment] = []
        var windowed = false
        var tail: PullSegment?
        if let firstDate = lo, let lastDate = hi {
            let firstDayDate = cal.startOfDay(for: firstDate)
            let lastDayDate = cal.startOfDay(for: lastDate)
            // 749 尾段: 只数到"昨天" —— 今天还没过完, 算成整天会凭空多出一格。
            // 尾段的要求比中段低 (只要有"最后一行"就行), 所以它在 daySet 只有一天的时候也成立:
            // 那种情形下"此后到今天之前本机没数据"恰恰是最该看得见的一条。
            let yest = WeekCal.shifted(cal.startOfDay(for: Date()), days: -1)
            if lastDayDate < yest {
                let t0 = WeekCal.shifted(lastDayDate, days: 1)
                let n = (cal.dateComponents([.day], from: t0, to: yest).day ?? 0) + 1   // 749 闭区间: 差值 + 1
                if n > 0 {
                    tail = PullSegment(fromDay: StatsKit.dayKey(t0), toDay: StatsKit.dayKey(yest),
                                       missingDays: n, approximate: true, basis: tailBasis)
                }
            }
            // 749 中段空洞要两侧都有依据 (451 的口径): 覆盖天数不足两天就一段也推不出来。
            // 这时候界面上只剩尾段与序号两条线, 各说各的, 不会冒出一条"缺 N 天"的假段。
            if daySet.count >= 2 {
                let span = cal.dateComponents([.day], from: firstDayDate, to: lastDayDate).day ?? 0
                var cur = firstDayDate
                if span > maxSpanDays {
                    windowed = true
                    cur = WeekCal.shifted(lastDayDate, days: -maxSpanDays)
                    // 749 窗口左边必须钉在"本机有日志的那一天"上: 否则最左那段就成了只有一侧有依据的猜测,
                    // 451 定下的"两侧都有数据"口径不能因为开窗而破。lastDay 本身在 daySet 里, 所以必停得住。
                    var snap = 0
                    while !daySet.contains(StatsKit.dayKey(cur)), snap < maxSpanDays + 2 {
                        cur = WeekCal.shifted(cur, days: 1)
                        snap += 1
                    }
                }
                // 749 第一步: 把要扫的那些天按序列成 dayKey (逐日走而不是比字符串 —— 跨度是日历日,
                // 用 86400 秒在有夏令时的地区会数错一格, 见 WeekCal:39-45)。
                var days: [String] = []
                var steps = 0
                let stepCeil = maxSpanDays + 400
                while cur < lastDayDate && steps < stepCeil {
                    steps += 1
                    days.append(StatsKit.dayKey(cur))
                    cur = WeekCal.shifted(cur, days: 1)
                }
                // 749 第二步: 连续缺的天并成段。这里只用下标算术, 不写需要跨层捕获可变局部量的闭包 ——
                // 本机没有编译器, 少一种形状就少一处"只有编译器才能定论"的地方。
                var i = 0
                while i < days.count {
                    if daySet.contains(days[i]) { i += 1; continue }
                    var j = i
                    while j < days.count, !daySet.contains(days[j]) { j += 1 }
                    allSegs.append(PullSegment(fromDay: days[i], toDay: days[j - 1],
                                               missingDays: j - i, approximate: true, basis: interiorBasis))
                    i = j
                }
                segs = Array(allSegs.reversed().prefix(maxSegments))   // 749 最近在前, 与本页其它清单一致
            }
        }
        return PullGapReport(
            totalRows: logs.count,
            clocklessRows: logs.count - dated,
            firstDay: lo.map { StatsKit.dayKey($0) },
            lastDay: hi.map { StatsKit.dayKey($0) },
            coveredDays: daySet.count,
            segments: segs,
            segmentsHidden: max(0, allSegs.count - segs.count),
            missingDayTotal: allSegs.reduce(0) { $0 + $1.missingDays },
            windowed: windowed,
            tail: tail,
            idxGaps: shownGaps,
            idxGapTotal: gaps.count,
            idxGapSkippedTotal: gapSkipped,
            idxAnomalies: anomalies
        )
    }
    /// 749 清单纯文本 (复制与影子对拍共用; 每一行都带"约", 结尾把"到场"这一既有限制写上)
    static func plainLine(_ r: PullGapReport, name: String) -> String {
        var out = "锁 \(name) · 本机日志 \(r.totalRows) 行 · 覆盖 \(r.coveredDays) 天"   // 749 本机日志
        for s in r.segments { out += "\n" + s.line + " — " + s.basis }
        if r.segmentsHidden > 0 { out += "\n另有 \(r.segmentsHidden) 段未列出" }
        if let t = r.tail { out += "\n尾段 " + t.line + " — " + t.basis }
        for g in r.idxGaps { out += "\n" + g.line }
        if r.idxAnomalies > 0 { out += "\n另有 \(r.idxAnomalies) 处序号跳变过大, 未报号数" }
        out += "\n以上全部为约: 锁端不提供缺口清单, 协议也没有锁内上报总数 — 补拉要到场连接后在记录页执行"
        return out
    }
}

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




// ---------- 149/150/160/545/760 一键体检引擎 (10 项, 单项可复测) ----------
struct HealthCheckItem: Identifiable {
    let id: String
    let name: String
    let ok: Bool
    let detail: String        // 人话: 状态 + 怎么办
}
struct HealthCheckArchive: Codable, Identifiable {
    var id = UUID().uuidString
    var at: String
    var score: Int
    var lines: [String]
}
@MainActor
enum DiagHealth {
    struct ItemDef {
        let id: String
        let name: String
        let run: @MainActor () -> HealthCheckItem
    }
    /// 545 能力自检清单 + 760 运行自检共用同一套项 (蓝牙/通知/应用锁/存储/备份/备份可读/连接/数据/触感/面容)
    static var items: [ItemDef] {
        [ItemDef(id: "ble", name: "蓝牙权限") { checkBLE() },
         ItemDef(id: "notify", name: "本地通知") { checkNotify() },
         ItemDef(id: "applock", name: "本机密码") { checkAppLock() },
         ItemDef(id: "storage", name: "存储余量") { checkStorage() },
         ItemDef(id: "backup", name: "备份新鲜度") { checkBackup() },
         ItemDef(id: "conn", name: "门锁连接") { checkConn() },
         ItemDef(id: "data", name: "数据完整性") { checkData() },
         ItemDef(id: "haptic", name: "触感反馈") { checkHaptic() },
         // 545 面容可用性: 无生物硬件的设备不算故障 (877 降级链已定义该情形), 如实报"走 DEFERRED"
         ItemDef(id: "faceid", name: "面容可用性") {
             let ok = AuthKit.biometricAvailable
             return HealthCheckItem(id: "faceid", name: "面容可用性", ok: ok,
                                    detail: ok ? "Face ID / Touch ID 可用" : "本机无生物识别硬件, 该能力走 DEFERRED")
         }]
    }
    /// 149 总分口径 (唯一算术, 视图不另算): 每项满分 20, 总分 = Σ得分 × 100 / 满分。
    /// 界面写"总分 X / 100", 原先 runAll 的 raw/10 与视图重测的 raw/2 各给各的 (9 项满分 18 / 90),
    /// "/100" 是假数 —— 两处收进这里, 全绿必然 100。
    static func percent(_ list: [HealthCheckItem]) -> Int {
        let full = list.count * 20
        guard full > 0 else { return 0 }
        let raw = list.reduce(0) { $0 + ($1.ok ? 20 : 10) }
        return Int(Double(raw) * 100 / Double(full))
    }
    /// 149 一键体检: 全量跑一遍出总分 (每项 20 / 警告 10)
    static func runAll() -> (score: Int, items: [HealthCheckItem]) {
        let list = items.map { $0.run() }
        return (percent(list), list)
    }
    /// 160 单项复测: 只重跑指定项
    static func runItem(_ id: String) -> HealthCheckItem? {
        items.first(where: { $0.id == id })?.run()
    }
    // ---------- 158 体检存档 (⚠ 降级: 本地存档列表, 历史对比"积累中"占位) ----------
    static func saveArchive(_ r: (score: Int, items: [HealthCheckItem])) {
        var list = archives()
        list.insert(HealthCheckArchive(at: DiagTime.full(), score: r.score,
                                       lines: r.items.map { ($0.ok ? "通过" : "待处理") + " " + $0.name }), at: 0)
        if list.count > 30 { list = Array(list.prefix(30)) }
        DB.store.setCodable("kf_diag_arch", list)
    }
    static func archives() -> [HealthCheckArchive] {
        DB.store.get([HealthCheckArchive].self, "kf_diag_arch") ?? []
    }
    // ---------- 分项 ----------
    /// 旧写法这里自建 `CBCentralManager()` 且**不传代理**: 没有代理的中央管理器状态永远停在 .unknown,
    /// 于是蓝牙明明开着, 体检这一项也恒红, 文案还把用户支去"控制中心打开蓝牙后重测" —— 永远重测不好。
    /// 现改用 BLEService 那个有代理、真正在跑的管理器的状态, 并把"不可判定"与"未开启"分开表述。
    static func checkBLE() -> HealthCheckItem {
        let auth = CBCentralManager.authorization
        if auth == .denied {
            return HealthCheckItem(id: "ble", name: "蓝牙权限", ok: false,
                                   detail: "蓝牙权限被拒绝 — 到 设置 → 离线锁管家 → 蓝牙 开启后复测")
        }
        func item(_ detail: String, ok: Bool = false) -> HealthCheckItem {
            HealthCheckItem(id: "ble", name: "蓝牙权限", ok: ok, detail: detail)
        }
        switch BLEService.shared.powerState {
        case .poweredOn:
            return item("蓝牙已开启, 可正常连接门锁", ok: true)
        case .poweredOff:
            return item("蓝牙未开启 — 控制中心打开蓝牙后点「重测」")
        case .unsupported:
            return item("此设备不支持所需的蓝牙功能")
        case .unauthorized:
            return item("未获得蓝牙权限: 系统设置 → 隐私与安全性 → 蓝牙 中允许本 App")
        case .resetting:
            return item("蓝牙栈正在重置, 稍后点「重测」")
        case .unknown, nil:
            return item("蓝牙状态尚未回报 (App 刚启动或中心管理器未初始化) — 不等于蓝牙正常, 请进入门锁页后复测")
        @unknown default:
            return item("蓝牙状态不可判定 — 不计为通过")
        }
    }
    static func checkNotify() -> HealthCheckItem {
        // 1170: notificationSettings() 在 iOS 15+ 是 async 方法, 而体检项 run 是同步闭包 ——
        // 用信号量把这一次查询拉回同步 (体检是用户主动点的低频操作, 阻塞上限 1.5s 可接受)。
        // 必须 Task.detached: 本函数在 MainActor 上跑, 若用 Task{} 会继承 MainActor,
        // 主线程正卡在 sem.wait 上, 任务体永远排不上 → 必超时。
        let box = NotifyAuthBox()
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            box.status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.5)
        switch box.status {
        case .denied:
            return HealthCheckItem(id: "notify", name: "本地通知", ok: false,
                                   detail: "通知被拒绝 — 保养/召回提醒不可用, 到系统设置重新开启")
        case .notDetermined:
            return HealthCheckItem(id: "notify", name: "本地通知", ok: true,
                                   detail: "尚未授权, 首次用到提醒时会弹请求")
        default:
            return HealthCheckItem(id: "notify", name: "本地通知", ok: true, detail: "通知已授权")
        }
    }
    static func checkAppLock() -> HealthCheckItem {
        DB.hasPasscode()
            ? HealthCheckItem(id: "applock", name: "本机密码", ok: true, detail: "已设置, 查看密码与备份需验证")
            : HealthCheckItem(id: "applock", name: "本机密码", ok: false, detail: "未设置 — 建议设置, 防他人直接看到密码明文")
    }
    static func checkStorage() -> HealthCheckItem {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // 读不到 = 不可判定, 不能计成通过 (旧写法让体检出现假绿灯)
            return HealthCheckItem(id: "storage", name: "存储余量", ok: false, detail: "无法读取卷容量 — 保守计为不通过")
        }
        let b = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        let ok = b > 500 * 1_048_576
        return HealthCheckItem(id: "storage", name: "存储余量", ok: ok,
                               detail: ok ? "剩余空间充足" : "剩余不足 500MB — 备份导出会受影响, 建议清理")
    }
    static func checkBackup() -> HealthCheckItem {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        guard let last = hist.max() else {
            return HealthCheckItem(id: "backup", name: "备份新鲜度", ok: false, detail: "从未备份 — 建议先做一次本地备份")
        }
        // last 是 epoch **毫秒**: 旧写法 now秒 - (毫秒/1000/86400) 把两种量纲直接相减,
        // 结果恒为 ~1.7e9 "天" → 备份新鲜度永远判超期。先换算成秒再算天数差。
        let days = max(0, Date().timeIntervalSince1970 - last / 1000) / 86_400
        let ok = days < 30
        return HealthCheckItem(id: "backup", name: "备份新鲜度", ok: ok,
                               detail: String(format: "上次备份 %.0f 天前", days) + (ok ? "" : " — 超过 30 天, 建议补一次"))
    }
    // 2026-10-27 六轮精简：备份文件可读性检查已删（BackupStudio 的 algoNote/checksum 一并移除）。
    static func checkConn() -> HealthCheckItem {
        let mac = DB.currentMac
        guard !mac.isEmpty else {
            return HealthCheckItem(id: "conn", name: "门锁连接", ok: true, detail: "未配对门锁 — 添加并首连验证后启用")
        }
        let m = LockArchive.meta(mac)
        if m.lastConnectedAt > 0, !LockArchive.isSleeping(mac) {
            return HealthCheckItem(id: "conn", name: "门锁连接", ok: true, detail: "近期连接成功, 链路正常")
        }
        return HealthCheckItem(id: "conn", name: "门锁连接", ok: m.lastConnectedAt > 0,
                                detail: m.lastConnectedAt > 0 ? "超过 30 天未连接 — 到设备页连一次验证" : "从未验证过连接 — 建议做一次首连验证")
    }
    static func checkData() -> HealthCheckItem {
        let rep = DataHealth.integrity()
        let ok = rep.allSatisfy { $0.hasPrefix("数据解析正常") }
        return HealthCheckItem(id: "data", name: "数据完整性", ok: ok, detail: rep.joined(separator: "; "))
    }
    static func checkHaptic() -> HealthCheckItem {
        // 系统没有任何"触感开关"的公开读取口 (UIImpactFeedbackGenerator 无 isEnabled 成员);
        // 能问的只有硬件是否支持触感 (CoreHaptics)。如实按硬件能力报, 不谎报"开着也没关" 也不谎报"关了"。
        let on = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        return HealthCheckItem(id: "haptic", name: "触感反馈", ok: on,
                               detail: on ? "触感引擎可用" : "系统触感关闭 — 设置 → 辅助功能 → 触感反馈")
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
    /// 2026-10-27 六轮精简：本机自检三项已删（哈希比对 / 审计链 / JSON 回环
    /// 三个依赖随 WebDAV 一族与 AuditLog 一起移除），只留空实现保证调用点不炸。
    static func run() -> [SelfCheckLine] { [] }

    /// 把自检结果压成一句话（手动触发时的 Toast / 解锁路径的静默判定都读它）。
    static func summary(_ lines: [SelfCheckLine]) -> String {
        let bad = lines.filter { !$0.ok }
        return bad.isEmpty ? "本机自检全部通过" : "本机自检 \(bad.count) 项异常 — 详情见下"
    }
}

/// 1170 同步读取通知授权状态的载体。
/// 只写一次 (写完即 signal), 故 @unchecked Sendable 安全 —— 不做跨线程读写交错。
private final class NotifyAuthBox: @unchecked Sendable {
    var status: UNAuthorizationStatus = .notDetermined
}
