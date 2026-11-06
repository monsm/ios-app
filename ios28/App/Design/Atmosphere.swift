// Atmosphere.swift —— 日光场与日光窗。
//
// 这一层是整个 App 的空间概念：
//   · DaylightField 是"窗外"：一层会随时间缓慢漂移的日光。
//   · DaylightPane  是"窗"：一块真正有厚度、有折射、有窗台的玻璃。
//   · Threshold     是"门槛"：窗的下沿。界面的上半部分是室外，下半部分是室内。
//
// 纪律：动效只允许在日光场上（极慢、低幅度）。内容区不做装饰动效。
import SwiftUI

// MARK: - 日光场

struct DaylightField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                T.C.canvas
                LinearGradient(colors: [T.C.canvasTop, T.C.canvas, T.C.canvas],
                               startPoint: .top, endPoint: .bottom)

                Circle()
                    .fill(T.C.atmoWarm)
                    .frame(width: geo.size.width * 1.15)
                    .blur(radius: 90)
                    .offset(x: geo.size.width * 0.34 + (drift ? 12 : -10),
                            y: -geo.size.height * 0.30 + (drift ? 8 : -6))
                    .opacity(0.75)

                Circle()
                    .fill(T.C.atmoCool)
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 80)
                    .offset(x: -geo.size.width * 0.40, y: -geo.size.height * 0.34)
                    .opacity(0.55)

                // 底部一层极淡的纸色回光，避免整页发灰。
                LinearGradient(colors: [.clear, T.C.canvasDeep.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
                    .opacity(0.6)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: T.M.driftDuration).repeatForever(autoreverses: true),
                       value: drift)
            .onAppear { if !reduceMotion { drift = true } }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 日光窗

struct DaylightPane<Content: View>: View {
    var height: CGFloat = 336
    var showSill: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                LinearGradient(colors: [T.C.paneTop, T.C.paneMid, T.C.paneBot],
                               startPoint: .topLeading, endPoint: .bottom)

                Circle()
                    .fill(T.C.paneWarm)
                    .frame(width: 300, height: 300)
                    .blur(radius: 74)
                    .offset(x: 132, y: -128)

                Circle()
                    .fill(T.C.paneCool)
                    .frame(width: 250, height: 250)
                    .blur(radius: 72)
                    .offset(x: -126, y: 18)

                // 斜向的一道光。它只是"窗"的一部分，不承载任何信息。
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, T.C.paneStreak.opacity(0.55), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 120)
                    .rotationEffect(.degrees(18))
                    .blur(radius: 12)
                    .offset(x: -40, y: -40)
                    .opacity(0.7)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(T.C.glassEdge)
                    .frame(height: 0.5)
                    .opacity(0.8)
            }

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
        .shadow(color: T.C.shadow, radius: 30, x: 0, y: 18)
    }
}

// MARK: - 玻璃面

struct GlassSurface<Content: View>: View {
    var radius: CGFloat = T.R.card
    var strong: Bool = false
    var padded: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padded ? T.S.m : 0)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(strong ? T.C.glassStrong : T.C.glass)
                    .background {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
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
    /// 原先 `trailing` 只是一个 Text —— 今日页的「全部」写着却打不开完整列表。
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(index)
                .type(T.F.kicker)
                .foregroundStyle(T.C.brass)
            Text(title)
                .type(T.F.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(T.C.ink)
            Rectangle()
                .fill(T.C.hair)
                .frame(height: 0.5)
                .offset(y: -3)
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
