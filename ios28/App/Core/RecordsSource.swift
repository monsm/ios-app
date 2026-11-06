// RecordsSource.swift —— 把锁端日志缓存投影成时间线行。
//
// 唯一口径：归属、凭证标签、告警色都在这里算一次。页面不许再解 CachedLog。
import Foundation

enum RecordsSource {
    /// - Parameter memberNames: 成员 id → 名字。直接给字典而不是 `[MemberCard]`：
    ///   记录投影不再依赖成员卡片投影（成员卡片反过来又要靠记录算活跃度，
    ///   互相依赖会绕成一个环 —— 环上一侧的刷新顺序一变，另一侧就读到旧值）。
    static func load(mac: String, lockName: String, memberNames: [String: String]) -> [EventItem] {
        let logs = DB.readLogs(mac)
        guard !logs.isEmpty else { return [] }

        let ledger = DB.ledger(mac)
        let entries = logs.map { c in
            LogEntry(type: c.type,
                     typeName: c.displayTypeName,
                     idx: c.idxRaw,
                     idxRaw: c.idxRaw,
                     lockTime: c.lockTime,
                     lockTimeStr: c.lockTimeStr,
                     body: "")
        }
        let snap = DB.readStatus(mac)
        let status: (fpStock: Int, pwdStock: Int, lockTime: Int64)? = snap.map {
            ($0.fpStock, $0.pwdStock, $0.lockTime)
        }
        let rows = Attribution.classify(logs: entries, pwds: ledger.pwds, fps: ledger.fps, status: status)

        var out: [EventItem] = []
        out.reserveCapacity(logs.count)
        for (i, c) in logs.enumerated() {
            let row = i < rows.count ? rows[i] : nil
            let key = String(c.idxRaw)
            let whoID = row?.who
            let alarm = c.type == 4 || c.type == 10
            // 锁端时钟读不到时 lockTime 是 0 —— 那条记录**没有日期**。
            // 原先照样换算，于是时间线顶上冒出一组「2010 年 1 月 1 日」
            // （本地 2010 纪元的零点），详情页也显示 2010 年。
            // 这里如实标成 time = 0，由页面按「无日期」显示。
            let time = c.lockTime == 0 ? 0 : Int64(ZKProtocol.protoSecondsToUnix(c.lockTime))
            out.append(EventItem(
                id: mac + "#" + key,
                mac: mac,
                lockName: lockName,
                type: c.type,
                typeName: c.displayTypeName,
                idx: c.idxRaw,
                time: time,
                whoID: whoID,
                whoName: whoID.flatMap { memberNames[$0] },
                provable: row?.provable,
                credential: row?.kind.flatMap { Attribution.words[$0] } ?? "",
                credKind: row?.kind,
                alarm: alarm,
                diff: c.diff,
                note: RecordOverlay.note(mac, key),
                flagged: RecordOverlay.isFlagged(mac, key)
            ))
        }
        // 有日期的按时间倒序在前；**没有日期的排在最后** —— 它们不知道自己在什么时候，
        // 混进时间线里只会假装自己发生在那一天。
        out.sort { a, b in
            switch (a.hasTime, b.hasTime) {
            case (true, true): return a.time > b.time
            case (true, false): return true
            case (false, true): return false
            case (false, false): return a.idx > b.idx
            }
        }
        return out
    }

    static func markSynced(mac: String, at: Int64) {
        DB.store.set("kf_logsync_" + DB.normalizeMac(mac), String(at))
    }

    static func lastSync(mac: String) -> Int64? {
        // 空壳里「上次读取」本身也是使用痕迹：它精确到分钟地说明主人什么时候翻过记录。
        // 与 readLogs 同口径，返回 nil（界面会说「还没读过锁」）。
        if DB.isDecoy { return nil }
        return Int64(DB.store.getString("kf_logsync_" + DB.normalizeMac(mac)))
    }
}
