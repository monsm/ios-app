// RecordSearch · 查询与筛选（按日/按成员/按凭证/越界窗口）
// 2026-10-29 从 RecordSearch.swift 拆出。
import Foundation

extension RecordSearch {
    static func outOfWindow(macs: [String]) -> [OutWin] {
        var out = [OutWin]()
        for mac in macs {
            let pws = DB.listPwds(mac).filter { $0.temp }
            guard !pws.isEmpty else { continue }
            for r in buildRecs(macs: [mac], includeFails: false, includeCare: false) where r.type == 4 {
                guard let d = dateOf(r) else { continue }
                let t = d.timeIntervalSince1970
                for p in pws {
                    let f = parseStamp(p.from), to = parseStamp(p.to)
                    guard f > 0, to > 0 else { continue }
                    let ts = Int(t)
                    if ts > to || ts < f {
                        out.append(OutWin(rec: r, window: "约 " + String(p.from.dropFirst(5).prefix(11)) + " – " + String(p.to.dropFirst(5).prefix(11))))
                        break
                    }
                }
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
