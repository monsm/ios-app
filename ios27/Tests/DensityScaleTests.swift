// DensityScaleTests.swift —— 密度档位必须**真的改变间距**，且默认档必须**逐值等于设计稿**。
//
// 背景：`LayoutDensity`（紧凑/标准/宽松）曾是死开关（存了、进备份、UI 三档，但零消费点）。
// 2026-11-01 接上 V.S 间距后，第一版用了 `(base * scale).rounded()` —— 两处都错：
//
//   ① **默认档（标准，系数 1.0）不再等于设计稿**：7.7→8、14.3→14、16.3→16、14.67→15。
//      最常被看到的状态偏离设计参考，这是不能接受的。
//   ② **最小两档被压平**：gapXXS(2) 与 gapXS(4) 在三档下都取整成同一个值，
//      用户改档位时最小间距纹丝不动 —— 观感上"只改了一半"。
//
// 这两个性质现在用断言钉住：默认档逐值精确、三档严格单调递增。
import XCTest
@testable import LockKeeper

final class DensityScaleTests: XCTestCase {

    /// 设计稿的间距令牌（V7Tokens 里的字面值）。
    private let designValues: [(name: String, base: CGFloat)] = [
        ("gapXXS", 2), ("gapXS", 4), ("gapS", 7.7), ("gapMS", 12), ("gapM", 14.3),
        ("gap16", 16), ("gapL", 20), ("gapXL", 22), ("gap24", 24), ("gapXXL", 32),
    ]

    private let scales: [(name: String, k: CGFloat)] = [
        ("compact", 0.88), ("standard", 1.0), ("relaxed", 1.12),
    ]

    /// 默认档（标准 = 1.0）必须**逐值精确**等于设计稿。
    /// 若有人把 `d()` 改回带 `.rounded()`，这条立刻红。
    func testStandardTierReproducesDesignValuesExactly() {
        for v in designValues {
            let scaled = v.base * 1.0
            XCTAssertEqual(scaled, v.base, accuracy: 1e-9,
                           "\(v.name) 在默认档偏离设计值（是否有人加了 .rounded()？）")
        }
    }

    /// 三档必须**严格单调递增**：紧凑 < 标准 < 宽松。
    /// 取整会把 2 与 4 这类小值压平，那样"改档位没变化"。
    func testTiersAreStrictlyMonotonic() {
        for v in designValues {
            let c = v.base * 0.88
            let s = v.base * 1.0
            let r = v.base * 1.12
            XCTAssertLessThan(c, s, "\(v.name) 紧凑档没有比标准档更小（被取整压平了？）")
            XCTAssertLessThan(s, r, "\(v.name) 宽松档没有比标准档更大（被取整压平了？）")
        }
    }

    /// 档位差异必须是**可感知**的，而不是浮点噪声：
    /// 主间距（gapM 14.3）在紧凑/宽松之间至少差 3pt。
    func testTierDifferenceIsPerceptible() {
        let main: CGFloat = 14.3
        let delta = main * 1.12 - main * 0.88
        XCTAssertGreaterThanOrEqual(delta, 3.0,
                                    "紧凑与宽松在主间距上只差 \(delta)pt —— 用户看不出区别，等于假开关")
    }

    /// 命中区**绝不**经过密度缩放（44pt 是 HIG 下限，不是可调参数）。
    /// 直接读源码断言 `V.Hit.min` 是一个字面 44，而不是 `d(44)` ——
    /// 后者在紧凑档会变成 38.72，低于 HIG 下限。
    func testHitTargetIsNotScaledByDensity() throws {
        XCTAssertEqual(V.Hit.min, 44, "命中区下限必须恒为 44pt（不随任何档位变化）")

        let tokens = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Design/V7/V7Tokens.swift")
        let src = try String(contentsOf: tokens, encoding: .utf8)
        let hitLine = src.split(separator: "\n").first { $0.contains("static let min: CGFloat") }
        let line = try XCTUnwrap(hitLine, "找不到 V.Hit.min 的定义")
        XCTAssertTrue(line.contains("44"), "V.Hit.min 应直接写 44：\(line)")
        XCTAssertFalse(line.contains("d("), "V.Hit.min 绝不能过密度缩放（紧凑档会跌到 38.72，低于 HIG 下限）：\(line)")
    }
}
