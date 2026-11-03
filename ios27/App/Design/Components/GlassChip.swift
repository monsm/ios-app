// GlassChip.swift —— 功能层的玻璃分段控件（筛选芯片）。
//
// 2026-11-03（用户："每个界面每个控件原生液态玻璃的质感太少太少了"）：
// 契约 §6 的"内容层不铺玻璃"针对的是**内容容器**（卡片）；筛选芯片是**控制件**，
// HIG 的 Liquid Glass 正是给控制件用的。所以把凭证页的筛选芯片换成玻璃胶囊：
// 选中态用染色玻璃，未选中用素玻璃 —— 与系统分段控件同一种材质语言。
import SwiftUI

struct GlassChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var solidFallback: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(V.F.footnote)
                .foregroundStyle(selected ? V.C.text1 : V.C.text3)
                .padding(.horizontal, V.S.gapM)
                .padding(.vertical, V.S.gapS)
                .background {
                    if solidFallback {
                        Capsule().fill(selected ? V.C.card : V.C.cardAlt)
                    } else {
                        Color.clear
                            .glassEffect(selected
                                         ? .regular.tint(V.C.blue.opacity(0.28))
                                         : .regular,
                                         in: Capsule())
                    }
                }
                .overlay {
                    Capsule().strokeBorder(selected ? V.C.blue.opacity(0.35) : V.C.hairlineSoft,
                                           lineWidth: V.S.hair)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
