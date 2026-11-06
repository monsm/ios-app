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
        static let brass = adaptive(124, 90, 49, 1, 216, 180, 127, 1)
        static let brassBright = adaptive(199, 158, 99, 1, 233, 206, 163, 1)
        static let brassWash = adaptive(199, 158, 99, 0.1412, 216, 180, 127, 0.149)
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
