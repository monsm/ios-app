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
        // 抽取时间窗后，命中短语的每个词都要从 must 里摘掉；否则它们会被当成
        // 字面词去匹配搜索面，结果恒为 0。
        //
        // 不能直接拿带空格的短语去比 token：「最近7天」（无空格）是一个 token，
        // 而短语标签是「最近 7 天」，子串判据落空。两边都去掉空白再比，
        // 「最近」「7」「天」「最近7天」就都能被消费掉。
        let hitKeys = timeHit.map { $0.filter { !$0.isWhitespace } }
        q.must.removeAll { token in
            let key = token.filter { !$0.isWhitespace }
            return hitKeys.contains { $0.contains(key) }
        }
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
        /// Calendar 对「加减一天/一个月」这类合法运算不会失败；仍给出确定性兜底，
        /// 不让搜索框在极端日历环境（自定义 firstWeekday / 时区跳变）下因 `!` 崩溃。
        func addDays(_ d: Date, _ n: Int) -> Date {
            cal.date(byAdding: .day, value: n, to: d) ?? d.addingTimeInterval(Double(n) * 86_400)
        }
        func dayRange(_ d: Date) -> (Date, Date) {
            let s = cal.startOfDay(for: d)
            return (s, addDays(s, 1))
        }
        var out: [(String, (from: Date, to: Date)?)] = []
        if joined.contains("昨天") { out.append(("昨天", dayRange(addDays(now, -1)))) }
        else if joined.contains("今天") || joined.contains("今日") { out.append(("今天", dayRange(now))) }
        if joined.contains("昨晚") {
            // 2026-11-03（全功能点排查 · 语义）：原来返回的是「昨天 00:00–04:00」——
            // 那是**昨天凌晨**，不是「昨晚」。中文里"昨晚"指昨天傍晚到午夜这一段，
            // 而"凌晨"这个短语本来就已经单独覆盖了 00:00–05:00（下一个 if）。
            // 现在改成「昨天 18:00 → 今天 00:00」，与"凌晨"拼起来正好覆盖一整个夜晚。
            let y = addDays(now, -1)
            let evening = cal.startOfDay(for: y).addingTimeInterval(18 * 3600)
            let midnight = cal.startOfDay(for: now)
            out.append(("昨晚", (evening, midnight)))
        }
        if joined.contains("凌晨") {
            let s = cal.startOfDay(for: now)
            out.append(("凌晨", (s, s.addingTimeInterval(5 * 3600))))
        }
        if joined.contains("上周"), let curWeek = WeekCal.calendar.dateInterval(of: .weekOfYear, for: now) {
            // 912: 周界走 WeekCal (只影响 firstWeekday / 最小周天数，日与月的边界不动)
            out.append(("上周", (WeekCal.shifted(curWeek.start, days: -7), curWeek.start)))
        }
        if joined.contains("本周"), let curWeek = WeekCal.calendar.dateInterval(of: .weekOfYear, for: now) {
            out.append(("本周", (curWeek.start, now)))
        }
        if joined.contains("上月"),
           let prevMonth = cal.date(byAdding: .month, value: -1, to: now),
           let m = cal.dateInterval(of: .month, for: prevMonth) {
            out.append(("上月", (m.start, m.end)))
        }
        if joined.contains("本月"), let m = cal.dateInterval(of: .month, for: now) {
            out.append(("本月", (m.start, now)))
        }
        if let n = intAfter(joined, "最近"), n > 0 {
            // 搜索框是逐字符触发的：`最近999999999999999天` 会让 Date 跑到
            // Int64 范围之外，后面 `Int64(timeIntervalSince1970)` 直接 trap。
            // 100 年已经覆盖任何真实查询，超出部分夹住即可。
            let days = min(n, 36500)
            let s = WeekCal.shifted(now, days: -days)
            out.append(("最近 \(days) 天", (cal.startOfDay(for: s), now)))
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
        let f = DF.shortDayTime
        return f.string(from: r.from) + " – " + f.string(from: r.to)
    }

}
