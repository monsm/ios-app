// 包10 统计与图表 — 纯本地聚合层 (Swift Charts 数据源)
// 数据全部来自既有本地台账 (kf_logcache_ 锁日志缓存 / kf_ledger_ 凭证台账 / kf_members 成员),
// 与 LockStats 同纪律: 只读既有表, 不新增采集, 不碰协议层, 归属只走 Attribution 可证明链 (R1/R2),
// 推不出的不猜 (CAPABILITY §3: 日志无身份字段, 成员相关统计一律"约"级)。
import Foundation
import SwiftUI

enum StatsKit {
    static let openTypes: Set<Int> = [1, 2, 3, 4, 5]
    static let alarmTypes: Set<Int> = [6, 7, 10, 13, 224]

    // ---------- 日期 ----------
    /// 缓存日志的协议秒 → 本地 `Date`。**`lockTime == 0` 是"锁端时钟没读到/无时钟型号"的占位值**
    /// (Milestones 夜猫子徽章那段早就把这条规则写明了：换算后落在协议纪元 2010-01-01 00:00，
    /// 其小时必然 < 6，会凭空点亮徽章)。这里原本写的是 `guard ms > 0`，而 `ms` 其实是 **Unix 秒**
    /// (1.7e9 量级)，`lockTime = 0` 换算出来是 2010-01-01 也是 > 0 ⇒ **那条守卫恒真、永不生效**：
    /// 全仓 47 个 `dateOf` 调用方都把一条没有时间戳的记录当成 2010-01-01 那条日子在数
    /// (`earliestDate` 被钉死在 2010 ⇒ 642 的"缓存最早从 2010-01-01 起"、`coverageDays` 约 6100 天、
    /// 日/月桶各多一个幽灵日)。口径收在这一个地方：没有锁端时刻 = 没有日期，返回 nil (§10.32)。
    static func dateOf(_ l: CachedLog) -> Date? {
        guard l.lockTime > 0 else { return nil }
        return Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(l.lockTime))
    }
    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }
    static func startOfDay(_ d: Date) -> Date {
        WeekCal.gregorian.startOfDay(for: d)
    }
    /// 616 周几分布与 780 工作日判定**共用**这一个周序: Calendar 的 `.weekday` 是 1=周日…7=周六，
    /// 而本仓的桶序是 1=周一…7=周日。两处各写一遍 `(+5)%7+1` 的话，改一处就会让"工作日"和
    /// "周几柱"对不上 —— 616 那条注释记录的正是这类平移一天的 bug。
    static func weekdayIndex(_ d: Date) -> Int {
        (WeekCal.gregorian.component(.weekday, from: d) + 5) % 7 + 1
    }
    /// 780 工作日口径: 非法定假日，且 (周一~周五 或 表里写着补班)。
    /// 假日表是 RecordSearch 那一份 (671 可在线更新)，这里不另立一套规则；表没覆盖的年份
    /// 就只按周几算 —— 那件事在 608/673 的口径里已经写明，界面上也照样要说。
    static func isWorkday(_ d: Date) -> Bool {
        let k = dayKey(d)
        if RecordSearch.holidayName(k) != nil { return false }
        if RecordSearch.isMakeupWorkday(k) { return true }
        return weekdayIndex(d) <= 5
    }
    /// 距本地零点的秒数 —— 用来比"哪天开得更早"。不做 12/24 制，那是显示层的事。
    static func secondsOfDay(_ d: Date) -> Int {
        let c = WeekCal.gregorian.dateComponents([.hour, .minute, .second], from: d)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }
    /// 缓存最早记录日 → 可回看的 7/30/90 天窗口; 缓存为空返回 nil
    static func earliestDate(_ logs: [CachedLog]) -> Date? {
        var e: Date? = nil
        for l in logs {
            if let d = dateOf(l), openTypes.contains(l.type) || alarmTypes.contains(l.type) {
                e = (e == nil) ? d : min(e!, d)
            }
        }
        return e
    }
    static func coverageDays(_ logs: [CachedLog]) -> Int {
        guard let e = earliestDate(logs) else { return 0 }
        return max(1, Int(Date().timeIntervalSince(e) / 86400) + 1)
    }

    // ---------- 646 小时桶降采样 (明细列表的上屏折叠) ----------
    /// 646 的折叠本体: 把一组逐条日志按 (日, 小时) 折成桶, 桶内各自计开门/告警, 并留**最近一条真日志**做跳转样本。
    /// 最新桶在前 (与 621 逐条列表同一个方向, "列最近 N 个"的截断才能同侧取前 N)。
    /// 只在 `StatModel.isHourFolded` 那一档才调用; 折完行数没少时调用方继续逐条列 (界面那句"已折叠"也不出现)。
    /// 要说清的边界: 日志缓存每锁只有 300 条 (`Store` 合并日志时硬截), 这里折的是**上屏行数**;
    /// 原句"万条日志保持 60fps"那个量级本仓读不到, 不拿这一条冒充它。
    static func hourBuckets(_ rows: [CachedLog]) -> [HourBucket] {
        var map = [String: (day: String, hour: Int16, opens: Int, alarms: Int, sample: CachedLog)]()
        for l in rows {
            guard let d = dateOf(l) else { continue }      // 没有锁端时刻 = 没有日期, 不进桶 (见 dateOf 那条口径)
            let day = dayKey(d)
            let h = Int16(WeekCal.gregorian.component(.hour, from: d))
            let k = day + " " + String(format: "%02d", h)   // 小时补零 ⇒ 字符串序就是时间序 (与全仓排序口径一致)
            var rec = map[k] ?? (day, h, 0, 0, l)
            if openTypes.contains(l.type) { rec.opens += 1 }
            if alarmTypes.contains(l.type) { rec.alarms += 1 }
            if d >= (dateOf(rec.sample) ?? .distantPast) { rec.sample = l }
            map[k] = rec
        }
        return map.keys.sorted().reversed().compactMap { k in
            guard let r = map[k] else { return nil }
            return HourBucket(key: k, day: r.day, hour: r.hour, opens: r.opens, alarms: r.alarms, sample: r.sample)
        }
    }

    // ---------- 模型 ----------
    struct DailyPoint: Identifiable {
        let day: Date
        let key: String
        // 2026-10-13 run 63: 原为 let —— 但 monthPair 里 `rec.opens += 1` / `rec.alarms += 1`
        // 要就地累加, 报 "left side of mutating operator isn't mutable: 'opens' is a 'let' constant"。
        var opens: Int
        var alarms: Int
        var id: String { key }
    }
    struct MovingPoint: Identifiable {
        let day: Date
        let avg: Double
        var id: Date { day }
    }
    /// 610/642/673 的空窗与节日底带: 单参 ForEach 要 Identifiable ——
    /// 单参 ForEach 要求元素 Identifiable, 而元组不能遵循协议 (与 605 同族修法; 与 key path 无关)。
    struct GapBand: Identifiable {
        let from: Date
        let to: Date
        var id: Date { from }
    }
    /// 605 告警散点阵的点: Chart(_:content:) 单参版要 "identifiable marks",
    /// 元组过不了 (原 [(day:type:typeName:)]); seq 保证同日同型多条也不撞 id。
    struct AlarmScatterPoint: Identifiable {
        let day: Date
        let type: Int
        let typeName: String
        let seq: Int
        var id: String { "\(seq)" }
    }
    struct HourStat: Identifiable {
        let hour: Int16
        let opens: Int
        let alarms: Int
        var id: Int16 { hour }
    }
    struct WeekdayStat: Identifiable {
        let weekday: Int   // 1 = 周一 … 7 = 周日
        let name: String
        let opens: Int
        var isWeekend: Bool { weekday >= 6 }
        var id: Int { weekday }
    }
    /// 780 一个工作日"当天第一次开门"的样本。timeStr 是锁端原串，显示只走 TimeFormat.clockOnly 那一个出口。
    struct FirstOpenSample {
        let dayKey: String
        let secondsOfDay: Int
        let timeStr: String
    }
    struct MonthPair {
        let days: Int
        let start: Date
        let thisMonth: [DailyPoint]
        let lastMonth: [DailyPoint]
        let thisCount: Int
        let lastCount: Int
        let complete: Bool
        // 2026-10-13 run 63: lackingDays 原先裸用 `coverageDays` —— 那是 StatModel 上的
        // `static func coverageDays(_ logs:)`, 在 MonthPair 里既不在作用域、又缺实参, 报
        // "cannot convert value of type '([CachedLog]) -> Int' to expected argument type 'Int'"。
        // 把外层 StatModel.coverage 作为字段传进来 (构造点在 monthPair)。
        let coverage: Int
        /// 数据积累中还差多少天 (622 降级文案用)
        /// 2026-10-13 对抗式排查: 原写 `max(0, Int(start.timeIntervalSince1970 / 86400) - coverage) + 1` ——
        /// `start.timeIntervalSince1970 / 86400` 是 **epoch 绝对日号** (今天是 20686 这样的数),
        /// 减掉 coverage 再加 1 得到的是 20627 这种天文数字, 不是"还差几天"。
        /// 正确的是"从本月首日到今天共几天"减"已覆盖几天", 不足 0 夹到 0。
        var lackingDays: Int { max(0, Int(Date().timeIntervalSince(start) / 86_400) + 1 - coverage) }
    }
    struct TempGantt: Identifiable {
        let alias: Int
        let name: String
        let owner: String
        let from: Date?
        let to: Date?
        let expired: Bool
        /// 横条上的开门刻度点时刻 (R1 可证明归属到本条临时码, 609 — 存全时刻供按真实位置定位)
        let ticks: [Date]
        /// 生效期内实际使用天数 / 可开天数 (629 核销率)
        let usedDays: Int
        let availDays: Int
        var id: Int { alias }
    }
    struct OtpPoint: Identifiable {
        let day: Date
        let hour: Int16
        let label: String
        var id: String { label }
    }
    /// 624 成员活跃气泡图的一个泡: x = 窗口内可证明归属次数, y = 距最近一次开门天数, r 由凭证数定。
    struct MemberBubble: Identifiable {
        let id: String
        let name: String
        let count: Int
        let daysAgo: Int
        let creds: Int
    }
    struct PwdUse {
        let alias: Int
        let name: String
        let owner: String
        let note: String
        /// 台账推断: 生效期内 type2 开门次数; 锁端不提供逐凭证次数 (CAPABILITY §3), 展示必须带"约"
        let approxUses: Int
        let firstUseDay: String?
        let outOfRange: Int
        let ratio: Double
    }
    struct RangeRow: Identifiable {
        let day: Date
        let key: String
        let minHour: Int
        let maxHour: Int
        let count: Int
        var id: String { key }
    }
    /// 646 小时桶: 一条 (日, 时) 桶 = 落在这一个小时里的逐条日志折成的一行 (明细列表用它上屏)。
    /// `sample` 留着该桶**最近一条真日志** ⇒ 点按仍跳到记录页那一行并高亮 (621/170 的跳转不因折叠而丢)。
    struct HourBucket: Identifiable {
        let key: String          // "yyyy-MM-dd HH" (小时补零 ⇒ 字符串序就是时间序)
        let day: String          // yyyy-MM-dd
        let hour: Int16
        let opens: Int
        let alarms: Int
        let sample: CachedLog
        var id: String { key }
    }
    struct AlertStat: Identifiable {
        let typeName: String
        let month: Int
        let last: Int
        let color: String
        var id: String { typeName }
    }

    // ---------- 查询 ----------
    struct StatModel {
        let mac: String
        let lockName: String
        let windowDays: Int
        let week: Int
        let logs: [CachedLog]
        let pwds: [LedgerPwd]
        let earliest: Date?

        var hasData: Bool { !logs.isEmpty }
        var coverage: Int { coverageDays(logs) }
        /// 窗口内的开门/告警总数。与 621 的区间计数一样都从 `logsInWindow()` 那份"窗口 ∩ 缓存"里出 ——
        /// 想改总量口径只改那一处，别在视图里再 `reduce` 一遍第二个定义。
        var opensTotal: Int { dailyPoints.reduce(0) { $0 + $1.opens } }
        var alarmsTotal: Int { dailyPoints.reduce(0) { $0 + $1.alarms } }
        /// 622 降级护栏: 覆盖不足 7 天或开门事件不足 5 条时不渲染空坐标轴, 显示"积累 X 天后可用"
        var isDegraded: Bool {
            !hasData || coverage < 7 || logs.filter { openTypes.contains($0.type) }.count < 5
        }

        var windowStart: Date {
            let s = WeekCal.shifted(startOfDay(Date()), days: -max(0, windowDays - 1))
            // 642 无数据底纹: 只画到缓存最早记录日, 更早日期区间视为"无数据"而非"0 次"
            if let e = earliest, e > s { return startOfDay(e) }
            return s
        }

        /// 678 周族窗口的**唯一读数**: 成员多线 (604)、图例胶囊 (632)、周小结 (799) 与界面上"近 N 天"
        /// 那几行字都从这里取同一个天数。原来 `week` 传进模型后全仓零消费 ⇒ 界面说"本周"、数据写死 7,
        /// 两套口径各说各的; 现在改一处就一起改。
        var weekWindowDays: Int { max(1, week) }
        /// 612/624 成员水平条的天数: 界面上那句"近 N 天"和查询参数同一个出处, 不再抄第二遍字面量
        var memberBarDays: Int { 30 }
        /// 646 长窗口档的天数 (90 天)。**这一族的 90 只写在这里一次** —— 折叠判据与 610 空窗带的
        /// 收起条件都读它, 免得哪天改成 60 天档时两处漂开。
        var longWindowDays: Int { 90 }
        /// 13 那排"近 N 天逐日柱"的天数: 它是 Apple Health 那一形态的**固定 7 天**, 刻意不跟 678 的周族档走
        /// (界面那句"近 7 天"与 `dailyPoints.suffix(7)` 以前各写一遍 7, 现在同一个出处)。
        var recentBarDays: Int { 7 }
        /// 605 告警散点阵的回看天数: 界面标题那句"近 N 天"与这里 `cut` 用的同一个数, 不再抄两遍。
        var alarmScatterDays: Int { 90 }
        /// 646 小时桶降采样的**唯一判据**: 窗口 ≥90 天才把明细折成 (日, 时) 桶。
        /// 界面那句"明细已按小时桶折叠"只读这个 Bool —— 文案与折叠同生同灭, 不许一处说折了、另一处还逐条列。
        var isHourFolded: Bool { windowDays >= longWindowDays }

        /// 618 窗口内**逐日首次开门**的最早/中位/最晚 (小时档)。三个数全从 `rangeRows` 的 minHour 里取 ——
        /// 与下方那排逐日条同一个出处, 不在别处再算第二套"首次开门"。分辨率只到「时」(与 608 同一句口径:
        /// 日志只到分, 而这里刻意按小时分桶看形状, 不是算错)。
        /// 中位取**下中位数**, 与 `workdayFirstOpenMedian` 同一条理由: 偶数个样本时插出来的那一刻没人开过门。
        var firstOpenHourSpread: (earliest: Int, median: Int, latest: Int)? {
            let v = rangeRows.map { $0.minHour }.sorted()
            guard let first = v.first, let last = v.last else { return nil }
            return (first, v[(v.count - 1) / 2], last)
        }

        func logsInWindow() -> [CachedLog] {
            let s = windowStart
            return logs.filter {
                guard let d = dateOf($0) else { return false }
                return d >= s
            }
        }

        var dailyPoints: [DailyPoint] {
            var map = [String: (o: Int, a: Int)]()
            for l in logsInWindow() {
                guard let d = dateOf(l) else { continue }
                let k = dayKey(d)
                var rec = map[k] ?? (0, 0)
                if openTypes.contains(l.type) { rec.o += 1 }
                if alarmTypes.contains(l.type) { rec.a += 1 }
                map[k] = rec
            }
            // 逐日补齐: "0 次"与"无数据"靠 gapBands 区分 (610/642)
            var out = [DailyPoint]()
            let cal = WeekCal.gregorian
            var d = startOfDay(windowStart)
            let end = startOfDay(Date())
            while d <= end {
                let k = dayKey(d)
                let rec = map[k] ?? (0, 0)
                out.append(DailyPoint(day: d, key: k, opens: rec.o, alarms: rec.a))
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            return out
        }

        var movingAverage: [MovingPoint] {
            let p = dailyPoints
            guard p.count >= 7 else { return [] }
            var out = [MovingPoint]()
            for i in 0..<p.count {
                let lo = max(0, i - 6)
                let slice = p[lo...i]
                out.append(MovingPoint(day: p[i].day, avg: Double(slice.reduce(0) { $0 + $1.opens }) / Double(slice.count)))
            }
            return out
        }

        var gapBands: [GapBand] {
            // 610: 相邻开门事件间隔 ≥48h 即"空窗区间" (外出时段可视化)
            var ts = [Date]()
            for l in logsInWindow() where openTypes.contains(l.type) {
                if let d = dateOf(l) { ts.append(d) }
            }
            ts.sort()
            var out = [GapBand]()
            // 窗口内没有开门记录时 ts 为空 → 旧写法 0..<(0-1) 触发 Range 前置条件崩溃 (统计页主路径)
            for i in 0..<max(0, ts.count - 1) {
                if ts[i + 1].timeIntervalSince(ts[i]) >= 48 * 3600 {
                    out.append(GapBand(from: ts[i], to: ts[i + 1]))
                }
            }
            return out
        }

        var hourStats: [HourStat] {
            var map = [Int16: (o: Int, a: Int)]()
            for l in logsInWindow() {
                guard let d = dateOf(l) else { continue }
                let h = Int16(WeekCal.gregorian.component(.hour, from: d))
                var rec = map[h] ?? (0, 0)
                if openTypes.contains(l.type) { rec.o += 1 }
                if alarmTypes.contains(l.type) { rec.a += 1 }
                map[h] = rec
            }
            return (0..<24).map { HourStat(hour: Int16($0), opens: map[Int16($0)]?.o ?? 0, alarms: map[Int16($0)]?.a ?? 0) }
        }

        /// 602 作息四轴 (早/午/晚/深夜) 开门密度：把 24 小时按段聚合，**边界显示出来**
        /// (原句要"夜归型一眼可辨"，那"深夜"到底从几点开始就必须说清，否则同一张图两个人读成两种)。
        /// 676: 深夜轴读「夜间时段」配置 (RecordSearch.nightFrom/nightTo, 与 572 深夜预设同一份判定)，
        /// 不再是写死的 22–04 —— 原先设置里把深夜调成 22–6, 统计页仍按 22–04 画, 两处各说各话。
        /// 每个小时只进一轴：先按配置切出深夜, 白天三轴按钟点归类, 所以配置再偏也不会重复计数。
        var dayparts: [(name: String, span: String, opens: Int)] {
            let hs = hourStats
            let night = hs.filter { RecordSearch.isLateNight(Int($0.hour)) }
            let day = hs.filter { !RecordSearch.isLateNight(Int($0.hour)) }
            func sum(_ xs: [HourStat]) -> Int { xs.reduce(0) { $0 + $1.opens } }
            func span(_ xs: [HourStat]) -> String {
                guard let lo = xs.map({ Int($0.hour) }).min(), let hi = xs.map({ Int($0.hour) }).max() else { return "—" }
                return String(format: "%02d–%02d", lo, hi)
            }
            let from = RecordSearch.nightFrom
            let to = RecordSearch.nightTo
            // 跨零点窗口的起止用"起–末小时"标 (22 起、6 前 ⇒ "22–05"), 与判定函数 hour<to 同口径
            let nightSpan = RecordSearch.nightWindowDegenerate ? "—" : String(format: "%02d–%02d", from, (to + 23) % 24)
            let morning = day.filter { Int($0.hour) < 11 }
            let noon = day.filter { (11...13).contains(Int($0.hour)) }
            let evening = day.filter { Int($0.hour) >= 14 }
            return [("早", span(morning), sum(morning)),
                    ("午", span(noon), sum(noon)),
                    ("晚", span(evening), sum(evening)),
                    ("深夜", nightSpan, sum(night))]
        }

        /// 622 降级护栏用：四轴总开门数 (雷达只在有量时才画)
        var daypartTotal: Int { dayparts.reduce(0) { $0 + $1.opens } }

        // ---------- 608 假期最后 3 天逐时开门 (系统电池用量图那一形态) ----------
        struct HolidayHour: Identifiable {
            let hour: Int16
            let opens: Int
            var id: Int16 { hour }
        }
        struct HolidayDay: Identifiable {
            let day: String          // yyyy-MM-dd
            let name: String           // 假期名 (元旦/春节…), 取自同一个出口
            let hours: [HolidayHour]
            let total: Int
            let peakHour: Int16
            var id: String { day }
        }
        /// 窗口内**最近一段连续放假日**的末 ≤3 天，各按小时数开门。
        /// 放假日只认 `RecordSearch.holidayName` 那一个出口 (它读本机已收录的 holiday-cn 缓存 + 内置表)，
        /// 没收录 ⇒ 这里返回空，界面上这一节直接不出现：**猜哪天放假**是把推断当事实，比不画更坏。
        var holidayTailDays: [HolidayDay] {
            let cal = WeekCal.gregorian
            var run = [String]()
            var last = [String]()
            func nextDay(_ k: String) -> String? {
                guard let d = RecordSearch.dateFromKey(k) else { return nil }
                guard let n = cal.date(byAdding: .day, value: 1, to: d) else { return nil }
                return StatsKit.dayKey(n)
            }
            var d = StatsKit.startOfDay(windowStart)
            let today = StatsKit.startOfDay(Date())
            var guardCount = 0                       // 死循环护栏: 窗口最多看 400 天
            while d <= today, guardCount < 400 {
                guardCount += 1
                let k = StatsKit.dayKey(d)
                if RecordSearch.holidayName(k) != nil {
                    // 连续 = 昨天也在这一段里; 断了就另起一段, 旧段留档
                    if let prev = run.last, nextDay(prev) == k { run.append(k) } else { if !run.isEmpty { last = run }; run = [k] }
                } else {
                    if !run.isEmpty { last = run; run = [] }
                }
                d = cal.date(byAdding: .day, value: 1, to: d) ?? today.addingTimeInterval(86400)
            }
            if !run.isEmpty { last = run }
            let tail = Array(last.suffix(3))
            guard !tail.isEmpty else { return [] }
            var byDay = [String: [Int16: Int]]()
            for l in logsInWindow() where openTypes.contains(l.type) {
                guard let dd = dateOf(l) else { continue }
                let k = StatsKit.dayKey(dd)
                guard tail.contains(k) else { continue }
                let h = Int16(cal.component(.hour, from: dd))
                var m = byDay[k] ?? [:]
                m[h, default: 0] += 1
                byDay[k] = m
            }
            return tail.map { k in
                let m = byDay[k] ?? [:]
                let hours = (0..<24).map { HolidayHour(hour: Int16($0), opens: m[Int16($0)] ?? 0) }
                let peak = hours.max(by: { $0.opens < $1.opens })?.hour ?? 0
                return HolidayDay(day: k, name: RecordSearch.holidayName(k) ?? "", hours: hours,
                                  total: m.values.reduce(0, +), peakHour: peak)
            }
        }

        var weekdayStats: [WeekdayStat] {
            let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            var map = [Int: Int]()
            for l in logsInWindow() where openTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                // Calendar .weekday 是 1=周日…7=周六, 而本结构的口径是 1=周一…7=周日 (names/isWeekend 都按此写)。
                // 旧实现直接把 .weekday 当桶键 → 全部标签平移一天 (周日的数据进"周一"桶),
                // 且 isWeekend (>=6) 实际圈到的是周五与周六、漏掉周日。
                // 这条换算现在是 weekdayIndex(_:) 一份规则 —— 780 的工作日判定与这里必须同一个周序。
                let cal = weekdayIndex(d)
                map[cal, default: 0] += 1
            }
            return (1...7).map { WeekdayStat(weekday: $0, name: names[$0 - 1], opens: map[$0] ?? 0) }
        }

        /// 780 窗口内**每个工作日**"当天最早一次开门"的样本, 按时刻从早到晚排好。
        /// 每个日子只取最早那一次 —— 一天开五次不把五个时刻都算进来, 那样统计的是开门量而不是作息。
        var workdayFirstOpens: [FirstOpenSample] {
            var byDay = [String: FirstOpenSample]()
            for l in logsInWindow() where openTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                let k = dayKey(d)
                guard isWorkday(d) else { continue }
                let s = secondsOfDay(d)
                if let cur = byDay[k], cur.secondsOfDay <= s { continue }
                byDay[k] = FirstOpenSample(dayKey: k, secondsOfDay: s, timeStr: l.lockTimeStr)
            }
            return byDay.values.sorted { $0.secondsOfDay < $1.secondsOfDay }
        }

        /// 780 的对照读数: 工作日首次开门的**中位数**。
        /// 为什么不是原句说的"平均"：首次开门时刻是个绕圈的量 —— 23:50 与 01:00 的算术平均是 12:40,
        /// 而那一刻根本没人开过门。中位数在同一批数据上说得出真话；偶数个样本取**下中位数**,
        /// 它是真发生过的一刻, 不是两个数插出来的。界面把这层口径写在图下方, 不让人按平均数去读。
        var workdayFirstOpenMedian: FirstOpenSample? {
            let v = workdayFirstOpens
            guard !v.isEmpty else { return nil }
            return v[(v.count - 1) / 2]
        }

        var typeOpenCount: [String: Int] {
            var m = [String: Int]()
            for l in logsInWindow() {
                guard let k = Attribution.openKind[l.type] else { continue }
                m[k, default: 0] += 1
            }
            return m
        }

        /// 615 帕累托 / 619 榜: **凭证类**降序 + 占比 + 累计占比。
        /// 口径先说死: 折的是 4 类凭证 (指纹/密码/临时密码/数字钥匙), **不是逐条凭证** —— 锁端不给逐凭证次数
        /// (CAPABILITY §3), 台账只能把 type2 归到"唯一命中的那条长期密码" (626 那一路), 覆盖面不足以出一条逐凭证的
        /// 累计曲线。所以这一支的界面也只许写"类"。
        /// 柱与线用**同一个 y 轴单位 (%)**: 原来柱画次数、线画 0…100 的累计, 却共用 `chartYScale(0...100)`
        /// ⇒ 超过 100 次的柱子被轴裁掉, 那根柱的高度就不是它自己的次数了。次数仍在 619 那排行里给数字。
        var pareto: [(kind: String, label: String, count: Int, pct: Double, cumPct: Double)] {
            let words = Attribution.words
            let total = typeOpenCount.values.reduce(0, +)
            let pairs = typeOpenCount.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
            var acc = 0.0
            var out = [(kind: String, label: String, count: Int, pct: Double, cumPct: Double)]()
            for p in pairs {
                let share = total > 0 ? Double(p.1) / Double(total) * 100 : 0
                acc += share
                out.append((kind: p.0, label: words[p.0] ?? "NFC", count: p.1, pct: share, cumPct: acc))
            }
            return out
        }

        /// 615 那句话里的"前几类": **累计首次够到 80% 的那一类算进去** (它自己就是跨过 80% 的那一步)。
        /// 原来写 `prefix { $0.cumPct <= 80 }.count` —— 那是"累计还没到 80% 的类数", 例如 60/85/95/100 只数出 1,
        /// 界面就说成"前 1 类承载 80% 开门", 而那一类其实只有 60%。够线的那一类被漏计 ⇒ 数说小了。
        /// 返回 nil 表示窗口内一次开门都没有 (没有数可说)。
        var paretoCover: (kinds: Int, cumPct: Double)? {
            let p = pareto
            guard !p.isEmpty else { return nil }
            if let i = p.firstIndex(where: { $0.cumPct >= 80 }) { return (i + 1, p[i].cumPct) }
            return (p.count, p[p.count - 1].cumPct)   // 浮点累加差一点点够不到 80 时按整表收口
        }

        /// 601 本月上月同比: 上月数据缺失 (缓存跨度不足) 时 complete = false, UI 降级
        var monthPair: MonthPair {
            let cal = WeekCal.gregorian
            let now = Date()
            let tStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let lStart = cal.date(byAdding: .month, value: -1, to: tStart)!
            // 上月末 = 本月起点, 取半开 [lStart, tStart): 原写法 lEnd = tStart 前一天 配 `<=`
            // 会把上月最后一天 (除零点整) 整天丢出同比 —— 界面说"上月全月", 却只算到月底前一天。
            let lEnd = tStart
            var thisM = [String: DailyPoint](), lastM = [String: DailyPoint]()
            var tCount = 0, lCount = 0
            for e in logs {
                guard let d = dateOf(e) else { continue }
                guard openTypes.contains(e.type) || alarmTypes.contains(e.type) else { continue }
                let k = dayKey(d)
                let isThis = d >= tStart
                let inLast = d >= lStart && d < lEnd
                guard isThis || inLast else { continue }
                let map = isThis ? thisM : lastM
                var rec = map[k] ?? DailyPoint(day: startOfDay(d), key: k, opens: 0, alarms: 0)
                if openTypes.contains(e.type) {
                    rec.opens += 1
                    if isThis { tCount += 1 } else { lCount += 1 }
                } else {
                    rec.alarms += 1
                }
                if isThis { thisM[k] = rec } else { lastM[k] = rec }
            }
            let t = thisM.values.sorted { $0.key < $1.key }
            let l = lastM.values.sorted { $0.key < $1.key }
            return MonthPair(days: 30, start: lStart, thisMonth: t, lastMonth: l,
                             thisCount: tCount, lastCount: lCount,
                             complete: earliest != nil && earliest! <= lStart,
                             coverage: coverage)
        }

        /// 641 环比箭头: 近 7 天 vs 前 7 天开门数
        var weekDelta: Double? {
            let pts = dailyPoints
            guard pts.count >= 14 else { return nil }
            let last7 = pts.suffix(7).reduce(0) { $0 + $1.opens }
            let prev7 = pts[pts.count - 14..<pts.count - 7].reduce(0) { $0 + $1.opens }
            guard prev7 > 0 else { return nil }
            return Double(last7 - prev7) / Double(prev7)
        }

        /// 613/620 告警构成: 按子类型分组的**本月**条数 (自然月首日起, 不是滚动 30 天) + 620 的上月对照读数。
        /// 界面那句"本月"必须与这里的 `mStart` 同一个口径 —— 以前注释写"近 30 天"、空态文案也跟着写"近 30 天",
        /// 而数据算的是本月: 每月 1 号那天它会说"近 30 天没有告警", 其实上周刚爆发过。
        var alertStats: [AlertStat] {
            let names: [Int: String] = [6: "电量低", 7: "防撬", 10: "试错锁定", 13: "指纹告警", 224: "键盘锁定"]
            let colors: [Int: String] = [6: "warn", 7: "danger", 10: "warn", 13: "neutral", 224: "danger"]
            let cal = WeekCal.gregorian
            let mStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            let lStart = cal.date(byAdding: .month, value: -1, to: mStart)!
            var m = [Int: Int](), lv = [Int: Int]()
            for l in logs where alarmTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                if d >= mStart { m[l.type, default: 0] += 1 }
                else if d >= lStart { lv[l.type, default: 0] += 1 }
            }
            return m.keys.sorted().map { AlertStat(typeName: names[$0] ?? "其他", month: m[$0] ?? 0, last: lv[$0] ?? 0, color: colors[$0] ?? "neutral") }
        }
        /// 605 告警散点阵的数据: 近 `alarmScatterDays` 天**每一条**告警的 (日, 类型号, 类型名)。
        /// 天数与界面标题那句"近 90 天"同一个出处 (以前一处写死在 cut、一处写死在文案里, 改一档就会各说一套)。
        /// 纵轴故意用类型号而不是次数 —— 605 的原句动机是"看防撬是不是集中在某一周爆发",
        /// 那是一个"哪些天、哪一类"的形状，聚合成次数就把它抹平了。
        /// 逐条上屏而不是抽样: 告警本来就少，抽样本该是给千点级折线图的降级手段，用在几十点上只会丢事件。
        var alarmScatter: [AlarmScatterPoint] {
            let cut = Date().addingTimeInterval(-Double(alarmScatterDays) * 86400)
            var out: [AlarmScatterPoint] = []
            for l in logs where alarmTypes.contains(l.type) {
                guard let d = dateOf(l), d >= cut else { continue }
                out.append(AlarmScatterPoint(day: d, type: l.type, typeName: l.typeName, seq: out.count))
            }
            return out
        }

        var alertTotalMonth: Int { alertStats.reduce(0) { $0 + $1.month } }
        var alertTotalLast: Int { alertStats.reduce(0) { $0 + $1.last } }

        /// 799 成员周小结 (797 同款纪律: 只有 Attribution 可证明归属才计数, 文案带"约")
        /// 天数读 `weekWindowDays` (678) —— 句子里的"近 N 天"与这里过滤用的 N 从此是同一个数, 不再一处写死 7。
        func weekSummary() -> [String] {
            let days = weekWindowDays
            let s = Date().addingTimeInterval(-Double(days) * 86400)
            // 不叠 logsInWindow 的第二道窗: 它的窗口是主图 windowDays, 比这里的 N 窄时
            // (主图 7 天 + 成员窗 30 天) 界面写着"近 N 天"、数据只算了 windowDays 天。
            let recent = logs.filter { l in
                openTypes.contains(l.type) && (dateOf(l) ?? .distantPast) >= s
            }
            guard !recent.isEmpty else { return [] }
            let cls = Attribution.classify(
                logs: recent.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac),
                status: DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            var per = [String: Int]()
            var hour = [Int: Int]()
            for (i, c) in cls.enumerated() {
                guard let who = c.who else { continue }
                per[who, default: 0] += 1
                if let d = dateOf(recent[i]) {
                    hour[WeekCal.gregorian.component(.hour, from: d), default: 0] += 1
                }
            }
            var out = [String]()
            for (id, cnt) in per.sorted(by: { $0.value > $1.value }) {
                let name = DB.member(id)?.name ?? "成员"
                if let best = hour.max(by: { $0.value < $1.value }), best.key >= 6 && best.key <= 23 {
                    out.append("\(name)近 \(days) 天开门约 \(cnt) 次, 集中在 \(best.key) 时前后")
                } else {
                    out.append("\(name)近 \(days) 天开门约 \(cnt) 次")
                }
            }
            if out.isEmpty { out.append("近 \(days) 天开门都还没有可证明的归属记录 (归属需要台账与日志窗口对齐)") }
            return out
        }

        /// 698 上周小结: 上一个**完整自然周** (周一–周日) 的开门 CSV + 三句话摘要 (总次数 / 最活跃成员 / 告警数)。
        /// 与 799 weekSummary 的差别: 那个是"滚动 N 天", 这条是自然周 —— 原句点名"上周"。
        /// 归属纪律同 799/797: 只有 Attribution 可证明归属才计入成员, 文案带"约"。
        /// 缓存只留最近 300 条 (Store.writeLogs), 上周翻不到时如实说明, 不把"没读到"写成"没发生"。
        func lastWeekDigest() -> (csv: String, lines: [String]) {
            let cal = WeekCal.gregorian
            let today = Date()
            guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today),
                  let from = cal.date(byAdding: .day, value: -7, to: thisWeek.start),
                  let end = cal.date(byAdding: .day, value: 7, to: from) else { return ("", []) }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            let head = fmt.string(from: from) + " 至 " + fmt.string(from: cal.date(byAdding: .day, value: -1, to: end) ?? from)
            let week = logs.filter { l in
                openTypes.contains(l.type) && (dateOf(l).map { $0 >= from && $0 < end } ?? false)
            }
            guard !week.isEmpty else {
                return ("", ["上周 (" + head + ") 没有本机读到的开门记录 — 缓存只留最近 300 条, 更早的翻不到不代表没发生。"])
            }
            let cls = Attribution.classify(
                logs: week.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac),
                status: DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            func esc(_ s: String) -> String {
                s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
            }
            var per = [String: Int]()
            var rows = ["时间,类型,成员"]
            for (i, c) in cls.enumerated() {
                let l = week[i]
                if let who = c.who { per[who, default: 0] += 1 }
                rows.append(esc(l.lockTimeStr) + "," + esc(l.typeName) + ","
                            + esc(c.who.flatMap { DB.member($0)?.name } ?? "未归属"))
            }
            let alarms = logs.filter { l in
                alarmTypes.contains(l.type) && (dateOf(l).map { $0 >= from && $0 < end } ?? false)
            }.count
            var lines = ["上周 (" + head + ") 共开门 \(week.count) 次。"]
            if let t = per.max(by: { $0.value < $1.value }), let n = DB.member(t.key)?.name {
                lines.append("最活跃成员: \(n) (约 \(t.value) 次)。")
            } else {
                lines.append("成员归属都还证明不了 (归属需要台账与日志窗口对齐)。")
            }
            lines.append("同期告警 \(alarms) 条。")
            return (rows.joined(separator: "\n"), lines)
        }

        /// 1020 黄金时段一句话
        var goldenSentence: String {
            let hs = hourStats
            let total = hs.reduce(0) { $0 + $1.opens }
            guard total > 0 else { return "暂无足够开门数据定位黄金时段" }
            let top = hs.filter { $0.opens == hs.map { $0.opens }.max() }.sorted { $0.hour < $1.hour }
            let h = top[0].hour
            let ph = (h + 1) % 24
            return "你家最常开门的时段是 \(h)-\(ph) 点"
        }

        /// 626/628 凭证维度: 逐条长期密码的台账推断用量与首用 (锁端无逐凭证计数, CAPABILITY §3, 展示必须带"约")
        var pwdUses: [PwdUse] {
            var per = [Int: Int]()
            var firsts = [Int: String?]()
            for l in logsInWindow() where l.type == 2 {
                guard let d = dateOf(l) else { continue }
                // 时间窗命中: 事件时刻落在该密码 [from,to] 内 (台账串 "yyyy-MM-dd HH:mm:ss" 本地时区)。
                // 两侧一律 **Unix 秒** —— 这里原本拿 `msOf2` 的返回值 (实为秒) 去和
                // `timeIntervalSince1970 * 1000` (毫秒) 比，1.7e9 永不 ≥ 1.7e12 ⇒ 命中恒 false (§10.32)。
                let inWin = pwds.filter { p in
                    guard !p.temp, let f = CredentialOrg.parseLocal(p.from), let t = CredentialOrg.parseLocal(p.to) else { return false }
                    return d.timeIntervalSince1970 >= f.timeIntervalSince1970 && d.timeIntervalSince1970 <= t.timeIntervalSince1970
                }
                guard inWin.count == 1, let p = inWin.first else { continue }   // 唯一命中才算数, 否则归属不明
                per[p.alias, default: 0] += 1
                firsts[p.alias] = firsts[p.alias] ?? dayKey(d)   // 这一句当时根本走不到 (上面恒 continue)，而它自己也还多除了一次 1000：首用日期会算到 1970-01-21
            }
            return pwds.filter { !$0.temp }.map { p in
                let f = CredentialOrg.parseLocal(p.from), t = CredentialOrg.parseLocal(p.to)
                // 窗口缺失/解析失败时按 1 天计, 不虚构; 上限 ≥1 防除零
                let days = (f != nil && t != nil) ? max(1, Int(t!.timeIntervalSince(f!) / 86400) + 1) : 1
                let u = per[p.alias] ?? 0
                let disp = p.note.isEmpty ? ("#" + String(p.alias)) : p.note
                return PwdUse(alias: p.alias, name: disp, owner: p.owner ?? "", note: p.note,
                              approxUses: u, firstUseDay: firsts[p.alias] ?? nil, outOfRange: 0,
                              ratio: days > 0 ? Double(min(u, days)) / Double(days) : 0)
            }
        }

        /// 628 越界开门: 落在所有长期密码时间窗之外的密码开门次数 (台账推断, "约"级)
        var outOfRangeTotal: Int {
            var n = 0
            for l in logsInWindow() where l.type == 2 {
                guard let d = dateOf(l) else { continue }
                let covered = pwds.contains { p in
                    guard !p.temp, let f = CredentialOrg.parseLocal(p.from), let t = CredentialOrg.parseLocal(p.to) else { return false }
                    return d.timeIntervalSince1970 >= f.timeIntervalSince1970 && d.timeIntervalSince1970 <= t.timeIntervalSince1970
                }
                if !covered { n += 1 }
            }
            return n
        }

        /// 617 在外时长代理 (棒棒糖) + 618 首次开门区间
        /// 612/624 成员水平条与周小结共用: 近 N 天可证明归属计数 (Attribution, "约"级)
        func memberCounts(days: Int) -> [(id: String, name: String, approx: Int)] {
            let s = Date().addingTimeInterval(-Double(days) * 86400)
            let recent = logs.filter { openTypes.contains($0.type) && (dateOf($0) ?? .distantPast) >= s }   // 不开第二道窗: 主图窗口比 N 窄时"近 N 天"会被悄悄截短
            let cls = Attribution.classify(
                logs: recent.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac),
                status: DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            var per = [String: Int]()
            for c in cls where c.who != nil { per[c.who!, default: 0] += 1 }
            return per.map { (id: $0.key, name: DB.member($0.key)?.name ?? "成员", approx: $0.value) }
                .sorted { $0.approx > $1.approx }
        }

        /// 624 成员活跃气泡图的三维 (归属口径与 612/604 相同: 只有 Attribution 可证明归属才计, "约"级)。
        /// x = 窗口内次数; y = 距最近一次开门的**天数** —— 这一维要扫**全量缓存**(窗口外也算),
        /// 否则"闲置三个月"的成员会被算成"窗口内没开过"而落不到 y 轴上; r = 名下凭证数 (台账 owner 计数)。
        func memberBubbles(days: Int) -> [MemberBubble] {
            let s = Date().addingTimeInterval(-Double(days) * 86400)
            let pwds = DB.listPwds(mac), fps = DB.listFps(mac)
            let status = DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) }
            func classify(_ src: [CachedLog]) -> [Attribution.Row] {
                Attribution.classify(
                    logs: src.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                    pwds: pwds, fps: fps, status: status)
            }
            let allOpen = logs.filter { openTypes.contains($0.type) }
            let allCls = classify(allOpen)
            var lastAt = [String: Date]()
            for (i, c) in allCls.enumerated() {
                guard let who = c.who, i < allOpen.count, let d = dateOf(allOpen[i]) else { continue }
                if let cur = lastAt[who] { if d > cur { lastAt[who] = d } } else { lastAt[who] = d }
            }
            let recent = logs.filter { openTypes.contains($0.type) && (dateOf($0) ?? .distantPast) >= s }
            var per = [String: Int]()
            for c in classify(recent) where c.who != nil { per[c.who!, default: 0] += 1 }
            return per.map { (id: String, n: Int) -> MemberBubble in
                let creds = pwds.filter { $0.owner == id }.count + fps.filter { $0.owner == id }.count
                let daysAgo = lastAt[id].map { max(0, Int(Date().timeIntervalSince($0) / 86400)) } ?? -1
                return MemberBubble(id: id, name: DB.member(id)?.name ?? "成员", count: n, daysAgo: daysAgo, creds: creds)
            }
            .filter { $0.daysAgo >= 0 }        // 全量缓存里扫不到该成员的行 → 不画 (不假装 0 天)
            .sorted { $0.count > $1.count }
        }

        /// 604 成员多线: 逐成员逐日可证明归属计数 (Attribution, "约"级; 无数据日补 0, 绝不伪造)
        func memberDaily(days: Int) -> [(id: String, name: String, perDay: [String: Int])] {
            let s = Date().addingTimeInterval(-Double(days) * 86400)
            let recent = logs.filter { openTypes.contains($0.type) && (dateOf($0) ?? .distantPast) >= s }   // 不开第二道窗: 主图窗口比 N 窄时"近 N 天"会被悄悄截短
            let cls = Attribution.classify(
                logs: recent.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac),
                status: DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            var per = [String: [String: Int]]()
            for (i, c) in cls.enumerated() {
                guard let who = c.who, i < recent.count else { continue }
                guard let d = dateOf(recent[i]) else { continue }
                per[who, default: [:]][dayKey(d), default: 0] += 1
            }
            return per.map { (id: $0.key, name: DB.member($0.key)?.name ?? "成员", perDay: $0.value) }
                .sorted { $0.perDay.values.reduce(0, +) > $1.perDay.values.reduce(0, +) }
        }

        /// 955 语音查"某人今天开了几次门": 今日可证明归属计数 (与 604/612 同一套 Attribution 归属口径, "约"级;
        /// 窗口是"今天零点起"而非 memberDaily(days:1) 的滚动 24 小时 —— 后者会把昨晚的算进"今天")
        func memberTodayCount(id: String) -> Int {
            let start = startOfDay(Date())
            let recent = logsInWindow().filter { openTypes.contains($0.type) && (dateOf($0) ?? .distantPast) >= start }
            let cls = Attribution.classify(
                logs: recent.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac),
                status: DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            return cls.filter { $0.who == id }.count
        }

        /// 625 凭证归属子段: 窗口内按 凭证类×成员 的可证明归属计数 (台账推断"约"级; 归属不出时不进)
        func kindOwnerBreakdown() -> [String: [(id: String, name: String, n: Int)]] {
            let cls = Attribution.classify(
                logs: logsInWindow().map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                                    lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac),
                status: DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            var out: [String: [String: Int]] = [:]
            for r in cls {
                guard let k = r.kind, let who = r.who else { continue }
                out[k, default: [:]][who, default: 0] += 1
            }
            return out.mapValues { dict in
                dict.map { (id: $0.key, name: DB.member($0.key)?.name ?? "成员", n: $0.value) }
                    .sorted { $0.n > $1.n }
            }
        }

        /// 800 在家时长代理值的日桶 (dayKey → (minHM, maxHM) 十进制时分): 文字版与月对比数值版共用这一个出处
        private func homeDayBuckets(from: Date, to: Date) -> [String: (Int, Int)] {
            let cal = WeekCal.gregorian
            var byDay = [String: (Int, Int)]()
            for l in logs where openTypes.contains(l.type) {
                guard let d = dateOf(l), d >= from, d < to else { continue }
                let k = dayKey(d)
                let hm = cal.component(.hour, from: d) * 100 + cal.component(.minute, from: d)
                let rec = byDay[k] ?? (hm, hm)
                byDay[k] = (min(rec.0, hm), max(rec.1, hm))
            }
            return byDay
        }
        /// 首末间隔折算小时 (两端「时分」差, 不足 1 小时按 1 计 — 隔 10 分钟也算出过门)
        private func homeHours(_ r: (Int, Int)) -> Int {
            let span = r.1 - r.0
            return max(1, span / 100 + (span % 100 > 0 ? 1 : 0))
        }
        /// 800 月对比数值版: [from, to) 逐日首末开门间隔求和 (小时) — 与文字版同出处, 不另算第二套
        func homeProxyHours(from: Date, to: Date) -> Int {
            homeDayBuckets(from: from, to: to).values.reduce(0) { $0 + homeHours($1) }
        }
        /// 800 在家时长代理值: 每日首末开门间隔求和 (小时, 代理口径 — 协议无门磁/上锁状态, 只能以开门事件包围近似)。
        /// 口径收在 homeDayBuckets: 不再叠 logsInWindow 的第二道窗, 名称是"近 N 天"就按 N 天算。
        func homeDurationProxy(days: Int) -> [String] {
            let cal = WeekCal.gregorian
            let s = cal.date(byAdding: .day, value: -min(days, 30), to: cal.startOfDay(for: Date()))!
            return homeDayBuckets(from: s, to: Date()).sorted(by: { $0.key < $1.key }).suffix(30).map { k, r in
                // 2026-10-13 对抗式排查: 原文案是"小时在外", 而同函数名 (homeDurationProxy)/本函数注释
                // (:870 "800 **在家**时长代理值")/统计页页脚 (StatsView "在家时长为「首末开门间隔求和」的代理值 (800)")
                // 三处都写"在家" —— 同一块屏幕上一行"在外"一行"在家", 必有一侧反了。按 800 声明的口径
                // 统一成"在家"(代理值本身仍是首末开门间隔, 语义边界由 800 的口径注释说明, 不在文案里翻案)。
                dayLabel(k) + " 约 " + String(homeHours(r)) + " 小时在家"
            }
        }
        private func dayLabel(_ key: String) -> String {
            let p = key.split(separator: "-")
            return p.count == 3 ? "\(Int(p[1]) ?? 0)-\(Int(p[2]) ?? 0)" : key
        }

        // ---------- 图表色 (只走 DS 语义令牌, 631 深浅模式由令牌自动切换) ----------
        static func kindColor(_ kind: String) -> Color {
            switch kind {
            case "fp": return DS.Palette.accent
            case "pwd": return DS.Palette.ok
            case "temp": return DS.Palette.warn
            case "key": return DS.Palette.textSub
            default: return DS.Palette.danger
            }
        }
        static func kindWords() -> [String: String] {
            ["fp": "指纹", "pwd": "密码", "temp": "临时密码", "key": "数字钥匙"]
        }
        static func kindOrder() -> [String] { ["fp", "pwd", "temp", "key"] }

        /// 667 万级计数缩写
        static func compact(_ n: Int) -> String {
            if n >= 10000 {
                let w = Double(n) / 10000
                return (w >= 10 ? String(Int(w)) : String(format: "%.1f", w).replacingOccurrences(of: ".0", with: "")) + " 万次"
            }
            return String(n) + " 次"
        }

        /// 652 指标自然句
        static func naturalSentence(total: Int, days: Int) -> String {
            guard days > 0, total > 0 else { return "窗口内还没有开门记录" }
            let avg = Double(total) / Double(days)
            let s = avg >= 10 ? String(Int(avg)) : String(format: "%.1f", avg)
            return "平均每天开门 \(s) 次"
        }

        /// 成员色 (612 成员水平条 / 成员小结): 按序号在 DS 令牌间轮转 — 颜色只走令牌, 不硬编码 hex
        static func memberColors() -> [Color] {
            [DS.Palette.accent, DS.Palette.ok, DS.Palette.warn, DS.Palette.danger, DS.Palette.accentText, DS.Palette.textSub]
        }
        static func memberColor(_ index: Int) -> Color {
            memberColors()[index % memberColors().count]
        }

        /// 617/618 那一族逐日条的**唯一数据源**。字段口径逐条钉住, 界面只许照这几个名字念:
        /// `minHour` = 当日**最早一次开门**的小时 (不是"离家时刻"), `maxHour` = 当日**最晚一次开门**的小时,
        /// `count` = 当日开门总次数 (只算 openTypes)。三者都来自 `logsInWindow()` 那一份"窗口 ∩ 缓存"。
        /// 所以这条能说的是"首末开门夹出来的区间 (在外时长代理)", 说不了"人在家多久"—— 800 那句代理口径同理。
        var rangeRows: [RangeRow] {
            var m = [String: (minH: Int, maxH: Int, c: Int)]()
            for l in logsInWindow() where openTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                let k = dayKey(d)
                let h = WeekCal.gregorian.component(.hour, from: d)
                var rec = m[k] ?? (h, h, 0)
                rec.minH = min(rec.minH, h)
                rec.maxH = max(rec.maxH, h)
                rec.c += 1
                m[k] = rec
            }
            return m.keys.sorted().map { k in
                let r = m[k]!
                return RangeRow(day: startOfDay(dateFromKey(k)), key: k, minHour: r.minH, maxHour: r.maxH, count: r.c)
            }
        }
        private func dateFromKey(_ k: String) -> Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            return f.date(from: k) ?? Date()
        }

        /// 609/629 临时码甘特 + 核销率
        var gantt: [TempGantt] {
            let nowSec = Date().timeIntervalSince1970
            let tLogs = logsInWindow().filter { $0.type == 4 }
            return pwds.filter { $0.temp }.sorted { ($0.at) > ($1.at) }.prefix(10).map { p in
                // 台账串 "yyyy-MM-dd HH:mm:ss" 本地时区 (与 CredentialOrg.parseLocal 同口径)；
                // 窗口与事件一律按 **Unix 秒** 比 —— 原来这里是 `msOf2`(秒) 对上 `* 1000`(毫秒)，
                // 于是每条临时码的刻度点与核销天数恒为 0 (§10.32)。
                let fD = CredentialOrg.parseLocal(p.from), tD = CredentialOrg.parseLocal(p.to)
                let f = fD.map { $0.timeIntervalSince1970 }, t = tD.map { $0.timeIntervalSince1970 }
                // R1 同款窗口匹配: 事件落在 [from,to] 内 → 刻度点 (可证明, 609 存全时刻)
                var ticks = [Date]()
                var days = Set<String>()
                for l in tLogs {
                    guard let d = dateOf(l) else { continue }
                    if let f, let t, d.timeIntervalSince1970 >= f, d.timeIntervalSince1970 <= t {
                        ticks.append(d)
                        days.insert(dayKey(d))
                    }
                }
                let avail = (fD != nil && tD != nil) ? max(1, Int(tD!.timeIntervalSince(fD!) / 86400) + 1) : 1
                let expired = tD != nil && tD!.timeIntervalSince1970 < nowSec
                let name = p.note.isEmpty ? ("#" + String(p.alias)) : p.note
                let owner = DB.member(p.owner)?.name ?? ""
                return TempGantt(alias: p.alias, name: name, owner: owner, from: fD, to: tD, expired: expired,
                                 ticks: ticks, usedDays: days.count, availDays: avail)
            }
        }

        /// 627 OTP 使用散点: 临时密码开门时刻
        var otpPoints: [OtpPoint] {
            var out = [OtpPoint]()
            for l in logsInWindow() where l.type == 4 {
                guard let d = dateOf(l) else { continue }
                let comps = WeekCal.gregorian.dateComponents([.hour, .minute], from: d)
                // 2026-10-13 对抗式排查: 原写 `String(format: ":%02d", h)` 而 h 是**小时**分量,
                // 又前面 `f.dateFormat = "MM-dd HH"` 已经印过小时 ⇒ 07:12 的开门被印成 "10-05 07:07",
                // 分钟 12 被吞。改成取 .minute。(y 轴仍用 hour, 那个是对的。)
                let h = Int16(comps.hour ?? 0)
                let mi = Int16(comps.minute ?? 0)
                let f = DateFormatter()
                f.dateFormat = "MM-dd HH"
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone.current
                out.append(OtpPoint(day: startOfDay(d), hour: h, label: f.string(from: d) + String(format: ":%02d", mi)))
            }
            return out
        }
    }

    // ---------- 构建 ----------
    @MainActor
    static func build(mac: String, week: Int, window: Int) -> StatModel {
        // 745 测试标记: 已标"测试"的自测告警不进统计 (键 = mac#idxRaw, 与 kf_rdispo 同一份)。
        // 在这里集中过滤 = 模型下游所有读数 (逐日告警/小时桶/构成/散点) 一次全排除,
        // 视图层不用各减一遍 (告警中心本身仍显示这些行, 只是灰显)。
        let testKeys = RecordSearch.testMarkedKeys
        let logs = DB.readLogs(mac).filter { !testKeys.contains(mac + "#" + String($0.idxRaw)) }
        let kc = DB.keychain(mac)
        let name = kc.map { LockArchive.displayName($0) } ?? "门锁"
        return StatModel(mac: mac, lockName: name, windowDays: window, week: week,
                         logs: logs, pwds: DB.listPwds(mac), earliest: earliestDate(logs))
    }

    /// 782 闲置锁判据 (全仓唯一读点): 本机日志里超 30 天无开门行 —— 说的是"没读到"而非"没人开";
    /// 从没拉取过日志的锁同样判闲置。对照页的灰标签与统计页的排除口径开关都读这一处。
    @MainActor
    static func isIdleLock(_ mac: String) -> Bool {
        let m = build(mac: mac, week: 7, window: 90)
        // 2026-10-13 对抗式排查: 原写 `m.dailyPoints.map{ $0.day }.max()` —— `dailyPoints` 是**逐日补齐**到
        // 今天的 (0 次也补行, 见其构造的 "逐日补齐" 注释), 所以 max() 恒等于今天 0 点,
        // `timeIntervalSince(last)` ≈ 0.x 天 < 30 天 ⇒ **本函数恒返回 false**。
        // 后果: LockCompareView 的"闲置标签"永远显示"30 天内有开门"; StatsView 的"排除闲置锁"开关恒不动一格。
        // 判据说的是"超 30 天无开门行", 所以要取**真有开门那天**里的最晚一个。
        let lastOpen = m.dailyPoints.filter { $0.opens > 0 }.map { $0.day }.max()
        guard let last = lastOpen else { return true }   // 90 天里一次开门都没有 = 闲置 (口径原文: 从没拉取过日志的锁同样判)
        return Date().timeIntervalSince(last) > 30 * 86_400
    }

    /// 673 春节区间:**直接取 671 表里该年春节"放假日"的首末日**, 不再用"前一日/后六日"推算。
    /// 旧推算在 2026 就偏了 (公告口径是 02-15~02-23, 且表里现在还含 02-14/02-28 两个补班日,
    /// 若不过滤 off 会把补班日当成春节首日)。表里没有该年 (如 2027 尚未公布) 就返回 nil, 宁可不画也不猜。
    /// `to` 是**右开区间** (= 最后一个放假日的次日 0 点)，理由见函数内注释。
    static func springFestiveRange(around date: Date = Date()) -> (from: Date, to: Date, label: String)? {
        let year = WeekCal.gregorian.component(.year, from: date)
        let prefix = String(year) + "-"
        let days = RecordSearch.holidays.filter { $0.name == "春节" && $0.off && $0.day.hasPrefix(prefix) }
                                        .map { $0.day }.sorted()
        guard let firstDay = days.first, let lastDay = days.last else { return nil }
        // 反解析走 `RecordSearch.dateFromKey` (yyyy-MM-dd → 本地 0 点, 已钉 en_US_POSIX)：
        // 这里原先自建 formatter 且没钉历法，用户系统选佛历时会把表里的 "2026-02-17"
        // 按佛历解释成公元 1468 年 ⇒ 春节档期永远命中不了 (§10.30)。
        guard let from = RecordSearch.dateFromKey(firstDay), let to = RecordSearch.dateFromKey(lastDay) else { return nil }
        // `dateFromKey` 给的是**该日 0 点**，直接当区间的右端用会少画一天：
        // 调用方 (`festivalRule`) 判的是 `f.to < windowStart`、画的是 Band(from…to)，
        // 于是假期最后一天既不在带里、窗口从那天中午起还会把整条带判成"不相交"，
        // 而文案写着"共 N 天"—— 说 N 天、画 N-1 天。右端推到次日 0 点 (按日历加一天，不用 86400 秒，避免夏令时那天差一小时)。
        let toEnd = WeekCal.gregorian.date(byAdding: .day, value: 1, to: to) ?? to
        return (from, toEnd, "春节假期 \(firstDay) ~ \(lastDay) (共 \(days.count) 天)")
    }
}
