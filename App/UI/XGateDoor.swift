import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 入户门 + 刃锁体（D 域主视图）
// ═══════════════════════════════════════════════════════════════════════
//
// 布局: 门占满整屏，锁按真实比例（门宽 5.7%）嵌在门面上。
//
// ═══ 真实比例与可读性的矛盾，以及解法 ═══
//
// 真实比例下锁只有门宽的 5.7% —— 在 393pt 宽的屏上约 20pt，
// 什么都看不清。但如果为了看清把锁做大 10 倍，门就变成"玩具"。
//
// 解法（用户提出）: **触摸时放大，点别处归位**。
//
//   · 常态: 锁按真实比例（20pt），门是完整的一扇门
//   · 点锁: 锁放大到 3.2×（约 64pt），门保持不动
//   · 点别处: 归位
//
// 3.2× 是算出来的: 20pt × 3.2 ≈ 64pt，
// 接近旧 LockPlate 在 plateDiameter ≈ 200 时的视觉占比。
//
// **这不违背物理** —— 放大发生在"看细节"的语境，不是"锁有这么大"。
struct XGateDoor: View {
    var isOpen: Bool
    var isFailed: Bool
    var isDeadbolted: Bool
    var charge: CGFloat
    /// 门面是否整体可见（false 时用于三棱柱的侧面，只留边缘）
    var tint: Color = XPalette.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lockFocused = false
    @State private var breathe = false

    /// 门的显示宽度：屏幕宽 × 0.92（留一点边给门框阴影）
    private var doorWidth: CGFloat {
        UIScreen.main.bounds.width * 0.92
    }
    private var doorHeight: CGFloat {
        doorWidth * GateMetrics.doorH / GateMetrics.doorW
    }
    /// 锁在「未放大」时的显示边长（取门宽的 5.7%，但下限 18pt 保证能点中）
    private var lockSide: CGFloat {
        let raw = doorWidth * GateMetrics.lockToDoorWidth
        // 60mm 宽 300mm 高 → 显示成 20 × 100 的长条
        return max(raw, 18)
    }
    private var lockHeight: CGFloat {
        lockSide * GateMetrics.lockH / GateMetrics.lockW
    }
    /// 锁中心相对门中心的位置（mm → pt）
    private var lockOffsetY: CGFloat {
        let mmFromDoorTop = GateMetrics.lockTopFromDoorTop + GateMetrics.lockH / 2
        let mmFromDoorCenter = mmFromDoorTop - GateMetrics.doorH / 2
        return mmFromDoorCenter * (doorWidth / GateMetrics.doorW)
    }
    /// 锁中心相对门中心的 X（锁芯距门边 60mm）
    private var lockOffsetX: CGFloat {
        let mmFromRight = GateMetrics.backset
        let mmFromCenter = GateMetrics.doorW / 2 - mmFromRight
        return mmFromCenter * (doorWidth / GateMetrics.doorW)
    }

    var body: some View {
        ZStack {
            // ── 门 ──
            Image(uiImage: GateFaceTexture.image(tint: UIColor(tint)))
                .resizable()
                .aspectRatio(GateMetrics.doorW / GateMetrics.doorH, contentMode: .fit)
                .frame(width: doorWidth, height: doorHeight)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                // 门在地面上的接触阴影（让它有重量）
                .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
                .overlay(alignment: .center) {
                    lockOverlay
                }
                // 点门面（非锁）→ 归位
                .contentShape(Rectangle())
                .onTapGesture { if lockFocused { withAnimation { lockFocused = false } } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    // ── 锁（真实比例 → 触摸放大）──
    private var lockOverlay: some View {
        XLockBlade(
            isOpen: isOpen,
            isFailed: isFailed,
            isDeadbolted: isDeadbolted,
            charge: charge,
            diameter: lockHeight)
            .frame(width: lockSide, height: lockHeight)
            .offset(x: lockOffsetX, y: lockOffsetY)
            // 放大聚焦: 只放大锁，门不动
            .scaleEffect(lockFocused ? 3.2 : 1.0, anchor: .center)
            // 用 XMotion.soft（约 0.35s）而不是 doorSwing（0.82s）——
            // 点击反馈必须在 0.4s 内完成，否则感觉"点下去没反应"。
            // （XMotion.gate 是我第一版凭空写的，全仓没有这个成员。）
            .animation(reduceMotion ? nil : XMotion.soft, value: lockFocused)
            // 放大时压暗周围门面，强化"聚焦"
            .background {
                if lockFocused {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { lockFocused = false } }
                        .transition(.opacity)
                }
            }
            // 触点热区放大到 44pt（真实比例下锁只有 20pt，太小点不中）
            .contentShape(Rectangle())
            .frame(minWidth: XHit.min, minHeight: XHit.min)
            .onTapGesture {
                XHaptics.tick.impactOccurred()
                withAnimation { lockFocused.toggle() }
            }
            // 默认时的呼吸光（保留旧 LockPlate 的氛围）
            .shadow(color: XPalette.accent.opacity(reduceMotion ? 0.10 : (breathe ? 0.18 : 0.06)),
                    radius: lockFocused ? 28 : 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("门锁")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(lockFocused ? "轻点归位" : "轻点放大查看")
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        parts.append(isFailed ? "操作失败" : (isOpen ? "已开" : "已锁"))
        if isDeadbolted { parts.append("门从里面反锁") }
        if charge > 0.01 { parts.append("充能 \(Int(charge * 100))%") }
        parts.append(lockFocused ? "已放大" : "原始比例")
        return parts.joined(separator: ", ")
    }
}
