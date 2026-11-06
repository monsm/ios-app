// RecordsSource.swift —— 把锁端日志缓存投影成时间线行。
//
// 唯一口径：归属、凭证标签、告警色都在这里算一次。页面不许再解 CachedLog。
import Foundation

enum RecordsSource {
    static func load(mac: String, lockName: String, members: [MemberCard]) -> [EventItem] {
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
        var names: [String: String] = [:]
        for m in members { names[m.id] = m.name }

        var out: [EventItem] = []
        out.reserveCapacity(logs.count)
        for (i, c) in logs.enumerated() {
            let row = i < rows.count ? rows[i] : nil
            let key = String(c.idxRaw)
            let whoID = row?.who
            let alarm = c.type == 4 || c.type == 10
            out.append(EventItem(
                id: mac + "#" + key,
                mac: mac,
                lockName: lockName,
                type: c.type,
                typeName: c.displayTypeName,
                idx: c.idxRaw,
                time: Int64(ZKProtocol.protoSecondsToUnix(c.lockTime)),
                whoID: whoID,
                whoName: whoID.flatMap { names[$0] },
                provable: row?.provable,
                credential: row?.kind.flatMap { Attribution.words[$0] } ?? "",
                alarm: alarm,
                diff: c.diff,
                note: RecordOverlay.note(mac, key),
                flagged: RecordOverlay.isFlagged(mac, key)
            ))
        }
        return out.sorted { $0.time > $1.time }
    }

    static func markSynced(mac: String, at: Int64) {
        DB.store.set("kf_logsync_" + DB.normalizeMac(mac), String(at))
    }

    static func lastSync(mac: String) -> Int64? {
        Int64(DB.store.getString("kf_logsync_" + DB.normalizeMac(mac)))
    }
}
