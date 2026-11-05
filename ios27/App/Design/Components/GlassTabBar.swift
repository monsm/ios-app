// GlassTabBar.swift —— V8 浮动胶囊标签栏（参考图 P1/P2/P3 的底部浮岛）
//
// 为什么自绘：参考图的标签栏是 390.5×48.2pt 的浮动胶囊，距屏底 14.4pt，选中项是一枚
// 70×41.1pt 的胶囊高亮，且**内容从栏下方流过并被渐隐**。官方 TabView 是全宽的，做不到这两点。
//
// 代价（如实记录）：丢系统语义（iPhone Duo 侧栏、滚动收起、VoiceOver 的「第 N 个标签，共 M 个」）。
// 补偿：手工补 accessibilityLabel 与 isSelected trait；Shell 保留 kf_native_tabbar 开关可回退官方 TabView。
import SwiftUI

struct GlassTabBar: View {
    let titles: [String]
    let symbols: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    VStack(spacing: V8.S.gapXS / 2) {
                        Image(systemName: symbols[index])
                            .resizable()
                            .scaledToFit()
                            .frame(width: V8.G.tabIconW, height: V8.G.tabIconH)
                        Text(titles[index])
                            .font(V8.T.tab)
                    }
                    .foregroundStyle(selection == index ? V8.C.accent : V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    // 2026-11-04（Round 16 复核）：原来是固定高度 —— V8.T.tab 12.6pt 随
                    // Dynamic Type 放大后，标签文字会被裁掉（SwiftUI 不报错，只是看不见字）。
                    // 与 a11y.js ⑥ 同一条纪律：下限只能当下限用。
                    .frame(minHeight: V8.G.tabPillH)
                    // 选中胶囊宽度按参考图 70pt，但不小于内容所需 —— 大字号下文字撑开它，
                    // 而不是被裁掉。用 minWidth 保证"读得下"。
                    .frame(minWidth: V8.G.tabPillW)
                    .background {
                        if selection == index {
                            Capsule(style: .continuous)
                                .fill(V8.C.chipOn.opacity(0.92))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(index + 1) 个标签，共 \(titles.count) 个：" + titles[index])
                .accessibilityAddTraits(selection == index ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, V8.S.gapXS)
        .frame(minHeight: V8.S.hTabBar)
        // 2026-11-05：整条栏是**可点的**（每个标签都是按钮）→ 用可交互玻璃。
        .glassEffect(
            .regular.tint(V8.C.glassTint).interactive(),
            in: .rect(cornerRadius: V8.R.capsule(V8.S.hTabBar))
        )
        .padding(.horizontal, V8.S.tabBarInset)
    }
}
