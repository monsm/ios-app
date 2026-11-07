// LensGlass.swift —— 解锁镜头的玻璃层（iOS 26+ 的**可变形**玻璃）。
//
// 为什么单独一层：镜头是全 App 唯一有「仪式感」的控件，它的玻璃也是唯一
// 需要**变形**的玻璃 —— 开锁成功时，那片玻璃会真的「推开」成一圈光，
// 而不是画一个假的缩放动画。
//
// 实现用 iOS 26 的两个新 API：
//   · `glassEffectID(_:in:)` —— 给这片玻璃一个稳定身份；
//   · `glassEffectTransition(.matchedGeometry)` —— 视图层级换掉时，它从旧形状**变形**过去。
// 两者必须配合 `GlassEffectContainer` 与 `@Namespace`。
//
// iOS 26 是本 App 的基线（工具链下限），所以这一层没有降级分支：
// 需要降级的只有 iOS 27 的新能力，它们收在 `Modern.swift`。
import SwiftUI

/// 可变形的镜头玻璃（iOS 26 基线能力）。
struct LensGlass26: View {
    var opened: Bool
    var namespace: Namespace.ID

    /// 深色下顶缘高光要收着：同样的白，在暗背景上会亮得发灰。
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { reduceTransparency || contrast == .increased }
    private var highlightOpacity: Double { scheme == .dark ? 0.16 : 0.30 }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            // 两个形状**共用一个 id**：开锁成功时 idle 那片被 opened 那片替换，
            // 系统在两者之间做几何匹配 —— 这就是「推开」的那一下。
            // 变形过渡挂在**被插入的那一片**上，不是常驻容器上。
            Group {
                if opened {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.tint(T.C.brassBright.opacity(0.45)), in: .circle)
                        .glassMorphID("lens", in: namespace)
                        .glassMorphTransition(.matchedGeometry)
                        .scaleEffect(1.34)
                } else {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.tint(GlassMetrics.tint), in: .circle)
                        .glassMorphID("lens", in: namespace)
                }
            }
            .overlay {
                Circle()
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
                Circle()
                    .strokeBorder(T.C.glassEdge, lineWidth: contrast == .increased ? 1 : GlassMetrics.stroke)
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
        }
        // 「减少透明度 / 增强对比度」下玻璃退场：只剩一圈边，形状还在。
        .opacity(opaque ? 0 : 1)
    }
}


