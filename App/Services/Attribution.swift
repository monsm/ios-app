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
    static let openKind: [Int: String] = [1: "key", 2: "pwd", 3: "fp", 4: "temp"]
    static let uniqueMaxAgeSec: Int64 = 3 * 86400

    static func ms(_ s: String) -> Int64? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        // JS attribution.js msOf 给时间串追加 'Z' 按 UTC 解析 — 本地串当 UTC 读。
        // 看似"错"但这是 JS 生态的既定语义: 写入端(App/小程序)都写本地串、读取端都按 UTC,
        // 两端同平移故窗口长度与相对判定不变; 跨设备互操作也只有与 JS 同语义才互通。
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: s) else { return nil }
        return Int64(d.timeIntervalSince1970 * 1000)
    }

    static func classify(logs: [LogEntry],
                         pwds: [LedgerPwd],
                         fps: [LedgerFp],
                         status: (fpStock: Int, pwdStock: Int, lockTime: Int64)?) -> [Row] {
        // JS 用 truthy 判 owner (attribution.js:31-33) — 空串同样视为未归属
        let temps = pwds.filter { $0.temp && !( $0.owner ?? "").isEmpty }
        let permOwned = pwds.filter { !$0.temp && !($0.owner ?? "").isEmpty }
        let fpOwned = fps.filter { !($0.owner ?? "").isEmpty }
        return logs.map { e in
            var row = Row(key: e.idxRaw, type: e.type, kind: openKind[e.type], who: nil, provable: nil)
            guard let kind = row.kind else { return row }
            // R1 临时码窗口 (含密码开门 — 由临时码完成)
            if kind == "temp" || kind == "pwd" {
                let t = ZKProtocol.protoSecondsToMs(e.lockTime)
                let hits = temps.compactMap { p -> LedgerPwd? in
                    guard let f = ms(p.from), let to = ms(p.to), f <= t, t <= to else { return nil }
                    return p
                }
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