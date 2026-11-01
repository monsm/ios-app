// 进程级复用的日期格式化器
//
// 为什么必须复用：
//   `DateFormatter()` 的初始化要做 locale / calendar / ICU 装配，量级 0.3–2 ms，
//   比一次 `string(from:)` 贵两三个数量级。本仓有多处**按记录循环**地建它 ——
//   最狠的一处是 `Attribution.classify`：它对「日志 × 临时码」的笛卡尔积调用 `ms()`，
//   而 `ms()` 每次新建 2 个 DateFormatter。100 条日志 × 20 条临时码 = 2000 次调用
//   ⇒ 4000 个 formatter，足以让记录页卡到秒级。
//
// 为什么用 `threadDictionary` 而不是 `static let`：
//   `DateFormatter` 不是 `Sendable`，在 Swift 6 语言模式下全局 `static let` 会被判
//   并发不安全。`Thread.current.threadDictionary` 是线程私有的，天然无竞态、无需加锁，
//   且键里带时区标识 —— 用户改时区后新键自然重建，不会拿到旧时区的缓存。
//
// 语义与原来逐处新建完全一致：同一 format / 同一 locale / 同一时区 ⇒ 同一输出。
import Foundation

enum DF {
    /// 取（或按需创建）当前线程的格式化器。
    /// - Parameters:
    ///   - format: 如 `"yyyy-MM-dd"`。
    ///   - timeZone: 传 nil = 跟随 `TimeZone.current`。
    ///   - locale: 默认 `en_US_POSIX`（本仓规范：日期格式必须钉公元历与固定 locale）。
    static func cached(_ format: String, timeZone: TimeZone? = nil, locale: String = "en_US_POSIX") -> DateFormatter {
        let tz = timeZone ?? TimeZone.current
        let key = "DF|" + format + "|" + tz.identifier + "|" + locale
        let dict = Thread.current.threadDictionary
        if let hit = dict[key] as? DateFormatter { return hit }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        // 2026-11-01 修复：**必须钉公历**。
        // `DateFormatter` 不设 `calendar` 时用的是 `Calendar.current` ——
        // 用户把系统历法切成佛历/民国历/农历，这里就会输出异 era 年份（2026 变 2569），
        // 而 `TimeFormat.machine` 早就钉了公历 ⇒ **同一个时刻在两处显示不同年份**。
        // `FormatterConsistencyTests` 之所以一直绿，是因为 CI 机器是公历：
        // 两边都输出公历，差异只在"用户改了历法"时才现形（那正是本仓 §10 反复强调的场景）。
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        f.timeZone = tz
        dict[key] = f
        return f
    }

    /// 只取 `yyyy-MM-dd HH:mm:ss`（本地时区）—— 最高频的一档，单独开一个名字让调用点更短。
    static var stamp: DateFormatter { cached("yyyy-MM-dd HH:mm:ss") }
    /// 同上但按 UTC 解析/格式化（JS 生态把本地串当 UTC 读，见 `Attribution.ms`）。
    static var stampUTC: DateFormatter { cached("yyyy-MM-dd HH:mm:ss", timeZone: TimeZone(identifier: "UTC")) }
    /// 只到分钟，UTC（兼容小程序/旧备份包里的 `"2026-01-05 08:00"`）。
    static var minuteUTC: DateFormatter { cached("yyyy-MM-dd HH:mm", timeZone: TimeZone(identifier: "UTC")) }
    /// 日 key（本地时区）。
    static var day: DateFormatter { cached("yyyy-MM-dd") }
    /// `MM-dd HH:mm`（本地时区）。
    static var shortDayTime: DateFormatter { cached("MM-dd HH:mm") }

    /// `DateFormatter.localizedString(from:dateStyle:.none,timeStyle:.medium)` 的缓存版。
    /// 那个**类方法每次调用都会新建一个 formatter**；本仓有几处在 body / BLE 日志行里调它，
    /// 设备页每次重算 body 都要白建一个。
    static func localTime(_ d: Date = Date()) -> String {
        let key = "DFLOCALTIME"
        let dict = Thread.current.threadDictionary
        if let f = dict[key] as? DateFormatter { return f.string(from: d) }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        dict[key] = f
        return f.string(from: d)
    }

    /// `dateStyle: .short, timeStyle: .short` 的缓存版（如「已验证于 26/10/29 18:00」）。
    static func localShort(_ d: Date) -> String { localCached("DFLOCALSHORT", d) { f in
        f.dateStyle = .short; f.timeStyle = .short
    } }
    /// `dateStyle: .medium, timeStyle: .none` 的缓存版（如「10月29日」）。
    static func localDate(_ d: Date) -> String { localCached("DFLOCALDATE", d) { f in
        f.dateStyle = .medium; f.timeStyle = .none
    } }
    private static func localCached(_ key: String, _ d: Date, _ cfg: (DateFormatter) -> Void) -> String {
        let dict = Thread.current.threadDictionary
        if let f = dict[key] as? DateFormatter { return f.string(from: d) }
        let f = DateFormatter()
        cfg(f)
        dict[key] = f
        return f.string(from: d)
    }

    /// ISO8601（不带小数秒）。`ISO8601DateFormatter` 初始化同样昂贵。
    static func iso(_ fractional: Bool = false) -> ISO8601DateFormatter {
        let key = "DFISO|" + (fractional ? "frac" : "plain")
        let dict = Thread.current.threadDictionary
        if let hit = dict[key] as? ISO8601DateFormatter { return hit }
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        dict[key] = f
        return f
    }
}
