// GlassSlideToUnlock.swift —— **原生来电滑块样式的开锁控件**（功能层玻璃）。
//
// 2026-11-03（用户拍板）：手动开锁只留这一种 —— iOS 接电话那种滑块。
// 替代"按住 0.9 秒/轻点/双击/沿环拖游标"四套手势。视觉对齐系统来电 UI：
// 玻璃胶囊滑轨 + 圆形把手 + "滑动来开锁"渐隐提示文字，拖到最右触发一次。
//
// 玻璃归属：这是门页**主行动控件**（浮动功能层，契约 §6 表"浮动操作条"），且本文件
// 位于 Components/Glass* —— glass 闸门 allowlist 内。减少透明度/增强对比度时
// 经 VGlassSurface 同一入口退化为不透明。
import SwiftUI

struct GlassSlideToUnlock: View {
    /// 拖到最右触发一次。触发后控件复位由内部状态处理（busy 时禁用）。
    let onUnlock: () -> Void
    var busy: Bool = false

    @State private var offset: CGFloat = 0
    @State private var fired = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// **减少透明度 / 增强对比度时必须退化为不透明**。
    ///
    /// 2026-11-03（Liquid Glass 审计）：`contrast` 与 `reduceTransparency` 两个环境值
    /// 在文件里声明了却**从未被读取**（全文各只出现一次，就是声明本身）—— 也就是说
    /// 低视力用户打开"降低透明度"后，门页这个**主行动控件**仍然是半透明玻璃。
    /// 这是本仓唯一的开锁入口，不能只在默认外观下可用。
    private var solid: Bool { reduceTransparency || contrast == .increased }

    private var knobDiameter: CGFloat { 56 }
    private var trackHeight: CGFloat { 72 }

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - knobDiameter - 16
            ZStack(alignment: .leading) {
                // 滑轨：功能层玻璃胶囊。
                // 2026-11-03（截图）：纯 .glassEffect 在浅色背景上几乎看不见 —— 补一层发丝描边
                // 与极淡底色，让控件边界成立（HIG：控件必须有可辨的容器）。
                // 2026-11-03（Liquid Glass 审计）：原来滑轨与把手**各自一层 glassEffect**，
                // 两层玻璃嵌套（全仓无 GlassEffectContainer）。玻璃只保留滑轨这一层，
                // 把手改成实心色块 —— 它本来就是"按钮"，不需要采样背后内容。
                Group {
                    if solid {
                        Capsule().fill(V.C.card)
                    } else {
                        Capsule().fill(.clear)
                            .glassEffect(.regular.tint(V.C.card.opacity(0.55)), in: Capsule())
                    }
                }
                .overlay {
                    Capsule().strokeBorder(V.C.hairlineSoft, lineWidth: V.S.hair)
                }
                    .overlay {
                        Text(offset > travel * 0.25 ? "" : "滑动来开锁")
                            .font(V.F.bodyStrong)
                            .foregroundStyle(V.C.text2)
                            .frame(maxWidth: .infinity)
                    }
                // 把手：圆形玻璃钮
                Circle()
                    .fill(solid ? V.C.blue : V.C.blue.opacity(0.92))
                    .overlay { Circle().strokeBorder(V.C.blue.opacity(0.35), lineWidth: V.S.hair) }
                    .frame(width: knobDiameter, height: knobDiameter)
                    .overlay {
                        Image(systemName: "chevron.right.2")
                            .font(V.F.icon18Medium)
                            .foregroundStyle(V.C.blue)
                    }
                    .offset(x: 8 + min(offset, travel))
                    .gesture(slideGesture(travel: travel))
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
        .opacity(busy ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("滑动开锁")
        .accessibilityHint("向右拖动圆形按钮到底，松手即开锁")
        .accessibilityAddTraits(.isButton)
        // 2026-11-04（读屏旁路）：busy 时拖动路径有 `guard !busy, !fired` 拦着，
        // 而这条 accessibilityAction 原来直接调 onUnlock() —— 读屏用户（或旁路工具）
        // 可以在开锁链进行中再次触发。同一道防线补齐。
        .accessibilityAction {
            guard !busy, !fired else { return }
            onUnlock()
        }
    }

    private func slideGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                guard !busy, !fired else { return }
                offset = max(0, min(travel, v.translation.width))
                if offset >= travel { fire() }
            }
            .onEnded { _ in
                guard !fired else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
            }
    }

    private func fire() {
        fired = true
        onUnlock()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 复位：稍等片刻让调用方切到 busy 态，再弹回
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
            fired = false
        }
    }
}
