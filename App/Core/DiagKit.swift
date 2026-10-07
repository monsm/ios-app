// 包11 诊断·性能·运维 — 数据层 (无 UI; 全部本地)
// 编号对照 docs/ROADMAP-DRAFT.md「包11」:
//   体检 149/150/151/158/160/545/760 · 日志 152-154/281/283/542/543/740 ·
//   数据健康 451/452/750/546/547/758/215/223 · 性能层 216/217/218/220/221/224 ·
//   深度诊断 277/544/748/749/753/754/756/661/662/762/127/299
// 底层说明: 本项目"数据库"是 UserDefaults(JSON 编码) 语义封装 (Store.swift),
// VACUUM/索引类创意按其等价落地: "整理"= 清残留空键 + 写队列冲刷; "完整性"= JSON 回环 + 台账计数核对。
import Foundation
import UIKit
import CoreBluetooth
import CryptoKit
import CoreImage
import UserNotifications

// ---------- 时间戳辅助 (locale 无关, 台账可比对) ----------
enum DiagTime {
    static func hhmmss() -> String {
        let c = Calendar.current
        return String(format: "%02d:%02d:%02d", c.component(.hour, from: Date()), c.component(.minute, from: Date()), c.component(.second, from: Date()))
    }
    static func mmddHHmm() -> String {
        let c = Calendar.current
        return String(format: "%02d-%02d %02d:%02d", c.component(.month, from: Date()), c.component(.day, from: Date()), c.component(.hour, from: Date()), c.component(.minute, from: Date()))
    }
    static func mmddHHmmss() -> String {
        let c = Calendar.current
        return String(format: "%02d-%02d %02d:%02d:%02d", c.component(.month, from: Date()), c.component(.day, from: Date()), c.component(.hour, from: Date()), c.component(.minute, from: Date()), c.component(.second, from: Date()))
    }
    /// 纯文本备份 (753 二维码/复制用)
    static func full() -> String {
        let c = Calendar.current
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
    static var isOn() -> Bool { DB.store.getBool(on, true) }
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
    private static var marks: [String: Double] = [:]
    static func mark(_ p: String) { marks[p] = CFAbsoluteTimeGetCurrent() - t0 }
    /// 各阶段耗时 (ms)
    static func ms(_ p: String) -> Double? { marks[p].map { ($0 * 1000).rounded() } }
    static var totalMs: Double { (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
    static var overBudget: Bool { totalMs > 800 }
}

// ---------- 218 写入合并: 批量落盘队列 (≤1s 合并, 退后台冲刷; 221 scenePhase 接线) ----------
enum WriteQueue {
    private static var queue: [(String, Any)] = []
    private static var timer: Timer?
    /// 入队: 同一键后写覆盖先写, 1 秒内同键只落一次盘
    static func enqueue(_ k: String, _ v: Any) {
        queue.removeAll { $0.0 == k }
        queue.append((k, v))
        schedule()
    }
    private static func schedule() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            timer = nil
            flush()
        }
    }
    static func flush() {
        timer?.invalidate(); timer = nil
        for (k, v) in queue { DB.store.set(k, v) }
        queue.removeAll()
    }
}

// ---------- 220 热点缓存: 当前锁最近 50 条常驻内存 (时间线首屏加速; 217 等价"热数据前置") ----------
enum HotCache {
    private static var store: [String: [CachedLog]] = [:]
    static var currentMac: String = ""
    static func load(mac: String) {
        currentMac = mac
        store[mac] = Array(DB.readLogs(mac).prefix(50))
    }
    /// 日志刷新后同步缓存 (保持首屏数据新鲜)
    static func invalidate(_ mac: String) {
        store[mac] = Array(DB.readLogs(mac).prefix(50))
    }
    static func recent(_ mac: String) -> [CachedLog] {
        if mac == currentMac, let v = store[mac] { return v }
        store[mac] = Array(DB.readLogs(mac).prefix(50))
        return store[mac] ?? []
    }
}

// ---------- 224 启动并行预热 (冷启动一次完成, 后续零成本) ----------
enum Prewarm {
    static var done = false
    static func run(mac: String) {
        guard !done else { return }
        done = true
        _ = DB.keychains()
        _ = DB.hasPasscode()
        _ = DB.store.getString("kf_theme")
        HotCache.load(mac: mac)
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
    static var entries: [DiagLogEntry] {
        DB.store.get([DiagLogEntry].self, "kf_diag_logs") ?? []
    }
    /// 按 751 保留策略过滤后的全量 (最新在末尾)
    static func all() -> [DiagLogEntry] {
        var list = entries
        if let days = retentionDays {
            let cs = String(Date().addingTimeInterval(-Double(days) * 86_400).formatted(.iso8601).prefix(10))
            list = list.filter { $0.date >= cs }
        }
        return list
    }
    static func today() -> [DiagLogEntry] {
        let d = String(Date().formatted(.iso8601).prefix(10))
        return entries.filter { $0.date == d }
    }
    /// 由 LockService 分级日志调用: date/time 取自行内已有时序, 落持久台账
    static func append(_ level: String, _ msg: String, date: String, time: String) {
        var list = entries
        list.append(DiagLogEntry(date: date, time: time, level: level, msg: msg))
        if list.count > 500 { list = Array(list.suffix(500)) }
        if let days = retentionDays {
            let cs = String(Date().addingTimeInterval(-Double(days) * 86_400).formatted(.iso8601).prefix(10))
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
            case .member(let n): return n
            case .mac(let m): return String(m.prefix(6))
            }
        }
    }
    static func entities(in msg: String) -> [EntityRef] {
        var out: [EntityRef] = []
        var s = msg
        var rng = s.startIndex...s.endIndex
        while let r = s.range(of: "pwd:(\\d+)", options: .regularExpression, range: rng) {
            let digits = String(s[r].dropFirst(4))
            if let a = Int(digits) { out.append(EntityRef(kind: .pwd(a))) }
            rng = r.upperBound..<s.endIndex
        }
        rng = s.startIndex...s.endIndex
        while let r = s.range(of: "fp:(\\d+)", options: .regularExpression, range: rng) {
            let digits = String(s[r].dropFirst(4))
            if let b = Int(digits) { out.append(EntityRef(kind: .fp(b))) }
            rng = r.upperBound..<s.endIndex
        }
        for m in DB.members() where !m.name.isEmpty, s.contains(m.name) {
            out.append(EntityRef(kind: .member(m.id)))
        }
        if let r = s.range(of: "[0-9a-f]{12}", options: [.regularExpression, .caseInsensitive]) {
            out.append(EntityRef(kind: .mac(String(s[r].dropFirst(2)))))
        }
        return out
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

// ---------- 277 看门狗自恢复 (BLE 连接态心跳自愈, 与 BLEService 只读协作) ----------
enum Watchdog {
    private static var consecutiveFail = 0
    private static var timer: Timer?
    /// 启动周期心跳: 已连接时每 45s 读一次 03; 失败尝试一次自愈重连 (127 静默排查时不跳)
    static func start(lock: LockService) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { _ in
            guard !DiagFlags.silent else { return }
            Task { @MainActor in await beat(lock) }
        }
    }
    static func stop() {
        timer?.invalidate(); timer = nil
    }
    private static func beat(_ lock: LockService) async {
        let mac = lock.connectedMAC
        guard !mac.isEmpty else { return }
        do {
            _ = try await lock.getStatus(mac: mac)
            consecutiveFail = 0
        } catch {
            consecutiveFail += 1
            guard consecutiveFail <= 3 else { return }   // 单次会话 3 次自愈上限, 不反复耗蓝牙
            do {
                try await lock.ensureConnected(mac: mac)
                DB.store.set("kf_wd_heal", DB.store.getInt("kf_wd_heal") + 1)
                lock.log("info", "看门狗: 心跳异常后已自动重建连接 (连续第 \(consecutiveFail) 次)")
            } catch {
                lock.log("warn", "看门狗: 自愈重连失败 — " + (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
    static var healCount: Int { DB.store.getInt("kf_wd_heal") }
}
/// 127 静默排查模式: 打开后暂停看门狗心跳与自动刷状态, 便于干净复现问题
enum DiagFlags {
    static var silent: Bool { DB.store.getBool("kf_silent_trouble") }
}

// ---------- 547/758 异常退出档案 (崩溃标记位 + 上次会话时长) ----------
enum CrashGuard {
    static let marker = "kf_crash_marker"
    static let lastDur = "kf_last_session"
    /// 启动调用: 若上次没走正常退出路径 (进后台未被杀死时标记应为 false), 记异常档案
    static func checkAbnormalExit() {
        let flagged = DB.store.getBool(marker)
        if !flagged {
            DB.store.set(marker, true)   // 本次会话开始打标记
            return
        }
        let prevDur = DB.store.get(Double.self, lastDur) ?? 0
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
        let started = DB.store.get(Double.self, "kf_session_start") ?? 0
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
    static func consumePending() -> Bool {
        defer { DB.store.remove("kf_crash_arch_pending") }
        return DB.store.getBool("kf_crash_arch_pending")
    }
    static var pendingAbnormal: Bool { DB.store.getBool("kf_crash_arch_pending") }
    static func archList() -> [String] { DB.store.get([String].self, "kf_crash_arch") ?? [] }
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
                if tail.count == 12 || tail.count == 8 { prefix = String(kk.prefix(upTo: idx + 1)) }
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
        let dataPrefix = ["kf_keychains", "kf_ledger_", "kf_snap_", "kf_logcache_", "kf_members", "kf_keychain_dongles",
                          "kf_gateways", "kf_chist_", "kf_cbin_", "kf_ccred", "kf_cseq_", "kf_clists_", "kf_calert_", "kf_fevents_"]
        let logPrefix = ["kf_diag_logs", "kf_ble_events", "kf_conn_attempts", "kf_crash_", "kf_wd_"]
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
                if JSONSerialization.jsonObject(with: d, options: []) == nil { badJson += 1 }
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
        WriteQueue.flush()
        let issues = integrity().filter { !$0.hasPrefix("数据解析正常") }
        return (issues.isEmpty ? "整理完成: 数据解析正常" : "整理完成, 仍待处理: " + issues.joined(separator: "; "))
            + " · 清理 \(removed) 个残留键"
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
                out.append("已删门锁 " + String(mac.prefix(6)) + " 的日志缓存残留 (\(DB.readLogs(mac).count) 条)")
                DB.store.remove(k)   // 隔离即修复: 日志缓存不是台账, 移除无副作用
            }
        }
        return out
    }
    /// 451 空洞日期检测: 日志缓存覆盖区间内整天无任何条目的日期
    static func gapDays(mac: String, days: Int = 14) -> [String] {
        let logs = DB.readLogs(mac).filter { !$0.lockTimeStr.isEmpty }
        guard !logs.isEmpty else { return [] }
        let daySet = Set(logs.map { String($0.lockTimeStr.prefix(10)) })
        let cal = Calendar.current
        let today = Date()
        var gaps: [String] = []
        for i in 1...days {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let key = String(d.formatted(.iso8601).prefix(10))
            if !daySet.contains(key) { gaps.insert(key, at: 0) }
        }
        // 只报"两侧都有数据"的空洞 (首尾无数据不算缺口)
        let sortedDays = Array(daySet).sorted()
        guard let first = sortedDays.first, let last = sortedDays.last else { return [] }
        return gaps.filter { $0 > first && $0 < last }
    }
    /// 223 老数据归档: 超一年的日志缓存条目移入 kf_logarch_ (可关: kf_archive_off)
    static func archiveOldLogs() -> Int {
        guard !DB.store.getBool("kf_archive_off") else { return 0 }
        let cutoffProto = ZKProtocol.protoSecondsFromMs((Date().addingTimeInterval(-365 * 86_400).timeIntervalSince1970 * 1000).rounded())
        var moved = 0
        for kc in DB.keychains() {
            let all = DB.readLogs(kc.mac)
            let old = all.filter { $0.lockTime > 0 && $0.lockTime < cutoffProto }
            guard !old.isEmpty else { continue }
            var arch = DB.store.get([CachedLog].self, "kf_logarch_" + kc.mac) ?? []
            arch.insert(contentsOf: old, at: 0)
            if arch.count > 400 { arch = Array(arch.prefix(400)) }
            DB.store.setCodable("kf_logarch_" + kc.mac, arch)
            let ids = Set(old.map { $0.idxRaw })
            let kept = all.filter { !ids.contains($0.idxRaw) }
            moved += old.count
            DB.writeLogs(kc.mac, kept.map { LogEntry(type: $0.type, typeName: $0.typeName, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") })
        }
        return moved
    }
    static func archivedCount(_ mac: String) -> Int {
        DB.store.get([CachedLog].self, "kf_logarch_" + mac)?.count ?? 0
    }
}

// ---------- 149/150/160/545/760 一键体检引擎 (8 项, 单项可复测) ----------
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
enum DiagHealth {
    struct ItemDef {
        let id: String
        let name: String
        let run: () -> HealthCheckItem
    }
    /// 545 能力自检清单 + 760 运行自检共用同一套项 (蓝牙/通知/应用锁/存储/备份/连接/数据/触感)
    static var items: [ItemDef] {
        [ItemDef(id: "ble", name: "蓝牙权限") { checkBLE() },
         ItemDef(id: "notify", name: "本地通知") { checkNotify() },
         ItemDef(id: "applock", name: "本机密码") { checkAppLock() },
         ItemDef(id: "storage", name: "存储余量") { checkStorage() },
         ItemDef(id: "backup", name: "备份新鲜度") { checkBackup() },
         ItemDef(id: "conn", name: "门锁连接") { checkConn() },
         ItemDef(id: "data", name: "数据完整性") { checkData() },
         ItemDef(id: "haptic", name: "触感反馈") { checkHaptic() }]
    }
    /// 149 一键体检: 全量跑一遍出总分 (每项 20 / 警告 10)
    static func runAll() -> (score: Int, items: [HealthCheckItem]) {
        let list = items.map { $0.run() }
        let raw = list.reduce(0) { $0 + ($1.ok ? 20 : 10) }
        return (Int(Double(raw) / 10), list)
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
    private static let probe = CBCentralManager()
    static func checkBLE() -> HealthCheckItem {
        let auth = CBCentralManager.authorization
        if auth == .denied {
            return HealthCheckItem(id: "ble", name: "蓝牙权限", ok: false,
                                   detail: "蓝牙权限被拒绝 — 到 设置 → 离线锁管家 → 蓝牙 开启后复测")
        }
        let on = probe.state == .poweredOn
        return HealthCheckItem(id: "ble", name: "蓝牙权限", ok: on,
                               detail: on ? "蓝牙已开启, 可正常连接门锁" : "蓝牙未开启 — 控制中心打开蓝牙后点「重测」")
    }
    static func checkNotify() -> HealthCheckItem {
        switch UNUserNotificationCenter.current().notificationSettings.authorizationStatus {
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
            return HealthCheckItem(id: "storage", name: "存储余量", ok: true, detail: "未知")
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
        let days = Date().timeIntervalSince1970 - last / 1000 / 86_400
        let ok = days < 30
        return HealthCheckItem(id: "backup", name: "备份新鲜度", ok: ok,
                               detail: String(format: "上次备份 %.0f 天前", days) + (ok ? "" : " — 超过 30 天, 建议补一次"))
    }
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
        let on = UIImpactFeedbackGenerator(style: .light).isEnabled
        return HealthCheckItem(id: "haptic", name: "触感反馈", ok: on,
                               detail: on ? "触感引擎可用" : "系统触感关闭 — 设置 → 辅助功能 → 触感反馈")
    }
}

// ---------- 753 诊断摘要二维码 (CoreImage 本地生成, 扫码即得本机可读文本) ----------
enum DiagQR {
    static func image(for text: String) -> UIImage? {
        var filter: CIFilter! = CIFilter(name: "CIQRCodeGenerator")
        guard let input = filter, let data = text.data(using: .utf8) else { return nil }
        input.setValue(data, forKey: "inputMessage")
        input.setValue("M", forKey: "inputCorrectionLevel")
        guard let raw = input.outputImage else { return nil }
        let rect = raw.extent
        let small = raw.cropped(to: CGRect(x: rect.minX, y: rect.minY, width: 1, height: 1))
        let scale: CGFloat = 480 / 1
        let big = small.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = big.imageRepresentation?.takeUnretainedValue() else { return nil }
        return UIImage(cgImage: cg)
    }
    /// 摘要文本: 版本 + 固件 + 最近错误 + 日志摘要哈希 (SHA256 前 6 字节, 12 hex)
    static func summaryText(app: AppState) -> String {
        var t = "【诊断摘要】\n"
        t += "App " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))\n"
        t += "系统 " + UIDevice.current.systemName + " " + UIDevice.current.systemVersion + "\n"
        if let kc = app.current {
            t += "门锁 " + app.displayName + " pid=" + String(kc.pid) + " 固件 " + (kc.fw.isEmpty ? "未知" : kc.fw) + "\n"
        } else {
            t += "门锁 未配对\n"
        }
        if !app.lock.lastError.isEmpty { t += "最近错误 " + app.lock.lastError + "\n" }
        let tail = DiagLogs.today().suffix(30).map { $0.time + "[" + $0.level + "] " + $0.msg }.joined(separator: "\n")
        let hash = SHA256(tail.utf8).prefix(6).map { String(format: "%02x", $0) }.joined()
        t += "日志摘要 " + hash
        return t
    }
}

// ---------- 754 协议字段字典 (CAPABILITY.md 内容内置, 可查可复制) ----------
enum ProtocolDict {
    struct Field: Identifiable {
        let k: String
        let name: String
        let desc: String
        var id: String { k + name }
    }
    static let statusFields: [Field] = [
        .init(k: "#01", name: "sKeyStatus", desc: "密钥状态 (1=清除态 / 2=ECDH)"),
        .init(k: "#03", name: "rc", desc: "总返回码, 0 成功; 1-27 锁端错误码 (对照错误码人话表)"),
        .init(k: "#04", name: "lockTime", desc: "锁内时钟, 协议秒 (基准 2010-01-01), 0 视为无效"),
        .init(k: "#05", name: "zotpPeriod", desc: "临时码周期, 单位分钟, 默认 30"),
        .init(k: "#06", name: "keyboardFreeze", desc: "键盘冻结标志"),
        .init(k: "#07", name: "keyboardErrCount", desc: "密码连续错误次数"),
        .init(k: "#08", name: "securityLevel", desc: "位域: bit0 单双验 / bit1 状态广播 / bit2 临时码开通"),
        .init(k: "#11", name: "powerLevel", desc: "电量百分比"),
        .init(k: "#14", name: "soundVolumn", desc: "音量, 0=有声 / 1=静音"),
        .init(k: "#21-23", name: "pinInfo", desc: "PIN 池 容量/剩余/绑定数"),
        .init(k: "#24-26", name: "pwdInfo", desc: "密码 容量/剩余/最大长度"),
        .init(k: "#27-29", name: "fpInfo", desc: "指纹 容量/剩余/批号"),
        .init(k: "#31", name: "verFirmware", desc: "固件 3B 反转直读 a.b.c"),
        .init(k: "#34", name: "pid", desc: "型号号, 映射见诊断页型号映射 (661)"),
        .init(k: "#35", name: "eCtrlVer", desc: "电控板版本, ASCII"),
        .init(k: "16#04", name: "surplus", desc: "GETLOG 剩余日志条数 (749 完整性校验依此对账)"),
        .init(k: "16#05", name: "logRec", desc: "日志条目: type 1B + len 1B + idx 4B LE + lockTime 4B LE")
    ]
    static let logTypes: [(Int, String)] = {
        StatusParser.logTypes.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }()
    static func copyable() -> String {
        statusFields.map { $0.k + " " + $0.name + " — " + $0.desc }.joined(separator: "\n")
    }
}

// ---------- 662 图标语义表 (SF Symbols 集中映射, 防漂移) ----------
enum IconSemantics {
    struct Row: Identifiable {
        let icon: String
        let use: String
        var id: String { icon }
    }
    static let rows: [Row] = [
        Row(icon: "fingerprint", use: "指纹凭证 / 录指纹"),
        Row(icon: "keyboard", use: "密码凭证 / 键盘输入"),
        Row(icon: "exclamationmark.triangle", use: "胁迫码 / 告警提示"),
        Row(icon: "shield.fill", use: "防撬 / 布防 / 安全中心"),
        Row(icon: "lock.fill", use: "门锁主体 / 设备 Tab"),
        Row(icon: "key.horizontal.fill", use: "凭证 Tab / 密码开门"),
        Row(icon: "list.bullet.rectangle.fill", use: "记录 Tab"),
        Row(icon: "gearshape.fill", use: "设置 Tab"),
        Row(icon: "bolt.fill", use: "电量 / 低电告警"),
        Row(icon: "network", use: "BLE 连接状态"),
        Row(icon: "archivebox.fill", use: "备份 / 归档"),
        Row(icon: "stethoscope", use: "诊断 / 体检"),
        Row(icon: "stop.circle.fill", use: "静默排查模式"),
        Row(icon: "chart.bar.fill", use: "统计 / 成功率"),
        Row(icon: "qrcode", use: "诊断摘要二维码"),
        Row(icon: "doc.text.magnifyingglass", use: "日志检索")
    ]
}

// ---------- 762 白名单查询模板 (只读下拉, 不开放自由输入) ----------
enum QueryTemplates {
    struct Result { let title: String; let lines: [String] }
    static func lastNLogs(_ n: Int) -> Result {
        let mac = DB.currentMac
        let logs = DB.readLogs(mac).prefix(n)
        return Result(title: "「\(mac.prefix(6))」最近 \(n) 条日志",
                      lines: logs.map { String($0.lockTimeStr.prefix(16)) + " " + $0.typeName })
    }
    static func byType(_ types: [Int]) -> Result {
        let mac = DB.currentMac
        let names = Set(types.map { StatusParser.logTypes[$0] ?? "未知(\($0))" })
        let logs = DB.readLogs(mac).filter { names.contains($0.typeName) }
        return Result(title: "按类型: " + types.map { String($0) }.joined(separator: "/"),
                      lines: logs.prefix(30).map { String($0.lockTimeStr.prefix(16)) + " " + $0.typeName })
    }
    static func memberUsage() -> Result {
        let l = DB.ledger(DB.currentMac)
        let rows = DB.members().map { m in
            let p = l.pwds.filter { $0.owner == m.id }.count
            let f = l.fps.filter { $0.owner == m.id }.count
            return "\(m.name): 密码 \(p) · 指纹 \(f)"
        }
        return Result(title: "成员凭证用量 (当前锁)", lines: rows)
    }
    static func recentFails() -> Result {
        let ev = DB.failEvents(DB.currentMac).prefix(10)
        return Result(title: "最近开锁失败", lines: ev.map {
            Date(timeIntervalSince1970: $0.ts).formatted(.dateTime.month().day().hour().minute()) + " " + $0.msg
        })
    }
}

// ---------- 740 原始报文查看 (hex dump, 常开入口; Debug 友好) ----------
enum HexDump {
    static func dump(_ hex: String, lineLen: Int = 32) -> String {
        var out: [String] = []
        let s = String(hex.uppercased()).filter { $0.isLetter || $0.isNumber }
        var i = 0
        while i < s.count {
            let start = s.index(s.startIndex, offsetBy: i)
            let n = min(lineLen, s.distance(from: start, to: s.endIndex))
            out.append(String(format: "%08d", i) + "  " + String(s[start..<s.index(start, offsetBy: n)]))
            i += lineLen
        }
        return out.isEmpty ? "(无数据)" : out.joined(separator: "\n")
    }
}

// ---------- 282 症状向导 (故障树, 本地词表) ----------
enum SymptomGuide {
    struct Step {
        let question: String
        let yesNext: [String]   // 下一步的 step id
        let noNext: [String]
        var conclusion: String? = nil
    }
    static let lockOpen: [String: Step] = [
        "q1": Step(question: "手机蓝牙是否已开启?",
                   yesNext: ["q2"], noNext: ["done_ble"]),
        "q2": Step(question: "手机是否紧贴门锁 (1 米内)?",
                   yesNext: ["q3"], noNext: ["done_dist"]),
        "q3": Step(question: "门锁是否通电 (键盘有反应)?",
                   yesNext: ["q4"], noNext: ["done_power"]),
        "q4": Step(question: "刚才是否提示「锁正忙」或「通讯过期」?",
                   yesNext: ["done_busy"], noNext: ["q5"]),
        "q5": Step(question: "换条凭证/重新添加一次还失败吗?",
                   yesNext: ["done_firmware"], noNext: ["done_fixed"]),
        "done_ble": Step(question: "", yesNext: [], noNext: [], conclusion: "蓝牙未开 — 控制中心打开蓝牙即可, 无需修复门锁"),
        "done_dist": Step(question: "", yesNext: [], noNext: [], conclusion: "距离太远 — 靠近到 1 米内重试, 蓝牙近场协议在墙外信号极弱"),
        "done_power": Step(question: "", yesNext: [], noNext: [], conclusion: "门锁断电 — 检查电池仓, 部分锁断电会清键盘输入缓冲"),
        "done_busy": Step(question: "", yesNext: [], noNext: [], conclusion: "锁正忙或时钟偏差 — 先在快捷操作「校准时间」, 等 10 秒再开"),
        "done_firmware": Step(question: "", yesNext: [], noNext: [], conclusion: "大概率凭证与锁状态不同步 — 到诊断页拉一次日志, 看「最近错误」并重新下发凭证; 仍不行可试固件更新"),
        "done_fixed": Step(question: "", yesNext: [], noNext: [], conclusion: "已恢复 — 这次成功说明是偶发链路抖动, 关注是否再次出现")
    ]
    static let bleConnect: [String: Step] = [
        "q1": Step(question: "手机能搜到「ZkDFU」以外的其它蓝牙设备吗?",
                   yesNext: ["q2"], noNext: ["done_bt"]),
        "q2": Step(question: "门锁的广播名/型号是否与本 App 记录一致?",
                   yesNext: ["q3"], noNext: ["done_repair"]),
        "q3": Step(question: "反复重连 3 次以上仍超时?",
                   yesNext: ["done_watchdog"], noNext: ["done_wait"]),
        "done_bt": Step(question: "", yesNext: [], noNext: [], conclusion: "手机蓝牙本身异常 — 开关一次蓝牙再试, 或重启手机"),
        "done_repair": Step(question: "", yesNext: [], noNext: [], conclusion: "档案与实物对不上 — 删除该锁重新配对 (本地钥匙串会同步更新)"),
        "done_watchdog": Step(question: "", yesNext: [], noNext: [], conclusion: "连接不稳 — 看诊断页「BLE 事件流水」与失败归类, 建议先查电量; 可启用看门狗自动重连"),
        "done_wait": Step(question: "", yesNext: [], noNext: [], conclusion: "偶发超时属正常 — 蓝牙近场受干扰常见, 保持 1 米内重试即可")
    ]
    static let records: [String: Step] = [
        "q1": Step(question: "「记录」页顶部是否显示过离线/未连接横幅?",
                   yesNext: ["q2"], noNext: ["q3"]),
        "q2": Step(question: "手动点一次「重新读取」能出记录吗?",
                   yesNext: ["done_offline"], noNext: ["done_fetchfail"]),
        "q3": Step(question: "刚发生的开门是否也读不到?",
                   yesNext: ["done_gap"], noNext: ["done_ok"]),
        "done_offline": Step(question: "", yesNext: [], noNext: [], conclusion: "上次读的时候没连接上 — 靠近门锁点「重新读取」即可, 记录一直在锁里"),
        "done_fetchfail": Step(question: "", yesNext: [], noNext: [], conclusion: "读取失败 — 跑一次一键体检, 优先看「蓝牙权限/门锁连接」两项"),
        "done_gap": Step(question: "", yesNext: [], noNext: [], conclusion: "锁端日志有上限会滚动 — 早期记录被新记录顶掉了, 属正常; 重要记录当时导出备份即可"),
        "done_ok": Step(question: "", yesNext: [], noNext: [], conclusion: "数据完整 — 记录读取正常")
    ]
}
