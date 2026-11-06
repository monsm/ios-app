// V8Components.swift —— V8 组件库（重构方案 04 的落地层）
//
// 对应 04 §1 的组件定义。所有数值走 V8Tokens.swift，不写任何样式字面量。
// 与 V7Components.swift 并存：V7 组件不动，V8 组件只被新页面引用。
import SwiftUI

// MARK: - 0. 标签栏形态（Shell 与 VPage 共用一份判据）

/// 标签栏是「系统 Liquid Glass」还是「自绘浮岛」。
///
/// 2026-11-05（用户拍板：「保持原生液态玻璃控件优先」）：默认走系统栏。
/// 判据只在这里读一次键 —— Shell 决定画不画 GlassTabBar，VPage 决定底部留多少白，
/// 两处必须同一个答案（否则会出现「系统栏 + 78pt 空白」或「浮岛栏压在内容上」）。
enum TabBarMode {
    static var native: Bool {
        // 2026-11-05（全技能审核 · 截图保真）：CI 复用的模拟器里残留了旧版本写下的
        // kf_native_tabbar=false，于是 21 张"当前"截图全是已非默认的自绘浮岛栏 ——
        // 按默认配置验收会看到另一套界面。CI 截图一律按默认（系统原生栏）渲染。
        if ProcessInfo.processInfo.arguments.contains("-kfUITest") { return true }
        return DB.store.getBool("kf_native_tabbar", true)
    }
}

// 2026-11-06（V9 · 液态仪器）：页面大气身份。每个 Tab 一组「顶光 / 尾光」，
// 内容层色彩明度 ≤10%（浅色）/ ≤16%（深色）—— HIG Materials 的纪律：
// 内容层的丰富靠色彩与光照，且必须足够淡，玻璃栏压上来时文字依旧可读。
// 对比度：辉光下仍是 bgTop/bgBottom 打底（≥4.5 断言不受影响）。
enum V8Atmosphere {
    case brand      // 门：品牌蓝 → 冷紫
    case violet     // 钥匙：指纹紫 → 品牌蓝
    case indigo     // 台账：信息靛 → 紫
    case green      // 家：手机钥匙绿 → 靛
    case graphite   // 设置：石墨 → 无尾光（最素的一页，呼应"仪器"）

    var top: Color {
        switch self {
        case .brand: return V8.C.glowA
        case .violet: return V8.C.glowVioletTop
        case .indigo: return V8.C.glowIndigoTop
        case .green: return V8.C.glowGreenTop
        case .graphite: return V8.C.glowGraphiteTop
        }
    }

    var bottom: Color {
        switch self {
        case .brand: return V8.C.glowB
        case .violet: return V8.C.glowA
        case .indigo: return V8.C.glowIndigoBottom
        case .green: return V8.C.glowGreenBottom
        case .graphite: return V8.C.glowGraphiteBottom
        }
    }
}

// MARK: - 1. 卡片容器

enum VCardStyle2 {
    /// 普通卡片（页面主体）
    case primary
    /// 凹槽/内嵌块
    case well
    /// 弹出层内容块
    case sheet

    var fill: Color {
        switch self {
        case .primary: return V8.C.card
        case .well: return V8.C.well
        case .sheet: return V8.C.card
        }
    }

    // 2026-11-06（V9 · 液态仪器）：well 不吃材质渐变（凹槽本来就是"沉下去"的素面），
    // primary / sheet 走「顶亮底暗」面板渐变 —— 真实仪器面板的光永远来自上方。
    var castsMaterial: Bool {
        switch self {
        case .primary, .sheet: return true
        case .well: return false
        }
    }

    var radius: CGFloat {
        switch self {
        case .primary, .sheet: return V8.R.card
        case .well: return V8.R.inset
        }
    }

    var castsShadow: Bool {
        switch self {
        case .primary, .sheet: return true
        case .well: return false
        }
    }
}

struct VCard2<Content: View>: View {
    var style: VCardStyle2 = .primary
    @ViewBuilder var content: Content

    var body: some View {
        // 2026-11-05（全技能审核 · 系统性缺陷）：必须先把 @ViewBuilder 的 content 收进 VStack。
        // 直接把 .padding/.background 挂到 content（TupleView）上时，SwiftUI 会把修饰符
        // 分别应用到**每个子视图**：VCardHead / VDivider2 / 正文 / 行表各自获得一份卡片背景，
        // 一张卡被拆成 3–5 张白卡，页面上还夹着只剩一条分隔线的"空卡"。
        // CI 截图里每页 27%–50% 的高度是这种空卡 — 之前的审计误判成"阴影带/背景色差异"。
        // VStack 让 content 成为一个真正的布局容器，卡片回到一张。
        VStack(alignment: .leading, spacing: 0) {
            content
        }
            // 卡内上下与左右**不对称**（参考图实测：上 20.6 / 下 18.7 / 左右 16.5）。
            // 之前四边都用 padCard，卡会显得"下边空一截"—— 因为底部的脚注行高比顶部眉标小。
            .padding(.horizontal, V8.S.padCard)
            .padding(.top, V8.S.padCardTop)
            .padding(.bottom, V8.S.padCardBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardSurface(style))
    }

    // 2026-11-06（V9 · 液态仪器）：卡片材质 = 渐变面板 + 顶缘受光高光 + 双层投影。
    //   · 渐变：cardTop → cardBottom，微斜向（纯垂直像塑料，斜向才是光）；
    //   · 高光：顶缘 1pt cardSheen 描边（面板受光的物理暗示）；
    //   · 投影：12pt 环境影（抬离纸面）+ 3pt 接触影（贴着桌面），同色 V8.C.shadow。
    // well（凹槽）保持素面 + 无影 —— 沉下去的层不反光。
    @ViewBuilder
    private func cardSurface(_ style: VCardStyle2) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
        if style.castsMaterial {
            shape
                .fill(
                    LinearGradient(
                        colors: [V8.C.cardTop, V8.C.cardBottom],
                        startPoint: UnitPoint(x: 0.3, y: 0),
                        endPoint: UnitPoint(x: 0.7, y: 1)
                    )
                )
                .shadow(
                    color: V8.C.shadow,
                    radius: V8.Z.cardShadowRadius,
                    y: V8.Z.cardShadowY
                )
                .shadow(
                    color: V8.C.shadow,
                    radius: V8.Z.cardShadowRadius2,
                    y: V8.Z.cardShadowY2
                )
                .overlay {
                    shape.strokeBorder(V8.C.cardSheen, lineWidth: V8.S.hair)
                }
        } else {
            shape
                .fill(style.fill)
        }
    }
}

// MARK: - 2. 卡头（eyebrow + statement）

struct VCardHead: View {
    let eyebrow: String
    let statement: String
    var trailing: String? = nil

    var body: some View {
        // 2026-11-05（Round 3 · 专业 iOS 27）：原来「14.5pt 灰色眉标 + 21.5pt 判断句」是
        // 每张卡固定的两层标题 —— 小字在上、大字在下，正是设计审查里点名的「eyebrow 模板感」；
        // 26 个页面 × 每页 3–6 张卡，整屏都是同一个节奏。
        // 原生层级反过来：卡片名（原 eyebrow）做 17pt semibold 标题，
        // 原来那句长判断降为 15pt 次级说明；右侧 trailing 仍是 13pt 辅助值。
        VStack(alignment: .leading, spacing: V8.S.gapHair) {
            HStack(alignment: .firstTextBaseline, spacing: V8.S.gapS) {
                Text(eyebrow)
                    .font(V8.T.headline)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(V8.T.label)
                        .foregroundStyle(V8.C.ink4)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Text(statement)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 3. 分隔线（0.4pt 实线，只做结构切分）

struct VDivider2: View {
    var body: some View {
        Rectangle()
            .fill(V8.C.line)
            .frame(height: V8.S.hair * (DB.store.getBool("kf_hc") ? 2 : 1))
    }
}

/// 表格行点线（数据网格，不是结构切分）
///
/// 2026-11-05（全技能审核 · 性能）：原来用 80 个 Circle 做 mask（全仓 147 个实例 ≈ 11,760 个 Shape，
/// 每个都要参与布局与合成）。改成一条**虚线描边**：同样的视觉（点 + 间隔），只有一个 Shape。
struct VDotRule: View {
    var body: some View {
        // 2026-11-06（V9 · 液态仪器）：点线恢复为「数据网格」签名 —— 与结构分割线
        // (VDivider2 实线) 区分开。实现是一条 1.2pt 高的 Canvas 点带：点距 6pt、
        // 点径 1.2pt、颜色 line（≥1.25:1 可感知断言仍过）。单个 Shape，无性能成本。
        // VDashLine 早已删除（dead-code 闸门确认）；这里不复活旧 Shape，直接 SwiftUI 原生画法。
        Canvas { context, size in
            let dot = CGSize(width: 1.2, height: 1.2)
            var x: CGFloat = 0
            let y = size.height / 2 - dot.height / 2
            let line = DB.store.getBool("kf_hc") ? V8.C.ink4 : V8.C.line
            while x < size.width {
                context.fill(
                    Path(ellipseIn: CGRect(origin: CGPoint(x: x, y: y), size: dot)),
                    with: .color(line)
                )
                x += 6
            }
        }
        .frame(height: V8.S.gapS / 2)
        .accessibilityHidden(true)
    }
}

/// 一条水平虚线（只有一个 Shape，用于表格行点线）。
private struct VDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

// MARK: - 4. 数据行（彩色标签 + 名称 + 右对齐值 + 可选行内波形）

struct VDataRow: View {
    let tag: String
    let tagTint: Color
    let title: String
    var detail: String? = nil
    let value: String
    var unit: String? = nil
    var spark: [Double]? = nil
    var sparkTint: Color = V8.C.accentFill
    /// 标签列宽度。默认 76pt（凭证分类词），时间线这类短时刻用窄档（51pt）。
    /// 2026-11-05（Round 3）：记录页时刻列原来也是 76pt，名称被挤到很晚才开始。
    var tagNarrow: Bool = false
    /// 2026-11-05（全技能审核 · 44pt 命中）：数据行作为 Button label 时视觉行高只有 22.1pt。
    /// 非交互表格保持密度（interactive=false），列表入口传 true 把命中区抬到 44pt。
    var interactive: Bool = false

    // 2026-11-05（全技能审核 · Dynamic Type）：AX 档下固定 76.3pt 标签列 + 全行 lineLimit(1)
    // 会把「密码 / 长期·大门 / 成员C / 永久」挤成一条截断线。AX 档改两行：
    // 第一行 = 分类 + 右侧值，第二行 = 名称/归属，全部允许换行。
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { axBody } else { compactBody }
        }
        .frame(minHeight: interactive ? V8.H.min : V8.S.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yText)
    }

    private var compactBody: some View {
        HStack(alignment: .center, spacing: V8.S.gapS) {
            Text(tag)
                .font(V8.T.caption)
                .foregroundStyle(tagTint)
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: tagNarrow ? V8.S.gapTableFirst * 1.2 : V8.S.gapTableFirst * 1.8, alignment: .leading)

            Text(title)
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
                .lineLimit(1)

            if let detail {
                Text(detail)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(1)
            }

            Spacer(minLength: V8.S.gapS)

            if let spark {
                VSpark(values: spark, tint: sparkTint, cursor: nil, axis: nil, height: V8.G.sparkHeightInline)
                    .frame(width: V8.S.gapTableFirst * 2.2)
                    .accessibilityHidden(true)
            }

            Text(value)
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
                .monospacedDigit()
                .lineLimit(1)

            if let unit {
                Text(unit)
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
            }
            // 2026-11-05（Round 3 · 可点性）：可点行如果只有文字、没有读数、也没有 chevron，
            // 用户看不出它能点（记录页时间线就是这样）。有读数的行末尾已经有数字，
            // 再加箭头会挤；所以只在「纯导航行」上显示 chevron。
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .accessibilityHidden(true)
            }
        }
    }

    private var showsDisclosure: Bool {
        interactive && value.isEmpty && unit == nil && spark == nil
    }

    private var axBody: some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            HStack(alignment: .firstTextBaseline, spacing: V8.S.gapS) {
                Text(tag)
                    .font(V8.T.caption)
                    .foregroundStyle(tagTint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(value)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let unit {
                    Text(unit)
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink4)
                }
            }
            if !title.isEmpty {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail {
                Text(detail)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let spark {
                VSpark(values: spark, tint: sparkTint, cursor: nil, axis: nil, height: V8.G.sparkHeightInline)
                    .frame(height: V8.G.sparkHeightInline)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, V8.S.gapXS)
    }

    private var a11yText: String {
        // 2026-11-05（全技能审核 · VoiceOver）：title 为空时原来会念出「密码，，1 次」。
        var parts: [String] = [tag, title]
        if let detail { parts.append(detail) }
        parts.append(value + (unit ?? ""))
        return parts.filter { !$0.isEmpty }.joined(separator: "，")
    }
}

// MARK: - 5. 芯片（微型仪表 + 两行字）

enum VChipIcon {
    /// 环（value 0…1）
    case ring(Double, Color)
    /// 分段环（每段占比）
    case segmented([(Double, Color)])
    /// 纯字形（无仪表）
    case glyph(String)
    /// 无图标（方形芯片）
    case none
}

struct VChip2: View {
    let icon: VChipIcon
    let label: String
    let value: String
    var selected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { chipBody }
                    .buttonStyle(V8PressStyle())
            } else {
                chipBody
            }
        }
    }

    private var chipBody: some View {
        // 2026-11-05（Round 3 · 专业 iOS 27）：原来每枚芯片左侧是一个 24pt 的「分段环」
        // 微图标 + 两行文字（14.5 / 16.4），一排 4–5 枚就像一排小仪表盘；环的填充比例
        // 与右侧数字说的是同一件事。现在收成原生筛选芯片：6pt 色点 + 单行「标签 值」，
        // 选中用强调色填充；信息密度不变，视觉噪音少一半。
        HStack(spacing: V8.S.gapXS) {
            Circle()
                .fill(chipDot)
                .frame(width: V8.G.chipDot, height: V8.G.chipDot)
                .accessibilityHidden(true)
            if !label.isEmpty {
                Text(label)
                    .font(V8.T.label)
                    .foregroundStyle(selected ? V8.C.onAccent.opacity(0.82) : V8.C.ink4)
                    .lineLimit(1)
            }
            if !value.isEmpty {
                Text(value)
                    .font(V8.T.chipValue)
                    .foregroundStyle(selected ? V8.C.onAccent : V8.C.ink1)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, V8.S.gapM)
        .frame(minHeight: V8.S.hChip)
        .background(chipBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.isEmpty ? value : "\(label)，\(value)")
        .accessibilityAddTraits(chipTraits)
    }

    // 2026-11-06（V9 · 液态仪器）：芯片从"两块平色胶囊"升级为材质两态 ——
    //   选中 = 品牌色纵向渐变 + 顶缘受光高光（像一颗凸起的玻璃珠）；
    //   未选 = 微妙的凸面（上亮下暗）+ 发丝描边（像嵌进面板的素键）。
    @ViewBuilder
    private var chipBackground: some View {
        let shape = Capsule(style: .continuous)
        if selected {
            shape
                .fill(
                    LinearGradient(
                        colors: [V8.C.accentFill, V8.C.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    shape.strokeBorder(V8.C.cardSheen, lineWidth: V8.S.hair)
                }
        } else {
            shape
                .fill(
                    LinearGradient(
                        colors: [V8.C.chipOn, V8.C.chipOff],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    shape.strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                }
        }
    }

    /// 芯片左侧色点：沿用原分段环的颜色，只保留「类别」这一层含义。
    private var chipDot: Color {
        switch icon {
        case .ring(_, let tint): return tint
        case .segmented(let segments): return segments.first?.1 ?? V8.C.accent
        case .glyph: return V8.C.ink3
        case .none: return Color.clear
        }
    }

    private var chipTraits: AccessibilityTraits {
        if action != nil {
            return selected ? [.isButton, .isSelected] : .isButton
        }
        return selected ? [.isSelected] : []
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .ring(let fraction, let tint):
            ZStack {
                Circle()
                    .strokeBorder(tint.opacity(0.18), lineWidth: V8.S.gapXS)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: V8.S.gapXS, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
        case .segmented(let segments):
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, item in
                    Circle()
                        .trim(
                            from: startFraction(index, segments),
                            to: endFraction(index, segments)
                        )
                        .stroke(item.1, style: StrokeStyle(lineWidth: V8.S.gapXS, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
        case .glyph(let symbol):
            Image(systemName: symbol)
                .font(V8.T.chipValue)
                .foregroundStyle(V8.C.ink2)
                .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
        case .none:
            EmptyView()
        }
    }

    private func total(_ segments: [(Double, Color)]) -> Double {
        max(0.0001, segments.reduce(0) { $0 + $1.0 })
    }

    private func startFraction(_ index: Int, _ segments: [(Double, Color)]) -> Double {
        let sum = segments.prefix(index).reduce(0) { $0 + $1.0 }
        return sum / total(segments)
    }

    private func endFraction(_ index: Int, _ segments: [(Double, Color)]) -> Double {
        let sum = segments.prefix(index + 1).reduce(0) { $0 + $1.0 }
        return sum / total(segments)
    }
}

struct VChipRow2<Item: Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    let value: (Item) -> String
    let icon: (Item) -> VChipIcon
    @Binding var selection: Item

    var body: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                ForEach(items, id: \.self) { item in
                    VChip2(
                        icon: icon(item),
                        label: label(item),
                        value: value(item),
                        selected: item == selection,
                        action: { selection = item }
                    )
                }
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }
}

// MARK: - 6. 空态（参考图没给的答案：空态环 + 判断句 + 因果 + 唯一出路）

struct VEmpty: View {
    let title: String
    let reason: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VCard2 {
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                VHeroRing(fraction: 0, center: "—", label: "", size: V8.G.segCompactOuter, tint: V8.C.ink4)
                    .accessibilityHidden(true)
                Text(title)
                    .font(V8.T.headline)
                    .foregroundStyle(V8.C.ink1)
                Text(reason)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .lineSpacing(V8.L.body - V8.T.body.size)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Text(actionTitle)
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .padding(.horizontal, V8.S.gapL)
                        .frame(minHeight: V8.H.min)
                        .background(
                            // 2026-11-06（V9 · 液态仪器）：主行动按钮 = 受光玻璃凸台 ——
                            // 纵向品牌色渐变 + 顶缘高光 + 抬升投影，像系统里最想被按的那颗按钮。
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [V8.C.accentFill, V8.C.accent],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(V8.C.cardSheen, lineWidth: V8.S.hair)
                                }
                                .shadow(
                                    color: V8.C.accent.opacity(0.35),
                                    radius: V8.Z.cardShadowRadius2,
                                    y: V8.Z.cardShadowY
                                )
                        )
                }
                .buttonStyle(V8PressStyle())
                // 2026-11-05（全技能审核 · VoiceOver）：空态的三段（判断 / 原因 / 出路）
                // 原来是一组散元素，读屏要滑四次才知道该干什么。合成一组并读成一句。
                .accessibilityElement(children: .contain)
            }
        }
    }
}

// MARK: - 7. 失败态（什么失败 / 为什么 / 下一步 / 原始串折叠）

struct VFailure: View {
    let what: String
    let why: String
    let next: String
    var raw: String? = nil
    var retry: (() -> Void)? = nil
    /// 动作文案。**默认「重试」，但并非所有出路都是重试** ——
    /// 2026-11-05（对抗审查 · 流程不合理）：原来这里写死 Text("重试")，
    /// 于是「本机台账读不出来，请先去备份恢复」这类错误**只能不给按钮**，
    /// 唯一的出路只存在于一句话里。现在调用点可以写成「去备份工作室」。
    var actionTitle: String = "重试"
    @State private var showsRaw = false

    var body: some View {
        VCard2(style: .well) {
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                HStack(spacing: V8.S.gapS) {
                    // 点用**容器档**（饱和度更高的"信号灯"），文字用**值档**（过 AA 的深色）。
                    // 同一个红族两档各司其职：点要跳出来，字要读得清。
                    Circle()
                        .fill(V8.C.dangerFill)
                        .frame(width: V8.S.gapS, height: V8.S.gapS)
                        .accessibilityHidden(true)
                    Text(what)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.danger)
                }
                // 2026-11-06（V9 · 液态仪器）：失败态头部加一条 danger 色带 ——
                // 4pt 圆头短杠贴在"什么失败"下面，语义与视觉同时强调（不只是文字变红）。
                Capsule()
                    .fill(V8.C.dangerFill)
                    .frame(width: V8.G.chipDot * 6, height: V8.G.chipDot / 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                Text(why)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(next)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(action: retry) {
                        Text(actionTitle)
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.accent)
                            .frame(minHeight: V8.H.min)
                    }
                    .buttonStyle(V8PressStyle())
                }
                if let raw {
                    VStack(alignment: .leading, spacing: V8.S.gapXS) {
                        Button {
                            showsRaw.toggle()
                        } label: {
                            Text(showsRaw ? "收起技术细节" : "技术细节")
                                .font(V8.T.micro)
                                .foregroundStyle(V8.C.ink4)
                                .frame(minHeight: V8.H.min)
                        }
                        .buttonStyle(V8PressStyle())
                        if showsRaw {
                            Text(raw)
                                .font(V8.T.micro)
                                .foregroundStyle(V8.C.ink4)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 8. 忙态

struct VBusy: View {
    let text: String

    var body: some View {
        HStack(spacing: V8.S.gapS) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
        }
        .frame(minHeight: V8.H.min)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - 9. 下钻链接行（彩色文字 + 灰 chevron + 下方数值）

struct VLinkRow: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        var unit: String? = nil
        let action: () -> Void
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: V8.S.gapL) {
            ForEach(items) { item in
                Button(action: item.action) {
                    VStack(alignment: .leading, spacing: V8.S.gapXS) {
                        HStack(spacing: V8.S.gapXS) {
                            Text(item.title)
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.accent)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(V8.T.micro)
                                .foregroundStyle(V8.C.ink4)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: V8.S.gapXS) {
                            Text(item.value)
                                .font(V8.T.value)
                                .foregroundStyle(V8.C.ink1)
                                .monospacedDigit()
                            if let unit = item.unit {
                                Text(unit)
                                    .font(V8.T.micro)
                                    .foregroundStyle(V8.C.ink4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: V8.H.min)
                }
                .buttonStyle(V8PressStyle())
                .accessibilityLabel(item.title + "，" + item.value + (item.unit ?? ""))
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

// MARK: - 10. 信息按钮（i）

struct VInfoDot: View {
    let title: String
    let bodyText: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Text("i")
                .font(V8.T.micro)
                .fontWeight(.semibold)
                .foregroundStyle(V8.C.ink4)
                .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
                .background(Circle().fill(V8.C.well))
                .frame(minWidth: V8.H.min, minHeight: V8.H.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("关于" + title + "的说明")
        .sheet(isPresented: $showing) {
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                Text(title)
                    .font(V8.T.headline)
                    .foregroundStyle(V8.C.ink1)
                Text(bodyText)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(V8.S.gapXL)
            .presentationDetents([.medium])
        }
    }
}

// MARK: - 11. 英雄数（大数 + 微标）

struct VHeroNumber: View {
    let value: String
    var unit: String? = nil
    var tint: Color = V8.C.accent
    var font: VFont = V8.T.heroL

    var body: some View {
        VStack(spacing: V8.S.gapXS) {
            Text(value)
                .font(font)
                .foregroundStyle(tint)
                .monospacedDigit()
                .tracking(V8.G.heroNumberTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(V8.T.micro)
                    .foregroundStyle(tint)
                    .tracking(V8.G.heroLabelTracking)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value + (unit ?? ""))
    }
}

// MARK: - 12. 两列读数

struct VStatPair2: View {
    struct Item: Identifiable {
        // 2026-11-05（全技能审核）：id 在 body 里每次重新生成 UUID，ForEach 身份每次全变。
        // 两列读数本来就是由 label+value 唯一确定的，用稳定派生值。
        var id: String { label + "|" + value }
        let label: String
        let value: String
        var unit: String? = nil
    }

    let items: [Item]
    /// 2026-11-05（全技能审核 · Dynamic Type）：V7 的 VStatPair 早已在 AX 档改竖排，
    /// V8 这里却永远横排 —— AX 档每列只剩一半宽度，两个读数互相挤压。照回 V7 的 AnyLayout 分支。
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: V8.S.gapS))
            : AnyLayout(HStackLayout(alignment: .top, spacing: V8.S.gapL))
        layout {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 && !typeSize.isAccessibilitySize {
                    Rectangle()
                        .fill(V8.C.line)
                        .frame(width: V8.S.hair)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text(item.label)
                        .font(V8.T.label)
                        .foregroundStyle(V8.C.ink4)
                    HStack(alignment: .firstTextBaseline, spacing: V8.S.gapXS) {
                        Text(item.value)
                            .font(V8.T.value)
                            .foregroundStyle(V8.C.ink1)
                            .monospacedDigit()
                        if let unit = item.unit {
                            Text(unit)
                                .font(V8.T.micro)
                                .foregroundStyle(V8.C.ink4)
                        }
                    }
                }
                // 2026-11-06（V9 · 液态仪器）：读数落在一块"沉下去的凹槽"里 ——
                // well 底色 + 顶缘暗缘（凹陷的物理暗示）。数字从"飘在卡面上"变成
                // "嵌在面板读数窗里"，与刻度盘的玻璃凸台形成凹凸对偶。
                .padding(.horizontal, V8.S.gapM)
                .padding(.vertical, V8.S.gapS)
                .background(
                    RoundedRectangle(cornerRadius: V8.R.inset, style: .continuous)
                        .fill(V8.C.well)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: V8.R.inset, style: .continuous)
                        .strokeBorder(V8.C.shadow, lineWidth: V8.S.hair)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 12·补 横向滚动容器（iOS 27：隐藏指示器只用 .scrollIndicators）

/// 横向滚动的芯片行 / 卡片行。全 App 唯一入口。
///
/// 2026-11-05（全技能审核 · iOS 27 API）：`ScrollView(.horizontal, showsIndicators: false)`
/// 的初始化器参数已随 iOS 17 软弃用，正确写法是 `.scrollIndicators(.hidden)`。
/// 全仓 43 处如果各写一遍，迟早有一处漏掉；收成一个组件后，指示器策略只有一份。
struct VHScroll<Content: View>: View {
    var showsIndicators: Bool = false
    private let content: Content

    init(showsIndicators: Bool = false, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal) {
            content
        }
        .scrollIndicators(showsIndicators ? .visible : .hidden)
    }
}

// MARK: - 13. 页面脚手架（参考图没有导航栏大标题：内容从状态栏下方开始）

struct VPage<Chips: View, Content: View>: View {
    let title: String
    var lead: String? = nil
    // 2026-11-06（V9 · 液态仪器）：每页自己的"大气色"。默认品牌蓝；
    // 五个根页各传一档（门=品牌 / 钥匙=紫 / 台账=靛 / 家=绿 / 设置=石墨），
    // 让每个 Tab 有可辨认的光色身份，而不是同一张蓝纸。
    var atmosphere: V8Atmosphere = .brand
    @ViewBuilder var chips: () -> Chips
    @ViewBuilder var content: () -> Content
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 2026-11-05（Round 3 · 专业 iOS 27 重构）：这一页原来把 34pt 的「判断句」
                // 当页面大标题，导航栏里什么都没有 —— 26 个页面全部是「无标题 + 自绘大标题」
                // 的非原生结构，也是「丑」的最大来源。现在：
                //   · 标题 → 系统 navigationTitle（根页 large / 子页 inline，见文件末尾）
                //   · 下面这句话 → 22pt status 行，只陈述状态，不再冒充标题
                //   · lead → 15pt 次级说明（原 22pt）
                Text(title)
                    .font(V8.T.pageStatus)
                    .foregroundStyle(V8.C.ink1)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .padding(.horizontal, V8.S.gutterText - V8.S.gutterCard)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
                if let lead {
                    Text(lead)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .lineSpacing(1.5)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapXS)
                        .fixedSize(horizontal: false, vertical: true)
                }
                chips()
                    .padding(.top, V8.S.gapM)
                VStack(alignment: .leading, spacing: V8.S.gapCard) {
                    content()
                }
                .padding(.top, V8.S.gapL)
            }
            .padding(.horizontal, V8.S.gutterCard)
            .padding(.bottom, V8.S.gapXL + (TabBarMode.native ? 0 : V8.S.hTabBar + V8.S.tabBarBottom))
        }
        // 2026-11-06（V9 · 液态仪器）：页面背景从"一张平纸"升级为"有大气层的面板"。
        // bgTop → bgBottom 纵向天光 + 顶部一团品牌色辉光（玻璃栏滚过时有东西可折射）
        // + 尾部一团冷紫辉光（页面收尾的层次）。全部属于内容层 —— HIG Materials：
        // 内容层的丰富靠色彩与光照；玻璃质感仍只属于功能层（Tab 栏 / 滑块）。
        .background(
            ZStack {
                LinearGradient(
                    colors: [V8.C.bgTop, V8.C.bgBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                GeometryReader { geo in
                    let w = geo.size.width
                    VStack(spacing: 0) {
                        // 顶部辉光：偏右上，本页大气色
                        Circle()
                            .fill(atmosphere.top)
                            .frame(width: w * 1.1, height: w * 1.1)
                            .blur(radius: w * 0.28)
                            .offset(x: w * 0.28, y: -w * 0.42)
                        Spacer(minLength: 0)
                        // 尾部辉光：偏左下，与本页大气色呼应的第二色
                        Circle()
                            .fill(atmosphere.bottom)
                            .frame(width: w * 0.95, height: w * 0.95)
                            .blur(radius: w * 0.30)
                            .offset(x: -w * 0.30, y: w * 0.10)
                    }
                    .frame(width: w)
                }
            }
            .ignoresSafeArea()
        )
        .scrollIndicators(.hidden)
        // 标题交给系统：根页 large（iOS 27 的 Liquid Glass 大标题会随滚动收起），
        // 子页 inline（详情页不该再有一个占半屏的大标题）。
        .navigationTitle(router.currentTitle)
        .navigationBarTitleDisplayMode(router.currentDest == nil ? .large : .inline)
        // 2026-11-05（对抗审查 · UI/UX）：全仓 18 个含输入框的页面**没有一处**能收起键盘。
        // 数字键盘（.numberPad）没有 Return 键，用户在「新建密码 / 数量 / 端口」这类输入里
        // 一旦弹出键盘就可能挡着下面的主按钮，退不出去。VPage 是所有页面的滚动容器，
        // 在这里挂一次交互式收起，25 个页面一次覆盖。
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - 14. 危险确认（统一文案结构：做什么 / 后果 / 能不能撤销）

struct VConfirm: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    /// 后果说明。**必须写清"能不能撤销"**（现状 12 处里只有 2 处写了）。
    let consequence: String
    let confirmTitle: String
    var isDestructive: Bool = true
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button(confirmTitle, role: isDestructive ? .destructive : nil) {
                onConfirm()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(consequence)
        }
    }
}

extension View {
    /// V8 危险确认的统一入口。调用方只提供文案，不自己拼 dialog。
    func v8Confirm(
        isPresented: Binding<Bool>,
        title: String,
        consequence: String,
        confirmTitle: String,
        isDestructive: Bool = true,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(VConfirm(
            isPresented: isPresented,
            title: title,
            consequence: consequence,
            confirmTitle: confirmTitle,
            isDestructive: isDestructive,
            onConfirm: onConfirm
        ))
    }
}

// MARK: - 15. 导航行（工具入口：标题 + 说明 + 右侧读数 + chevron）

struct VNavRow: View {
    let title: String
    var detail: String? = nil
    var value: String? = nil
    /// 设置行的前置 SF Symbol（原生 Settings 语法：30pt 圆角图标砖）。
    var systemImage: String? = nil
    var iconTint: Color = V8.C.accent
    let action: () -> Void

    // 2026-11-06（V9 · 液态仪器）：图标砖从平色块升级为"受光的小玻璃砖" ——
    // 顶部叠 18% 白的纵向光照 + 顶缘发丝高光。原生设置 App 的图标砖正是这种光照。
    private var iconTile: some View {
        let shape = RoundedRectangle(cornerRadius: V8.G.iconTileRadius, style: .continuous)
        return shape
            .fill(iconTint)
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.24), lineWidth: V8.S.hair)
            }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: V8.S.gapM) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(V8.T.chipValue)
                        .foregroundStyle(V8.C.onAccent)
                        .frame(width: V8.G.iconTile, height: V8.G.iconTile)
                        .background(iconTile)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text(title)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                        // 2026-11-05（全技能审核 · Dynamic Type）：导航行标题在 AX 档会截断。
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink4)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel([title, detail ?? "", value ?? ""].filter { !$0.isEmpty }.joined(separator: "，"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 15·补 头像（首字圆，原生联系人语法）

/// 成员头像：姓名首字 + 类别色。零图片资源 —— 与 HHAvatar 同一判据，但走 V8 令牌。
struct VAvatar: View {
    let name: String
    var tint: Color = V8.D.fingerprint

    var body: some View {
        ZStack {
            // 2026-11-06（V9 · 液态仪器）：头像从一块 14% 平色圆升级为"受光玻璃珠" ——
            // 顶部提亮 26% 的纵向光照 + 底部 12% 品牌色沉底 + 顶缘高光描边。
            // 原生联系人列表的头像正是这种光照。
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.26), tint.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Circle()
                .strokeBorder(tint.opacity(0.35), lineWidth: V8.S.hair)
            Text(initial)
                .font(V8.T.chipValue)
                .foregroundStyle(tint)
        }
        .frame(width: V8.G.avatarRow, height: V8.G.avatarRow)
        .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "成" : String(trimmed.prefix(1))
    }
}

// MARK: - 15·补2 成员行（头像 + 名称 + 角色 + 右侧凭证数，原生联系人行语法）

/// 家页成员行的 V8 版本。原来用 VDataRow 的「彩色标签 + 名称」语法，
/// 每行开头都是「家人 家人 家人」—— 三个成员就是三遍同一类别词，是家页最模板化的一块。
/// 原生联系人行的识别是「头像 + 姓名 + 次级状态」，角色与状态并到一行小字里。
struct VMemberRow: View {
    let name: String
    let role: String
    var roleTint: Color = V8.D.fingerprint
    let status: String
    let keyCount: Int

    var body: some View {
        HStack(spacing: V8.S.gapM) {
            VAvatar(name: name, tint: roleTint)
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(name.isEmpty ? "未命名成员" : name)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Text(role + " · " + status)
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(1)
            }
            Spacer(minLength: V8.S.gapS)
            HStack(alignment: .firstTextBaseline, spacing: V8.S.gapXS) {
                Text(String(keyCount))
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink2)
                    .monospacedDigit()
                Text("枚")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
            }
        }
        .frame(minHeight: V8.H.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(role)，\(status)，名下 \(keyCount) 枚凭证")
    }
}

// MARK: - 16. 范围标（T26：给图形"量什么"的上下文）

/// 每个图形上方必须有一行"范围/单位"标。用 13.9pt 半粗，不用微标 —— 微标撑不起"量什么"。
struct VRangeCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(V8.T.caption)
            .fontWeight(.semibold)
            .foregroundStyle(V8.C.ink1)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 17. 可折叠说明（2026-11-05）
//
// 用途：把「原理 / 口径」类说明收起来，首屏只留一句标题。
// 不用于安全后果说明 —— 那些必须默认可见（删数据、密钥泄露、不可撤销）。
//
// 判定标准：这段话删掉会不会让人做错决定？会 ⇒ 不许折叠；不会 ⇒ 可以折叠。
struct VDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            Button {
                // 2026-11-05（全技能审核 · 动效）：原来用裸 easeInOut(0.18)，绕过 V8.M 令牌。
                // 改走 V8.M.move（会跟随「动效强度」分档），Reduce Motion 仍直接切换。
                withAnimation(reduceMotion ? nil : V8.M.move) { open.toggle() }
            } label: {
                HStack(spacing: V8.S.gapXS) {
                    Text(title)
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink4)
                }
                .frame(minHeight: V8.H.min)
            }
            .buttonStyle(V8PressStyle())
            .accessibilityLabel(title)
            .accessibilityHint(open ? "收起说明" : "展开说明")
            if open {
                content
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 18. 统一按压反馈（2026-11-05 全技能审核）
//
// V8 里曾全部用 .buttonStyle(.plain) —— iOS 上 plain 没有按压反馈，点击像没反应。
// 这里与 V7 的 PressStyle 同语义，但动效走 V8.M.snap（并受 MotionTier 分档）。
// 只做透明度 + 极小缩放，不改 bounds；Reduce Motion 时只保留透明度。
struct V8PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        V8PressBody(configuration: configuration)
    }

    private struct V8PressBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.72 : 1)
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
                .animation(reduceMotion ? nil : V8.M.snap, value: configuration.isPressed)
        }
    }
}
