// 通用 UI 组件 · Toast / 按压反馈 / 应用锁闸 / 卡片 / 小节标题
// 2026-10-29 从 LockKeeperApp.swift（686 行）拆出。
import SwiftUI

struct ToastView: View {
    var text: String
    var body: some View {
        Text(text)
            .vkFont(.footnote, weight: .medium)
            .foregroundStyle(DS.Palette.text)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s + 2)
            .frame(maxWidth: 420)
            // 玻璃层自带深浅色适配与背景折射, 不需要再叠一层描边
            .axGlass(DS.Radius.control)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.xs)
            .accessibilityAddTraits(.isStaticText)
    }
}

struct PressFeedback: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.16 : 0), radius: 7, y: 3)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

struct PressableButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Gate(configuration: configuration)
    }
    private struct Gate: View {
        let configuration: Configuration
        @State private var lastFire = Date.distantPast
        var body: some View {
            Button {
                let now = Date()
                guard !AXPrefs.dbltapGuard || now.timeIntervalSince(lastFire) >= 0.3 else { return }
                lastFire = now
                configuration.trigger()
            } label: { configuration.label }
            .buttonStyle(PressFeedback())
        }
    }
}

struct Card<Content: View>: View {
    var tint: ToneColor?
    var content: Content
    init(tint: ToneColor? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }
    /// 语义色叠底 (低电/告警的 ToneColor)。实底时代是 0.08；改玻璃后提到 0.14 ——
    /// 染色要同时压住自身与身后折射的底色，沿用 0.08 会让"这张卡是告警色"这件事失色。
    private var tintWash: Color {
        tint.map { $0.color.opacity(0.14) } ?? .clear
    }
    var body: some View {
        // 2026-10-16: 形状的决定权交给 VK.card —— 53 处 Card 调用一次跟着两套界面变，
        // 而不是去 53 个调用点各改一遍（那既是"同一个量算两次"，也必然漏改）。
        // `.legacy` 分支是原来这段 body 逐字搬过去的，见 VariantGrammar.swift 的 VK.card。
        // 传 tintWash 而不是 tint 本体：0.14 这个叠底浓度是"玻璃时代"定下来的，
        // 它的理由写在下面 tintWash 的注释里，两套新界面各自决定怎么用这个语义色。
        VK().card(tint: tint == nil ? nil : tintWash) { content }
    }
}

struct SectionTitle: View {
    var text: String
    var count: Int?
    var body: some View {
        // 2026-10-16: 形状交给当前变体决定 (VK.sectionTitle)，21 处调用一次跟着两套走。
        // legacy 分支是这里原来的实现逐字搬过去的，见 VariantGrammar.swift。
        VK().sectionTitle(text: text, count: count)
    }
}

