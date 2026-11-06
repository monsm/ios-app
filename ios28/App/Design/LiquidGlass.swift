// LiquidGlass.swift —— 原生液态玻璃（iOS 26+ 的 `glassEffect`）的唯一入口。
//
// 为什么单独一层：
//   ① `.glassEffect` 采样的是**背后的真实内容**（折射 + 高光），与 `.ultraThinMaterial`
//      的模糊不是一回事。把材质参数收在一处，全 App 的玻璃口径才审计得清。
//   ② 「减少透明度」与「增强对比度」必须退化成不透明面板 —— 这个判断只该有一份。
//      系统在减少透明度档期望不透明背景，在增强对比度档期望更实的填充与更明显的描边。
//   ③ 玻璃分三层用，但**参数同源**：
//      · 浮层（Tab 栏 / 工具托盘 / 镜头 / 临时提示 / 胶囊按钮）—— 带黄铜染色；
//      · 控件（输入框 / 分段 / 选项胶囊 / 键盘键）—— 同色染色，可交互；
//      · 内容卡片（`GlassSurface`）—— 不染色，避免整页泛黄。
//      圆角、描边宽度、顶缘高光都取自下面的 `GlassMetrics`，各页面不再自己写。
//
// 与上一版（ios27）的关系：只取"原生玻璃 + 顶缘高光"这一材质做法，
// 不搬它的任何设计令牌或组件名。
import SwiftUI

/// 玻璃材质的唯一参数源。页面里不要再出现圆角 / 描边 / 染色字面量。
enum GlassMetrics {
    /// Tab 栏：接近胶囊的大圆角。
    static let barRadius: CGFloat = 30
    /// 工具托盘：比内容卡片更"厚"一点。
    static let trayRadius: CGFloat = 22
    /// 内容卡片。
    static let cardRadius: CGFloat = T.R.card
    /// 按钮 / 输入框 / 分段控件。
    static let controlRadius: CGFloat = T.R.control
    /// 键盘键、方形小控件。
    static let keyRadius: CGFloat = T.R.tile
    /// 统一的描边宽度（增强对比度档会加倍）。
    static let stroke: CGFloat = 0.5
    /// 浮层与控件共用的黄铜染色；内容卡片不染色。
    static let tint: Color = T.C.brassWash
}

private struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    /// 两档无障碍设置都退化成不透明：这是玻璃唯一的"关不掉就糟"的场景。
    private var opaque: Bool { reduceTransparency || contrast == .increased }
    private var edgeWidth: CGFloat { contrast == .increased ? 1 : GlassMetrics.stroke }
    /// 深色下顶缘高光要收着：同样的白，在暗背景上会亮得发灰。
    private var highlightOpacity: Double { scheme == .dark ? 0.16 : 0.30 }

    func body(content: Content) -> some View {
        if opaque {
            content
                .background(T.C.glassStrong, in: shape)
                .overlay {
                    shape.strokeBorder(T.C.glassEdge, lineWidth: edgeWidth)
                }
        } else {
            content
                .glassEffect(glass, in: shape)
                // 真实玻璃受光后上缘总有一条亮线。只加"厚度感"，不改变折射行为。
                .overlay {
                    shape
                        .fill(
                            LinearGradient(colors: [.white.opacity(highlightOpacity), .clear],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .mask(alignment: .top) {
                            Rectangle().frame(height: T.S.l)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay {
                    shape.strokeBorder(T.C.glassEdge, lineWidth: edgeWidth)
                }
        }
    }

    private var glass: Glass {
        var value = Glass.regular
        if let tint { value = value.tint(tint) }
        if interactive { value = value.interactive() }
        return value
    }
}

extension View {
    /// 真液态玻璃。`shape` 决定玻璃的形状与圆角；`tint` 让玻璃带上一点家的颜色。
    func liquidGlass<S: InsettableShape>(in shape: S,
                                         tint: Color? = nil,
                                         interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}
