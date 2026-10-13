// TimeFormat 的单元测试 (647 制式 / 651 秒 / 665 区间精简)。
//
// 为什么要写: 这三条全是**纯字符串口径**，正是能在 CI 之外被证伪的那类逻辑。
// 但要说清边界: 本仓没有 iOS 模拟器，`xcodebuild build-for-testing` 只编译不执行 ⇒
// 这份测试目前的作用是"让编译器核对签名与可编性"，真正跑起来要有模拟器的机器
// (见 docs/VERIFY-CHECKLIST.md 第 0 节)。纯函数另有 tools/shadowdiff.js 的跨语言影子对拍，
// 那个现在就能跑，但只覆盖 vendor JS 也有的原语 —— TimeFormat 是 iOS 侧新增，没有 JS 权威源。
import XCTest
@testable import OfflineLock

final class TimeFormatTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 测试期间回到"跟随系统 + 不带秒"，避免上一条用例的偏好漏进来 (Store 是真 UserDefaults)
        DB.store.set(TimeFormat.styleKey, "")
        DB.store.set(TimeFormat.secsKey, false)
    }

    // 647: 12/24 制只改小时写法，分钟不许被动过
    func testClockRespectsStyle() {
        DB.store.set(TimeFormat.styleKey, "24")
        XCTAssertEqual(TimeFormat.clock("2026-10-07 09:05:12"), "2026-10-07 09:05")
        DB.store.set(TimeFormat.styleKey, "12")
        XCTAssertEqual(TimeFormat.clock("2026-10-07 15:05:12"), "2026-10-07 3:05 下午")
    }

    // 651: 秒位只在**开了设置且源串真有秒**时出现；缺位不补 ":00"
    func testSecondsOnlyWhenPresent() {
        DB.store.set(TimeFormat.styleKey, "24")
        XCTAssertEqual(TimeFormat.clock("2026-10-07 09:05"), "2026-10-07 09:05")
        DB.store.set(TimeFormat.secsKey, true)
        XCTAssertEqual(TimeFormat.clock("2026-10-07 09:05"), "2026-10-07 09:05")     // 源串没秒 ⇒ 不假装
        XCTAssertEqual(TimeFormat.clock("2026-10-07 09:05:41"), "2026-10-07 09:05:41")
    }

    // 认不出时刻段时**原样返回**，不猜 (日志行、日期串都会路过这里)
    func testClockLeavesNonTimeAlone() {
        XCTAssertEqual(TimeFormat.clock("2026-10-07"), "2026-10-07")
        XCTAssertEqual(TimeFormat.clock("今天"), "今天")
    }

    // 665: 同年省年份、同月只写一次日
    func testRangeAbbreviation() {
        XCTAssertEqual(TimeFormat.range(fromDay: "2026-10-01", toDay: "2026-10-07"), "10月1日–7日")
        XCTAssertEqual(TimeFormat.range(fromDay: "2026-10-01", toDay: "2026-11-07"), "10月1日–11月7日")
        XCTAssertEqual(TimeFormat.range(fromDay: "2025-12-30", toDay: "2026-01-02"), "2025年12月30日–2026年1月2日")
        // 畸形输入不许崩、也不许装作精简过
        XCTAssertEqual(TimeFormat.range(fromDay: "abc", toDay: "2026-01-02"), "abc–2026-01-02")
    }
}
