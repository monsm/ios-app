// RecordSearch · 查询与筛选（按日/按成员/按凭证/越界窗口）
// 2026-10-29 从 RecordSearch.swift 拆出。
import Foundation

extension RecordSearch {
    static func outOfWindow(macs: [String]) -> [OutWin] {
        var out = [OutWin]()
        // 2026-10-30 性能：临时码窗口先统一解析成秒对（标签也一并拼好）——
        // 原来在内层对每条开门日志各解析两遍：日志 × 凭证 × 2 次字符串解析，
        // 一次 DateFormatter 解析就是一次 ICU 装配，300 条日志 × 20 张临时码 = 1.2 万次。
        // 现在每张临时码只解析一次；日志循环里只剩整数比较。
        //
        // 2026-11-01：这里用的必须是 `parseLocal`（本地墙钟），**不是** UTC 口径 ——
        // 见下面 for 循环里的时基说明。原注释写的 `parseStamp` 已随该修复一起作废。
        struct TempWin { let from: Int64; let to: Int64; let label: String }
        var perMac: [String: [TempWin]] = [:]
        for mac in macs {
            let pws = DB.listPwds(mac).filter { $0.temp }
            guard !pws.isEmpty else { continue }
            var wins = [TempWin]()
            for p in pws {
                // 时基必须与日志侧一致（见下方 2026-11-01 修复说明）。
                // 临时码的 from/to 是**本地墙钟串**（`DF.cached(...)` 默认 TimeZone.current 写出），
                // 所以这里也要按本地解析 —— 不能用 parseStamp（它按 UTC 解析）。
                let f = parseLocal(p.from), to = parseLocal(p.to)   // 失败给 0，下面 f>0 判据兜住
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
        // 2026-10-30 修复（第 90 轮）：这里原来写的是 **[3: "fp", 2: "pwd", 4: "temp", 1: "key"]** ——
        // 那是**旧/错**的类型表。本仓权威映射在 `Attribution.openKind`：
        //   [11: "key", 16: "temp", 17: "pwd", 19: "fp"]（与 `StatsKit.openTypes = [11,16,17,19]` 一致）
        // 同文件的 `outOfWindow` 早有一条注释点明「临时码开门是 16，旧值 4 是消息中心枚举」。
        // 用旧表的后果：真实开门（11/16/17/19）**一条都不计**，这个「活跃凭证」页永远是空的；
        // 而万一日志里出现 1/2/3/4 这些消息中心类型，又会被**错误归成** key/pwd/fp/temp。
        // 现在直接用权威表，不再另抄一份。
        //
        // 2026-11-03（全功能点排查 · 语义）：**这里原来按 `kind#idxRaw` 分组** ——
        // 而 `idxRaw` 是**日志行号**，不是凭证编号。后果有两层：
        //   ① 每条日志自成一组 ⇒ 列表永远是"指纹 #42 … 1 次 / 密码 #41 … 1 次"，
        //      所有计数都是 1，"活跃"两个字没有任何意义；
        //   ② 下面还拿这个行号去 `lg.fps.first { String($0.batch) == slot }` 查备注 ——
        //      行号与指纹批号是两套编号，几乎必然查不到；偶尔撞上就是**张冠李戴**。
        // 锁端日志（type 11/16/17/19）**不携带凭证槽位**，所以"哪一把凭证"这个问题
        // 在数据上不可回答。诚实做法：只按**凭证种类**聚合，标题也跟着改成"开门构成"。
        let typeToKind: [Int: String] = Attribution.openKind
        for l in logs { if let k = typeToKind[l.type] { c[k, default: 0] += 1 } }
        return c.sorted { $0.value > $1.value }.map { kind, n in
            (kind, Attribution.words[kind] ?? kind, n)
        }
    }

}
