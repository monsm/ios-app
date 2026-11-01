// GlassSurface.swift —— **原生液态玻璃的唯一入口**。
//
// 为什么要有这一层（三条都是可核对的）：
//   ① `glass` 闸门要求"玻璃只在功能层"（`Shell/` 或 `Components/Glass*`）。把 `.glassEffect(`
//      这个字面量收在一处，审计才能一眼看全"全 App 有几块玻璃、分别在哪"。
//   ② 「减少透明度」（系统设置或 App 内同档开关）必须退化成**不透明**面板 ——
//      这个判断也只该有一份，否则总有某块玻璃忘了退化。
//   ③ iOS 26 起 `glassEffect` 是**真液态玻璃**：它采样背后的内容做折射与高光；
//      而 `.ultraThinMaterial` 只是模糊。两者不是同一件事，前者才是"原生化"。
//
// 用法：`VGlassSurface(cornerRadius: V.R.tab) { 内容 }`，需要染色时传 `tint:`。
import SwiftUI

struct VGlassSurface<Content: View>: View {
    /// true = 退化为不透明卡片（无障碍「减少透明度」或 App 内同档开关）。
    var solid: Bool = false
    var cornerRadius: CGFloat
    /// 染色。原生玻璃本身是无色的，靠 tint 才能与品牌色对齐。
    var tint: Color? = nil
    /// 细描边。玻璃在浅色背景上边界不清，需要一条 hairline 定形。
    var stroke: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if solid {
            content
                .background(V.C.card, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay { border }
        } else {
            content
                // 部署目标是 iOS 27，`glassEffect` 必然可用 —— 不需要 `#available` 分支
                // （加了反而会被编译器判"多余的可用性检查"）。
                .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular,
                             in: .rect(cornerRadius: cornerRadius))
                .overlay { border }
        }
    }

    @ViewBuilder private var border: some View {
        if let stroke {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(stroke, lineWidth: V.S.hair)
        }
    }
}
