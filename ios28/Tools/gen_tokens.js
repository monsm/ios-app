#!/usr/bin/env node
// gen_tokens.js —— 从 DesignLab/tokens.json 生成两端的令牌：
//   · App/Design/Tokens.swift   （Swift 唯一来源）
//   · DesignLab/tokens.css      （视觉验收台的 CSS 变量）
//
// 为什么生成而不是手写两份：颜色/字号/间距在两个端各写一遍，第一周就会漂。
// `node Tools/gen_tokens.js --check` 只比对不写盘，供 Gates/tokensync.js 使用。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'DesignLab', 'tokens.json');
const SWIFT_OUT = path.join(ROOT, 'App', 'Design', 'Tokens.swift');
const CSS_OUT = path.join(ROOT, 'DesignLab', 'tokens.css');

const t = JSON.parse(fs.readFileSync(SRC, 'utf8'));

const camel = (s) => s;
const hexToSwift = (hex) => {
  const h = hex.replace('#', '');
  // #RRGGBB 或 #RRGGBBAA
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  const a = h.length === 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1;
  return { r, g, b, a };
};
const fmt = (n) => (Number.isInteger(n) ? String(n) : String(Number(n.toFixed(4))));

function swift() {
  const L = t.colors.light, D = t.colors.dark;
  const keys = Object.keys(L);
  // H1 品牌色：强调族三色不走 static let，而是运行时解析（外观页可整族换色）。
  // 生成器仍产出默认值回落 —— 未设置 kf_accent 时与 tokens.json 完全同值，像素不漂。
  const ACCENT_DYNAMIC = ['brass', 'brassBright', 'brassWash'];
  const hex = (k, mode) => hexToSwift(t.colors[mode][k] || t.colors.light[k]);
  const alphaOf = (k, mode) => hex(k, mode).a;
  const colorLines = keys.filter((k) => !ACCENT_DYNAMIC.includes(k)).map((k) => {
    const l = hexToSwift(L[k]);
    const d = hexToSwift(D[k] || L[k]);
    return `        static let ${camel(k)} = adaptive(${fmt(l.r)}, ${fmt(l.g)}, ${fmt(l.b)}, ${fmt(l.a)}, ` +
      `${fmt(d.r)}, ${fmt(d.g)}, ${fmt(d.b)}, ${fmt(d.a)})`;
  }).join('\n');
  const brass = hex('brass', 'light'), brassD = hex('brass', 'dark');
  const brassB = hex('brassBright', 'light'), brassBD = hex('brassBright', 'dark');
  const accentBlock = `
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
            guard let a = accentBase() else { return adaptive(${fmt(brass.r)}, ${fmt(brass.g)}, ${fmt(brass.b)}, 1, ${fmt(brassD.r)}, ${fmt(brassD.g)}, ${fmt(brassD.b)}, 1) }
            return adaptive(a.lr, a.lg, a.lb, 1, a.dr, a.dg, a.db, 1)
        }
        /// 亮黄铜（图形高亮）：同色相，浅色档 L+0.24 / 深色档 L+0.10（由默认值反推的差量）。
        static var brassBright: Color {
            guard let a = accentBase() else { return adaptive(${fmt(brassB.r)}, ${fmt(brassB.g)}, ${fmt(brassB.b)}, 1, ${fmt(brassBD.r)}, ${fmt(brassBD.g)}, ${fmt(brassBD.b)}, 1) }
            let l = rgbHSL(a.lr, a.lg, a.lb)
            let d = rgbHSL(a.dr, a.dg, a.db)
            let lo = hslRGB(l.h, l.s, min(1, l.l + 0.24))
            let da = hslRGB(d.h, d.s, min(1, d.l + 0.10))
            return adaptive(lo.r, lo.g, lo.b, 1, da.r, da.g, da.b, 1)
        }
        /// 黄铜洗色（低透明填充）：随品牌色走，透明度沿用 tokens.json（0x24 / 0x26）。
        /// 派生口径与默认值一致：浅色档用「亮一档」的基色，深色档用基色本身。
        static var brassWash: Color {
            guard let a = accentBase() else { return adaptive(${fmt(brassB.r)}, ${fmt(brassB.g)}, ${fmt(brassB.b)}, ${fmt(alphaOf('brassWash', 'light'))}, ${fmt(brassD.r)}, ${fmt(brassD.g)}, ${fmt(brassD.b)}, ${fmt(alphaOf('brassWash', 'dark'))}) }
            let l = rgbHSL(a.lr, a.lg, a.lb)
            let lo = hslRGB(l.h, l.s, min(1, l.l + 0.24))
            return adaptive(lo.r, lo.g, lo.b, ${fmt(alphaOf('brassWash', 'light'))}, a.dr, a.dg, a.db, ${fmt(alphaOf('brassWash', 'dark'))})
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
`.trimEnd();

  const typeLines = Object.keys(t.type).map((k) => {
    const v = t.type[k];
    const w = v.weight;
    const d = v.design;
    return `        static let ${k} = TypeStyle(size: ${fmt(v.size)}, weight: .${w}, design: .${d}, relativeTo: .${v.relativeTo})`;
  }).join('\n');

  const spaceLines = Object.keys(t.space).map((k) => `        static let ${k}: CGFloat = ${fmt(t.space[k])}`).join('\n');
  const radiusLines = Object.keys(t.radius).map((k) => `        static let ${k}: CGFloat = ${fmt(t.radius[k])}`).join('\n');

  const m = t.motion;
  return `// Tokens.swift —— 由 DesignLab/tokens.json 生成（Tools/gen_tokens.js）。**不要手改这个文件。**
//
// 设计语言：DAYLIGHT / 日光阈值
//   · 颜色只有三个家族：陶土纸（canvas/ink 的无彩暖灰）、黄铜（唯一强调色）、语义色（危险/可证）。
//   · 字号全部带 Dynamic Type（TypeStyle 内部用 @ScaledMetric）。
//   · 任何页面都不许出现字面量颜色/字号/间距/圆角 —— 一律走 T.*。
import SwiftUI
import UIKit

enum T {
    enum C {
${colorLines}

${accentBlock}

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
${typeLines}
    }

    enum S {
${spaceLines}
    }

    enum R {
${radiusLines}
    }

    enum M {
        static let settle = Animation.spring(response: ${fmt(m.settle.response)}, dampingFraction: ${fmt(m.settle.damping)})
        static let snap = Animation.spring(response: ${fmt(m.snap.response)}, dampingFraction: ${fmt(m.snap.damping)})
        static let driftDuration: Double = ${fmt(m.drift.duration)}
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
`;
}

function css() {
  const block = (mode) => Object.keys(t.colors[mode]).map((k) => `  --${k}: ${t.colors[mode][k]};`).join('\n');
  const typeCss = Object.keys(t.type).map((k) => {
    const v = t.type[k];
    const family = v.design === 'serif' ? '"Songti SC","Noto Serif SC","Source Han Serif SC",SimSun,serif'
      : v.design === 'monospaced' ? 'ui-monospace,"SF Mono","Cascadia Mono",Consolas,monospace'
        : '-apple-system,"SF Pro Display","Segoe UI","Microsoft YaHei",sans-serif';
    return `  --font-${k}: ${v.weight === 'regular' ? 400 : 600} ${v.size / 16}rem/${Math.round(v.size * (v.design === 'serif' ? 1.18 : 1.4)) / 16}rem ${family};`;
  }).join('\n');
  const spaceCss = Object.keys(t.space).map((k) => `  --sp-${k}: ${t.space[k]}px;`).join('\n');
  const radiusCss = Object.keys(t.radius).map((k) => `  --r-${k}: ${t.radius[k]}px;`).join('\n');
  return `/* tokens.css —— 由 DesignLab/tokens.json 生成。不要手改。 */
:root[data-mode="light"] {
${block('light')}
}
:root[data-mode="dark"] {
${block('dark')}
}
:root {
${typeCss}
${spaceCss}
${radiusCss}
}
`;
}

const out = { [SWIFT_OUT]: swift(), [CSS_OUT]: css() };
const check = process.argv.includes('--check');
let bad = false;
for (const [file, content] of Object.entries(out)) {
  const old = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
  if (check) {
    if (old !== content) { console.error('令牌漂移: ' + path.relative(ROOT, file)); bad = true; }
  } else {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content, 'utf8');
  }
}
if (!check) console.log('gen_tokens: 已生成 Tokens.swift 与 tokens.css');
else if (bad) process.exit(1);
