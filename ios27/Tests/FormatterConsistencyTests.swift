// FormatterConsistencyTests.swift —— 两个日期工厂必须**产出同一结果**。
//
// 这个仓库有两套日期格式化入口，都在用，都有正当理由：
//   · `DF.cached`    —— 按 (format, timezone, locale) 缓存的通用工厂（Engine 层用）。
//   · `TimeFormat`   —— 时间口径的唯一出口（UI 层 90 处用），钉公历 + POSIX + 本地时区。
//
// 危险：两套各写一遍格式串，**改一处忘另一处**就会出现"同一个时刻在两页显示不同"。
// 这类不一致不会崩、不会报错，只在用户眼里显得"App 算错了"。
// 本文件把两条路径的产出钉在一起。
import XCTest
@testable import LockKeeper

final class FormatterConsistencyTests: XCTestCase {

    /// 覆盖常见时刻 + 边界（闰年 2 月 29、跨年零点、月末）。
    private let samples: [Int64] = [
        0,                              // 1970 epoch
        1_767_225_600_000,              // 2026-01-01 00:00:00 UTC
        1_709_164_800_000,              // 2024-02-29（闰日）
        1_735_689_600_000,              // 2025-01-01 00:00:00 UTC
        2_147_483_647_000,              // 2038 边界附近
    ]

    /// HH:mm 必须一致。
    func testClockFormatAgrees() {
        for ms in samples {
            let viaTimeFormat = TimeFormat.clock(ms)
            let viaDF = DF.cached("HH:mm").string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
            XCTAssertEqual(viaTimeFormat, viaDF, "HH:mm 在两个工厂间不一致（ms=\(ms)）")
        }
    }

    /// 自然日键 yyyy-MM-dd 必须一致 —— 分组、检索、比较全靠它。
    func testDayKeyFormatAgrees() {
        for ms in samples {
            let viaTimeFormat = TimeFormat.dayKey(ms)
            let viaDF = DF.cached("yyyy-MM-dd").string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
            XCTAssertEqual(viaTimeFormat, viaDF, "dayKey 不一致（ms=\(ms)）—— 会让同一天的记录分到两组")
        }
    }

    /// 短日期 MM-dd 必须一致。
    func testDayShortFormatAgrees() {
        for ms in samples {
            let viaTimeFormat = TimeFormat.dayShort(ms)
            let viaDF = DF.cached("MM-dd").string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
            XCTAssertEqual(viaTimeFormat, viaDF, "dayShort 不一致（ms=\(ms)）")
        }
    }

    /// `TimeFormat.calendar` 必须是公历 —— 用户把系统历法切成佛历/农历时，
    /// `Calendar.current` 会算出异 era 年份（2026 变 2569）。
    func testTimeFormatCalendarIsGregorian() {
        XCTAssertEqual(TimeFormat.calendar.identifier, .gregorian,
                       "时间口径必须钉公历，不能用 Calendar.current")
        // 直接验算：公历下 2026 年就是 2026，不会变成佛历 2569。
        let comps = TimeFormat.calendar.dateComponents([.year], from: Date(timeIntervalSince1970: 1_767_225_600))
        XCTAssertEqual(comps.year, 2026, "公历年份算错（历法被系统设置带跑）")
    }

    /// 毫秒 → 秒的换算不能丢精度或错位（`TimeFormat.date` 是唯一入口）。
    func testEpochMillisToDate() {
        for ms in samples {
            XCTAssertEqual(TimeFormat.date(ms).timeIntervalSince1970, Double(ms) / 1000, accuracy: 0.001,
                           "毫秒→秒换算错位（ms=\(ms)）")
        }
        // 单位混用的后果要**具体**验算，不能凭直觉写阈值。
        // 把 1_767_225_600 秒当成毫秒喂进去 ⇒ 得到 1_767_225.6 秒 ≈ 1970-01-21，
        // 也就是"时间塌回 1970 年代"；而正确喂 1_767_225_600_000 毫秒才是 2026-01-01。
        let fedSecondsAsMs = TimeFormat.date(1_767_225_600).timeIntervalSince1970
        XCTAssertLessThan(fedSecondsAsMs, 1_767_225_600, "单位混用必然得到一个更小的时刻")
        // 注意：dayKey 用**本地时区**（这是对的，用户看的是本地日历）。
        // 所以这里不能断言字面 "2026-01-01" —— 在 UTC+8 上那是 2026-01-01 08:00，
        // 在 UTC-5 上则是 2025-12-31 19:00。断言**年份**即可，跨时区都成立。
        XCTAssertTrue(TimeFormat.dayKey(1_767_225_600_000).hasPrefix("2026")
                      || TimeFormat.dayKey(1_767_225_600_000).hasPrefix("2025"),
                      "2026-01-01T00:00Z 在本地日历上应落在 2025 末或 2026 初")
        // 混用后年份塌到 1970 年代 —— 用同一个 dayKey 出口证明，而不是拍一个阈值。
        XCTAssertTrue(TimeFormat.dayKey(1_767_225_600).hasPrefix("1970"),
                      "秒当毫秒 ⇒ 日期塌回 1970 年代")
    }
}
