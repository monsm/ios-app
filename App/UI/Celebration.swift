// ================= 庆祝动效 (功能包18) =================
// 礼花粒子: SwiftUI Canvas + TimelineView 自绘, 零第三方、零图片资源。
// 降级链: reduceMotion / 素颜模式(1046) → 不播粒子, 时刻卡保留内容与静态亮起;
// 24 首次完成庆祝 = 本文件的"一次性时刻"通道 (礼花 + 时刻卡)，不新造一套庆祝视图:
// 庆祝层各写一份的话，reduceMotion 与素颜模式的降级就得在每个新入口重记一遍 (本仓那两条是硬约束)。
// 时刻卡复用 XHeroCard 的渐变视觉语言与既有触感 (idea 24/992/1010/1021/1050 等一次性时刻)。
import SwiftUI


// ---------- 一次性时刻卡 (复用 XHeroCard 视觉语言) ----------
struct Moment: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
}

struct MomentCardView: View {
    let moment: Moment
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            // 压暗底: 让渐变卡成为唯一焦点
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: XSpace.l) {
                // 徽章圆座: 玻璃感 + 品牌渐变
                ZStack {
                    Circle()
                        .fill(XPalette.onAccent.opacity(0.16))
                        .frame(width: 96, height: 96)
                    Image(systemName: moment.icon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(XPalette.onAccent)
                }
                .accessibilityHidden(true)

                VStack(spacing: XSpace.s) {
                    Text(moment.title)
                        .xFont(.title3, weight: .semibold)
                        .foregroundStyle(XPalette.onAccent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(moment.subtitle)
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.onAccent.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("轻点任意处继续")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.onAccent.opacity(0.62))
            }
            .padding(XSpace.xl)
            .frame(maxWidth: 340)
            .background(XGradient.hero, in: RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
            .shadow(color: XPalette.accent.opacity(0.35), radius: 26, y: 12)
            .padding(.horizontal, XSpace.xl)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onAppear { withAnimation(XMotion.standard) { shown = true } }
        // 防滞留: 无人点击也自动收起, 回到正常使用流。
        // 2026-10-15 走查: 这条原先写在 .onAppear 里的裸 `Task {}` 有两个坑 ——
        //   ① 用户提前轻点关掉这张后, 那个计时器仍在跑, 5.4s 到点再调一次 onDismiss;
        //      而 root 那边 onDismiss = advanceMoment() (弹出队列里的下一张), 于是**下一张时刻被这记
        //      迟到点直接吞掉** (从没显示就没了), 正在显示的这张也会自己闪退。
        //   ② root 的覆盖层是 `if let m = app.moment` 且没挂 `.id`, 换下一张时**视图身份不变** ⇒
        //      `.onAppear` 不再触发 ⇒ 第二张起压根没有自动收起计时, "防滞留"只对第一张生效。
        // `.task(id: moment.id)` 一次解决两条: 换卡即重开一份计时, 卡片离树/被点掉则自动取消。
        // 取消那一路必须显式判 —— `try?` 会把 CancellationError 吞成一个 nil 继续往下走 (同族见 UnlockDial 心跳)。
        .task(id: moment.id) {
            try? await Task.sleep(nanoseconds: 5_400_000_000)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(moment.title), \(moment.subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
