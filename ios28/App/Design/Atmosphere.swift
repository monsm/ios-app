// Atmosphere.swift —— 日光场与日光窗。
//
// 这一层是整个 App 的空间概念：
//   · DaylightField 是"窗外"：一层会随时间缓慢漂移的日光。
//   · DaylightPane  是"窗"：一块真正有厚度、有折射、有窗台的玻璃。
//   · Threshold     是"门槛"：窗的下沿。界面的上半部分是室外，下半部分是室内。
//
// 2026-11-07 材质升级：
//   · 窗底从「一条线性渐变」换成 **MeshGradient**（iOS 18）：9 个控制点缓慢推挤，
//     冷暖两团光是**流动**的，不是叠两个模糊圆。
//   · 整层加极轻的**颗粒**（纯矢量、确定性伪随机）—— 玻璃与渐变最怕太干净。
//   · 章节头与标题的排版收紧：编号进黄铜小方块、细线从左长出、计数走等宽。
//
// 纪律：动效只允许在日光场上（极慢、低幅度）。内容区不做装饰动效。
import SwiftUI

// MARK: - 日光场

struct DaylightField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        // F28：日光场按**真实时刻**走 —— 太阳偏西时暖光团往左挪，
        // 天黑后整层压暗。算式在 `Solar` 里（本地算，不联网）。
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let phase = Solar.phase(at: ctx.date)
            GeometryReader { geo in
                ZStack {
                    T.C.canvas
                    LinearGradient(colors: [T.C.canvasTop, T.C.canvas, T.C.canvas],
                                   startPoint: .top, endPoint: .bottom)

                    // 暖光团：随太阳偏西往左挪。
                    Circle()
                        .fill(T.C.atmoWarm)
                        .frame(width: geo.size.width * 1.15)
                        .blur(radius: 90)
                        .offset(x: geo.size.width * Solar.warmOffset(phase) + (drift ? 12 : -10),
                                y: -geo.size.height * 0.30 + (drift ? 8 : -6))
                        .opacity(0.75 * (0.35 + 0.65 * phase.brightness))

                    // 冷光团：左上。
                    Circle()
                        .fill(T.C.atmoCool)
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 80)
                        .offset(x: -geo.size.width * 0.40, y: -geo.size.height * 0.34)
                        .opacity(0.55 * (0.4 + 0.6 * phase.brightness))

                    // 第三团：贴着地面的回光，让下半页不至于死平。
                    Circle()
                        .fill(T.C.atmoWarm.opacity(0.5))
                        .frame(width: geo.size.width * 0.8)
                        .blur(radius: 110)
                        .offset(x: geo.size.width * 0.42, y: geo.size.height * 0.42)
                        .opacity(0.35 * phase.brightness)

                    // 底部一层极淡的纸色回光，避免整页发灰。
                    LinearGradient(colors: [.clear, T.C.canvasDeep.opacity(0.55)],
                                   startPoint: .center, endPoint: .bottom)
                        .opacity(0.6)

                    // 夜里再压一层 —— 不是变黑，是把光收走。
                    Rectangle()
                        .fill(T.C.canvasDeep)
                        .opacity(0.28 * (1 - phase.brightness))

                    // 颗粒：让"纸"有纤维感，而不是一块塑料渐变。
                    GrainOverlay(opacity: 0.045, count: 320)
                        .opacity(0.9)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: T.M.driftDuration).repeatForever(autoreverses: true),
                           value: drift)
                .onAppear { if !reduceMotion { drift = true } }
            }
        }
        .ignoresSafeArea()
        // iOS 26+：背景在安全区外延展 —— iPad 分屏与侧边栏时，日光不会在边缘被裁断。
        .extendBackground()
    }
}

// MARK: - 日光窗

struct DaylightPane<Content: View>: View {
    var height: CGFloat = 336
    var showSill: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    /// 3×3 网格的控制点。中心与右中两个点会缓慢推挤，
    /// 冷暖两团光因此像被风推着走 —— 这是"窗外的日光"，不是一张静态渐变。
    private var meshPoints: [SIMD2<Float>] {
        let d: Float = drift ? 1 : 0
        return [
            .init(0, 0), .init(0.5 + 0.02 * d, 0), .init(1, 0),
            .init(0, 0.42 + 0.04 * d), .init(0.46 - 0.03 * d, 0.52), .init(1, 0.36 + 0.02 * d),
            .init(0, 1), .init(0.52 + 0.02 * d, 1), .init(1, 1),
        ]
    }

    private var meshColors: [Color] {
        [T.C.paneTop, T.C.paneTop, T.C.paneCool,
         T.C.paneMid, T.C.paneWarm, T.C.paneMid,
         T.C.paneBot, T.C.paneBot, T.C.paneBot]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 26).repeatForever(autoreverses: true),
                               value: drift)

                // 斜向的一道光。它只是"窗"的一部分，不承载任何信息。
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, T.C.paneStreak.opacity(0.55), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 120)
                    .rotationEffect(.degrees(18))
                    .blur(radius: 12)
                    .offset(x: drift ? -24 : -56, y: -40)
                    .opacity(0.7)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 18).repeatForever(autoreverses: true),
                               value: drift)

                // 玻璃厚度：顶部一条冷高光 + 底部一圈暗边（窗框的阴影）。
                LinearGradient(colors: [T.C.glassEdge.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .center)
                    .opacity(0.6)

                GrainOverlay(opacity: 0.055, count: 300)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(T.C.glassEdge)
                    .frame(height: 0.5)
                    .opacity(0.8)
            }
            .onAppear { if !reduceMotion { drift = true } }

            content()

            if showSill {
                LinearGradient(colors: [.clear, T.C.hairStrong, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 0.5)
                    .padding(.horizontal, 26)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: T.R.pane, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: T.R.pane, style: .continuous)
                .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
        }
        // 双层阴影：近处一层紧实的接触阴影 + 远处一层散开的环境阴影。
        .shadow(color: T.C.shadow, radius: 30, x: 0, y: 18)
        .shadow(color: T.C.shadow.opacity(0.5), radius: 6, x: 0, y: 3)
    }
}

// MARK: - 玻璃面

struct GlassSurface<Content: View>: View {
    var radius: CGFloat = GlassMetrics.cardRadius
    var padded: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padded ? T.S.m : 0)
            // 内容卡片是浮在页面底层之上的第二层：用真玻璃，但不染色 ——
            // 一页里可能同时出现好几张卡片，染色叠染色会让整页泛黄。
            .liquidGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            // 卡片的"厚度"：上缘一条极淡的高光，让它在纸面上立起来。
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.white.opacity(0.10), .clear],
                                       startPoint: .top, endPoint: .center)
                    )
                    .mask(alignment: .top) { Rectangle().frame(height: T.S.l) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .shadow(color: T.C.shadow, radius: 18, x: 0, y: 10)
    }
}

// MARK: - 门槛线

struct Threshold: View {
    var lit: Bool = false

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, T.C.hairStrong, .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.5)
            if lit {
                Circle()
                    .fill(T.C.brassBright)
                    .frame(width: 4, height: 4)
                    .shadow(color: T.C.brassBright.opacity(0.7), radius: 6)
                    .offset(x: 72)
            }
        }
    }
}

// MARK: - 章节头

struct SectionHead: View {
    var index: String
    var title: String
    var trailing: String? = nil
    /// 右侧文字若是入口（例如「全部」），必须真的能点。
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // 编号进黄铜小方块：它是一页里的顺序，不是装饰，但需要一个"锚"。
            Text(index)
                .type(T.F.kicker)
                .foregroundStyle(T.C.onAccent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(T.C.brass, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(title)
                .type(T.F.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(T.C.ink)
            Rectangle()
                .fill(
                    LinearGradient(colors: [T.C.hairStrong, T.C.hair.opacity(0.2)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 0.5)
                .offset(y: -3)
                .ruleReveal()
            if let trailing {
                if let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailing)
                            .type(T.F.kicker)
                            .foregroundStyle(T.C.brass)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(trailing)
                        .type(T.F.kicker)
                        .monospacedDigit()
                        .foregroundStyle(T.C.ink3)
                }
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 4)
    }
}

// MARK: - 主标题（衬线）

struct DisplayLine: View {
    var text: String
    var size: CGFloat = 44

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .serif))
            .tracking(-0.8)
            .lineSpacing(2)
            .foregroundStyle(T.C.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
