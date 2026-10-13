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
import os   // 2026-10-13 对抗式排查: 凭证通知排期失败要能查 (原先 try? 静默吞掉)
// 502 彻底删除的统一门槛口 (guardedPurge) 要问生物识别, 所以本文件也吃这一套系统框架;
// 与 AccessibilityKit 的 AuthKit (877) 同源, 那边不复用的理由写在 guardedPurge 上方。
import LocalAuthentication

// ================= 数据模型 =================
/// 487/489/490/495/496 版本快照: 值/时段/备注逐字段对齐, 供 diff 与"恢复即新版本"
struct CredSnapshot: Codable, Identifiable {
    var version: Int
    var at: Double              // Unix 秒
    var note: String            // 人话摘要 (490), 由 makeSummary 生成
    var starred: Bool = false   // 495 星标版不受配额淘汰
    var auto: Bool = false      // 488 自动还原点 (还原备份/批量操作前) 置顶加标记
    var pwd: LedgerPwd?
    var fp: LedgerFp?
    /// 487-496 版本历史列表的标识: 同一凭证的 version 单调递增, 天然唯一
    var id: Int { version }
}
/// 498 来源过滤: 手动删除 / 批量清理 / 过期清理 / 重录替代
enum CredBinSource: Int, Codable, CaseIterable {
    case manual = 0, batch = 1, expired = 2, rererecord = 3, orphan = 4
    var label: String {
        switch self {
        case .manual: return "手动删除"
        case .batch: return "批量清理"
        case .expired: return "过期清理"
        case .rererecord: return "重录替代"
        // 452: 诊断页"隔离无主凭证"这一支 —— 来源单列一档, 用户看得见它是被谁收走的
        case .orphan: return "无主隔离"
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
        at > 0 ? "\(at)" : (pwd.map { "\($0.alias)" } ?? fp.map { "\($0.batch)" } ?? "bin")
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
    var d3: Bool = false       // 930: 到期前 3 天
    var d1: Bool = false       // 930: 到期前 1 天
    var h24: Bool = false
    var h2: Bool = false
    init(day: Bool = false, d3: Bool = false, d1: Bool = false, h24: Bool = false, h2: Bool = false) {
        self.day = day; self.d3 = d3; self.d1 = d1; self.h24 = h24; self.h2 = h2
    }
    enum CodingKeys: String, CodingKey { case day, d3, d1, h24, h2 }
    /// 930 新增 d3/d1 之后, 老包 `kf_calert_` 的 JSON 里没有这两个键。合成解码器遇到**缺键**是抛错,
    /// 一抛整组开关会被 `?? CredAlert()` 吞成"全关" —— 用户已经开好的 7 天/24 小时档会静默消失。
    /// 所以显式解码: 缺键 = 那一档关, 不牵动别的档 (与恢复包"缺字段=不动本机"同一条纪律)。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Bool.self, forKey: .day)) ?? false
        d3 = (try? c.decodeIfPresent(Bool.self, forKey: .d3)) ?? false
        d1 = (try? c.decodeIfPresent(Bool.self, forKey: .d1)) ?? false
        h24 = (try? c.decodeIfPresent(Bool.self, forKey: .h24)) ?? false
        h2 = (try? c.decodeIfPresent(Bool.self, forKey: .h2)) ?? false
    }
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
        case .recent: return "最近使用(约)"   // 锁端日志不记凭证身份, 长期凭证只能按锁级推断 → 按本仓纪律带"约"
        case .expiry: return "到期"
        }
    }
}
enum CredGroupMode: Int { case type, owner }

// ================= 组织层 =================
enum CredentialOrg {
    /// 2026-10-13 对抗式排查: 凭证通知排期失败的可见出口。
    /// 原先 `Task { try? await UNUserNotificationCenter…add(req) }` 把失败静默吞掉, 界面照显"已排程"。
    /// 凭证到期预警是这条链唯一的提醒出口, 静默失败 = "说要提醒但没人提醒"。
    static let notifyLog = Logger(subsystem: "com.aapk.OfflineLock", category: "credentialNotify")
    // ---------- 键 ----------
    static func histKey(_ mac: String, _ kind: String, _ key: Int) -> String { "kf_chist_\(mac)_\(kind)_\(key)" }
    static func binKey(_ mac: String) -> String { "kf_cbin_" + mac }
    static func queueKey(_ mac: String) -> String { "kf_cqueue_" + mac }
    static func starKey(_ mac: String) -> String { "kf_cstar_" + mac }
    /// 354 归档区: 与星标同式的本机单键 (同一把锁一份)
    static func archKey(_ mac: String) -> String { "kf_carch_" + mac }
    static func alertKey(_ mac: String, _ kind: String, _ key: Int) -> String { "kf_calert_\(mac)_\(kind)_\(key)" }
    static func listsKey(_ mac: String) -> String { "kf_clists_" + mac }
    static func seqKey(_ mac: String) -> String { "kf_cseq_" + mac }

    // ---------- 时间解析 (台账串 "yyyy-MM-dd HH:mm:ss", 本地时区) ----------
    static let credFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")   // 这一份既格式化也**反解析**台账串，必须钉公元历 (原 zh_CN 对纯数字格式没起作用，反而跟着系统历法跑)
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
    // `latest(_:kind:_:)` (取某条凭证的最新快照) 第九十二批删除：全库零调用点，
    // 而调用方要的东西都是 `history(...)` 再自己挑 (历史页要整条列表)。
    // grep 到的 `latest(` 全是 BatteryCare.latest —— 同名不同主，正是成员级限定计数上线才分得清的那种。
    static func saveHistory(_ mac: String, _ kind: String, _ key: Int, _ list: [CredSnapshot]) {
        DB.setCodable(list, histKey(mac, kind, key))
    }
    /// 496 恢复即新版本: 不覆盖, 按基线 s 复制回台账, 并新增一条 "恢复自 v(s)" 快照。
    /// 返回补进提示的那半句 —— 这一条**改的是本机台账，锁里那条不会自己变回来**：
    /// 第一百五十四批查出这里是"第四处两侧不一致"（与 152 的撤销、153 的删成员、154 的队列同一族）：
    /// 回滚一个改过的密码值/时段之后，界面报"已恢复"，而用户拿那串码去开门会开不了。
    /// 密码 ⇒ 按 504 排一次重新下发；指纹 ⇒ 来源口径：锁里存的是指纹模板，快照能变的只有名称/备注/归属
    /// (全是本机字段，锁那边既改不了也不需要改)，所以不排队。
    static func restore(_ mac: String, kind: String, key: Int, from s: CredSnapshot) -> String {
        var note = ""
        if let p = s.pwd {
            DB.addPwd(mac, p)
            note = queueRestore(mac, p)
        }
        if let f = s.fp { DB.addFp(mac, f) }
        snapshot(mac, kind: kind, key: key, pwd: s.pwd, fp: s.fp, note: "恢复自 v\(s.version)", starred: true)
        return note
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
    /// 回收站那一格的移除 + 放回台账。**这只是"从回收站取回"这一步**，
    /// 一次删除动作在别处留下的痕迹 (365 待下发的锁端删除、361 停用便签) 它管不着 ——
    /// 所以调用方要的是下面 `undoRemove` 而不是这个。
    /// 来源口径：被这一行放回台账的凭证，锁端那一半由调用方负责 ——
    /// 撤销停用走 `reclaim` 收回待发删除，撤销/还原彻底删除走 504 `queueRestore`；直接调本函数就是绕过它。
    @discardableResult
    static func undoBin(_ mac: String, entry: CredBinEntry) -> Bool {
        var list = bin(mac)
        guard let i = list.firstIndex(where: { $0.id == entry.id }) else { return false }
        let e = list.remove(at: i)
        saveBin(mac, list)
        if let p = e.pwd { DB.addPwd(mac, p) }
        if let f = e.fp { DB.addFp(mac, f) }
        return true
    }

    /// 506 撤销的**完整**语义：把那次删除留在本机的东西一并收回去。
    /// 为什么必须有这一层 (第一百五十二批读代码读出来的，此前是缺陷不是设计)：
    ///  · 停用那条路 (`disablePwd/disableFp`) 删之前就 `enqueue("del_pwd"/"del_fp")` 排了锁端删除、
    ///    并写了 361 停用便签。旧撤销只做 `undoBin` ⇒ 撤销之后
    ///     ① 队列里那条待下发的删除还在，连上锁就把**刚恢复的凭证从锁上删掉**（本机却显示它在用），
    ///     ② 列表上这条"已恢复"的凭证仍挂着「停用原因 未填 · 本机单条停用」。
    ///    界面上那句"已原位还原"因此是假的 —— 现在这里把两样都收回，并把话说清。
    ///  · 彻底删除那条路 (`doDeletePwd/doDeleteFp`) 里锁端那一步**已经真执行了**，不能"收回"，
    ///    只能按 504 的既有口径"还原即重新下发"补 `restore`；指纹没有远程补录的路 (670)，只能如实说。
    /// 返回的是**给用户看的那句话** —— 措辞只在这里有一份，界面不再各写一遍。
    static func undoRemove(_ mac: String, entry: CredBinEntry, hard: Bool) -> String {
        guard undoBin(mac, entry: entry) else {
            return "这条已经不在回收站里了 (506) — 可能已恢复、已清理，或本机刚换过锁"
        }
        if hard {
            if let p = entry.pwd {
                queueRestore(mac, p)
                let q = queue(mac).contains { $0.kind == "restore" && $0.pwd?.alias == p.alias }
                return q ? "本机记录已放回原位；锁端那条已经真删了 —— 按 504 排入「重新下发」，连上锁补回 (506)"
                         : "本机记录已放回原位；锁端那条已经真删，而这条已过有效期 ⇒ 既不重发也无处可恢复 (506)"
            }
            if entry.fp != nil {
                return "本机记录已放回原位；锁端那条已经真删 —— 指纹只能本人到锁前重录 8 次，App 无法远程补录 (670)"
            }
            return "本机记录已放回原位 (506)"
        }
        return "已撤销停用：本机记录放回原位" + reclaim(mac, entry: entry)
    }

    /// 收回**还没发出去**的那条锁端删除。只动 pending 的，已经下发/失败的留着 (那两步是真发生过的，
    /// 悄悄删掉记录等于抹掉证据 —— 失败的那条改由队列页自己处理)。
    static func cancelPendingDelete(_ mac: String, entry: CredBinEntry) -> Bool {
        let q = queue(mac)
        let dead = q.filter { it in
            guard it.state == CredQueueState.pending.rawValue else { return false }
            if it.kind == "del_pwd", let a = entry.pwd?.alias { return it.pwd?.alias == a }
            if it.kind == "del_fp", let b = entry.fp?.batch { return it.fp?.batch == b }
            return false
        }.map { $0.id }
        guard !dead.isEmpty else { return false }
        saveQueue(mac, q.filter { !dead.contains($0.id) })
        return true
    }

    /// 361 便签的逆操作。写回用的是与 `markDisabled` **同一个** `store.setCodable(键, 值)` 参数序 ——
    /// 这一族层间参数序是反的 (swiftlint ④ 盯的就是它)，两处各写一套必错一套。
    static func clearDisabled(_ mac: String, kind: String, key: Int) {
        var m = DB.store.get([String: DisableMark].self, disReasonKey(mac)) ?? [:]
        guard m.removeValue(forKey: "\(kind):\(key)") != nil else { return }
        DB.store.setCodable(disReasonKey(mac), m)
    }
    /// 一条凭证"又归本机了"的统一收尾 (506 撤销与 499/504 还原共用这一份)：
    /// 收回它名下**还没发出去**的锁端删除，并清掉 361 停用便签。
    /// 不收尾会有两种谎：队列继续排着"删除刚恢复的这条"、列表把它标成"停用中"。
    /// 没可收回的东西就回空串 —— 提示语不吹一件没发生的事。
    static func reclaim(_ mac: String, entry: CredBinEntry) -> String {
        let dropped = cancelPendingDelete(mac, entry: entry)
        var cleared = false
        if let p = entry.pwd, disableMark(mac, kind: "pwd", key: p.alias) != nil {
            clearDisabled(mac, kind: "pwd", key: p.alias); cleared = true
        }
        if let f = entry.fp, disableMark(mac, kind: "fp", key: f.batch) != nil {
            clearDisabled(mac, kind: "fp", key: f.batch); cleared = true
        }
        var bits: [String] = []
        if dropped { bits.append("已收回待下发的锁端删除") }
        if cleared { bits.append("已清停用便签") }
        // 指纹这条要多说一句 (第一百五十二批)：密码还原后 504 会问"要不要重新下发"，
        // 指纹**没有远程补录这条路** (670)，锁端那一半到底是"还没删"还是"已经删了"本机无从证实。
        // 没收回待发删除时，"已还原"这句话掩盖的正是这个未知 —— 所以按实说。
        if entry.fp != nil {
            bits.append(dropped ? "这条指纹锁端那步还没发出去，已收回 —— 仍可开门"
                                : "锁端这条有无被删过要连上锁才证实；若已删，指纹只能本人到锁前重录 (670)")
        }
        return bits.isEmpty ? "" : " · " + bits.joined(separator: " · ")
    }
    /// 499 还原冲突副本: 同 ID 已存在时, 加 "还原-" 前缀别名还原
    /// 第一百五十四批把 504 的"排一次重新下发"**搬进这个函数**：以前它写在回收站页那一个调用点的弹窗里，
    /// 而 `restoreBin` 有三个调用方 (单条还原 / 批量还原 / 还原为副本)，另两条路把密码放回台账却从不排下发
    /// ⇒ 界面报"已还原"，锁里却没这条，人拿码去开门会开不了。规则收在一处才不会三份各写一份。
    /// 指纹不排：锁存的是模板，本机改不了也不需要改 (名称/备注/归属都是本机字段) —— 来源口径：见 `reclaim`。
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
            msg += queueRestore(mac, cp)     // 504: 还原的密码一律排一次重新下发 (过期则不排, 由返回值说明)
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
        // 第一百五十二批: 还原 = 这条又归本机了 ⇒ 一并收回它名下那条还没发出去的删除。
        // 不做这一步，"还原"后队列里仍排着 del_pwd/del_fp，连上锁就把刚还原的凭证再删一次。
        return msg + reclaim(mac, entry: entry)
    }
    /// 502 的**裸执行**口: 不问生物识别、不弹确认, 调到这里就直接把这条从回收站抹掉。
    /// 门槛只允许落在界面上的 `guardedPurge(_:ids:reason:onDeniedPresentFallback:)` ——
    /// 任何调用点都不得绕过它直接调这里 (delsweep 的 UI_SINK 名单收的正是这一族一按即删的汇点)。
    static func purgeBin(_ mac: String, id: String) {
        saveBin(mac, bin(mac).filter { $0.id != id })
    }
    /// 502 彻底删除的**统一门槛**: 单条与清空回收站走同一个函数, 两条路的深浅必须一样。
    /// 为什么收在一处 (与 323 双签同型的那次整改同一条理由): 原先「清空」自己写了半套生物识别 +
    /// 兜底弹窗, 「单条」只有一遍 confirmationDialog, 两套深浅各说各话 —— 门槛分叉就是漏问的开始。
    /// 口径:
    ///  · 设备有可用的 Face ID / Touch ID ⇒ 先刷, **通过即执行** commit, 不再多问一句;
    ///  · 没录生物 / 系统判不可用 / 刷失败 ⇒ 把**同一个** commit 交回调用方, 由
    ///    `onDeniedPresentFallback` 决定 UI 怎么问双确认 (confirmDestructive 或 confirmationDialog 都行),
    ///    用户确认之后才执行。
    /// fail-closed: 「没法刷脸」不等于放行 —— 那一支必须过 UI 的第二问。
    /// commit 落的只有 purgeBin / saveBin 这一条裸执行路, 门槛与执行因此分得开也查得清。
    /// ⚠ 为什么不走 AccessibilityKit 的 `AuthKit.verifyBiometric` (877): 那份把 localizedReason
    ///   写死成代替密码那句, 也没有 denied 分支 —— 502 要说的是彻底删除 N 条, 且未通过时得有第二条路。
    static func guardedPurge(_ mac: String, ids: [String], reason: String,
                             onDeniedPresentFallback: @escaping (_ commit: @escaping () -> Void) -> Void,
                             onDone: @escaping () -> Void = {}) {
        // onDone 挂在 commit 里，而不是挂在调用方的两条分支上：生物识别那一路如果由 UI 自己补一句回执，
        // 就会出现"刷脸成功了但回执文案只在弹窗那一路有"的分叉。
        let commit: () -> Void = { purgeNow(mac, ids: ids); onDone() }
        let ctx = LAContext()
        var err: NSError?
        // 可用性与 AuthKit.biometricAvailable (877) 同一判据: canEvaluate 为真却带 biometryNotAvailable
        // 的情形实测存在过, 两支都按"这台设备没生物可刷"处理 —— 没生物 = 走 UI 第二问, 不是放行。
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
              err?.code != LAError.biometryNotAvailable.rawValue else {
            onDeniedPresentFallback(commit)
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async {
                if ok { commit() } else { onDeniedPresentFallback(commit) }
            }
        }
    }
    /// 502 门槛过完之后的执行体: 一条就删那一条, 多条/整组按 id 集合删。
    /// 两支共用同一个过滤口径 (与 purgeBin 逐字同一件事), 不另写第二套清空逻辑 ——
    /// 否则同一条目在单条与清空两条路上会被删得不一样。
    static func purgeNow(_ mac: String, ids: [String]) {
        if ids.count == 1, let only = ids.first { purgeBin(mac, id: only); return }
        let drop = Set(ids)
        saveBin(mac, bin(mac).filter { !drop.contains($0.id) })
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
    /// 501/349 成员删除: 名下凭证随成员入回收站 (整组同戳, 可整组还原)
    /// D-152a (2026-10-11 拍板 方案③): 弹窗当场选「只移除档案 / 连锁端一起收回」, 默认第一项。
    ///  · revokeLocks = false: 只动本机台账, 整组可还原 (501); 锁里那些指纹与密码仍然有效, TA 照旧能开门。
    ///  · revokeLocks = true: 每条再排 365 队列的 `del_pwd`/`del_fp` —— 与 629 逐条停用、353 批量停用
    ///    走的是同一条现成队列, 到场连接后真正生效, 没有新数据面。
    ///    ⚠ 指纹在锁端删掉就无法远程补录 (670), 还原时对指纹只剩本机记录 —— 这句话必须和选择写在同一屏,
    ///    两处弹窗都是这么写的。
    /// 返回本次排上锁端删除的条数: 界面按实数报, 不写死一句"已删除"。
    @discardableResult
    static func cascadeBinMember(_ mac: String, _ memberID: String, revokeLocks: Bool = false) -> Int {
        var queued = 0
        for p in DB.listPwds(mac).filter({ $0.owner == memberID }) {
            var cp = p
            cp.owner = nil
            DB.delPwd(mac, p.alias)
            addToBin(mac, pwd: cp, source: .manual)
            if revokeLocks {
                enqueue(mac, kind: "del_pwd", title: "删成员连带 密码 #\(p.alias) (D-152a)")
                queued += 1
            }
        }
        for f in DB.listFps(mac).filter({ $0.owner == memberID }) {
            var cp = f
            cp.owner = nil
            DB.delFp(mac, f.batch)
            addToBin(mac, fp: cp, source: .manual)
            if revokeLocks {
                enqueue(mac, kind: "del_fp", title: "删成员连带 指纹「\(f.name)」 (D-152a)")
                queued += 1
            }
        }
        return queued
    }
    /// 501/263 删除成员预告: 名下将入回收站的凭证清单 (跨锁合计)。
    /// 两处「删除成员」弹窗共用这一份, 免得同一条预览各写一遍; 锁名一律走 LockArchive.displayName (769 口径)。
    static func memberCredentialPreview(_ memberID: String) -> [String] {
        var out: [String] = []
        for kc in DB.keychains() {
            let lockName = LockArchive.displayName(kc)
            for p in DB.listPwds(kc.mac).filter({ $0.owner == memberID }) {
                out.append("密码 #" + String(p.alias) + " · " + lockName)
            }
            for f in DB.listFps(kc.mac).filter({ $0.owner == memberID }) {
                out.append("指纹「" + f.name + "」· " + lockName)
            }
        }
        return out
    }
    /// 504 还原即重新下发: 在用 (未过期) 密码还原后并入队, 由 UI 询问"立即重新下发"。
    /// 返回补进提示的那半句 (第一百五十四批): 排没排上、为什么没排，界面要说得出来，
    /// 不能一律"已还原" —— 锁上那条没跟着变，用户拿恢复后的码去开门会吃闭门羹。
    @discardableResult
    static func queueRestore(_ mac: String, _ p: LedgerPwd) -> String {
        guard let to = expiryDate(p), to.timeIntervalSinceNow > 0 else { return " · 已过有效期，不排重新下发" }
        var q = queue(mac)
        if q.contains(where: { $0.kind == "restore" && $0.pwd?.alias == p.alias }) { return " · 重新下发本来就在队列里" }
        q.insert(CredQueueItem(id: nextQueueId(mac), kind: "restore", title: "重新下发「\(displayPwd(p))」",
                               pwd: p, state: CredQueueState.pending.rawValue), at: 0)
        saveQueue(mac, q)
        return " · 已排入重新下发 (504)，到场连接后生效"
    }

    // ---------- 365 下发状态队列 (本地容错态, 重试走既有命令) ----------
    static func queue(_ mac: String) -> [CredQueueItem] {
        DB.get([CredQueueItem].self, queueKey(mac)) ?? []
    }
    static func saveQueue(_ mac: String, _ q: [CredQueueItem]) {
        DB.setCodable(q, queueKey(mac))
    }
    /// 541 替代: "此锁配置上次成功下发于 X"。原句要的锁端配置序号字段与配置拉取命令都不存在,
    /// 所以这把尺只能到**本机台账**: 365 队列里 state = 已下发(1) 的条目中最新的 `lastAt` (毫秒)。
    /// 它证明的是"本机发过且锁端回过受理", 不是"锁端现在就是这份配置" —— 界面上那句话必须跟着说清这一点,
    /// 否则又变成替锁端虚报一个读不到的真值。
    static func lastApplyAt(_ mac: String) -> Double? {
        let done = queue(mac).filter { $0.state == CredQueueState.done.rawValue }
        guard let m = done.map({ $0.lastAt }).max(), m > 0 else { return nil }
        return m
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
    /// 365 队列项的**唯一**下发实现 (第一百五十四批收拢的)。
    /// 为什么要收：这条 switch 原本抄了三份 —— `CredentialsView.applyQueueItem` (带着"缺别名就中止"的修正)、
    /// `CredentialCenterView.applyItem` (没带)、`LinkSenseKit.applyQueueItem` (没带，而且它走的是
    /// **回前台/到场自动补发**那条没人盯着的路)。缺对象时 `?? 0` 会向锁发"删 0 号槽"，
    /// 删掉的是**别人**的密码，回包还被 `markQueue(.done)` 标成"锁端确认"。
    /// 同一份修正在两份里没落地 —— CredentialsView 里那段注释写的就是这个坑，它只修了自己那份。
    /// 返回一句要补进队列提示的话 (只有锁端把这条落到别的槽时才有内容)。
    static func sendQueued(_ mac: String, _ lock: LockService, _ item: CredQueueItem) async throws -> String {
        switch item.kind {
        case "del_pwd":
            guard let p = item.pwd, p.alias != 0 else {
                throw BLEErrorX.msg("队列项缺少密码别名 (\(item.title))，已中止下发 — 请重新选择该凭证")
            }
            // 留存口径：本机台账在停用那一刻就删了 (disablePwd)，这一步只负责把命令发出去
            try await lock.pwdDelete(p.alias)
            return ""
        case "del_fp":
            // 2026-10-13 对抗式排查: 原只判 `f.batch != 0`, 而 `UInt32(f.batch)` 对负数/超上界是 **trap**。
            // 导入链不校验 batch 符号 ⇒ 构造备份即可让用户点删除时崩进程。改成取安全转换后的值。
            guard let f = item.fp, let b = f.batchU32 else {
                throw BLEErrorX.msg("队列项指纹缺失或批次号越界 (\(String(describing: item.title)))，已中止下发 — 请检查台账或备份来源")
            }
            try await lock.fpDelete(b)
            return ""
        case "period":
            guard let p = item.pwd, p.alias != 0, !item.newFrom.isEmpty else {
                throw BLEErrorX.msg("队列项缺少改期对象 (\(item.title))，已中止下发")
            }
            // 留存口径：batchExtend 入队时已把本机时段改掉 (CredentialOrg.swift:460)，这里不写第二遍
            try await lock.pwdExpire(p.alias, item.newFrom, item.newTo)
            return ""
        case "restore":
            guard let p = item.pwd, let v = p.pwd else {
                throw BLEErrorX.msg("这条没有口令明文，无法重新下发 (\(item.title)) — 需重新录入 (504)")
            }
            let alias = try await lock.pwdAdd(pwd: v, validFrom: p.from, validTo: p.to)
            guard alias != p.alias else { return "" }
            // 锁把这条放进了别的槽 ⇒ 本机那行跟着改号 (照改值那条路 CredentialStudio.swift:1131 的写法：
            // 删旧号 + 用新号写回，并留一档版本历史)。三份旧实现都把返回值扔了 (`_ =`)，
            // 不归位就是两份真相：本机按旧别名去"彻底删除/改期"，动的却是**同槽位的另一个凭证**。
            var moved = p
            moved.alias = alias
            DB.delPwd(mac, p.alias)
            DB.addPwd(mac, moved)
            snapshot(mac, kind: "pwd", key: alias, pwd: moved, fp: nil,
                     note: "重新下发落到别名 #\(alias) (365 归位)")
            return " · 锁端落到别名 #\(alias)"
        default:
            return ""
        }
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
            enqueue(mac, kind: "period", title: "延期 密码 #\(a)", pwd: LedgerPwd(alias: a, from: from, to: to, temp: p.temp, at: p.at, note: p.note), newFrom: from, newTo: to)
            out.append(a)
        }
        return out
    }
    /// 349 批量移交: 批量改归属 (本地台账), 各写一条本地记录 (锁端无归属字段)
    /// 注释里的"各写一条本地记录"此前是**空头支票** —— 两个循环只调了 setPwdOwner/setFpOwner, 没有任何快照落盘,
    /// 改完归属查不到是谁改的。撤掉 467 待接受区后这条路径就是唯一移交入口, 留痕更不能少, 所以补齐而不是删注释。
    static func batchTransfer(_ mac: String, pwdAliases: [Int], fpBatches: [Int], to: String?) -> Int {
        var n = 0
        let toName = to.flatMap { DB.member($0)?.name } ?? "未指派"
        for a in pwdAliases {
            guard let old = DB.ledger(mac).pwds.first(where: { $0.alias == a }) else { continue }
            DB.setPwdOwner(mac, a, to)
            if let p = DB.listPwds(mac).first(where: { $0.alias == a }) {
                snapshot(mac, kind: "pwd", key: a, pwd: p, fp: nil, note: "移交 → " + toName + proxySuffix(old.owner))
            }
            n += 1
        }
        for b in fpBatches {
            guard let old = DB.ledger(mac).fps.first(where: { $0.batch == b }) else { continue }
            DB.setFpOwner(mac, b, to)
            if let f = DB.listFps(mac).first(where: { $0.batch == b }) {
                snapshot(mac, kind: "fp", key: b, pwd: nil, fp: f, note: "移交 → " + toName + proxySuffix(old.owner))
            }
            n += 1
        }
        return n
    }
    /// 468 代管补记: 条目**改动前**的属主被点名「由我代管」时, 快照补一句 管理员代操作。
    /// 判据与单条停用 disableVia、批量停用拆分同一张 proxyNames; 无归属不猜。
    private static func proxySuffix(_ owner: String?) -> String {
        guard let o = owner, !o.isEmpty, MemberHub.proxyNames.contains(o) else { return "" }
        return " · 管理员代操作 (468)"
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
            // 498: 已过期的进回收站标"过期", 未过期的手动批量停用仍标"批量"
            addToBin(mac, pwd: p, source: pwdState(p) == 2 ? .expired : .batch)
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
        let pwds = DB.listPwds(mac), fps = DB.listFps(mac)
        return (pwds.count + fps.count, pwds.count, fps.count, DB.otpStatus(mac)?.on == true ? 1 : 0)
    }
    static func pwdState(_ p: LedgerPwd) -> Int {
        // 0 进行中 / 1 已排期 / 2 已过期 (按时间窗推断, 一次性语义锁端未定义故不区分)
        if let to = expiryDate(p), to.timeIntervalSinceNow <= 0 { return 2 }
        if let f = parseLocal(p.from), f.timeIntervalSinceNow > 0 { return 1 }
        return 0
    }

    // ---------- 526/921 置顶星标 + 高频 ----------
    static func stars(_ mac: String) -> Set<Int> {
        Set(DB.get([Int].self, starKey(mac)) ?? [])
    }
    static func toggleStar(_ mac: String, _ kind: String, _ key: Int) {
        setStar(mac, kind, key, !isStarred(mac, kind, key))
    }
    /// 922 批量置顶: 同一个星标键, 补一个"设为"写点 —— 批量里用 toggle 会把已置顶的那几条翻下去
    static func setStar(_ mac: String, _ kind: String, _ key: Int, _ on: Bool) {
        var s = stars(mac)
        let id = kind == "pwd" ? key : 100000 + key   // 指纹段偏移, 避免别名冲突
        if on { s.insert(id) } else { s.remove(id) }
        DB.setCodable(Array(s), starKey(mac))
    }
    static func isStarred(_ mac: String, _ kind: String, _ key: Int) -> Bool {
        stars(mac).contains(kind == "pwd" ? key : 100000 + key)
    }
    /// 921 高频标记: 台账可推断 (近 30 天开门类日志中命中时间窗次数最多的临时密码), 标"约"
    static func starSuggestion(_ mac: String) -> String? {
        // 354: 归档条目不进"猜你要开哪条"的候选 —— 与 921 快捷直达同一口径, 收起的东西不许被推荐
        let temps = DB.listPwds(mac).filter { $0.temp && !isArchived(mac, "pwd", $0.alias) }
        let logs = DB.readLogs(mac).filter { $0.type == 2 || $0.type == 4 }
        guard !temps.isEmpty, !logs.isEmpty else { return nil }
        func inWindow(_ p: LedgerPwd, at t: Double) -> Bool {
            guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return false }
            return f.timeIntervalSince1970 <= t && t <= to.timeIntervalSince1970
        }
        var hits: [String: Int] = [:]
        for l in logs {
            let t = ZKProtocol.protoSecondsToUnix(Int64(l.lockTime))
            guard t >= nowSec - 30 * 86400 else { continue }
            for p in temps where inWindow(p, at: t) {
                hits["p\(p.alias)", default: 0] += 1
            }
        }
        guard let top = hits.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        return top.key
    }

    // ---------- 354 归档区: 收起不删 — 与停用/彻底删除是两个不同档, 归档只碰展示层, 台账与锁端零改动 ----------
    static func archived(_ mac: String) -> Set<Int> {
        Set(DB.get([Int].self, archKey(mac)) ?? [])
    }
    static func setArchived(_ mac: String, _ kind: String, _ key: Int, _ on: Bool) {
        var s = archived(mac)
        let id = kind == "pwd" ? key : 100000 + key   // 指纹段偏移, 与星标同一约定
        if on { s.insert(id) } else { s.remove(id) }
        DB.setCodable(Array(s), archKey(mac))
    }
    static func isArchived(_ mac: String, _ kind: String, _ key: Int) -> Bool {
        archived(mac).contains(kind == "pwd" ? key : 100000 + key)
    }
    /// 354 "全部还原": 一次清键 — 逐条 toggle 会把批量里并发的读改写搅在一起
    static func unarchiveAll(_ mac: String) {
        DB.setCodable([Int](), archKey(mac))
    }

    // ---------- 359 三档预警 (本地通知; 2 小时档做 App 内提醒行, 7 天/24 小时档排程) ----------
    static func alert(_ mac: String, _ p: LedgerPwd) -> CredAlert {
        DB.get(CredAlert.self, alertKey(mac, "pwd", p.alias)) ?? CredAlert()
    }
    static func saveAlert(_ mac: String, _ p: LedgerPwd, _ a: CredAlert) {
        DB.setCodable(a, alertKey(mac, "pwd", p.alias))
    }
    /// 926/930 替代: 7 / 3 / 1 天 + 24 / 2 小时**都**排本地通知, 另加"到期时"一条。
    /// 原 359 把 2 小时档做成"只插列表提醒行, 不排通知"(详情页卡片上写着这句话);
    /// 926/930 判 ❌ 后拍板按替代执行 —— 替代栏原话是"到期前 2 小时与到期时各发本地通知"。
    /// 排程扩到六条, 列表提醒行 (dueSoonPwds) **照旧保留**: 前台多一处提示不是坏事。
    static func scheduleAlerts(_ mac: String, _ p: LedgerPwd, _ a: CredAlert) {
        let c = UNUserNotificationCenter.current()
        let id = "c6.alert.\(mac).p\(p.alias)"
        c.getPendingNotificationRequests { reqs in
            let stale = reqs.map(\.identifier).filter { $0 == id || $0.hasPrefix(id + ".") }
            if !stale.isEmpty { c.removePendingNotificationRequests(withIdentifiers: stale) }
        }
        // "到期时"不看单档开关: 开了任何一档 = 在意这条凭证的到期, 到点本身最该说话。
        let any = a.day || a.d3 || a.d1 || a.h24 || a.h2
        guard let to = expiryDate(p), any else { return }
        let name = displayPwd(p)
        // 天数档是**日历日** ⇒ 走 WeekCal.shifted; 小时档说的是"还有 N 小时" = 时长。
        // 两种口径在这里不是一回事 (§10.33), 混用会让 -1 天那条在夏令时切换日多/少一小时。
        func dayTier(_ on: Bool, _ k: Int, _ suf: String, _ tail: String) {
            if on {
                addCalendar(id: id + suf, date: WeekCal.shifted(to, days: -k),
                            title: "密码临期", body: "\(name) 距到期还有 \(k) 天。" + tail)
            }
        }
        dayTier(a.day, 7, ".d7", "记得续期或停用。")
        dayTier(a.d3, 3, ".d3", "")
        dayTier(a.d1, 1, ".d1", "明天就失效了。")
        if a.h24 {
            addCalendar(id: id + ".h24", date: to.addingTimeInterval(-86400),
                        title: "密码临期", body: "\(name) 距到期不足 24 小时。")
        }
        if a.h2 {
            addCalendar(id: id + ".h2", date: to.addingTimeInterval(-7200),
                        title: "密码临期", body: "\(name) 距到期还有 2 小时。")
        }
        addCalendar(id: id + ".t0", date: to, title: "已到期",
                    body: "\(name) 到期了, 锁端到这个时刻后不再放行这条凭证。")
    }

    /// 930 凭证 Tab 角标: 近 7 日内到期的条数。
    /// 与 363 月历格、dueSoonPwds 同源同一把尺 (expiryDate), 不另算第二套; 长期有效 (2118) 与归档条不计。
    static func expiringSoonCount(macs: [String], within days: Int = 7) -> Int {
        let limit = nowSec + Double(days) * 86400
        var n = 0
        for mac in macs {
            for p in DB.listPwds(mac) where !isArchived(mac, "pwd", p.alias) {
                if let to = expiryDate(p) {
                    let t = to.timeIntervalSince1970
                    if t >= nowSec && t <= limit { n += 1 }
                }
            }
        }
        return n
    }
    private static func addCalendar(id: String, date: Date, title: String, body: String) {
        guard date > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = WeekCal.gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        // 2026-10-13 对抗式排查: 原写 `Task { try? await … }` —— 排期失败被静默吞掉,
        // 而界面照样显示"已排程/已设定"。凭证到期预警是这条链唯一的提醒出口, 静默失败
        // 等于"账单说要扣钱但没人扣"。改成 catch 里写 os 日志 (authFail/log 之外唯一可见出口)。
        Task {
            do { try await UNUserNotificationCenter.current().add(req) }
            catch { CredentialOrg.notifyLog.error("凭证通知排期失败 id=\(id, privacy: .public) err=\(String(describing: error), privacy: .public)") }
        }
    }
    /// App 内 2 小时档: 到期前 2 小时且开了 h2 的条 (设备 Tab Hero 卡下插提醒行)
    /// 359: 提醒行点按要跳最近一条的详情 —— 名单与计数必须同源同一个 filter, 抽出来共用
    static func dueSoonPwds(_ mac: String) -> [LedgerPwd] {
        let soon = nowSec + 2 * 3600
        return DB.listPwds(mac).filter { p in
            if let to = expiryDate(p) {
                let a = alert(mac, p)
                return a.h2 && to.timeIntervalSince1970 <= soon && to.timeIntervalSince1970 >= nowSec - 3600
            }
            return false
        }
    }

    // ---------- 358/505 整理建议中心 ----------
    struct Advice: Identifiable {
        let id: String
        let title: String
        let sub: String
        let icon: String
        let action: String   // "expired" / "dups" / "noowner" / "bin" / "memberExpired" (471)
    }
    static func advice(_ mac: String) -> [Advice] {
        var out: [Advice] = []
        // 354: 整理中心是动作面 — 计数与集合都取"选得中"的那一份 (归档条不参与催办)
        let expired = DB.listPwds(mac).filter { pwdState($0) == 2 && !isArchived(mac, "pwd", $0.alias) }.count
        if expired > 0 {
            out.append(Advice(id: "expired", title: "过期 \(expired) 条",
                              sub: "已过期凭证待清理或续期", icon: "clock.arrow.circlepath", action: "expired"))
        }
        var values: [String: [LedgerPwd]] = [:]
        for p in DB.listPwds(mac) where p.pwd != nil && !isArchived(mac, "pwd", p.alias) { values[p.pwd!, default: []].append(p) }
        let dups = values.values.filter { $0.count > 1 }.count
        if dups > 0 {
            out.append(Advice(id: "dups", title: "重复值 \(dups) 组",
                              sub: "多条台账同一密码, 可合并归属", icon: "plus.slash.minus", action: "dups"))
        }
        let noowner = DB.listPwds(mac).filter { $0.owner == nil && !isArchived(mac, "pwd", $0.alias) }.count
        if noowner > 0 {
            out.append(Advice(id: "noowner", title: "无归属 \(noowner) 条",
                              sub: "未指定成员的凭证, 建议移交或停用", icon: "person.slash", action: "noowner"))
        }
        let binN = bin(mac).count
        if binN > 0 {
            out.append(Advice(id: "bin", title: "回收站 \(binN) 条可彻底清理",
                              sub: "超过 \(reclaimDays()) 天保留期将自动清除", icon: "trash", action: "bin"))
        }
        // 471 到期收回建议: 口径是"该成员名下临时码**全部**已过期" (有部分没过期就不该催收回)
        var byOwner: [String: (all: Int, expired: Int)] = [:]
        for p in DB.listPwds(mac) where p.temp && !isArchived(mac, "pwd", p.alias) {
            guard let o = p.owner, !o.isEmpty else { continue }
            var t = byOwner[o] ?? (0, 0)
            t.all += 1
            if pwdState(p) == 2 { t.expired += 1 }
            byOwner[o] = t
        }
        let allGone = byOwner.filter { $0.value.all > 0 && $0.value.all == $0.value.expired }
                          .sorted { $0.value.all > $1.value.all }
        for (owner, v) in allGone.prefix(3) {
            let nm = DB.member(owner)?.name ?? "该成员"
            out.append(Advice(id: "memberExpired:" + owner,
                              title: "归属 \(nm) 的 \(v.all) 张临时码已全部过期",
                              sub: "建议停用收回, 台账与回收站会留着痕迹 (471)",
                              icon: "person.crop.circle.badge.xmark", action: "memberExpired"))
        }
        return out
    }
    /// 智能选取 (350 三按钮) 的集合定义: 已过期 / 同成员 / 同类型
    /// 354: 选择位面与浏览位面同一份 —— 归档条目不进任何选取集合
    static func smartSet(_ mac: String, set: String, base: (pwd: [Int], fp: [Int])) -> (pwd: [Int], fp: [Int]) {
        switch set {
        case "expired":
            return (DB.listPwds(mac).filter { pwdState($0) == 2 && !isArchived(mac, "pwd", $0.alias) }.map { $0.alias }, [])
        case "sameowner":
            guard let first = DB.listPwds(mac).filter({ base.pwd.contains($0.alias) }).first?.owner ?? DB.listFps(mac).filter({ base.fp.contains($0.batch) }).first?.owner else {
                return base }
            return (DB.listPwds(mac).filter { $0.owner == first && !isArchived(mac, "pwd", $0.alias) }.map { $0.alias },
                    DB.listFps(mac).filter { $0.owner == first && !isArchived(mac, "fp", $0.batch) }.map { $0.batch })
        case "samekind":
            let anyPwd = !base.pwd.isEmpty
            return anyPwd ? (DB.listPwds(mac).filter { !isArchived(mac, "pwd", $0.alias) }.map { $0.alias }, [])
                          : ([], DB.listFps(mac).filter { !isArchived(mac, "fp", $0.batch) }.map { $0.batch })
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
    // 527 智能列表的"整表是否有内容"判定 (原名 `matches(_:_:)`) 与"取某条快照的最新版本"(`latest`)
    // 都在第九十二批删除：两者全库零调用点 (deadscan 的 A/B 档逐条人读确认，同名调用都属于别的类型)。
    // 智能列表的**过滤**规则只有一个真实现身 = CredentialsView.swift:759-767 的 inline filter；
    // 留第二条形状不同、看起来像有主的谓词，正是本仓"半接线"缺陷的经典形态。
    // 要"空列表灰显"这类需求时按当时的真实签名重写即可 (stateString / pwdState / nowSec 都还在用)。
    static func smartListLabel(_ l: CredSmartList) -> String {
        var s = l.name.isEmpty ? "智能列表" : l.name
        if l.owner != "" { s += " · " + (DB.member(l.owner)?.name ?? l.owner) }
        if !l.state.isEmpty {
            s += " · " + ["active": "进行中", "scheduled": "已排期", "expired": "已过期"][l.state, default: l.state]
        }
        return s
    }

    // ---------- 361 停用原因回溯 (逐条存, 由 313 的必填原因采集) ----------
    // 台账在停用后就没有这条凭证了, 详情卡无从打开 —— 所以回显落在回收站行 (CredBinView)。
    struct DisableMark: Codable {
        var label: String    // 313 四选一的中文标签
        var at: Double
        var via: String      // 真实来源只有本机这几条路径, 不写"操作端"这种无法证实的值
    }
    static func disReasonKey(_ mac: String) -> String { "kf_cdisrea_" + mac }
    static func disableMark(_ mac: String, kind: String, key: Int) -> DisableMark? {
        (DB.store.get([String: DisableMark].self, disReasonKey(mac)) ?? [:])["\(kind):\(key)"]
    }
    static func markDisabled(_ mac: String, kind: String, keys: [Int], label: String, via: String) {
        guard !keys.isEmpty else { return }
        var m = DB.store.get([String: DisableMark].self, disReasonKey(mac)) ?? [:]
        let now = Date().timeIntervalSince1970
        for k in keys { m["\(kind):\(k)"] = DisableMark(label: label, at: now, via: via) }
        // 只留最近 200 条: 这是回溯用的便签, 不是第二本台账, 不该无限增长
        if m.count > 200 {
            let keep = m.sorted { $0.value.at > $1.value.at }.prefix(200)
            m = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        DB.store.setCodable(disReasonKey(mac), m)   // 注意层间参数序相反: store.setCodable(键,值), DB.setCodable(值,键)
    }
    /// 361 回显文案: 停用原因 + 时刻 + 来源路径; 没有标记 (非本 App 停用) 就不编造
    static func disableMarkText(_ mac: String, kind: String, key: Int) -> String? {
        guard let d = disableMark(mac, kind: kind, key: key) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return "停用原因 \(d.label) · \(f.string(from: Date(timeIntervalSince1970: d.at))) · \(d.via) (361)"
    }

    // ---------- 355/914 组织偏好持久化 ----------
    // kf_ccred_prefs 只有 bit0 是分组模式 (setGroupMode 的掩码一直是这么写的), 其余位留给后续偏好。
    // CredGroupMode 此前是"另一套没人用的表示", UI 拿裸 Int 比 == 1 → 让枚举成为唯一口径。
    static var groupMode: CredGroupMode {
        CredGroupMode(rawValue: DB.store.getInt("kf_ccred_prefs", 0) & 1) ?? .type
    }
    static var sortKey: CredSortKey { CredSortKey(rawValue: DB.store.getInt("kf_ccred_sort", 3)) ?? .expiry }
    static var aliasDisplay: Bool { DB.store.getBool("kf_calias_display", true) }
    static func setGroupMode(_ v: CredGroupMode) {
        let prefs = DB.store.getInt("kf_ccred_prefs", 0)
        DB.store.set("kf_ccred_prefs", (prefs & ~1) | (v.rawValue & 1))
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
        var cal = WeekCal.gregorian
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
        let cal = WeekCal.gregorian
        return DB.listPwds(mac).filter { p in
            guard let to = expiryDate(p) else { return false }
            return cal.isDate(to, inSameDayAs: date)
        }
    }

    // ---------- 364 恢复窗口期 (7 天内可一键恢复, 超期需重新下发) ----------
    static func withinRecoverWindow(_ mac: String, entry: CredBinEntry) -> Bool {
        // 单位口径：秒 —— `CredBinEntry.at` 写的是 `nowSec` (本文件 :249)，与 LedgerPwd.at 的毫秒**不是**一把尺。
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
            let t = ZKProtocol.protoSecondsToUnix(Int64(l.lockTime))
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
        Task {
            do { try await UNUserNotificationCenter.current().add(req) }
            catch { CredentialOrg.notifyLog.error("月度清理通知排期失败 err=\(String(describing: error), privacy: .public)") }
        }
    }

    // ---------- 通知分派 (App 前台时由 didReceive 转发; 后台由系统弹出) ----------
    // 只认全仓真实排期过的标识: `c6.alert.<mac>.p<alias>.d7|.d3|.d1|.h24|.h2|.t0` (scheduleAlerts) 与 `c6.monthly`
    // (scheduleMonthlySweep)。旧版里的 c6.expired / c6.center / c6.queue / c6.restore.* 没有任何生产者
    // (grep 全仓仅命中这个函数自身), 属"分派一个不存在的通知" → 删掉而不是留着装作能跳。
    enum Action {
        case locatePwd(mac: String, alias: Int)
        case panel(String)          // 面板名: 与 CredentialsView.consumeCredPanel 同一词表
    }
    static func handleNotificationAction(_ id: String) -> Action? {
        // 标识形如 c6.alert.<mac>.p<alias>.d7 —— MAC 归一化后是纯 hex (无点), 按 "." 切是安全的
        let parts = id.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        if parts.count == 5, parts[0] == "c6", parts[1] == "alert", parts[3].hasPrefix("p"),
           let alias = Int(parts[3].dropFirst(1)), alias > 0, !parts[2].isEmpty {
            return .locatePwd(mac: parts[2], alias: alias)
        }
        if id == "c6.monthly" { return .panel("organize") }   // 文案就写着"到「凭证」点「整理」"
        return nil
    }
    /// 366/1013 通知落地 (此前 handleNotificationAction 零调用 = 点通知什么也不发生)。
    /// 只走已有的两条跳法: 单条凭证定位 (577) 与面板打开; 应用锁没开时值一直挂着, 解锁后才落地。
    @MainActor static func applyNotification(_ a: Action) {
        guard let app = AppState.hostRef else { return }
        app.tabSelection = 1
        switch a {
        case .locatePwd(let mac, let alias):
            if !mac.isEmpty, DB.keychain(mac) != nil { app.select(mac) }   // 陌生 MAC 不改当前锁
            app.pendingCredNav = "pwd:\(alias)"
            app.pendingCredNavMac = mac
        case .panel(let p):
            app.pendingCredPanel = p
        }
    }

    // ================= 包5 凭证工坊辅助 (纯本地推断, 不新增协议命令) =================
    // 展示层语义纪律: 锁端一次性/周期/暂停未定义 (CAPABILITY §4), 所有推断值 UI 必须带"约"字。

    // ---------- 304 全库重复拦截 ----------
    static func duplicatePwdValues(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        DB.listPwds(mac).filter { $0.pwd == value && $0.alias != excluding }
    }
    /// 跨锁同值 (304 "全库"): 只报**其它锁**的显示名 (去重)。
    /// 旧版 `duplicatePwdValuesAnyLock` 返回 [LedgerPwd] 却不带 mac —— 调用方拿到条目也说不出是哪把锁,
    /// 还把当前锁的其它别名一起算进来, 与上面的同锁检查重复计数。改成直接给一句警告需要的信息。
    static func duplicatePwdLockNames(_ value: String, excludingMac: String) -> [String] {
        guard !value.isEmpty else { return [] }
        var names: [String] = []
        for k in DB.keychains() where k.mac != excludingMac {
            guard DB.listPwds(k.mac).contains(where: { $0.pwd == value }) else { continue }
            let n = LockArchive.displayName(k)
            if !names.contains(n) { names.append(n) }
        }
        return names
    }
    /// 314 前缀混淆: 同锁内其它密码前 4 位相同, 口头易混淆
    static func prefixConflict(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        guard value.count >= 4 else { return [] }
        let pre = value.prefix(4)
        return DB.listPwds(mac).filter { $0.alias != excluding && $0.pwd?.hasPrefix(pre) == true }
    }

    // ---------- 305 老旧巡检: 台账只记**添加**时刻, 标"约" ----------
    /// ⚠ 数据源实况 (逐行读过 Store.swift 的三条写口): `addPwd` 落 `at`, 而 `rePwd` (改值) 与
    ///   `setPwdPeriod` (改期) **都不回写 `at`** —— 所以这里的"天数"是"这条台账添加至今"的天数,
    ///   不是"这个码值有多久没换"。锁端也没有最后修改字段 (CAPABILITY §3: 日志无凭证身份、无修改时刻),
    ///   本机又没留改值时刻的字段, 于是换没换过值只能反查 487 版本快照那条路, 不在本函数口径内。
    ///   因此不新增持久化字段 (避开 swiftshape R3 的合成 Codable 雷区), UI 侧文案照这里的口径写:
    ///   添加于约 N 天前, 台账无改值时刻、这段时间没留下换码记录。
    // ---------- 9 凭证风险体检 (安全审计卡) ----------
    struct PwdRisk: Identifiable {
        var id: String { kind + "|" + mac + "|" + String(alias) }
        let kind: String        // 同值 / 超期 / 弱口令
        let mac: String
        let alias: Int
        let lockName: String
        let detail: String
    }
    /// 9 安全审计: 全库密码风险清单 (**只读扫描**, 不写任何东西)。
    /// 三类判据都写死在代码里, 不编"强度评分": 同值 (同一串值出现在多条凭证上)、
    /// 超期 (添加至今 > maxAgeDays)、弱口令 (少于 6 位 / 全部同数字 / 连续递增递减)。
    /// 归属与锁名走既有口径 (769 LockArchive.displayName), 处置动作仍在凭证 Tab 的改码 (305/306)。
    static func passwordRisks(maxAgeDays: Int = 180) -> [PwdRisk] {
        var byValue: [String: [(mac: String, alias: Int, lock: String)]] = [:]
        var all: [(mac: String, lock: String, p: LedgerPwd)] = []
        for kc in DB.keychains() {
            let lock = LockArchive.displayName(kc)
            for p in DB.listPwds(kc.mac) {
                all.append((kc.mac, lock, p))
                let v = (p.pwd ?? "").trimmingCharacters(in: .whitespaces)
                if v.count >= 4 { byValue[v, default: []].append((kc.mac, p.alias, lock)) }
            }
        }
        var out: [PwdRisk] = []
        for (mac, lock, p) in all {
            let v = (p.pwd ?? "").trimmingCharacters(in: .whitespaces)
            if v.count >= 4, let dup = byValue[v], dup.count > 1 {
                out.append(PwdRisk(kind: "同值", mac: mac, alias: p.alias, lockName: lock,
                                   detail: "与另外 \(dup.count - 1) 条凭证同值"))
            }
            if let age = pwdAgeDays(p), age > maxAgeDays {
                out.append(PwdRisk(kind: "超期", mac: mac, alias: p.alias, lockName: lock,
                                   detail: "添加至今 \(age) 天未改"))
            }
            if let why = weakReason(v) {
                out.append(PwdRisk(kind: "弱口令", mac: mac, alias: p.alias, lockName: lock, detail: why))
            }
        }
        return out
    }
    /// 弱口令三条判据 (都可证伪; 不评"强度分"): 少于 6 位 / 全部同一位 / 连续递增递减
    static func weakReason(_ v: String) -> String? {
        guard !v.isEmpty else { return nil }
        if v.count < 6 { return "少于 6 位" }
        if Set(v).count == 1 { return "全部同一位数字" }
        let digits = v.compactMap { $0.wholeNumberValue }
        if digits.count == v.count, digits.count >= 3 {
            var up = true, down = true
            for i in 1..<digits.count {
                if digits[i] != digits[i - 1] + 1 { up = false }
                if digits[i] != digits[i - 1] - 1 { down = false }
            }
            if up || down { return "连续递增/递减序列" }
        }
        return nil
    }
    static func pwdAgeDays(_ p: LedgerPwd) -> Int? {
        guard p.at > 0 else { return nil }
        // 单位口径：毫秒 —— LedgerPwd.at 写的是 `timeIntervalSince1970 * 1000` (见 CredentialStudio 提交那两处)，先除回秒再算天数。
        return Int(max(0, (nowSec - p.at / 1000)) / 86400)
    }
    /// 305 超阈值建议换码: 阈值量的是**添加至今** (见上面 pwdAgeDays 的数据源实况), 不是"未换值天数"。
    static func isStalePwd(_ p: LedgerPwd, days: Int = 180) -> Bool {
        (pwdAgeDays(p) ?? 0) > days
    }
    /// 305 的"换没换过值"到底能不能证实? 台账那侧不能 (at 不回写), 但 487 版本快照那侧能查一角:
    /// 改造密码 (306/307) 与重新下发落到别的别名时都会留一档快照, 备注里写着这两件事。
    /// 所以这里只回答"**本机快照里查得到改值留档吗**", 查不到也不等于没换过 (非本 App 改的值本机无痕) ——
    /// UI 两句都要照这个口径说, 不许说成"多少天没换码"。不新增持久化字段, 读的就是既有 kf_chist_ 键。
    static func hasReRecordSnapshot(_ mac: String, _ p: LedgerPwd) -> Bool {
        history(mac, "pwd", p.alias).contains { $0.note.contains("改造") || $0.note.contains("重新下发") }
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
    // 这一族的文案与数据源是**同一份**判据, 不各说一套; 也不许把"约"写成精确:
    // docs/CAPABILITY.md §3 写明 cmd16 日志每条只有 [type][len][idx][lockTime][body],
    // **无 alias / 无指纹批号**这类身份字段 ⇒ "谁用它开的门"只能拿凭证自己的时间窗去框。
    // 约族核对结论: 311/316/320/332 四处 UI 小字与下面这几个函数的口径本就对齐, 本轮不动;
    // 333 原只滤下界 (超窗的旧日志也会命中, 见 firstUse 的补界)、335/326 的小字原把"时间窗推断"
    // 说成"本地计次" —— 这两处已改成与数据源同一句话。
    /// 311 同码引用: 时间窗内用它"开过的门"计数 (无 alias 日志字段, 按时间窗推断, 标"约")
    static func openCountInWindow(_ mac: String, p: LedgerPwd) -> Int {
        guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return 0 }
        return DB.readLogs(mac).filter { log in
            guard log.type == 2 || log.type == 4 else { return false }
            let t = ZKProtocol.protoSecondsToUnix(Int64(log.lockTime))
            return f.timeIntervalSince1970 <= t && t <= to.timeIntervalSince1970
        }.count
    }
    /// 316 档案三行统计 / 320 误识档案: 最近一次使用 (⚠ 锁端开门日志无凭证身份字段, 全是时间窗推断)
    /// 旧写法取"数组首条命中"当最近使用 —— writeLogs 是"新抓的拼在旧缓存前", 数组序不等于时间序,
    /// 跨多次拉取合并后更不保证; 一律改成取最大时间戳。
    /// 第九十一批删掉了单条版 `inferredLastUse(_:pwdAlias:)`：现役只有批量版
    /// `inferredLastUseMap` (919 起的注释就写着"逐条调会让排序在每帧重解一遍日志")，
    /// 单条版全仓零调用点，留着一份更慢的入口只会让人误调用它。
    /// 316/914 批量版: 一次读日志算完全部凭证。
    static func inferredLastUseMap(_ mac: String) -> [Int: Double] {
        let opens = openTimes(mac)
        guard !opens.isEmpty else { return [:] }
        var out: [Int: Double] = [:]
        for p in DB.ledger(mac).pwds {
            if let t = lastUse(of: p, opens: opens) { out[p.alias] = t }
        }
        return out
    }
    private static func openTimes(_ mac: String) -> [Double] {
        DB.readLogs(mac).filter { $0.type == 2 || $0.type == 4 }
            .map { ZKProtocol.protoSecondsToUnix(Int64($0.lockTime)) }
    }
    /// 临时凭证: 只算落在它自己时间窗内的开门 (时间窗就是它唯一的归属依据)。
    /// 长期凭证: 日志无法指认是哪条密码开的门, 只能给"这把锁最近一次开门" —— 同锁各条数值相同,
    /// 所以调用方拿到它只能当锁级参考, 不能当成"这条凭证被用过"。
    private static func lastUse(of p: LedgerPwd, opens: [Double]) -> Double? {
        if p.temp {
            guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return nil }
            let lo = f.timeIntervalSince1970, hi = to.timeIntervalSince1970
            return opens.filter { $0 >= lo && $0 <= hi }.max()
        }
        return opens.max()
    }
    /// 316 指纹档案统计: 近 30 天 type3 (指纹开门) 日志条数 — ⚠ 日志无指纹身份字段, 只能按锁整体推断, 标"约"
    static func fpUseCount30d(_ mac: String) -> Int {
        let cut = nowSec - 30 * 86400
        return DB.readLogs(mac).filter { l in
            guard l.type == 3 else { return false }
            return ZKProtocol.protoSecondsToUnix(Int64(l.lockTime)) >= cut
        }.count
    }
    /// 320 误识计数: 本地日志 type13 (指纹告警) 出现次数 — ⚠ 锁端语义待实测, 只做展示标"约"
    static func fpAlarmLogCount(_ mac: String) -> Int {
        DB.readLogs(mac).filter { $0.type == 13 }.count
    }
    /// 326/335 计次退役与用量刻度: 锁端**无计次字段**, 所以这里数的是"这条凭证自己的时间窗里
    /// 本地开门日志 (type4) 有几条" —— 不是锁报过的用量, 也不保证每一条都真用它开过门
    /// (CAPABILITY §3: 日志无凭证身份字段)。UI 小字与这句同一口径: 按本地开门日志时间窗推断。
    static func usageCount(_ mac: String, p: LedgerPwd) -> Int {
        guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return 0 }
        return DB.readLogs(mac).filter { log in
            guard log.type == 4 else { return false }
            let t = ZKProtocol.protoSecondsToUnix(Int64(log.lockTime))
            return f.timeIntervalSince1970 <= t && t <= to.timeIntervalSince1970
        }.count
    }
    /// 333 首用回执: 时间窗内**最早**一条开门日志 (⚠ 无 alias 字段, 按时间推断, 标"约")。
    /// 上界必须一起滤: 原写法只滤了下界 `t >= from`, 于是窗口外(到期之后)的旧日志也会命中,
    /// 完成页就会指着一条早就失效的码说"约在某时有人用它开过门"。同一族的 311/326/335
    /// 两个界都滤 (openCountInWindow / usageCount), 这里补齐后才谈得上"同源"。
    static func firstUse(_ mac: String, p: LedgerPwd) -> Double? {
        guard let f = parseLocal(p.from), let hi = parseLocal(p.to) else { return nil }
        let lo = f.timeIntervalSince1970
        let upper = hi.timeIntervalSince1970
        var hit: Double? = nil
        for l in DB.readLogs(mac) where l.type == 2 || l.type == 4 {
            let t = ZKProtocol.protoSecondsToUnix(Int64(l.lockTime))
            guard t >= lo, t <= upper else { continue }
            hit = hit == nil ? t : min(hit!, t)
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

    // ---------- 331 提前失效滑杆 (本地意图, 不改协议; 到点只作提示, 不自动下发停用) ----------
    // 备案口径见 docs/DEFERRED.md 包5 的 331 那一行: 滑杆只写 kf_cestudy_earlyexp_, 不改协议。
    // 这里补的是那两个判据 (原文件只有键的读写, 没有任何地方真的算过到没到点):
    //  · `effectiveExpiry` = 锁端到期时刻减掉本机设的提前量, 是**本机自己的一把尺**;
    //  · `isEarlyExpired`  = 当前时刻有没有越过那把尺。
    // ⚠ 越过它**不会**给锁发任何命令, 门锁在自己那份到期时刻之前照样开门 ——
    //   到点只提示停用 (详情页顶部提醒条 + 状态行标注), 要不要真停用仍由人决定。
    /// 331 本地提前失效时刻; 滑杆为 0 时就等于锁端到期时刻, 长期有效 (2118) 无到期点 ⇒ nil。
    static func effectiveExpiry(_ mac: String, _ p: LedgerPwd) -> Date? {
        guard let to = expiryDate(p) else { return nil }
        let m = earlyExpireMin(mac, p.alias)
        guard m > 0 else { return to }
        return to.addingTimeInterval(-Double(m) * 60)
    }
    /// 331 是否已过本机设定的提前失效时刻。`now` 由调用方给一次、两处提示共用 (顶部提醒条与状态行
    /// 同帧同判据), 不留隐式 Date() —— 隐式取时刻会让同一屏里两条结论各自漂。没设提前量恒 false。
    static func isEarlyExpired(_ mac: String, _ p: LedgerPwd, _ now: Date) -> Bool {
        guard earlyExpireMin(mac, p.alias) > 0, let e = effectiveExpiry(mac, p) else { return false }
        return now >= e
    }
    /// 331 详情页状态行的后缀: 设了提前量才给, 没设就空串 (提示语不吹一件没设过的事)。
    static func earlyExpiryNote(_ mac: String, _ p: LedgerPwd) -> String {
        let m = earlyExpireMin(mac, p.alias)
        guard m > 0, let e = effectiveExpiry(mac, p) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return " · 本机提前 " + String(m) + " 分钟 (331, 约 " + f.string(from: e) + ", 锁端未改)"
    }
    static func earlyExpireMin(_ mac: String, _ alias: Int) -> Int {
        DB.store.getInt("kf_cestudy_earlyexp_" + mac + "_" + String(alias), 0)
    }
    static func setEarlyExpireMin(_ mac: String, _ alias: Int, _ m: Int) {
        DB.store.set("kf_cestudy_earlyexp_" + mac + "_" + String(alias), m)
    }

    // ---------- 341/343/346 OTP 独立口令组与静态备份码 (纯本地, 不走锁端) ----------
    // 341 有两条入口 (otpauth:// 文本导入 + 手工添加), 但只有一份落库形状 = 下面这个 TOTPEntry:
    // 解析在 UI 侧的 StudioTools.parseOtpAuth, 两条路都经 `addTotp` 落库 ⇒ 存、读、备份只有一套字段。
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
    /// 343 独立口令的存档键**带 mac**, 这是刻意的: 口令的算法与锁协议毫无关系 (HMAC-TOTP, 手机自己算),
    /// 但备份是**按锁导出**的 (凭证分区一锁一包, 见 `exportPackage` 与 BackupStudioKit),
    /// 去掉 mac 就会把 A 锁的包里混进 B 锁的口令、还原时又一并倒回去。
    /// ⚠ 所以别把键名读成"这些口令属于这把锁": 它只是**按当前锁分格存放**, 换一把锁看的就是另一组。
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

    // ---------- 337/171 独立 TOTP 时窗 ----------
    // 倒计时的唯一实现是 WindowBar.remaining (CredentialStudio.swift:238, 同一公式 per - epoch % per)。
    // 这里曾有 totpRemaining —— 与它逐字重复且全仓零调用, 留着只会让人以为有两套口径。
    // (⚠ 锁端 ZOTP 为分钟级, 秒级只属独立口令)
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
        let o = ownerName(p.owner)
        if !o.isEmpty { return "\(o) 的密码 #\(p.alias)" }
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
    /// 331 列表侧倒计时: 设过本机提前量时改按 effectiveExpiry 这把本机尺读数, 并标 "(本机提前)";
    /// 没设就与 countdown 完全同值 (不吹一件没设过的事)。now 由调用方给一次, 与同行"提前失效"胶囊同帧同判据。
    /// 越线但锁端未到期时如实说"锁端未到" —— 提示不是指令, 锁端没被改过。
    static func listCountdown(_ mac: String, _ p: LedgerPwd, _ now: Date) -> String {
        guard earlyExpireMin(mac, p.alias) > 0, let e = effectiveExpiry(mac, p) else {
            return countdown(p)
        }
        let d = e.timeIntervalSince(now)
        if d <= 0 {
            // 锁端也已过期时按锁端事实报 —— 提前线在先, 更硬的事实在锁端
            return now >= (expiryDate(p) ?? e) ? countdown(p) : "已过本机提前线 (锁端未到)"
        }
        let day = Int(d / 86400)
        if day >= 1 { return "剩 \(day) 天 (本机提前)" }
        let h = Int(d / 3600)
        if h >= 1 { return "剩 \(h) 小时 (本机提前)" }
        return "剩 \(Int(d / 60)) 分钟 (本机提前)"
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
        f.locale = Locale(identifier: "en_US_POSIX")
        let diff = -d.timeIntervalSinceNow
        let abs = f.string(from: d)
        if diff < 60 { return "刚刚 · " + abs }
        if diff < 3600 { return String(Int(diff / 60)) + " 分钟前 · " + abs }   // 16: 两档不再同写"刚刚"
        return abs
    }
}
