import SwiftUI

// 纪念时刻卡 (从 Celebration.swift 抽出保留)
//
// 2026-10-25 大删: 成就/庆祝/礼花整套已剥离, 但 MomentQueue 仍被两处**真实**启动提示使用 ——
// 758 上次异常退出、752 保留期到期但未备份。所以卡本体与队列留下, 只去掉礼花与徽章圆座之外的庆祝语义。


/// 纪念时刻卡层 (2026-10-16 从 mainTabsChrome 抽出): 一次只呈现一张, 点掉或超时自动收起后取下一张。
struct MomentLayer: ViewModifier {
    @EnvironmentObject var app: AppState

    func body(content: Content) -> some View {
        content
            .overlay {
                if let m = app.moment {
                    MomentCardView(moment: m) { app.advanceMoment() }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(DS.Motion.soft, value: app.moment)
    }
}

/// 一张时刻卡的数据 (队列元素)。celebrate 字段保留但恒 false —— 礼花组件已删。
struct Moment: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    var celebrate: Bool = false
}

struct MomentCardView: View {
    let moment: Moment
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.l) {
                ZStack {
                    Circle().fill(DS.heroFg.opacity(0.16)).frame(width: 96, height: 96)
                    Image(systemName: moment.icon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(DS.heroFg)
                }
                .accessibilityHidden(true)

                VStack(spacing: DS.Space.s) {
                    Text(moment.title)
                        .vkFont(.title3, weight: .semibold)
                        .foregroundStyle(DS.heroFg)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(moment.subtitle)
                        .vkFont(.footnote)
                        .foregroundStyle(DS.heroFg.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("轻点任意处继续")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.heroFg.opacity(0.62))
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 340)
            .background(DS.heroGradientSafe, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .shadow(color: DS.Palette.accent.opacity(0.35), radius: 26, y: 12)
            .padding(.horizontal, DS.Space.xl)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onAppear { withAnimation(DS.Motion.standard) { shown = true } }
        // 防滞留: 无人点击也自动收起。用 .task(id:) 而不是裸 Task ——
        // 换卡要重开计时, 卡片离树要自动取消 (理由见原实现, 已随本文件保留)。
        .task(id: moment.id) {
            try? await Task.sleep(nanoseconds: 5_400_000_000)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}