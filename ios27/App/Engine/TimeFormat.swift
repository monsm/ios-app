// TimeFormat.swift —— 时间口径的唯一出口。
//
// 纪律：日期一律走 Gregorian 日历（用户历法切成佛历/农历时直接取 Calendar.current
// 会算出异 era 年份）；机器面格式钉 en_US_POSIX；UTC epoch 秒/毫秒不混用。
import Foundation

enum TimeFormat {
    /// 持久化的时间戳是否可信（**不超过"现在"太多**）。
    ///
    /// 为什么需要它：本仓多处用 `now - t` 做判断（冷却、节流、沉睡），而 `t` 来自 UserDefaults。
    /// 用户调过系统时间、或换机后带过来另一个设备的时钟时，`t` 可能**在未来** ——
    /// 于是 `now - t` 为负，判断结果被永久钉在一侧：
    ///   · `AutoOpenKit.coolReady`：冷却永久生效 ⇒ **自动开锁无声失效**（已修）；
    ///   · `LockStats.touchConnection`：`now - last < 300` 恒真 ⇒ **"最近连接时间"再也不更新**，
    ///     而那个字段喂给"30 天未连 → 沉睡"判定。
    /// 这里给一个容忍窗口（默认 60s）：小幅时钟漂移不算超前，真·未来值才算。
    static func timestampIsPlausible(_ t: Double, now: Double = Date().timeIntervalSince1970,
                                     tolerance: Double = 60) -> Bool {
        t <= 0 || t <= now + tolerance
    }

    /// 固定公历。取年月日一律走它，不走 Calendar.current。
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    /// 机器面格式：钉 POSIX，避免系统历法影响。
    private static func machine(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f
    }

    private static let clockFmt = machine("HH:mm")
    private static let dayKeyFmt = machine("yyyy-MM-dd")
    private static let dayShortFmt = machine("MM-dd")
    private static let dayTitleFmt = machine("MM-dd")

    static func date(_ epochMillis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(epochMillis) / 1000)
    }

    /// 时刻 HH:mm。
    static func clock(_ epochMillis: Int64) -> String {
        clockFmt.string(from: date(epochMillis))
    }

    /// 自然日键 yyyy-MM-dd（分组、检索、比较都用它）。
    static func dayKey(_ epochMillis: Int64) -> String {
        dayKeyFmt.string(from: date(epochMillis))
    }

    /// 短日期 MM-dd。
    static func dayShort(_ epochMillis: Int64) -> String {
        dayShortFmt.string(from: date(epochMillis))
    }

    /// 组头：今天 / 昨天 / MM-dd / **跨年时 yyyy-MM-dd**。
    ///
    /// 2026-11-01 修复：旧实现一律 `MM-dd`。而记录页会列出**跨年**的日志（锁端日志最多能读到
    /// 几十上百条，跨年是常态），于是「12-25」既可能是去年也可能是今年 —— 用户无法判断，
    /// 也无法在两个年份相同的月日之间做比较。非当年一律带年份。
    static func dayTitle(_ dayKey: String) -> String {
        let today = dayKeyFmt.string(from: Date())
        if dayKey == today { return "今天" }
        guard let d = dayKeyFmt.date(from: dayKey) else { return dayKey }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        if dayKeyFmt.string(from: yesterday) == dayKey { return "昨天" }
        // 与「今天」同一年 → MM-dd；否则 yyyy-MM-dd。
        let thisYear = calendar.component(.year, from: Date())
        let thatYear = calendar.component(.year, from: d)
        return thatYear == thisYear ? dayTitleFmt.string(from: d) : dayKey
    }

    /// 相对距今（「刚刚」「12 分钟前」「3 小时前」「2 天前」）。
    static func ago(_ epochMillis: Int64, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String {
        let delta = max(0, now - epochMillis)
        let mins = delta / 60_000
        if mins < 1 { return "刚刚" }
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        if days < 30 { return "\(days) 天前" }
        return dayShort(epochMillis)
    }
}
