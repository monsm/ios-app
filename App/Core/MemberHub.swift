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
    var proxy: Bool = false          // 468 代管标记 (期间操作记"管理员代操作")
    var emergencyAdmin: Bool = false // 469 紧急管理员 (纯本地语义, 绑定救援码说明)
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

/// 467 所有权移交 (待目标成员确认才改归属)
struct MemberTransfer: Codable, Identifiable {
    var id: String
    var mac: String
    var kind: String      // "pwd" / "fp"
    var key: Int
    var from: String      // 原成员 id (源成员)
    var to: String        // 目标成员 id
    var at: Double
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
        (DB.store.get([String: MemberExt].self, extKey) ?? [:]).filter { $0.value.archived }.map(\.key)
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

    // 666 成员名兜底: 超长名中段截断 (头像取首字由 UI 层做)
    static func display(_ m: Member) -> String {
        var n = m.name.isEmpty ? "成员" : m.name
        if n.count > 6 {
            n = String(n.prefix(3)) + "…" + String(n.suffix(2))
        }
        return n
    }
    /// 461 双层文本: "称呼（备注）"
    static func doubleLine(_ m: Member) -> String {
        let r = ext(m.id).remark
        return r.isEmpty ? display(m) : display(m) + "（" + r + "）"
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
        let mStart = Calendar.current.dateInterval(of: .month, for: Date())!.start.timeIntervalSince1970
        for kc in DB.keychains() {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            for (i, r) in rows.enumerated() where r.who == id {
                let unix = Double(ZKProtocol.protoSecondsToMs(Int64(logs[i].lockTime))) / 1000
                if unix >= now - 30 * 86400 { a.opens30 += 1 }
                if unix >= mStart { a.month += 1 }
                if logs[i].lockTimeStr > a.last { a.last = logs[i].lockTimeStr }
            }
            a.owns += DB.listPwds(kc.mac).filter { $0.owner == id }.count
            a.owns += DB.listFps(kc.mac).filter { $0.owner == id }.count
        }
        return a
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
                let snap = CredentialOrg.history(kc.mac, "pwd", p.alias).last
                if let s = snap, s.note.hasPrefix("移交") { moved += 1 }
                else if let s = snap, s.note.hasPrefix("恢复") { restored += 1 }
                else { created += 1 }
            }
            for f in DB.listFps(kc.mac) where f.owner == id {
                let snap = CredentialOrg.history(kc.mac, "fp", f.batch).last
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
    static func graph(_ id: String) -> [Edge] {
        var out = [Edge]()
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) where p.owner == id {
                let snaps = CredentialOrg.history(kc.mac, "pwd", p.alias)
                // 我名下但现在记的是别人的快照 → 我创建后移交出去; 反向看最近一条"移交给 X"
                if let s = snaps.last, s.note.hasPrefix("移交给"), s.pwd?.owner != id {
                    out.append(Edge(label: "密码 #" + String(p.alias), peer: s.note.replacingOccurrences(of: "移交给", with: ""), direction: "out"))
                }
            }
            for f in DB.listFps(kc.mac) where f.owner == id {
                let snaps = CredentialOrg.history(kc.mac, "fp", f.batch)
                if let s = snaps.last, s.note.hasPrefix("移交给"), s.fp?.owner != id {
                    out.append(Edge(label: "指纹「" + f.name + "」", peer: s.note.replacingOccurrences(of: "移交给", with: ""), direction: "out"))
                }
            }
            // 转入方向: 历史里有"移交给 (我名)"
            for p in DB.listPwds(kc.mac) where p.owner == id {
                if CredentialOrg.history(kc.mac, "pwd", p.alias).contains(where: { $0.note.hasPrefix("移交给") }) {
                    out.append(Edge(label: "密码 #" + String(p.alias), peer: "家庭成员", direction: "in"))
                }
            }
            break   // 图谱只取第一把锁的样例, 避免大表全扫描 (纯展示层)
        }
        return out
    }

    // ---------- 467 所有权移交 (待确认区) ----------
    private static let transferKey = "kf_mtransfer"
    static func pendingTransfers(_ memberId: String) -> [MemberTransfer] {
        (DB.store.get([String: MemberTransfer].self, transferKey) ?? [:]).values
            .filter { $0.to == memberId }
            .sorted { $0.at > $1.at }
    }
    static func addTransfer(id: String, mac: String, kind: String, key: Int, from: String, to: String) {
        var all = DB.store.get([String: MemberTransfer].self, transferKey) ?? [:]
        let t = MemberTransfer(id: UUID().uuidString, mac: mac, kind: kind, key: key,
                                from: from, to: to, at: Date().timeIntervalSince1970)
        all[t.id] = t
        DB.store.setCodable(transferKey, all)
    }
    static func rejectTransfer(_ id: String) {
        var all = DB.store.get([String: MemberTransfer].self, transferKey) ?? [:]
        all.removeValue(forKey: id)
        DB.store.setCodable(transferKey, all)
    }
    static func acceptTransfer(_ t: MemberTransfer) {
        if t.kind == "pwd" {
            DB.setPwdOwner(t.mac, t.key, t.to)
            if let p = DB.listPwds(t.mac).first(where: { $0.alias == t.key }) {
                CredentialOrg.snapshot(t.mac, kind: "pwd", key: t.key, pwd: p, fp: nil,
                                       note: "移交" + (DB.member(t.to)?.name ?? ""))
            }
        } else {
            DB.setFpOwner(t.mac, t.key, t.to)
            if let f = DB.listFps(t.mac).first(where: { $0.batch == t.key }) {
                CredentialOrg.snapshot(t.mac, kind: "fp", key: t.key, pwd: nil, fp: f,
                                       note: "移交" + (DB.member(t.to)?.name ?? ""))
            }
        }
        var all = DB.store.get([String: MemberTransfer].self, transferKey) ?? [:]
        all.removeValue(forKey: t.id)
        DB.store.setCodable(transferKey, all)
    }
    /// 468 代管: 目标成员的日志统一标注 (展示层文案用)
    static var proxyNames: Set<String> {
        (DB.store.get([String: MemberExt].self, extKey) ?? [:]).filter { $0.value.proxy }.map(\.key)
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
        let c = Calendar.current
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

    // ---------- 794 隐私浏览 (限时 10 分钟 + 只显示本人数据 + 水印) ----------
    static var privacyActive: Bool {
        (DB.store.get(Double.self, "kf_privacy_until") ?? 0) > Date().timeIntervalSince1970
    }
    static var privacyUntilSec: Double { DB.store.get(Double.self, "kf_privacy_until") ?? 0 }
    static func setPrivacy(_ on: Bool) {
        DB.store.set("kf_privacy_until", on ? Date().timeIntervalSince1970 + 600.0 : 0.0)
    }

    // ---------- 479/486 长辈模式 (本地布局档: 大字 + 凭证页只留密码/指纹) ----------
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
