// 包13 成员·家庭协作 — 数据层扩展 (纯本地, 不动协议层与备份包 schema)
// 全部走 kf_* 键存本地: 角色/备注/分组/归档/代管/紧急管理员等档案扩展 (kf_member_ext),
// 流转 (467 移交 472 借用 483 家政窗 474 处置), 家庭场景 (481 轮值 480 关怀 475 便签 484 欢迎语),
// 聚合 (794 隐私浏览限时 791 认领 793 访客虚拟分组常量)。
// 活跃度一律台账+归属推断 (⚠262/459/466: 日志无身份字段), 展示层强制带"约"。
import Foundation

/// 成员档案扩展 (包13): 挂在成员 id 上, 不动 Member 结构体 (备份互通不受影响)
    // 2026-10-27 审核说明 (AUDIT-A F-32)：`Member` 模型是**本仓独有** ——
    // vendor 没有"家人/成员"概念（它的凭证是平铺的）。
    // 本仓加它是为了归属管理（谁的指纹、谁的密码），属功能增强，不是协议差异。
struct MemberExt: Codable {
    var role: String = "member"      // 458 三档: main / member / guest
    var emoji: String = ""           // 916 emoji 代号 (纯文字头像, 零图片资源)
    var remark: String = ""          // 265/461 备注名 (独立于称呼 relation)
    var commonLocks: [String] = []   // 464 常用锁 (mac 列表)
    var emergency: String = ""       // 465 紧急联系 (姓名+电话, 纯本地)
    var groupTag: String = ""        // 630 分组标签: 家人 / 访客 / 服务人员
    var archived: Bool = false       // 460/795 归档 (保留历史, 默认统计隐藏)
    var proxy: Bool = false          // 468 代管标记 (停用 TA 名下凭证时, 361 便签补一句 管理员代操作)
    var emergencyAdmin: Bool = false // 469 紧急管理员 (本机点名档: 成员页与 482 会议摘要点名; 锁端与救援码本体都不读它)
    var careText: String = ""        // 480 孩子码关怀文案
    var note: String = ""            // 475 家庭便签 (与成员绑定; 成员中心与 vCard 导出在用)
    var welcome: String = ""         // 484 访客欢迎语 (归属靠时间推断, 展示带"约")

    enum CodingKeys: String, CodingKey {
        case role, emoji, remark, commonLocks, emergency, groupTag, archived, proxy, emergencyAdmin, careText, note, welcome
    }

    /// 全默认构造（`MemberHub.ext()` 找不到该成员时用它兜底）。
    /// 加 `init(from:)` 会让合成的逐参数 init 消失，所以这里显式补一个。
    init() {}

    /// 容错解码（2026-10-29）：与 Ledger 家族同一类问题。
    /// 本表是 `[成员id: MemberExt]` 一整个字典存进 UserDefaults ——
    /// 只要**任意一个成员**缺一个字段，合成解码器就让整张表解码失败，
    /// 于是所有人的角色/分组/归档/备注/emoji 全部回落默认值（归档的人会重新出现在名单里）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "member"
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        remark = try c.decodeIfPresent(String.self, forKey: .remark) ?? ""
        commonLocks = try c.decodeIfPresent([String].self, forKey: .commonLocks) ?? []
        emergency = try c.decodeIfPresent(String.self, forKey: .emergency) ?? ""
        groupTag = try c.decodeIfPresent(String.self, forKey: .groupTag) ?? ""
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        proxy = try c.decodeIfPresent(Bool.self, forKey: .proxy) ?? false
        emergencyAdmin = try c.decodeIfPresent(Bool.self, forKey: .emergencyAdmin) ?? false
        careText = try c.decodeIfPresent(String.self, forKey: .careText) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        welcome = try c.decodeIfPresent(String.self, forKey: .welcome) ?? ""
    }
}

/// 472 借用登记 (per-lock)
struct MemberBorrow: Codable {
    var by: String        // 借用人
    var due: String       // 归还日 "yyyy-MM-dd"
    var at: Double       // 登记时刻

    enum CodingKeys: String, CodingKey { case by, due, at }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        by = try c.decodeIfPresent(String.self, forKey: .by) ?? ""
        due = try c.decodeIfPresent(String.self, forKey: .due) ?? ""
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}

enum MemberHub {
    // 793 访客虚拟分组: 只存在于本地展示层, 绝不写入锁端凭证表
    static let visitorId = "__visitor"
    /// 访客虚拟行判定: 临时码类记录且无可证明归属 (与 793 "不与家人混淆" 的独立分组)
    static func isVisitorRow(kind: String?, whoId: String?) -> Bool {
        kind == "temp" && whoId == nil
    }
    /// 468 代管: 目标成员的 id 集合 (读点三处 — 成员页那一行、482 会议摘要、
    /// 以及凭证页单条停用时往 361 便签里补的那一句「管理员代操作」)。
    /// 锁端没有"代操作"这一位, 所以这一族标注只落本机便签与本机摘要, 不发往锁。
    static var proxyNames: Set<String> {
        // 同上: map 出 [String] 需显式转 Set (调用方 MemberCenterView 用 .contains)
        Set((DB.store.get([String: MemberExt].self, extKey) ?? [:]).filter { $0.value.proxy }.map(\.key))
    }

    // ---------- 档案扩展 ----------
    private static let extKey = "kf_member_ext"
    static func ext(_ id: String) -> MemberExt {
        let all = DB.store.get([String: MemberExt].self, extKey) ?? [:]
        return all[id] ?? MemberExt()
    }
    static func saveExt(_ id: String, _ e: MemberExt) {
        var all = DB.store.get([String: MemberExt].self, extKey) ?? [:]
        all[id] = e
        DB.store.setCodable(extKey, all)
    }
    static func archivedIDs() -> Set<String> {
        // map(\.key) 产出 [String], 声明是 Set<String> → 不可隐式转换, 显式包一层
        Set((DB.store.get([String: MemberExt].self, extKey) ?? [:]).filter { $0.value.archived }.map(\.key))
    }
    static func isActive(_ id: String) -> Bool { !ext(id).archived }

    // 458 角色三档
    static let roles = ["main", "member", "guest"]
    static func roleLabel(_ r: String) -> String {
        switch r {
        case "main": return "主理人"
        case "guest": return "访客"
        default: return "成员"
        }
    }

    // ---------- 458/470 角色权限行 (全仓唯一定义) ----------
    /// 470 的权限矩阵此前只在成员页"画"出来给人看, 全仓没有一处按它收起过任何入口 ⇒ 那句话是说明文字。
    /// 这张表现在同时是**判据**: 成员页上真存在的两枚开关按它亮灭 (468 代管走「管凭证」, 469 紧急管理员走「成员管理」),
    /// 矩阵行、角色示例卡、建档向导副标题、名册导出 (415) 的角色注记都从这一处算, 不再各写一份。
    /// 边界照旧写在界面上: 锁端没有角色字段, 这一档不改任何发往锁端的字节, 也不碰备份包 schema。
    static func permRows(_ role: String) -> [(name: String, allowed: Bool)] {
        switch role {
        case "main":
            return [(name: "看记录", allowed: true), (name: "管凭证", allowed: true), (name: "导出", allowed: true),
                    (name: "备份", allowed: true), (name: "成员管理", allowed: true)]
        case "guest":
            return [(name: "看记录", allowed: false), (name: "管凭证", allowed: false), (name: "导出", allowed: false),
                    (name: "备份", allowed: false), (name: "成员管理", allowed: false)]
        default:
            return [(name: "看记录", allowed: true), (name: "管凭证", allowed: true), (name: "导出", allowed: false),
                    (name: "备份", allowed: false), (name: "成员管理", allowed: false)]
        }
    }
    /// 470 判定读点: 某角色在某一项上是否被允许 (查不到的项一律按不允许走, 不做"默认放行")。
    static func permAllows(_ role: String, _ cap: String) -> Bool {
        permRows(role).first { $0.name == cap }?.allowed ?? false
    }
    /// 470 能力名列表 (允许的那几项, 供示例卡与向导副标题现算)
    static func permCan(_ role: String) -> [String] { permRows(role).filter { $0.allowed }.map { $0.name } }
    static func permCannot(_ role: String) -> [String] { permRows(role).filter { !$0.allowed }.map { $0.name } }

    /// 469 紧急管理员: 档案上的点名档。
    /// 原先这个位只有成员页 Toggle 的 set、全仓零读取方, 界面却写"救援码说明与其绑定" ⇒ 空头支票。
    /// 现在的真读点: 成员页点名 (权限与应急段) + 设置-安全 救援码下的保管人声明
    /// （原 SecurityCenterView.rescueCustodyLine，该页已删） 三处各读一次。
    static func emergencyAdmins() -> [Member] {
        // 一次解表再筛名册: 逐成员调 ext() 会把整张表重复解 N 遍 (同 MemberCenterView 归档计数那一处教训)
        let all = DB.store.get([String: MemberExt].self, extKey) ?? [:]
        return DB.members().filter { all[$0.id]?.emergencyAdmin == true }
    }

    // 666 成员名兜底: 超长名中段截断 (头像取首字由 UI 层做)
    static func display(_ m: Member) -> String {
        var n = m.name.isEmpty ? unnamedLabel(m.id) : m.name
        if n.count > 6 {
            n = String(n.prefix(3)) + "…" + String(n.suffix(2))
        }
        return n
    }
    /// 666 编号兜底: 未命名成员不再一律叫"成员" —— 多位未命名时同名分不出人,
    /// 归属、代管开关、记录行都认不出是谁。按名册自然序号给"成员 N" (序号与成员页行序同源)。
    private static func unnamedLabel(_ id: String) -> String {
        let roster = DB.members()
        guard let i = roster.firstIndex(where: { $0.id == id }) else { return "成员" }
        return "成员 \(i + 1)"
    }
    /// 461 双层文本: "称呼（备注）"
    static func doubleLine(_ m: Member) -> String {
        let r = ext(m.id).remark
        return r.isEmpty ? display(m) : display(m) + "（" + r + "）"
    }
    /// 919 时间线别名: 开关开且该成员 relation 非空 → 返回关系称呼 (如「老妈」), 否则 nil (调用方回退真名)。
    /// 只做显示替换 —— 匹配与凭证深链仍走裸名 (owner == whoName 的相等判定不能被别名污染)。
    static func aliasName(_ whoId: String?) -> String? {
        guard let whoId, !whoId.isEmpty, CredentialOrg.aliasDisplay,
              let m = DB.member(whoId), !m.relation.isEmpty else { return nil }
        return m.relation
    }

    // ---------- 活跃度推断 (⚠262/459/466: 台账口径, 必须带"约") ----------
    struct Activity {
        var opens30: Int = 0
        var month: Int = 0
        var last: String = ""
        var owns: Int = 0
        /// 久未用 (262 置灰判据): 30 天无可证明归属开门
        var stale: Bool { opens30 == 0 }
    }
    // 2026-10-29 删除：`activity(_:)`（单个成员一次全量扫描）已零调用 —— 成员中心与建档向导
    // 都改用下面的 `activityBundle(_:)`（一次遍历算完全员）。留着它只会让人误以为还有个
    // 「按成员查」的便宜入口，实际是 O(锁 × 日志) 的重活。


    /// 一次算完全员的活跃度 + 访客统计（2026-10-29 性能）。
    ///
    /// 原来 `activity(_:)` 每调一次就要把**每把锁的全部日志**读一遍再做 Attribution 分类；
    /// 而成员中心的每一行要调它 2 次（subLine 的"最近开门/名下"、staleTag 的"久未用"），
    /// 排序还要再来一遍 ⇒ O(成员数² × 锁数 × 日志数)。10 个成员 × 2 把锁 × 100 条日志，
    /// 单次渲染就是 4000 次分类。
    ///
    /// 这里改成**一次遍历**：外层走锁，内层把每条归属结果直接累加到对应成员；
    /// 顺带把访客虚拟分组的两项统计（开门数 / 名下临时码数）一起算出来。
    struct ActivityBundle {
        var table: [String: Activity] = [:]
        var visitorOpens = 0
        var visitorTemps = 0
    }

    static func activityBundle(_ ids: [String]) -> ActivityBundle {
        var b = ActivityBundle()
        for id in ids { b.table[id] = Activity() }
        let now = Date().timeIntervalSince1970
        let mStart = WeekCal.gregorian.dateInterval(of: .month, for: Date())?.start.timeIntervalSince1970 ?? now
        for kc in DB.keychains() {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let pwds = DB.listPwds(kc.mac)
            let fps = DB.listFps(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: pwds, fps: fps,
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            for (i, r) in rows.enumerated() {
                if isVisitorRow(kind: r.kind, whoId: r.who) { b.visitorOpens += 1 }
                guard let who = r.who, var a = b.table[who] else { continue }
                let unix = ZKProtocol.protoSecondsToUnix(Int64(logs[i].lockTime))
                if unix >= now - 30 * 86400 { a.opens30 += 1 }
                if unix >= mStart { a.month += 1 }
                if logs[i].lockTimeStr > a.last { a.last = logs[i].lockTimeStr }
                b.table[who] = a
            }
            for p in pwds {
                if p.temp { b.visitorTemps += 1 }
                if let o = p.owner, !o.isEmpty, var a = b.table[o] { a.owns += 1; b.table[o] = a }
            }
            for f in fps {
                if let o = f.owner, !o.isEmpty, var a = b.table[o] { a.owns += 1; b.table[o] = a }
            }
        }
        return b
    }
    /// 799 成员周小结一句人话 (跨全部锁): 近 7 天可证明归属次数 + 工作日最活跃小时段, 归属不出不计
    static func weekSentence(_ id: String) -> String? {
        let cutoff = Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970
        var n = 0
        var byHour = [Int: Int]()
        for kc in DB.keychains() {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: DB.readStatus(kc.mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            for (i, r) in rows.enumerated() where r.who == id {
                let unix = ZKProtocol.protoSecondsToUnix(Int64(logs[i].lockTime))
                guard unix >= cutoff else { continue }
                n += 1
                let d = Date(timeIntervalSince1970: unix)
                if (2...6).contains(WeekCal.gregorian.component(.weekday, from: d)) {
                    byHour[WeekCal.gregorian.component(.hour, from: d), default: 0] += 1
                }
            }
        }
        guard n > 0 else { return nil }
        let name = DB.member(id)?.name ?? "成员"
        if let b = byHour.max(by: { $0.value < $1.value }) {
            return "\(name)近 7 天开门约 \(n) 次, 工作日 \(b.key)–\(b.key + 1) 点最活跃。"
        }
        return "\(name)近 7 天开门约 \(n) 次 (工作日样本不足)。"
    }
    /// 459/789 最近开门摘录 (归属可证明才进, 展示带"约")
    struct Excerpt {
        var time: String
        var text: String
    }
    // 【保留未接 2026-10-29】成员详情「最近记录摘录」—— 成员 360 页的空档补位
    static func recentExcerpts(_ id: String, _ n: Int = 10) -> [Excerpt] {
        var out = [Excerpt]()
        for kc in DB.keychains() {
            let lockName = LockArchive.displayName(kc)
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            var i = 0
            while i < logs.count && out.count < n {
                if rows[i].who == id {
                    let word = Attribution.words[rows[i].kind ?? ""] ?? ""
                    out.append(Excerpt(time: logs[i].lockTimeStr, text: word + " · " + lockName))
                }
                i += 1
            }
        }
        return out.suffix(n).reversed().map { $0 }
    }


    // ---------- 472 借用登记 (per-lock) ----------
    static func borrows(_ mac: String) -> [String: MemberBorrow] {
        DB.store.get([String: MemberBorrow].self, "kf_mborrow_" + mac) ?? [:]
    }


    // ---------- 481 本周轮值 ----------
    private static func weekKey(_ d: Date = Date()) -> String {
        // 912: 周界必须与 Milestones/RecordSearch/月历同一个 Calendar，
        // 否则"本周轮值"和"本周整理数"会在跨周那天各说一套。
        let c = WeekCal.calendar
        return String(c.component(.yearForWeekOfYear, from: d)) + "-W" + String(c.component(.weekOfYear, from: d))
    }
    static var dutyThisWeek: String? {
        let map = DB.store.get([String: String].self, "kf_duty_week") ?? [:]
        return map[weekKey()]
    }

    // ---------- 791 未归属记录认领 (记录 key = idxRaw, 本机覆盖层) ----------
    static func claims(_ mac: String) -> [String: String] {
        DB.store.get([String: String].self, "kf_mclaim_" + mac) ?? [:]
    }
    static func claim(_ mac: String, logKey: String, memberId: String) {
        var all = claims(mac)
        all[logKey] = memberId
        DB.store.setCodable("kf_mclaim_" + mac, all)
    }
    /// 462 合并/迁移归属: 旧成员 id 认领过的记录改判给新成员 ——
    /// 合并只迁凭证不迁认领的话, 合并后这些记录会挂在已不存在的 id 上 (显示成"无法归属")。
    static func reassignClaims(from: String, to: String) {
        for kc in DB.keychains() {
            var all = claims(kc.mac)
            var hit = false
            for (k, v) in all where v == from { all[k] = to; hit = true }
            if hit { DB.store.setCodable("kf_mclaim_" + kc.mac, all) }
        }
    }

    // 794「隐私浏览」—— 2026-10-26 **已删除**（用户决策）。
    //
    // 原实现只写一个 `kf_privacy_until` 时间戳，唯一消费方是成员设置页的倒计时回显；
    // 794 原句承诺的「只显示本人数据 + 水印」两要素从未接线（StatsKit/StatsView 零 privacy 消费）。
    // 一个只写时间戳、不改变任何可见行为的开关，比没有更糟：用户以为自己在保护隐私。
    // 删除而不是补全的理由：真要做就得改统计口径 + 全页水印，那是另一个特性，
    // 而离线的单人锁场景里「给谁看」这个前提本身就不成立。
    //
    // 键名 `kf_privacy_until` 保留在 Store 的族删清单里（老用户升级时会被清掉）。

    // ---------- 479/486 长辈模式 (本机布局档) ----------
    /// 479 这一档真实改的是**凭证页**那一族: 分段只留 全部/密码/指纹 (CredentialsView 分段胶囊)、
    /// 隐藏批量与导出入口、组尾那条过期清理按钮不出现, 行内字号升到语义标题/正文档并把次文本换成主文本色
    /// (大字与高对比都在 CredentialsView 的 rowTitleFont / rowSubFont / rowSubColor 三处消费, 字号全走语义档,
    /// 不写 .system(size:) —— 那一档不跟随 Dynamic Type)。
    /// 486 (长辈模式下临时码完成页默认进口述卡) 已接: 消费点在 CredentialStudio 的 TempCodeStudio.doneCard
    /// (完成页收成 口述卡 + 大「完成」, 329/333/再发一张 收起);
    /// 其余页面仍不跟这一档 —— 成员页的开关说明按这个口径写, 不许它承诺"全 App 大字"。
    static var elderMode: Bool { DB.store.getBool("kf_elder_mode") }
    static func setElderMode(_ on: Bool) { DB.store.set("kf_elder_mode", on) }
}
