// V7Components.swift —— v7 组件库（像素复刻自 3 张 Apple 第一方参考图）。
//
// 逐组件来源（pt 全部取自 TOKENS.md / R1-R2-R3 的 CSS 实测）：
//   · VGauge           ← R1-device.html：外径 279.3 / 描边 36.3 / 缺口 bearing 163–201° /
//                        顶部刻度 4.3×23.3 / 游标 23.3pt @289° r131 / 内盘 Ø206.7 /
//                        中心数字 73pt/700 #3F8EF4 / 标签 13.5pt 字距 1.5 #48525B。
//   · VChip            ← R1：178×53.3 r14 #262626→#1C1C1C + 内描边 0.5pt rgba(255,255,255,.08)；
//                        R2 变体：53×53 / 102×53 / 120×53。
//   · VCard            ← R2：背景 #232227、圆角 27、内边距 16.3；mini 变体 R3：170.7×178 r16 #1C1C1E。
//   · VStatPair        ← TOKENS.md：标签 12.5pt #828282 / 值 17pt/600 #FFFFFF。
//   · VSegmentedRing   ← R2：Ø92、环宽 20.3、段间 4–5°、暗层 55% 亮度、中心数字 21.3pt。
//   · VRingStack       ← R3/Tokens：环宽 14、间隙 1.2、12 点起圆头；参考 C 外径 133.7。
//   · VMiniBars        ← R3：24 格网格线 #3A3A3C 高 57、数据柱宽 1.8 r0.9 带发光。
//   · VAreaChart       ← R1：6 条竖向点线、3 条横线、蓝色区间带、折线 #3F8EF4 宽 1.6、左端圆点 2.4。
//   · VFloatingTabBar  ← TOKENS.md：268×57 r28.5 bottom19.7、玻璃 rgba(32,32,32,.72)+blur20/sat180、
//                        内描边 rgba(120,150,160,.35)、选中黑胶囊 56×49。
import SwiftUI

// MARK: - 主环（参考 A：健康寿命环）

/// 按 bearing（12 点为 0°、顺时针）画弧，inset 为描边中心线相对外径的收缩量。
struct VBearingArc: Shape {
    let startBearing: Double
    let endBearing: Double
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - inset
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: max(0, radius),
            startAngle: .degrees(startBearing - 90),
            endAngle: .degrees(endBearing - 90),
            clockwise: false
        )
        return path
    }
}

/// 主环：279.3pt 外径、36.3pt 角向渐变带、163–201° 缺口、289° 游标。
struct VGauge: View {
    let center: String
    let label: String
    let fraction: Double
    var tint: Color = V.C.blue
    /// 中心读数的字体档（外观「主控读数数字字体」：圆体 / 系统默认体）。
    var numberFont: VFont = V.F.gaugeNumber

    private var clamped: Double {
        max(0, min(1, fraction))
    }

    private var ringGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: V.Gauge.gradient),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    private var cursorOffset: CGSize {
        let radians = V.Gauge.cursorBearing * Double.pi / 180
        return CGSize(
            width: CGFloat(sin(radians)) * V.Gauge.cursorRadius,
            height: -CGFloat(cos(radians)) * V.Gauge.cursorRadius
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [V.C.disc0, V.C.disc1, V.C.disc2]),
                        center: UnitPoint(x: 0.5, y: 0.34),
                        startRadius: 0,
                        endRadius: V.Gauge.discDiameter / 2
                    )
                )
                .frame(width: V.Gauge.discDiameter, height: V.Gauge.discDiameter)

            // 底环：完整 308.2° 角向渐变（暗层；与 R1 JS 的 A0/A1 一致）。
            VBearingArc(
                startBearing: V.Gauge.gapStart,
                endBearing: V.Gauge.gapStart + V.Gauge.sweepDegrees,
                inset: V.Gauge.stroke / 2
            )
            .stroke(ringGradient, style: StrokeStyle(lineWidth: V.Gauge.stroke, lineCap: .round))
            .opacity(V.Gauge.baseOpacity)

            // 亮环：同一角向渐变按 fraction 遮罩，长度 = 308.2° × fraction。
            VBearingArc(
                startBearing: V.Gauge.gapStart,
                endBearing: V.Gauge.gapStart + V.Gauge.sweepDegrees * clamped,
                inset: V.Gauge.stroke / 2
            )
            .stroke(ringGradient, style: StrokeStyle(lineWidth: V.Gauge.stroke, lineCap: .round))
            .shadow(color: tint.opacity(V.Gauge.glowOpacity), radius: V.Gauge.stroke / 3)

            // 顶部刻度：4.3×23.3 #384064，距外沿 6.7。
            RoundedRectangle(cornerRadius: V.Gauge.tickW / 2, style: .continuous)
                .fill(V.C.tick)
                .frame(width: V.Gauge.tickW, height: V.Gauge.tickH)
                .offset(y: -V.Gauge.outer / 2 + V.Gauge.tickTop + V.Gauge.tickH / 2)

            // 游标：23.3pt 实心圆点，bearing 289°、r131，带柔光。
            Circle()
                .fill(tint)
                .frame(width: V.Gauge.cursorDiameter, height: V.Gauge.cursorDiameter)
                .shadow(color: tint.opacity(0.8), radius: V.Gauge.cursorDiameter / 2)
                .offset(cursorOffset)

            // i 按钮：20.7pt 圆 #1D1D21，字形 #5D5D62，位于屏幕 (325,337)。
            Text("i")
                .font(V.F.bedValue)
                .italic()
                .foregroundStyle(V.C.infoGlyph)
                .frame(width: V.Gauge.infoSize, height: V.Gauge.infoSize)
                .background(V.C.infoBG, in: Circle())
                .offset(
                    x: V.Gauge.infoX - V.S.screenW / 2,
                    y: V.Gauge.infoY - V.Gauge.centerY
                )
                .accessibilityHidden(true)

            VStack(spacing: V.S.gapXS + 2) {
                Text(center)
                    .font(numberFont)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .tracking(V.Gauge.numberTracking)
                Text(label)
                    .font(V.F.gaugeLabel)
                    .foregroundStyle(V.C.text5)
                    .tracking(V.Gauge.labelTracking)
            }
        }
        .frame(width: V.Gauge.outer, height: V.Gauge.outer)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(center)
    }
}

// MARK: - 芯片（参考 A / 参考 B）

enum VChipStyle: Equatable {
    /// R1：178×53.3。
    case standard
    /// R2：53×53 方形（只有图标）。
    case square
    /// R2：102×53。
    case compact
    /// R2：120×53。
    case wide

    var width: CGFloat {
        switch self {
        case .standard: return V.S.chipW
        case .square: return V.S.chipH
        case .compact: return 102
        case .wide: return 120
        }
    }

    var usesSecondPalette: Bool {
        switch self {
        case .standard: return false
        default: return true
        }
    }
}

/// 芯片：178×53.3 r14 渐变 + 内描边；B 页变体有 53/102/120 三档宽度。
struct VChip: View {
    let title: String
    let value: String
    var tint: Color = V.C.blue
    var style: VChipStyle = .standard
    var systemImage: String? = nil

    private var top: Color {
        style.usesSecondPalette ? V.C.chipTopB : V.C.chipTop
    }

    private var bottom: Color {
        style.usesSecondPalette ? V.C.chipBottomB : V.C.chipBottom
    }

    var body: some View {
        HStack(spacing: V.S.chipIconGap) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(V.F.bodyMedium)
                    .foregroundStyle(style == .square ? V.C.text1 : tint)
                    .frame(width: V.S.chipIconBox, height: V.S.chipIconBox)
                    .accessibilityHidden(true)
            }
            if style != .square {
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    Text(title)
                        .font(V.F.chipLabel)
                        .foregroundStyle(V.C.text4)
                        .lineLimit(1)
                    Text(value)
                        .font(V.F.chipValue)
                        .foregroundStyle(V.C.text1)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, style == .square ? 0 : V.S.chipPadH)
        .frame(width: style.width, height: V.S.chipH)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [top, bottom]),
                startPoint: .top,
                endPoint: .bottom
            ),
            in: .rect(cornerRadius: V.R.chip, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: V.R.chip, style: .continuous)
                .strokeBorder(V.C.hairlineSoft, lineWidth: V.S.hair)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title.isEmpty ? value : title + "，" + value)
    }
}

// MARK: - 卡片（参考 B / 参考 C）

enum VCardStyle {
    /// R2：背景 #232227、圆角 27、内边距 16.3。
    case regular
    /// R2 卡 2 的暖灰底。
    case warm
    /// R3 微卡：背景 #1C1C1E、圆角 16、内边距 14.7。
    case mini

    var fill: Color {
        switch self {
        case .regular: return V.C.card
        case .warm: return V.C.cardWarm
        case .mini: return V.C.cardAlt
        }
    }

    var radius: CGFloat {
        switch self {
        case .regular, .warm: return V.R.card
        case .mini: return V.R.mini
        }
    }

    var inset: CGFloat {
        switch self {
        case .regular, .warm: return V.S.cardPad
        case .mini: return V.S.miniPad
        }
    }
}

/// 卡片：默认 #232227 r27 内边距 16.3；mini 变体给参考 C 的 170.7×178 微卡用。
struct VCard<Content: View>: View {
    var style: VCardStyle = .regular
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(style.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.fill, in: .rect(cornerRadius: style.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                    .strokeBorder(V.C.hairlineSoft, lineWidth: V.S.hair)
            }
    }
}

/// 卡内分隔线（参考 B：左右距卡边 15.2，rgba(255,255,255,.14)）。
struct VDivider: View {
    var body: some View {
        Rectangle()
            .fill(V.C.hairline)
            .frame(height: V.S.hair)
            .accessibilityHidden(true)
    }
}

// MARK: - 双列读数（TOKENS.md）

/// 标签 12.5pt #828282 / 值 17pt 600。
struct VStatPair: View {
    let items: [(String, String)]

    var body: some View {
        HStack(alignment: .top, spacing: V.S.statGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                VStack(alignment: .leading, spacing: V.S.statLabelGap) {
                    Text(pair.element.0)
                        .font(V.F.statLabel)
                        .foregroundStyle(V.C.text2)
                    Text(pair.element.1)
                        .font(V.F.statValue)
                        .foregroundStyle(V.C.text1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 分段环（参考 B 卡 1 右上）

/// 分段环：Ø92、环宽 20.3、段间 4–5°、每段压 55% 亮度暗层 + 亮芯。
struct VSegmentedRing: View {
    /// (进度占比 0...1, 段颜色)
    let segments: [(Double, Color)]
    let center: String

    private var arcs: [(start: Double, end: Double, color: Color)] {
        let count = max(segments.count, 1)
        let usable = 360 - V.Segmented.gapDegrees * Double(count)
        var cursor = V.Segmented.startBearing
        var result: [(start: Double, end: Double, color: Color)] = []
        for segment in segments {
            let span = max(0, min(1, segment.0)) * usable
            result.append((start: cursor, end: cursor + span, color: segment.1))
            cursor += span + V.Segmented.gapDegrees
        }
        return result
    }

    var body: some View {
        ZStack {
            ForEach(Array(arcs.enumerated()), id: \.offset) { pair in
                VBearingArc(
                    startBearing: pair.element.start,
                    endBearing: pair.element.end,
                    inset: V.Segmented.width / 2
                )
                .stroke(V.C.dimmed(pair.element.color, by: V.Segmented.dimBrightness),
                        style: StrokeStyle(lineWidth: V.Segmented.width, lineCap: .round))
            }
            ForEach(Array(arcs.enumerated()), id: \.offset) { pair in
                VBearingArc(
                    startBearing: pair.element.start,
                    endBearing: pair.element.end,
                    inset: V.Segmented.width / 2
                )
                .stroke(pair.element.color, style: StrokeStyle(lineWidth: V.Segmented.coreWidth, lineCap: .round))
            }
            Text(center)
                .font(V.F.ringCenter)
                .foregroundStyle(V.C.text1)
                .monospacedDigit()
        }
        .frame(width: V.Segmented.diameter, height: V.Segmented.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("分段环")
        .accessibilityValue(a11yValue)
    }

    private var a11yValue: String {
        let parts = segments.enumerated().map { index, segment in
            "第\(index + 1)段 \(Int((max(0, min(1, segment.0)) * 100).rounded()))%"
        }
        return "总计 \(center)" + (parts.isEmpty ? "" : "，" + parts.joined(separator: "，"))
    }
}

// MARK: - 同心活动环（参考 C 活动卡）

/// 同心环组：参考 C 外径 133.7 / 环宽 14 / 间隙 1.2，全部 12 点起顺时针、圆头。
/// 小尺寸（如 88pt）按 size*0.09 收线宽，保证三条环仍有可分辨的间隙。
struct VRingStack: View {
    /// (进度 0...1, 环颜色)，数组顺序为外 → 内。
    let rings: [(Double, Color)]
    let size: CGFloat

    private var lineWidth: CGFloat { V.Ring.lineWidth(for: size) }

    private func ringGradient(_ color: Color) -> AngularGradient? {
        guard color == V.C.red || color == V.C.pink else { return nil }
        return AngularGradient(
            gradient: Gradient(colors: [V.C.redDeep, V.C.redBright, V.C.redDeep]),
            center: .center
        )
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { pair in
                let diameter = size - lineWidth - CGFloat(pair.offset) * (lineWidth + V.Ring.gap) * 2
                Circle()
                    .stroke(V.Ring.track(for: pair.element.1), lineWidth: lineWidth)
                    .frame(width: max(lineWidth, diameter), height: max(lineWidth, diameter))
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, pair.element.0)))
                    .stroke(
                        ringGradient(pair.element.1).map { AnyShapeStyle($0) } ?? AnyShapeStyle(pair.element.1),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: max(lineWidth, diameter), height: max(lineWidth, diameter))
                    .rotationEffect(.degrees(-90))
            }

            // 起点方向箭头（参考 C：红 →、绿 »、青 ↑），放在 12 点附近，纯装饰。
            HStack(spacing: max(2, lineWidth * 0.35)) {
                ForEach(Array(rings.enumerated()), id: \.offset) { pair in
                    Text(arrow(for: pair.element.1))
                        .font(V.F.chartTick)
                        .foregroundStyle(pair.element.1)
                }
            }
            .offset(y: -size / 2 + lineWidth * 0.5)
            .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("活动环")
        .accessibilityValue(a11yValue)
    }

    private func arrow(for color: Color) -> String {
        if color == V.C.red || color == V.C.pink { return "→" }
        if color == V.C.green || color == V.C.rewardGreen { return "»" }
        if color == V.C.cyan || color == V.C.rewardBlue { return "↑" }
        return "•"
    }

    private var a11yValue: String {
        rings.enumerated().map { index, ring in
            "第\(index + 1)环 \(Int((max(0, min(1, ring.0)) * 100).rounded()))%"
        }.joined(separator: "，")
    }
}

// MARK: - 迷你柱图（参考 C 微卡）

/// 24 格通高网格线（1pt #3A3A3C、高 57）+ 数据柱（宽 1.8、r0.9、带发光）+ 轴标。
struct VMiniBars: View {
    let values: [Double]
    var tint: Color = V.C.purple

    private var peakValue: Double { max(values.max() ?? 1, 0.0001) }

    var body: some View {
        VStack(alignment: .leading, spacing: V.Mini.axisLabelGap) {
            GeometryReader { proxy in
                let count = V.Mini.gridCount
                let slot = proxy.size.width / CGFloat(max(count, 1))
                ZStack(alignment: .bottomLeading) {
                    ForEach(0 ..< count, id: \.self) { index in
                        Rectangle()
                            .fill(V.C.grid)
                            .frame(width: V.Mini.gridW, height: V.Mini.gridH)
                            .offset(x: CGFloat(index) * slot)
                    }
                    ForEach(Array(values.prefix(count).enumerated()), id: \.offset) { pair in
                        let height = max(V.Mini.minBarH, V.Mini.gridH * CGFloat(pair.element / peakValue))
                        RoundedRectangle(cornerRadius: V.Mini.barRadius, style: .continuous)
                            .fill(tint)
                            .frame(width: V.Mini.barW, height: height)
                            .shadow(color: tint.opacity(0.7), radius: V.Mini.glowRadius)
                            .offset(x: CGFloat(pair.offset) * slot + (slot - V.Mini.barW) / 2)
                    }
                }
                .frame(width: proxy.size.width, height: V.Mini.gridH, alignment: .bottomLeading)
            }
            .frame(height: V.Mini.gridH)

            // 轴标：0 / 6 / 12 / 18 / 24 时（TOKENS：11px #8E8E93）。
            HStack {
                ForEach(["0", "6", "12", "18", "24"], id: \.self) { label in
                    Text(label)
                        .font(V.F.axisTick)
                        .foregroundStyle(V.C.axisLabel)
                    if label != "24" { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("柱状图")
        .accessibilityValue(a11yValue)
    }

    private var a11yValue: String {
        let total = values.reduce(0, +)
        return "共 24 格，峰值 \(Int(peakValue.rounded()))，合计 \(Int(total.rounded()))"
    }
}

// MARK: - 面积图（参考 A 底部）

/// 6 条竖向点线 + 3 条横线 + 蓝色区间带 + 折线 #3F8EF4（1.6pt）+ 左端圆点 2.4pt。
struct VAreaChart: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            let top = V.Chart.topGap
            let bottom = size.height

            // 3 条横线：顶部 #262626 / 36pt 处 #393939 / 底部 #262626。
            let rules: [(CGFloat, Color)] = [
                (0, V.C.rule1),
                (V.Chart.ruleMidY, V.C.rule2),
                (size.height, V.C.rule1)
            ]
            for rule in rules {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: rule.0))
                line.addLine(to: CGPoint(x: size.width, y: rule.0))
                context.stroke(line, with: .color(rule.1), lineWidth: V.S.hair)
            }

            // 6 条竖向点线：实测间距 43pt，首条距绘图区左沿 14.4pt（TOKENS 52 行）。
            for index in 0 ..< V.Chart.verticals {
                let x = V.Chart.firstInset + CGFloat(index) * V.Chart.verticalSpacing
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    line,
                    with: .color(V.C.chartGrid),
                    style: StrokeStyle(lineWidth: V.S.hair, dash: V.Chart.dash)
                )
            }

            guard values.count >= 2 else { return }
            let peak = max(values.max() ?? 1, 0.0001)
            let x0 = size.width * V.Chart.xStart
            let x1 = size.width * V.Chart.xEnd
            let usableHeight = size.height * V.Chart.usable

            func point(_ index: Int) -> CGPoint {
                let ratio = CGFloat(values[index] / peak)
                let x = x0 + (x1 - x0) * CGFloat(index) / CGFloat(values.count - 1)
                let y = bottom - top - ratio * usableHeight
                return CGPoint(x: x, y: y)
            }

            var linePath = Path()
            for index in values.indices {
                if index == 0 {
                    linePath.move(to: point(index))
                } else {
                    linePath.addLine(to: point(index))
                }
            }

            // 区间带：折线上沿 + 下方 80% 位置的下沿。
            var band = Path()
            band.move(to: point(0))
            for index in 1 ..< values.count {
                band.addLine(to: point(index))
            }
            let lower = max(top, bottom - top - usableHeight * 0.45)
            band.addLine(to: CGPoint(x: x1, y: lower))
            band.addLine(to: CGPoint(x: x0, y: lower))
            band.closeSubpath()
            context.fill(
                band,
                with: .linearGradient(
                    Gradient(colors: [V.C.blueBand.opacity(0.55), V.C.blueBand.opacity(0.12)]),
                    startPoint: CGPoint(x: 0, y: top),
                    endPoint: CGPoint(x: 0, y: bottom)
                )
            )

            context.stroke(
                linePath,
                with: .color(V.C.blue),
                style: StrokeStyle(lineWidth: V.Chart.lineWidth, lineJoin: .round)
            )

            let first = point(0)
            let dot = Path(ellipseIn: CGRect(
                x: first.x - V.Chart.dot,
                y: first.y - V.Chart.dot,
                width: V.Chart.dot * 2,
                height: V.Chart.dot * 2
            ))
            context.fill(dot, with: .color(V.C.blue))
        }
        .frame(height: V.Chart.height)
        .overlay(alignment: .bottomLeading) {
            Text("0 时")
                .font(V.F.chartTick)
                .foregroundStyle(V.C.axisLabel)
                .offset(x: V.S.gapXS, y: -V.S.gapXS)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: V.S.gapXXS) {
                Text("高峰")
                Text("平时")
            }
            .font(V.F.chartTick)
            .foregroundStyle(V.C.axisLabel)
            .offset(x: -V.S.gapXS, y: -V.S.gapXS)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("面积图")
        .accessibilityValue(a11yValue)
    }

    private var a11yValue: String {
        guard let first = values.first, let last = values.last, let peak = values.max() else { return "无数据" }
        return "起点 \(Int(first.rounded()))，终点 \(Int(last.rounded()))，峰值 \(Int(peak.rounded()))，共 \(values.count) 个采样"
    }
}

// MARK: - 浮动标签栏（TOKENS.md 统一规格）

struct VTabItem: Identifiable {
    let slot: TabSlot
    let title: String
    let symbol: String
    /// 右上角角标（凭证 Tab 的近 7 日到期数）。nil / 0 = 不画。
    var badge: Int? = nil

    var id: Int { slot.rawValue }

    static var all: [VTabItem] {
        [
            VTabItem(slot: .door, title: "设备", symbol: "shield.fill"),
            VTabItem(slot: .keys, title: "凭证", symbol: "lock.fill"),
            VTabItem(slot: .records, title: "记录", symbol: "list.bullet"),
            VTabItem(slot: .settings, title: "设置", symbol: "gearshape.fill")
        ]
    }
}

/// 268×57 玻璃胶囊、bottom 19.7、选中黑胶囊 56×49。
struct VFloatingTabBar: View {
    @Binding var selection: TabSlot
    var items: [VTabItem] = VTabItem.all

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = selection == item.slot
                Button {
                    selection = item.slot
                } label: {
                    VStack(spacing: V.Tab.labelGap) {
                        Image(systemName: item.symbol)
                            .font(V.F.tabIcon)
                            .foregroundStyle(selected ? V.C.text1 : V.C.text3)
                            .accessibilityHidden(true)
                            .overlay(alignment: .topTrailing) {
                                if let badge = item.badge, badge > 0 {
                                    Text(badge > 9 ? "9+" : "\(badge)")
                                        .font(V.F.microSmall)
                                        .foregroundStyle(V.C.text1)
                                        .padding(.horizontal, V.S.gapXS)
                                        .background(V.C.red, in: Capsule())
                                        .offset(x: V.S.gapMS, y: -V.S.gapS)
                                        .accessibilityHidden(true)
                                }
                            }
                        Text(item.title)
                            .font(V.F.tab)
                            .foregroundStyle(selected ? V.C.text1 : V.C.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: V.Tab.height)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: V.R.tabSelected, style: .continuous)
                                .fill(V.C.tabPill)
                                .frame(width: V.Tab.selectedW, height: V.Tab.selectedH)
                                .overlay {
                                    RoundedRectangle(cornerRadius: V.R.tabSelected, style: .continuous)
                                        .strokeBorder(V.C.tabPillEdge, lineWidth: V.S.hair)
                                }
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.badge.map { $0 > 0 ? "\(item.title)，\($0) 条近 7 日到期" : item.title } ?? item.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, V.S.gapS)
        .frame(width: V.Tab.width, height: V.Tab.height)
        .background {
            RoundedRectangle(cornerRadius: V.R.tab, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: V.R.tab, style: .continuous)
                        .fill(V.C.tabGlass)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: V.R.tab, style: .continuous)
                        .strokeBorder(V.C.tabEdge, lineWidth: V.S.hair)
                }
        }
        .clipShape(.rect(cornerRadius: V.R.tab, style: .continuous))
        .shadow(color: V.C.bg.opacity(0.5), radius: 12, y: 8)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 动作按钮（空态出路 / 卡内主操作）

/// v7 动作按钮：50pt 高、14pt 圆角、蓝底白字（参考图没有按钮，沿用卡片的 14pt 圆角语言）。
struct VActionButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = V.C.blue
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: V.S.gapS) {
                if busy {
                    ProgressView().controlSize(.small).tint(V.C.text1)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(V.F.actionIcon)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(V.F.bodyStrong)
            }
            .foregroundStyle(V.C.text1)
            .frame(maxWidth: .infinity)
            .frame(height: V.Action.height)
            .background(tint, in: .rect(cornerRadius: V.R.action, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - 通用行（设置 / 次级入口）

/// 小节标题（参考 B 卡头 / 参考 R4 区块标题两档）。
struct VSectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
            Text(text)
                .font(V.F.small)
                .foregroundStyle(V.C.text3)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 卡头：11pt/500 #A2A1A6 + 右侧 chevron（参考 B 每张卡的「门锁 ›」）。
struct VCardHeader: View {
    let title: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: V.S.gapXS) {
            Text(title)
                .font(V.F.cardHeader)
                .foregroundStyle(V.C.text8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(V.F.tab)
                    .foregroundStyle(V.C.text3)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 列表行：圆形图标 + 标题/说明 + 可选读数 + chevron（设置页与快捷入口共用）。
struct VListRow: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    var tint: Color = V.C.rewardBlue
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: V.S.gapM) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(V.F.rowIcon)
                        .foregroundStyle(V.C.text1)
                        .frame(width: V.List.iconSize, height: V.List.iconSize)
                        .background(tint, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    Text(title)
                        .font(V.F.rowTitle)
                        .foregroundStyle(V.C.text1)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(V.F.rowDetail)
                            .foregroundStyle(V.C.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: V.S.gapS)
                if let value {
                    Text(value)
                        .font(V.F.rowDetail)
                        .foregroundStyle(V.C.text3)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(V.F.chevron)
                    .foregroundStyle(V.C.text4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V.List.rowMinHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// 右侧读数是设置页最关键的结论（82% / 已设 / 从未备份），必须进 VoiceOver。
    private var a11yLabel: String {
        var parts = [title]
        if let detail, !detail.isEmpty { parts.append(detail) }
        if let value, !value.isEmpty { parts.append("当前 " + value) }
        return parts.joined(separator: "，")
    }
}

/// 开关行：标题 + 说明 + 系统 Toggle。
struct VToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(V.F.rowTitle)
                    .foregroundStyle(V.C.text1)
            }
            .tint(V.C.rewardBlue)
            .frame(minHeight: V.List.toggleMinHeight)
            if let detail {
                Text(detail)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews（每个组件一份，自包含 mock 数据）

#Preview("VGauge") {
    VGauge(center: "82", label: "电量", fraction: 0.82, tint: V.C.blue)
        .padding(V.S.gapL)
        .background(V.C.bg)
}

#Preview("VChip") {
    HStack(spacing: V.S.chipGap) {
        VChip(title: "概览", value: "全部正常", tint: V.C.rewardGreen, style: .standard, systemImage: "circle.hexagongrid.fill")
        VChip(title: "电量", value: "82%", tint: V.C.blue, style: .standard, systemImage: "battery.75percent")
    }
    .padding(V.S.chipLeftA)
    .background(V.C.bg)
}

#Preview("VCard") {
    VCard {
        VStack(alignment: .leading, spacing: V.S.gapM) {
            Text("凭证有效").font(V.F.cardBig).foregroundStyle(V.C.text1)
            VStatPair(items: [("总数", "12 枚"), ("本周新增", "3 枚")])
        }
    }
    .padding(V.S.cardGutter)
    .background(V.C.bg)
}

#Preview("VStatPair") {
    VStatPair(items: [("预计可用", "4 个月"), ("建议更换", "2 月 12 日")])
        .padding(V.S.pageGutterA)
        .background(V.C.bg)
}

#Preview("VSegmentedRing") {
    VSegmentedRing(
        segments: [(0.27, V.C.mint), (0.18, V.C.coral), (0.50, V.C.indigo)],
        center: "12"
    )
    .padding(V.S.gapL)
    .background(V.C.bg)
}

#Preview("VRingStack") {
    VRingStack(
        rings: [(0.46, V.C.red), (0.11, V.C.green), (0.57, V.C.cyan)],
        size: V.Ring.referenceOuter
    )
    .padding(V.S.gapL)
    .background(V.C.bg)
}

#Preview("VMiniBars") {
    VMiniBars(values: [0, 0, 0, 0, 0, 0, 25, 20, 19, 38, 0, 0], tint: V.C.purple)
        .frame(width: 143)
        .padding(V.S.gapL)
        .background(V.C.cardAlt)
}

#Preview("VAreaChart") {
    VAreaChart(values: [28, 36, 41, 44, 52, 48, 55, 58, 54, 61, 57, 64, 60, 67])
        .padding(V.S.gapM)
        .background(V.C.bg)
}

private struct VFloatingTabBarPreviewHost: View {
    @State private var selection: TabSlot = .door

    var body: some View {
        VStack {
            Spacer()
            VFloatingTabBar(selection: $selection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V.C.bg)
    }
}

#Preview("VFloatingTabBar") {
    VFloatingTabBarPreviewHost()
}

#Preview("VSectionLabel") {
    VSectionLabel(text: "门锁", trailing: "3 项")
        .padding(V.S.pageGutterC)
        .background(V.C.bg)
}

#Preview("VCardHeader") {
    VCardHeader(title: "门锁")
        .padding(V.S.cardPad)
        .background(V.C.card)
}

#Preview("VDivider") {
    VDivider()
        .padding(V.S.cardPad)
        .background(V.C.card)
}

private struct VToggleRowPreviewHost: View {
    @State private var isOn = true

    var body: some View {
        VToggleRow(title: "只读试验模式", detail: "只读模式会停用所有写入类命令。", isOn: $isOn)
            .padding(V.S.cardPad)
            .background(V.C.card)
    }
}

#Preview("VToggleRow") {
    VToggleRowPreviewHost()
}

#Preview("VActionButton") {
    VActionButton(title: "添加门锁", systemImage: "plus") {}
        .padding(V.S.pageGutterA)
        .background(V.C.bg)
}

#Preview("VListRow") {
    VStack(spacing: 0) {
        VListRow(title: "锁实况", detail: "电量 82% · 已连接", systemImage: "gauge.with.dots.needle.50percent", tint: V.C.rewardBlue, value: "82%") {}
        VDivider()
        VListRow(title: "备份与恢复", detail: "上次备份 10 月 28 日", systemImage: "externaldrive", tint: V.C.rewardGreen) {}
    }
    .padding(V.S.cardPad)
    .background(V.C.card, in: .rect(cornerRadius: V.R.card, style: .continuous))
    .padding(V.S.cardGutter)
    .background(V.C.bg)
}
