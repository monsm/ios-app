#!/usr/bin/env node
// lab.js —— 视觉验收台：把 Swift 令牌解析成 CSS，把每屏渲染成 430x932 的帧，再用 Edge 截图。
//
// 为什么这样做：本地没有 Mac、没有 iOS 模拟器，SwiftUI 渲染不了。
// 但观感必须被看见 —— 静态闸门只能验数值，验不了这屏是不是三个卡片并排的模板脸。
// 所以这里用同一套 token 值做 1:1 HTML 镜像，逐屏截图。
//
// 2026-11-06（V10 · Quiet Instrument 视觉重做）：令牌来源从 V7Tokens 换成
// **Design/V8/V8Tokens.swift**（全 App 唯一的令牌层）。此前这里读的是 V7，
// 于是镜像与真机已经是两套设计语言 —— 截图看着"还行"，真机却是另一个样子。
//
// 诚实边界：① 不是 SwiftUI 布局引擎，CSS 近似；② Windows 无 PingFang，中文宽度有偏差；
// ③ 液态玻璃用 backdrop-filter 近似。能验版式/层级/间距/色彩/密度，不能验手势与真实折射。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
// 唯一令牌来源：App/Design/V8/V8Tokens.swift
const TOKENS = path.join(ROOT, 'App', 'Design', 'V8', 'V8Tokens.swift');
const src = fs.readFileSync(TOKENS, 'utf8');

// 按 enum 块切分再解析 —— 否则同名成员会互相覆盖。
function enumBlock(name) {
  const re = new RegExp('enum ' + name + ' \\{([\\s\\S]*?)\\n    \\}');
  const m = re.exec(src);
  return m ? m[1] : '';
}

// —— 颜色：static let x = dual(light, dark) 与 computed var x: Color { … } 都认。
// 带 alpha 的（lightAlpha/darkAlpha）解析成 rgba()。
const DUAL = {};
for (const m of src.matchAll(/static (?:let|var) (\w+)(?:\s*:\s*Color)?\s*=\s*dual\(\s*0x([0-9A-Fa-f]{6})\s*,\s*0x([0-9A-Fa-f]{6})(?:\s*,\s*lightAlpha:\s*([\d.]+)\s*,\s*darkAlpha:\s*([\d.]+))?\s*\)/g)) {
  DUAL[m[1]] = {
    light: m[2].toUpperCase(),
    dark: m[3].toUpperCase(),
    lightA: m[4] === undefined ? 1 : parseFloat(m[4]),
    darkA: m[5] === undefined ? 1 : parseFloat(m[5]),
  };
}
// computed var（高对比档）：取**最后一个** dual()，即默认外观的值。
for (const m of src.matchAll(/static var (\w+): Color \{([\s\S]*?)\n        \}/g)) {
  const pairs = [...m[2].matchAll(/dual\(\s*0x([0-9A-Fa-f]{6})\s*,\s*0x([0-9A-Fa-f]{6})(?:\s*,\s*lightAlpha:\s*([\d.]+)\s*,\s*darkAlpha:\s*([\d.]+))?\s*\)/g)];
  if (!pairs.length) continue;
  const p = pairs[pairs.length - 1];
  DUAL[m[1]] = {
    light: p[1].toUpperCase(),
    dark: p[2].toUpperCase(),
    lightA: p[3] === undefined ? 1 : parseFloat(p[3]),
    darkA: p[4] === undefined ? 1 : parseFloat(p[4]),
  };
}
function color(name, mode) {
  const c = DUAL[name];
  if (!c) return undefined;
  const hex = mode === 'dark' ? c.dark : c.light;
  const a = mode === 'dark' ? c.darkA : c.lightA;
  if (a >= 1) return '#' + hex;
  const n = parseInt(hex, 16);
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  return 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
}

// —— 间距 / 半径 / 高度 / 图形 / 描边 / 字号
const SPACE = {}, RADIUS = {}, HEIGHT = {}, GRAPHIC = {}, STROKE = {}, F = {};
const sBlock = enumBlock('S');
for (const m of sBlock.matchAll(/static (?:let|var) (\w+): CGFloat(?:\s*=\s*([\d.]+)|\s*\{\s*d\(([\d.]+)\))/g)) {
  const v = m[2] !== undefined ? +m[2] : +m[3];
  if (!Number.isNaN(v)) SPACE[m[1]] = v;
}
// 半径：V8.R 是 switch，取 default 分支的值（标准档）。
const rBlock = enumBlock('R');
const rDefault = /default:\s*return\s*([\d.]+)/.exec(rBlock);
const rDefaultValue = rDefault ? +rDefault[1] : 16;
for (const m of rBlock.matchAll(/static var (\w+): CGFloat/g)) RADIUS[m[1]] = rDefaultValue;
const hBlock = enumBlock('H');
for (const m of hBlock.matchAll(/static let (\w+): CGFloat = ([\d.]+)/g)) HEIGHT[m[1]] = +m[2];
const gBlock = enumBlock('G');
for (const m of gBlock.matchAll(/static let (\w+): CGFloat = ([\d.]+)/g)) GRAPHIC[m[1]] = +m[2];
const eBlock = enumBlock('E');
for (const m of eBlock.matchAll(/static let (\w+): CGFloat = ([\d.]+)/g)) STROKE[m[1]] = +m[2];
// 字号：V8.T 的每个档位是 `VFont(size: N, …)`。
const tBlock = enumBlock('T');
for (const m of tBlock.matchAll(/static let (\w+) = VFont\(size: ([\d.]+)/g)) F[m[1]] = +m[2];

const kebab = (v) => v.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());

// CSS 变量名沿用旧名（screens.js / primitives.js 里的 var(--x) 不用改），
// 值全部来自 V8 令牌 —— 变量名是"外壳"，值才是"事实"。
function rootVars(mode) {
  const out = [];
  const put = (name, value) => { if (value !== undefined) out.push('--' + name + ': ' + value + ';'); };

  // 表面
  put('paper', color('bgTop', mode));
  put('paper-2', color('bgBottom', mode));
  put('plate', color('card', mode));
  put('plate-top', color('cardTop', mode));
  put('plate-bottom', color('cardBottom', mode));
  put('plate-alt', color('well', mode));
  put('hairline', color('line', mode));
  put('shadow', color('shadow', mode));

  // 墨
  put('ink', color('ink1', mode));
  put('ink-sub', color('ink3', mode));
  put('ink-faint', color('ink4', mode));

  // 强调色：品牌六套由 kf_accent 派生，镜像里只能用默认那套（#0558B8 / #5AA7F5）。
  put('base', mode === 'dark' ? '#5AA7F5' : '#0558B8');
  put('on', mode === 'dark' ? '#08131F' : '#FFFFFF');

  // 语义
  put('ok', color('ok', mode));
  put('attention', color('warn', mode));
  put('critical', color('danger', mode));
  put('info', color('info', mode));

  // 间距
  put('sp-gutter', SPACE.gutterCard + 'px');
  put('sp-xs', SPACE.gapXS + 'px');
  put('sp-s', SPACE.gapS + 'px');
  put('sp-m', SPACE.gapM + 'px');
  put('sp-l', SPACE.gapL + 'px');
  put('sp-xl', SPACE.gapXL + 'px');
  put('sp-xxl', SPACE.gapXXL + 'px');
  put('sp-row', SPACE.rowHeight + 'px');
  put('sp-tag', SPACE.tagColumn + 'px');
  put('sp-hair', SPACE.hair + 'px');

  // 圆角
  put('r-plate', RADIUS.card + 'px');
  put('r-inset', RADIUS.inset + 'px');
  put('r-control', RADIUS.control + 'px');
  put('r-sheet', RADIUS.sheet + 'px');

  // 高度 / 描边
  put('h-chip', SPACE.hChip + 'px');
  put('h-action', HEIGHT.comfortable + 'px');
  put('h-min', HEIGHT.min + 'px');
  put('stroke-hair', STROKE.hair + 'px');
  put('stroke-focus', STROKE.focus + 'px');

  // 字号
  put('f-display', F.pageStatus + 'px');
  put('f-title', F.headline + 'px');
  put('f-body', F.body + 'px');
  put('f-reading', F.value + 'px');
  put('f-section', F.label + 'px');
  put('f-caption', F.caption + 'px');
  put('f-footnote', F.footnote + 'px');
  put('f-unit', F.micro + 'px');
  put('f-stamp', F.footnote + 'px');
  put('f-hero', F.heroL + 'px');

  return out.join(' ');
}

const cssBody = [
  '*{box-sizing:border-box;-webkit-font-smoothing:antialiased}',
  'body{margin:0;background:#101214;font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif;color:#c9ced4}',
  '.wrap{padding:24px}',
  '.grid{display:flex;flex-wrap:wrap;gap:28px;align-items:flex-start}',
  '.frame{width:var(--phone-w,430px)}',
  '.frame h2{font-size:12px;font-weight:600;color:#8d959d;margin:0 0 8px 4px;font-family:ui-monospace,Consolas,monospace}',
  '.frame h2 span{color:#5d646b;font-weight:400}',
  // 页面底：一条极浅冷灰渐变，没有彩色辉光（V10：页面之间不再各带一团光）。
  '.phone{width:var(--phone-w,430px);height:932px;background:linear-gradient(180deg,var(--paper),var(--paper-2));border-radius:44px;overflow:hidden;position:relative;box-shadow:0 24px 60px rgba(0,0,0,.5),0 0 0 1px rgba(255,255,255,.06);color:var(--ink)}',
  '.statusbar{height:54px;display:flex;align-items:center;justify-content:space-between;padding:0 32px;font-size:13px;font-weight:600;color:var(--ink)}',
  '.scroll{position:absolute;inset:54px 0 0 0;overflow:hidden;padding-bottom:96px}',
  '.scrollinner{height:100%;overflow-y:auto;padding-bottom:96px}',
  '.navbar{height:44px;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;color:var(--ink);position:relative}',
  '.navbar .tr{position:absolute;right:20px;top:50%;transform:translateY(-50%);font-size:19px;color:var(--base)}',
  '.tabbar{position:absolute;left:16px;right:16px;bottom:16px;height:56px;border-radius:28px;display:flex;align-items:center;background:color-mix(in srgb,var(--plate) 82%,transparent);backdrop-filter:blur(24px) saturate(1.4);box-shadow:inset 0 .5px 0 rgba(255,255,255,.35),0 6px 20px rgba(0,0,0,.12);z-index:20}',
  '.tabbar .t{flex:1;text-align:center;font-size:10.5px;color:var(--ink-faint);line-height:1.1}',
  '.tabbar .t b{display:block;font-size:17px;margin-bottom:2px;font-weight:400}',
  '.tabbar .t.on{color:var(--base)} .tabbar .t.on b{font-weight:600}',
  // 页头：系统大标题在上，22pt 状态行在下（V10 的层级）。
  '.phead{padding:4px var(--sp-gutter) 0}',
  '.phead h1{font-size:var(--f-display);font-weight:600;letter-spacing:-.2px;margin:0;color:var(--ink)}',
  '.pstat{display:flex;align-items:center;gap:var(--sp-s);margin-top:var(--sp-xs);font-size:var(--f-body);color:var(--ink-sub)}',
  // 卡片：近白面板 + 0.4pt 描边 + 一级柔和投影（V10）。
  '.panel{background:linear-gradient(180deg,var(--plate-top),var(--plate-bottom));border-radius:var(--r-plate);padding:var(--sp-l);margin:0 var(--sp-gutter);box-shadow:0 10px 24px var(--shadow),0 2px 4px var(--shadow);border:var(--stroke-hair) solid var(--hairline)}',
  '.inset{background:var(--plate-alt);border-radius:var(--r-inset);padding:var(--sp-m);border:var(--stroke-hair) solid var(--hairline)}',
  '.slabel{display:flex;align-items:baseline;justify-content:space-between;font-size:var(--f-title);font-weight:600;color:var(--ink)}',
  '.slabel em{font-style:normal;font-size:var(--f-unit);font-weight:400;color:var(--ink-faint);letter-spacing:.6px}',
  '.reading{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace;font-variant-numeric:tabular-nums;letter-spacing:-.2px}',
  '.reading i{font-style:normal;font-size:var(--f-unit);font-weight:400;color:var(--ink-faint);letter-spacing:.6px;margin-left:3px}',
  '.cap{display:block;font-size:var(--f-unit);color:var(--ink-faint);letter-spacing:.6px;margin-bottom:2px}',
  '.rgrid{display:grid;gap:var(--sp-m)}',
  '.hair{height:var(--stroke-hair);background:var(--hairline);border:0;margin:var(--sp-s) 0}',
  '.frow{display:flex;align-items:baseline;justify-content:space-between;gap:var(--sp-m);min-height:var(--sp-row);font-size:var(--f-body);color:var(--ink-sub)}',
  '.frow .reading{color:var(--ink)}',
  '.dot{display:inline-block;width:7px;height:7px;border-radius:50%;flex:0 0 auto}',
  '.dot.t-critical{border-radius:1.2px;width:6px;height:6px}',
  '.dot.t-attention{width:0;height:0;border:0;border-left:4px solid transparent;border-right:4px solid transparent;border-bottom:7px solid var(--attention)}',
  '.t-ok{color:var(--base)} .t-critical{color:var(--critical)} .t-attention{color:var(--attention)} .t-live{color:var(--base)}',
  '.sline{display:inline-flex;align-items:center;gap:var(--sp-s);font-size:var(--f-caption)}',
  '.sub{color:var(--ink-sub)}',
  '.chips{display:flex;gap:var(--sp-s);padding:0 var(--sp-gutter);overflow:hidden}',
  '.chip{height:var(--h-chip);padding:0 var(--sp-m);border-radius:999px;border:var(--stroke-hair) solid var(--hairline);background:var(--plate-alt);font:inherit;font-size:var(--f-caption);color:var(--ink-sub)}',
  '.chip.on{background:var(--base);border-color:var(--base);color:var(--on)}',
  '.btn{height:var(--h-action);border-radius:var(--r-control);border:0;font:inherit;font-size:var(--f-body);font-weight:600;width:100%}',
  '.btn.primary{background:var(--base);color:var(--on)}',
  '.btn.secondary{background:var(--plate-alt);color:var(--ink);box-shadow:inset 0 0 0 var(--stroke-hair) var(--hairline)}',
  '.btn.narrow{width:240px;margin:0 auto}',
  '.lrow{display:flex;align-items:baseline;gap:var(--sp-m);min-height:48px;padding:6px 0}',
  '.stamp{width:48px;font-family:ui-monospace,Consolas,monospace;font-size:var(--f-stamp);color:var(--ink)}',
  '.stamp em{display:block;font-style:normal;font-size:var(--f-unit);color:var(--ink-faint)}',
  '.lev{flex:1}',
  '.lev span{display:block;font-size:var(--f-body);color:var(--ink)}',
  '.lev em{display:block;font-style:normal;font-size:var(--f-unit);color:var(--ink-sub)}',
  '.dhead{display:flex;justify-content:space-between;align-items:baseline;padding:var(--sp-l) var(--sp-gutter) var(--sp-xs);font-size:var(--f-title);font-weight:600;color:var(--ink)}',
  '.srow{display:flex;align-items:center;gap:var(--sp-m);min-height:44px;font-size:var(--f-body);color:var(--ink)}',
  '.srow .glyph{width:28px;color:var(--ink-sub)}',
  '.srow i{margin-left:auto;font-style:normal;color:var(--ink-faint);font-size:13px}',
  '.srow+.srow{border-top:var(--stroke-hair) solid var(--hairline)}',
  '.dial{position:relative;display:flex;align-items:center;justify-content:center;margin:0 auto}',
  '.dial svg{position:absolute;inset:0}',
  '.hub{text-align:center;width:52%}',
  '.hub b{display:block;font-family:ui-monospace,Consolas,monospace;font-size:30px;font-weight:600;color:var(--ink)}',
  '.hub em{display:block;font-style:normal;font-size:var(--f-unit);color:var(--ink-faint);letter-spacing:.6px;margin-top:2px}',
  '.hub p{margin:var(--sp-s) 0 0;font-size:var(--f-caption);color:var(--ink-sub)}',
  '.empty{text-align:center;padding:var(--sp-xxl) var(--sp-l)}',
  '.empty .eglyph{display:block;font-size:40px;color:var(--ink-faint);margin-bottom:var(--sp-m)}',
  '.empty b{display:block;font-size:var(--f-title);color:var(--ink);margin-bottom:var(--sp-xs)}',
  '.empty p{margin:0 0 var(--sp-l);font-size:var(--f-body);color:var(--ink-sub);line-height:1.5}',
  '.gap{height:var(--sp-l)} .gap-s{height:var(--sp-s)} .gap-m{height:var(--sp-m)}',
  '.row{display:flex;gap:var(--sp-m);margin:0 var(--sp-gutter)} .row>*{flex:1}',
  '.banner{display:flex;align-items:center;gap:var(--sp-s);margin:0 var(--sp-gutter);padding:var(--sp-m) var(--sp-l);border-radius:var(--r-control);background:color-mix(in srgb,var(--critical) 10%,transparent);font-size:var(--f-caption);color:var(--critical)}',
  '.note{font-size:var(--f-body);color:var(--ink-sub);line-height:1.55;padding:0 var(--sp-gutter)}',
  '.foot{padding:var(--sp-l) var(--sp-gutter);font-size:var(--f-unit);color:var(--ink-faint);text-align:center}',
  '.kv{display:flex;justify-content:space-between;align-items:baseline;padding:var(--sp-s) 0;font-size:var(--f-body);color:var(--ink-sub)}',
  '.badge{display:inline-block;padding:1px 6px;border-radius:999px;font-size:var(--f-unit);letter-spacing:.6px;background:color-mix(in srgb,var(--base) 14%,transparent);color:var(--base)}',
  '.badge.warn{background:color-mix(in srgb,var(--attention) 14%,transparent);color:var(--attention)}',
  '.badge.bad{background:color-mix(in srgb,var(--critical) 14%,transparent);color:var(--critical)}',
  '.grid2{display:grid;grid-template-columns:1fr 1fr;gap:var(--sp-m)}',
  '.cal{display:grid;grid-template-columns:repeat(7,1fr);gap:4px;text-align:center;font-size:var(--f-unit);color:var(--ink-sub)}',
  '.cal b{font-weight:400;color:var(--ink-faint);padding:2px 0}',
  '.cal span{padding:5px 0;border-radius:6px}',
  '.cal span.on{background:color-mix(in srgb,var(--base) 14%,transparent);color:var(--base)}',
  '.ladder{display:flex;gap:var(--sp-s);margin:0 var(--sp-gutter)}',
  '.ladder .step{flex:1;padding:var(--sp-s) var(--sp-m);border-radius:var(--r-control);background:var(--plate-alt);border:var(--stroke-hair) solid var(--hairline)}',
  '.ladder .num{display:block;font-family:ui-monospace,Consolas,monospace;font-size:var(--f-unit);color:var(--ink-faint)}',
  '.ladder .lbl{display:block;font-size:var(--f-caption);color:var(--ink-sub);margin-top:2px}',
  '.ladder .step.now{background:color-mix(in srgb,var(--base) 10%,var(--plate));border-color:color-mix(in srgb,var(--base) 40%,transparent)}',
  '.ladder .step.now .num,.ladder .step.now .lbl{color:var(--base)}',
  '.ladder .step.done .num{color:var(--ink-sub)} .ladder .step.done .lbl{color:var(--ink)}',
  '.avatar{width:32px;height:32px;border-radius:50%;background:var(--plate-alt);display:inline-flex;align-items:center;justify-content:center;font-size:var(--f-caption);color:var(--ink-sub)}',
  '.toggle{width:44px;height:26px;border-radius:999px;background:var(--plate-alt);border:var(--stroke-hair) solid var(--hairline);position:relative}',
  '.toggle.on{background:var(--base)} .toggle i{position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:50%;background:#fff;transition:none}',
  '.toggle.on i{left:21px}',
].join('\n');

module.exports = { SPACE, RADIUS, HEIGHT, GRAPHIC, STROKE, F, DUAL, kebab, color, rootVars, cssBody };
