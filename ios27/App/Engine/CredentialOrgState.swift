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
        // 2026-11-03（HIG Notifications）：通知授权在**第一次真的排提醒**时才请求，
        // 不在启动时问（真机截图证实启动即弹窗挡住了 6 张子页）。
        NotificationAuth.ensure()
        let id = "c6.alert.\(mac).p\(p.alias)"
        // 2026-10-29 修复（竞态）：原来的顺序是「异步查待处理 → 回调里删旧的」与「下面同步排新的」，
        // 而 getPendingNotificationRequests 的回调是**另一个线程、晚于本函数返回**才跑的 ——
        // 于是它删 stale 时，本函数刚排进去的新通知**也在 pending 列表里**（id 前缀相同），
        // 被一并删掉。表现：改了凭证有效期/提醒档位后，提醒反而**一条都不响**，
        // 而界面上"已排程"照旧显示。
        // 修法：把「删旧 + 排新」整体放进同一个异步序列里，删除先完成再排。
        scheduleAlertsOrdered(id: id, p: p, a: a, mac: mac)
    }

    /// 2026-10-30 新增（第 94 轮）：**删除/停用凭证时取消已排程的到期提醒**。
    ///
    /// 在此之前 `removePendingNotificationRequests` 只在 `scheduleAlertsOrdered` 里被调 ——
    /// 也就是只有「改提醒开关」会取消，**删凭证不会**。于是：
    ///   建一条 10 月 25 日到期的密码并开「7 天提醒」→ 10 月 20 日把它删了
    ///   → 10 月 18 日那条提醒**照旧弹出**，说「密码临期」—— 而那条密码早已不存在。
    /// 用户会以为删除没生效，或者被一条指向空气的提醒反复打扰。
    static func cancelAlerts(mac: String, alias: Int) {
        let id = "c6.alert.\(mac).p\(alias)"
        // SEC-32：取消与排期必须走**同一条串行链**。旧实现两者各起一条
        // getPendingNotificationRequests 异步序列：删除凭证时「取消」还在飞，
        // 同一时刻的「排新」已经把新通知写进 pending —— 取消回调再把它一起删掉，
        // 表现为"删了凭证，但提醒还在（或反之：改期后一条都不响）"。
        enqueue { done in
            let c = UNUserNotificationCenter.current()
            c.getPendingNotificationRequests { reqs in
                let stale = reqs.map(\.identifier).filter { $0 == id || $0.hasPrefix(id + ".") }
                if !stale.isEmpty { c.removePendingNotificationRequests(withIdentifiers: stale) }
                done()
            }
        }
    }

    /// 有效期变了 ⇒ 旧的到期提醒必须按新日期重排。
    ///
    /// 2026-11-01（Round 226）：`setPwdPeriod`（手动改期与批量延期都走它）此前**只改台账、从不重排提醒** ——
    /// 于是把「11-10 到期」延到「次年 1-1」，通知仍会在 11-03 弹「即将到期」，用户以为密码快过期了。
    /// 与上面 `cancelAlerts` 的注释是同一族：**改/删都要让通知跟着走**。
    static func rescheduleAlerts(mac: String, alias: Int) {
        guard let p = DB.listPwds(mac).first(where: { $0.alias == alias }) else { return }
        cancelAlerts(mac: mac, alias: alias)
        let a = alertTable(mac)["pwd:" + String(alias)] ?? CredAlert()
        scheduleAlerts(mac, p, a)
    }

    // MARK: - SEC-32 通知排期的唯一串行链

    /// 「删旧 / 排新 / 取消」三类动作全部排进同一条队列，逐个完成后再取下一个。
    /// 旧实现让 cancelAlerts 与 scheduleAlertsOrdered 各自起异步序列，两条序列互相
    /// 看不到对方的中间态 —— 删凭证与改期同时发生时，先删后加的顺序不成立。
    // 队列元素类型：**`@escaping` 保持原样**（`86f4617` 就有、CI 已验证可编译），只补 `@Sendable`。
    //
    // 我一度写注释说"这里不能写 `@escaping`" —— 那是错的：它标的是"该闭包参数在函数体内会逃逸"，
    // 而这里正是函数类型的参数位。删掉它会得到
    // `escaping closure captures non-escaping parameter 'done'`（6 处）—— 反证它必须保留。
    private static let notifyQueue = Locked<[(@escaping @Sendable () -> Void) -> Void]>([])
    private static let notifyBusy = Locked(false)

    /// 入队一个"完成时调 done()"的异步动作；队列空闲则立刻开跑。
    ///
    /// **两个 `@Sendable` 都是必要的**（2026-11-01，两轮才补齐）：
    ///   · 内层 `done` —— 它被 `UNUserNotificationCenter` 的 `@Sendable` 闭包捕获；
    ///   · 外层 `job` —— 它被存进 `notifyQueue` 并在 `Task { @MainActor in … }` 里被调用。
    /// 只标内层会得到一条新告警 `passing non-Sendable parameter 'job'`（我上一轮就只标了内层，
    /// CI 从 6 条降到 1 条而不是 0 条，正是这条）。
    ///
    /// `@escaping` 的位置**保持原始写法**（内外两层都标）—— 这是 `86f4617` 就有、且 CI 验证过可编译的形状。
    /// 我一度以为"内层 `@escaping` 非法"并删掉它，结果得到
    /// `converting non-escaping parameter 'job' to generic parameter 'Element' may allow it to escape`
    /// —— 恰恰是因为删掉之后 `job` 不再被当成逃逸。
    static func enqueue(_ job: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) {
        let start: Bool = notifyQueue.withLock { q in
            q.append(job)
            return !notifyBusy.withLock { b in
                if b { return false }
                b = true
                return true
            }
        }
        if start { runNextNotify() }
    }

    /// 取队首执行；队列空则释放忙标志。**任何路径都必须调 advance()**，否则整条链会卡死。
    private static func runNextNotify() {
        let job: ((@escaping @Sendable () -> Void) -> Void)? = notifyQueue.withLock { q in
            q.isEmpty ? nil : q.removeFirst()
        }
        guard let job else {
            notifyBusy.withLock { $0 = false }
            return
        }
        job { advance() }
    }

    /// 一个动作完成：继续下一个（或释放忙标志）。
    private static func advance() {
        Task { @MainActor in runNextNotify() }
    }

    /// 本 App 自己排的通知标识前缀（`c6.` 全族）。集中一处，避免各处各写一遍。
    ///
    /// 族内有两个生产者，**两者文案都带真实名称**，所以空壳模式必须整族清掉：
    ///   · `c6.alert.<mac>.p<alias>.<档位>` / `c6.monthly`（凭证到期提醒，带凭证名）
    ///   · `c6.batt.<mac>.l<level>`（低电提醒，正文是「<锁名>」只剩 N%）
    static func isOwnNotification(_ id: String) -> Bool { id.hasPrefix("c6.") }

    /// 进入空壳模式时**抹掉通知面**（2026-11-01）。
    ///
    /// 为什么必须做：空壳模式（胁迫码进入）只清数据层投影（SEC-03），
    /// 但**已排的到期提醒会带着真实凭证名弹出** ——
    /// 「密码临期 · 前门密码」这种文案，等于当着胁迫者的面把"这人有哪些密码"念出来。
    /// 已送达的同样带着名字，所以 pending 与 delivered 都要清。
    /// 走同一条串行队列，避免与正在进行的排程/取消交错。
    /// 幂等守卫：`reload` 会被频繁调用，每次入队没必要。
    /// 只在"这次真的进入了空壳"时清一次；退出空壳时复位（见 AppModel 的 else 分支）。
    private static let decoyCleared = Locked(false)

    static func cancelAllForDecoy() {
        let need = decoyCleared.withLock { already -> Bool in
            if already { return false }
            already = true
            return true
        }
        guard need else { return }
        enqueue { done in
            let c = UNUserNotificationCenter.current()
            c.getPendingNotificationRequests { reqs in
                let stale = reqs.map(\.identifier).filter { isOwnNotification($0) }
                if !stale.isEmpty { c.removePendingNotificationRequests(withIdentifiers: stale) }
                // 已送达的那批同样带真实凭证名，留在通知中心一样会泄露。
                c.removeAllDeliveredNotifications()
                done()
            }
        }
    }

    /// 退出空壳后**重建全部到期提醒**（2026-11-01）。
    ///
    /// 为什么需要它：`cancelAllForDecoy()` 会清掉整族通知，
    /// 而本仓**没有**任何"全量重排"入口 —— 不清回来，用户退出空壳后会永久失去
    /// 所有凭证的到期提醒，直到他逐条重新保存提醒开关。那是一种静默的功能丢失：
    /// 界面照旧显示"已排程"，实际一条都不会响。
    ///
    /// 逐条走 `scheduleAlerts`（内部经串行队列），只排用户确实开过档位的那几条。
    static func rescheduleAllAlerts() {
        for mac in DB.keychains().map(\.mac) {
            // 2026-11-01：改用 `expiryDate`（`nil` = 永久），不再自己写 `hasPrefix("2118")`。
            // 同一判据两处各写一遍，改一处就会漂 —— `expiryDate` 是本文件里的唯一口径。
            for p in DB.listPwds(mac) where expiryDate(p) != nil {
                let a = alert(mac, p)
                let any = a.day || a.d3 || a.d1 || a.h24 || a.h2
                if any { scheduleAlerts(mac, p, a) }
            }
        }
    }

    /// 退出空壳时复位，让下一次进入能再清一次。
    static func resetDecoyNotificationGuard() { decoyCleared.withLock { $0 = false } }

    /// 删旧 → 排新，严格串行（见 scheduleAlerts 的竞态说明）。
    private static func scheduleAlertsOrdered(id: String, p: LedgerPwd, a: CredAlert, mac: String) {
        enqueue { done in
            let c = UNUserNotificationCenter.current()
            c.getPendingNotificationRequests { reqs in
                let stale = reqs.map(\.identifier).filter { $0 == id || $0.hasPrefix(id + ".") }
                // E-06：只捕获值，在主 actor 里重建动作 —— 删先于加的顺序语义不变。
                if !stale.isEmpty { c.removePendingNotificationRequests(withIdentifiers: stale) }
                Task { @MainActor in
                    // 必须 await 到六条提醒**全部**排进系统，再放行队列的下一个动作。
                    // 否则下一个动作（取消/重排）可能与这些 add 交错，竞态重现。
                    await scheduleAlertsNow(id: id, p: p, a: a, mac: mac)
                    done()
                }
            }
        }
    }

    /// 真正排六条提醒（原 scheduleAlerts 的函数体）。
    /// async：必须 await 到每条提醒**真正排进系统**才返回，
    /// 否则外层串行队列的 done() 会提前放行下一个动作（删除/取消），竞态重现。
    private static func scheduleAlertsNow(id: String, p: LedgerPwd, a: CredAlert, mac: String) async {
        // "到期时"不看单档开关: 开了任何一档 = 在意这条凭证的到期, 到点本身最该说话。
        let any = a.day || a.d3 || a.d1 || a.h24 || a.h2
        guard let to = expiryDate(p), any else { return }
        let name = displayPwd(p)
        // 天数档是**日历日** ⇒ 走 WeekCal.shifted; 小时档说的是"还有 N 小时" = 时长。
        // 两种口径在这里不是一回事 (§10.33), 混用会让 -1 天那条在夏令时切换日多/少一小时。
        // 逐条 await：每条**落地**后才排下一条，且整组完成后调用方才会 done()。
        func dayTier(_ on: Bool, _ k: Int, _ suf: String, _ tail: String) async {
            guard on else { return }
            await addCalendar(id: id + suf, date: WeekCal.shifted(to, days: -k),
                              title: "密码临期", body: "\(name) 距到期还有 \(k) 天。" + tail)
        }
        await dayTier(a.day, 7, ".d7", "记得续期或停用。")
        await dayTier(a.d3, 3, ".d3", "")
        await dayTier(a.d1, 1, ".d1", "明天就失效了。")
        if a.h24 {
            await addCalendar(id: id + ".h24", date: to.addingTimeInterval(-86400),
                              title: "密码临期", body: "\(name) 距到期不足 24 小时。")
        }
        if a.h2 {
            await addCalendar(id: id + ".h2", date: to.addingTimeInterval(-7200),
                              title: "密码临期", body: "\(name) 距到期还有 2 小时。")
        }
        await addCalendar(id: id + ".t0", date: to, title: "已到期",
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

    // 【保留未接 2026-11-01】停用原因**读取与回显**（361）—— 接线点：凭证详情页的停用行。
    // 与 `CredentialOrg.markDisabled`（写侧）成对；两边都没接，所以整条链目前是死的。
    static func disableMark(_ mac: String, kind: String, key: Int) -> DisableMark? {
        (DB.store.get([String: DisableMark].self, disReasonKey(mac)) ?? [:])["\(kind):\(key)"]
    }

    /// 361 回显文案: 停用原因 + 时刻 + 来源路径; 没有标记 (非本 App 停用) 就不编造
    // 【保留未接 2026-10-29】停用原因回显（用户 B1 未选，保留待接：凭证详情页的停用行）
    static func disableMarkText(_ mac: String, kind: String, key: Int) -> String? {
        guard let d = disableMark(mac, kind: kind, key: key) else { return nil }
        let f = DF.shortDayTime
        return "停用原因 \(d.label) · \(f.string(from: Date(timeIntervalSince1970: d.at))) · \(d.via)"   // 361 停用原因
    }

    // 363「月历到期」`monthDeadlines(_:year:month:)` + `dayDeadlines(_:_:)`：**已删除**（2026-11-01）。
    //
    // 它们零调用，而**功能已经存在** —— 由 `KeyCalendarScreen` 自己算：
    //   · `deadlines`（按 dayKey 分桶）→ 每格到期条数；
    //   · `pickedItems` → 当天清单；
    //   · `monthTotal` → 页头「本月 N 条到期」。
    //
    // 而且界面那版**覆盖面更广**：它用 `app.keys`（含指纹与手机钥匙），
    // 而这里只遍历 `DB.listPwds`（仅密码/临时码）。
    //
    // 所以这不是"保留未接"，是**数据源更窄的旧实现**（同 `typeCounts` / `MemberHub.display` 一族）。
    // 留此说明是为了不让人去 Engine 里找月历逻辑（它在 KeyCalendarScreen）。

    /// 弱口令三条判据 (都可证伪; 不评"强度分"): 少于 6 位 / 全部同一位 / 连续递增递减
    /// 接线点：`KeyCreateParts.duplicateNote`（新密码输入时的即时提示）。**已接线** ——
    /// 原标记「保留未接 2026-10-29」已过期并删掉（它导致我把这个函数误判成未接，见 AUDIT-ROUND-97）。
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
        // 2026-11-01（Round 237）：**`owner` 这个字段历史上存过两种东西** ——
        // 成员 id（成员管理指派 / 合并 / 恢复走这条）与成员**名字**（凭证工作室创建时 `owner = member.name`）。
        // 而 `DB.member(_:)` 只按 id 查 ⇒ 名字那批永远解析不出人，界面显示「未归属」。
        // 读侧先按 id、再按名字回退；写侧已在 `AppModel.addPassword` 统一成 id（见那里的注释）。
        guard let id, !id.isEmpty else { return "" }
        let m = DB.member(id) ?? DB.members().first(where: { $0.name == id })
        guard let m else { return "" }
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
