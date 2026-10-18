//  LockPlate.swift
//  门面上的锁体: 凹槽 / 金属倒角 / 深色玻璃 / 地面反光 / 镜面高光 五层 + 字形双态 + 充能环。
//  2026-10-18 门面改造新增。
//
//  约束 (D3): 充能进度 p 是**连续量**, 1:1 驱动 环 trim / 光晕 / 刻度 / 盘体 scale。
//  禁止用 Timer 分段推进状态 —— 那是脚本动画, 手指停在 60% 时界面不会有任何反馈。

import SwiftUI

struct LockPlate: View {
    /// 0…1 充能进度。唯一驱动量。
    let progress: CGFloat
    /// 是否处于按压态 (scale 0.972)。
    let pressed: Bool
    /// 是否已开锁 (字形换成开环)。
    let unlocked: Bool
    /// 失败抖动位移 (由外层注入, 锁体自己不做动画)。
    let shakeX: CGFloat
    /// 直径 (由 LockFaceStyle.plateDiameter 算好传入, 不在这里读设置)。
    let diameter: CGFloat
    let skin: LockFaceSkin

    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var nightDim: Bool { DS.isNightDim }

    var body: some View {
        ZStack {
            groove
            bevel
            glassFace
            specular
            glyph
            chargeRing
        }
        .frame(width: diameter, height: diameter)
        // 按压反馈 (Apple Design §1: 按下那一刻就要有反馈; §4: 用 spring 而不是固定时长)。
        // 按下 0.972 用 quick 令牌 (spring response .22 / damping .9), 松手回弹也走同一条 ——
        // 这样"按下去"和"弹回来"是同一个物理量, 而不是两段拼起来的动画。
        .scaleEffect(pressed ? 0.972 : 1)
        .animation(DS.Motion.quick, value: pressed)
        .offset(x: shakeX)
        .shadow(color: shadowColor, radius: 26 * skin.shadowStrength,
                x: 14 * skin.shadowStrength, y: 20 * skin.shadowStrength)
        .animation(DS.Motion.glyphSwap, value: unlocked)
    }

    // MARK: - 第 1 层: 铣进材料的凹槽

    private var groove: some View {
        Circle()
            .fill(
                LinearGradient(colors: [Color(hex: 0xDCD5C9), Color(hex: 0xEBE6DC), Color(hex: 0xF3EFE7)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
            )
            .padding(-LockFaceStyle.grooveOutset)
    }

    // MARK: - 第 2 层: 金属倒角 (AngularGradient 对应 v10 的 conic-gradient)

    private var bevel: some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(colors: LockFaceStyle.bevelStops),
                    center: .center,
                    angle: .degrees(158)
                )
            )
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.28 * skin.bevelBrightness), lineWidth: 1)
            )
    }

    // MARK: - 第 3 层: 深色玻璃面 (光源在 26% / 4%)

    private var glassFace: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: LockFaceStyle.plateGlassColors,
                    center: UnitPoint(x: 0.26, y: 0.04),
                    startRadius: 0,
                    endRadius: diameter * 0.62
                )
            )
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1)
            )
            .padding(LockFaceStyle.faceInset)
    }

    // MARK: - 第 4 层: 镜面高光条 (斜 24°)

    private var specular: some View {
        Circle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.30),
                        .init(color: LockFaceStyle.specularTint(0.20), location: 0.44),
                        .init(color: LockFaceStyle.specularTint(0.52), location: 0.49),
                        .init(color: LockFaceStyle.specularTint(0.10), location: 0.56),
                        .init(color: .clear, location: 0.68)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .rotationEffect(.degrees(-24))
            .blur(radius: 3)
            .opacity((nightDim ? LockFaceStyle.nightDimFactor : 1) * 0.9)
            .clipShape(Circle())
            .padding(LockFaceStyle.faceInset)
            .allowsHitTesting(false)
    }

    // MARK: - 第 5 层: 字形 (闭环 / 开环, 不是文字)

    private var glyph: some View {
        ZStack {
            LockGlyphShape(open: false)
                .fill(glyphInk)
                .opacity(unlocked ? 0 : 1)
                .scaleEffect(unlocked ? 0.9 : 1)
            LockGlyphShape(open: true)
                .fill(glyphInk)
                .opacity(unlocked ? 1 : 0)
                .scaleEffect(unlocked ? 1 : 0.9)
        }
        .frame(width: LockFaceStyle.glyphSize, height: LockFaceStyle.glyphSize)
        .shadow(color: .black.opacity(0.55), radius: 1, x: 0, y: 1)
        .shadow(color: Color(hex: 0xFFF4E2).opacity(0.10), radius: 14)
        .allowsHitTesting(false)
    }

    /// 字形不是纯白: 自上而下由白转灰的一块料, 读起来像被上方的光打到。
    private var glyphInk: LinearGradient {
        LinearGradient(colors: LockFaceStyle.glyphColors, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - 充能环 (只在 p>0 时出现; 与 p 1:1)

    private var chargeRing: some View {
        Group {
            if progress > 0.001 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [DS.Palette.accentText, DS.Palette.accent, DS.Palette.accentText],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(LockFaceStyle.faceInset + 6)
                    .shadow(color: DS.Palette.accent.opacity(0.55), radius: 10)
                    // 1:1 跟手 —— 必须切断隐式动画继承, 否则它会跟着外层的 spring 走,
                    // 手指已经到 80% 了环还在半路追 (Apple Design §2 直接操纵)。
                    // 本仓 DESIGN-SPEC §2.5 也写了同一条纪律 (呼吸环那处)。
                    .transaction { $0.animation = nil }
                    .allowsHitTesting(false)
            }
        }
    }

    private var shadowColor: Color {
        Color(hex: 0x58442C).opacity(0.16 * (nightDim ? LockFaceStyle.nightDimFactor : 1))
    }
}

/// 锁体字形。两条路径照抄 v10 原型的 SVG (闭环 / 开环), 不是文字渲染。
/// 用 SwiftUI Path 手写: 不引位图, 也不用 SF Symbol (那会与"料"的渐变填充对不上)。
struct LockGlyphShape: Shape {
    let open: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width / 48.0   // v10 的 viewBox 是 48×48
        let h = rect.height / 48.0

        if open {
            // 开环: 挂锁的锁梁向右上抬起 (v10 的 .opn path)
            p.move(to: CGPoint(x: 15 * w, y: 20.5 * h))
            p.addLine(to: CGPoint(x: 15 * w, y: 15.5 * h))
            p.addQuadCurve(to: CGPoint(x: 36.3 * w, y: 11.7 * h),
                           control: CGPoint(x: 26.5 * w, y: 4.5 * h))
            p.addLine(to: CGPoint(x: 32 * w, y: 13.4 * h))
            p.addQuadCurve(to: CGPoint(x: 19.6 * w, y: 15.5 * h),
                           control: CGPoint(x: 24.5 * w, y: 11.7 * h))
            p.addLine(to: CGPoint(x: 19.6 * w, y: 20.5 * h))
            p.addLine(to: CGPoint(x: 22.2 * w, y: 20.5 * h))
            p.addQuadCurve(to: CGPoint(x: 27 * w, y: 25.3 * h),
                           control: CGPoint(x: 27 * w, y: 20.5 * h))
            p.addLine(to: CGPoint(x: 27 * w, y: 38.7 * h))
            p.addQuadCurve(to: CGPoint(x: 22.2 * w, y: 43.5 * h),
                           control: CGPoint(x: 27 * w, y: 43.5 * h))
            p.addLine(to: CGPoint(x: 7.8 * w, y: 43.5 * h))
            p.addQuadCurve(to: CGPoint(x: 3 * w, y: 38.7 * h),
                           control: CGPoint(x: 3 * w, y: 43.5 * h))
            p.addLine(to: CGPoint(x: 3 * w, y: 25.3 * h))
            p.addQuadCurve(to: CGPoint(x: 7.8 * w, y: 20.5 * h),
                           control: CGPoint(x: 3 * w, y: 20.5 * h))
            p.closeSubpath()
        } else {
            // 闭环: 锁梁扣死 (v10 的 .cls path)
            p.move(to: CGPoint(x: 13 * w, y: 20.5 * h))
            p.addLine(to: CGPoint(x: 13 * w, y: 15.5 * h))
            p.addQuadCurve(to: CGPoint(x: 35 * w, y: 15.5 * h),
                           control: CGPoint(x: 24 * w, y: 4.5 * h))
            p.addLine(to: CGPoint(x: 35 * w, y: 20.5 * h))
            p.addLine(to: CGPoint(x: 36.2 * w, y: 20.5 * h))
            p.addQuadCurve(to: CGPoint(x: 41 * w, y: 25.3 * h),
                           control: CGPoint(x: 41 * w, y: 20.5 * h))
            p.addLine(to: CGPoint(x: 41 * w, y: 38.7 * h))
            p.addQuadCurve(to: CGPoint(x: 36.2 * w, y: 43.5 * h),
                           control: CGPoint(x: 41 * w, y: 43.5 * h))
            p.addLine(to: CGPoint(x: 11.8 * w, y: 43.5 * h))
            p.addQuadCurve(to: CGPoint(x: 7 * w, y: 38.7 * h),
                           control: CGPoint(x: 7 * w, y: 43.5 * h))
            p.addLine(to: CGPoint(x: 7 * w, y: 25.3 * h))
            p.addQuadCurve(to: CGPoint(x: 11.8 * w, y: 20.5 * h),
                           control: CGPoint(x: 7 * w, y: 20.5 * h))
            p.closeSubpath()
        }
        return p
    }
}
