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
  const colorLines = keys.map((k) => {
    const l = hexToSwift(L[k]);
    const d = hexToSwift(D[k] || L[k]);
    return `        static let ${camel(k)} = adaptive(${fmt(l.r)}, ${fmt(l.g)}, ${fmt(l.b)}, ${fmt(l.a)}, ` +
      `${fmt(d.r)}, ${fmt(d.g)}, ${fmt(d.b)}, ${fmt(d.a)})`;
  }).join('\n');

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
