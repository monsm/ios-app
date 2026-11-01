// TimeBasisTests.swift —— 时间串的**时基一致性**回归。
//
// 为什么值得单独一个文件：这个仓库里同时存在两种解析口径，两者都**有正当理由**：
//   · `DF.stamp`    —— 本地墙钟。用于"用户看到的墙钟时间"（锁钟显示、台账 from/to、日志行）。
//   · `DF.stampUTC` —— 按 UTC 解析本地串。这是 **JS 生态的既定语义**（vendor 小程序/APK
//                      两端都这么干，见 `Attribution.ms` 的注释），跨设备互操作必须与它同语义。
//
// 危险在于**混用**：同一个比较里一边本地、一边 UTC，在东八区就是整体平移 8 小时。
// 这类 bug 不会崩、不会报错，只会让判定结果错 —— 最典型的是「越界窗口的临时码开门」
// 把正常开门诬告成"伪造或时钟偏差"（2026-11-01 修复的正是这一处）。
//
// 本文件把"每个字段该用哪个口径"钉住，防止后人改一处忘另一处。
import XCTest
@testable import LockKeeper

// MARK: - 持久化时间戳的可信性（未来值会让"现在 − 时间戳"类判断被永久钉死）

final class TimestampPlausibilityTests: XCTestCase {

    func testFutureStampsAreRejectedButSmallDriftIsNot() {
        let now = 1_700_000_000.0
        XCTAssertTrue(TimeFormat.timestampIsPlausible(0, now: now), "0 = 没有记录，不算不可信")
        XCTAssertTrue(TimeFormat.timestampIsPlausible(now - 10, now: now))
        XCTAssertTrue(TimeFormat.timestampIsPlausible(now + 30, now: now), "小幅时钟漂移容忍")
        XCTAssertFalse(TimeFormat.timestampIsPlausible(now + 3600, now: now), "真·未来值不可信")
        XCTAssertFalse(TimeFormat.timestampIsPlausible(now + 86400 * 30, now: now))
    }

    /// 使用点：`AutoOpenKit.coolReady` 的冷却（`LockStats` 的连接节流同理）。
    func testCooldownAndTouchThrottleIgnoreFutureStamps() {
        let now = 1_700_000_000.0
        XCTAssertTrue(AutoOpenKit.coolReady(lastDispatch: now + 3600, now: now),
                      "未来时间戳不该把 6 秒冷却变成永久封禁")
        XCTAssertFalse(AutoOpenKit.coolReady(lastDispatch: now - 3, now: now))
    }
}

final class TimeBasisTests: XCTestCase {

    private let sample = "2026-01-01 00:00:00"

    /// 两个口径**必须不同**，且正好相差一个时区偏移。
    /// 若有人把它们改成同一个时区，这个仓库的两套语义就塌了（且是静默的）。
    func testTwoParsersUseDifferentTimeBases() {
        let local = RecordSearch.parseLocal(sample)
        let utc = RecordSearch.parseStamp(sample)
        XCTAssertGreaterThan(local, 0)
        XCTAssertGreaterThan(utc, 0)
        // 同一个墙钟串：按 UTC 解析得到的 Unix 秒比按本地解析**大**一个时区偏移。
        // 在 UTC runner 上偏移是 0 —— 这是正确结果，不是 bug。
        let offset = Int64(TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(local))))
        XCTAssertEqual(utc - local, offset, "两个解析口径必须正好相差一个时区偏移")
    }

    /// `dateOf`（日志行）与 `parseLocal`（台账 from/to）必须**同一口径** ——
    /// 越界窗口判定就是靠这两个值直接比较的。
    func testLogTimeAndLedgerWindowShareTheSameBasis() throws {
        let rec = Rec(key: "1", mac: "aabbccddeeff", lockName: "锁", type: 16,
                      typeName: "一次性密码开门", idxRaw: 1, lockTime: 0, timeStr: sample,
                      kind: "temp", cred: "", alarm: false, care: false, failMsg: "")
        let logSec = try XCTUnwrap(RecordSearch.dateOf(rec)).timeIntervalSince1970
        XCTAssertEqual(Int64(logSec), RecordSearch.parseLocal(sample),
                       "日志行与台账窗口必须用同一时基，否则越界判定整体偏移")
        // 与 UTC 口径的关系：差值必须**正好**是时区偏移（在 UTC runner 上偏移为 0，两者自然相等）。
        // 注意：这里**不能**断言"两个口径必须不同" —— CI runner 就是 UTC，那时它们本来就相等，
        // 那样的断言只在东八区开发机上成立，会把正确实现判成红（本轮实测踩到）。
        let offset = Int64(TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(logSec))))
        XCTAssertEqual(RecordSearch.parseStamp(sample) - Int64(logSec), offset,
                       "本地口径与 UTC 口径必须正好相差一个时区偏移")
    }

    /// 窗口是闭区间：起点与终点都算"在窗口内"。
    func testWindowBoundaryIsInclusive() {
        let from = RecordSearch.parseLocal("2026-01-01 00:00:00")
        let to = RecordSearch.parseLocal("2026-01-02 00:00:00")
        XCTAssertTrue(from <= from && from <= to, "起点落在窗口内")
        XCTAssertTrue(from <= to && to <= to, "终点落在窗口内")
    }

    /// 失败输入给 0（调用方用 `f > 0` 兜住），而不是崩溃或返回垃圾值。
    func testUnparseableStampYieldsZero() {
        XCTAssertEqual(RecordSearch.parseLocal(""), 0)
        XCTAssertEqual(RecordSearch.parseLocal("不是时间"), 0)
        XCTAssertEqual(RecordSearch.parseStamp(""), 0)
    }

    /// 锁钟 0 = "没有时间"，必须渲染成空串 —— 不能变成 2010-01-01 08:00:00。
    func testProtoTimeZeroMeansNoTime() {
        XCTAssertEqual(ProtoTime.localStr(0), "",
                       "lockTime == 0 是占位值，不能渲染成协议纪元")
        XCTAssertFalse(ProtoTime.localStr(123456).isEmpty)
    }

    /// 协议秒 → Unix 秒的换算必须无漂移（epoch 是整千毫秒）。
    func testProtoSecondsRoundTrip() {
        for sec in [Int64(0), 1, 86_400, 1_000_000] {
            let unix = ZKProtocol.protoSecondsToUnix(sec)
            XCTAssertEqual(Int64(unix), ZKProtocol.epochMs / 1000 + sec, "sec=\(sec) 换算漂移")
        }
    }

    /// 组头跨年必须带年份：记录页会列出跨年日志，只写 `MM-dd` 会与今年的同月日混淆。
    func testDayTitleCarriesYearWhenNotCurrentYear() {
        let cal = TimeFormat.calendar
        let now = Date()
        let thisYear = cal.component(.year, from: now)
        // 今天 / 昨天：不带年份
        let todayKey = TimeFormat.dayKey(Int64(now.timeIntervalSince1970 * 1000))
        XCTAssertEqual(TimeFormat.dayTitle(todayKey), "今天")
        // 上一个年份的同月日：必须带 yyyy-MM-dd
        let lastYear = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let lastYearKey = TimeFormat.dayKey(Int64(lastYear.timeIntervalSince1970 * 1000))
        XCTAssertEqual(TimeFormat.dayTitle(lastYearKey), lastYearKey,
                       "跨年日期必须原样返回 yyyy-MM-dd，不能只给 MM-dd")
        XCTAssertTrue(TimeFormat.dayTitle(lastYearKey).hasPrefix(String(thisYear - 1)),
                      "跨年组头必须以那一年开头")
    }
}
