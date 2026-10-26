// 包9 布防（cmd25）纯逻辑单测 —— 不依赖真机 BLE。
// 表驱动：三档 control 语义 / 时段五条校验 / 跨午夜 / 半秒换算 / 状态行文案。
//
// 为什么这些必须先测：布防是**双向**约定 —— 本地 DefendCfg 同时驱动
// ① 发给锁的 cmd25（半秒刻度）② 自动开锁的 F4 否决门（AutoOpenKit.defendActive，同一把尺）。
// 两处只要有一处换算口径不同，就会出现「锁端布防了、本机还在自动开」或反之，
// 而这两种错都不会崩、不会报错，只会静静地把门留着。
import XCTest
import Foundation
@testable import OfflineLock

final class DefendKitTests: XCTestCase {

    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let day0 = Date(timeIntervalSince1970: 1_767_868_800)   // 2026-01-08 00:00 UTC

    /// 半秒刻度 → Date（与 defendActive 的 startSec/endSec 同一把尺）
    private func t(_ halfSec: Int) -> Date { day0.addingTimeInterval(TimeInterval(halfSec) / 2.0) }

    // MARK: - control 语义

    /// 三档 rawValue 必须与 cmd25 的 control 字段一致；3 = readonly 本代不发，所以不在枚举里。
    func testModeRawValuesMatchProtocol() {
        XCTAssertEqual(DefendMode.off.rawValue, 0)
        XCTAssertEqual(DefendMode.once.rawValue, 1)
        XCTAssertEqual(DefendMode.period.rawValue, 2)
        XCTAssertEqual(DefendMode.allCases.count, 3, "readonly(3) 本代不发，不应出现在可选项里")
    }

    // MARK: - 半秒换算（唯一的换算出口）

    func testProtoSecRoundTrip() {
        let cases: [(sec: Int, proto: Int)] = [
            (0, 0), (1, 2), (59, 118), (60, 120),
            (22 * 3600, 158_400),          // 22:00
            (6 * 3600 + 60, 43_320),       // 01:00
            (86_400, 172_800),             // 24:00 = 满一天
        ]
        for c in cases {
            XCTAssertEqual(DefendKit.protoSec(c.sec), c.proto, "\(c.sec)s → 半秒刻度")
            XCTAssertEqual(DefendKit.secFromProto(c.proto), c.sec, "\(c.proto) 半秒 → 秒")
        }
    }

    /// 越界必须夹住，不能回绕（cmd25 的 start/end 是 4B LE，回绕会变成 2146 年那种值）
    func testProtoSecClampsOutOfRange() {
        XCTAssertEqual(DefendKit.protoSec(-5), 0, "负数夹到 0")
        XCTAssertEqual(DefendKit.protoSec(86_401), DefendKit.halfDay, "超一天夹到满一天")
    }

    // MARK: - 时段校验五条

    func testValidateTable() {
        // (mode, start, end, now 半秒刻度, 期望的拒绝语或 nil)
        let cases: [(DefendMode, Int, Int, Int, String?)] = [
            (.off, 0, 0, 0, nil),                                  // 撤防永远合法
            (.once, 0, 0, 0, nil),                                 // 不定期永远合法
            (.period, 22 * 3600, 7 * 3600, 12 * 3600, nil),        // 跨午夜，合法
            (.period, 8 * 3600, 18 * 3600, 12 * 3600, nil),        // 正常时段，合法
            (.period, 8 * 3600, 8 * 3600, 0, "结束时间不能等于开始时间"),
            (.period, 18 * 3600, 8 * 3600, 0, "结束时间必须大于开始时间"),   // 同日内 start > end 且非跨夜意图
            (.period, 0, 3 * 3600, 4 * 3600, "结束时间必须大于当前时间"),
            (.period, -1, 3600, 0, "开始时间不在一天之内"),
            (.period, 0, 86_401, 0, "结束时间不在一天之内"),
        ]
        for (i, c) in cases.enumerated() {
            let got = DefendKit.validate(mode: c.0,
                                         startSec: c.1,
                                         endSec: c.2,
                                         now: t(c.3))
            XCTAssertEqual(got, c.4, "case #\(i) \(c.0) \(c.1)–\(c.2)")
        }
    }

    /// 跨午夜：开始晚于结束是允许的（APK 的 page-defend 也是这个口径），
    /// 但「结束>开始」那条只在非跨夜意图下判定 —— 这里明确钉住 22:00–07:00 必须通过。
    func testCrossMidnightAccepted() {
        XCTAssertNil(DefendKit.validate(mode: .period,
                                        startSec: 22 * 3600,
                                        endSec: 7 * 3600,
                                        now: t(12 * 3600)))
    }

    // MARK: - 与 F4 否决门同尺

    /// 关键一致性：DefendKit 写下去的半秒值，喂给 AutoOpenKit.defendActive 必须得到
    /// 「时段内 = 否决、时段外 = 放行」。这是两个模块之间唯一的契约。
    func testWrittenConfigFeedsF4Gate() {
        // 22:00–07:00 跨夜
        let startProto = DefendKit.protoSec(22 * 3600)
        let endProto = DefendKit.protoSec(7 * 3600)
        // 23:00 → 时段内
        XCTAssertTrue(AutoOpenKit.defendActive(control: 2, startSec: startProto, endSec: endProto,
                                               now: t(23 * 3600 * 2), cal: utc))
        // 03:00 → 时段内（跨午夜后半段）
        XCTAssertTrue(AutoOpenKit.defendActive(control: 2, startSec: startProto, endSec: endProto,
                                               now: t(3 * 3600 * 2), cal: utc))
        // 12:00 → 时段外
        XCTAssertFalse(AutoOpenKit.defendActive(control: 2, startSec: startProto, endSec: endProto,
                                                now: t(12 * 3600 * 2), cal: utc))
        // 不定期布防（control=1）不参与 F4 时段否决 —— 它的语义是"一直布防"，
        // 由 DefendKit.isActive 判，不是由 defendActive 判。
        XCTAssertFalse(AutoOpenKit.defendActive(control: 1, startSec: 0, endSec: 0,
                                                now: t(12 * 3600 * 2), cal: utc))
    }

    // MARK: - 全天布防

    func testAllDay() {
        let cfg = DefendCfg(control: 2, startSec: 0, endSec: 0, at: 0)
        XCTAssertTrue(DefendKit.isAllDay(cfg), "start == end 在协议里表示整天，读侧必须 fail-closed 读成全天")
        // defendActive 同样把 start==end 读成全天（与 isAllDay 口径一致）
        XCTAssertTrue(AutoOpenKit.defendActive(control: 2, startSec: 0, endSec: 0, now: day0, cal: utc))
    }

    // MARK: - 状态行文案

    func testSummaryTable() {
        let now = t(12 * 3600 * 2)     // 12:00
        XCTAssertEqual(DefendKit.summary(nil, now: now), "当前无布防")
        XCTAssertEqual(DefendKit.summary(DefendCfg(control: 0, startSec: 0, endSec: 0, at: 0), now: now), "当前无布防")
        XCTAssertEqual(DefendKit.summary(DefendCfg(control: 1, startSec: 0, endSec: 0, at: 0), now: now), "不定期布防中")
        let allDay = DefendKit.summary(DefendCfg(control: 2, startSec: 0, endSec: 0, at: 0), now: now)
        XCTAssertTrue(allDay.contains("全天"), allDay)
        let outside = DefendKit.summary(DefendCfg(control: 2,
                                                  startSec: DefendKit.protoSec(22 * 3600),
                                                  endSec: DefendKit.protoSec(7 * 3600), at: 0), now: now)
        XCTAssertTrue(outside.contains("时段外"), outside)
        XCTAssertTrue(outside.contains("22:00"), outside)
        XCTAssertTrue(outside.contains("07:00"), outside)
    }

    func testIsActive() {
        let now = t(23 * 3600 * 2)     // 23:00
        XCTAssertFalse(DefendKit.isActive(nil, now: now))
        XCTAssertTrue(DefendKit.isActive(DefendCfg(control: 1, startSec: 0, endSec: 0, at: 0), now: now),
                      "不定期布防：isActive 恒真")
        XCTAssertTrue(DefendKit.isActive(DefendCfg(control: 2,
                                                   startSec: DefendKit.protoSec(22 * 3600),
                                                   endSec: DefendKit.protoSec(7 * 3600), at: 0), now: now))
    }

    // MARK: - 时间格式化

    func testHhmm() {
        XCTAssertEqual(DefendKit.hhmm(0), "00:00")
        XCTAssertEqual(DefendKit.hhmm(22 * 3600), "22:00")
        XCTAssertEqual(DefendKit.hhmm(7 * 3600 + 30 * 60), "07:30")
        XCTAssertEqual(DefendKit.hhmm(-1), "00:00", "负数夹住，不输出 -1:-1")
        XCTAssertEqual(DefendKit.hhmm(99_999), "00:00", "超一天夹到 24:00 的位置再格式化")
    }

    /// secondsOfDay 必须与 defendActive 内部的口径一致（都是本地时区的 h/m/s）
    func testSecondsOfDayMatchesGate() {
        let noon = t(12 * 3600 * 2)
        XCTAssertEqual(DefendKit.secondsOfDay(noon, cal: utc), 12 * 3600)
        // 与 AutoOpenKit 的判定对齐：12:00 正好落在 [8:00, 18:00) 内
        XCTAssertTrue(AutoOpenKit.defendActive(control: 2,
                                               startSec: DefendKit.protoSec(8 * 3600),
                                               endSec: DefendKit.protoSec(18 * 3600),
                                               now: noon, cal: utc))
    }
}
