// Motion.swift —— 动效的第二套词汇（第一套是 T.M.settle / T.M.snap）。
//
// 纪律：
//   · 只动 opacity / offset / scale / blur —— 不动布局（不 animate frame）；
//   · 入场按 index 延迟，形成「从下往上依次亮起」的节奏，而不是整页一起闪；
//   · 「减少动态效果」时全部退化成直接出现；
//   · 动效是**状态反馈**，不是装饰：每一次出现都对应一件刚发生的事。
import SwiftUI

enum Motion {
    /// 入场：稍慢、略带过冲（0.55s / 0.86）。
    static let reveal = Animation.spring(response: 0.55, dampingFraction: 0.86)
    /// 小范围位移：快而稳（0.38s / 0.9）。
    static let glide = Animation.spring(response: 0.38, dampingFraction: 0.9)
    /// 页面级切换：沿用设计令牌里的 settle。
    static let settle = T.M.settle
    /// 按压回弹：沿用 snap。
    static let snap = T.M.snap
}

// MARK: - 入场

private struct Entrance: ViewModifier {
    var index: Int
    var rise: CGFloat
    var delayStep: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : rise)
            .scaleEffect(shown ? 1 : 0.985, anchor: .top)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(Motion.reveal.delay(Double(index) * delayStep)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// 入场：淡入 + 轻微上浮 + 极小缩放。`index` 决定延迟（同屏依次出现）。
    func entrance(_ index: Int, rise: CGFloat = 14, delayStep: Double = 0.055) -> some View {
        modifier(Entrance(index: index, rise: rise, delayStep: delayStep))
    }
}

// MARK: - 滚动视差

extension View {
    /// 滚动视差：元素滚到边缘时轻微缩小、变淡、虚化。
    ///
    /// 只在**视觉层**做（scale / opacity / blur），不改变滚动位置与命中区。
    func scrollParallax(depth: CGFloat = 0.93) -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : depth, anchor: .top)
                .opacity(phase.isIdentity ? 1 : 0.88)
                .blur(radius: phase.isIdentity ? 0 : 1.4)
        }
    }
}

// MARK: - 错误抖动

/// 输入错误时的横向抖动（配一次轻触觉，不用红字训人）。
struct ShakeEffect: GeometryEffect {
    /// 0 → 1 走完一次抖动；再触发时 +1。
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = sin(animatableData * .pi * 6) * 7
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

extension View {
    /// 抖动一次。`count` 是外部持有的计数器（每次 +1 抖一下）。
    func shake(_ count: CGFloat, enabled: Bool = true) -> some View {
        modifier(ShakeEffect(animatableData: enabled ? count : 0))
    }
}

// MARK: - 规则线生长

private struct RuleReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: grown ? 1 : 0.001, y: 1, anchor: .leading)
            .opacity(grown ? 1 : 0)
            .onAppear {
                if reduceMotion { grown = true; return }
                withAnimation(Motion.reveal.delay(0.12)) { grown = true }
            }
    }
}

extension View {
    /// 细线从左往右长出来（章节头、分隔线用）。
    func ruleReveal() -> some View { modifier(RuleReveal()) }
}

// MARK: - 颗粒

/// 极轻的颗粒（纯矢量：确定性伪随机点，零位图）。
///
/// 玻璃与渐变在真机上最怕「太干净」—— 一层几乎看不见的颗粒会把它们压回纸的质感。
struct GrainOverlay: View {
    var opacity: Double = 0.05
    /// 颗粒密度（点数）。默认 260 在 6.7 吋屏上是「看不见但摸得到」的量。
    var count: Int = 260

    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 0x5EED_2026)
            for _ in 0 ..< count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let r = CGFloat(rng.next()) * 0.9 + 0.35
                let a = rng.next()
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(.white.opacity(opacity * (0.3 + 0.7 * a)))
                )
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 确定性伪随机（线性同余）：同一块屏幕上每次重画的颗粒位置一致，不会闪。
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let v = (state >> 33) & 0xFFFF_FFFF
        return Double(v) / Double(0xFFFF_FFFF)
    }
}
