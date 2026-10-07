// ================= 庆祝动效 (功能包18) =================
// 礼花粒子: SwiftUI Canvas + TimelineView 自绘, 零第三方、零图片资源。
// 降级链: reduceMotion / 素颜模式(1046) → 不播粒子, 时刻卡保留内容与静态亮起;
// 时刻卡复用 HeroCard 的渐变视觉语言与既有触感 (idea 24/992/1010/1021/1050 等一次性时刻)。
import SwiftUI

// ---------- 礼花粒子层 ----------
struct ConfettiView: View {
    /// 粒子总数 (基准 90, 史诗时刻可加密)
    var intensity: Int = 90
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece {
        var x0: Double      // 0...1 起点横向位置
        var delay: Double   // s
        var fall: Double    // 下落时长 s
        var sway: Double    // 横向摆幅 (0...1 → 比例)
        var spin: Double    // 自转圈数
        var size: Double
        var colorIdx: Int
        var round: Bool     // 圆点/矩形 两形混排
    }

    // 颜色只经 DS 令牌: 主题 hero 两端 + 语义 ok/warn
    private var palette: [Color] {
        [DS.Palette.themed("heroA"), DS.Palette.themed("heroB"), DS.Palette.ok, DS.Palette.warn]
    }

    // 确定性伪随机: 同一次庆祝内稳定, 不每帧重排
    private static func piece(_ i: Int) -> Piece {
        func rnd(_ seed: UInt64) -> Double {
            let x = (seed &* 6364136223846793005 &+ 1442695040888963407) >> 33
            return Double(x & 0xffffff) / 0xffffff
        }
        let s = UInt64(i &* 2_654_435_761 &+ 7)
        return Piece(
            x0: rnd(s),
            delay: rnd(s &+ 11) * 0.55,
            fall: 1.6 + rnd(s &+ 23) * 0.9,
            sway: 0.02 + rnd(s &+ 37) * 0.06,
            spin: 1 + rnd(s &+ 53) * 2,
            size: 5 + rnd(s &+ 71) * 6,
            colorIdx: Int(rnd(s &+ 97) * 4) % 4,
            round: rnd(s &+ 131) > 0.5)
    }

    var body: some View {
        if reduceMotion || Milestones.plainMode {
            // 降级: 静态徽章亮起 — 不播粒子, 保留"有纪念"的语义
            VStack(spacing: DS.Space.s) {
                Image(systemName: "rosette")
                    .font(.system(size: DS.Icon.xl, weight: .medium))
                    .foregroundStyle(.white)
                Text("纪念时刻")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(DS.Space.l)
            .background(.white.opacity(0.14), in: Capsule())
            .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let colors = palette
                    for i in 0..<intensity {
                        let p = Self.piece(i)
                        let life = (t - p.delay) / p.fall
                        guard life > 0, life < 1 else { continue }
                        let y = -20 + life * (size.height + 60)
                        let x = p.x0 * size.width + sin(life * .pi * 2 + Double(i)) * p.sway * size.width
                        let alpha = life < 0.85 ? 1 : (1 - life) / 0.15
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(life * p.spin * 2 * .pi))
                        let r = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.round ? p.size : p.size * 0.55)
                        c.opacity = alpha
                        if p.round {
                            c.fill(Path(ellipseIn: r), with: .color(colors[p.colorIdx]))
                        } else {
                            c.fill(Path(r), with: .color(colors[p.colorIdx]))
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

// ---------- 一次性时刻卡 (复用 HeroCard 视觉语言) ----------
struct Moment: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    var celebrate: Bool = false   // 是否播礼花 (素颜/降级时只静置)
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
            VStack(spacing: DS.Space.l) {
                // 徽章圆座: 玻璃感 + 品牌渐变
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.16))
                        .frame(width: 96, height: 96)
                    Image(systemName: moment.icon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(spacing: DS.Space.s) {
                    Text(moment.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(moment.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("轻点任意处继续")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 340)
            .background(DS.Gradient.hero, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .shadow(color: DS.Palette.accent.opacity(0.35), radius: 26, y: 12)
            .padding(.horizontal, DS.Space.xl)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
        }
        .overlay {
            if moment.celebrate {
                ConfettiView(intensity: 110)
                    .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onAppear {
            withAnimation(DS.Motion.standard) { shown = true }
            // 防滞留: 无人点击也自动收起, 回到正常使用流
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_400_000_000)
                onDismiss()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(moment.title), \(moment.subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
