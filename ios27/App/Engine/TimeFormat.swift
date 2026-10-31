// TimeFormat.swift —— 时间口径的唯一出口。
//
// 纪律：日期一律走 Gregorian 日历（用户历法切成佛历/农历时直接取 Calendar.current
// 会算出异 era 年份）；机器面格式钉 en_US_POSIX；UTC epoch 秒/毫秒不混用。
import Foundation

enum TimeFormat {
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

    /// 组头：今天 / 昨天 / MM-dd。
    static func dayTitle(_ dayKey: String) -> String {
        let today = dayKeyFmt.string(from: Date())
        if dayKey == today { return "今天" }
        guard let d = dayKeyFmt.date(from: dayKey) else { return dayKey }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        if dayKeyFmt.string(from: yesterday) == dayKey { return "昨天" }
        return dayTitleFmt.string(from: d)
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
