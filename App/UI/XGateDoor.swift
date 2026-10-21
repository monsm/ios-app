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
    /// 门在屏幕上实际占的尺寸
    ///
    /// ═══ 这里踩过一个坑 ═══
    ///
    /// 第一版:
    ///   doorWidth  = 屏宽 × 0.92            → 393×0.92 = 361.6pt
    ///   doorHeight = doorWidth × 2300/1050  → 361.6×2.19 = 792pt
    ///   Image().aspectRatio(...).frame(width:height:)
    ///
    /// 问题: iPhone 15 Pro 屏高 852pt，扣掉状态栏与安全区约 93pt，
    ///       可用高度 759pt < 门高 792pt —— 超出 33pt。
    ///
    /// 而且 .aspectRatio() 写在 .frame() 之前会被固定 frame 覆盖，
    /// 所以 aspectRatio 根本没起作用。
    ///
    /// 修法: 按「宽和高哪个先到边」取小，保证整扇门可见。
    private var doorWidth: CGFloat {
        let byWidth = UIScreen.main.bounds.width * 0.92
        let byHeight = availableHeight * (GateMetrics.doorW / GateMetrics.doorH)
        return min(byWidth, byHeight)
    }
    private var doorHeight: CGFloat {
        doorWidth * GateMetrics.doorH / GateMetrics.doorW
    }

    /// 屏幕可用高度
    ///
    /// ═══ 为什么只留 120pt 而不是 340pt ═══
    ///
    /// 第一版我扣掉 340pt（顶部信息 100 + 底部按钮 240），
    /// 结果 iPhone 15 上门只剩 234pt 宽 —— 屏宽的 60%，明显偏小。
    /// 而且真实比例的锁只有 13.4pt，低于 18pt 下限被放大 34%，比例失真。
    ///
    /// 但 D 域的设计意图是「**门占满整屏，信息浮在门面上**」——
    /// 锁名、状态、按住开锁都是 overlay，压在门上面，不占门的空间。
    ///
    /// 所以只留 120pt（状态栏 + 底部安全区）。
    /// 门宽 334pt、锁 19.1pt > 18pt 下限 —— 比例不再失真。
    private var availableHeight: CGFloat {
        max(320, UIScreen.main.bounds.height - 120)
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
                // 不写 .aspectRatio —— doorWidth/doorHeight 已经是
                // 精确的 1050:2300 比例（见上面的计算），再写一层
                // aspectRatio 反而会和固定 frame 打架。
                .frame(width: doorWidth, height: doorHeight)
                // 只用 clipShape —— 它自带裁剪。
                // 前面再写 .clipped() 是两步裁剪（两次离屏渲染），
                // 而且 .clipped() 裁成矩形后 clipShape 再裁圆角，纯浪费。
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                // 门在地面上的接触阴影（让它有重量）
                .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
                .overlay(alignment: .center) {
                    // 放大时先把周围压暗，再叠锁 ——
                    // 遮罩必须在 scaleEffect 之外，否则会跟着锁放大。
                    ZStack {
                        if lockFocused {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                                .transition(.opacity)
                        }
                        lockOverlay
                    }
                }
                // 点门面（非锁）→ 归位
                .contentShape(Rectangle())
                .onTapGesture { if lockFocused { withAnimation { lockFocused = false } } }
        }
        // 全屏归位热区 —— 放大时铺满整屏，点任何地方都能退回去。
        // 注意 layers: 它在 ZStack 之上，但只在 lockFocused 时可交互，
        // 所以不会挡住平时的门面点击。
        .overlay {
            if lockFocused {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { lockFocused = false } }
                    .accessibilityLabel("归位")
                    .accessibilityAddTraits(.isButton)
            }
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
            size: CGSize(width: lockSide, height: lockHeight))
            // 不再加 .frame —— XLockBlade 内部已经按 size 定了尺寸。
            // 外面再写一次会让 offset 的定位基准变成两层，位置算不准。
            .offset(x: lockOffsetX, y: lockOffsetY)
            // 放大聚焦: 只放大锁，门不动
            .scaleEffect(lockFocused ? 3.2 : 1.0, anchor: .center)
            // 用 XMotion.soft（约 0.35s）而不是 doorSwing（0.82s）——
            // 点击反馈必须在 0.4s 内完成，否则感觉"点下去没反应"。
            // （XMotion.gate 是我第一版凭空写的，全仓没有这个成员。）
            .animation(reduceMotion ? nil : XMotion.soft, value: lockFocused)
            // 遮罩已移到 body 的 ZStack 顶层（见下）。
            // 原来挂在这里是错的 —— .background 是对「已 scale 的视图」加背景，
            // 会跟着放大 3.2 倍，只有锁周围一小块被压暗，
            // 而且「点其他位置归位」的热区也只在那一小块 —— 根本点不到。
            // 触点热区: 真实比例下锁只有 19pt 宽，直接点很难中。
            // 用 overlay 叠一层 44×44 透明区域接手势 ——
            // **不能用 .frame(minWidth:) 撑**，那会把锁体本身拉成正方形。
            .overlay {
                Color.clear
                    .frame(width: XHit.min, height: XHit.min)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        XHaptics.tick.impactOccurred()
                        withAnimation { lockFocused.toggle() }
                    }
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
