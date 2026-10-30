// RecordSearch · 查询与筛选（按日/按成员/按凭证/越界窗口）
// 2026-10-29 从 RecordSearch.swift 拆出。
import Foundation

extension RecordSearch {
    static func outOfWindow(macs: [String]) -> [OutWin] {
        var out = [OutWin]()
        // 2026-10-30 性能：临时码窗口先统一解析成秒对（标签也一并拼好）——
        // 原来在内层对每条开门日志各 parseStamp 两遍：日志 × 凭证 × 2 次字符串解析，
        // parseStamp 是一次 DateFormatter 解析，300 条日志 × 20 张临时码 = 1.2 万次。
        // 现在每张临时码只解析一次；日志循环里只剩整数比较。
        // parseStamp 返回 Int64（DateFormatter 解析出的秒），窗口对齐用它
        struct TempWin { let from: Int64; let to: Int64; let label: String }
        var perMac: [String: [TempWin]] = [:]
        for mac in macs {
            let pws = DB.listPwds(mac).filter { $0.temp }
            guard !pws.isEmpty else { continue }
            var wins = [TempWin]()
            for p in pws {
                let f = parseStamp(p.from), to = parseStamp(p.to)   // parseStamp 失败给 0，下面 f>0 判据兜住
                guard f > 0, to > 0 else { continue }
                let label = "约 " + String(p.from.dropFirst(5).prefix(11)) + " – " + String(p.to.dropFirst(5).prefix(11))
                wins.append(TempWin(from: f, to: to, label: label))
            }
            perMac[mac] = wins
        }
        // 2026-10-29 修正：临时码开门在 APK We 表里是 16（旧值 4 是消息中心枚举）。
        for r in buildRecs(macs: macs) where r.type == 16 {
            guard let d = dateOf(r), let temps = perMac[r.mac], !temps.isEmpty else { continue }
            let ts = Int64(d.timeIntervalSince1970)
            // 这条开门落在**任一**临时码窗口内 = 正常；全都不在窗内才报越界（取第一条窗口做展示）
            if !temps.contains(where: { ts >= $0.from && ts <= $0.to }) {
                out.append(OutWin(rec: r, window: temps[0].label))
            }
        }
        return out.sorted { $0.rec.timeStr > $1.rec.timeStr }
    }

    /// 574 活跃凭证 (台账推断, 展示层必须标"约"): 近 30 天开门日志按「类型 #槽位」计次,
    /// 槽位翻台账出备注 (指纹查批次 / 密码·临时查别名), 翻不到回落"类型 #槽号" ——
    /// 旧版只汇总到四类大字, 用户看到"指纹 5 次"不知道是哪一个。
    static func activeCredentials(mac: String) -> [(kind: String, word: String, count: Int)] {
        let now = Date().timeIntervalSince1970
        let logs = DB.readLogs(mac).filter { l in
            guard let d = StatsKit.dateOf(l) else { return false }
            return d.timeIntervalSince1970 >= now - 30 * 86400
        }
        var c: [String: Int] = [:]
        let typeToKind: [Int: String] = [3: "fp", 2: "pwd", 4: "temp", 1: "key"]
        for l in logs { if let k = typeToKind[l.type] { c[k + "#" + String(l.idxRaw), default: 0] += 1 } }
        let lg = DB.ledger(mac)
        return c.sorted { $0.value > $1.value }.map { key, n in
            let parts = key.split(separator: "#", maxSplits: 1).map(String.init)
            let kind = parts.first ?? "", slot = parts.count > 1 ? parts[1] : ""
            let base = Attribution.words[kind] ?? kind
            let note = kind == "fp"
                ? lg.fps.first { String($0.batch) == slot }?.note
                : lg.pwds.first { String($0.alias) == slot }?.note
            let seg = (note ?? "").split(separator: "\n").first.map(String.init) ?? ""
            let short = seg.count > 12 ? String(seg.prefix(12)) + "…" : seg
            return (kind, short.isEmpty ? base + " #" + slot : base + " #" + slot + " · " + short, n)
        }
    }

}
