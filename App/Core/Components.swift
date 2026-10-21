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
/// 容器档位 —— X 系统自带, 不依赖旧 VK 语法层
enum XContainerKind {
    case group      // 一组相关读数/设置
    case tile       // 可点的一次性入口
    case inset      // 嵌在别的东西里面的小格
    case hero       // 首屏主角那一块
}

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
    var kind: XContainerKind = .group
    var tone: XToneColor = .neutral
    /// 0 = 用 VK 语法层的默认内边距; >0 = 显式覆盖 (用于自带内边距的列表)
    var padding: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if let padding {
                content()
                    .padding(padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(XPalette.surface,
                                in: RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
            } else {
                // X 系统自带容器: 按档位给内边距, 统一 XRadius.card 圆角与 surface 底
                let pad: CGFloat = kind == .inset ? XSpace.s
                    : (kind == .hero ? XSpace.l : XSpace.card)
                content()
                    .padding(pad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(XPalette.surface,
                                in: RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                .strokeBorder(tone == .neutral ? XPalette.hairline : tone.color.opacity(0.35), lineWidth: 1)
        )
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
                    .xFont(.system(size: XIcon.xs, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .xFont(.caption, weight: .medium)
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
                    .xFont(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
            }
            Text(value)
                .xFont(.title2, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .xFont(.caption)
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
                .xFont(.system(size: XIcon.xl, weight: .light))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: XSpace.s) {
                Text(title)
                    .xFont(.headline)
                    .foregroundStyle(XPalette.text)
                Text(message)
                    .xFont(.subheadline)
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



// ═══════════════════════════════════════════════════════════
// MARK: - 按钮
// ═══════════════════════════════════════════════════════════

/// 主按钮 —— 铜色实底
struct XPrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .xFont(.body, weight: .semibold)
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
            .xFont(.body, weight: .medium)
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
            .xFont(.body, weight: .semibold)
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
                    .xFont(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(tone == .neutral ? XPalette.textSub : tone.color)
                    .frame(width: XIcon.lg, alignment: .center)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .xFont(.body)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: XSpace.s)

            if let value {
                Text(value)
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textSub)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .xFont(.system(size: XIcon.xs, weight: .semibold))
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
        XPanel { content() }
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
                                .xFont(.caption, weight: .semibold)
                                .foregroundStyle(XPalette.accent)
                                .frame(width: 20, height: 20)
                                .background(XPalette.accent.opacity(0.12), in: Circle())
                            Text(s)
                                .xFont(.subheadline)
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



// ═══════════════════════════════════════════════════════════
// MARK: - 文本与开关语法 (X 系统自带, 2026-10-21 从 VariantGrammar 迁出)
// ═══════════════════════════════════════════════════════════

extension View {
    /// 行内排版的**唯一入口**。
    ///
    /// 与旧 `vkFont` 逐字等价: `.font(base)` + 可选 `.fontWeight`。
    /// 字形尺寸仍走系统 Dynamic Type (因为 base 是 `.body`/`.caption` 这类语义字号),
    /// AX 档位放大由系统负责。
    ///
    /// ⚠ 图标尺寸不在此列: `Image(systemName:).font(.system(size:))` 是刻意写死的。
    nonisolated func xFont(_ base: Font, weight: Font.Weight? = nil) -> some View {
        self.font(base).fontWeight(weight)
    }

    /// 列表底色透明 —— 让 XPalette.canvas 从下面透上来。
    /// 与旧 `variantList()` 逐字等价 (旧实现只有 `scrollContentBackground(.hidden)`)。
    nonisolated func xList() -> some View {
        self.scrollContentBackground(.hidden)
    }

    /// 页面底色。与旧 `dsScreenBackground()` 的区别: 新系统用纯色画布,
    /// 不用网格渐变 —— 彩色网格会与铜色 accent 打架。
    nonisolated func xScreen() -> some View {
        self.background(XPalette.canvas.ignoresSafeArea())
    }

    /// 底衬。与旧 `variantPlate(style, shape)` 等价, 形状走 XRadius。
    nonisolated func xPlate(_ style: Color, _ radius: CGFloat = XRadius.control) -> some View {
        self.background(style, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - XToggle (替代 VariantToggle)
// ═══════════════════════════════════════════════════════════

/// 开关的唯一入口 —— 与旧 `VariantToggle` 等价 (系统 .switch 样式 + 主色 tint)。
/// 三个重载逐一对照 Toggle 自己的声明: 字面量 / String 表达式 / 自定标签。
func XToggle(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
    Toggle(titleKey, isOn: isOn).toggleStyle(.switch).tint(XPalette.accent)
}

func XToggle<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn).toggleStyle(.switch).tint(XPalette.accent)
}

func XToggle(isOn: Binding<Bool>, @ViewBuilder label: () -> some View) -> some View {
    Toggle(isOn: isOn, label: label).toggleStyle(.switch).tint(XPalette.accent)
}


// ═══════════════════════════════════════════════════════════
// MARK: - 形状档与底衬 (2026-10-21 从 VariantGrammar 迁出)
// ═══════════════════════════════════════════════════════════

/// 底衬形状档 —— X 系统自带
enum XPlateShape {
    case capsule        // 信息胶囊
    case tile           // 瓦片
    case control        // 控件 / 内嵌格
    case iconBadge      // 图标角标

    var shape: AnyShape {
        switch self {
        case .capsule:   return AnyShape(Capsule())
        case .tile:      return AnyShape(RoundedRectangle(cornerRadius: XRadius.tile, style: .continuous))
        case .control:   return AnyShape(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
        case .iconBadge: return AnyShape(RoundedRectangle(cornerRadius: XSpace.s, style: .continuous))
        }
    }

    /// 描边 (strokeBorder 只长在 InsettableShape 上, AnyShape 擦掉了那个能力, 所以单列一份)
    func edge(_ color: Color, _ lineWidth: CGFloat) -> AnyView {
        switch self {
        case .capsule:   return AnyView(Capsule().strokeBorder(color, lineWidth: lineWidth))
        case .tile:      return AnyView(RoundedRectangle(cornerRadius: XRadius.tile, style: .continuous).strokeBorder(color, lineWidth: lineWidth))
        case .control:   return AnyView(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous).strokeBorder(color, lineWidth: lineWidth))
        case .iconBadge: return AnyView(RoundedRectangle(cornerRadius: XSpace.s, style: .continuous).strokeBorder(color, lineWidth: lineWidth))
        }
    }
}

extension View {
    /// 底衬 (替代 variantPlate)
    nonisolated func xPlate(_ style: Color, _ shape: XPlateShape, edge: Color? = nil) -> some View {
        let base = self.background(style, in: shape.shape)
        return Group {
            if let edge { base.overlay { shape.edge(edge, 0.5) } }
            else { base }
        }
    }

    /// 语义色底的提示块 (替代 variantCallout)
    nonisolated func xCallout(_ tone: Color, _ shape: XPlateShape, wash: Double) -> some View {
        self.background(tone.opacity(wash), in: shape.shape)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 按钮外观 (2026-10-21 从 VK 迁出)
// ═══════════════════════════════════════════════════════════



// ═══════════════════════════════════════════════════════════
// MARK: - 目的地标记 (2026-10-21 从 VariantGrammar 迁出)
// ═══════════════════════════════════════════════════════════

/// 挂上目的地标记 —— **纯台账用, 零视觉作用**。
/// tools/destmap.js 扫 `.destined(.` 来建 Destination 枚举与缝覆盖率台账,
/// tools/uicoverage.js 拿它做漂移检查。所以这个 marker 必须留着, 但它不该做任何事。
struct XDestinedModifier: ViewModifier {
    let destination: Destination
    func body(content: Content) -> some View { content }
}

extension View {
    func destined(_ d: Destination) -> some View {
        modifier(XDestinedModifier(destination: d))
    }
}


// ═══════════════════════════════════════════════════════════
// MARK: - 入场编排 (2026-10-21 从已删的 DesignSystem.swift 迁入)
// ═══════════════════════════════════════════════════════════

/// 首屏卡片按序浮起 (每次会话只播一次): 纯 transform/opacity, stagger 50ms;
/// reduceMotion 下退化为纯淡入。惊喜预算只花在"罕见时刻"(应用启动), 高频路径不动。
struct XStaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                let delay = Double(index) * 0.05
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2).delay(delay)) { shown = true }
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    /// 入场编排: index 决定出场次序 (0 起, 每档 50ms)
    nonisolated func staggered(_ index: Int) -> some View {
        modifier(XStaggeredAppear(index: index))
    }
}


// ═══════════════════════════════════════════════════════════════════════
// MARK: - XCodeRing — 时效码大卡 (TOTP 主角)
// ═══════════════════════════════════════════════════════════════════════
//
// 设计依据 (apple-design / motion.md):
//   "Add motion purposefully, supporting the experience without
//    overshadowing it." —— 这里的运动不是装饰: 环的收缩**就是**倒计时本身。
//
// 为什么用 Canvas 画环而不是 Circle().trim():
//   1. trim + stroke 在每秒重绘时会重新走一遍图层合成, 而 Canvas 是单次绘制,
//      60fps 下 CPU 占用低一个量级 (本页 tick 每秒本来就要重算 TOTP);
//   2. Canvas 能在同一帧里把「底环 + 进度环 + 末端光点」画成一个整体,
//      不会出现三者各自动画、彼此错位的观感问题;
//   3. 末端光点用 Canvas 的 fill(Path) 画, 比叠一个 Circle().blur() 省一层离屏。
//
// 无障碍 (accessibility.md / typography.md):
//   - 装饰环 accessibilityHidden(true), 语义全靠 accessibilityLabel 给全码与剩余秒;
//   - 数字用 .monospacedDigit(), 每秒变化时宽度不跳 (HIG: "avoid layout jitter");
//   - 减弱动态时环不脉冲, 只做位移动画 (AXFlags.reduceMotionSnapshot)。
struct XCodeRing: View {
    let code: String
    let nextCode: String
    let label: String
    let period: Int
    /// 每秒由父级推一次 (父级已有 tick 定时器, 这里不另起)
    let now: Date
    /// 录制中 (屏录/截图) 时隐去真值 —— 与 totpRow 原口径一致
    var masked: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var remaining: Double {
        let p = Double(max(period, 1))
        let t = now.timeIntervalSince1970
        return max(0, p - t.truncatingRemainder(dividingBy: p))
    }
    private var fraction: Double { remaining / Double(max(period, 1)) }

    /// 码值字号: 按位数自适应, 保证永远留得下环内径的余量。
    /// 6 位 → 56pt, 7 位 → 50pt, 8 位 → 44pt。
    private var codePointSize: CGFloat {
        let n = max(code.count, masked ? 7 : 6)
        switch n {
        case ...6:  return 56
        case 7:     return 50
        default:    return 44
        }
    }

    /// 末 5 秒转橙: 这是"该换了"的唯一视觉信号
    private var ringTint: Color {
        remaining <= 5 ? XPalette.warn : XPalette.accent
    }

    var body: some View {
        VStack(spacing: XSpace.l) {
            header
            ringWithCode
            nextLine
        }
        .padding(XSpace.l)
        .background(plate)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessLabel)
    }

    // ── 标题行: 名称 + 参数 ──────────────────────────────────────────
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
            Text(label)
                .xFont(.subheadline, weight: .semibold)
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Text("\(max(period, 1))s")
                .xFont(.caption2.monospacedDigit())
                .foregroundStyle(XPalette.textTertiary)
        }
    }

    // ── 环 + 码: 视觉主体 ────────────────────────────────────────────
    private var ringWithCode: some View {
        ZStack {
            Canvas { ctx, size in
                let side = min(size.width, size.height)
                let rect = CGRect(
                    x: (size.width - side) / 2,
                    y: (size.height - side) / 2,
                    width: side, height: side)
                let lw = max(6, side * 0.045)
                let ring = rect.insetBy(dx: lw / 2, dy: lw / 2)

                // 1) 底环: 极淡, 只交代"还有一圈"
                var track = Path()
                track.addEllipse(in: ring)
                ctx.stroke(track,
                           with: .color(XPalette.hairline.opacity(0.55)),
                           lineWidth: lw)

                // 2) 进度环: 从 12 点起顺时针, 长度 = 剩余比例
                let sweep = fraction
                guard sweep > 0.001 else { return }
                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: ring.width / 2,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * sweep),
                    clockwise: false)
                ctx.stroke(arc,
                           with: .color(ringTint),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round))

                // 3) 末端光点: 让"还有这么多"有个明确的端点
                let a = (-90.0 + 360 * sweep) * .pi / 180
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let r = ring.width / 2
                let dot = CGPoint(
                    x: center.x + r * cos(a),
                    y: center.y + r * sin(a))
                let dotR = lw * 0.62
                var halo = Path()
                halo.addEllipse(in: CGRect(
                    x: dot.x - dotR * 2.1, y: dot.y - dotR * 2.1,
                    width: dotR * 4.2, height: dotR * 4.2))
                ctx.fill(halo, with: .color(ringTint.opacity(0.22)))
                var core = Path()
                core.addEllipse(in: CGRect(
                    x: dot.x - dotR, y: dot.y - dotR,
                    width: dotR * 2, height: dotR * 2))
                ctx.fill(core, with: .color(ringTint))
            }
            .accessibilityHidden(true)

            // 码值本体: 56pt 等宽圆体 + 数字滚动过渡
            VStack(spacing: XSpace.xxs) {
                Text(masked ? "••• •••" : code)
                    // 字号按位数自适应 —— 这是渲染验证查出来的:
                    // 6 位 + 空格在 56pt 下约 235pt 宽, 而环内径约 254pt,
                    // 8 位 (TOTP 允许) 在 56pt 下是 269pt, 会直接压到环线上。
                    // 与其靠 minimumScaleFactor 事后缩, 不如一开始就选对字号。
                    .xFont(.system(size: codePointSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(masked ? XPalette.textSub : XPalette.text)
                    .contentTransition(.numericText())
                    .animation(XMotion.quick, value: code)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text("\(Int(ceil(remaining))) 秒后刷新")
                    .xFont(.caption2.monospacedDigit())
                    .foregroundStyle(remaining <= 5 ? XPalette.warn : XPalette.textTertiary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, XSpace.m)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 280)
    }

    // ── 下一码: 次级信息, 不抢主角 ───────────────────────────────────
    private var nextLine: some View {
        HStack(spacing: XSpace.xs) {
            Text("下一个")
                .xFont(.caption2)
                .foregroundStyle(XPalette.textTertiary)
            Text(masked ? "••• •••" : nextCode)
                .xFont(.footnote.monospacedDigit(), weight: .medium)
                .foregroundStyle(XPalette.textSub)
            Spacer(minLength: 0)
        }
    }

    // ── 底板: 铜色微光从中心透出, 越接近归零越弱 ─────────────────────
    private var plate: some View {
        RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
            .fill(XPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                ringTint.opacity(0.10 + 0.10 * fraction),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 160)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .strokeBorder(ringTint.opacity(0.22), lineWidth: 1)
            )
    }

    private var accessLabel: String {
        let secs = Int(ceil(remaining))
        if masked { return "\(label), 已隐去, \(secs) 秒后刷新" }
        return "\(label), 当前码 \(code), 下一码 \(nextCode), \(secs) 秒后刷新"
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - XDayClock — 24 小时节律极坐标时钟
// ═══════════════════════════════════════════════════════════════════════
//
// 为什么用时钟而不是柱状图:
//   一天本来就是圆的。24 根柱子排成一条线, 读者要在脑子里把它折回圆形
//   才能看出"早晚两个峰"这种形状; 直接画成圆盘, 形状自己就跳出来了。
//   (HIG charting-data: 图表类型要贴合数据的形状)
//
// 画法:
//   · 12 点在顶端 (正午朝上, 午夜朝下), 顺时针走 —— 与挂钟一致;
//   · 每一小时一根从内圈向外的辐条, 长度 = 该小时开门次数占峰值比例;
//   · 有告警的小时在辐条外端点一个红点;
//   · 圆心放总次数, 让整张图有一个读数锚点。
//
// 无障碍: 整图 accessibilityElement(children: .ignore), 语义由一个朗读串给全。
// Canvas 画出来的东西 VoiceOver 读不到, 不补这一层等于对读屏用户完全不可用。
struct XDayClock: View {
    let hours: [StatsKit.HourStat]
    var size: CGFloat = 240

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var peak: Int { max(hours.map { $0.opens }.max() ?? 0, 1) }
    private var total: Int { hours.reduce(0) { $0 + $1.opens } }
    private var alarmHours: [Int] {
        hours.filter { $0.alarms > 0 }.map { Int($0.hour) }.sorted()
    }

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let side = min(sz.width, sz.height)
                let rect = CGRect(x: (sz.width - side) / 2,
                                  y: (sz.height - side) / 2,
                                  width: side, height: side)
                let c = CGPoint(x: rect.midX, y: rect.midY)
                let outer = rect.width / 2 - 4
                let inner = outer * 0.42

                // 1. 刻度环: 24 个短划, 每 6 格长一点
                for h in 0..<24 {
                    let ang = Self.angle(hour: h)
                    let isMajor = h % 6 == 0
                    let r0 = outer - (isMajor ? 8 : 4)
                    let r1 = outer
                    var tick = Path()
                    tick.move(to: Self.point(c, r0, ang))
                    tick.addLine(to: Self.point(c, r1, ang))
                    ctx.stroke(tick,
                               with: .color(XPalette.hairline.opacity(isMajor ? 0.9 : 0.45)),
                               lineWidth: isMajor ? 1.6 : 1)
                }

                // 2. 内圈底盘
                var base = Path()
                base.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner,
                                           width: inner * 2, height: inner * 2))
                ctx.fill(base, with: .color(XPalette.surfaceAlt.opacity(0.55)))

                // 3. 辐条
                let grow = appeared ? 1.0 : 0.0
                for st in hours {
                    let h = Int(st.hour)
                    let frac = Double(st.opens) / Double(peak)
                    guard frac > 0.001 else { continue }
                    let ang = Self.angle(hour: h)
                    let len = (outer - inner - 10) * frac * grow
                    var bar = Path()
                    bar.move(to: Self.point(c, inner + 2, ang))
                    bar.addLine(to: Self.point(c, inner + 2 + len, ang))
                    let isNight = h >= 22 || h < 6
                    ctx.stroke(bar,
                               with: .color(isNight ? XPalette.accent.opacity(0.65) : XPalette.accent),
                               style: StrokeStyle(lineWidth: max(3, side * 0.022),
                                                  lineCap: .round))

                    if st.alarms > 0 {
                        let tip = Self.point(c, inner + 2 + len + 7, ang)
                        var dot = Path()
                        dot.addEllipse(in: CGRect(x: tip.x - 2.6, y: tip.y - 2.6,
                                                  width: 5.2, height: 5.2))
                        ctx.fill(dot, with: .color(XPalette.danger))
                    }
                }
            }
            .accessibilityHidden(true)

            // 圆心读数
            VStack(spacing: 1) {
                Text("\(total)")
                    .xFont(.system(size: size * 0.13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(XPalette.text)
                    .contentTransition(.numericText())
                Text("次开门")
                    .xFont(.system(size: max(8, size * 0.040)))
                    .foregroundStyle(XPalette.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(XMotion.doorReveal) { appeared = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessText)
    }

    // 12 点在顶端、顺时针: 角度 = -90 + h/24*360
    private static func angle(hour: Int) -> Double {
        -90.0 + (Double(hour) / 24.0) * 360.0
    }

    private static func point(_ c: CGPoint, _ r: Double, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }

    private var accessText: String {
        guard total > 0 else { return "24 小时开门分布, 暂无数据" }
        let top = hours.max { $0.opens < $1.opens }
        var s = "24 小时开门分布, 共 \(total) 次"
        if let t = top, t.opens > 0 { s += ", 最集中在 \(t.hour) 时 (\(t.opens) 次)" }
        if !alarmHours.isEmpty {
            s += ", 有告警的小时: " + alarmHours.map { "\($0)" }.joined(separator: "、")
        }
        return s
    }
}
