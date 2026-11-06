// LiquidGlass.swift —— 原生液态玻璃（iOS 26+ 的 `glassEffect`）的唯一入口。
//
// 为什么单独一层：
//   ① `.glassEffect` 采样的是**背后的真实内容**（折射 + 高光），与 `.ultraThinMaterial`
//      的模糊不是一回事。把字面量收在一处，"全 App 有几块真玻璃"才审计得清。
//   ② 「减少透明度」与「增强对比度」必须退化成不透明面板 —— 这个判断只该有一份。
//      系统在减少透明度档期望不透明背景，在增强对比度档期望更实的填充与更明显的描边。
//   ③ 玻璃只给**浮在内容之上、承担功能**的层（Tab 栏、工具托盘、解锁镜头、临时提示）；
//      内容卡片仍走 `GlassSurface`（材料模糊），避免整页都在折射。
//
// 与上一版（ios27）的关系：只取"原生玻璃 + 顶缘高光"这一材质做法，
// 不搬它的任何设计令牌或组件名。
import SwiftUI

private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// 两档无障碍设置都退化成不透明：这是玻璃唯一的"关不掉就糟"的场景。
    private var opaque: Bool { reduceTransparency || contrast == .increased }

    func body(content: Content) -> some View {
        if opaque {
            content
                .background(T.C.glassStrong, in: shape)
                .overlay {
                    shape.strokeBorder(T.C.glassEdge, lineWidth: 0.5)
                }
        } else {
            content
                .glassEffect(glass, in: shape)
                // 真实玻璃受光后上缘总有一条亮线。只加"厚度感"，不改变折射行为。
                .overlay {
                    shape
                        .fill(
                            LinearGradient(colors: [.white.opacity(0.30), .clear],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .mask(alignment: .top) {
                            Rectangle().frame(height: T.S.l)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay {
                    shape.strokeBorder(T.C.glassEdge, lineWidth: 0.5)
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
    func liquidGlass<S: Shape>(in shape: S,
                               tint: Color? = nil,
                               interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}
