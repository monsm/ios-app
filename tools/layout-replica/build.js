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
const ds = rd('App/Core/DesignSystem.swift');
const num = (re) => { const m = re.exec(ds); return m ? parseFloat(m[1]) : null; };
const SPACE = {};
for (const m of ds.matchAll(/static var (xxs|xs|s|m|l|xl|xxl|gutter): CGFloat \{ d\((\d+(?:\.\d+)?)\)/g)) SPACE[m[1]] = +m[2];
const RADIUS = {};
for (const m of ds.matchAll(/static var (card|control|tile): CGFloat \{ r\((\d+(?:\.\d+)?)\)/g)) RADIUS[m[2] ? m[1] : m[1]] = +m[2];
const ICON = {};
for (const m of ds.matchAll(/static let (xs|sm|md|lg|xl): CGFloat = (\d+)/g)) ICON[m[1]] = +m[2];
const HIT = num(/enum Hit \{ static let min: CGFloat = (\d+)/);
const DIALS = (ds.match(/CGFloat\(\[160, 176, 200\]\.contains/) ? [160, 176, 200] : null);
const DIAL_DEF = num(/getInt\("kf_dial_size", (\d+)/);
const DENSITY = { compact: 0.85, standard: 1.0, relaxed: 1.18 };
const RK = { soft: 0.62, standard: 1.0, plump: 1.3 };

// 自适应色: Color.adaptive(浅, 深)
const ADAPT = {};
for (const m of ds.matchAll(/static let (\w+)\s*= Color\.adaptive\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)/g)) {
  ADAPT[m[1]] = { light: m[2].toUpperCase(), dark: m[3].toUpperCase() };
}
// 六套主题 × 明暗 × 角色 —— Swift 里是数组字面量 `[...]` 而不是字典 `{...}`，正则必须跟着形状走
const THEMES = {};
{
  const tbl = /static let themeTable[^=]*= \[([\s\S]*?)\n    \];/.exec(ds) || /static let themeTable[^=]*= \[([\s\S]*)/.exec(ds);
  if (tbl) {
    const body = tbl[1];
    const re = /"(\w+)":\s*\[\s*"light": \[([^\]]*)\],\s*"dark": \[([^\]]*)\]/g;
    let m;
    while ((m = re.exec(body))) {
      const parse = (seg) => { const o = {}; for (const k of seg.matchAll(/"(\w+)": 0x([0-9A-Fa-f]{6})/g)) o[k[1]] = k[2].toUpperCase(); return o; };
      THEMES[m[1]] = { light: parse(m[2]), dark: parse(m[3]) };
    }
  }
}
// heroFg / heroPlate / cardElevation (在别的文件里)
const ak = rd('App/Core/AccessibilityKit.swift');
const HERO_FG = /static var heroFg: Color \{[^}]*\? Palette\.text : (Color\.white|\.white)/.test(ak) ? '#FFFFFF' : null;
const PLATE = /static var heroPlate: Color \{ Color\.black\.opacity\(([\d.]+)\)/.exec(ds);
// 阴影: 源码顺序是 `== .dark ? white.withAlphaComponent(A) : black.withAlphaComponent(B)`
// ⇒ 第一个捕获属于 dark, 第二个属于 light。上一版按"light,dark"贴标签, 明暗正好读反。
const ELEV = /cardElevation[\s\S]{0,200}?== \.dark[\s\S]{0,120}?withAlphaComponent\(0\.(\d+)\)[\s\S]{0,120}?withAlphaComponent\(0\.(\d+)\)/.exec(rd('App/LockKeeperApp.swift'));

const missing = [];
if (!Object.keys(SPACE).length) missing.push('Space');
if (!Object.keys(RADIUS).length) missing.push('Radius');
if (!Object.keys(ICON).length) missing.push('Icon');
if (!Object.keys(THEMES).length) missing.push('themeTable');
if (HIT == null) missing.push('Hit');
if (!HERO_FG) missing.push('heroFg');
if (!PLATE) missing.push('heroPlate');
if (!DIALS) missing.push('dial 档位');

// ---------- 2. 内容抽取 (与 extract.js 同一口径, 内联一份免得两处漂) ----------
const E = require('./extract.js');
const content = E.extract();

const out = {
  generated: new Date().toISOString().slice(0, 16).replace('T', ' '),
  tokens: { SPACE, RADIUS, ICON, HIT, DIALS, DIAL_DEF, DENSITY, RK, ADAPT, THEMES, HERO_FG,
    plate: PLATE ? +PLATE[1] : null,
    // 捕获 1 = dark 分支, 捕获 2 = light 分支 (源码 ternary 的顺序就是先 dark)
    elev: ELEV ? { dark: +('0.' + ELEV[1]), light: +('0.' + ELEV[2]) } : null },
  missing, content,
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
