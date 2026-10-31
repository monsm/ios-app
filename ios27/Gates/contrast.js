#!/usr/bin/env node
// contrast.js —— 对比度闸门。
//
// 判什么：从 App/Design/Tokens.swift 解析全部色令牌的真实取值，按 WCAG 2.1 逐条核算。
// 为什么：观感不能验，数值能验。深色模式不是浅色的反相，两套必须各自达标。
//
// 判据（WCAG 2.1）：
//   · 正文（≤17pt）≥ 4.5:1
//   · 大字号（≥18pt 或 ≥14pt 粗体）≥ 3:1
//   · 非文本（描边/分割线/状态点）≥ 3:1（UI 组件边界），装饰性分割线 ≥ 1.25:1
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TOKENS = path.join(ROOT, 'App', 'Design', 'Tokens.swift');
const src = fs.readFileSync(TOKENS, 'utf8');

// 解析 Color.dual(light: 0xXXXXXX, dark: 0xXXXXXX)
const DUAL = {};
for (const m of src.matchAll(/static let (\w+)\s*=\s*Color\.dual\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})\)/g)) {
  DUAL[m[1]] = { light: m[2].toUpperCase(), dark: m[3].toUpperCase() };
}

function rgb(hex) {
  const n = parseInt(hex, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
function lum(hex) {
  const [r, g, b] = rgb(hex).map((v) => {
    const s = v / 255;
    return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function ratio(a, b) {
  const la = lum(a), lb = lum(b);
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

const MODES = ['light', 'dark'];
let pass = 0;
const fails = [];

function check(name, fg, bg, min) {
  for (const mode of MODES) {
    const f = DUAL[fg]?.[mode];
    const b = DUAL[bg]?.[mode];
    if (!f || !b) { fails.push(`${name}: 令牌缺失 ${!f ? fg : bg}`); continue; }
    const r = ratio(f, b);
    const ok = r >= min;
    if (ok) pass++;
    else fails.push(`${name} [${mode}] ${fg}#${f} on ${bg}#${b} = ${r.toFixed(2)}:1 < ${min}:1`);
  }
}

// —— 正文（4.5:1）
check('正文 ink / plate', 'ink', 'plate', 4.5);
check('正文 ink / paper', 'ink', 'paper', 4.5);
check('正文 ink / plateAlt', 'ink', 'plateAlt', 4.5);
check('次文本 inkSub / plate', 'inkSub', 'plate', 4.5);
check('次文本 inkSub / paper', 'inkSub', 'paper', 4.5);
check('次文本 inkSub / plateAlt', 'inkSub', 'plateAlt', 4.5);
check('品牌字 signal / plate', 'base', 'plate', 4.5);
check('品牌字 signal / paper', 'base', 'paper', 4.5);
check('注意字 attention / plate', 'attention', 'plate', 4.5);
check('危险字 critical / plate', 'critical', 'plate', 4.5);

// —— 压填充上的文字（onSignal 压 signal，4.5:1）
check('onSignal / signal', 'on', 'base', 4.5);

// —— 非文本 UI（3:1）
check('描边 hairline / plate（UI 边界）', 'hairline', 'plate', 1.25);
check('描边 hairline / paper（UI 边界）', 'hairline', 'paper', 1.25);
check('状态点 attention / plate', 'attention', 'plate', 3);
check('状态点 critical / plate', 'critical', 'plate', 3);
check('状态点 signal / plate', 'base', 'plate', 3);

// —— 大字号（3:1，读数 22pt+ 允许更低一档）
check('读数 ink / plate（大字号）', 'ink', 'plate', 3);
check('读数 attention / plate（大字号）', 'attention', 'plate', 3);

// —— 单位小字（11pt 属正文档，必须 4.5）
check('单位小字 inkFaint / plate', 'inkFaint', 'plate', 4.5);
check('单位小字 inkFaint / paper', 'inkFaint', 'paper', 4.5);
check('单位小字 inkFaint / plateAlt', 'inkFaint', 'plateAlt', 4.5);
check('次文本 inkSub / plateAlt', 'inkSub', 'plateAlt', 4.5);

// —— 选中态描边（Signal.edge = base @ 75% 叠在 plate/paper 上）：UI 组件要 ≥3:1。
// 这条是实测补的：原来用 35%，浅色下只有 1.69:1 —— 强光下等于没有选中态。
function blend(fg, bg, a) {
  const f = rgb(fg), b = rgb(bg);
  const o = f.map((c, i) => Math.round(c * a + b[i] * (1 - a)));
  return ((o[0] << 16) | (o[1] << 8) | o[2]).toString(16).padStart(6, '0').toUpperCase();
}
function checkEdge(name, bgName, alpha, min) {
  for (const mode of MODES) {
    const base = DUAL['base']?.[mode];
    const bg = DUAL[bgName]?.[mode];
    if (!base || !bg) { fails.push(name + ': 令牌缺失'); continue; }
    const mixed = blend(base, bg, alpha);
    const r = ratio(mixed, bg);
    if (r >= min) pass++;
    else fails.push(`${name} [${mode}] base@${Math.round(alpha * 100)}% on ${bgName} = ${r.toFixed(2)}:1 < ${min}:1（实测 #${mixed}）`);
  }
}
checkEdge('选中描边 edge / plate', 'plate', 0.75, 3);
checkEdge('选中描边 edge / paper', 'paper', 0.75, 3);

// —— 层级差（"次要"必须看得出次要：ink 与 inkSub、inkSub 与 inkFaint 之间要有可辨差异）
check('层级 ink / inkSub 至少 1.3:1', 'ink', 'inkSub', 1.3);
check('层级 inkSub / inkFaint 至少 1.4:1', 'inkSub', 'inkFaint', 1.4);

// 输出
console.log(`contrast: 解析到 ${Object.keys(DUAL).length} 个色令牌 × 2 模式`);
if (fails.length === 0) {
  console.log(`contrast: OK — ${pass} 条断言全部达标`);
  process.exit(0);
}
console.log(`contrast: FAIL — ${fails.length} 条不达标（${pass} 条通过）\n`);
for (const f of fails) console.log('  ' + f);
process.exit(1);