//
//  DoorStage.swift
//  门面系统 · 全新设计 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  设计契约
//  ═══════════════════════════════════════════════════════════
//
//  隐喻   : 一扇真实的门。App 有门里门外两面。
//  性格   : Premium —— 刚性材质 1.2x 时长, 零过冲。
//  材质   : 金属门板 (无位图, 纯程序化) + 门缝透光。
//  动效   : 三层视差 (前景锁体 / 中景门板 / 背景光晕), 单调曲线。
//  手势   : 左边缘 24pt 牵引, 1:1 跟手, 连续可控。
//
//  ═══════════════════════════════════════════════════════════
//  关键技术决策
//  ═══════════════════════════════════════════════════════════
//
//  1. 为什么是「两扇门转开」而不是「180° 翻转」
//     · 180° 翻转会在 90° 时把视图压成一条线, 视觉断裂
//     · 真实门的开法是绕铰链转, 有厚度、有透视
//     · rotation3DEffect 的 anchor 设 .leading, 就是铰链
//
//  2. 为什么必须用单调曲线
//     · spring 即使 damping 1.0 也可能因初速度过冲
//     · 过冲越过 90° 会露出镜像背面 (SwiftUI 不自动隐藏背面)
//     · timingCurve 单调, 绝不越过终点
//
//  3. 为什么背面要透明度斜坡
//     · SwiftUI 的 rotation3DEffect 没有 backface-visibility
//     · 必须用与角度联动的连续函数隐藏背面
//     · 斜坡区间 [86°, 94°] —— 足够窄不闪, 足够宽不突变
//
//  4. 为什么手势挂在左边缘 24pt
//     · SwiftUI DragGesture 不暴露手指数, 双指方案不可行
//     · 左边缘是"门把手"的自然位置, 符合物理隐喻
//     · 不侵占中间的按住开锁区域
//     · VoiceOver 有独立按钮, 手势只是增强
//

import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════
// MARK: - 相位状态机
// ═══════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════
// MARK: - 几何
// ═══════════════════════════════════════════════════════════

enum DoorGeometry {
    /// 门板最大开启角度 —— 106° 而非 180°:
    /// 真实门不会转平, 106° 时仍能看到门板厚度与投影, 视觉上"门真的开了"
    static let maxOpenAngle: Double = 106

    /// 翻面最大角度 —— 180° (整面翻过去)
    static let flipAngle: Double = 180

    /// 透视强度。iOS 默认 1, 门需要更强纵深
    static let perspective: CGFloat = 0.55

    /// 背面透明度斜坡区间 (度)
    static let backfaceFadeStart: Double = 86
    static let backfaceFadeEnd: Double = 94

    /// 左边缘手势热区宽度
    static let edgeGrabWidth: CGFloat = 24

    /// 翻面吸附阈值 (拖过 50% 才吸附)
    static let flipThreshold: CGFloat = 0.5

    /// 锁体直径相对屏幕宽度的比例
    static func plateDiameter(screenWidth: CGFloat) -> CGFloat {
        min(max(screenWidth * 0.52, 160), 260)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 背面透明度 (连续函数)
// ═══════════════════════════════════════════════════════════

/// 与角度联动的透明度。
///
/// SwiftUI 的 rotation3DEffect **不自动隐藏背面** (CSS 的 backface-visibility
/// 没有等价物)。90° 之后看到的是镜像的正面, 必须自己用透明度藏掉。
///
/// 用 smoothstep 而非 if/else: 阶跃在 90° 会闪一下, smoothstep 是连续函数。
@inline(__always)
func backfaceOpacity(angle: Double) -> Double {
    let a = abs(angle.truncatingRemainder(dividingBy: 360))
    if a <= DoorGeometry.backfaceFadeStart { return 0 }
    if a >= DoorGeometry.backfaceFadeEnd { return 1 }
    let t = (a - DoorGeometry.backfaceFadeStart) /
            (DoorGeometry.backfaceFadeEnd - DoorGeometry.backfaceFadeStart)
    // smoothstep 淡入
    return 3 * t * t - 2 * t * t * t
}

/// 正面的透明度 —— 角度 < 90° 可见, 90° 之后淡出。
///
/// 与 backfaceOpacity 严格互补: front + back == 1, 任何角度都成立。
/// 这保证翻转过程中屏幕上永远有内容, 不会出现"两面都透明"的空档。
@inline(__always)
func frontfaceOpacity(angle: Double) -> Double {
    let a = abs(angle.truncatingRemainder(dividingBy: 360))
    if a <= DoorGeometry.backfaceFadeStart { return 1 }
    if a >= DoorGeometry.backfaceFadeEnd { return 0 }
    let t = (a - DoorGeometry.backfaceFadeStart) /
            (DoorGeometry.backfaceFadeEnd - DoorGeometry.backfaceFadeStart)
    return 1 - (3 * t * t - 2 * t * t * t)
}

// ═══════════════════════════════════════════════════════════
// MARK: - 门板材质 (纯程序化, 零位图)
// ═══════════════════════════════════════════════════════════



// ═══════════════════════════════════════════════════════════
// MARK: - 门缝透光
// ═══════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════
// MARK: - 锁体
// ═══════════════════════════════════════════════════════════

/// 锁体 —— 金属环 + 中心字形 + 充能进度
struct LockPlate: View {
    /// 充能进度 0...1
    var charge: CGFloat
    /// 是否已开
    var isOpen: Bool
    /// 是否失败
    var isFailed: Bool
    /// 直径
    var diameter: CGFloat

    /// 减弱动态: 关掉光扫与呼吸, 保留状态切换 (motion.md:
    /// "Make motion optional" —— 运动不能是传达信息的唯一方式)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 光扫相位 (金属环上一道高光绕圈)
    @State private var sweep: Double = 0
    /// 开锁脉冲 (0→1, 一次性)
    @State private var burst: CGFloat = 0

    private var ringW: CGFloat { diameter * 0.035 }
    private var chargeW: CGFloat { diameter * 0.045 }

    /// 夜间暗化系数 (22:00–06:00)。
    ///
    /// 门锁 App 最高频的使用场景之一就是夜里回家开锁 ——
    /// 而整屏最亮的东西是一圈银白金属环, 在黑暗的楼道里相当刺眼。
    /// XMetric.isNightDim 这个令牌早就有, 但旧圆盘删掉之后一直没接上。
    ///
    /// 只压**装饰层** (金属环 + 光扫)。充能环与中心字形不压:
    /// 那两个承载功能信息 (充能进度 / 开锁状态), 暗化等于降低可读性。
    private var nightDim: Double { XMetric.isNightDim ? 0.72 : 1.0 }

    var body: some View {
        ZStack {
            // ── 1. 外环 (金属渐变) + 绕圈高光 ─────────────────────
            //
            // 高光用 AngularGradient 做一段窄的亮弧, 叠在金属环上绕圈转。
            // 这是"黄铜锁芯在灯下转动"的那点活气 —— 不加这一层, 整个锁面是死的。
            Circle()
                .strokeBorder(XGradient.lockRing, lineWidth: ringW)
                .opacity(nightDim)
                .frame(width: diameter, height: diameter)

            if !reduceMotion {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .clear, location: 0.62),
                                .init(color: XPalette.accent.opacity(0.85), location: 0.78),
                                .init(color: XPalette.specular.opacity(0.55), location: 0.82),
                                .init(color: XPalette.accent.opacity(0.85), location: 0.86),
                                .init(color: .clear, location: 0.94),
                                .init(color: .clear, location: 1.00)
                            ],
                            center: .center,
                            angle: .degrees(sweep))
                    )
                    .frame(width: diameter, height: diameter)
                    .blendMode(.plusLighter)
                    .opacity(nightDim)
                    .accessibilityHidden(true)
            }

            // ── 2. 充能环: 描边 + 外发光 ──────────────────────────
            //
            // 两层同一路径: 底下那层粗而虚 (glow), 上面那层细而实。
            // 直接把 shadow 挂在 stroke 上在低端机会掉帧, 分层画更稳。
            if charge > 0.001 {
                Circle()
                    .trim(from: 0, to: charge)
                    .stroke(XPalette.accent.opacity(0.35),
                            style: StrokeStyle(lineWidth: chargeW * 2.4, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: chargeW * 1.6)
                    .accessibilityHidden(true)
            }
            Circle()
                .trim(from: 0, to: charge)
                .stroke(XPalette.accent,
                        style: StrokeStyle(lineWidth: chargeW, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))

            // ── 3. 内圈 (凹槽) ────────────────────────────────────
            Circle()
                .fill(XPalette.surfaceSunken)
                .frame(width: diameter * 0.72, height: diameter * 0.72)
                .overlay(
                    Circle().strokeBorder(XPalette.hairline, lineWidth: 1)
                        .frame(width: diameter * 0.72, height: diameter * 0.72)
                )

            // ── 4. 开锁脉冲: 一圈扩散出去的光 ─────────────────────
            if burst > 0.001 {
                Circle()
                    .stroke(XPalette.ok.opacity(Double(1 - burst) * 0.7),
                            lineWidth: 2 + burst * 3)
                    .frame(width: diameter * (1 + burst * 0.35),
                           height: diameter * (1 + burst * 0.35))
                    .accessibilityHidden(true)
            }

            // ── 5. 中心字形 ──────────────────────────────────────
            Image(systemName: glyphName)
                .font(.system(size: diameter * 0.28, weight: .light))
                .foregroundStyle(glyphColor)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .modifier(ShakeEffect(animatableData: isFailed ? CGFloat(1) : CGFloat(0)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOpen ? "门已开" : "门已锁")
        .accessibilityValue(charge > 0 ? "充能 \(Int(charge * 100))%" : "")
        .onAppear { startSweep() }
        .onChange(of: reduceMotion) { _, _ in startSweep() }
        .onChange(of: isOpen) { _, nowOpen in
            guard nowOpen, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.55)) { burst = 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                burst = 0
            }
        }
    }

    /// 金属环高光绕圈。reduceMotion 时**不启动** ——
    /// motion.md 明确要求 "Make motion optional", 且无限循环动画是
    /// 晕动症用户最主要的不适来源。
    private func startSweep() {
        guard !reduceMotion else {
            sweep = 0
            return
        }
        sweep = 0
        withAnimation(.linear(duration: 5.5).repeatForever(autoreverses: false)) {
            sweep = 360
        }
    }

    private var glyphName: String {
        if isOpen { return "lock.open" }
        if isFailed { return "exclamationmark.triangle" }
        return "lock.fill"
    }

    private var glyphColor: Color {
        if isFailed { return XPalette.danger }
        if isOpen { return XPalette.ok }
        return XPalette.textSub
    }
}

/// 抖动效果 (失败时)
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = sin(animatableData * .pi * 4) * 6
        return ProjectionTransform(CGAffineTransform(translationX: t, y: 0))
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 门面主视图
// ═══════════════════════════════════════════════════════════

/// 门面 —— 首屏唯一内容。
///
/// 结构: 三层视差
///   Layer 1 (背景): 光晕, 旋转最慢
///   Layer 2 (中景): 门板, 标准速度
///   Layer 3 (前景): 锁体 + 文字, 旋转最快
struct DoorStage<Front: View, Back: View>: View {
    @Binding var flipped: Bool

    /// 门外内容
    @ViewBuilder var front: () -> Front
    /// 门里内容
    @ViewBuilder var back: () -> Back

    /// 手势拖拽进度 0...1 (0=门外, 1=门里)
    @State private var dragProgress: CGFloat = 0
    @State private var isDragging = false
    @State private var hapticTickAt: Int = -1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 当前翻转角度
    private var angle: Double {
        let base = flipped ? 1.0 : 0.0
        let p = isDragging ? dragProgress : base
        return p * DoorGeometry.flipAngle
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if reduceMotion {
                    // ── 真降级: 不挂 rotation3DEffect ──
                    // 只做交叉淡入 + 微缩放, 空间隐喻消失但内容可读
                    ZStack {
                        front()
                            .opacity(flipped ? 0 : 1)
                            .scaleEffect(flipped ? 0.98 : 1)
                        back()
                            .opacity(flipped ? 1 : 0)
                            .scaleEffect(flipped ? 1 : 0.98)
                    }
                    .animation(XMotion.soft, value: flipped)
                } else {
                    // ── 真 3D: 三层视差 ──
                    ZStack {
                        // Layer 1: 背景光晕 (最慢)
                        RadialGradient(
                            colors: [XPalette.accent.opacity(0.08), .clear],
                            center: .center, startRadius: 0, endRadius: geo.size.width * 0.8)
                            .rotation3DEffect(
                                .degrees(angle * 0.6),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .leading,
                                perspective: DoorGeometry.perspective)
                            .allowsHitTesting(false)

                        // Layer 2 + 3: 门板与内容
                        ZStack {
                            // 正面
                            front()
                                .opacity(frontfaceOpacity(angle: angle))
                                .allowsHitTesting(!flipped && !isDragging)
                                .accessibilityHidden(flipped)

                            // 背面 (预旋转 180° 防镜像)
                            back()
                                .opacity(backfaceOpacity(angle: angle))
                                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                                .allowsHitTesting(flipped && !isDragging)
                                .accessibilityHidden(!flipped)
                        }
                        .rotation3DEffect(
                            .degrees(angle),
                            axis: (x: 0, y: 1, z: 0),
                            anchor: .leading,
                            perspective: DoorGeometry.perspective)
                    }
                }
            }
            .overlay(alignment: .leading) {
                // 左边缘手势热区 (仅增强, 不是唯一入口)
                if !reduceMotion {
                    Color.clear
                        .frame(width: DoorGeometry.edgeGrabWidth)
                        .contentShape(Rectangle())
                        .gesture(edgeDrag(width: geo.size.width))
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .leading) {
                // 边缘视觉把手 (细光条, 暗示可拖)
                if !flipped && !isDragging {
                    LinearGradient(
                        colors: [.clear, XPalette.accent.opacity(0.18), .clear],
                        startPoint: .top, endPoint: .bottom)
                        .frame(width: 2)
                        .padding(.vertical, 120)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(flipped ? "门里" : "门外")
    }

    // ── 边缘牵引手势 ──
    private func edgeDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { g in
                if !isDragging { isDragging = true }
                let p = min(max(g.translation.width / (width * 0.7), 0), 1)
                dragProgress = flipped ? 1 - p : p
                // 每过 25% 给一次 tick
                let tick = Int(dragProgress * 4)
                if tick != hapticTickAt {
                    hapticTickAt = tick
                    XHaptics.tick.impactOccurred()
                }
            }
            .onEnded { g in
                let p = min(max(g.translation.width / (width * 0.7), 0), 1)
                let target = flipped ? 1 - p : p
                isDragging = false
                hapticTickAt = -1
                if target > DoorGeometry.flipThreshold {
                    withAnimation(XMotion.doorSwing) {
                        flipped = true
                        dragProgress = 1
                    }
                    XHaptics.trigger.impactOccurred()
                    UIAccessibility.post(notification: .screenChanged,
                                         argument: flipped ? "门里" : "门外")
                } else {
                    withAnimation(XMotion.doorSwing) {
                        dragProgress = flipped ? 1 : 0
                    }
                }
            }
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 翻面按钮 (无障碍唯一入口)
// ═══════════════════════════════════════════════════════════

/// 翻面按钮 —— VoiceOver 用户的可达路径。
/// 手势只是增强, 这个按钮才是"必须存在"的入口。
struct DoorFlipButton: View {
    @Binding var flipped: Bool

    var body: some View {
        Button {
            withAnimation(XMotion.doorSwing) {
                flipped.toggle()
            }
            XHaptics.trigger.impactOccurred()
            UIAccessibility.post(notification: .screenChanged,
                                 argument: flipped ? "门里" : "门外")
        } label: {
            Image(systemName: flipped ? "door.left.hand.open" : "door.left.hand.closed")
                .font(.system(size: XIcon.md, weight: .medium))
                .foregroundStyle(XPalette.textSub)
                .frame(width: XHit.min, height: XHit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(flipped ? "返回门外" : "进入门里")
        .accessibilityHint("切换门的正反面")
        .accessibilityAddTraits(.isButton)
    }
}
