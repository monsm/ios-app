// GlassSlideToUnlock.swift —— **原生来电滑块样式的开锁控件**（功能层玻璃 · V8 令牌）
//
// 2026-11-03（用户拍板）：手动开锁只留这一种 —— iOS 接电话那种滑块。
// 视觉对齐系统来电 UI：玻璃胶囊滑轨 + 圆形把手 + "滑动来开锁"渐隐提示文字，拖到最右触发一次。
//
// 玻璃归属：这是门页**主行动控件**（浮动功能层，契约 §6 表"浮动操作条"），且本文件
// 位于 Components/Glass* —— glass 闸门 allowlist 内。减少透明度/增强对比度时退化为不透明。
//
// 2026-11-04（Round 16 · S4 复核）：本控件是门页**唯一主动作**，却还在用 V7 令牌 ——
// 从 V8 门页里弹出一个 V7 外观的控件，是同一个交互里两套设计语言。令牌换成 V8，行为一字未改。
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
    /// 在文件里声明了却**从未被读取** —— 也就是说低视力用户打开"降低透明度"后，
    /// 门页这个**主行动控件**仍然是半透明玻璃。这是本仓唯一的开锁入口。
    private var solid: Bool { reduceTransparency || contrast == .increased }

    /// 把手直径与滑轨高度（V8 令牌里没有这两个数，用 S 的语义档组合出来）。
    private var knobDiameter: CGFloat { V8.S.gapXXL * 2.33 }
    private var trackHeight: CGFloat { V8.H.comfortable + V8.S.gapXL }

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - knobDiameter - V8.S.gapL
            ZStack(alignment: .leading) {
                // 滑轨：功能层玻璃胶囊。玻璃只保留滑轨这一层，把手是实心色块 ——
                // 它本来就是"按钮"，不需要采样背后内容（避免玻璃叠玻璃）。
                Group {
                    if solid {
                        Capsule().fill(V8.C.card)
                    } else {
                        Capsule().fill(.clear)
                            .glassEffect(.regular.tint(V8.C.glassTint), in: Capsule())
                    }
                }
                .overlay {
                    Capsule().strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                }
                .overlay {
                    Text(offset > travel * 0.25 ? "" : "滑动来开锁")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink2)
                        .frame(maxWidth: .infinity)
                }
                // 把手：圆形钮
                Circle()
                    .fill(solid ? V8.C.accentFill : V8.C.accentFill.opacity(0.92))
                    .overlay { Circle().strokeBorder(V8.C.accentTrack, lineWidth: V8.S.hair) }
                    .frame(width: knobDiameter, height: knobDiameter)
                    .overlay {
                        Image(systemName: "chevron.right.2")
                            .font(V8.T.chipValue)
                            .foregroundStyle(V8.C.chipOn)
                            .accessibilityHidden(true)
                    }
                    .offset(x: V8.S.gapS + min(offset, travel))
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
        // 而这条 accessibilityAction 原来直接调 onUnlock() —— 读屏用户可以在开锁链进行中再次触发。
        .accessibilityAction {
            guard !busy, !fired else { return }
            onUnlock()
        }
    }

    private func slideGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: V8.S.gapS)
            .onChanged { v in
                guard !busy, !fired else { return }
                offset = max(0, min(travel, v.translation.width))
                if offset >= travel { fire() }
            }
            .onEnded { _ in
                guard !fired else { return }
                withAnimation(reduceMotion ? nil : V8.M.move) { offset = 0 }
            }
    }

    private func fire() {
        fired = true
        onUnlock()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 复位：稍等片刻让调用方切到 busy 态，再弹回
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(reduceMotion ? nil : V8.M.move) { offset = 0 }
            fired = false
        }
    }
}
