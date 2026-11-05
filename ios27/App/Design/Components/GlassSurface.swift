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
// 用法：`VGlassSurface(cornerRadius: V.R.action) { 内容 }`，需要染色时传 `tint:`。
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

    /// 2026-11-01：**「增强对比度」也要退化成不透明**。
    ///
    /// `apple-design` 的 `hig/liquid-glass.md › Review checklist` 第 5 条：
    /// > Reduce Transparency gets an opaque fallback, **Increase Contrast gets stronger fills and borders**,
    /// > Reduce Motion drops morphing and refraction animation.
    ///
    /// 本轮之前只处理了 Reduce Transparency —— 开了「增强对比度」的用户看到的仍是半透明玻璃，
    /// 而系统在那一档期望的是**更实的填充与更明显的描边**。
    /// 玻璃的"半透明"在这一档就是可读性负担，所以直接走不透明分支（最强的一档）。
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { solid || contrast == .increased }

    var body: some View {
        if opaque {
            content
                // 2026-11-05（全技能审核 · V7/V8 双系统）：这里是 App 里唯一的自绘玻璃入口，
                // 却被 V8 的 Toast / 只读试验条调用 —— 退化底色还走 V7 的 V.C.card。
                // 统一到 V8 卡片色与 V8 线宽，保证「减少透明度」档的颜色与页面其余部分同源。
                .background(V8.C.card, in: .rect(cornerRadius: cornerRadius, style: .continuous))
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
                // 增强对比度时描边加粗一倍 —— 与"更强的描边"一致。
                .strokeBorder(stroke, lineWidth: contrast == .increased ? V8.S.hair * 2 : V8.S.hair)
        }
    }
}
