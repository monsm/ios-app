//  DoorSurface.swift
//  门面材质: 三停渐变 + 光位叠加 + 程序化噪声 (零位图)。2026-10-18 门面改造新增。
//
//  噪声照抄 DS.HeroTexture 的 grain 档 (DesignSystem.swift:214-230): 固定种子的线性同余。
//  为什么必须固定种子: 纹理要每次重建都长一样, 否则外观种子一变, 点就整体重掷, 看着像闪了一下噪点。
//  禁止 Double.random / arc4random。

import SwiftUI

struct DoorSurface: View {
    let skin: LockFaceSkin
    /// 右扇门的材质要横向偏移半屏, 这样两扇合起来才是一整面 (v10 的 .leaf.r .surface{left:-100%})。
    let isRightLeaf: Bool

    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                base(w: w, h: h)
                lighting(w: w, h: h)
                grain
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    // MARK: - 底色斜向渐变 (主光: 左上 -> 右下, 102°)

    private func base(w: CGFloat, h: CGFloat) -> some View {
        LinearGradient(
            colors: LockFaceStyle.surfaceColors(skin: skin, dark: dark),
            startPoint: UnitPoint(x: 0.16, y: 0),
            endPoint: UnitPoint(x: 0.84, y: 1)
        )
    }

    // MARK: - 光位叠加 (右上高光 / 左下压暗 / 左右边缘暗角)

    private func lighting(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                colors: [Color.white.opacity(dark ? 0.10 : 0.95), .clear],
                center: UnitPoint(x: 0.78, y: 0.04),
                startRadius: 0,
                endRadius: max(w, h) * 0.46
            )
            .blendMode(.softLight)

            RadialGradient(
                colors: [Color.black.opacity(dark ? 0.34 : 0.10), .clear],
                center: UnitPoint(x: 0.18, y: 1.0),
                startRadius: 0,
                endRadius: max(w, h) * 0.52
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.055), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.70),
                    .init(color: Color.black.opacity(0.045), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    // MARK: - 噪声 (固定种子 LCG, 照抄 DS.HeroTexture 的做法)

    private var grain: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B9
            // 门面面积约是 Hero 卡的 6 倍, 点数按面积放大 (130 -> 780)
            let n = 780
            for _ in 0..<n {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let u = CGFloat(Double(seed >> 11) / Double(1 << 53))
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let v = CGFloat(Double(seed >> 11) / Double(1 << 53))
                let r: CGFloat = 1.1
                ctx.fill(
                    Path(ellipseIn: CGRect(x: u * size.width, y: v * size.height, width: r * 2, height: r * 2)),
                    with: .color(.black.opacity(0.07))
                )
            }
        }
        .blendMode(.multiply)
        .opacity(skin.noiseOpacity(dark: dark))
        .drawingGroup()   // 只光栅化一次, 不逐帧重绘
        .allowsHitTesting(false)
    }
}
