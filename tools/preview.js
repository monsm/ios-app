#!/usr/bin/env node
// tools/preview.js — 从**现役令牌**生成一张可渲染的门厅预览, 并用无头浏览器截图。
//
//   node tools/preview.js            生成 tools/preview/home.html
//   node tools/preview.js --png      再截图到 docs/GLASS/preview-home.png (需要 Edge/Chrome)
//
// ⚠️ 能力边界 (必须先读, 否则会把它当成验证):
//
//   这**不是** SwiftUI 布局引擎。它是用 flex/grid 手工复刻的门厅骨架, 数值从
//   App/Core/Theme.swift 现场解析。所以它能证明的和不能证明的必须分清:
//
//   ✅ 能证明: 令牌解析链路是通的 (Theme.swift → 数值 → 渲染 → 像素);
//              改一个令牌, 这里立刻能看见它在界面上的样子;
//              渲染出来的颜色**确实是**令牌定义的那个颜色 (可逐像素取样核对)。
//   ❌ 不能证明: 真实 SwiftUI 的布局结果。字宽、lineLimit 行为、
//              安全区、Dynamic Type 重排、玻璃在真机上的明度 —— 一条都验不了。
//              这些仍然要真机 / 模拟器。
//
// 为什么值得留着: 2026-10-22 发现上一个复刻器读的是**已删除**的 DesignSystem.swift,
// 一跑就 ENOENT, 整条视觉链路断了一个月没人发现。一个能跑的最小闭环,
// 比一个「看起来很全但已经崩了」的工具更有用。
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const theme = fs.readFileSync(path.join(ROOT, 'App/Core/Theme.swift'), 'utf8');

// ---------- 令牌解析 (唯一来源: Theme.swift) ----------
// 2026-10-23：令牌改回**深浅双值**（App 只跟随系统，不提供配色选择）。
// 预览渲染**深色档** —— 那是规范的实测基准，也是这个复刻器一直在验的那一档。
const COLORS = {};
for (const m of theme.matchAll(/static var (\w+): Color \{ Color\.adaptive\(0x[0-9A-Fa-f]{6}, 0x([0-9A-Fa-f]{6})\) \}/g)) {
  COLORS[m[1]] = { dark: '#' + m[2] };
}
for (const m of theme.matchAll(/static var (\w+): Color \{ Color\(hex: 0x([0-9A-Fa-f]{6})\) \}/g)) {
  if (!COLORS[m[1]]) COLORS[m[1]] = { dark: '#' + m[2] };
}
// 半透明令牌：按底色合成（预览里主要压在卡片/画布上）
const ALPHA = {};
for (const m of theme.matchAll(/static var (\w+): Color \{ Color\.white\.opacity\(([0-9.]+)\) \}/g)) {
  ALPHA[m[1]] = parseFloat(m[2]);
}
if (!COLORS.canvas) COLORS.canvas = { dark: '#000000' };
if (!COLORS.accent) COLORS.accent = { dark: '#D98B45' };
if (!COLORS.accentText) COLORS.accentText = { dark: '#E8A05C' };

const SP = {};
for (const m of theme.matchAll(/static var (\w+): CGFloat \{ d\((\d+(?:\.\d+)?)\) \}/g)) SP[m[1]] = +m[2];
const RAD = {};
for (const m of theme.matchAll(/static var (\w+): CGFloat \{ r\((\d+(?:\.\d+)?)\) \}/g)) RAD[m[1]] = +m[2];
const RING = {};
{
  const s = theme.slice(theme.indexOf('enum DSRing'), theme.indexOf('enum DSRing') + 1400);
  const cur = /static let cursor: CGFloat = (\d+)/.exec(s); if (cur) RING.cursor = +cur[1];
  const stk = /static let minStrokeLarge: CGFloat = (\d+)/.exec(s); if (stk) RING.minStrokeLarge = +stk[1];
  // 三个手写的 Color(hex:) —— 它们不是 Color.adaptive, 通用循环抓不到。
  // 这里必须显式取: 取不到就渲染成品红 (c() 的兜底), 一眼能看出漏了。
  for (const [k, re] of [['innerDisc', /static var innerDisc: Color \{ Color\(hex: 0x([0-9A-Fa-f]{6})\) \}/],
                         ['trackTop', /static var trackTop: Color \{ Color\(hex: 0x([0-9A-Fa-f]{6})\) \}/],
                         ['trackBottom', /static var trackBottom: Color \{ Color\(hex: 0x([0-9A-Fa-f]{6})\) \}/]]) {
    const m = re.exec(s); if (m) RING[k] = '#' + m[1].toUpperCase();
  }
}

// 自检: 解析不到就立刻失败 —— 这正是上一个复刻器的死因 (它崩了但没人跑)。
const missing = [];
if (!Object.keys(SP).length) missing.push('XSpace');
if (!Object.keys(RAD).length) missing.push('XRadius');
if (!COLORS.surface) missing.push('surface');
if (!RING.minStrokeLarge) missing.push('DSRing.minStrokeLarge');
if (missing.length) {
  console.error('✗ 令牌解析失败: ' + missing.join(', ') + ' —— Theme.swift 的结构变了?');
  process.exit(1);
}

// --light 用浅色档渲染同一套骨架 —— 规范 G1 要求「玻璃在亮/黑两种背景各看一次」。
// 复刻件不能替代真机, 但它至少能让「浅色档到底长什么样」这件事**第一次有画面**。
const LIGHT = process.argv.includes('--light');
// 规范 §13.4「应用体：只做深色」。浅色档已随明暗双模一并删除 ——
// 留着 --light 会渲染出一张**不存在的界面**，那种图比没有图更误导。
if (LIGHT) {
  console.error('✗ --light 已停用：规范 §13.4 规定应用体只做深色，浅色档已从令牌层删除。');
  console.error('  再渲染它只会得到一张不存在的界面。用 node tools/preview.js --png 出深色档。');
  process.exit(1);
}
const MODE = LIGHT ? 'light' : 'dark';
// 环那三个手写色是深色档专用, 浅色档给近似值 (规范只给了深色档的环色)。
const RING_LIGHT = { innerDisc: '#FFFFFF', trackTop: '#C8C8D2', trackBottom: '#ADADB8' };
const c = (k, onTop) => {
  if (LIGHT && RING_LIGHT[k]) return RING_LIGHT[k];
  if (COLORS[k]) return COLORS[k].dark;
  if (ALPHA[k] != null) {
    const bg = onTop || (MODE === 'light' ? '#F2F2F7' : '#000000');
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(bg.slice(i, i + 2), 16));
    const mix = (v, t) => Math.round(ALPHA[k] * 255 + (1 - ALPHA[k]) * v);
    return 'rgb(' + mix(r) + ',' + mix(g) + ',' + mix(b) + ')';
  }
  if (RING[k]) return RING[k];
  return '#FF00FF';
};   // 品红 = 令牌缺失, 一眼可见
const align = SP.gutter + SP.card - 1;

// ---------- 样式 ----------
const L = [];
const p = (s) => L.push(s);
p('*{margin:0;padding:0;box-sizing:border-box}');
p('body{width:390px;overflow-x:hidden;background:' + c('canvas') + ';color:' + c('text') + ';font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif}');
p('.phone{width:390px;padding:0 ' + SP.gutter + 'px 120px}');
p('.masthead{display:flex;justify-content:space-between;align-items:center;height:20px;font-size:13px;color:' + c('textSub') + ';margin-top:8px}');
p('.pill{font-size:11px;padding:2px 8px;border-radius:999px;background:' + c('ok') + '22;color:' + c('ok') + '}');
p('.title{font-size:30px;font-weight:700;letter-spacing:-.4px;margin-top:' + (SP.titleToFirstCard - SP.section) + 'px}');
p('.digest{font-size:16px;color:' + c('textSub') + ';margin-top:' + SP.s + 'px}');
p('.sec{margin-top:' + SP.section + 'px}');
p('.card{background:' + c('surface') + ';border-radius:' + RAD.card + 'px;border:1px solid ' + c('hairline') + ';padding:' + SP.card + 'px}');
// 环按 SwiftUI 的真实做法复刻 (HomeConsole.unlockStage):
//   内盘 DSRing.innerDisc (深海军蓝, 不是黑) → 轨道上暗下亮渐变 → 蓄力弧角度渐变 + 圆头
//   → 18pt 游标 → Canvas 外一层 300pt 辉光 blur40 opacity .12
p('.ring-wrap{display:flex;justify-content:center;align-items:center;margin-top:' + SP.section + 'px;height:260px;position:relative}');
p('.ring-glow{position:absolute;width:300px;height:300px;border-radius:50%;background:radial-gradient(circle,' + c('accent') + '59 0%,transparent 70%);filter:blur(40px);opacity:.5}');
p('.ring{width:220px;height:220px;border-radius:50%;position:relative;display:flex;align-items:center;justify-content:center;background:conic-gradient(from 0deg,' + c('accent') + ' 0deg,' + c('accent') + ' 0deg,transparent 0deg)}');
p('.ring-track{position:absolute;inset:0;border-radius:50%;background:conic-gradient(from 0deg,' + c('trackTop') + ',' + c('trackBottom') + ',' + c('trackTop') + ')}');
p('.ring-mask{position:absolute;inset:' + RING.minStrokeLarge + 'px;border-radius:50%;background:' + c('innerDisc') + '}');
p('.ring-arc{position:absolute;inset:0;border-radius:50%;background:conic-gradient(from 0deg,' + c('accent') + '99 0deg,' + c('accent') + ' 130deg,transparent 130deg);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - ' + RING.minStrokeLarge + 'px),#000 calc(100% - ' + RING.minStrokeLarge + 'px))}');
// 游标骑在**轨道中线上**: 半径 = 110 - 线宽/2。用极坐标算 left/top, 比 transform-origin 稳。
const RING_R = 110, RING_MID = RING_R - RING.minStrokeLarge / 2, ARC_DEG = 130;
const curX = RING_R + RING_MID * Math.sin(ARC_DEG * Math.PI / 180) - RING.cursor / 2;
const curY = RING_R - RING_MID * Math.cos(ARC_DEG * Math.PI / 180) - RING.cursor / 2;
p('.ring-cursor{position:absolute;width:' + RING.cursor + 'px;height:' + RING.cursor + 'px;border-radius:50%;background:' + c('accent') + ';left:' + curX + 'px;top:' + curY + 'px;box-shadow:0 0 8px ' + c('accent') + '88}');
p('.ring-inner{position:relative;z-index:2;text-align:center}');
p('.ring-glyph{font-size:42px}');
p('.ring-cap{font-size:12px;color:' + c('textTertiary') + ';margin-top:4px;text-align:center}');
p('.metrics{display:flex;margin-top:' + SP.section + 'px}');
p('.metric{flex:1;text-align:center}');
p('.metric .l{font-size:14px;color:' + c('textSub') + ';margin-bottom:2px}');
p('.metric .v{font-size:19px;font-weight:600}');
p('.divider{width:1px;background:' + c('hairline') + ';margin:0 4px}');
// 规范 §7.9: 柱状图是 **1px 发丝线阵列**, 无圆角无渐变; 非当前时段 25% 不透明度。
// 背后是虚线竖向网格 (1pt, rgba(255,255,255,.10), 5-6 条)。
p('.chart-wrap{position:relative;height:46px}');
p('.grid-v{position:absolute;inset:0;display:flex;justify-content:space-between}');
p('.grid-v i{width:1px;background:repeating-linear-gradient(to bottom,rgba(255,255,255,.10) 0 2px,transparent 2px 5px)}');
p('.chart{position:absolute;inset:0;display:flex;align-items:flex-end;gap:1px}');
p('.bar{flex:1;min-width:1px;background:' + c('accent') + ';opacity:.25}');
p('.bar.on{opacity:1}');
p('.bar.zero{opacity:1;background:' + c('hairline') + '}');
p('.axis{display:flex;justify-content:space-between;font-size:10px;color:' + c('textTertiary') + ';margin-top:' + SP.xs + 'px}');
p('.label{font-size:11px;font-weight:600;letter-spacing:.8px;color:' + c('textTertiary') + ';margin-bottom:' + SP.s + 'px}');
// 规范 §7.11 卡内标题链接: 14pt textSub + 12pt chevron, 箭头距文字 4pt
p('.cardlink{display:flex;align-items:center;gap:' + SP.xxs + 'px;font-size:14px;color:' + c('textSub') + ';min-height:44px}');
p('.cardlink .ch{font-size:12px;color:' + c('specular') + ';opacity:.45}');
p('.cardhead{display:flex;justify-content:space-between;align-items:center}');
p('.cardhr{height:1px;background:' + c('hairline') + ';margin:14px 0}');
p('.kv{margin-top:2px}');
p('.kv .k{font-size:12px;color:' + c('textSub') + '}');
p('.kv .v{font-size:16px;font-weight:600}');
p('.foot{font-size:12px;line-height:1.6;color:' + c('textSub') + ';margin-top:12px}');
p('.statcard-title{font-size:19px;font-weight:700;color:' + c('text') + ';margin-top:6px;line-height:1.2}');
p('.statrow{display:flex;align-items:center;justify-content:space-between;margin-top:12px}');
p('.miniring{width:104px;height:104px}');
p('.row2{display:flex;gap:' + SP.rowGap + 'px}');
p('.chip{height:52px;border-radius:' + RAD.chip + 'px;background:' + c('surfaceChip') + ';border:1px solid rgba(255,255,255,.10);display:flex;align-items:center;gap:10px;padding:0 14px;flex:1}');
p('.chip .ico{width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,.08);display:flex;align-items:center;justify-content:center;font-size:15px}');
p('.chip .t{font-size:14px;color:' + c('textSub') + '}');
p('.chip .val{font-size:14px;font-weight:600}');
p('.grid{display:grid;grid-template-columns:repeat(5,1fr);gap:' + SP.colGap + 'px}');
p('.tile{height:62px;border-radius:' + RAD.tile + 'px;background:' + c('surface') + ';border:1px solid ' + c('hairline') + ';display:flex;flex-direction:column;align-items:center;justify-content:center;gap:7px}');
p('.tile .ti{font-size:19px}');
p('.tile .tt{font-size:13px;color:' + c('textSub') + '}');
// 玻璃 Tab: 真 backdrop-filter + 选中项一枚**独立的玻璃胶囊**（不是给文字换色就算）
// ultraThinMaterial 是**自适应**的（SwiftUI 侧就是这么写的）。复刻件必须跟着走 ——
// 之前这里写死 rgba(28,28,30,.72)（深色玻璃），于是浅色档渲染出一个「浅底上的黑胶囊」，
// 那是我复刻件的失真，不是 App 的缺陷。这一点必须分清。
const TAB_BG = LIGHT ? 'rgba(255,255,255,.72)' : 'rgba(28,28,30,.72)';
const TAB_EDGE = LIGHT ? 'rgba(0,0,0,.10)' : 'rgba(255,255,255,.14)';
const TAB_SHADOW = LIGHT ? '0 8px 32px rgba(0,0,0,.16)' : '0 8px 32px rgba(0,0,0,.55)';
const TAB_GLOSS = LIGHT ? 'rgba(255,255,255,.70)' : 'rgba(255,255,255,.10)';
const TAB_PILL = LIGHT ? 'rgba(0,0,0,.06)' : 'rgba(255,255,255,.10)';
const TAB_IDLE = LIGHT ? 'rgba(60,60,67,.60)' : 'rgba(235,235,245,.55)';
p('.tabbar{position:fixed;bottom:18px;left:' + SP.gutter + 'px;width:' + (390 - SP.gutter * 2) + 'px;height:58px;border-radius:999px;background:' + TAB_BG + ';backdrop-filter:blur(30px) saturate(180%);-webkit-backdrop-filter:blur(30px) saturate(180%);border:.5px solid ' + TAB_EDGE + ';display:flex;align-items:center;padding:0 5px;box-shadow:' + TAB_SHADOW + ',inset 0 1px 0 ' + TAB_GLOSS + '}');
p('.tab{flex:1;height:46px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;font-size:10px;color:' + TAB_IDLE + ';border-radius:999px}');
p('.tab .ico{font-size:18px;line-height:1}');
p('.tab.on{color:' + c('accentText') + ';background:' + TAB_PILL + ';box-shadow:inset 0 1px 0 ' + TAB_GLOSS + '}');
p('.legend{margin-top:' + SP.section + 'px;font-size:11px;line-height:1.8;color:' + c('textSub') + ';border-top:1px solid ' + c('hairline') + ';padding-top:' + SP.m + 'px}');
p('.legend b{color:' + c('text') + '}');

const bars = Array.from({ length: 24 }, (_, h) => {
  const v = h === 8 ? 46 : h === 7 ? 24 : h === 18 ? 34 : h === 9 ? 12 : 0;
  const cls = v === 0 ? 'zero' : (h === 8 ? 'on' : '');
  return '<div class="bar ' + cls + '" style="height:' + Math.max(1, v) + 'px"></div>';
}).join('');

const body = [
  '<div class="phone">',
  '<div class="masthead"><span>9:41</span><span class="pill">● 已连接</span></div>',
  '<div class="title">家门</div>',
  '<div class="digest">今天开过 3 次 · 近 30 天 2 人用过</div>',
  '<div class="ring-wrap">',
  '  <div class="ring-glow"></div>',
  '  <div class="ring"><div class="ring-track"></div><div class="ring-mask"></div>',
  '    <div class="ring-arc"></div><div class="ring-cursor"></div>',
  '    <div class="ring-inner"><div class="ring-glyph">🔒</div><div class="ring-cap">按住开锁</div></div>',
  '  </div>',
  '</div>',
  '<div class="metrics"><div class="metric"><div class="l">今日开门</div><div class="v">3</div></div>',
  '<div class="divider"></div><div class="metric"><div class="l">今日成员</div><div class="v">2</div></div>',
  '<div class="divider"></div><div class="metric"><div class="l">最早开门</div><div class="v">07:12</div></div></div>',
  '<div class="sec"><div class="card">',
  '  <div class="cardlink">今天<span class="ch">›</span></div>',
  '  <div class="chart-wrap"><div class="grid-v"><i></i><i></i><i></i><i></i><i></i><i></i></div>',
  '  <div class="chart">' + bars + '</div></div>',
  '  <div class="axis"><span>0</span><span>6</span><span>12</span><span>18</span><span>24</span></div>',
  '  <div class="cardhr"></div>',
  '  <div class="kv"><div class="k">最早一次</div><div class="v">07:12</div></div>',
  '  <div class="foot">今天 3 次开门，其中 2 次由成员完成。柱高是该小时的开门次数。</div>',
  '</div></div>',
  // ── 规范 §7.6 StatCard：卡头 › 标题 → 标签/值 + **右侧环槽** → 分隔线 → 页脚 ──
  '<div class="sec"><div class="card">',
  '  <div class="cardlink">保养<span class="ch">›</span></div>',
  '  <div class="statcard-title">该做保养了</div>',
  '  <div class="statrow"><div><div class="k">距离下次</div><div class="v">该做</div></div>',
  '  <div class="miniring"><svg viewBox="0 0 104 104"><circle cx="52" cy="52" r="44" fill="none" stroke="' + c('surfaceAlt') + '" stroke-width="12"/>',
  '  <circle cx="52" cy="52" r="44" fill="none" stroke="' + c('warn') + '" stroke-width="12" stroke-linecap="round" stroke-dasharray="276.5" stroke-dashoffset="0" transform="rotate(-90 52 52)"/>',
  '  <text x="52" y="58" text-anchor="middle" font-size="20" font-weight="600" fill="' + c('text') + '">100%</text></svg></div></div>',
  '  <div class="cardhr"></div>',
  '  <div class="foot">高频使用会把保养周期缩短到 60 天。上次记录在 92 天前。</div>',
  '</div></div>',
  '<div class="sec"><div class="cardlink">成员<span class="ch">›</span></div><div class="row2">',
  '<div class="chip"><div class="ico">👤</div><div><div class="t">张三</div><div class="val">今天 2 次</div></div></div>',
  '<div class="chip"><div class="ico">👤</div><div><div class="t">李四</div><div class="val">今天 1 次</div></div></div></div></div>',
  '<div class="sec"><div class="label">管理</div><div class="grid">',
  ['钥匙','设备','成员','安全','数据'].map((t, i) => '<div class="tile"><div class="ti">' + ['🔑','📱','👥','🛡','💾'][i] + '</div><div class="tt">' + t + '</div></div>').join(''),
  '</div></div>',
  '<div class="legend"><b>本页所有数值均由 Theme.swift 现场解析</b><br>',
  '页边距 gutter=' + SP.gutter + 'pt · 区块 section=' + SP.section + 'pt · 卡内边距=' + SP.card + 'pt<br>',
  '卡片圆角=' + RAD.card + 'pt · 胶囊圆角=' + RAD.chip + 'pt · 行距=' + SP.rowGap + 'pt · 列距=' + SP.colGap + 'pt<br>',
  '标题→首卡=' + SP.titleToFirstCard + 'pt · 文字对齐线=' + align + 'pt<br>',
  '大环线宽=' + RING.minStrokeLarge + 'pt (§14-21 下限 30) · 游标=' + RING.cursor + 'pt (§7.8)</div></div>',
  '<div class="tabbar">' + [['◉','设备'],['⌘','钥匙'],['☰','记录'],['⚙','设置']].map(([i, t], k) => '<div class="tab' + (k === 0 ? ' on' : '') + '"><span class="ico">' + i + '</span><span>' + t + '</span></div>').join('') + '</div>',
].join('');

const html = '<!DOCTYPE html><html><head><meta charset="utf-8"><style>' + L.join('') + '</style></head><body>' + body + '</body></html>';
const dir = path.join(__dirname, 'preview');
fs.mkdirSync(dir, { recursive: true });
const htmlPath = path.join(dir, LIGHT ? 'home-light.html' : 'home.html');
fs.writeFileSync(htmlPath, html);
console.log('✓ ' + path.relative(ROOT, htmlPath) + '  (' + (html.length / 1024).toFixed(1) + ' KB)');
console.log('  令牌: gutter=' + SP.gutter + ' section=' + SP.section + ' card=' + SP.card +
            ' radius.card=' + RAD.card + ' ring=' + RING.minStrokeLarge + '/' + RING.cursor);

if (process.argv.includes('--png')) {
  const cands = [
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
  ];
  const exe = cands.find((x) => fs.existsSync(x));
  if (!exe) { console.log('· 没有找到 Edge/Chrome, 跳过截图'); process.exit(0); }
  const outPng = path.join(ROOT, LIGHT ? 'docs/GLASS/preview-home-light.png' : 'docs/GLASS/preview-home.png');
  execFileSync(exe, ['--headless=new', '--disable-gpu', '--hide-scrollbars',
    '--window-size=390,1180', '--screenshot=' + outPng, '--virtual-time-budget=2500',
    'file:///' + htmlPath.replace(/\\/g, '/')], { stdio: 'ignore' });
  console.log('✓ ' + path.relative(ROOT, outPng) + '  (' + (fs.statSync(outPng).size / 1024).toFixed(1) + ' KB)');
}
// ---------- --check: 逐像素核对渲染结果与令牌是否一致 ----------
//
// 这是本工具**唯一**能给出的硬证据: 渲染出来的颜色确实是令牌定义的那个色。
// 它不能证明 SwiftUI 长这样, 但能证明「令牌 → 像素」这条链路没断。
if (process.argv.includes('--check')) {
  const zlib = require('zlib');
  // 规范 §13.4：应用体**只做深色**。所以只验深色一档 ——
  // 浅色档在第十轮已随「明暗双模」一并删除，再验它等于验一个不存在的界面。
  const targets = [
    { mode: 'dark',  png: path.join(ROOT, 'docs/GLASS/preview-home.png'),
      spec: { canvas: '#000000', surface: '#1C1C1E' } },   // 规范 §2.1 / §2.2
  ];
  for (const t of targets) {
    if (!fs.existsSync(t.png)) { console.error('✗ 缺少 ' + t.mode + ' 渲染，先跑 node tools/preview.js --png' + (t.mode === 'light' ? ' --light' : '')); process.exit(1); }
  }
  function decode(buf) {
    const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20), colorType = buf[25];
    const bpp = colorType === 6 ? 4 : 3;
    let off = 8; const idat = [];
    while (off < buf.length) {
      const len = buf.readUInt32BE(off), type = buf.toString('ascii', off + 4, off + 8);
      if (type === 'IDAT') idat.push(buf.slice(off + 8, off + 8 + len));
      if (type === 'IEND') break;
      off += 12 + len;
    }
    const raw = zlib.inflateSync(Buffer.concat(idat));
    const stride = w * bpp, out = Buffer.alloc(h * stride);
    let pos = 0;
    for (let y = 0; y < h; y++) {
      const ft = raw[pos++]; const line = raw.slice(pos, pos + stride); pos += stride;
      const prev = y > 0 ? out.slice((y - 1) * stride, y * stride) : Buffer.alloc(stride);
      for (let x = 0; x < stride; x++) {
        const a = x >= bpp ? out[y * stride + x - bpp] : 0;
        const b = prev[x], cc = x >= bpp ? prev[x - bpp] : 0;
        let v = line[x];
        if (ft === 1) v += a; else if (ft === 2) v += b; else if (ft === 3) v += (a + b) >> 1;
        else if (ft === 4) {
          const pa = Math.abs(b - cc), pb = Math.abs(a - cc), pc = Math.abs(a + b - 2 * cc);
          v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : cc);
        }
        out[y * stride + x] = v & 255;
      }
    }
    return { w, h, bpp, px: (x, y) => { const i = y * stride + x * bpp; return [out[i], out[i + 1], out[i + 2]]; } };
  }
  const probesFor = {
    dark: [['画布 canvas', 2, 2, '#000000'], ['卡片 surface', 195, 640, '#1C1C1E']],
  };
  let bad = 0;
  for (const t of targets) {
    const img = decode(fs.readFileSync(t.png));
    const hex = (r) => '#' + r.map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase();
    console.log('  [' + t.mode + ']');
    for (const [name, x, y, expect] of probesFor[t.mode]) {
      const got = hex(img.px(x, y));
      const ok = got === expect;
      if (!ok) bad++;
      console.log('  ' + (ok ? '✓ ' : '✗ ') + name + ' 期望 ' + expect + ' 实测 ' + got);
    }
  }
  if (bad) { console.error('✗ 渲染与规范常量不一致 ' + bad + ' 处'); process.exit(1); }
  console.log('✓ 令牌 → 渲染 → 像素 链路一致');
}