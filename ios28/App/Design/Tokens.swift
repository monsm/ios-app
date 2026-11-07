// Tokens.swift —— 由 DesignLab/tokens.json 生成（Tools/gen_tokens.js）。**不要手改这个文件。**
//
// 设计语言：DAYLIGHT / 日光阈值
//   · 颜色只有三个家族：陶土纸（canvas/ink 的无彩暖灰）、黄铜（唯一强调色）、语义色（危险/可证）。
//   · 字号全部带 Dynamic Type（TypeStyle 内部用 @ScaledMetric）。
//   · 任何页面都不许出现字面量颜色/字号/间距/圆角 —— 一律走 T.*。
import SwiftUI
import UIKit

enum T {
    enum C {
        static let canvas = adaptive(243, 240, 233, 1, 13, 15, 18, 1)
        static let canvasTop = adaptive(231, 238, 243, 1, 18, 24, 32, 1)
        static let canvasDeep = adaptive(234, 229, 219, 1, 9, 10, 12, 1)
        static let ink = adaptive(20, 22, 26, 1, 243, 241, 236, 1)
        static let ink2 = adaptive(85, 90, 97, 1, 168, 172, 178, 1)
        static let ink3 = adaptive(102, 107, 114, 1, 131, 136, 143, 1)
        static let ink4 = adaptive(154, 160, 167, 1, 86, 92, 100, 1)
        static let hair = adaptive(20, 22, 26, 0.0784, 243, 241, 236, 0.1216)
        static let hairStrong = adaptive(20, 22, 26, 0.149, 243, 241, 236, 0.2)
        static let danger = adaptive(168, 69, 46, 1, 226, 115, 92, 1)
        static let dangerWash = adaptive(168, 69, 46, 0.0941, 226, 115, 92, 0.1333)
        static let ok = adaptive(63, 114, 80, 1, 127, 176, 140, 1)
        static let onAccent = adaptive(255, 255, 255, 1, 13, 15, 18, 1)
        static let sky = adaptive(124, 153, 173, 1, 95, 127, 148, 1)
        static let sun = adaptive(235, 203, 156, 1, 138, 107, 69, 1)
        static let glass = adaptive(255, 255, 255, 0.7216, 27, 32, 39, 0.651)
        static let glassStrong = adaptive(255, 255, 255, 0.851, 35, 42, 50, 0.8)
        static let glassEdge = adaptive(255, 255, 255, 0.902, 255, 255, 255, 0.1216)
        static let shadow = adaptive(42, 36, 28, 0.1412, 0, 0, 0, 0.4)
        static let veil = adaptive(243, 240, 233, 0.902, 13, 15, 18, 0.902)
        static let atmoWarm = adaptive(240, 214, 176, 1, 110, 85, 54, 1)
        static let atmoCool = adaptive(255, 255, 255, 1, 81, 97, 110, 1)
        static let paneTop = adaptive(220, 233, 243, 1, 27, 40, 51, 1)
        static let paneMid = adaptive(237, 232, 222, 1, 22, 27, 33, 1)
        static let paneBot = adaptive(248, 243, 233, 1, 15, 18, 22, 1)
        static let paneWarm = adaptive(244, 210, 160, 1, 106, 77, 44, 1)
        static let paneCool = adaptive(255, 255, 255, 1, 126, 149, 166, 1)
        static let paneStreak = adaptive(255, 255, 255, 1, 185, 202, 214, 1)


        // MARK: H1 品牌色 —— 强调族运行时解析
        //
        // 外观页的品牌色（kf_accent 六套预设 + kf_accent_custom 自定义）整族换掉黄铜。
        // 对比度账：六套预设浅色档 vs 白字 ≥4.5（WCAG AA，与 ios27 同一组色值同一次自检）；
        // 深色档统一抬到 HSL 亮度 ≥0.62，近黑字压上去 ≥4.5。闸门只按默认黄铜断言
        // （Gates/contrast.js 读 tokens.json），预设与自定义由外观页的自检说明兜底。
        //
        // 注意：令牌层必须可在任何线程求值 —— 这里直接读 DB.store，
        // 不经过 @MainActor 的 SettingsStore（与 ios27 同一条纪律）。
        private static func accentBase() -> (lr: Double, lg: Double, lb: Double, dr: Double, dg: Double, db: Double)? {
            // 自定义优先（kf_accent_custom，0xRRGGBB；0 = 未启用）—— 与 ios27 同口径。
            let custom = DB.store.getInt("kf_accent_custom", 0)
            if custom > 0 {
                let r = Double((custom >> 16) & 0xFF), g = Double((custom >> 8) & 0xFF), b = Double(custom & 0xFF)
                let d = hslLift(r, g, b, 0.62)
                return (r, g, b, d.r, d.g, d.b)
            }
            switch DB.store.getString("kf_accent") {
            case "indigo":   return liftDark(5, 88, 184)
            case "forest":   return liftDark(29, 111, 95)
            case "amber":    return liftDark(180, 83, 9)
            case "graphite": return liftDark(91, 97, 105)
            case "rose":     return liftDark(190, 18, 60)
            case "aurora":   return liftDark(14, 116, 144)
            default:         return nil    // 默认黄铜
            }
        }

        /// 浅色档原样，深色档抬亮到 HSL 亮度下限（深纸上的可读性）。
        private static func liftDark(_ r: Double, _ g: Double, _ b: Double) -> (lr: Double, lg: Double, lb: Double, dr: Double, dg: Double, db: Double) {
            let d = hslLift(r, g, b, 0.62)
            return (r, g, b, d.r, d.g, d.b)
        }

        static var brass: Color {
            guard let a = accentBase() else { return adaptive(124, 90, 49, 1, 216, 180, 127, 1) }
            return adaptive(a.lr, a.lg, a.lb, 1, a.dr, a.dg, a.db, 1)
        }
        /// 亮黄铜（图形高亮）：同色相，浅色档 L+0.24 / 深色档 L+0.10（由默认值反推的差量）。
        static var brassBright: Color {
            guard let a = accentBase() else { return adaptive(199, 158, 99, 1, 233, 206, 163, 1) }
            let l = rgbHSL(a.lr, a.lg, a.lb)
            let d = rgbHSL(a.dr, a.dg, a.db)
            let lo = hslRGB(l.h, l.s, min(1, l.l + 0.24))
            let da = hslRGB(d.h, d.s, min(1, d.l + 0.10))
            return adaptive(lo.r, lo.g, lo.b, 1, da.r, da.g, da.b, 1)
        }
        /// 黄铜洗色（低透明填充）：随品牌色走，透明度沿用 tokens.json（0x24 / 0x26）。
        /// 派生口径与默认值一致：浅色档用「亮一档」的基色，深色档用基色本身。
        static var brassWash: Color {
            guard let a = accentBase() else { return adaptive(199, 158, 99, 0.1412, 216, 180, 127, 0.149) }
            let l = rgbHSL(a.lr, a.lg, a.lb)
            let lo = hslRGB(l.h, l.s, min(1, l.l + 0.24))
            return adaptive(lo.r, lo.g, lo.b, 0.1412, a.dr, a.dg, a.db, 0.149)
        }

        private static func hslLift(_ r: Double, _ g: Double, _ b: Double, _ minL: Double) -> (r: Double, g: Double, b: Double) {
            let hsl = rgbHSL(r, g, b)
            return hslRGB(hsl.h, hsl.s, max(hsl.l, minL))
        }

        private static func rgbHSL(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
            let rn = r / 255, gn = g / 255, bn = b / 255
            let mx = max(rn, gn, bn), mn = min(rn, gn, bn), d = mx - mn
            let l = (mx + mn) / 2
            guard d > 0 else { return (0, 0, l) }
            let s = d / (1 - abs(2 * l - 1))
            var h: Double
            if mx == rn { h = (gn - bn) / d }
            else if mx == gn { h = (bn - rn) / d + 2 }
            else { h = (rn - gn) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
            return (h, s, l)
        }

        private static func hslRGB(_ h: Double, _ s: Double, _ l: Double) -> (r: Double, g: Double, b: Double) {
            let c = (1 - abs(2 * l - 1)) * s
            let hp = h.truncatingRemainder(dividingBy: 360) / 60
            let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
            let rgb: (Double, Double, Double)
            switch hp {
            case ..<1: rgb = (c, x, 0)
            case ..<2: rgb = (x, c, 0)
            case ..<3: rgb = (0, c, x)
            case ..<4: rgb = (0, x, c)
            case ..<5: rgb = (x, 0, c)
            default:   rgb = (c, 0, x)
            }
            let m = l - c / 2
            return ((rgb.0 + m) * 255, (rgb.1 + m) * 255, (rgb.2 + m) * 255)
        }

        private static func adaptive(_ lr: Double, _ lg: Double, _ lb: Double, _ la: Double,
                                     _ dr: Double, _ dg: Double, _ db: Double, _ da: Double) -> Color {
            Color(uiColor: UIColor { traits in
                let dark = traits.userInterfaceStyle == .dark
                return UIColor(red: (dark ? dr : lr) / 255, green: (dark ? dg : lg) / 255,
                               blue: (dark ? db : lb) / 255, alpha: dark ? da : la)
            })
        }
    }

    enum F {
        static let display = TypeStyle(size: 44, weight: .regular, design: .serif, relativeTo: .largeTitle)
        static let displayS = TypeStyle(size: 34, weight: .regular, design: .serif, relativeTo: .title)
        static let title = TypeStyle(size: 28, weight: .semibold, design: .default, relativeTo: .title)
        static let title2 = TypeStyle(size: 22, weight: .semibold, design: .default, relativeTo: .title2)
        static let headline = TypeStyle(size: 17, weight: .semibold, design: .default, relativeTo: .headline)
        static let body = TypeStyle(size: 16, weight: .regular, design: .default, relativeTo: .body)
        static let callout = TypeStyle(size: 15, weight: .regular, design: .default, relativeTo: .callout)
        static let footnote = TypeStyle(size: 13, weight: .regular, design: .default, relativeTo: .footnote)
        static let caption = TypeStyle(size: 11.5, weight: .regular, design: .default, relativeTo: .caption2)
        static let kicker = TypeStyle(size: 10.5, weight: .semibold, design: .monospaced, relativeTo: .caption2)
        static let mono = TypeStyle(size: 12.5, weight: .regular, design: .monospaced, relativeTo: .caption)
        static let monoBig = TypeStyle(size: 17, weight: .medium, design: .monospaced, relativeTo: .callout)
        static let wordmark = TypeStyle(size: 40, weight: .regular, design: .serif, relativeTo: .largeTitle)
        static let wordmarkHero = TypeStyle(size: 68, weight: .regular, design: .serif, relativeTo: .largeTitle)
        static let heroTime = TypeStyle(size: 46, weight: .regular, design: .serif, relativeTo: .largeTitle)
        static let code = TypeStyle(size: 34, weight: .regular, design: .monospaced, relativeTo: .title2)
        static let codeSmall = TypeStyle(size: 26, weight: .regular, design: .monospaced, relativeTo: .title2)
        static let keypad = TypeStyle(size: 24, weight: .regular, design: .rounded, relativeTo: .title2)
        static let codeBig = TypeStyle(size: 44, weight: .regular, design: .monospaced, relativeTo: .largeTitle)
    }

    enum S {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let sm: CGFloat = 12
        static let m: CGFloat = 16
        static let ml: CGFloat = 20
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 56
        static let huge: CGFloat = 72
    }

    enum R {
        static let pane: CGFloat = 36
        static let card: CGFloat = 24
        static let tile: CGFloat = 18
        static let control: CGFloat = 14
        static let chip: CGFloat = 999
        static let sheet: CGFloat = 40
    }

    enum M {
        static let settle = Animation.spring(response: 0.45, dampingFraction: 0.86)
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.9)
        static let driftDuration: Double = 42
    }
}

// MARK: - 品牌色板建色出口（H1）

extension T.C {
    /// 由 0xRRGGBB **数据值**建色 —— 外观页色板 / 自定义强调色的回填都走这里。
    /// 页面层禁止直接写 Color(red:)（Gates/tokens.js），这是唯一出口：
    /// 色板是数据驱动的展示色，不是样式字面量。
    static func rgb(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - 字体样式

struct TypeStyle {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let relativeTo: Font.TextStyle

    var uiTextStyle: UIFont.TextStyle {
        switch relativeTo {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

private struct ScaledType: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(_ style: TypeStyle) {
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        weight = style.weight
        design = style.design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func type(_ style: TypeStyle) -> some View { modifier(ScaledType(style)) }
}

extension Text {
    /// Text 专用重载：保留 Text 的链式能力（tracking / fontWeight），
    /// 同时用 UIFontMetrics 跟随系统字号 —— 不能直接拿 style.size，那样会绕开 Dynamic Type。
    func type(_ style: TypeStyle) -> Text {
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: style.size)
        return font(.system(size: scaled, weight: style.weight, design: style.design))
    }
}
