// RecordSearch · 记录构建与解析（buildRecs / 日期 / 时段 / 节假日 / 缺口）
// 2026-10-29 从 RecordSearch.swift 拆出。
import Foundation

extension RecordSearch {
    // ---------- 数据源: 聚合多锁 + 手机侧事件 (561/770 跨锁范围切换) ----------
    static func buildRecs(macs: [String], includeFails: Bool = true, includeCare: Bool = true) -> [Rec] {
        var out = [Rec]()
        let members = DB.members()
        // 2026-10-30 性能：`memberName` 原来对每次调用都 `members.first(where:)` 线性查找 ——
        // 而它在 applyFilter 热路径上（搜索/切锁/刷新都会全量重跑），单锁几百条日志就是几百次线性扫。
        // 一次建表。
        let memberNames = Dictionary(members.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func memberName(_ id: String?) -> String? {
            guard let id, !id.isEmpty else { return nil }
            return memberNames[id]
        }
        for mac in macs {
            let kc = DB.keychain(mac)
            let lockName = LockArchive.displayName(kc ?? Keychain(mac: mac, skey: ""))
            let logs = DB.readLogs(mac)
            let pws = DB.listPwds(mac)
            let fps = DB.listFps(mac)
            let snap = DB.readStatus(mac)
            let entries = logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") }
            let cls = Attribution.classify(logs: entries, pwds: pws, fps: fps, status: snap.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })  // StatusSnapshotData.lockTime 非可选
            for (i, e) in entries.enumerated() {
                guard i < cls.count else { continue }
                let c = cls[i]
                let who = memberName(c.who)
                let cred = credLabel(kind: c.kind, who: who, pws: pws, fps: fps, e: e)
                out.append(Rec(key: String(e.idxRaw), mac: mac, lockName: lockName, type: e.type,
                               typeName: e.typeName, idxRaw: e.idxRaw, lockTime: e.lockTime,
                               timeStr: e.lockTimeStr, whoId: c.who, whoName: who, kind: c.kind,
                               provable: c.provable, cred: cred,
                               alarm: StatsKit.alarmTypes.contains(e.type), care: false, failMsg: ""))
            }
        }
        out.sort { $0.timeStr > $1.timeStr }   // 字符串序 = 时间倒序 (同格式)
        return out
    }

    static func localStr(_ ts: Double) -> String {
        // 2026-10-29 性能：复用进程级 formatter（原每次新建，且本函数按记录调用）。
        DF.stamp.string(from: Date(timeIntervalSince1970: ts))
    }

    static func dateOf(_ l: CachedLog) -> Date? { StatsKit.dateOf(l) }

    /// 日 key 口径与 `StatsKit.dayKey` 合并为一份 (§10.30)：此前两处各抄一遍同样的
    /// yyyy-MM-dd + POSIX + 当前时区，值恰好相同，但改一处就会让检索分组与统计柱对不齐。
    static func dayKeyOf(_ d: Date) -> String { StatsKit.dayKey(d) }

    /// "yyyy-MM-dd" → 该日 0 点 (本地时区)
    static func dateFromKey(_ key: String) -> Date? {
        // 2026-10-29 性能：fillGaps 会对每一对相邻日各调两次，原来就是 2xN 个 formatter。
        DF.day.date(from: key)
    }

    /// 649 凌晨归属前一晚: 0:00-4:59 归前一天
    static func dayKeyOfNight(_ d: Date) -> String {
        let c = WeekCal.gregorian
        if c.component(.hour, from: d) < 5 {
            return dayKeyOf(c.date(byAdding: .day, value: -1, to: d) ?? d)
        }
        return dayKeyOf(d)
    }

    /// 564/572 深夜判定。**672 假日顺延接在这里**: 节假日当日把区间终点 +2 小时。
    /// 此前 extendedEndHour/holidayExtendOn 组成一条没人走的链 = 设置形同虚设。
    /// dayKey 传 "" (或不传) = 不做假日判定, 与旧行为一致。
    static func isLateNight(_ hour: Int, dayKey: String = "") -> Bool {
        let a = nightFrom
        let b = extendedEndHour(dayKey) ?? nightTo
        return a > b ? (hour >= a || hour < b) : (hour >= a && hour < b)
    }

    /// 671 节假日名 (组头标签); 补班日不在此列
    static func holidayName(_ dayKey: String) -> String? { ensureMerged(); return mergedLock.withLock { $0.map[dayKey] } }

    // 【保留未接 2026-10-29】同类型记录计数（「这是本周第 3 次撬锁」）—— 记录详情可挂
    static func sameTypeCount(mac: String, type: Int, exceptKey: String) -> SameCount {
        let hits = DB.readLogs(mac).filter { $0.type == type && String($0.idxRaw) != exceptKey }
        let last = hits.first?.lockTimeStr ?? ""
        return SameCount(total: hits.count + 1, lastStr: last)
    }

    /// 736 前后事件上下文: 告警前后 10 分钟同锁记录 (前 3 条 / 后 3 条)
    // 【保留未接 2026-10-29】告警前后 10 分钟同锁记录（前3/后3）—— 记录详情「前后事件」区
    static func context(mac: String, aroundKey: String, minutes: Int = 10, n: Int = 3) -> (before: [Rec], after: [Rec]) {
        let recs = buildRecs(macs: [mac], includeFails: false, includeCare: false)
        guard let mid = recs.first(where: { $0.key == aroundKey }), let md = dateOf(mid) else { return ([], []) }
        let win = Double(minutes) * 60
        let t0 = md.timeIntervalSince1970
        // 2026-10-14: 取错极值。recs 是**倒序** (新在前) ——
        //   前事件 [t0-win, t0) 里"紧邻"的在前 ⇒ 应取 prefix (旧写法 suffix 取到窗内最旧 3 条);
        //   后事件 (t0, t0+win] 里"最早"的在尾 ⇒ 应取 suffix (旧写法 prefix 取到最新 3 条)。
        // 两支都反转为时间正序返回, 调用方用 `.before.last` 当"紧邻上一条"才成立。
        let before = recs.filter { r in
            guard let d = dateOf(r) else { return false }
            return r.id != mid.id && d.timeIntervalSince1970 >= t0 - win && d.timeIntervalSince1970 < t0
        }.prefix(n)
        let after = recs.filter { r in
            guard let d = dateOf(r) else { return false }
            return r.id != mid.id && d.timeIntervalSince1970 > t0 && d.timeIntervalSince1970 <= t0 + win
        }.suffix(n)
        return (Array(before).reversed(), Array(after).reversed())
    }

    /// 596 替代: 该日发生过「多次密码开门失败锁定」(10) 的日键集合。
/// 2026-10-27 审核修复 (AUDIT-B 2.8 #6)：原注释说「与 `unhandledAlarmDays` 同一份 IO 形状」，
/// 而 `unhandledAlarmDays` 已删（全仓 0 命中）。现在它就是**唯一**这一类扫描：
/// 各锁缓存日志 → 按日归集 → 不看处置。
    /// "这一天出过事"与"还没人看过"是两件事, 处置过的也照留; 日的归属沿用 649 (dayKeyOfNight)。
    static func damageDays(macs: [String]) -> Set<String> {
        var days = Set<String>()
        for mac in macs {
            for l in DB.readLogs(mac) where AlarmMeta.damageTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                days.insert(dayKeyOfNight(d))
            }
        }
        return days
    }

}
