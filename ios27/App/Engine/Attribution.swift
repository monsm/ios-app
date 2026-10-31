// 归属推断 (JS services/attribution.js 移植) — 「谁开的门」只在可证明时给出, 绝不猜测:
//   R1 一次性密码窗口: 事件时刻落在某条给成员发的临时码 [from,to] 内且唯一命中 → 归属
//   R2 锁内唯一凭证 + 实时背书: 本次会话实时 03 显示该型凭证只剩 1 个且事件够新 (≤3 天)
// 差分基准: golden.attribution*
import Foundation

enum Attribution {
    struct Row {
        var key: UInt32
        var type: Int
        var kind: String?   // fp/pwd/temp/key
        var who: String?    // 成员 id
        var provable: String? // temp/unique
    }
    static let words: [String: String] = ["fp": "指纹", "pwd": "密码", "temp": "一次性密码", "key": "数字钥匙"]
    // 开门型事件 → 凭证种类 (App 日志枚举 1/2/3/4/5)
    // 2026-10-29 修正：日志类型按 APK `We` 表 —— 11 数字钥匙 / 16 一次性密码 / 17 密码 / 19 指纹。
    static let openKind: [Int: String] = [11: "key", 16: "temp", 17: "pwd", 19: "fp"]
    static let uniqueMaxAgeSec: Int64 = 3 * 86400

    static func ms(_ s: String) -> Int64? {
        // 2026-10-29 性能：原每次调用新建 2 个 DateFormatter，而本函数在 classify 里是
        // 「日志 × 临时码」量级的调用（100x20 = 2000 次 ⇒ 4000 个 formatter，秒级卡顿）。
        // 现在两个都走进程级缓存。
        //
        // JS attribution.js msOf 给时间串追加 'Z' 按 UTC 解析 — 本地串当 UTC 读。
        // 看似"错"但这是 JS 生态的既定语义: 写入端(App/小程序)都写本地串、读取端都按 UTC,
        // 两端同平移故窗口长度与相对判定不变; 跨设备互操作也只有与 JS 同语义才互通。
        var d = DF.stampUTC.date(from: s)
        if d == nil {
            // 兼容只写到分钟的 from/to (小程序与旧备份包里的 "2026-01-05 08:00"):
            // JS 侧走宽松 Date.parse 能解, 旧写法返回 nil → R1 临时码窗口静默不归属。
            d = DF.minuteUTC.date(from: s)
        }
        guard let dd = d else { return nil }
        return Int64(dd.timeIntervalSince1970 * 1000)
    }

    static func classify(logs: [LogEntry],
                         pwds: [LedgerPwd],
                         fps: [LedgerFp],
                         status: (fpStock: Int, pwdStock: Int, lockTime: Int64)?) -> [Row] {
        // JS 用 truthy 判 owner (attribution.js:31-33) — 空串同样视为未归属
        let temps = pwds.filter { $0.temp && !( $0.owner ?? "").isEmpty }
        let permOwned = pwds.filter { !$0.temp && !($0.owner ?? "").isEmpty }
        let fpOwned = fps.filter { !($0.owner ?? "").isEmpty }
        // 2026-10-29 性能：临时码时间窗**先算一次**。
        // 原写法把 ms(p.from)/ms(p.to) 放在 logs.map 里 —— 等于对每条日志重解析每个临时码的两条边，
        // 100 条日志 × 20 条临时码 = 2000 次字符串解析（每次都还要建 DateFormatter）。
        // 现在 O(临时码) 一次，循环里只剩整数比较。
        let tempWindows: [(owner: String, from: Int64, to: Int64)] = temps.compactMap { p in
            guard let f = ms(p.from), let t = ms(p.to), let o = p.owner, !o.isEmpty else { return nil }
            return (o, f, t)
        }
        return logs.map { e in
            var row = Row(key: e.idxRaw, type: e.type, kind: openKind[e.type], who: nil, provable: nil)
            guard let kind = row.kind else { return row }
            // R1 临时码窗口 (含密码开门 — 由临时码完成)
            if kind == "temp" || kind == "pwd" {
                let t = ZKProtocol.protoSecondsToMs(e.lockTime)
                let hits = tempWindows.filter { $0.from <= t && t <= $0.to }
                if hits.count == 1 {
                    row.who = hits[0].owner
                    row.provable = "temp"
                }
            }
            // R2 锁内唯一凭证 (需实时背书 + 事件新鲜)
            if row.who == nil, let st = status {
                let age = st.lockTime - e.lockTime
                if age >= 0 && age <= uniqueMaxAgeSec {
                    if kind == "fp" && st.fpStock == 1 && fpOwned.count == 1 {
                        row.who = fpOwned[0].owner
                        row.provable = "unique"
                    } else if kind == "pwd" && st.pwdStock == 1 && permOwned.count == 1 {
                        row.who = permOwned[0].owner
                        row.provable = "unique"
                    }
                }
            }
            return row
        }
    }
}