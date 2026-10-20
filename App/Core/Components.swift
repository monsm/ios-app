//
//  Components.swift
//  全新组件库 · 第二块基石
//
//  设计原则
//  ─────────────────────────────
//  1. 每个组件只做一件事, 没有"可选参数矩阵"
//  2. 所有视觉来自 Theme 令牌, 组件内不写魔法数字
//  3. 所有组件必须支持 Dynamic Type / VoiceOver / reduceMotion
//  4. 优先用系统控件, 只在系统控件表达不了时才自绘
//

import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════
// MARK: - 色调 (语义色的可传递载体)
// ═══════════════════════════════════════════════════════════

/// 语义色调 —— 让组件不直接依赖具体颜色, 便于统一降级
enum XToneColor {
    case neutral, accent, ok, warn, danger

    var color: Color {
        switch self {
        case .neutral: return XPalette.textSub
        case .accent: return XPalette.accent
        case .ok: return XPalette.ok
        case .warn: return XPalette.warn
        case .danger: return XPalette.danger
        }
    }

    var label: String {
        switch self {
        case .neutral: return "一般"
        case .accent: return "强调"
        case .ok: return "正常"
        case .warn: return "注意"
        case .danger: return "危险"
        }
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 基础容器
// ═══════════════════════════════════════════════════════════

/// 面板 —— 新设计里唯一的"卡片"。
///
/// 与旧 Card 的区别: 不用阴影, 用**描边 + 底色差**表达层次。
/// 阴影在深色模式会糊成一团, 描边在任何模式下都清晰。
struct XPanel<Content: View>: View {
    var kind: ContainerKind = .group
    var tone: XToneColor = .neutral
    @ViewBuilder var content: () -> Content

    var body: some View {
        VK.current.container(kind) { content() }
            .overlay(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .strokeBorder(tone == .neutral ? XPalette.hairline : tone.color.opacity(0.35), lineWidth: 1)
            )
    }
}

/// 内嵌区块 —— 面板里的次级分区, 用底色下沉表达
struct XInset<Content: View>: View {
    var padding: CGFloat = XSpace.control
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XPalette.surfaceAlt, in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
    }
}

/// 分隔线
struct XHairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(XPalette.hairline)
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, inset)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 状态
// ═══════════════════════════════════════════════════════════

/// 状态胶囊 —— 语义色 + 文字, 不单靠颜色区分
struct XStatusPill: View {
    var text: String
    var tone: XToneColor = .neutral
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: XSpace.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .vkFont(.system(size: XIcon.xs, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .vkFont(.caption, weight: .medium)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, XSpace.s)
        .padding(.vertical, XSpace.xxs + 1)
        .background(tone.color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tone.color.opacity(0.24), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tone.label): \(text)")
    }
}

/// 指标磁贴 —— 一个大数字 + 一个标签
struct XMetricTile: View {
    var value: String
    var label: String
    var tone: XToneColor = .neutral
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .vkFont(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
            }
            Text(value)
                .vkFont(.title2, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .vkFont(.caption)
                .foregroundStyle(XPalette.textSub)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XSpace.tile)
        .background(XPalette.surfaceAlt, in: RoundedRectangle(cornerRadius: XRadius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 空态 / 错误态
// ═══════════════════════════════════════════════════════════

/// 空态 —— 系统化, 不再每个页面自己写
struct XEmptyState: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: systemImage)
                .vkFont(.system(size: XIcon.xl, weight: .light))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: XSpace.s) {
                Text(title)
                    .vkFont(.headline)
                    .foregroundStyle(XPalette.text)
                Text(message)
                    .vkFont(.subheadline)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(XPrimaryButtonStyle())
            }
        }
        .padding(XSpace.xl)
        .frame(maxWidth: .infinity)
    }
}

/// 错误态 —— 与空态同构, 但用 danger 色调 + 重试
struct XErrorState: View {
    var title: String
    var message: String
    var retryTitle: String = "重试"
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "exclamationmark.triangle")
                .vkFont(.system(size: XIcon.xl, weight: .light))
                .foregroundStyle(XPalette.danger)
                .accessibilityHidden(true)

            VStack(spacing: XSpace.s) {
                Text(title)
                    .vkFont(.headline)
                    .foregroundStyle(XPalette.text)
                Text(message)
                    .vkFont(.subheadline)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(XSecondaryButtonStyle())
            }
        }
        .padding(XSpace.xl)
        .frame(maxWidth: .infinity)
    }
}

/// 加载态 —— 统一形状
struct XLoadingState: View {
    var message: String = "正在读取…"

    var body: some View {
        VStack(spacing: XSpace.m) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .vkFont(.subheadline)
                .foregroundStyle(XPalette.textSub)
        }
        .padding(XSpace.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 按钮
// ═══════════════════════════════════════════════════════════

/// 主按钮 —— 铜色实底
struct XPrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vkFont(.body, weight: .semibold)
            .foregroundStyle(XPalette.onAccent)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: XHit.min)
            .padding(.horizontal, XSpace.l)
            .background(
                RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                    .fill(XPalette.accent)
                    .opacity(configuration.isPressed ? 0.82 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(XMotion.quick, value: configuration.isPressed)
    }
}

/// 次按钮 —— 描边
struct XSecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vkFont(.body, weight: .medium)
            .foregroundStyle(XPalette.accentText)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: XHit.min)
            .padding(.horizontal, XSpace.l)
            .background(
                RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                    .fill(configuration.isPressed ? XPalette.surfaceAlt : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                    .strokeBorder(XPalette.accent.opacity(0.5), lineWidth: 1)
            )
            .animation(XMotion.quick, value: configuration.isPressed)
    }
}

/// 破坏性按钮 —— 危险色
struct XDestructiveButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vkFont(.body, weight: .semibold)
            .foregroundStyle(XPalette.danger)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: XHit.min)
            .padding(.horizontal, XSpace.l)
            .background(
                RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                    .fill(XPalette.danger.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .animation(XMotion.quick, value: configuration.isPressed)
    }
}

/// 忙碌按钮 —— 带进度, 防重复点击
struct XBusyButton: View {
    var title: String
    var systemImage: String? = nil
    var busy: Bool
    var style: Style = .primary
    var action: () -> Void

    enum Style { case primary, secondary, destructive }

    var body: some View {
        Button(action: action) {
            HStack(spacing: XSpace.s) {
                if busy {
                    ProgressView().controlSize(.small)
                        .tint(style == .primary ? XPalette.onAccent : XPalette.accentText)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(AnyButtonStyle(style))
        .disabled(busy)
        .accessibilityLabel(busy ? "\(title), 进行中" : title)
    }

    /// 把三种 ButtonStyle 收成一个 (SwiftUI 要求 ButtonStyle 是具体类型)
    private struct AnyButtonStyle: ButtonStyle {
        let kind: Style
        init(_ kind: Style) { self.kind = kind }
        func makeBody(configuration: Configuration) -> some View {
            switch kind {
            case .primary: XPrimaryButtonStyle().makeBody(configuration: configuration)
            case .secondary: XSecondaryButtonStyle().makeBody(configuration: configuration)
            case .destructive: XDestructiveButtonStyle().makeBody(configuration: configuration)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 行 (列表基元)
// ═══════════════════════════════════════════════════════════

/// 标准行 —— 左图标 + 标题 + 副标题 + 右侧值/箭头
///
/// 这是新设计里所有列表的唯一行形状。禁止再自造 row。
struct XRow: View {
    var systemImage: String? = nil
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var tone: XToneColor = .neutral
    var showsChevron: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack(spacing: XSpace.m) {
            if let systemImage {
                Image(systemName: systemImage)
                    .vkFont(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(tone == .neutral ? XPalette.textSub : tone.color)
                    .frame(width: XIcon.lg, alignment: .center)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .vkFont(.body)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .vkFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: XSpace.s)

            if let value {
                Text(value)
                    .vkFont(.subheadline)
                    .foregroundStyle(XPalette.textSub)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .vkFont(.system(size: XIcon.xs, weight: .semibold))
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: XHit.min)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 兼容层 (Core 层仍在用旧组件名)
// ═══════════════════════════════════════════════════════════

/// 旧 HeroCard 的替代 —— 新设计里不再有"英雄卡", 用 Panel 替代
struct XHeroCard<Content: View>: View {
    var flair: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Panel { content() }
    }
}

/// 旧 HeroStat
struct XHeroStat: View {
    var id: String
    var label: String
    var value: String
    var body: some View { XMetricTile(value: value, label: label) }
}

/// 旧 HeroPill
struct XHeroPill: View {
    var text: String
    var systemImage: String? = nil
    var body: some View {
        XStatusPill(text: text, tone: .accent, systemImage: systemImage)
    }
}

/// 旧 GuidedEmptyView
struct XGuidedEmptyView: View {
    var systemImage: String
    var title: String
    var message: String
    var steps: [String] = []
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: XSpace.l) {
            XEmptyState(systemImage: systemImage, title: title, message: message,
                       actionTitle: actionTitle, action: action)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: XSpace.s) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: XSpace.s) {
                            Text("\(i + 1)")
                                .vkFont(.caption, weight: .semibold)
                                .foregroundStyle(XPalette.accent)
                                .frame(width: 20, height: 20)
                                .background(XPalette.accent.opacity(0.12), in: Circle())
                            Text(s)
                                .vkFont(.subheadline)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(XSpace.l)
                .background(XPalette.surfaceAlt, in: RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
            }
        }
        .padding(XSpace.l)
    }
}

/// 旧 HeroTexture —— 新设计里材质由 DoorSurface 承担, 这里保留空实现
struct XHeroTexture: View {
    var body: some View { Color.clear }
}

/// 旧 HeroStats 命名空间 (Core 层读写它的可见性)
enum XHeroStats {
    static let all = ["firmware", "lockclock"]
    static var visible: Set<String> {
        Set(DB.store.get([String].self, "kf_hero_stats") ?? all)
    }
    static func shows(_ id: String) -> Bool { visible.contains(id) }
    static func setVisible(_ ids: [String]) {
        DB.store.set("kf_hero_stats", ids.filter { all.contains($0) })
    }
}

/// 旧 XFlowLayout(Core 层在用)
struct XFlowLayout: Layout {
    var spacing: CGFloat = XSpace.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if rows[rows.count - 1] + s.width + (rows[rows.count - 1] > 0 ? spacing : 0) > maxWidth {
                rows.append(s.width)
                rowHeights.append(s.height)
            } else {
                rows[rows.count - 1] += s.width + (rows[rows.count - 1] > 0 ? spacing : 0)
                rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], s.height)
            }
        }
        let h = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: maxWidth == .infinity ? rows.max() ?? 0 : maxWidth, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
