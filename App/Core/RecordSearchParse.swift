// RecordSearch · 搜索解析（查询串解析 / 时段短语 / 区间标签）
// 2026-10-29 从 RecordSearch.swift（625 行）拆出。
import Foundation

extension RecordSearch {
    static func parse(_ raw: String) -> Query {
        var q = Query(must: [], not: [], member: nil, range: nil, alarmOnly: false, credKind: nil, parsedTags: [])
        // 555 加减号: 空格切词, 识别 +/- 前缀 (其余为裸词)
        for tok in raw.components(separatedBy: " ") where !tok.isEmpty {
            if let f = tok.first, f == "-" {
                if tok.count > 1 {
                    q.not.append(String(tok.dropFirst()))
                    q.parsedTags.append(String(tok))
                }
            } else if let f = tok.first, f == "+" {
                if tok.count > 1 {
                    q.must.append(String(tok.dropFirst()))
                    q.parsedTags.append(String(tok))
                }
            } else {
                q.must.append(tok)
                q.parsedTags.append(tok)
            }
        }
        let tokens = q.must
        let joined = tokens.joined(separator: " ")
        // 554 时间短语; 558 配套修: 命中的时间词从 must 摘除, 否则去掉时间窗后它仍被当字面词对搜索面, 必然 0 条
        var timeHit: [String] = []
        for (phrase, range) in timePhrases(joined: joined) {
            timeHit.append(phrase)
            q.range = range
            q.parsedTags.append(rangeLabel(range))
        }
        q.must.removeAll { t in timeHit.contains { $0.contains(t) } }
        // 告警关键词
        if tokens.contains(where: { $0.contains("告警") || $0.contains("异常") }) {
            q.alarmOnly = true
        }
        // 凭证类词 (551 按类型词检索)
        for (word, kind) in [("指纹", "fp"), ("密码", "pwd"), ("临时码", "temp"), ("一次性密码", "temp"), ("钥匙", "key"), ("NFC", "key"), ("nfc", "key")] {
            if tokens.contains(where: { $0.localizedCaseInsensitiveContains(word) }) {
                q.credKind = kind
                break
            }
        }
        // 569 失败事件词
        if tokens.contains(where: { $0.contains("失败") || $0.contains("未成功") }) {
            q.credKind = nil
            q.parsedTags.append("失败（仅告警级）")
        }
        q.must.removeAll { $0.hasPrefix("告警") || $0.hasPrefix("失败") || $0.hasPrefix("异常") }
        // 551 成员名匹配
        let names = DB.members().map { $0.name }
        for t in tokens {
            if let hit = names.first(where: { $0.contains(t) && t.count >= 1 }) {
                q.member = hit
            }
        }
        // 自然语言时间短语在裸词里 (不含 +/-) 也识别一遍
        if q.range == nil, let r = timePhrases(joined: raw).first?.1 {
            q.range = r
            q.parsedTags.append(rangeLabel(r))
        }
        return q
    }

    /// 554 中文时间短语表 (今天/昨天/昨晚/本周/上周/本月/上月/最近N天/N月D日)
    static func timePhrases(joined: String) -> [(String, (from: Date, to: Date)?)] {
        let now = Date()
        let cal = WeekCal.gregorian
        func dayRange(_ d: Date) -> (Date, Date) {
            let s = cal.startOfDay(for: d)
            return (s, cal.date(byAdding: .day, value: 1, to: s)!)
        }
        var out: [(String, (from: Date, to: Date)?)] = []
        if joined.contains("昨天") { out.append(("昨天", dayRange(cal.date(byAdding: .day, value: -1, to: now)!))) }
        else if joined.contains("今天") || joined.contains("今日") { out.append(("今天", dayRange(now))) }
        if joined.contains("昨晚") {
            let y = cal.date(byAdding: .day, value: -1, to: now)!
            let s = cal.startOfDay(for: y)
            out.append(("昨晚", (s, s.addingTimeInterval(4 * 3600))))
        }
        if joined.contains("凌晨") {
            let s = cal.startOfDay(for: now)
            out.append(("凌晨", (s, s.addingTimeInterval(5 * 3600))))
        }
        if joined.contains("上周") {
            // 912: 周界走 WeekCal (只影响 firstWeekday / 最小周天数，日与月的边界不动)
            let curWeek = WeekCal.calendar.dateInterval(of: .weekOfYear, for: now)!
            out.append(("上周", (WeekCal.shifted(curWeek.start, days: -7), curWeek.start)))
        }
        if joined.contains("本周") {
            let curWeek = WeekCal.calendar.dateInterval(of: .weekOfYear, for: now)!
            out.append(("本周", (curWeek.start, now)))
        }
        if joined.contains("上月") {
            let m = cal.dateInterval(of: .month, for: cal.date(byAdding: .month, value: -1, to: now)!)!
            out.append(("上月", (m.start, m.end)))
        }
        if joined.contains("本月") {
            let m = cal.dateInterval(of: .month, for: now)!
            out.append(("本月", (m.start, now)))
        }
        if let n = intAfter(joined, "最近"), n > 0 {
            let s = WeekCal.shifted(now, days: -n)
            out.append(("最近 \(n) 天", (cal.startOfDay(for: s), now)))
        }
        // "N月D日" (只认含"月"的那个词, 避免"工作日"里的"日"误命中; 当年, 已过则去年)
        if let tok = tokensFirstContaining(joined: joined, "月"),
           let mo = intBefore(tok, "月"), mo > 0, let dy = intBetween(tok, "月", "日"), dy > 0
           // 2026-10-13 对抗式点击审计: 原写只校下界 (mo>0 / dy>0) 不校上界 ⇒ 用户在搜索框敲
           // 「13月1日」「2月30日」「4月31日」时 `Calendar.date(from:)` 返回 nil, 下一行 `!` 直接 trap。
           // 记录页搜索框是 onChange 逐字符触发的 (RecordsView 的 onRecordsAppear/onChange 里 sel = 该值),
           // 所以**不用回车, 敲到"1""3"那两个字符就崩**。先把月/日夹到合法区间, 再用 guard 兜住
           // 任何 Calendar 仍然解不出的组合 (2月30日 这种夹不动的)。
           , mo <= 12, dy <= 31,
           let d = monthDayComps(cal: cal, now: now, month: mo, day: dy) {
            var dd = d
            if dd > now {
                var cc = DateComponents(); cc.year = cal.component(.year, from: now) - 1; cc.month = mo; cc.day = dy
                guard let d2 = cal.date(from: cc) else { return out }
                dd = d2
            }
            let label = String(tok)
            out.append((label, dayRange(dd)))
        }
        return out
    }

    static func rangeLabel(_ r: (from: Date, to: Date)?) -> String {
        guard let r = r else { return "" }
        let f = DF.cached("MM-dd HH:mm")
        return f.string(from: r.from) + " – " + f.string(from: r.to)
    }

}
