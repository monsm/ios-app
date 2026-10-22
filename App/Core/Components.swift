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
    case group      // 一组相关读数/设置 (pad 16)
    case hero       // 首屏主角那一块 (pad 20 + 更宽描边 + 阴影)
    // 已删 case inset: 与 .tile 同因 —— 全仓零使用。
    // 留着会让读的人以为"有个更紧凑的档位可选"，实际选中只是把 padding 改成 8。
    // 已删 case tile: 它与 .group 拿到完全相同的 padding, 全仓零使用。
    // 留着会让读的人以为"有个更紧凑的档位可选", 实际选中也没变化。
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

/// 面板 —— 全 App **唯一**的卡片。
///
/// 2026-10-22 整层重做 (Black Canvas / Glass Instrument)。三条硬规则:
///
/// 1. **卡片永远是实色 surface, 圆角 24, 零投影。**
///    旧实现有四处违反: 圆角 16 (规范下限 20)、hero 带 0.22 黑投影
///    (黑底上的投影只会发脏)、hero 用"3% 铜洗染 + 5.5% 顶部微光"两层次渐变
///    (那是与 heroGradient 打架的第二套渐变语言, 且渐变卡一屏只许一张)。
///    层次靠**明度差分 + 描边**建立, 不靠阴影 —— 纯黑画布上阴影根本不可见。
///
/// 2. **content 层永不许用毛玻璃。** 玻璃只属于功能层 (Tab Bar / 浮层 / Sheet),
///    见 xGlass(in:)。卡片用玻璃 = 层搞错了。
///
/// 3. **一屏只有一个主角。** .hero 是全屏唯一允许的渐变卡 (heroGradient, r34),
///    所以它必须**每屏至多一张**。普通 .group 卡永远不渐变。
struct XPanel<Content: View>: View {
    var kind: XContainerKind = .group
    var tone: XToneColor = .neutral
    /// 0 = 用语法层的默认内边距; >0 = 显式覆盖 (用于自带内边距的列表)
    var padding: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    /// 内边距是**层级信号**：留白越多，越像主角。
    /// hero 多给 4pt：卡片整体大一圈，眼睛先落上去，再往下读。
    private var pad: CGFloat {
        if let padding { return padding }
        switch kind {
        case .hero:  return XSpace.card + 4      // 20
        case .group: return XSpace.card          // 16
        }
    }

    /// 圆角是**层级的第二个信号**: 主角卡更大更圆 (34), 普通卡 24。
    private var radius: CGFloat {
        kind == .hero ? XRadius.cardLg : XRadius.card
    }

    private var edgeColor: Color {
        if tone != .neutral { return tone.color.opacity(XOpacity.edge) }
        // group 卡在纯黑上只有 1.26:1 的明度差, 必须有一条能看见的描边;
        // hero 用更实的一档 —— 它要在同屏一堆 group 卡里第一个被看见。
        return kind == .hero ? XPalette.hairlineStrong : XPalette.hairline
    }

    var body: some View {
        content()
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(plate)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(edgeColor, lineWidth: 1)
            )
            // 卡片**零投影** (规范 6.3 明令)。这里刻意不写 .shadow ——
            // 不是忘了, 是黑底上投影只会把卡片边缘糊成一圈脏灰。
    }

    /// 卡片底。
    /// group = 纯 surface (#1C1C1E), 无渐变、无洗染。
    /// hero  = 规范 7.4 的 HeroCard: 全屏唯一渐变, r34。
    @ViewBuilder
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if kind == .hero {
            shape.fill(XGradient.hero)
        } else {
            shape.fill(XPalette.surface)
        }
    }
}
/// 卡内分隔线 —— 规范 §7.6「卡内全宽，**不内缩**」。
///
/// 它不只是那 1 物理像素：规范 §7.6 的「内部纵向节奏」表给了分隔线**上下各 14pt**、
/// 到下一组标签再 12pt。这张表是执行者最容易漏的一页 —— 只给内边距 16pt、
/// 元素之间全靠猜，做出来会「松一圈」：卡片看着厚，但读不出组与组的分界。
///
/// 所以留白挂在组件自己身上，而不是让每个调用点各写一遍 .padding。
struct XHairline: View {
    /// 水平内缩。默认 0 = 卡内全宽（规范要求的形态）。
    var inset: CGFloat = 0
    /// 上下留白。**默认 0** —— 因为绝大多数调用是「列表行分隔线」，
    /// 行自己的 `.padding(.vertical)` 已经给了留白，分隔线再补就会把行撑高。
    ///
    /// **2026-10-23 更正**：这里原来写着「本 App 没有多段指标卡 —— 所以这个参数保留、默认不用」。
    /// 那是假的：`CarePage.periodCard` 与 `HomeConsole.todaySection` 都是多段卡，而且都在传 14。
    /// 更要紧的是**传 14 也是错的** —— 规范 §7.6 的节奏表是「值→线 **14pt**」这个**净距**，
    /// 不是「线上下各补 14」。线补 14 再叠容器 12，净距成了 26，比规范松近一倍。
    ///
    /// 正确用法（见 CarePage.periodCard）：线不补白，用 `.padding(.top, 2)` 补足上方净距。
    var verticalPadding: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(XPalette.hairline)
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, inset)
            .padding(.vertical, verticalPadding)
            // 分隔线是纯装饰，不进无障碍树（读它只会打断 VoiceOver 的节奏）
            .accessibilityHidden(true)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 区块标题链接 (规范 §7.11)
// ═══════════════════════════════════════════════════════════

/// 卡内顶部的「区块标题 + chevron」—— 规范 §7.11。
///
/// 参考图里的 `Sleep ›` / `Fitness ›` 就是这一枚：它**不是**白色粗体标题，
/// 是一行灰色小字 + 一枚更淡的箭头。作用是「这张卡还能再进去一层」，
/// 同时不抢卡内主内容的视觉重量。
///
/// 规范给的四个数：
///   字号 14 Regular · textSecondary
///   箭头 chevron.right 12pt · rgba(235,235,245,0.45)
///   箭头距文字 4pt
///   位置 卡内顶部，距边 18pt
///
/// 为什么单独做一个组件: 之前各页要么写死 title、要么干脆没有进去的门 ——
/// 用户看到一张卡却不知道它可点。把它收成组件，'可进入'这件事才有一致的形状。
struct XCardLink: View {
    var title: String
    var action: () -> Void

    /// 规范 §7.11 的箭头透明度 0.45。
    private var arrowColor: Color { XPalette.specular.opacity(0.45) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: XSpace.xxs) {          // 箭头距文字 4pt
                Text(title)
                    .xFont(.subheadline)   // 14
                    .foregroundStyle(XPalette.textSub)
                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs, weight: .semibold))  // 12
                    .foregroundStyle(arrowColor)
            }
            // 视觉是 14pt 一行小字，命中补到 44 —— 这条链接是卡里唯一的入口，
            // 点不中等于这张卡进不去（与 chipLabel 同一口径）。
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("进入详情")
        .accessibilityAddTraits(.isButton)
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
                // 状态胶囊在状态切换时会换图标 (已连接 → 未连接、达标 → 待处理…)。
                // symbolEffect(.replace) 让新旧字形做一次变形过渡, 而不是硬切。
                // reduceMotion 由系统自动降级 (SF Symbols 的 replace 会退化成淡入淡出)。
                Image(systemName: systemImage)
                    .xFontExact(.system(size: XIcon.xs, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            Text(text)
                .xFont(.caption, weight: .medium)
                .contentTransition(.opacity)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, XSpace.s)
        .padding(.vertical, XSpace.xxs + 1)
        .background(tone.color.opacity(XOpacity.badge), in: Capsule())
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
    /// 单位 —— 规范 §7.16：与数值**同色**、**档位的 70%**、同字重、中间空一格、基线对齐。
    ///
    /// 为什么不做成「把单位拼进 value 字符串」：那样单位会拿到数值的字号与颜色。
    /// 规范给的反例正是这个 —— `665/750` 粉 + `CAL` 灰、或 `CAL` 与数字同大。
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .xFontExact(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
            }
            // §7.16 单位排版走 XValueUnit（全仓唯一实现）；§7.18 的按位数降档在这里套一层。
            XValueUnit(
                value: XMetric.display(value),
                unit: unit,
                style: .title2,
                weight: .semibold,
                scale: XMetric.overflowScale(digits: XMetric.digitCount(value)))
            .minimumScaleFactor(0.7)
                // 数值变化做滚动数字 (规范 11.1 的 numberRoll: easeInOut 0.25s)。
                // 磁贴里的读数是会变的 (告警率 / 天数 / 总次数), 硬切会让眼睛追不上。
                .contentTransition(.numericText())
                .animation(XMotion.numberRoll, value: value)
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
                .xFontExact(.system(size: XIcon.xl, weight: .light))
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
                // 纯色填充之上压一层竖向渐变 (上亮下暗) ——
                // 一点点的深度差就能让按钮从"贴纸"变成"实体"。
                // 渐变幅度刻意很小 (0.10 → 0.00), 在深色模式下也看不出色块分界。
                RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                    .fill(XPalette.accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [XPalette.specular.opacity(0.10), .clear],
                                    startPoint: .top, endPoint: .bottom)
                            )
                    )
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
                // 状态位: 忙碌时转圈, 空闲时显示图标。
                // 原来两态是硬切 —— 点下去图标"啪"地消失、转圈"啪"地出现。
                // ZStack + opacity 让两者交叠淡入淡出, 中间不会有一帧什么都没有。
                ZStack {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .opacity(busy ? 0 : 1)
                    }
                    ProgressView()
                        .controlSize(.small)
                        .tint(style == .primary ? XPalette.onAccent : XPalette.accentText)
                        .opacity(busy ? 1 : 0)
                }
                .frame(width: 20, height: 20)
                .animation(XMotion.quick, value: busy)

                Text(title)
                    .contentTransition(.opacity)
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
            // 图标徽章: 28pt 圆角底 + 图标。
            //
            // 原来图标裸放在行首, 与文字同一灰度 —— 一屏十几行长得一模一样,
            // 眼睛没有落点。加一层 12% 同色底之后, 每行左侧形成一列色点,
            // 扫读时先认位置再认字, 这是列表可读性的基本盘。
            // tone 仍沿用 XToneColor (neutral 走 textSub), 不新增配色维度。
            if let systemImage {
                ZStack {
                    RoundedRectangle(cornerRadius: XRadius.min, style: .continuous)
                        .fill((tone == .neutral ? XPalette.textSub : tone.color).opacity(XOpacity.badge))
                    Image(systemName: systemImage)
                        .xFontExact(.system(size: XIcon.sm, weight: .semibold))
                        .foregroundStyle(tone == .neutral ? XPalette.textSub : tone.color)
                }
                .frame(width: 28, height: 28)
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
                    .contentTransition(.numericText())   // 备份天数 / 门锁数变化时做数字滚动
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .xFontExact(.system(size: XIcon.xs, weight: .semibold))
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
/// 首屏主角卡 —— 就是 XPanel(kind: .hero) 的语义别名。
///
/// 修: 原来 body 写的是 `XPanel { content() }` (默认 kind: .group),
/// 而 .hero 在当时与 .group 像素级相同 —— 所以这个类型一直是个空壳。
/// 现在两个问题都修了: XPanel 的 .hero 有独立视觉, 这里也真的传 .hero。
/// 同时删掉从未被使用也从未生效的 `flair` 参数。
struct XHeroCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        XPanel(kind: .hero) { content() }
    }
}



/// 旧 GuidedEmptyView


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

/// 把 `XText` 的规范字号 + Dynamic Type 一起算出来。
///
/// `@ScaledMetric` 让 AX 档放大走系统惯例比例，而不是把 11pt 硬放大成 30pt。
/// 基准档由 `XText.relativeTo` 给（例如 caption2 按 caption2 的比例放大）。
struct XTextModifier: ViewModifier {
    let style: XText
    let weightOverride: Font.Weight?
    let design: Font.Design
    /// §7.18 数字溢出的降档系数（1.0 / 0.82 / 0.65）。只由 xFontScaled 传。
    var factor: CGFloat = 1

    @ScaledMetric private var scaled: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    init(style: XText, weightOverride: Font.Weight?, design: Font.Design = .default, factor: CGFloat = 1) {
        self.style = style
        self.weightOverride = weightOverride
        self.design = design
        self.factor = factor
        _scaled = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    /// 规范 §13.1：「**环不随字号缩放**」「AX3：displayNumber **允许降至 44pt**」。
    ///
    /// displayNumber 装在**固定尺寸**的环里 —— 跟着 Dynamic Type 放大会把数字顶出环外。
    /// 所以它走另一条路：不放大，AX 档反而降到规范给的 44。
    private var finalSize: CGFloat {
        if factor != 1 { return (style == .displayNumber ? min(scaled, DSFont.displayNumber) : scaled) * factor }
        guard style == .displayNumber else { return scaled }
        return typeSize.isAccessibilitySize ? 44 : min(scaled, DSFont.displayNumber)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: finalSize, weight: weightOverride ?? style.weight, design: design).monospacedDigit())
    }
}
extension View {
    /// 行内排版的**唯一入口** —— 字号取自规范 §4.2（见 `XText`）。
    ///
    /// 2026-10-22 审计修正：这里原来是 `.font(base).fontWeight(weight)`，
    /// 即把 SwiftUI 语义字号**原样透传**。于是全仓 766 处排版跑的是 HIG 默认值，
    /// 而规范 §4.2 明确要求全线下修一档（caption 12→11 / footnote 13→12 /
    /// subheadline 15→14 / body 17→16 / title2 22→19 / largeTitle 34→30）。
    ///
    /// 现在参数类型换成 `XText`（case 名与语义字号同名，调用点零改动），
    /// 尺寸与字重都由规范表给出，**Dynamic Type 仍由系统缩放**（按系统档作基准）。
    nonisolated func xFont(_ style: XText, weight: Font.Weight? = nil,
                           design: Font.Design = .default) -> some View {
        modifier(XTextModifier(style: style, weightOverride: weight, design: design))
    }

    /// 显式字号的**逃生门** —— 图表轴、量规数字、图标尺寸这些 XText 表达不了的场合。
    ///
    /// 2026-10-22：它原来叫 `xFont(_ base: Font, …)`。加了 `xFont(_ style: XText, …)` 之后
    /// 两个重载会**同时匹配** `.xFont(.footnote)` —— Swift 会报「重载歧义」，
    /// 而这种错在无编译器环境里只能靠推理发现。为了保证 `.xFontExact(.样式)` 唯一含义，
    /// 这条退路改名为 `xFontExact`：**名字里就写着「我绕过了规范字阶」**，
    /// grep 得到、闸门数得清，不会悄悄变成主流写法。
    nonisolated func xFontExact(_ base: Font, weight: Font.Weight? = nil) -> some View {
        self.font(base).fontWeight(weight)
    }



    /// 底衬。与旧 `variantPlate(style, shape)` 等价, 形状走 XRadius。
    nonisolated func xPlate(_ style: Color, _ radius: CGFloat = XRadius.control) -> some View {
        self.background(style, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// §7.18 数字溢出的降档入口 —— 与 `xFont` **同一个字号源**，只是整体乘一个系数。
    ///
    /// 为什么不直接用 `minimumScaleFactor`：那是「放不下才缩」，缩出来的比例逐条不同，
    /// 同一列两个数字会一大一小，读起来像排版错误。§7.18 给的是**按位数分档**的确定值。
    ///
    /// 也不直接用 `xFontExact(.system(size:))`：那会绕过字号表，等于在字阶之外又开一条路。
    func xFontScaled(_ style: XText, scale: CGFloat,
                     weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        modifier(XTextModifier(style: style, weightOverride: weight, design: design, factor: scale))
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
// MARK: - XCodeRing — 时效码大卡 (TOTP 主角)
// ═══════════════════════════════════════════════════════════
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
        case ...6:  return DSFont.displayNumber
        case 7:     return DSFont.displayNumber - 6
        default:    return DSFont.displayNumber - 12
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
                .xFontExact(.caption2.monospacedDigit())
                .foregroundStyle(XPalette.textSub)
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
                           with: .color(XPalette.hairline.opacity(XOpacity.track)),
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
                    .xFontExact(.system(size: XMetric.dataText(CGFloat(codePointSize)), weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(masked ? XPalette.textSub : XPalette.text)
                    .contentTransition(.numericText())
                    .animation(XMotion.quick, value: code)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text("\(Int(ceil(remaining))) 秒后刷新")
                    .xFontExact(.caption2.monospacedDigit())
                    .foregroundStyle(remaining <= 5 ? XPalette.warn : XPalette.textSub)
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
                .foregroundStyle(XPalette.textSub)
            Text(masked ? "••• •••" : nextCode)
                .xFontExact(.footnote.monospacedDigit(), weight: .medium)
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
                    .xFontExact(.system(size: XMetric.dataText(size * 0.13), weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(XPalette.text)
                    .contentTransition(.numericText())
                Text("次开门")
                    .xFontExact(.system(size: XMetric.dataText(max(8, size * 0.040))))
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

// ═══════════════════════════════════════════════════════════════════════
// MARK: - XBatteryGauge — 电量仪表环
// ═══════════════════════════════════════════════════════════════════════
//
// 门锁电量是这台设备唯一会"耗尽"的资源, 而它原来只是一个 78% 的数字。
// 数字看不出"还剩多少余量", 弧形看得出。
//
// 画法:
//   · 270° 开口弧 (底部留口, 像汽车油表), 从左侧 7:30 起顺时针;
//   · 底弧极淡, 前景弧按电量走, 三档变色: >20% 正常 / 11-20% 警告 / <=10% 危险;
//   · 弧末端一个圆点, 让"还剩多少"有个明确的边界;
//   · 圆心放百分数 + 下方一行状态词。
//
// 无障碍: 弧 accessibilityHidden, 语义由一个 label 给全 ——
// Canvas 的图形 VoiceOver 读不到, 不补这层等于没有。
struct XBatteryGauge: View {
    /// 0...100, nil = 还没读到
    let level: Int?
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var frac: Double {
        guard let l = level else { return 0 }
        return min(max(Double(l) / 100.0, 0), 1)
    }

    private var tint: Color {
        guard let l = level else { return XPalette.textTertiary }
        if l <= 10 { return XPalette.danger }
        if l <= 20 { return XPalette.warn }
        return XPalette.ok
    }

    /// 开口弧: 从左下 135° 起, 顺时针扫 270°
    private let startAngle: Double = 135
    private let sweepAngle: Double = 270

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let side = min(sz.width, sz.height)
                let rect = CGRect(x: (sz.width - side) / 2,
                                  y: (sz.height - side) / 2,
                                  width: side, height: side)
                let c = CGPoint(x: rect.midX, y: rect.midY)
                let lw = max(7, side * 0.085)
                let r = side / 2 - lw / 2 - 1

                // 底弧
                var track = Path()
                track.addArc(center: c, radius: r,
                             startAngle: .degrees(startAngle),
                             endAngle: .degrees(startAngle + sweepAngle),
                             clockwise: false)
                ctx.stroke(track,
                           with: .color(XPalette.hairline.opacity(XOpacity.track)),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round))

                // 前景弧
                guard shown > 0.001 else { return }
                let end = startAngle + sweepAngle * shown
                var arc = Path()
                arc.addArc(center: c, radius: r,
                           startAngle: .degrees(startAngle),
                           endAngle: .degrees(end),
                           clockwise: false)
                ctx.stroke(arc,
                           with: .color(tint),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round))

                // 末端圆点
                let a = end * .pi / 180
                let tip = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                let dr = lw * 0.42
                var dot = Path()
                dot.addEllipse(in: CGRect(x: tip.x - dr, y: tip.y - dr,
                                          width: dr * 2, height: dr * 2))
                ctx.fill(dot, with: .color(tint))
            }
            .accessibilityHidden(true)

            // 圆心读数
            VStack(spacing: 0) {
                if let l = level {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(l)")
                            .xFontExact(.system(size: XMetric.dataText(size * 0.28), weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(XPalette.text)
                            .contentTransition(.numericText())
                        Text("%")
                            .xFontExact(.system(size: XMetric.dataText(size * 0.13), weight: .medium, design: .rounded))
                            .foregroundStyle(XPalette.textSub)
                    }
                    Text(statusWord)
                        .xFontExact(.system(size: XMetric.dataText(max(9, size * 0.072)), weight: .medium))
                        .foregroundStyle(tint)
                } else {
                    Text("—")
                        .xFontExact(.system(size: XMetric.dataText(size * 0.26), weight: .semibold, design: .rounded))
                        .foregroundStyle(XPalette.textTertiary)
                    Text("未读到")
                        .xFontExact(.system(size: XMetric.dataText(max(9, size * 0.072))))
                        .foregroundStyle(XPalette.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animateTo(frac) }
        .onChange(of: frac) { _, v in animateTo(v) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.map { "电量 \($0)%, \(statusWord)" } ?? "电量未读到")
    }

    private func animateTo(_ v: Double) {
        if reduceMotion { shown = v }
        // 规范 §11.1「环形生长 easeOut 1.00s / delay 0.15」—— 就是这个 token。
        // 电量环与门厅开锁环是同一族图形, 生长曲线必须同源, 否则两个环"长得不一样"。
        else { withAnimation(XMotion.ringGrow) { shown = v } }
    }

    private var statusWord: String {
        guard let l = level else { return "未读到" }
        if l <= 10 { return "需要换电池" }
        if l <= 20 { return "偏低" }
        return "充足"
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - XCycleRing — 周期进度环
// ═══════════════════════════════════════════════════════════════════════
//
// 用于「还剩 N 天该做某事」这一类语义: 保养周期、耗材更换、证书到期。
// 与 XBatteryGauge 的区别在于它表达的是**时间进程**而不是**容量余量**,
// 所以弧是"已过去多少"而不是"还剩多少" —— 弧走得越满越该动手。
//
// 画法:
//   · 360° 整圈, 从 12 点顺时针;
//   · 底弧极淡, 前景弧 = 已过去的比例;
//   · 圆心: 大字天数 + 小字说明;
//   · 超过周期时整环变 warn 色并轻微脉冲 (reduceMotion 时不脉冲)。
struct XCycleRing: View {
    /// 已过去的天数 (可为负 = 还没开始)
    let elapsed: Int
    /// 总周期天数
    let period: Int
    /// 圆心大字 (调用方给, 比如 "3" 或 "该做了")
    let headline: String
    /// 圆心小字
    let caption: String
    /// 读屏用的**自然语句**（规范 §13.5 的格式：「睡眠分数 53，共 7 小时 42 分」）。
    ///
    /// 不给时退化成「值，标签」—— 那是兜底，不是好文案。
    var a11yText: String? = nil
    var size: CGFloat = 128

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var pulse = false

    private var frac: Double {
        guard period > 0 else { return 1 }
        return min(max(Double(elapsed) / Double(period), 0), 1)
    }
    private var overdue: Bool { elapsed >= period }
    private var tint: Color {
        if overdue { return XPalette.warn }
        if frac > 0.8 { return XPalette.warn }
        return XPalette.ok
    }

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let side = min(sz.width, sz.height)
                let rect = CGRect(x: (sz.width - side) / 2,
                                  y: (sz.height - side) / 2,
                                  width: side, height: side)
                let c = CGPoint(x: rect.midX, y: rect.midY)
                let lw = max(6, side * 0.08)
                let r = side / 2 - lw / 2 - 1

                var track = Path()
                track.addEllipse(in: CGRect(x: c.x - r, y: c.y - r,
                                            width: r * 2, height: r * 2))
                ctx.stroke(track,
                           with: .color(XPalette.hairline.opacity(0.5)),
                           lineWidth: lw)

                guard shown > 0.001 else { return }
                var arc = Path()
                arc.addArc(center: c, radius: r,
                           startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * shown),
                           clockwise: false)
                ctx.stroke(arc,
                           with: .color(tint),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
            .accessibilityHidden(true)

            VStack(spacing: 1) {
                Text(headline)
                    .xFontExact(.system(size: XMetric.dataText(size * 0.22), weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(XPalette.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(caption)
                    .xFontExact(.system(size: XMetric.dataText(max(8, size * 0.062))))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, XSpace.m)
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse ? 1.03 : 1)
        .onAppear {
            if reduceMotion { shown = frac }
            else { withAnimation(XMotion.doorReveal) { shown = frac } }
            startPulse()
        }
        .onChange(of: frac) { _, v in
            if reduceMotion { shown = v }
            else { withAnimation(XMotion.standard) { shown = v } }
        }
        .accessibilityElement(children: .ignore)
        // 规范 §13.5 的 VoiceOver 格式是**自然语句**，不是把两个词用逗号拼起来：
        //   「睡眠分数 53，共 7 小时 42 分」→ 读出来是一句话，不是一个值加一个标签。
        // 调用方给 a11yText 就用它；没给就退化成「值，标签」，并注明这是兜底。
        .accessibilityLabel(a11yText ?? "\(headline)，\(caption)")
        // 超期脉冲是无限循环 —— 切断隐式继承 (本仓 DESIGN-SPEC §2.5)。
        // 不做这一步时, 外层任何 animation 重算都会把这条循环曲线打断重来,
        // 表现为"呼吸偶尔卡一下", 而代码上完全看不出来。
        .transaction { $0.animation = nil }
    }

    /// 超期时轻微脉冲提醒; reduceMotion 与未超期都不启动
    private func startPulse() {
        guard overdue, !reduceMotion else { return }
        // 规范 11.2: 动画不得超过 1.2s。原 1.6s 的超期脉冲收到 1.2s。
        // 提醒仍然持续, 只是一次明暗循环更短, 不会读成缓慢呼吸的背景色。
        // 事务切断点就在 body 里、读 pulse 的那个 Canvas 上 —— 见下方 `.transaction`。
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - XStepBar — 带标题的步骤指示器
// ═══════════════════════════════════════════════════════════════════════
//
// 多步向导最需要让人知道"我在第几步、还剩几步"。
// 原来是一排 4 个胶囊 (当前那个变长), 能看出进度但看不出步骤名。
//
// 现在每步有: 序号圆点 / 标题 / 连接线。当前步铜色实心,
// 已过步铜色描边带勾, 未到步灰色描边。
//
// 无障碍: 整条合成一个 label "第 2 步, 共 4 步, 设口令";
// 逐个圆点念会让读屏用户听一串没有上下文的数字。
struct XStepBar: View {
    let titles: [String]
    let current: Int
    /// 已完成步显示勾 (向导用), 关闭时只显示序号
    var marksDone: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                dot(i)
                Text(t)
                    .xFont(.caption2, weight: i == current ? .semibold : .regular)
                    .foregroundStyle(i == current ? XPalette.text
                                     : (i < current ? XPalette.textSub : XPalette.textSub))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, XSpace.xs)
                    .accessibilityHidden(true)
                if i < titles.count - 1 {
                    Rectangle()
                        .fill(i < current ? XPalette.accent.opacity(0.5) : XPalette.hairline)
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, XSpace.xs)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessText)
    }

    @ViewBuilder
    private func dot(_ i: Int) -> some View {
        ZStack {
            Circle()
                .fill(i == current ? XPalette.accent
                      : (i < current ? XPalette.accent.opacity(XOpacity.glow) : Color.clear))
            Circle()
                .strokeBorder(i <= current ? XPalette.accent : XPalette.hairline,
                              lineWidth: i == current ? 0 : 1.5)
            if marksDone && i < current {
                Image(systemName: "checkmark")
                    // 规范 §10：图标最小 12pt（原 11pt 差 1pt，但那是档位下限）。
                    .font(.system(size: XIcon.xs, weight: .bold))
                    .foregroundStyle(XPalette.accent)
            } else {
                Text("\(i + 1)")
                    .xFontExact(.system(size: XMetric.dataText(12), weight: .semibold).monospacedDigit())
                    .foregroundStyle(i == current ? XPalette.onAccent
                                     : (i < current ? XPalette.accent : XPalette.textTertiary))
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private var accessText: String {
        let n = min(max(current, 0), max(titles.count - 1, 0))
        let name = titles.isEmpty ? "" : titles[n]
        return "第 \(n + 1) 步, 共 \(titles.count) 步, \(name)"
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - XScrollLift — 卡片滚动时的连续形变
// ═══════════════════════════════════════════════════════════════════════
//
// iOS 17 的 scrollTransition 让"进出视口边缘"成为一个可映射的连续量。
// 用它给纵向卡片列表加两层微变化:
//   · 接近边缘 → 轻微缩小 (0.97) + 降低不透明度 (0.72)
//   · 进入中心 → 恢复 1.0 / 1.0
//
// 为什么值得做:
//   卡片列表滚动时, 原来所有卡片都是刚性平移 —— 边缘那几张"啪"地出现。
//   加了过渡之后, 视线会被自然带向屏幕中部, 眼睛不需要在硬边界上重新对焦。
//
// 幅度刻意保守: scale 只到 0.97, opacity 只到 0.72。
//   再大就成了"每张卡都在呼吸", 那是炫技, 不是可读性。
//
// 无障碍: reduceMotion 时什么都不做 —— 滚动中的连续缩放是最容易
//   引起前庭不适的效果之一, 这条必须给退路。
struct XScrollLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // scrollTransition 的闭包签名是 (content, phase) -> some VisualEffect ——
            // 两个参数, 第二个 ScrollTransitionPhase 才有 .value (-1…0…1)。
            // 原来写成单参数 `effect in effect.scaleEffect(... effect.value)` ——
            // effect 是 EmptyVisualEffect, 根本没有 .value, 编译直接失败。
            content.scrollTransition(.interactive, axis: .vertical) { effect, phase in
                effect
                    .scaleEffect(1 - 0.03 * abs(phase.value))
                    .opacity(1 - 0.28 * abs(phase.value))
            }
        }
    }
}

extension View {
    /// 纵向滚动列表里给卡片加"进出边缘连续形变"。
    /// 只给卡片用, 不要给整块 ScrollView 用。
    nonisolated func xScrollLift() -> some View {
        modifier(XScrollLift())
    }
}
// ═══════════════════════════════════════════════════════════
// MARK: - 分段控件（规范 §7.3 形态 B）
// ═══════════════════════════════════════════════════════════

/// 分段控件 —— 全仓**唯一**实现，对应规范 §7.3 的「形态 B · 胶囊式」。
///
/// 为什么要收成一个：§7.3 的自检是「**同一产品内只用一种，不得混用**」。
/// 本仓此前有三种：`.pickerStyle(.segmented)`（4 处，系统样式 —— 背景是
/// `tertiarySystemFill`，既不是规范的 0.06 也不是 0.18）、KeysPage 手搓的
/// 「axGlassCapsule + accent 洗底」（accent 洗底正是 §7.10 点名做错的那类）、
/// 以及别处各自写的。三种形态并存 = 三种视觉语言。
///
/// 规范给的数：
///   容器 `rgba(255,255,255,0.06)` · 高 **36** · r=999 · pad **2**
///   选中块 `rgba(255,255,255,0.18)` + **白字 Semibold**
struct XSegmented<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            // 元组元素 key path 是合法的（见 App/Core/LockStats.swift:134 的查证记录：
            // Swift 诊断表里没有 "key path cannot refer to tuple element" 这条）。
            // 真正会编译不过的是**单参 ForEach**：那版初始化器要求元素 Identifiable，
            // 而元组不能遵循协议 —— 所以这里显式给 id:。
            ForEach(Array(items.enumerated()), id: \.element) { _, item in
                let on = item == selection
                Button {
                    guard !on else { return }
                    withAnimation(XMotion.standard) { selection = item }
                    XHaptics.tick.impactOccurred()
                } label: {
                    ZStack {
                        if on {
                            // 选中块 rgba(255,255,255,0.18) —— 规范给的数，不是 accent 洗底
                            Capsule()
                                .fill(XPalette.segThumb)
                                .matchedGeometryEffect(id: "seg", in: pill)
                        }
                        Text(title(item))
                            .xFont(.subheadline, weight: on ? .semibold : .regular)
                            .foregroundStyle(on ? XPalette.segOn : XPalette.segOff)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(2)
        .background(Capsule().fill(XPalette.segTrack))
        // 容器高 36 = 32 的块 + 上下各 2 的 pad
        .frame(height: 36)
        .animation(XMotion.standard, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 数值 + 单位（规范 §7.16）
// ═══════════════════════════════════════════════════════════

/// 数值带单位 —— 全仓**唯一**实现。
///
/// 规范 §7.16 的五条：
///   颜色 **与数值同色**（不是灰）· 字号 **数值的 70%** · 字重同 · 中间空一格 · 基线对齐
///
/// 给的反例正是本仓原来的写法：`Text("\(days) 天")` ——
/// 单位与数值同一个字号、同一个颜色，"天" 和 "53" 一样大，
/// 数字于是读不成「一整块」。
///
/// 70% 落到档位上会偏（见 XText.unitStyle 的偏差表），但方向是对的：
/// 单位**必须**比数值小一档且同色，绝不能靠改灰来区分主次。
struct XValueUnit: View {
    var value: String
    var unit: String?
    var style: XText
    var weight: Font.Weight? = nil
    var color: Color = XPalette.text
    /// §7.18 的按位数降档系数（1.0 / 0.82 / 0.65）。
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .xFontScaled(style, scale: scale, weight: weight)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
            if let unit {
                Text(unit)
                    .xFont(style.unitStyle, weight: weight)
                    .foregroundStyle(color)   // §7.16：同色，不是灰
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 行内错误条
// ═══════════════════════════════════════════════════════════

/// 行内错误条 —— 动作失败时压在内容里的一条，不是全屏错误页。
///
/// 规范 §7.20.3 给了错误态的语法：图标 + 一句话 + 出路。
/// 本仓此前有三处各写了一遍，三处的图标尺寸（17 / 无 / 12）、字号（footnote / caption）、
/// 内边距（16 / 无 / 8）、圆角（12 / — / 8）全不一样 —— 同一个语义几种长相。
///
/// 尺寸按**下修后**的档位取：§7.20.3 原文写 图标 24 / 说明 13，
/// 但 §4.2 明写已全线下修 13→12，§10 又给了固定七档（24 不在七档内，取最近的 22）。
struct XInlineError: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: XIcon.xm, weight: .semibold))
                .foregroundStyle(XPalette.danger)
                .accessibilityHidden(true)
            Text(message)
                .xFont(.footnote)
                .foregroundStyle(XPalette.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XSpace.m)
        .background(XPalette.danger.opacity(XOpacity.wash),
                    in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
        // 颜色不是唯一信号（§13.3）：图标形状 + 文案本身就说明了这是失败。
        .accessibilityElement(children: .combine)
    }
}


// ═══════════════════════════════════════════════════════════════════════
// MARK: - XSkeleton — 首屏骨架屏
// ═══════════════════════════════════════════════════════════════════════
//
// 为什么需要:  三个列表页 (告警/记录/统计) 初次加载时只显示一个居中转圈,
// 画布是空的 —— 从"点进去"到"看到内容"之间有一段纯空白, 末了内容"啪"地铺满。
// 骨架屏把这段时间变成"内容正在成形", 视觉上连续得多。
//
// 形状对得上才有用: 骨架的块数/高度/圆角照最终卡片的节奏排,
// 不能是三个等宽横条 (那样内容一进来还是跳)。
//
// reduceMotion: 关掉流光扫动, 只留静态占位块。
// 流光是最容易让前庭敏感的人不适的效果之一, 这条必须给退路。
struct XSkeleton: View {
    /// 占位块的数量 (按目标页面的卡片数给)
    var blocks: Int = 3
    /// 每块高度
    var blockHeight: CGFloat = 108

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -1

    var body: some View {
        VStack(spacing: XSpace.l) {
            ForEach(0..<blocks, id: \.self) { i in
                block(index: i)
            }
        }
        .padding(.horizontal, XSpace.gutter)
        .padding(.vertical, XSpace.l)
        .onAppear {
            guard !reduceMotion else { return }
            // 规范 §7.20.1：微光是 **ease-in-out** 循环，周期 1.4s。
            // 原来是 .linear —— 匀速扫光的观感是"机器在跑"，ease-in-out 才像"光掠过"。
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = 2
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载")
        .accessibilityAddTraits(.updatesFrequently)
        // 骨架流光同样是无限循环 —— 切断隐式继承, 理由同上。
        .transaction { $0.animation = nil }
        // 规范 §7.20.1「消失：数据到达后 opacity 0.2s 淡出，不位移」。
        // 只给透明度、不给位移 —— 内容是到了，不是滑进来的。
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
    }

    @ViewBuilder
    private func block(index: Int) -> some View {
        // 每块内部的高度错开一点, 看起来像"不同的内容", 不像三个一样的条
        let innerHeights: [CGFloat] = index % 2 == 0 ? [14, 10] : [10, 14, 10]
        VStack(alignment: .leading, spacing: XSpace.s) {
            ForEach(Array(innerHeights.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(XPalette.surfaceAlt)
                    .frame(height: h)
                    .frame(maxWidth: h > 12 ? 180 : .infinity, alignment: .leading)
            }
        }
        .padding(XSpace.card)
        .frame(maxWidth: .infinity, minHeight: blockHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                .fill(XPalette.surface)
        )
        .overlay(
            // 流光: 一条窄的高光从左扫到右
            GeometryReader { geo in
                if !reduceMotion {
                    // 规范 §7.20.1：高光宽 **30%**（不是 45%）、颜色 **rgba(255,255,255,0.06)**。
                    // 原来写的是 specular(#C8C8D4) —— 那是一只偏冷的灰, 扫过时会把底色带偏。
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.30)
                        .offset(x: geo.size.width * sweep)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 偏差刻度条
// ═══════════════════════════════════════════════════════════════════
//
// 一根居中刻度条：中心 = 0，向左/向右表示正负偏差。
// 用于「锁钟偏差」这类"差多少"的量 —— 一行数字看不出严重程度，
// 一根条能。
//
// 放在 Components 里而不是页面里：它是形状定义，属于设计系统。
struct XSkewBar: View {
    /// 偏差值（秒）。正负决定方向
    let value: Int64
    /// 刻度封顶值 —— 超过它条子满格，但调用方仍显示真实数字
    var cap: Double = 300
    /// 判定色：准 / 提醒 / 警告
    var tone: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamped = Swift.min(Double(Swift.abs(value)) / Swift.max(cap, 1), 1.0)
            let half = clamped / 2
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(XPalette.surfaceAlt)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tone.opacity(0.55))
                    .frame(width: Swift.max(2, w * half))
                    .offset(x: value >= 0 ? w / 2 : w / 2 - w * half)
                Rectangle()
                    .fill(XPalette.textTertiary)
                    .frame(width: 1)
                    .offset(x: w / 2)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 崩溃面包屑
// ═══════════════════════════════════════════════════════════════════════
extension View {
    /// 记住最后打开的界面，异常退出后写进诊断档案。
    ///
    /// 为什么需要：真机"进去就闪退"这类问题，静态分析查不到 ——
    /// 只有 App 自己记下"我最后一次打开的是哪一页"，重启后才能对上号。
    /// 开销：一次 UserDefaults 比较（值没变不写盘）。
    func trackScreen(_ name: String) -> some View {
        onAppear { CrashGuard.markScreen(name) }
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 规范 §7 组件族 (2026-10-22 新增)
// ═══════════════════════════════════════════════════════════
//
// 这一族逐条对应设计规范的组件表。它们不是「又一个卡片」, 而是范式里有名字、
// 有数值、有自检条款的**主件** —— 缺了它们, 页面只能退化成一堆同形的 XPanel。

// ─────────────────────────────────────────── §7.2 StatChip
/// 顶部胶囊 —— 一屏最上面那条「我关心什么」的横向摘要。
///
/// **最容易做反的一个组件** (规范 §7.2 自检原话):
///   标签必须是**灰的、在上面**; 值必须是**白的、在下面**。
///   反过来就是错的 —— 那会让「睡眠」比「Low」更醒目, 而真正要读的是值。
///
/// 尺寸: 高 52, 圆角 **14 (圆角矩形, 不是胶囊)**, 图标 34 圆底, HStack(spacing:10)。
/// 规范正文写 52、自检写 56 —— 取 **52**: 56 是 Tab Bar 的高度 (§7.10),
/// 两者同高会让「胶囊行」与「导航栏」在下滑时连成一片, 层级读不出来。
struct XStatChip: View {
    var label: String
    var value: String
    /// 圆形图标: SF Symbol 名; nil 且给了 ringFraction 时画迷你环
    var systemImage: String? = nil
    /// 迷你环进度 0...1; nil = 画符号
    var ringFraction: Double? = nil
    var tint: Color = XPalette.accent
    /// compact 变体: 仅图标, 无文字 (规范 §7.2 compact)
    var compact: Bool = false
    var selected: Bool = false

    private var height: CGFloat { 52 }

    var body: some View {
        HStack(spacing: 10) {
            iconBadge
            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    // 标签在上、灰 —— 这是规范点名的顺序
                    Text(label)
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                    // 值在下、白粗
                    Text(value)
                        .xFont(.subheadline, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, compact ? 0 : 14)
        .frame(minWidth: compact ? height : 120)
        .frame(height: height)
        .background(
            // 规范 §7.2：背景是 **chipGradient**（渐变），不是实色。
            // 本仓原来用 XPalette.surfaceChip(#232326) 纯色 —— 而 XGradient.chip 早就定义好了、
            // 一处没用上。纯色胶囊在深卡上读起来是「贴上去的一块」，渐变才有「顶面受光」的厚度。
            RoundedRectangle(cornerRadius: XRadius.chip, style: .continuous)
                .fill(XGradient.chip)
        )
        .overlay(
            RoundedRectangle(cornerRadius: XRadius.chip, style: .continuous)
                .strokeBorder(XPalette.specular.opacity(selected ? 0.24 : 0.10), lineWidth: 0.5)
        )
        .frame(maxWidth: compact ? nil : .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label + ": " + value)
    }

    private var iconBadge: some View {
        ZStack {
            // 规范 §7.2：图标底色是 **rgba(255,255,255,0.08)**（纯白 8%）。
            // 原来用 specular(#C8C8D4) —— 那是一只偏冷的灰, 与规范给的纯白不是同一个颜色。
            Circle().fill(XPalette.veil)
            if let ringFraction {
                Circle()
                    .trim(from: 0, to: min(max(ringFraction, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .xFontExact(.system(size: XIcon.sm, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

// ─────────────────────────────────────────── §6.2 玻璃面
/// 功能层玻璃 —— **只给 Tab Bar / 浮层 / Sheet 用, 卡片永远不许用**。
///
/// 与 axGlass 的分工: axGlass 是「跟随系统降级」的入口 (降透明/高对比落回实底),
/// 这枚是「**配方写死**」的实现 —— 规范 §6.2 要求 fill 8% / 描边 0.5pt 12% /
/// 顶部高光 14%, 三个数都要对得上。降透明与高对比的退路复用同一条判据。
///
/// 玻璃是**自适应**的, 不能写死颜色 (规范 §6.2 的警告): 同一套 Tab Bar
/// 在亮背景上呈浅灰、在纯黑上呈近黑。这里靠 Material 吸背景, 8% 白只做提亮一档。
/// 验收时必须在亮/黑两种背景上各看一次 —— 只测一种必然翻车。
struct XGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill: Double = XOpacity.glassFill

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || XAppearance.highContrast {
            // 降低透明度 / 高对比: 玻璃降为实底 + 实描边 (规范 §13.4 强制要求)
            content
                .background(XPalette.surface, in: shape)
                .overlay(shape.strokeBorder(XPalette.hairlineStrong, lineWidth: 0.5))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(XPalette.specular.opacity(fill), in: shape)
                .overlay(shape.strokeBorder(XPalette.specular.opacity(XOpacity.glassEdge), lineWidth: 0.5))
                // 顶部微光: 局部镜面反射, 不是通栏直线 (规范 §7.10 的自检)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [XPalette.specular.opacity(0.14), .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// 功能层玻璃。仅 TabBar / 浮层 / Sheet, 禁止用于卡片。
    nonisolated func xGlass<S: InsettableShape>(in shape: S, fill: Double = XOpacity.glassFill) -> some View {
        modifier(XGlassSurface(shape: shape, fill: fill))
    }
}

// ─────────────────────────────────────────── §7.10 GlassTabBar
/// Tab Bar 的一项
struct XTabItem: Identifiable {
    let id: Int
    let title: String
    let symbol: String
    let selectedSymbol: String
    let tint: Color
}

/// 玻璃 Tab Bar —— 3–4 项, 每项图标 + 标签, 悬浮距物理底 20。
///
/// **规范里最容易做反的一处 (§7.10 自检)**: 选中态是「浮起来的微光胶囊」——
/// 白 8–10% 叠在栏体**之上**, 比栏体更亮。写成深色胶囊是把微光误读成了凹陷。
///
/// 而且**只有明度差不够**: 实测选中胶囊只比栏体亮 6 个色阶 (#0B0B0B → #111213),
/// 纯黑上几乎看不见。所以图标与标签必须**同时**变语义色 —— 颜色才是主要识别信号。
struct XGlassTabBar: View {
    let items: [XTabItem]
    @Binding var selection: Int
    var onSelect: ((Int) -> Void)? = nil

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let on = selection == item.id
                Button {
                    guard !on else { return }
                    selection = item.id
                    onSelect?(item.id)
                } label: {
                    ZStack {
                        // 选中: 白 10% 高光胶囊 —— 比栏体**更亮**, 不是更暗
                        if on {
                            Capsule()
                                .fill(XPalette.specular.opacity(XOpacity.tabSelected))
                                .overlay(Capsule().stroke(XPalette.specular.opacity(0.10), lineWidth: 0.5))
                                .frame(width: 64, height: 36)
                                .matchedGeometryEffect(id: "tabpill", in: pill)
                        }
                        VStack(spacing: 2) {
                            Image(systemName: on ? item.selectedSymbol : item.symbol)
                                .xFontExact(.system(size: XIcon.md, weight: on ? .semibold : .regular))
                                .contentTransition(.symbolEffect(.replace))
                            Text(item.title)
                                .xFont(.caption2, weight: on ? .semibold : .regular)
                        }
                        // 图标与标签**同时**变语义色
                        .foregroundStyle(on ? item.tint : XPalette.specular.opacity(XOpacity.tabIdle))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 56)
        .xGlass(in: Capsule())
        .animation(XMotion.standard, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}


// ─────────────────────────────────────────── 呼吸循环 (无限动画的唯一实现)
/// 无限循环的「呼吸」动画 —— 全仓**唯一**一处 `repeatForever` 的合法出口。
///
/// 为什么必须收成一处 (本仓 `docs/DESIGN-SPEC.md` §2.5 的原话):
///
/// > 呼吸环等无限循环动画必须**独立成视图**并用 `.transaction { $0.animation = nil }`
/// > 切断隐式继承，否则会和外层 `.animation(_, value:)` 抢同一批 scaleEffect/opacity 属性。
///
/// 抢属性的表现不是崩溃，是**抖动**：外层因为别的原因重算一帧，内层的循环曲线被打断重来，
/// 于是本该匀速的呼吸出现不规则的顿挫。这种缺陷在代码里完全看不出来，只有盯着看才发现。
///
/// 收成一处还买到三件事:
///   · `reduceMotion` 判断只写一次 (此前 5 处各写一遍)；
///   · 周期只有一个来源，改节奏不用找 5 个地方；
///   · 循环状态是**这个子视图自己的** @State —— 外层重算不会重置它。
struct XBreathing<Content: View>: View {
    /// 是否呼吸。false 时静态停在中位，不占任何动画预算。
    var active: Bool = true
    /// 呼吸的幅度（1.03 = 放大 3%）。超过 1.08 会读成心跳而不是呼吸。
    var scale: CGFloat = 1.03
    /// 一次完整呼吸的时长。默认 1.2s —— 规范 §11.2 的动画上限。
    var period: Double = 1.2
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var running: Bool { active && !reduceMotion }

    var body: some View {
        content()
            .scaleEffect(running ? (expanded ? scale : 2 - scale) : 1)
            .animation(running ? .easeInOut(duration: period).repeatForever(autoreverses: true) : nil,
                       value: expanded)
            // 断掉外层的隐式继承 —— 这一行就是 §2.5 说的那个 transaction。
            // 循环本身由上面那条 .animation(_, value:) 驱动; 这一行只负责挡住外部。
            .transaction { $0.animation = nil }
            .onAppear { expanded = running }
            .onChange(of: running) { _, now in expanded = now }
            .accessibilityHidden(true)
    }
}