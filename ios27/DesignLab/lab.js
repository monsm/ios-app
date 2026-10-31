#!/usr/bin/env node
// lab.js —— 视觉验收台：把 Swift 令牌解析成 CSS，把每屏渲染成 430x932 的帧，再用 Edge 截图。
//
// 为什么这样做：本地没有 Mac、没有 iOS 模拟器，SwiftUI 渲染不了。
// 但观感必须被看见 —— 静态闸门只能验数值，验不了这屏是不是三个卡片并排的模板脸。
// 所以这里用同一套 token 值做 1:1 HTML 镜像，逐屏截图。
//
// 诚实边界：① 不是 SwiftUI 布局引擎，CSS 近似；② Windows 无 PingFang，中文宽度有偏差；
// ③ 液态玻璃用 backdrop-filter 近似。能验版式/层级/间距/色彩/密度，不能验手势与真实折射。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const TOKENS = path.join(ROOT, 'App', 'Design', 'Tokens.swift');
const src = fs.readFileSync(TOKENS, 'utf8');

// 按 enum 块切分再解析 —— 否则 "s/m/l/xl" 在 Spacing 与 Icon 两个枚举里同名，会互相覆盖。
function enumBlock(name) {
  const re = new RegExp('enum ' + name + ' \\{([\\s\\S]*?)\\n    \\}');
  const m = re.exec(src);
  return m ? m[1] : '';
}
const SPACE = {}, RADIUS = {}, HEIGHT = {}, ICON = {}, STROKE = {};
const collect = (block, re, into) => { for (const m of block.matchAll(re)) into[m[1]] = +m[2]; };
collect(enumBlock('S'), /static let (xxs|xs|s|m|l|xl|xxl|gutter): CGFloat = ([\d.]+)/g, SPACE);
collect(enumBlock('R'), /static let (plate|inset|control|pill): CGFloat = ([\d.]+)/g, RADIUS);
collect(enumBlock('H'), /static let (chip|action|row): CGFloat = ([\d.]+)/g, HEIGHT);
collect(enumBlock('Icon'), /static let (s|m|l|xl): CGFloat = ([\d.]+)/g, ICON);
collect(enumBlock('Stroke'), /static let (hair|focus): CGFloat = ([\d.]+)/g, STROKE);

const F = {};
const num1 = (re, dflt) => { const m = re.exec(src); return m ? +m[1] : dflt; };
F.display = num1(/func display\(_ size: CGFloat = (\d+)/, 34);
F.section = num1(/static let section = Font\.system\(size: (\d+)/, 13);
F.body = num1(/static let body = Font\.system\(size: (\d+)/, 15);
F.caption = num1(/static let caption = Font\.system\(size: (\d+)/, 13);
F.unit = num1(/static let unit = Font\.system\(size: (\d+)/, 11);
F.stamp = num1(/static let stamp = Font\.system\(size: (\d+)/, 13);
F.reading = num1(/func reading\(_ size: CGFloat = (\d+)/, 17);

const DUAL = {};
for (const m of src.matchAll(/static let (\w+)\s*=\s*Color\.dual\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})\)/g)) {
  DUAL[m[1]] = { light: m[2].toUpperCase(), dark: m[3].toUpperCase() };
}
const kebab = (v) => v.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());

function rootVars(mode) {
  const out = [];
  for (const k of Object.keys(DUAL)) out.push('--' + kebab(k) + ': #' + DUAL[k][mode] + ';');
  for (const k of Object.keys(SPACE)) out.push('--sp-' + k + ': ' + SPACE[k] + 'px;');
  for (const k of Object.keys(RADIUS)) out.push('--r-' + k + ': ' + RADIUS[k] + 'px;');
  for (const k of Object.keys(HEIGHT)) out.push('--h-' + k + ': ' + HEIGHT[k] + 'px;');
  for (const k of Object.keys(ICON)) out.push('--i-' + k + ': ' + ICON[k] + 'px;');
  for (const k of Object.keys(STROKE)) out.push('--stroke-' + k + ': ' + STROKE[k] + 'px;');
  for (const k of Object.keys(F)) out.push('--f-' + k + ': ' + F[k] + 'px;');
  return out.join(' ');
}

const cssBody = [
  '*{box-sizing:border-box;-webkit-font-smoothing:antialiased}',
  'body{margin:0;background:#101214;font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif;color:#c9ced4}',
  '.wrap{padding:24px}',
  '.grid{display:flex;flex-wrap:wrap;gap:28px;align-items:flex-start}',
  '.frame{width:430px}',
  '.frame h2{font-size:12px;font-weight:600;color:#8d959d;margin:0 0 8px 4px;font-family:ui-monospace,Consolas,monospace}',
  '.frame h2 span{color:#5d646b;font-weight:400}',
  '.phone{width:430px;height:932px;background:var(--paper);border-radius:44px;overflow:hidden;position:relative;box-shadow:0 24px 60px rgba(0,0,0,.5),0 0 0 1px rgba(255,255,255,.06);color:var(--ink)}',
  '.statusbar{height:54px;display:flex;align-items:center;justify-content:space-between;padding:0 32px;font-size:13px;font-weight:600;color:var(--ink)}',
  '.scroll{position:absolute;inset:54px 0 0 0;overflow:hidden;padding-bottom:96px}',
  '.scrollinner{height:100%;overflow-y:auto;padding-bottom:96px}',
  '.navbar{height:44px;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;color:var(--ink);position:relative}',
  '.navbar .tr{position:absolute;right:20px;top:50%;transform:translateY(-50%);font-size:19px;color:var(--base)}',
  '.tabbar{position:absolute;left:16px;right:16px;bottom:16px;height:56px;border-radius:28px;display:flex;align-items:center;background:color-mix(in srgb,var(--plate) 74%,transparent);backdrop-filter:blur(24px) saturate(1.4);box-shadow:inset 0 .5px 0 rgba(255,255,255,.35),0 6px 20px rgba(0,0,0,.12);z-index:20}',
  '.tabbar .t{flex:1;text-align:center;font-size:10.5px;color:var(--ink-faint);line-height:1.1}',
  '.tabbar .t b{display:block;font-size:17px;margin-bottom:2px;font-weight:400}',
  '.tabbar .t.on{color:var(--base)} .tabbar .t.on b{font-weight:600}',
  '.phead{padding:4px var(--sp-gutter) 0}',
  '.phead h1{font-size:var(--f-display);font-weight:600;letter-spacing:-.4px;margin:0;color:var(--ink)}',
  '.pstat{display:flex;align-items:center;gap:var(--sp-s);margin-top:var(--sp-xs);font-size:var(--f-caption);color:var(--ink-sub)}',
  '.panel{background:var(--plate);border-radius:var(--r-plate);padding:var(--sp-l);margin:0 var(--sp-gutter);box-shadow:inset 0 0 0 var(--stroke-hair) var(--hairline)}',
  '.inset{background:var(--plate-alt);border-radius:var(--r-inset);padding:var(--sp-m)}',
  '.slabel{display:flex;align-items:baseline;justify-content:space-between;font-size:var(--f-section);font-weight:600;color:var(--ink-sub)}',
  '.slabel em{font-style:normal;font-size:var(--f-unit);font-weight:400;color:var(--ink-faint);letter-spacing:.6px}',
  '.reading{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace;font-variant-numeric:tabular-nums;letter-spacing:-.2px}',
  '.reading i{font-style:normal;font-size:var(--f-unit);font-weight:400;color:var(--ink-faint);letter-spacing:.6px;margin-left:3px}',
  '.cap{display:block;font-size:var(--f-unit);color:var(--ink-faint);letter-spacing:.6px;margin-bottom:2px}',
  '.rgrid{display:grid;gap:var(--sp-m)}',
  '.hair{height:var(--stroke-hair);background:var(--hairline);border:0;margin:var(--sp-s) 0}',
  '.frow{display:flex;align-items:baseline;justify-content:space-between;gap:var(--sp-m);min-height:36px;font-size:var(--f-body);color:var(--ink-sub)}',
  '.frow .reading{color:var(--ink)}',
  '.dot{display:inline-block;width:7px;height:7px;border-radius:50%;flex:0 0 auto}',
  '.dot.t-critical{border-radius:1.2px;width:6px;height:6px}',
  '.dot.t-attention{width:0;height:0;border:0;border-left:4px solid transparent;border-right:4px solid transparent;border-bottom:7px solid var(--attention)}',
  '.t-ok{color:var(--base)} .t-critical{color:var(--critical)} .t-attention{color:var(--attention)} .t-live{color:var(--base)}',
  '.sline{display:inline-flex;align-items:center;gap:var(--sp-s);font-size:var(--f-caption)}',
  '.sub{color:var(--ink-sub)}',
  '.chips{display:flex;gap:var(--sp-s);padding:0 var(--sp-gutter);overflow:hidden}',
  '.chip{height:var(--h-chip);padding:0 var(--sp-m);border-radius:999px;border:var(--stroke-hair) solid var(--hairline);background:transparent;font:inherit;font-size:var(--f-caption);color:var(--ink-sub)}',
  '.chip.on{background:color-mix(in srgb,var(--base) 12%,transparent);border-color:color-mix(in srgb,var(--base) 35%,transparent);color:var(--ink)}',
  '.btn{height:var(--h-action);border-radius:var(--r-control);border:0;font:inherit;font-size:var(--f-body);font-weight:500;width:100%}',
  '.btn.primary{background:var(--base);color:var(--on)}',
  '.btn.secondary{background:transparent;color:var(--ink);box-shadow:inset 0 0 0 var(--stroke-hair) var(--hairline)}',
  '.btn.narrow{width:240px;margin:0 auto}',
  '.lrow{display:flex;align-items:baseline;gap:var(--sp-m);min-height:48px;padding:6px 0}',
  '.stamp{width:48px;font-family:ui-monospace,Consolas,monospace;font-size:var(--f-stamp);color:var(--ink)}',
  '.stamp em{display:block;font-style:normal;font-size:var(--f-unit);color:var(--ink-faint)}',
  '.lev{flex:1}',
  '.lev span{display:block;font-size:var(--f-body);color:var(--ink)}',
  '.lev em{display:block;font-style:normal;font-size:var(--f-unit);color:var(--ink-sub)}',
  '.dhead{display:flex;justify-content:space-between;align-items:baseline;padding:var(--sp-l) var(--sp-gutter) var(--sp-xs);font-size:var(--f-section);font-weight:600;color:var(--ink)}',
  '.srow{display:flex;align-items:center;gap:var(--sp-m);min-height:44px;font-size:var(--f-body);color:var(--ink)}',
  '.srow .glyph{width:28px;color:var(--ink-sub)}',
  '.srow i{margin-left:auto;font-style:normal;color:var(--ink-faint);font-size:13px}',
  '.srow+.srow{border-top:var(--stroke-hair) solid var(--hairline)}',
  '.dial{position:relative;display:flex;align-items:center;justify-content:center;margin:0 auto}',
  '.dial svg{position:absolute;inset:0}',
  '.hub{text-align:center;width:52%}',
  '.hub b{display:block;font-family:ui-monospace,Consolas,monospace;font-size:30px;font-weight:500;color:var(--ink)}',
  '.hub em{display:block;font-style:normal;font-size:var(--f-unit);color:var(--ink-faint);letter-spacing:.6px;margin-top:2px}',
  '.hub p{margin:var(--sp-s) 0 0;font-size:var(--f-caption);color:var(--ink-sub)}',
  '.empty{text-align:center;padding:var(--sp-xxl) var(--sp-l)}',
  '.empty .eglyph{display:block;font-size:40px;color:var(--ink-faint);margin-bottom:var(--sp-m)}',
  '.empty b{display:block;font-size:var(--f-body);color:var(--ink);margin-bottom:var(--sp-xs)}',
  '.empty p{margin:0 0 var(--sp-l);font-size:var(--f-caption);color:var(--ink-sub);line-height:1.5}',
  '.gap{height:var(--sp-l)} .gap-s{height:var(--sp-s)} .gap-m{height:var(--sp-m)}',
  '.row{display:flex;gap:var(--sp-m);margin:0 var(--sp-gutter)} .row>*{flex:1}',
  '.banner{display:flex;align-items:center;gap:var(--sp-s);margin:0 var(--sp-gutter);padding:var(--sp-m) var(--sp-l);border-radius:var(--r-control);background:color-mix(in srgb,var(--critical) 10%,transparent);font-size:var(--f-caption);color:var(--critical)}',
  '.note{font-size:var(--f-caption);color:var(--ink-sub);line-height:1.55;padding:0 var(--sp-gutter)}',
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
  '.ladder .step{flex:1;padding:var(--sp-s) var(--sp-m);border-radius:var(--r-control);background:var(--plate-alt);box-shadow:inset 0 0 0 var(--stroke-hair) var(--hairline)}',
  '.ladder .num{display:block;font-family:ui-monospace,Consolas,monospace;font-size:var(--f-unit);color:var(--ink-faint)}',
  '.ladder .lbl{display:block;font-size:var(--f-caption);color:var(--ink-sub);margin-top:2px}',
  '.ladder .step.now{background:color-mix(in srgb,var(--base) 10%,var(--plate));box-shadow:inset 0 0 0 var(--stroke-hair) color-mix(in srgb,var(--base) 40%,transparent)}',
  '.ladder .step.now .num,.ladder .step.now .lbl{color:var(--base)}',
  '.ladder .step.done .num{color:var(--ink-sub)} .ladder .step.done .lbl{color:var(--ink)}',
  '.avatar{width:32px;height:32px;border-radius:50%;background:var(--plate-alt);display:inline-flex;align-items:center;justify-content:center;font-size:var(--f-caption);color:var(--ink-sub)}',
  '.toggle{width:44px;height:26px;border-radius:999px;background:var(--plate-alt);box-shadow:inset 0 0 0 var(--stroke-hair) var(--hairline);position:relative}',
  '.toggle.on{background:var(--base)} .toggle i{position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:50%;background:#fff;transition:none}',
  '.toggle.on i{left:21px}',
].join('\n');

module.exports = { SPACE, RADIUS, HEIGHT, ICON, STROKE, F, DUAL, kebab, rootVars, cssBody };
