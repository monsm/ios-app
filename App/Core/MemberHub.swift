// 包13 成员·家庭协作 — 数据层扩展 (纯本地, 不动协议层与备份包 schema)
// 全部走 kf_* 键存本地: 角色/备注/分组/归档/代管/紧急管理员等档案扩展 (kf_member_ext),
// 流转 (467 移交 472 借用 483 家政窗 474 处置), 家庭场景 (481 轮值 480 关怀 475 便签 484 欢迎语),
// 聚合 (794 隐私浏览限时 791 认领 793 访客虚拟分组常量)。
// 活跃度一律台账+归属推断 (⚠262/459/466: 日志无身份字段), 展示层强制带"约"。
import Foundation

/// 成员档案扩展 (包13): 挂在成员 id 上, 不动 Member 结构体 (备份互通不受影响)
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
    var welcome: String = ""         // 484 访客欢迎语 (归属靠时间推断, 展示带"约")
    var note: String = ""            // 475 家庭便签 (与成员绑定)
}

/// 472 借用登记 (per-lock)
struct MemberBorrow: Codable {
    var by: String        // 借用人
    var due: String       // 归还日 "yyyy-MM-dd"
    var at: Double       // 登记时刻
}

/// 483 家政周期预设 (⚠降级: 协议无循环时段, 只做整段起止窗)
struct HouseWin: Codable {
    var from: String      // "yyyy-MM-dd HH:mm:ss"
    var to: String
    var label: String
}

enum MemberHub {
    // 793 访客虚拟分组: 只存在于本地展示层, 绝不写入锁端凭证表
    static let visitorId = "__visitor"
    /// 访客虚拟行判定: 临时码类记录且无可证明归属 (与 793 "不与家人混淆" 的独立分组)
    static func isVisitorRow(kind: String?, whoId: String?) -> Bool {
        kind == "temp" && whoId == nil
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
    /// 现在的真读点: 成员页点名 (权限与应急段) + 482 家庭会议摘要 + 设置-安全 救援码下的保管人声明
    /// (SecurityCenterView.rescueCustodyLine) 三处各读一次。
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
    static func activity(_ id: String) -> Activity {
        var a = Activity()
        let now = Date().timeIntervalSince1970
        let mStart = WeekCal.gregorian.dateInterval(of: .month, for: Date())!.start.timeIntervalSince1970
        for kc in DB.keychains() {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            for (i, r) in rows.enumerated() where r.who == id {
                let unix = ZKProtocol.protoSecondsToUnix(Int64(logs[i].lockTime))
                if unix >= now - 30 * 86400 { a.opens30 += 1 }
                if unix >= mStart { a.month += 1 }
                if logs[i].lockTimeStr > a.last { a.last = logs[i].lockTimeStr }
            }
            a.owns += DB.listPwds(kc.mac).filter { $0.owner == id }.count
            a.owns += DB.listFps(kc.mac).filter { $0.owner == id }.count
        }
        return a
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

    // ---------- 473 授权来源统计 (本地可证明: 版本历史快照注记) ----------
    static func sourceCounts(_ id: String) -> (created: Int, moved: Int, restored: Int) {
        var created = 0, moved = 0, restored = 0
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) where p.owner == id {
                // 2026-10-14: 快照表把 auto 版排在末尾 ⇒ .last 常是较旧的自动快照; 取版本号最大者。
                let snap = CredentialOrg.history(kc.mac, "pwd", p.alias).max { $0.version < $1.version }
                if let s = snap, s.note.hasPrefix("移交") { moved += 1 }
                else if let s = snap, s.note.hasPrefix("恢复") { restored += 1 }
                else { created += 1 }
            }
            for f in DB.listFps(kc.mac) where f.owner == id {
                let snap = CredentialOrg.history(kc.mac, "fp", f.batch).max { $0.version < $1.version }
                if let s = snap, s.note.hasPrefix("移交") { moved += 1 }
                else if let s = snap, s.note.hasPrefix("恢复") { restored += 1 }
                else { created += 1 }
            }
        }
        return (created, moved, restored)
    }

    // ---------- 476 归属图谱 (谁创建给谁, 两列自绘) ----------
    struct Edge {
        var label: String   // 凭证描述
        var peer: String    // 对端成员名
        var direction: String // "out" 我创建的给对方 / "in" 对方转给我的
    }
    /// 移交注记的**落盘前缀** = CredentialOrg.batchTransfer 写进版本历史的那一条: 「移交 → 使用人」。
    /// 原先这里判 hasPrefix("移交给") —— 两个字符串永不相等, 条件还与 owner != id 互斥,
    /// 于是图谱恒为占位句, 而界面写的是"移交后这里会画出创建人→使用人"。改成与真实注记同源。
    private static let transferNotePrefix = "移交 → "
    /// 图谱上限: 逐条凭证都要解一次版本历史, 这是展示层不是台账层, 扫到够画就停。
    private static let graphCap = 24

    static func graph(_ id: String) -> [Edge] {
        var out = [Edge]()
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) {
                if out.count >= graphCap { break }
                appendEdge(&out, forMe: id, label: "密码 #" + String(p.alias),
                           snaps: CredentialOrg.history(kc.mac, "pwd", p.alias),
                           ownerOf: { $0.pwd?.owner })
            }
            for f in DB.listFps(kc.mac) {
                if out.count >= graphCap { break }
                appendEdge(&out, forMe: id, label: "指纹「" + f.name + "」",
                           snaps: CredentialOrg.history(kc.mac, "fp", f.batch),
                           ownerOf: { $0.fp?.owner })
            }
        }
        return out
    }
    /// 一条凭证能画出的边: 取**最后一条**「移交 → X」快照 —— 它存的是移交之后的归属,
    /// 版本号比它小的那一版存的就是移交之前的归属 (按 version 找上一版, 不按数组下标:
    /// CredentialOrg.snapshot 落盘时把 488 的自动还原点单独排在手动版之后, 下标不等于时间序)。
    /// 两端都只在本机版本历史留得下来时才知道; 查不到上一手 (最早一版就已经是移交) 就不画,
    /// 也不拿一个"家庭成员"顶上 (原先的 in 边就编过这个名字)。
    private static func appendEdge(_ out: inout [Edge], forMe id: String, label: String,
                                   snaps: [CredSnapshot], ownerOf: (CredSnapshot) -> String?) {
        guard let hit = snaps.lastIndex(where: { $0.note.hasPrefix(transferNotePrefix) }) else { return }
        let s = snaps[hit]
        let to = ownerOf(s)
        let prev = snaps.filter { $0.version < s.version }.max(by: { $0.version < $1.version })
        let from = prev.flatMap(ownerOf)
        if let from, from == id, to != id {
            out.append(Edge(label: label, peer: peerName(to), direction: "out"))
        } else if let from, to == id, from != id {
            out.append(Edge(label: label, peer: peerName(from), direction: "in"))
        }
    }
    /// 对端显示名: 成员真在名册里才报名字; 已删/未指派一律写"未指派", 不编一个看起来像名字的词。
    private static func peerName(_ id: String?) -> String {
        guard let id, let m = DB.member(id) else { return "未指派" }
        return m.name
    }

    /// 468 代管: 目标成员的 id 集合 (读点三处 — 成员页那一行、482 会议摘要、
    /// 以及凭证页单条停用时往 361 便签里补的那一句「管理员代操作」)。
    /// 锁端没有"代操作"这一位, 所以这一族标注只落本机便签与本机摘要, 不发往锁。
    static var proxyNames: Set<String> {
        // 同上: map 出 [String] 需显式转 Set (调用方 MemberCenterView 用 .contains)
        Set((DB.store.get([String: MemberExt].self, extKey) ?? [:]).filter { $0.value.proxy }.map(\.key))
    }

    // ---------- 472 借用登记 (per-lock) ----------
    static func borrows(_ mac: String) -> [String: MemberBorrow] {
        DB.store.get([String: MemberBorrow].self, "kf_mborrow_" + mac) ?? [:]
    }
    static func saveBorrow(_ mac: String, itemKey: String, _ b: MemberBorrow?) {
        var all = borrows(mac)
        if let b { all[itemKey] = b } else { all.removeValue(forKey: itemKey) }
        DB.store.setCodable("kf_mborrow_" + mac, all)
    }

    // ---------- 483 家政周期预设 (整段起止窗, 降级备案) ----------
    static func houseWin(_ mac: String) -> HouseWin? {
        DB.store.get(HouseWin.self, "kf_house_win_" + mac)
    }
    static func saveHouseWin(_ mac: String, _ w: HouseWin) {
        DB.store.setCodable("kf_house_win_" + mac, w)
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
    static func setDuty(_ memberId: String?) {
        var map = DB.store.get([String: String].self, "kf_duty_week") ?? [:]
        if let memberId { map[weekKey()] = memberId } else { map.removeValue(forKey: weekKey()) }
        DB.store.setCodable("kf_duty_week", map)
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

    // ---------- 794 隐私浏览 (限时 10 分钟) ----------\n    /// 现状: 只有 kf_privacy_until 一个时间戳, 消费方仅成员设置页倒计时回显;\n    /// 794 原句的\"只显示本人数据 + 水印\"两要素未接线 (StatsKit/StatsView 零 privacy 消费), 2026-10-13 文案已按此诚实化。
    static var privacyActive: Bool {
        (DB.store.get(Double.self, "kf_privacy_until") ?? 0) > Date().timeIntervalSince1970
    }
    static var privacyUntilSec: Double { DB.store.get(Double.self, "kf_privacy_until") ?? 0 }
    static func setPrivacy(_ on: Bool) {
        DB.store.set("kf_privacy_until", on ? Date().timeIntervalSince1970 + 600.0 : 0.0)
    }

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

    // ---------- 480 孩子码关怀: 名下临时码 N 天内到期 (台账推断) ----------
    struct CareDue {
        var member: Member
        var days: Int
    }
    static func careDue(_ mac: String) -> [CareDue] {
        var out = [CareDue]()
        let soon = 3 * 86400
        let now = Date().timeIntervalSince1970
        for p in DB.listPwds(mac) where p.temp && !(p.owner ?? "").isEmpty {
            guard let exp = CredentialOrg.expiryDate(p) else { continue }
            let d = exp.timeIntervalSince1970 - now
            guard d >= 0, d <= Double(soon) else { continue }
            guard let owner = p.owner, let m = DB.member(owner) else { continue }
            out.append(CareDue(member: m, days: Int(d / 86400) + 1))
        }
        return out
    }
}
