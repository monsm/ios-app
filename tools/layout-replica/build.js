#!/usr/bin/env node
// 布局复刻生成器 —— 从 Swift 源码解析设计令牌 + 抽取可见内容, 生成可自检的单文件 HTML。
//
//   node tools/layout-replica/build.js        生成 tools/layout-replica/index.html
//
// 为什么做成生成器而不是手写 HTML: 手写的复刻会漂成"我以为的界面"。这里每个数值都从
// App/Core/DesignSystem.swift 现场解析, 每块内容都带 Swift 出处 (文件:行), 页面上直接可查。
//
// 诚实边界 (页面上也写了): ① 这不是 SwiftUI 布局引擎, flex 近似 stack; ② 中文字宽在 Windows
// 上没有 PingFang, 用雅黑度量 ⇒ 提供"中文字宽补偿"滑杆把裁切测出来; ③ 液态玻璃用 backdrop-filter 近似。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');
const rd = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

// ---------- 1. 令牌解析 ----------
//
// 2026-10-22: 原来读的是 `App/Core/DesignSystem.swift` —— 该文件已于 2026-10-21 整份删除,
// 于是这个生成器**一跑就 ENOENT**, 整个视觉复刻链路断了一轮没人发现。
// 现役令牌唯一真相源是 `App/Core/Theme.swift` 的 XPalette / XSpace / XRadius / XIcon / XHit / DSRing。
// 判据: 改令牌来源后, 立刻跑一次这个脚本 —— 它崩了就是没接上。
const themeSrc = rd('App/Core/Theme.swift');

// 间距: XSpace 里的 d(N)
const SPACE = {};
for (const m of themeSrc.matchAll(/static var (\w+): CGFloat \{ d\((\d+(?:\.\d+)?)\) \}/g)) SPACE[m[1]] = +m[2];
// 圆角: XRadius 里的 r(N)
const RADIUS = {};
for (const m of themeSrc.matchAll(/static var (\w+): CGFloat \{ r\((\d+(?:\.\d+)?)\) \}/g)) RADIUS[m[1]] = +m[2];
// 图标: XIcon 的 static let N: CGFloat = M
const ICON = {};
{
  const sec = themeSrc.slice(themeSrc.indexOf("enum XIcon"), themeSrc.indexOf("enum XIcon") + 600);
  for (const m of sec.matchAll(/static let (\w+): CGFloat = (\d+(?:\.\d+)?)/g)) ICON[m[1]] = +m[2];
}
// 触达: XHit.min
const HIT = (() => { const m = /static let min: CGFloat = (\d+)/.exec(themeSrc); return m ? +m[1] : null; })();
// 环: DSRing 的三个数（这是本轮新增的令牌族，复刻页要能看见它）
const RING = {};
{
  const sec = themeSrc.slice(themeSrc.indexOf("enum DSRing"), themeSrc.indexOf("enum DSRing") + 900);
  const cur = /static let cursor: CGFloat = (\d+)/.exec(sec);
  const minStroke = /static let minStrokeLarge: CGFloat = (\d+)/.exec(sec);
  if (cur) RING.cursor = +cur[1];
  if (minStroke) RING.minStrokeLarge = +minStroke[1];
}

const DIALS = null;      // 圆盘档位随锁面层一起删除, 保留字段让模板不必改
const DIAL_DEF = null;
const DENSITY = { compact: 0.85, standard: 1.0, relaxed: 1.18 };
const RK = { soft: 0.62, standard: 1.0, plump: 1.3 };

// 自适应色: Color.adaptive(浅, 深)
// 规范 §13.4：只做深色 —— 令牌已改为单值 Color(hex:)。
const ADAPT = {};
for (const m of themeSrc.matchAll(/static var (\w+): Color \{ Color\(hex: 0x([0-9A-Fa-f]{6})\) \}/g)) {
  ADAPT[m[1]] = { dark: m[2].toUpperCase() };
}
// canvas 走 isAMOLED 三元分支, 正则抓不到 —— 单独补
if (!ADAPT.canvas) {
  const cm = /isAMOLED \? \.black : Color\.adaptive\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)/.exec(themeSrc);
  if (cm) ADAPT.canvas = { light: cm[1].toUpperCase(), dark: '000000' };
}
// accent 带 kf_accent 覆盖分支
if (!ADAPT.accent) {
  const am = /static var accent: Color \{[\s\S]*?return Color\.adaptive\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)/.exec(themeSrc);
  if (am) ADAPT.accent = { light: am[1].toUpperCase(), dark: am[2].toUpperCase() };
}

// 主题: XPalette 只有一个默认强调色 + 六套备选 (accentOverride)。
// 复刻页要的是"同一界面在六种强调色下的样子", 所以按 accentOverride 展开。
const THEMES = { default: { light: {}, dark: {} } };
let lastLight = (ADAPT.accent || {}).light, lastDark = (ADAPT.accent || {}).dark;
for (const m of themeSrc.matchAll(/case "(\w+)":\s*return \(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)/g)) {
  THEMES[m[1]] = { light: { accent: m[2].toUpperCase() }, dark: { accent: m[3].toUpperCase() } };
}

// hero 相关: 新设计里 hero 是 XGradient.hero, 不再有 heroFg/heroPlate 两个令牌
const HERO_FG = '#FFFFFF';                     // 渐变卡上的文字一律浅色
const PLATE = null;                            // 不再有黑纱层

const missing = [];
if (!Object.keys(SPACE).length) missing.push('Space');
if (!Object.keys(RADIUS).length) missing.push('Radius');
if (!Object.keys(ICON).length) missing.push('Icon');
if (HIT == null) missing.push('Hit');
if (!ADAPT.canvas) missing.push('canvas 色');
if (!ADAPT.surface) missing.push('surface 色');

// ---------- 2. 内容抽取 (与 extract.js 同一口径, 内联一份免得两处漂) ----------
const E = require('./extract.js');
const content = E.extract();

const out = {
  generated: new Date().toISOString().slice(0, 16).replace('T', ' '),
  tokens: { SPACE, RADIUS, ICON, HIT, DIALS, DIAL_DEF, DENSITY, RK, ADAPT, THEMES, HERO_FG, RING,
    plate: PLATE ? +PLATE[1] : null,
    // 新设计系统: 卡片零投影 (规范 §6.3), 没有 elevation 可解析。
    elev: null },
  missing,
  content,
};
fs.writeFileSync(path.join(__dirname, 'tokens.json'), JSON.stringify(out, null, 1));
if (missing.length) console.log('!! 没解析到:', missing.join(','));
// 生成 HTML (单文件, 内容与令牌已内联, 可直接双击打开)
const { render } = require('./template.js');
const html = render(out.tokens, out.content, { generated: out.generated });
fs.writeFileSync(path.join(__dirname, 'index.html'), html);
console.log('index.html 已生成', (html.length / 1024).toFixed(1) + ' KB —', path.join(__dirname, 'index.html'));
console.log('令牌: Space', JSON.stringify(SPACE), 'Radius', JSON.stringify(RADIUS), 'Icon', JSON.stringify(ICON), 'Hit', HIT);
console.log('主题', Object.keys(THEMES).length, '套:', Object.keys(THEMES).join('/'), '| adaptive 色', Object.keys(ADAPT).length, '组');
console.log('heroFg', HERO_FG, '| heroPlate 黑@', out.tokens.plate, '| 阴影 alpha', JSON.stringify(out.tokens.elev));
console.log('内容: Tab', content.tabs.length, '| 设置节', content.settings.length, '| 设备模块', content.device.length, '| 快捷格', content.quickAll.length);
if (missing.length) console.log('!! 没解析到:', missing.join(','));
