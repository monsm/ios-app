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

    private var knobDiameter: CGFloat { 56 }
    private var trackHeight: CGFloat { 72 }

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - knobDiameter - 16
            ZStack(alignment: .leading) {
                // 滑轨：功能层玻璃胶囊
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())
                    .overlay {
                        Text(offset > travel * 0.25 ? "" : "滑动来开锁")
                            .font(V.F.bodyStrong)
                            .foregroundStyle(V.C.text2)
                            .frame(maxWidth: .infinity)
                    }
                // 把手：圆形玻璃钮
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(V.C.blue.opacity(0.35)), in: Circle())
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
        .accessibilityAction { onUnlock() }   // 读屏用户直接触发，不需要拖
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
