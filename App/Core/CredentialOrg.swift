// 包6 凭证列表·批量·流转 — 本地组织层 (纯本地数据, 不碰协议命令集, 不读 vendor/)
// 新增表全部 kf_ 前缀, 与既有 kf_ledger_ / kf_members 同库, 不进备份包 schema (492 留包8 勾选):
//   kf_chist_<mac>        487/488 版本快照 (保存自动快照 + 自动还原点置顶标记)
//   kf_cbin_<mac>        497-506 回收站 (来源过滤 / 剩余天数 / 彻底删除)
//   kf_cqueue_<mac>      365 下发状态队列 (本地容错步条: 待下发→已下发→锁端确认, 不改协议层)
//   kf_cstar_<mac>       526/921 置顶星标 + 921 高频标记
//   kf_calert_<mac>      359 三档预警设定
//   kf_clists_<mac>      527 命名智能列表
//   kf_cseq_<mac>        182/352 拖拽排序序
//   kf_ccred_prefs       355/914 双视图分组与四维排序的持久化
//   kf_calias_display    919 别名显示切换 (全局)
//   kf_csearch_hist      531 最近搜索词
//   kf_cbin_reclaim_days 497 回收站保留天数 (设置可改)
// 展示层语义: 一次性/周期/暂停锁端协议未定义 (CAPABILITY §4) — 全部按时间窗推断, 标注"约"。
import Foundation
import SwiftUI
import UserNotifications

// ================= 数据模型 =================
/// 487/489/490/495/496 版本快照: 值/时段/备注逐字段对齐, 供 diff 与"恢复即新版本"
struct CredSnapshot: Codable {
    var version: Int
    var at: Double              // Unix 秒
    var note: String            // 人话摘要 (490), 由 makeSummary 生成
    var starred: Bool = false   // 495 星标版不受配额淘汰
    var auto: Bool = false      // 488 自动还原点 (还原备份/批量操作前) 置顶加标记
    var pwd: LedgerPwd?
    var fp: LedgerFp?
}
/// 498 来源过滤: 手动删除 / 批量清理 / 过期清理 / 重录替代
enum CredBinSource: Int, Codable, CaseIterable {
    case manual = 0, batch = 1, expired = 2, rererecord = 3
    var label: String {
        switch self {
        case .manual: return "手动删除"
        case .batch: return "批量清理"
        case .expired: return "过期清理"
        case .rererecord: return "重录替代"
        }
    }
}
/// 497-502 回收站条目
struct CredBinEntry: Codable, Identifiable {
    var at: Double
    var source: Int                 // CredBinSource.rawValue
    var pwd: LedgerPwd? = nil
    var fp: LedgerFp? = nil
    var id: String {
        at > 0 ? "\(at)" : (pwd?.alias.map { "\($0)" } ?? fp?.batch.map { "\($0)" } ?? "bin")
    }
    /// 行首文案 (回收站/撤销条共用)
    var text: String {
        if let p = pwd { return "密码 #\(p.alias)" + (p.temp ? " (一次性)" : "") }
        if let f = fp { return "指纹「\(f.name)」" }
        return "凭证"
    }
    var sourceName: String { CredBinSource(rawValue: source)?.label ?? "手动删除" }
}
/// 365 下发状态 (本地容错态): 待下发 → 已下发 → 锁端确认 (rc@#03)
enum CredQueueState: Int, Codable {
    case pending = 0, done = 1, failed = 2
}
/// 365 队列条目: kind 决定重试时下发哪条既有命令, 不新增协议指令
struct CredQueueItem: Codable, Identifiable {
    var id: Int
    var kind: String      // "del_pwd"/"del_fp"/"period"/"restore"/"copy"
    var title: String     // 行内一句话 (如 "删除密码 #3")
    var pwd: LedgerPwd?   // 载荷 (本地值, 重试时重新走既有 LockService 命令)
    var fp: LedgerFp?
    var newFrom: String = ""
    var newTo: String = ""
    var state: Int
    var attempt: Int = 0
    var lastAt: Double = 0
}
struct CredAlert: Codable {
    var day: Bool = false
    var h24: Bool = false
    var h2: Bool = false
}
/// 527 命名智能列表: 常用筛选组合存为具名快捷
struct CredSmartList: Codable, Identifiable {
    var id: String
    var name: String
    var kind: String     // "all"/"pwd"/"fp"
    var owner: String    // "" = 不限
    var state: String    // "active"/"scheduled"/"expired"/""
    var tag: String      // "stale" 老旧值 / "noowner" 无归属
}
/// 四维排序 (914): 名称 / 类型 / 最近使用 / 到期
enum CredSortKey: Int, CaseIterable {
    case name = 0, type, recent, expiry
    var label: String {
        switch self {
        case .name: return "名称"
        case .type: return "类型"
        case .recent: return "最近使用"
        case .expiry: return "到期"
        }
    }
}
enum CredGroupMode: Int { case type, owner }

// ================= 组织层 =================
enum CredentialOrg {
    // ---------- 键 ----------
    static func histKey(_ mac: String, _ kind: String, _ key: Int) -> String { "kf_chist_\(mac)_\(kind)_\(key)" }
    static func binKey(_ mac: String) -> String { "kf_cbin_" + mac }
    static func queueKey(_ mac: String) -> String { "kf_cqueue_" + mac }
    static func starKey(_ mac: String) -> String { "kf_cstar_" + mac }
    static func alertKey(_ mac: String, _ kind: String, _ key: Int) -> String { "kf_calert_\(mac)_\(kind)_\(key)" }
    static func listsKey(_ mac: String) -> String { "kf_clists_" + mac }
    static func seqKey(_ mac: String) -> String { "kf_cseq_" + mac }

    // ---------- 时间解析 (台账串 "yyyy-MM-dd HH:mm:ss", 本地时区) ----------
    static let credFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    static func parseLocal(_ s: String) -> Date? {
        let t = String(s.prefix(19))
        return credFormatter.date(from: t)
    }
    /// 永久有效期 (2118) 返回 nil — 不参与到期排序与预警
    static func expiryDate(_ p: LedgerPwd) -> Date? {
        guard !p.to.hasPrefix("2118") else { return nil }
        return parseLocal(p.to)
    }
    static var nowSec: Double { Date().timeIntervalSince1970 }

    // ---------- 487/488/491/495 版本历史 ----------
    static func history(_ mac: String, _ kind: String, _ key: Int) -> [CredSnapshot] {
        DB.get([CredSnapshot].self, histKey(mac, kind, key)) ?? []
    }
    static func quota(_ mac: String) -> Int { DB.store.getInt("kf_ccred_quota", 10) }
    /// 487 保存自动快照: 每凭证保留 N 版, 超限滚动淘汰最旧 (495 星标版豁免;
    /// 488 自动还原点: auto 快照不计入配额, 始终保留最近 2 个, 历史页置顶加标记)
    static func snapshot(_ mac: String, kind: String, key: Int, pwd: LedgerPwd?, fp: LedgerFp?,
                         note: String, starred: Bool = false, auto: Bool = false) {
        var list = history(mac, kind, key)
        let v = (list.last?.version ?? 0) + 1
        let snap = CredSnapshot(version: v, at: nowSec, note: note, starred: starred, auto: auto, pwd: pwd, fp: fp)
        list.append(snap)
        let autos = list.filter { $0.auto }
        let autosKeep = Array(autos.suffix(2))                       // 488 自动还原点 2 席
        var manual = list.filter { !$0.auto }                        // 配额域 = 手动快照
        let cap = quota(mac)
        if manual.count > cap {
            // 保留: 星标版 + 最近 N-星标数 条普通版
            let kept = manual.filter { $0.starred }
            let plain = manual.filter { !$0.starred }
            let room = max(cap - kept.count, 0)
            manual = kept + Array(plain.suffix(room))
        }
        let out = manual + autosKeep
        DB.setCodable(out, histKey(mac, kind, key))
    }
    static func latest(_ mac: String, kind: String, _ key: Int) -> CredSnapshot? {
        history(mac, kind, key).last
    }
    static func saveHistory(_ mac: String, _ kind: String, _ key: Int, _ list: [CredSnapshot]) {
        DB.setCodable(list, histKey(mac, kind, key))
    }
    /// 496 恢复即新版本: 不覆盖, 按基线 s 复制回台账, 并新增一条 "恢复自 v(s)" 快照
    static func restore(_ mac: String, kind: String, key: Int, from s: CredSnapshot) {
        if let p = s.pwd { DB.addPwd(mac, p) }
        if let f = s.fp { DB.addFp(mac, f) }
        snapshot(mac, kind: kind, key: key, pwd: s.pwd, fp: s.fp, note: "恢复自 v\(s.version)", starred: true)
    }
    /// 494 删除前快照: 双通道可找回 (历史 + 回收站)
    static func snapshotBeforeDelete(_ mac: String, pwd: LedgerPwd?, fp: LedgerFp?) {
        if let p = pwd { snapshot(mac, kind: "pwd", key: p.alias, pwd: p, fp: nil, note: "删除前快照") }
        if let f = fp { snapshot(mac, kind: "fp", key: f.batch, pwd: nil, fp: f, note: "删除前快照") }
    }

    // ---------- 489 修订着色 diff (删除红/新增绿/修改黄, 逐字段对齐) ----------
    struct Diff: Identifiable {
        var id: String { label }
        let label: String
        let old: String
        let neu: String
        var kind: String {
            if old.isEmpty { return "add" }
            if neu.isEmpty { return "del" }
            return old == neu ? "same" : "mod"
        }
    }
    static func diff(_ a: CredSnapshot?, _ b: CredSnapshot) -> [Diff] {
        var rows: [Diff] = []
        func add(_ label: String, _ old: String, _ neu: String) { rows.append(Diff(label: label, old: old, neu: neu)) }
        if a == nil {
            add("整条记录", "", summaryText(of: b))
            return rows
        }
        if let pa = a!.pwd, let pb = b.pwd {
            add("密码值", pa.pwd ?? "·", pb.pwd ?? "·")
            add("有效期起", pa.from, pb.from)
            add("有效期止", pa.to, pb.to)
            add("类型", pa.temp ? "临时密码" : "长期密码", pb.temp ? "临时密码" : "长期密码")
            add("备注", pa.note, pb.note)
            let oa = pa.owner.flatMap { DB.member($0)?.name } ?? ""
            let ob = pb.owner.flatMap { DB.member($0)?.name } ?? ""
            add("归属", oa.isEmpty ? "未归属" : oa, ob.isEmpty ? "未归属" : ob)
        } else if let fa = a!.fp, let fb = b.fp {
            add("名称", fa.name, fb.name)
            add("备注", fa.note, fb.note)
            add("预警", fa.isAlarm == true ? "预警指纹" : "普通", fb.isAlarm == true ? "预警指纹" : "普通")
            let oa = fa.owner.flatMap { DB.member($0)?.name } ?? ""
            let ob = fb.owner.flatMap { DB.member($0)?.name } ?? ""
            add("归属", oa.isEmpty ? "未归属" : oa, ob.isEmpty ? "未归属" : ob)
        }
        return rows
    }
    static func summaryText(of s: CredSnapshot) -> String {
        var parts: [String] = []
        if let p = s.pwd {
            parts.append(p.temp ? "临时密码 #\(p.alias)" : "密码 #\(p.alias)")
            if p.to.hasPrefix("2118") { parts.append("长期有效") }
            else if let d = parseLocal(p.to) { parts.append("到 \(d.formatted(.dateTime.month().day().hour().minute()))") }
        }
        if let f = s.fp { parts.append("指纹「\(f.name)」") }
        return parts.joined(separator: " · ")
    }

    // ---------- 497-506 回收站 ----------
    static func bin(_ mac: String) -> [CredBinEntry] {
        DB.get([CredBinEntry].self, binKey(mac)) ?? []
    }
    static func saveBin(_ mac: String, _ list: [CredBinEntry]) {
        DB.setCodable(list, binKey(mac))
    }
    static func binPwd(_ mac: String, _ alias: Int) -> LedgerPwd? { bin(mac).compactMap { $0.pwd }.first { $0.alias == alias } }
    static func binFp(_ mac: String, _ batch: Int) -> LedgerFp? { bin(mac).compactMap { $0.fp }.first { $0.batch == batch } }
    static func addToBin(_ mac: String, pwd: LedgerPwd? = nil, fp: LedgerFp? = nil, source: CredBinSource) {
        snapshotBeforeDelete(mac, pwd: pwd, fp: fp)   // 494 删除前快照先落
        var list = bin(mac)
        list.insert(CredBinEntry(at: nowSec, source: source.rawValue, pwd: pwd, fp: fp), at: 0)
        saveBin(mac, list)
    }
    /// 506 误删撤销: 原位还原不入回收站 — 撤销 = 从回收站取出放回
    @discardableResult
    static func undoBin(_ mac: String, entry: CredBinEntry) -> Bool {
        var list = bin(mac)
        guard let i = list.firstIndex(where: { $0.id == entry.id }) else { return false }
        var e = list.remove(at: i)
        saveBin(mac, list)
        if let p = e.pwd { DB.addPwd(mac, p) }
        if let f = e.fp { DB.addFp(mac, f) }
        return true
    }
    /// 499 还原冲突副本: 同 ID 已存在时, 加 "还原-" 前缀别名还原
    static func restoreBin(_ mac: String, entry: CredBinEntry, asCopy: Bool) -> String {
        var list = bin(mac)
        list.removeAll { $0.id == entry.id }
        saveBin(mac, list)
        var msg = "已还原"
        if let p = entry.pwd {
            var cp = p
            let clash = DB.ledger(mac).pwds.contains { $0.alias == cp.alias }
            if asCopy || clash {
                cp.note = "还原-" + cp.note
                msg = "已还原为副本 (备注加「还原-」前缀)"
            }
            DB.addPwd(mac, cp)
        }
        if let f = entry.fp {
            var cp = f
            let clash = DB.ledger(mac).fps.contains { $0.batch == cp.batch }
            if asCopy || clash {
                cp.name = "还原-" + cp.name
                msg = "已还原为副本 (名称加「还原-」前缀)"
            }
            DB.addFp(mac, cp)
        }
        return msg
    }
    static func purgeBin(_ mac: String, id: String) {
        saveBin(mac, bin(mac).filter { $0.id != id })
    }
    static func reclaimDays() -> Int { DB.store.getInt("kf_cbin_reclaim_days", 30) }
    /// 497 启动清理: 超保留期的条目自动清, 返回清掉的条数
    static func sweepReclaim(_ mac: String) -> Int {
        let keep = Double(reclaimDays()) * 86400
        var list = bin(mac)
        let cut = nowSec - keep
        let before = list.count
        list = list.filter { $0.at >= cut }
        saveBin(mac, list)
        return before - list.count
    }
    /// 500 容量头行: 条数 + 下次自动清理日期 (最老条目到保留期)
    static func binHeader(_ mac: String) -> (count: Int, nextClean: Date?) {
        let list = bin(mac)
        guard let oldest = list.map({ $0.at }).min() else { return (0, nil) }
        return (list.count, Date(timeIntervalSince1970: oldest + Double(reclaimDays()) * 86400))
    }
    /// 501 级联预告: 删除成员前列出名下将一并入回收站的凭证
    static func cascadePreview(_ memberID: String) -> (pwds: [LedgerPwd], fps: [LedgerFp]) {
        var pwds: [LedgerPwd] = [], fps: [LedgerFp] = []
        for kc in DB.keychains() where kc.mac != "" {
            pwds.append(contentsOf: DB.listPwds(kc.mac).filter { $0.owner == memberID })
            fps.append(contentsOf: DB.listFp(kc.mac).filter { $0.owner == memberID })
        }
        return (pwds, fps)
    }
    /// 501/349 成员删除: 名下凭证随成员入回收站 (整组同戳, 可整组还原)
    static func cascadeBinMember(_ mac: String, _ memberID: String) {
        for p in DB.listPwds(mac).filter({ $0.owner == memberID }) {
            var cp = p
            cp.owner = nil
            DB.delPwd(mac, p.alias)
            addToBin(mac, pwd: cp, source: .manual)
        }
        for f in DB.listFp(mac).filter({ $0.owner == memberID }) {
            var cp = f
            cp.owner = nil
            DB.delFp(mac, f.batch)
            addToBin(mac, fp: cp, source: .manual)
        }
    }
    /// 504 还原即重新下发: 在用 (未过期) 密码的本地删除项还原后并入队, 由 UI 询问"立即重新下发"
    static func queueRestore(_ mac: String, _ p: LedgerPwd) {
        guard let to = expiryDate(p), to.timeIntervalSinceNow > 0 else { return }
        var q = queue(mac)
        if !q.contains(where: { $0.kind == "restore" && $0.pwd?.alias == p.alias }) {
            q.insert(CredQueueItem(id: nextQueueId(mac), kind: "restore", title: "重新下发「\(displayPwd(p))」",
                                   pwd: p, state: CredQueueState.pending.rawValue), at: 0)
            saveQueue(mac, q)
        }
    }

    // ---------- 365 下发状态队列 (本地容错态, 重试走既有命令) ----------
    static func queue(_ mac: String) -> [CredQueueItem] {
        DB.get([CredQueueItem].self, queueKey(mac)) ?? []
    }
    static func saveQueue(_ mac: String, _ q: [CredQueueItem]) {
        DB.setCodable(q, queueKey(mac))
    }
    static func nextQueueId(_ mac: String) -> Int {
        (queue(mac).map { $0.id }.max() ?? 0) + 1
    }
    static func enqueue(_ mac: String, kind: String, title: String,
                        pwd: LedgerPwd? = nil, fp: LedgerFp? = nil,
                        newFrom: String = "", newTo: String = "") {
        var q = queue(mac)
        q.insert(CredQueueItem(id: nextQueueId(mac), kind: kind, title: title, pwd: pwd, fp: fp,
                               newFrom: newFrom, newTo: newTo, state: CredQueueState.pending.rawValue), at: 0)
        saveQueue(mac, q)
    }
    static func markQueue(_ mac: String, id: Int, state: CredQueueState, note: String) {
        var q = queue(mac)
        for i in q.indices where q[i].id == id {
            q[i].state = state.rawValue
            q[i].attempt += 1
            q[i].lastAt = nowSec
            q[i].title = note
        }
        saveQueue(mac, q)
    }
    static func pendingCount(_ mac: String) -> Int {
        queue(mac).filter { $0.state == CredQueueState.pending.rawValue || $0.state == CredQueueState.failed.rawValue }.count
    }
    /// 365 顶部徽标与队列页共用的"未完成"子集 (待下发 + 失败可重试)
    static func pendingQueue(_ mac: String) -> [CredQueueItem] {
        queue(mac).filter { $0.state != CredQueueState.done.rawValue }
    }
    /// 启动清理: 全锁回收站 497 保留期巡检 (LockKeeperApp.onLaunch 调用)
    @discardableResult
    static func launchTick() -> Int {
        var n = 0
        for kc in DB.keychains() { n += sweepReclaim(kc.mac) }
        scheduleMonthlySweep()   // 366 月度清理任务幂等排程
        return n
    }

    // ---------- 347/348/349/357 批量本地操作 (下发部分只入队, UI 标注本地意图) ----------
    /// 348 统一延期: 本地改写所选过期字段并留变更清单 (逐条入队, 到场后统一补发)
    static func batchExtend(_ mac: String, _ aliases: [Int], _ from: String, _ to: String) -> [Int] {
        var out: [Int] = []
        for a in aliases {
            guard let p = DB.ledger(mac).pwds.first(where: { $0.alias == a }) else { continue }
            snapshot(mac, kind: "pwd", key: a, pwd: p, fp: nil, note: "统一延期", auto: true)   // 488 批量前自动还原点
            DB.setPwdPeriod(mac, a, from, to)
            enqueue(mac, kind: "period", title: "延期 密码 #\(a)", pwd: LedgerPwd(alias: a, from: from, to: to, temp: p.temp, at: p.at), newFrom: from, newTo: to)
            out.append(a)
        }
        return out
    }
    /// 349 批量移交: 批量改归属 (本地台账), 各写一条本地记录 (锁端无归属字段)
    static func batchTransfer(_ mac: String, pwdAliases: [Int], fpBatches: [Int], to: String?) -> Int {
        var n = 0
        for a in pwdAliases {
            guard DB.ledger(mac).pwds.contains(where: { $0.alias == a }) else { continue }
            DB.setPwdOwner(mac, a, to)
            n += 1
        }
        for b in fpBatches {
            guard DB.ledger(mac).fps.contains(where: { $0.batch == b }) else { continue }
            DB.setFpOwner(mac, b, to)
            n += 1
        }
        return n
    }
    /// 357 前缀批量备注
    static func batchPrefixNote(_ mac: String, pwdAliases: [Int], fpBatches: [Int], prefix: String) -> Int {
        var n = 0
        var l = DB.ledger(mac)
        for i in l.pwds.indices where pwdAliases.contains(l.pwds[i].alias) && !(l.pwds[i].note.hasPrefix(prefix)) {
            l.pwds[i].note = prefix + l.pwds[i].note; n += 1
        }
        for i in l.fps.indices where fpBatches.contains(l.fps[i].batch) && !(l.fps[i].note.hasPrefix(prefix)) {
            l.fps[i].note = prefix + l.fps[i].note; n += 1
        }
        DB.saveLedger(mac, l)
        return n
    }
    /// 353 批量停用: 所选过期/老旧项本地移除并入回收站, 锁端删除入队
    static func batchDisable(_ mac: String, pwdAliases: [Int], fpBatches: [Int]) -> Int {
        var n = 0
        for a in pwdAliases {
            guard let p = DB.ledger(mac).pwds.first(where: { $0.alias == a }) else { continue }
            DB.delPwd(mac, a)
            addToBin(mac, pwd: p, source: .batch)
            enqueue(mac, kind: "del_pwd", title: "删除密码 #\(a)")
            n += 1
        }
        for b in fpBatches {
            guard let f = DB.ledger(mac).fps.first(where: { $0.batch == b }) else { continue }
            DB.delFp(mac, b)
            addToBin(mac, fp: f, source: .batch)
            enqueue(mac, kind: "del_fp", title: "删除指纹批次 \(b)")
            n += 1
        }
        return n
    }

    // ---------- 524/526/528 计数与三态 ----------
    static func typeCounts(_ mac: String) -> (all: Int, pwd: Int, fp: Int, otp: Int) {
        let pwds = DB.listPwds(mac), fps = DB.listFp(mac)
        return (pwds.count + fps.count, pwds.count, fps.count, DB.otpStatus(mac)?.on == true ? 1 : 0)
    }
    static func pwdState(_ p: LedgerPwd) -> Int {
        // 0 进行中 / 1 已排期 / 2 已过期 (按时间窗推断, 一次性语义锁端未定义故不区分)
        if let to = expiryDate(p), to.timeIntervalSinceNow <= 0 { return 2 }
        if let f = parseLocal(p.from), f.timeIntervalSinceNow > 0 { return 1 }
        return 0
    }
    static func groupCount(_ mac: String, state: Int) -> Int {
        DB.listPwds(mac).filter { pwdState($0) == state }.count
    }

    // ---------- 526/921 置顶星标 + 高频 ----------
    static func stars(_ mac: String) -> Set<Int> {
        DB.get([Int].self, starKey(mac)) ?? []
    }
    static func toggleStar(_ mac: String, _ kind: String, _ key: Int) {
        var s = stars(mac)
        let id = kind == "pwd" ? key : 100000 + key   // 指纹段偏移, 避免别名冲突
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        DB.setCodable(Array(s), starKey(mac))
    }
    static func isStarred(_ mac: String, _ kind: String, _ key: Int) -> Bool {
        stars(mac).contains(kind == "pwd" ? key : 100000 + key)
    }
    /// 921 高频标记: 台账可推断 (近 30 天开门类日志中命中时间窗次数最多的临时密码), 标"约"
    static func starSuggestion(_ mac: String) -> String? {
        let temps = DB.listPwds(mac).filter { $0.temp }
        let logs = DB.readLogs(mac).filter { $0.type == 2 || $0.type == 4 }
        guard !temps.isEmpty, !logs.isEmpty else { return nil }
        func inWindow(_ p: LedgerPwd, at t: Double) -> Bool {
            guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return false }
            return f.timeIntervalSince1970 <= t && t <= to.timeIntervalSince1970
        }
        var hits: [String: Int] = [:]
        for l in logs {
            let t = ZKProtocol.protoSecondsToMs(Int64(l.lockTime)) / 1000
            guard t >= nowSec - 30 * 86400 else { continue }
            for p in temps where inWindow(p, at: t) {
                hits["p\(p.alias)", default: 0] += 1
            }
        }
        guard let top = hits.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        return top.key
    }

    // ---------- 359 三档预警 (本地通知; 2 小时档做 App 内提醒行, 7 天/24 小时档排程) ----------
    static func alert(_ mac: String, _ p: LedgerPwd) -> CredAlert {
        DB.get(CredAlert.self, alertKey(mac, "pwd", p.alias)) ?? CredAlert()
    }
    static func saveAlert(_ mac: String, _ p: LedgerPwd, _ a: CredAlert) {
        DB.setCodable(a, alertKey(mac, "pwd", p.alias))
    }
    /// 7 天 / 24 小时两档按日历触发本地通知; 2 小时档 App 内巡检提醒 (跨 App 前后台均可达)
    static func scheduleAlerts(_ mac: String, _ p: LedgerPwd, _ a: CredAlert) {
        let c = UNUserNotificationCenter.current()
        let id = "c6.alert.\(mac).p\(p.alias)"
        for r in c.pendingRequests() where r.identifier == id || r.identifier.hasPrefix(id + ".") {
            c.removePendingNotificationRequests(withIdentifiers: [r.identifier])
        }
        guard let to = expiryDate(p), a.day || a.h24 else { return }
        let name = displayPwd(p)
        if a.day {
            addCalendar(id: id + ".d7", date: to.addingTimeInterval(-7 * 86400),
                        title: "密码临期", body: "\(name) 距到期还有 7 天, 记得续期或停用。")
        }
        if a.h24 {
            addCalendar(id: id + ".h24", date: to.addingTimeInterval(-86400),
                        title: "密码临期", body: "\(name) 距到期不足 24 小时。")
        }
    }
    private static func addCalendar(id: String, date: Date, title: String, body: String) {
        guard date > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        var comps = DateComponents()
        comps.date = date
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        Task { try? await UNUserNotificationCenter.current().add(req) }
    }
    /// App 内 2 小时档: 到期前 2 小时且开了 h2 的条数 (设备 Tab Hero 卡下插提醒行)
    static func dueSoonCount(_ mac: String) -> Int {
        let soon = nowSec + 2 * 3600
        return DB.listPwds(mac).filter { p in
            if let a = alert(mac, p), let to = expiryDate(p) {
                return a.h2 && to.timeIntervalSince1970 <= soon && to.timeIntervalSince1970 >= nowSec - 3600
            }
            return false
        }.count
    }

    // ---------- 358/505 整理建议中心 ----------
    struct Advice: Identifiable {
        let id: String
        let title: String
        let sub: String
        let icon: String
        let action: String   // "expired" / "dups" / "noowner" / "bin"
    }
    static func advice(_ mac: String) -> [Advice] {
        var out: [Advice] = []
        let expired = groupCount(mac, state: 2)
        if expired > 0 {
            out.append(Advice(id: "expired", title: "过期 \(expired) 条",
                              sub: "已过期凭证待清理或续期", icon: "clock.arrow.circlepath", action: "expired"))
        }
        var values: [String: [LedgerPwd]] = [:]
        for p in DB.listPwds(mac) where p.pwd != nil { values[p.pwd!, default: []].append(p) }
        let dups = values.values.filter { $0.count > 1 }.count
        if dups > 0 {
            out.append(Advice(id: "dups", title: "重复值 \(dups) 组",
                              sub: "多条台账同一密码, 可合并归属", icon: "plus.slash.minus", action: "dups"))
        }
        let noowner = DB.listPwds(mac).filter { $0.owner == nil }.count
        if noowner > 0 {
            out.append(Advice(id: "noowner", title: "无归属 \(noowner) 条",
                              sub: "未指定成员的凭证, 建议移交或停用", icon: "person.slash", action: "noowner"))
        }
        let binN = bin(mac).count
        if binN > 0 {
            out.append(Advice(id: "bin", title: "回收站 \(binN) 条可彻底清理",
                              sub: "超过 \(reclaimDays()) 天保留期将自动清除", icon: "trash", action: "bin"))
        }
        return out
    }
    /// 智能选取 (350 三按钮) 的集合定义: 已过期 / 同成员 / 同类型
    static func smartSet(_ mac: String, set: String, base: (pwd: [Int], fp: [Int])) -> (pwd: [Int], fp: [Int]) {
        switch set {
        case "expired":
            return (DB.listPwds(mac).filter { pwdState($0) == 2 }.map { $0.alias }, [])
        case "sameowner":
            guard let first = DB.listPwds(mac).filter({ base.pwd.contains($0.alias) }).first?.owner ?? DB.listFp(mac).filter({ base.fp.contains($0.batch) }).first?.owner else {
                return base }
            return (DB.listPwds(mac).filter { $0.owner == first }.map { $0.alias },
                    DB.listFp(mac).filter { $0.owner == first }.map { $0.batch })
        case "samekind":
            let anyPwd = !base.pwd.isEmpty
            return anyPwd ? (DB.listPwds(mac).map { $0.alias }, []) : ([], DB.listFp(mac).map { $0.batch })
        default:
            return base
        }
    }

    // ---------- 527 命名智能列表 ----------
    static func smartLists(_ mac: String) -> [CredSmartList] {
        DB.get([CredSmartList].self, listsKey(mac)) ?? []
    }
    static func saveSmartLists(_ mac: String, _ l: [CredSmartList]) {
        DB.setCodable(l, listsKey(mac))
    }
    static func matches(_ mac: String, _ l: CredSmartList) -> Bool {
        func test(_ p: LedgerPwd) -> Bool {
            if l.kind == "fp" { return false }
            if l.owner != "", p.owner != l.owner { return false }
            if !l.state.isEmpty, stateString(pwdState(p)) != l.state { return false }
            if l.tag == "stale" && p.at > 0 && nowSec - p.at > 365 * 86400 { return true }
            if l.tag == "noowner" && p.owner == nil { return true }
            return true
        }
        switch l.kind {
        case "fp":
            let fps = DB.listFp(mac).filter { l.owner.isEmpty || $0.owner == l.owner }
            if l.tag == "noowner" { return fps.contains { $0.owner == nil } }
            return !fps.isEmpty
        default:
            let pwds = DB.listPwds(mac)
            if l.tag == "stale" {
                return pwds.contains { p in p.at > 0 && nowSec - p.at > 365 * 86400 }
            }
            if l.tag == "noowner" {
                return pwds.contains { $0.owner == nil }
            }
            return pwds.contains { test($0) }
        }
    }
    static func smartListLabel(_ l: CredSmartList) -> String {
        var s = l.name.isEmpty ? "智能列表" : l.name
        if l.owner != "" { s += " · " + (DB.member(l.owner)?.name ?? l.owner) }
        if !l.state.isEmpty {
            s += " · " + ["active": "进行中", "scheduled": "已排期", "expired": "已过期"][l.state, default: l.state]
        }
        return s
    }

    // ---------- 355/914 组织偏好持久化 ----------
    static var groupMode: Int { DB.store.getInt("kf_ccred_prefs", 0) }
    static var sortKey: CredSortKey { CredSortKey(rawValue: DB.store.getInt("kf_ccred_sort", 3)) ?? .expiry }
    static var aliasDisplay: Bool { DB.store.getBool("kf_calias_display", true) }
    static func setGroupMode(_ v: Int) {
        var prefs = groupMode
        prefs = (prefs & ~1) | (v == 1 ? 1 : 0)
        DB.store.set("kf_ccred_prefs", prefs)
    }
    static func setSortKey(_ k: CredSortKey) { DB.store.set("kf_ccred_sort", k.rawValue) }

    // ---------- 182/352 拖拽排序序: "p"/"f" 段各自存 index→元素 数组 ----------
    static func seq(_ mac: String) -> [String: [Int]] {
        DB.get([String: [Int]].self, seqKey(mac)) ?? [:]
    }
    static func setSeq(_ mac: String, _ map: [String: [Int]]) {
        DB.setCodable(map, seqKey(mac))
    }

    // ---------- 531 最近搜索词 ----------
    static func searchHistory() -> [String] {
        DB.get([String].self, "kf_csearch_hist") ?? []
    }
    static func pushSearchHistory(_ q: String) {
        var list = Array(searchHistory().filter { $0 != q }.prefix(4))
        list.insert(q, at: 0)
        DB.setCodable(list, "kf_csearch_hist")
    }
    static func removeSearchHistory(_ q: String) {
        DB.setCodable(searchHistory().filter { $0 != q }, "kf_csearch_hist")
    }

    // ---------- 363 月历到期 (每日格右上角当日到期凭证数) ----------
    static func monthDeadlines(_ mac: String, year: Int, month: Int) -> [Date: Int] {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        guard let start = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return [:] }
        var out: [Date: Int] = [:]
        for p in DB.listPwds(mac) {
            guard let to = expiryDate(p),
                  cal.component(.year, from: to) == year,
                  cal.component(.month, from: to) == month,
                  let key = cal.date(from: DateComponents(year: year, month: month, day: cal.component(.day, from: to))) else { continue }
            out[key, default: 0] += 1
            _ = start
        }
        return out
    }
    static func dayDeadlines(_ mac: String, _ date: Date) -> [LedgerPwd] {
        let cal = Calendar.current
        return DB.listPwds(mac).filter { p in
            guard let to = expiryDate(p) else { return false }
            return cal.isDate(to, inSameDayAs: date)
        }
    }

    // ---------- 364 恢复窗口期 (7 天内可一键恢复, 超期需重新下发) ----------
    static func withinRecoverWindow(_ mac: String, entry: CredBinEntry) -> Bool {
        entry.at > 0 && nowSec - entry.at <= 7 * 86400
    }

    // ---------- 529 组尾统计 (基于台账推断, 标"约") ----------
    /// 近 N 天使用次数: 临时密码按时间窗命中开门日志 (type2/4) 计, 长期密码只在
    /// 锁内唯一且有归属时计 (推断口径, UI 必须带"约"字)。日志缺失返回 nil (不出行)。
    static func recentUseCount(_ mac: String, pwdAlias: Int, days: Int = 30) -> Int? {
        let p = DB.ledger(mac).pwds.first { $0.alias == pwdAlias }
        guard let p else { return nil }
        let logs = DB.readLogs(mac).filter { $0.type == 2 || $0.type == 4 }
        guard !logs.isEmpty else { return nil }
        var n = 0
        for l in logs {
            let t = ZKProtocol.protoSecondsToMs(Int64(l.lockTime)) / 1000
            guard t >= nowSec - Double(days) * 86400 else { continue }
            if p.temp {
                if let f = parseLocal(p.from), let to = parseLocal(p.to),
                   f.timeIntervalSince1970 <= t, t <= to.timeIntervalSince1970 { n += 1 }
            } else if p.owner != nil, l.type == 2 {
                let owned = DB.ledger(mac).pwds.filter { !$0.temp && $0.owner != nil }
                if owned.count == 1 { n += 1 }
            }
        }
        return n
    }

    // ---------- 351 合包导出: 仅凭证分区的最小 AES 信封 (口令由 UI 生成, 不走全量 schema) ----------
    struct CredPackage: Codable {
        var v: Int
        var mac: String
        var lockName: String
        var pwds: [LedgerPwd]
        var fps: [LedgerFp]
        var at: Double
    }
    /// 返回 (Base64 信封文本, 口令)。UI 用 ShareLink 发文本 + 口令单列展示, 不与凭证混排。
    static func exportPackage(_ mac: String, pwdAliases: [Int], fpBatches: [Int], password: String) -> (data: Data, size: Int)? {
        let l = DB.ledger(mac)
        let pwds = l.pwds.filter { pwdAliases.isEmpty || pwdAliases.contains($0.alias) }
        let fps = l.fps.filter { fpBatches.isEmpty || fpBatches.contains($0.batch) }
        guard !pwds.isEmpty || !fps.isEmpty else { return nil }
        let pkg = CredPackage(v: 1, mac: mac, lockName: LockArchive.displayName(DB.keychain(mac) ?? Keychain(mac: mac, skey: "")),
                              pwds: pwds, fps: fps, at: nowSec)
        guard let json = try? JSONEncoder().encode(pkg),
              let text = String(data: json, encoding: .utf8),
              let enc = try? CryptoBox.encryptText(text, password: password) else { return nil }
        return (Data(enc.utf8), pwds.count + fps.count)
    }

    // ---------- 366 月度清理任务 (每月 1 日 09:00 本地通知) ----------
    static func scheduleMonthlySweep() {
        var comps = DateComponents()
        comps.day = 1
        comps.hour = 9
        let c = UNMutableNotificationContent()
        c.title = "月度凭证清理"
        c.body = "上月有过期凭证待处理, 到「凭证」点「整理」一键清理。"
        let req = UNNotificationRequest(identifier: "c6.monthly", content: c,
                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        Task { try? await UNUserNotificationCenter.current().add(req) }
    }

    // ---------- 通知分派 (App 前台时由 didReceive 转发; 后台由系统弹出) ----------
    enum Action {
        case restoreBin(String)
        case openExpired
        case openCenter
        case retryQueue
    }
    static func handleNotificationAction(_ id: String, _ userInfo: [AnyHashable: Any]) -> Action? {
        if id.hasPrefix("c6.restore.") {
            let mac = id.dropFirst("c6.restore.".count).split(separator: ".")[0]
            return .restoreBin(String(mac))
        }
        switch id {
        case "c6.expired": return .openExpired
        case "c6.center": return .openCenter
        case "c6.queue": return .retryQueue
        default:
            if let act = userInfo["c6action"] as? String {
                switch act {
                case "expired": return .openExpired
                case "center": return .openCenter
                default: return nil
                }
            }
        }
        return nil
    }

    // ================= 包5 凭证工坊辅助 (纯本地推断, 不新增协议命令) =================
    // 展示层语义纪律: 锁端一次性/周期/暂停未定义 (CAPABILITY §4), 所有推断值 UI 必须带"约"字。

    // ---------- 304 全库重复拦截 ----------
    static func duplicatePwdValues(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        DB.listPwds(mac).filter { $0.pwd == value && $0.alias != excluding }
    }
    /// 跨锁同值 (304 "全库"), 供命中提示跳转
    static func duplicatePwdValuesAnyLock(_ value: String, excludingMac: String, excludingAlias: Int) -> [LedgerPwd] {
        var out: [LedgerPwd] = []
        for k in DB.keychains() {
            for p in DB.listPwds(k.mac) where p.pwd == value && !(k.mac == excludingMac && p.alias == excludingAlias) {
                out.append(p)
            }
        }
        return out
    }
    /// 314 前缀混淆: 同锁内其它密码前 4 位相同, 口头易混淆
    static func prefixConflict(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        guard value.count >= 4 else { return [] }
        let pre = value.prefix(4)
        return DB.listPwds(mac).filter { $0.alias != excluding && $0.pwd?.hasPrefix(pre) == true }
    }

    // ---------- 305 老旧巡检: 台账自记录修改时刻起算 (锁端无最后修改字段, 标"约") ----------
    static func pwdAgeDays(_ p: LedgerPwd) -> Int? {
        guard p.at > 0 else { return nil }
        return Int(max(0, (nowSec - p.at / 1000)) / 86400)
    }
    static func isStalePwd(_ p: LedgerPwd, days: Int = 180) -> Bool {
        (pwdAgeDays(p) ?? 0) > days
    }

    // ---------- 307 保存前逐位 diff: 改动位集合 (1 起; 长度变化补 "·" 对齐) ----------
    static func digitDiff(old: String, new: String) -> Set<Int> {
        var ch = Set<Int>()
        let n = max(old.count, new.count)
        for i in 0..<n {
            let a = i < old.count ? old[old.index(old.startIndex, offsetBy: i)] : " "
            let b = i < new.count ? new[new.index(new.startIndex, offsetBy: i)] : " "
            if a != b { ch.insert(i + 1) }
        }
        return ch
    }

    // ---------- 327 租期重叠检测 ----------
    static func overlapWindows(_ mac: String, from: String, to: String, owner: String?, excluding: Int) -> [LedgerPwd] {
        guard let f = parseLocal(from), let t = parseLocal(to) else { return [] }
        return DB.listPwds(mac).filter { p in
            p.alias != excluding &&
            (owner == nil || p.owner == owner) &&
            {
                guard let pf = parseLocal(p.from), let pt = parseLocal(p.to) else { return false }
                return pf < t && f < pt
            }()
        }
    }

    // ---------- 319 重录继承 / 324 冗余横条 ----------
    /// 该成员名下可用指纹数 (0 = 最后一枚 → 删除需双签 323; 冗余横条 324 用全锁口径)
    static func fpCountByOwner(_ mac: String, _ owner: String?) -> Int {
        guard let o = owner else { return 0 }
        return DB.listFps(mac).filter { $0.owner == o }.count
    }
    static func fpCountTotal(_ mac: String) -> Int { DB.listFps(mac).count }

    // ---------- 311/316/320/326/335/333 台账推断统计 (⚠ 全部标"约") ----------
    /// 311 同码引用: 时间窗内用它"开过的门"计数 (无 alias 日志字段, 按时间窗推断, 标"约")
    static func openCountInWindow(_ mac: String, p: LedgerPwd) -> Int {
        guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return 0 }
        return DB.readLogs(mac).filter { log in
            guard log.type == 2 || log.type == 4 else { return false }
            let t = ZKProtocol.protoSecondsToMs(Int64(log.lockTime)) / 1000
            return f.timeIntervalSince1970 <= t && t <= to.timeIntervalSince1970
        }.count
    }
    /// 316 档案三行统计 / 320 误识档案: 最近一次使用与近似误识 (type13 指纹告警, ⚠ 语义待实测)
    static func inferredLastUse(_ mac: String, pwdAlias: Int) -> Double? {
        guard let p = DB.ledger(mac).pwds.first(where: { $0.alias == pwdAlias }) else { return nil }
        var hit: Double? = nil
        for l in DB.readLogs(mac) where l.type == 2 || l.type == 4 {
            let t = ZKProtocol.protoSecondsToMs(Int64(l.lockTime)) / 1000
            if p.temp {
                if let f = parseLocal(p.from), let to = parseLocal(p.to),
                   f.timeIntervalSince1970 <= t, t <= to.timeIntervalSince1970 { hit = t }
            } else if hit == nil {
                hit = t
            }
        }
        return hit
    }
    /// 316 指纹档案统计: 近 30 天 type3 (指纹开门) 日志条数 — ⚠ 日志无指纹身份字段, 只能按锁整体推断, 标"约"
    static func fpUseCount30d(_ mac: String) -> Int {
        let cut = nowSec - 30 * 86400
        return DB.readLogs(mac).filter { l in
            guard l.type == 3 else { return false }
            return ZKProtocol.protoSecondsToMs(Int64(l.lockTime)) / 1000 >= cut
        }.count
    }
    /// 320 误识计数: 本地日志 type13 (指纹告警) 出现次数 — ⚠ 锁端语义待实测, 只做展示标"约"
    static func fpAlarmLogCount(_ mac: String) -> Int {
        DB.readLogs(mac).filter { $0.type == 13 }.count
    }
    /// 326/335 计次退役与用量刻度: 锁端无计次, 降级为本地 type4 临时码开门计数 (标"约")
    static func usageCount(_ mac: String, p: LedgerPwd) -> Int {
        guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return 0 }
        return DB.readLogs(mac).filter { log in
            guard log.type == 4 else { return false }
            let t = ZKProtocol.protoSecondsToMs(Int64(log.lockTime)) / 1000
            return f.timeIntervalSince1970 <= t && t <= to.timeIntervalSince1970
        }.count
    }
    /// 333 首用回执: 时间窗内最早一条开门日志 (⚠ 无 alias 字段, 按时间推断, 标"约")
    static func firstUse(_ mac: String, p: LedgerPwd) -> Double? {
        guard let f = parseLocal(p.from) else { return nil }
        var hit: Double? = nil
        for l in DB.readLogs(mac) where l.type == 2 || l.type == 4 {
            let t = ZKProtocol.protoSecondsToMs(Int64(l.lockTime)) / 1000
            if t >= f.timeIntervalSince1970 { hit = hit == nil ? t : min(hit!, t) }
        }
        return hit
    }

    // ---------- 315/174 指纹命名建议轮播 ----------
    /// 按该成员已录数量给 "成员·手指 (N)" 式建议; 手指序 食指→中指→备用→应急 循环 (315/174)
    /// extra = 轮播额外下标 (录入页同时给出 3 个备选)
    static func fpNameSuggestion(_ mac: String, owner: String?, extra: Int = 0) -> String {
        let who = ownerName(owner)
        let n = (owner.flatMap { fpCountByOwner(mac, $0) } ?? 0) + max(extra, 0)
        let names = ["食指", "中指", "备用", "应急"]
        let pick = names[n % names.count]
        let base = n > 0 ? pick + " (\(n + 1))" : pick
        return who.isEmpty ? "指纹·" + base : who + "·" + base
    }

    // ---------- 331 提前失效滑杆 (本地意图, 不改协议; 到点由巡检行提示停用) ----------
    static func earlyExpireMin(_ mac: String, _ alias: Int) -> Int {
        DB.store.getInt("kf_cestudy_earlyexp_" + mac + "_" + String(alias), 0)
    }
    static func setEarlyExpireMin(_ mac: String, _ alias: Int, _ m: Int) {
        DB.store.set("kf_cestudy_earlyexp_" + mac + "_" + String(alias), m)
    }

    // ---------- 341/343/346 OTP 独立口令组与静态备份码 (纯本地, 不走锁端) ----------
    struct TOTPEntry: Codable, Identifiable {
        var id: String
        var name: String
        var secret: String      // Base32
        var algo: String        // SHA1 / SHA256 / SHA512
        var period: Int        // 秒, 默认 30
        var digits: Int        // 默认 6
        var at: Double
    }
    struct StaticCode: Codable, Identifiable {
        var id: String
        var name: String
        var code: String
        var note: String
        var used: Bool
        var at: Double
    }
    static func totpKey(_ mac: String) -> String { "kf_cotp_t_" + mac }
    static func staticKey(_ mac: String) -> String { "kf_cotp_s_" + mac }
    static func totpEntries(_ mac: String) -> [TOTPEntry] {
        DB.get([TOTPEntry].self, totpKey(mac)) ?? []
    }
    static func addTotp(_ mac: String, _ e: TOTPEntry) {
        saveTotpEntries(mac, totpEntries(mac) + [e])
    }
    static func saveTotpEntries(_ mac: String, _ e: [TOTPEntry]) {
        DB.setCodable(e, totpKey(mac))
    }
    static func removeTotp(_ mac: String, _ id: String) {
        saveTotpEntries(mac, totpEntries(mac).filter { $0.id != id })
    }
    static func staticCodes(_ mac: String) -> [StaticCode] {
        DB.get([StaticCode].self, staticKey(mac)) ?? []
    }
    static func addStaticCode(_ mac: String, _ c: StaticCode) {
        saveStaticCodes(mac, staticCodes(mac) + [c])
    }
    static func saveStaticCodes(_ mac: String, _ c: [StaticCode]) {
        DB.setCodable(c, staticKey(mac))
    }
    static func removeStaticCode(_ mac: String, _ id: String) {
        saveStaticCodes(mac, staticCodes(mac).filter { $0.id != id })
    }

    // ---------- 337/171 独立 TOTP 时窗 (⚠ 锁端 ZOTP 为分钟级, 秒级仅独立口令) ----------
    static func totpRemaining(_ e: TOTPEntry) -> Int {
        let per = e.period > 0 ? e.period : 30
        return per - (Int(Date().timeIntervalSince1970) / per)
    }
    /// 345 参数小字: "SHA1·6位·30s"
    static func totpParams(_ e: TOTPEntry) -> String {
        e.algo + "·" + String(e.digits) + "位·" + String(e.period > 0 ? e.period : 30) + "s (独立口令, 约)"
    }

    // ---------- 518 草稿续填 (关闭自动保留, 成功保存即清) ----------
    struct StudioDraft: Codable {
        var step: Int
        var kind: Int          // 0 密码 / 1 临时码
        var pwd: String
        var permanent: Bool
        var fromISO: String
        var toISO: String
        var owner: String?
        var useTemplate: Bool
        var note: String
        var scene: String
        var batch: Int
        var at: Double
    }
    static func draft(_ mac: String) -> StudioDraft? {
        DB.get(StudioDraft.self, "kf_cdraft_" + mac)
    }
    static func saveDraft(_ mac: String, _ d: StudioDraft) {
        DB.setCodable(d, "kf_cdraft_" + mac)
    }
    static func clearDraft(_ mac: String) {
        DB.store.set("kf_cdraft_" + mac, Data())
    }

    // ---------- 显示层辅助 (919 别名显示切换: 成员"别名"字段 = relation 备注, 空则回退真名) ----------
    static func ownerName(_ id: String?) -> String {
        guard let id, let m = DB.member(id) else { return "" }
        if aliasDisplay, !m.relation.isEmpty { return m.relation }
        return m.name
    }
    static func displayPwd(_ p: LedgerPwd) -> String {
        if !p.note.isEmpty {
            let s = p.note.split(separator: "·").map { String($0).trimmingCharacters(in: .whitespaces) }.first
            if let s, !s.isEmpty, s.count <= 12 { return s }
        }
        if let o = ownerName(p.owner) { return "\(o) 的密码 #\(p.alias)" }
        return p.temp ? "临时密码 #\(p.alias)" : "密码 #\(p.alias)"
    }
    /// 918 命名模板 "谁-哪里-何时" 占位建议 (锁端无名称字段, 台账本地展示)
    static func namingTemplate(_ p: LedgerPwd) -> String {
        var who = ownerName(p.owner)
        var where_ = ""
        var when = "长期"
        if let to = expiryDate(p), let f = parseLocal(p.from) {
            when = f.formatted(.dateTime.month().day()) + "-" + to.formatted(.dateTime.month().day())
        }
        if who.isEmpty { who = "未归属" }
        if where_.isEmpty { where_ = "大门" }
        return [who, where_, when].joined(separator: "-")
    }
    /// 12 到期倒计时胶囊 (长期显示 "长期有效")
    static func countdown(_ p: LedgerPwd) -> String {
        guard let to = expiryDate(p) else { return "长期有效" }
        let d = to.timeIntervalSinceNow
        let day = Int(d / 86400)
        if d <= 0 { return "已过期 \(max(-day, 0)) 天" }
        if day >= 1 { return "剩 \(day) 天" }
        let h = Int(d / 3600)
        if h >= 1 { return "剩 \(h) 小时" }
        return "剩 \(Int(d / 60)) 分钟"
    }
    static func stateLabel(_ s: Int) -> String {
        switch s {
        case 1: return "已排期"
        case 2: return "已过期"
        default: return "进行中"
        }
    }
    /// 智能列表 state 字段用的机读串 (matches/label 共用)
    static func stateString(_ s: Int) -> String {
        switch s {
        case 1: return "scheduled"
        case 2: return "expired"
        default: return "active"
        }
    }
}

// 490 摘要句流的时间展示: 相对 + 绝对
extension CredSnapshot {
    var relTime: String {
        let d = Date(timeIntervalSince1970: at)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let diff = -d.timeIntervalSinceNow
        let abs = f.string(from: d)
        if diff < 60 { return "刚刚 · " + abs }
        if diff < 3600 { return "刚刚 · " + abs }
        return abs
    }
}
