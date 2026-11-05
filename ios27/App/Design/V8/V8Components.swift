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
            .background(
                RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                    .fill(style.fill)
                    .shadow(
                        color: style.castsShadow ? V8.C.shadow : Color.clear,
                        radius: style.castsShadow ? V8.Z.cardShadowRadius : 0,
                        y: style.castsShadow ? V8.Z.cardShadowY : 0
                    )
            )
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
        // 2026-11-05（Round 3 · 专业 iOS 27）：点线是参考图的签名元素，但在真机上
        // 它读起来像「装饰性虚线」而不是原生分隔线。原生列表统一用 0.5pt 实线，
        // 这里直接复用结构分割线的颜色与粗细 —— 更安静，也更像系统设置。
        Rectangle()
            .fill(V8.C.line)
            .frame(height: V8.S.hair * (DB.store.getBool("kf_hc") ? 2 : 1))
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
        .background(
            Capsule(style: .continuous)
                .fill(selected ? V8.C.accent : V8.C.chipOff)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.isEmpty ? value : "\(label)，\(value)")
        .accessibilityAddTraits(chipTraits)
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
                            Capsule(style: .continuous).fill(V8.C.accent)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: V8.S.gapM) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(V8.T.chipValue)
                        .foregroundStyle(V8.C.onAccent)
                        .frame(width: V8.G.iconTile, height: V8.G.iconTile)
                        .background(
                            RoundedRectangle(cornerRadius: V8.G.iconTileRadius, style: .continuous)
                                .fill(iconTint)
                        )
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
            Circle().fill(tint.opacity(0.14))
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
