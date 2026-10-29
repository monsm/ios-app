// CredentialOrg · 状态与到期（已过期 / 即将过期 / 到期日 / 弱口令 / 停用标记 / 智能列表）
// 2026-10-29 从 CredentialOrg.swift 拆出。
import Foundation
@preconcurrency import UserNotifications

extension CredentialOrg {
    /// 永久有效期 (2118) 返回 nil — 不参与到期排序与预警
    static func expiryDate(_ p: LedgerPwd) -> Date? {
        guard !p.to.hasPrefix("2118") else { return nil }
        return parseLocal(p.to)
    }

    static func pwdState(_ p: LedgerPwd) -> Int {
        // 0 进行中 / 1 已排期 / 2 已过期 (按时间窗推断, 一次性语义锁端未定义故不区分)
        if let to = expiryDate(p), to.timeIntervalSinceNow <= 0 { return 2 }
        if let f = parseLocal(p.from), f.timeIntervalSinceNow > 0 { return 1 }
        return 0
    }

    /// 926/930 替代: 7 / 3 / 1 天 + 24 / 2 小时**都**排本地通知, 另加"到期时"一条。
    /// 原 359 把 2 小时档做成"只插列表提醒行, 不排通知"(详情页卡片上写着这句话);
    /// 926/930 判 ❌ 后拍板按替代执行 —— 替代栏原话是"到期前 2 小时与到期时各发本地通知"。
    /// 排程扩到六条, 列表提醒行 (dueSoonPwds) **照旧保留**: 前台多一处提示不是坏事。
    static func scheduleAlerts(_ mac: String, _ p: LedgerPwd, _ a: CredAlert) {
        let id = "c6.alert.\(mac).p\(p.alias)"
        // 2026-10-29 修复（竞态）：原来的顺序是「异步查待处理 → 回调里删旧的」与「下面同步排新的」，
        // 而 getPendingNotificationRequests 的回调是**另一个线程、晚于本函数返回**才跑的 ——
        // 于是它删 stale 时，本函数刚排进去的新通知**也在 pending 列表里**（id 前缀相同），
        // 被一并删掉。表现：改了凭证有效期/提醒档位后，提醒反而**一条都不响**，
        // 而界面上"已排程"照旧显示。
        // 修法：把「删旧 + 排新」整体放进同一个异步序列里，删除先完成再排。
        scheduleAlertsOrdered(id: id, p: p, a: a, mac: mac)
    }

    /// 删旧 → 排新，严格串行（见 scheduleAlerts 的竞态说明）。
    private static func scheduleAlertsOrdered(id: String, p: LedgerPwd, a: CredAlert, mac: String) {
        let c = UNUserNotificationCenter.current()
        c.getPendingNotificationRequests { reqs in
            let stale = reqs.map(\.identifier).filter { $0 == id || $0.hasPrefix(id + ".") }
            let afterRemove: () -> Void = { scheduleAlertsNow(id: id, p: p, a: a, mac: mac) }
            if stale.isEmpty { afterRemove(); return }
            c.removePendingNotificationRequests(withIdentifiers: stale)
            // removePendingNotificationRequests 没有完成回调，但它与 add 都在同一串行队列上；
            // 为了让「删」先于「加」在语义上确定，排新动作再跳一次主队列。
            DispatchQueue.main.async(execute: afterRemove)
        }
    }

    /// 真正排六条提醒（原 scheduleAlerts 的函数体）。
    private static func scheduleAlertsNow(id: String, p: LedgerPwd, a: CredAlert, mac: String) {
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
                    body: "\(name) 到期了， 锁端到这个时刻后不再放行这条凭证。")
    }

    /// 930 凭证 Tab 角标: 近 7 日内到期的条数。
    /// 与 363 月历格、dueSoonPwds 同源同一把尺 (expiryDate), 不另算第二套; 长期有效 (2118) 与归档条不计。
    static func expiringSoonCount(macs: [String], within days: Int = 7) -> Int {
        let limit = nowSec + Double(days) * 86400
        var n = 0
        for mac in macs {
            for p in DB.listPwds(mac) {
                if let to = expiryDate(p) {
                    let t = to.timeIntervalSince1970
                    if t >= nowSec && t <= limit { n += 1 }
                }
            }
        }
        return n
    }

    static func disableMark(_ mac: String, kind: String, key: Int) -> DisableMark? {
        (DB.store.get([String: DisableMark].self, disReasonKey(mac)) ?? [:])["\(kind):\(key)"]
    }

    /// 361 回显文案: 停用原因 + 时刻 + 来源路径; 没有标记 (非本 App 停用) 就不编造
    // 【保留未接 2026-10-29】停用原因回显（用户 B1 未选，保留待接：凭证详情页的停用行）
    static func disableMarkText(_ mac: String, kind: String, key: Int) -> String? {
        guard let d = disableMark(mac, kind: kind, key: key) else { return nil }
        let f = DF.cached("MM-dd HH:mm")
        return "停用原因 \(d.label) · \(f.string(from: Date(timeIntervalSince1970: d.at))) · \(d.via)"   // 361 停用原因
    }

    // ---------- 363 月历到期 (每日格右上角当日到期凭证数) ----------
    // 【保留未接 2026-10-29】月历到期角标（用户 B1 未选，保留待接：凭证页月历视图）
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

    // 【保留未接 2026-10-29】某天到期凭证列表 —— monthDeadlines 的配套读侧，同日历一起接
    static func dayDeadlines(_ mac: String, _ date: Date) -> [LedgerPwd] {
        let cal = WeekCal.gregorian
        return DB.listPwds(mac).filter { p in
            guard let to = expiryDate(p) else { return false }
            return cal.isDate(to, inSameDayAs: date)
        }
    }

    /// 弱口令三条判据 (都可证伪; 不评"强度分"): 少于 6 位 / 全部同一位 / 连续递增递减
    // 【保留未接 2026-10-29】弱口令判据（少于6位/全同位/连续）—— 新密码输入时可用于即时提示
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

    // ---------- 319 重录继承 / 324 冗余横条 ----------
    /// 该成员名下可用指纹数 (0 = 最后一枚 → 删除需双签 323; 冗余横条 324 用全锁口径)
    static func fpCountByOwner(_ mac: String, _ owner: String?) -> Int {
        guard let o = owner else { return 0 }
        return DB.listFps(mac).filter { $0.owner == o }.count
    }

    static func isEarlyExpired(_ mac: String, _ p: LedgerPwd, _ now: Date) -> Bool {
        guard earlyExpireMin(mac, p.alias) > 0, let e = effectiveExpiry(mac, p) else { return false }
        return now >= e
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

}
