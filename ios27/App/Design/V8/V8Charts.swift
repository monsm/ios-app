// V8Charts.swift —— V8 图形组件（环 / 分段环 / 波形 / 半环）
//
// 参考图的"仪表语法"只有一套：轨道 + 已填充段 + 游标 + 刻度。全 App 只缩放尺寸，不换语法。
// 全部数值走 V8.G.*，不写样式字面量。
//
// 轴说明只能有一套（2026-11-05）：`VSpark(axis:)` 自带「0 时/12 时/24 时」或「最早/最近」，
// 因此**用了 axis 就不要再加 VRangeCaption**；反之 axis 传 nil 时才用 VRangeCaption。
// 这条在全仓犯过三次（家页、成员页、记录页），每次都是同一屏两组轴标签，
// 删掉其中一套后信息一点没少 —— 因为它本来就重复。
//
// 为什么没有「每行微型图表」（2026-11-05 设计判定）：参考图 Apple Health 的行内小图靠的是
// 同一个人/同一件事的每日时间序列；本 App 的数据是离散状态（某把锁、某位成员、某条记录），
// 没有等间隔序列可画。硬造一条会是假数据 —— 宁可给整页一处真图形，也不给每行一处假图形。
import SwiftUI

// MARK: - 主环（P2 型：279.3pt 外径 / 36.3pt 描边 / 缺口在正下方）


/// 尺寸纪律（2026-11-05）：`size` 是固定宽度，SwiftUI 不会压缩。
/// 多个环放进同一个 HStack 前必须手算：环数 * size + 间隙 * (环数-1) <= 卡内可用宽度。
/// 实测可用宽度约 336pt（屏 402 - 2*gutterCard 16.6 - 2*padCard 16.5）。
/// 反例：锁设置页曾放 3 个 segCompactOuter*1.9 = 125.4pt 的环，合计 408pt，
/// 结果整页被撑宽、左右各裁一条，连返回按钮都缺一块。
/// 单环加文字横排是安全的：145pt 环 + 16pt 间隙 + 175pt 文字。

struct VHeroRing: View {
    @Environment(\.colorScheme) private var colorScheme
    /// 2026-11-05（全技能审核 · T17）：ambient glow 之前只是静态色块，V8.M.ambient
    /// 定义了 2.4s 呼吸却零消费。这里用 phaseAnimator 让光晕在 0.94↔1.0 之间缓慢呼吸；
    /// Reduce Motion 时单相位（不动）。不用 repeatForever（项目禁令）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 已填充比例 0…1
    let fraction: Double
    /// 环心大数
    let center: String
    /// 环下微标
    var label: String = ""
    /// 外径（默认主环 279.3）
    var size: CGFloat = V8.G.heroOuter
    var tint: Color = V8.C.accent
    /// 是否画 12 点刻度与游标
    var showsTick: Bool = true
    var showsCursor: Bool = true

    private var stroke: CGFloat { size * (V8.G.heroStroke / V8.G.heroOuter) }
    private var radius: CGFloat { (size - stroke) / 2 }
    /// 几何按 heroOuter 归一化后按 size 缩放 —— 全 App 只缩放尺寸，不换语法。
    private var scale: CGFloat { size / V8.G.heroOuter }
    /// 缺口与扫过角度（度）。轨道与已填充段**共用同一起点**，否则两者会错开。
    private var sweepFraction: Double { V8.G.heroSweep / 360 }
    /// 12 点 = 0°、顺时针；SwiftUI 的 trim 起点在 3 点 ⇒ 差 90°。
    private var startRotation: Double { V8.G.heroGapStart - 90 }

    private var glowAlpha: Double {
        colorScheme == .dark ? V8.G.glowAlphaDark : V8.G.glowAlphaLight
    }

    var body: some View {
        ZStack {
            // T17 ambient glow：贴形状的一层呼吸，10pt 内从 100% 衰减到 0 —— 不是页面级渐变。
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [tint.opacity(glowAlpha), tint.opacity(0)]),
                        center: .center,
                        startRadius: size * 0.34,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size * V8.G.glowRadiusFactor, height: size * V8.G.glowRadiusFactor)
                .blur(radius: V8.S.gapS)
                .phaseAnimator(reduceMotion ? [1.0] : [0.94, 1.0]) { view, phase in
                    view.scaleEffect(phase)
                } animation: { _ in V8.M.ambient }
                .accessibilityHidden(true)
            // 内盘（Ø206.7 @ 全尺寸）：环心数字垫在它上面。
            // 2026-11-06（V9 · 液态仪器）：实心卡片色升级为"玻璃表盘" —— 顶亮底暗的
            // 受光渐变 + 顶缘高光描边，像仪器面板上一块嵌进去的玻璃表盘。
            Circle()
                .fill(
                    LinearGradient(
                        colors: [V8.C.cardTop, V8.C.cardBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Circle().strokeBorder(V8.C.cardSheen, lineWidth: V8.S.hair)
                }
                .frame(width: V8.G.heroDisc * scale, height: V8.G.heroDisc * scale)
            // 轨道：画满整段扫过角（含缺口），这样"还没填"的部分是可感知的空槽。
            // 2026-11-06（V9）：轨道加一层内凹阴影（凹槽感），填充段改为高光渐变 ——
            // 亮部在左上（受光面），暗部在右下，模拟抛光金属刻度。
            Circle()
                .trim(from: 0, to: sweepFraction)
                .stroke(V8.C.line, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(startRotation))
                .shadow(color: V8.C.shadow, radius: V8.Z.cardShadowRadius2, y: V8.Z.cardShadowY2)
            Circle()
                .trim(from: 0, to: sweepFraction * max(0, min(1, fraction)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            tint.opacity(0.55),
                            tint,
                            tint.opacity(0.85),
                            tint,
                            tint.opacity(0.55)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(startRotation))
            if showsTick {
                VStack {
                    Capsule(style: .continuous)
                        .fill(V8.C.ink4.opacity(0.55))
                        .frame(width: size * (V8.G.heroTickW / V8.G.heroOuter),
                               height: size * (V8.G.heroTickH / V8.G.heroOuter))
                        .offset(y: size * (V8.G.heroTickTop / V8.G.heroOuter))
                    Spacer(minLength: 0)
                }
            }
            if showsCursor && fraction > 0 {
                // 游标固定在参考图的 bearing 289° / r131（"上次采样位置"），不随填充比例跑。
                Circle()
                    .fill(tint)
                    .frame(width: V8.G.heroCursor * scale, height: V8.G.heroCursor * scale)
                    .offset(y: -V8.G.heroCursorRadius * scale)
                    .rotationEffect(.degrees(V8.G.heroCursorBearing))
                    .accessibilityHidden(true)
            }
            VStack(spacing: V8.S.gapXS) {
                Text(center)
                    .font(size > V8.S.gapXXL * 4 ? V8.T.heroL : V8.T.headline)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .tracking(V8.G.heroNumberTracking)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !label.isEmpty {
                    Text(label)
                        .font(V8.T.micro)
                        .foregroundStyle(tint)
                        .tracking(V8.G.heroLabelTracking)
                }
            }
            .padding(.horizontal, stroke)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? center : label + "，" + center)
        .accessibilityValue(String(format: "%.0f%%", max(0, min(1, fraction)) * 100))
    }
}

// MARK: - 分段环（P1 卡 A 型：多段 + 环心数）

struct VSegmentedRing2: View {
    /// 每段（占比, 颜色）
    let segments: [(Double, Color)]
    let center: String
    var size: CGFloat = V8.G.segOuter
    var width: CGFloat = V8.G.segWidth

    private var total: Double { max(0.0001, segments.reduce(0) { $0 + $1.0 }) }
    /// 段间留缝（4.5°）折算成比例。段数为 1 时不留缝 —— 留了会变成一道缺口。
    private var gapFraction: Double {
        segments.count <= 1 ? 0 : (V8.G.segGapDegrees / 360) / 2
    }

    var body: some View {
        ZStack {
            // 2026-11-06（V9）：环心加一块受光玻璃盘（顶亮底暗），数字不再直接坐在卡面上 ——
            // 与主环的玻璃表盘同一语法，只是尺寸更小。
            Circle()
                .fill(
                    LinearGradient(
                        colors: [V8.C.cardTop, V8.C.cardBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size - width * 2 - V8.S.gapS, height: size - width * 2 - V8.S.gapS)
            Circle()
                .strokeBorder(V8.C.line, lineWidth: width)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, item in
                Circle()
                    .trim(
                        from: startFraction(index) + gapFraction,
                        to: max(startFraction(index) + gapFraction, endFraction(index) - gapFraction)
                    )
                    .stroke(
                        item.1,
                        style: StrokeStyle(lineWidth: width, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(V8.G.segStartBearing - 90))
            }
            Text(center)
                .font(size < V8.G.segOuter ? V8.T.value : V8.T.headline)
                .foregroundStyle(V8.C.ink1)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.isEmpty ? center : "分段构成")
        .accessibilityValue(center)
    }

    private func startFraction(_ index: Int) -> Double {
        segments.prefix(index).reduce(0) { $0 + $1.0 } / total
    }

    private func endFraction(_ index: Int) -> Double {
        segments.prefix(index + 1).reduce(0) { $0 + $1.0 } / total
    }
}

// MARK: - 半环（P1 卡 B 型：开口向下的 180° 仪表）

struct VHalfRing: View {
    let fraction: Double
    let center: String
    var tint: Color = V8.C.accent
    var size: CGFloat = V8.G.segOuter

    private var width: CGFloat { size * 0.1 }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(V8.C.line, style: StrokeStyle(lineWidth: width, lineCap: .round))
            Circle()
                .trim(from: 0.5, to: 0.5 + 0.5 * max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
            VStack(spacing: V8.S.gapXS) {
                Text(center)
                    .font(V8.T.headline)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.top, size * 0.38)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("仪表")
        .accessibilityValue(String(format: "%.0f%%", max(0, min(1, fraction)) * 100))
    }
}

// MARK: - 细柱波形（P3 sparkline：24 根 2pt 柱 + 点线基线 + 游标点）

enum VSparkAxis {
    case hours24
    case samples
}

struct VSpark: View {
    let values: [Double]
    var tint: Color = V8.C.accent
    var cursor: Int? = nil
    var axis: VSparkAxis? = nil
    var height: CGFloat = V8.G.sparkHeight

    private var peak: Double { max(1, values.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            GeometryReader { geo in
                let count = max(1, values.count)
                let gap = count > 1
                    ? max(V8.S.gapXS / 2, (geo.size.width - CGFloat(count) * V8.G.sparkBarW) / CGFloat(count - 1))
                    : 0
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let ratio = max(0.03, value / peak)
                        // 柱是圆头的：宽度 2pt 时 Capsule 的等效圆角就是 1pt（= sparkBarRadius）。
                        // 2026-11-06（V9）：柱身改为纵向受光渐变（顶亮底暗）——
                        // 波形从"一根根色条"变成"一排受光的刻度柱"。
                        RoundedRectangle(cornerRadius: V8.G.sparkBarRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint, tint.opacity(0.45)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .opacity(isCursor(index) ? 1 : 0.72)
                            )
                            .frame(width: V8.G.sparkBarW, height: max(V8.G.sparkBarW, geo.size.height * ratio))
                            .overlay(alignment: .top) {
                                if isCursor(index) {
                                    Circle()
                                        .strokeBorder(tint, lineWidth: V8.S.hair * 3)
                                        .background(Circle().fill(V8.C.bg))
                                        .frame(width: V8.G.sparkCursor, height: V8.G.sparkCursor)
                                        .offset(y: -V8.G.sparkCursor / 2)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: height)
            .accessibilityHidden(true)

            VDotRule()

            if let axis {
                HStack {
                    Text(axis == .hours24 ? "0 时" : "最早")
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink4)
                    Spacer(minLength: 0)
                    if axis == .hours24 {
                        Text("12 时")
                            .font(V8.T.micro)
                            .foregroundStyle(V8.C.ink4)
                        Spacer(minLength: 0)
                    }
                    Text(axis == .hours24 ? "24 时" : "最近")
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        // 2026-11-05（全技能审核 · 图表可读性）：原来只报「波形 / 近24小时」，
        // 对读屏用户等于「有一张图」—— 数据完全不可读。补上格数/峰值/末值。
        .accessibilityLabel(axis == .hours24 ? "近 24 小时柱状图" : "采样走势柱状图")
        .accessibilityValue(values.isEmpty
            ? "没有数据"
            : "共 \(values.count) 个值，峰值 \(Int(values.max() ?? 0))，末值 \(Int(values.last ?? 0))")
    }

    private func isCursor(_ index: Int) -> Bool {
        guard let cursor else { return false }
        return cursor == index
    }
}