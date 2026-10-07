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
    static func dateOf(_ l: CachedLog) -> Date? {
        let ms = ZKProtocol.protoSecondsToMs(l.lockTime) / 1000
        guard ms > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ms))
    }
    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }
    static func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
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

    // ---------- 模型 ----------
    struct DailyPoint: Identifiable {
        let day: Date
        let key: String
        let opens: Int
        let alarms: Int
        var id: String { key }
    }
    struct MovingPoint: Identifiable {
        let day: Date
        let avg: Double
        var id: Date { day }
    }
    struct GapBand {
        let from: Date
        let to: Date
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
    struct MonthPair {
        let days: Int
        let start: Date
        let thisMonth: [DailyPoint]
        let lastMonth: [DailyPoint]
        let thisCount: Int
        let lastCount: Int
        let complete: Bool
        /// 数据积累中还差多少天 (622 降级文案用)
        var lackingDays: Int { max(0, Int(start.timeIntervalSince1970 / 86400) - coverageDays) + 1 }
    }
    struct TempGantt: Identifiable {
        let alias: Int
        let name: String
        let owner: String
        let from: Date?
        let to: Date?
        let expired: Bool
        /// 横条上的开门刻度点 (R1 可证明归属到本条临时码, 609)
        let ticks: [Int16]
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
        /// 622 降级护栏: 覆盖不足 7 天或开门事件不足 5 条时不渲染空坐标轴, 显示"积累 X 天后可用"
        var isDegraded: Bool {
            !hasData || coverage < 7 || logs.filter { openTypes.contains($0.type) }.count < 5
        }

        var windowStart: Date {
            let s = startOfDay(Date()).addingTimeInterval(-Double(max(0, windowDays - 1)) * 86400)
            // 642 无数据底纹: 只画到缓存最早记录日, 更早日期区间视为"无数据"而非"0 次"
            if let e = earliest, e > s { return startOfDay(e) }
            return s
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
            let cal = Calendar.current
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
            for i in 0..<(ts.count - 1) {
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
                let h = Int16(Calendar.current.component(.hour, from: d))
                var rec = map[h] ?? (0, 0)
                if openTypes.contains(l.type) { rec.o += 1 }
                if alarmTypes.contains(l.type) { rec.a += 1 }
                map[h] = rec
            }
            return (0..<24).map { HourStat(hour: Int16($0), opens: map[Int16($0)]?.o ?? 0, alarms: map[Int16($0)]?.a ?? 0) }
        }

        var weekdayStats: [WeekdayStat] {
            let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            var map = [Int: Int]()
            for l in logsInWindow() where openTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                map[Calendar.current.component(.weekday, from: d), default: 0] += 1
            }
            return (1...7).map { WeekdayStat(weekday: $0, name: names[$0 - 1], opens: map[$0] ?? 0) }
        }

        var typeOpenCount: [String: Int] {
            var m = [String: Int]()
            for l in logsInWindow() {
                guard let k = Attribution.openKind[l.type] else { continue }
                m[k, default: 0] += 1
            }
            return m
        }

        /// 615 帕累托 / 619 Top5: 凭证种类降序 + 累计占比
        var pareto: [(kind: String, label: String, count: Int, cumPct: Double)] {
            let words = Attribution.words
            let total = typeOpenCount.values.reduce(0, +)
            let pairs = typeOpenCount.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
            var acc = 0.0
            var out = [(kind: String, label: String, count: Int, cumPct: Double)]()
            for p in pairs {
                acc += total > 0 ? Double(p.1) / Double(total) * 100 : 0
                out.append((kind: p.0, label: words[p.0] ?? "NFC", count: p.1, cumPct: acc))
            }
            return out
        }

        /// 601 本月上月同比: 上月数据缺失 (缓存跨度不足) 时 complete = false, UI 降级
        var monthPair: MonthPair {
            let cal = Calendar.current
            let now = Date()
            let tStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let lStart = cal.date(byAdding: .month, value: -1, to: tStart)!
            let lEnd = cal.date(byAdding: .day, value: -1, to: tStart)!
            var thisM = [String: DailyPoint](), lastM = [String: DailyPoint]()
            var tCount = 0, lCount = 0
            for e in logs {
                guard let d = dateOf(e) else { continue }
                guard openTypes.contains(e.type) || alarmTypes.contains(e.type) else { continue }
                let k = dayKey(d)
                let isThis = d >= tStart
                let inLast = d >= lStart && d <= lEnd
                guard isThis || inLast else { continue }
                var map = isThis ? thisM : lastM
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
                             complete: earliest != nil && earliest! <= lStart)
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

        /// 613/620 告警构成: 按子类型分组 (近 30 天), 620 双柱按月
        var alertStats: [AlertStat] {
            let names: [Int: String] = [6: "电量低", 7: "防撬", 10: "试错锁定", 13: "指纹告警", 224: "键盘锁定"]
            let colors: [Int: String] = [6: "warn", 7: "danger", 10: "warn", 13: "neutral", 224: "danger"]
            let cal = Calendar.current
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
        var alertTotalMonth: Int { alertStats.reduce(0) { $0 + $1.month } }
        var alertTotalLast: Int { alertStats.reduce(0) { $0 + $1.last } }

        /// 799 成员周小结 (797 同款纪律: 只有 Attribution 可证明归属才计数, 文案带"约")
        func weekSummary() -> [String] {
            let s = Date().addingTimeInterval(-7 * 86400)
            let recent = logsInWindow().filter { l in
                openTypes.contains(l.type) && (dateOf(l) ?? .distantPast) >= s
            }
            guard !recent.isEmpty else { return [] }
            let cls = Attribution.classify(
                logs: recent.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac), status: nil)
            var per = [String: Int]()
            var hour = [Int: Int]()
            for (i, c) in cls.enumerated() {
                guard let who = c.who else { continue }
                per[who, default: 0] += 1
                if let d = dateOf(recent[i]) {
                    hour[Calendar.current.component(.hour, from: d), default: 0] += 1
                }
            }
            var out = [String]()
            for (id, cnt) in per.sorted(by: { $0.value > $1.value }) {
                let name = DB.member(id)?.name ?? "成员"
                if let best = hour.max(by: { $0.value < $1.value }), best.key >= 6 && best.key <= 23 {
                    out.append("\(name)本周开门约 \(cnt) 次, 集中在 \(best.key) 时前后")
                } else {
                    out.append("\(name)本周开门约 \(cnt) 次")
                }
            }
            if out.isEmpty { out.append("近 7 天开门都还没有可证明的归属记录 (归属需要台账与日志窗口对齐)") }
            return out
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
                guard let ms = msOf2(l) else { continue }
                // 时间窗命中: 事件时刻落在该密码 [from,to] 内
                let inWin = pwds.filter { p in
                    guard !p.temp, let f = msOf(p.from), let t = msOf(p.to) else { return false }
                    return ms >= f && ms <= t
                }
                guard inWin.count == 1, let p = inWin.first else { continue }   // 唯一命中才算数, 否则归属不明
                per[p.alias, default: 0] += 1
                firsts[p.alias] = firsts[p.alias] ?? dayKey(Date(timeIntervalSince1970: ms / 1000))
            }
            return pwds.filter { !$0.temp }.map { p in
                let f = msOf(p.from), t = msOf(p.to)
                let days = (f != nil && t != nil) ? max(1, Int(t! / 86400000 - f! / 86400000) + 1) : 1
                let u = per[p.alias] ?? 0
                let disp = p.note.isEmpty ? ("#" + String(p.alias)) : p.note
                return PwdUse(alias: p.alias, name: disp, owner: p.owner ?? "", note: p.note,
                              approxUses: u, firstUseDay: firsts[p.alias], outOfRange: 0,
                              ratio: days > 0 ? Double(min(u, days)) / Double(days) : 0)
            }
        }

        /// 628 越界开门: 落在所有长期密码时间窗之外的密码开门次数 (台账推断, "约"级)
        var outOfRangeTotal: Int {
            var n = 0
            for l in logsInWindow() where l.type == 2 {
                guard let ms = msOf2(l) else { continue }
                let covered = pwds.contains { p in
                    guard !p.temp, let f = msOf(p.from), let t = msOf(p.to) else { return false }
                    return ms >= f && ms <= t
                }
                if !covered { n += 1 }
            }
            return n
        }

        /// 617 在外时长代理 (棒棒糖) + 618 首次开门区间
        /// 612/624 成员水平条与周小结共用: 近 N 天可证明归属计数 (Attribution, "约"级)
        func memberCounts(days: Int) -> [(id: String, name: String, approx: Int)] {
            let s = Date().addingTimeInterval(-Double(days) * 86400)
            let recent = logsInWindow().filter { openTypes.contains($0.type) && (dateOf($0) ?? .distantPast) >= s }
            let cls = Attribution.classify(
                logs: recent.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac), status: nil)
            var per = [String: Int]()
            for c in cls where c.who != nil { per[c.who!, default: 0] += 1 }
            return per.map { (id: $0.key, name: DB.member($0.key)?.name ?? "成员", approx: $0.value) }
                .sorted { $0.approx > $1.approx }
        }

        /// 800 在家时长代理值: 每日首末开门间隔求和 (小时, 代理口径 — 协议无门磁/上锁状态, 只能以开门事件包围近似)
        func homeDurationProxy(days: Int) -> [String] {
            let cal = Calendar.current
            let s = cal.date(byAdding: .day, value: -min(days, 30), to: cal.startOfDay(Date()))!
            var byDay = [String: (Int, Int)]()   // dayKey → (minHM, maxHM) 十进制时分
            for l in logsInWindow() where openTypes.contains(l.type) {
                guard let d = dateOf(l), d >= s else { continue }
                let k = dayKey(d)
                let hm = cal.component(.hour, from: d) * 100 + cal.component(.minute, from: d)
                var rec = byDay[k] ?? (hm, hm)
                byDay[k] = (min(rec.0, hm), max(rec.1, hm))
            }
            return byDay.sorted(by: { $0.key < $1.key }).suffix(30).map { k, r in
                let hours = (r.1 - r.0) / 100 + ((r.1 - r.0) % 100 > 0 ? 1 : 0)
                return dayLabel(k) + " 约 " + String(max(1, hours)) + " 小时在外"
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

        var rangeRows: [RangeRow] {
            var m = [String: (minH: Int, maxH: Int, c: Int)]()
            for l in logsInWindow() where openTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                let k = dayKey(d)
                let h = Calendar.current.component(.hour, from: d)
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
            let nowMs = Date().timeIntervalSince1970 * 1000
            let tLogs = logsInWindow().filter { $0.type == 4 }
            return pwds.filter { $0.temp }.sorted { ($0.at) > ($1.at) }.prefix(10).map { p in
                let f = msOf(p.from), t = msOf(p.to)
                // R1 同款窗口匹配: 事件落在 [from,to] 内 → 刻度点 (可证明)
                var ticks = [Int16]()
                var days = Set<String>()
                for l in tLogs {
                    guard let ms = msOf2(l) else { continue }
                    if f != nil && t != nil, ms >= f, ms <= t {
                        if let d = dateOf(l) {
                            let h = Int16(Calendar.current.component(.hour, from: d))
                            ticks.append(h)
                            days.insert(dayKey(d))
                        }
                    }
                }
                let avail = (f != nil && t != nil) ? max(1, Int(t! / 86400000 - f! / 86400000) + 1) : 1
                let expired = t != nil && t! < nowMs
                let name = p.note.isEmpty ? ("#" + String(p.alias)) : p.note
                let owner = DB.member(p.owner)?.name ?? ""
                return TempGantt(alias: p.alias, name: name, owner: owner, from: f.map { Date(timeIntervalSince1970: $0 / 1000) },
                                 to: t.map { Date(timeIntervalSince1970: $0 / 1000) }, expired: expired,
                                 ticks: ticks, usedDays: days.count, availDays: avail)
            }
        }

        /// 627 OTP 使用散点: 临时密码开门时刻
        var otpPoints: [OtpPoint] {
            var out = [OtpPoint]()
            for l in logsInWindow() where l.type == 4 {
                guard let d = dateOf(l) else { continue }
                let h = Int16(Calendar.current.component(.hour, from: d))
                let f = DateFormatter()
                f.dateFormat = "MM-dd HH"
                f.timeZone = TimeZone.current
                out.append(OtpPoint(day: startOfDay(d), hour: h, label: f.string(from: d) + String(format: ":%02d", h)))
            }
            return out
        }
        private func msOf(_ s: String) -> Double? {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            f.timeZone = TimeZone.current
            guard let d = f.date(from: s) else { return nil }
            return d.timeIntervalSince1970 * 1000
        }
        private func msOf2(_ l: CachedLog) -> Double? {
            let ms = ZKProtocol.protoSecondsToMs(l.lockTime) / 1000
            guard ms > 0 else { return nil }
            return Double(ms)
        }
    }

    // ---------- 构建 ----------
    @MainActor
    static func build(mac: String, week: Int, window: Int) -> StatModel {
        let logs = DB.readLogs(mac)
        let kc = DB.keychain(mac)
        let name = kc.map { LockArchive.displayName($0) } ?? "门锁"
        return StatModel(mac: mac, lockName: name, windowDays: window, week: week,
                         logs: logs, pwds: DB.listPwds(mac), earliest: earliestDate(logs))
    }

    /// 673 春节近似区间: 内置 2026-02 静态表 (无节假日表依赖, 文案明示"近似")
    static var springFestiveRange: (from: Date, to: Date, label: String)? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        guard let s = f.date(from: "2026-02-15"), let e = f.date(from: "2026-02-23") else { return nil }
        return (s, e, "春节假期 (近似)")
    }
}
