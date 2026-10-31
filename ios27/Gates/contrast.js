#!/usr/bin/env node
// contrast.js —— 对比度闸门。
//
// 判什么：
//   ① 旧令牌 App/Design/Tokens.swift 的 Color.dual(light:dark:) 全部色对，按 WCAG 2.1 逐条核算。
//   ② V7 令牌 App/Design/V7/V7Tokens.swift 的 rgb(r,g,b) 色板真实取值，按同一口径逐条核算。
//   ③ 低对比黑名单：#48525B / #6D6D6D / #5D5D62 / #4E4E50 这类"参考图实测但不可交付"的颜色
//      一旦出现在 V7 色板里即判失败，并给出达标替代（见 BANNED_V7）。
//
// 判据（WCAG 2.1）：
//   · 正文（≤17pt）≥ 4.5:1
//   · 大字号（≥18pt 或 ≥14pt 粗体）≥ 3:1
//   · 非文本（描边/分割线/状态点）≥ 3:1（装饰性分割线 ≥ 1.25:1）
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TOKENS = path.join(ROOT, 'App', 'Design', 'Tokens.swift');
const V7_TOKENS = path.join(ROOT, 'App', 'Design', 'V7', 'V7Tokens.swift');
const src = fs.readFileSync(TOKENS, 'utf8');
const v7src = fs.readFileSync(V7_TOKENS, 'utf8');

// 解析 Color.dual(light: 0xXXXXXX, dark: 0xXXXXXX)
const DUAL = {};
for (const m of src.matchAll(/static let (\w+)\s*=\s*Color\.dual\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})\)/g)) {
  DUAL[m[1]] = { light: m[2].toUpperCase(), dark: m[3].toUpperCase() };
}

// 解析 V7 色板：static let token = rgb(r, g, b[, a])
const V7 = {};
for (const m of v7src.matchAll(/static let (\w+)\s*=\s*rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+)\s*)?\)/g)) {
  const hex = [m[2], m[3], m[4]].map((v) => parseInt(v, 10).toString(16).padStart(2, '0')).join('').toUpperCase();
  V7[m[1]] = { hex, a: m[5] === undefined ? 1 : parseFloat(m[5]) };
}

// V7 低对比黑名单：参考图里的视觉值，但 < 4.5:1（11pt 文本）或 < 3:1（非文本）。
// 命中即失败，必须提供达标替代（已落地：text4=#9A9A9F / text5=#8E98A3 / infoGlyph=#8E8E93 / axisLabel=#8E8E93）。
const BANNED_V7 = {
  '48525B': { was: 'V.C.text5 原值', ratio: '2.63:1 on #000', fix: 'V.C.text5 = #8E98A3（7.17:1）' },
  '6D6D6D': { was: 'V.C.text4 原值', ratio: '2.92:1 on #262626', fix: 'V.C.text4 = #9A9A9F（5.40:1）' },
  '5D5D62': { was: 'V.C.infoGlyph 原值', ratio: '2.57:1 on #1D1D21', fix: 'V.C.infoGlyph = #8E8E93（5.15:1）' },
  '4E4E50': { was: '图表轴标旧值', ratio: '2.53:1 on #000', fix: 'V.C.axisLabel = #8E8E93（6.44:1）' },
};

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

// —— 旧令牌正文（4.5:1）
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
check('onSignal / signal', 'on', 'base', 4.5);

// —— 旧令牌非文本 UI（3:1）
check('描边 hairline / plate（UI 边界）', 'hairline', 'plate', 1.25);
check('描边 hairline / paper（UI 边界）', 'hairline', 'paper', 1.25);
check('状态点 attention / plate', 'attention', 'plate', 3);
check('状态点 critical / plate', 'critical', 'plate', 3);
check('状态点 signal / plate', 'base', 'plate', 3);
check('读数 ink / plate（大字号）', 'ink', 'plate', 3);
check('读数 attention / plate（大字号）', 'attention', 'plate', 3);
check('单位小字 inkFaint / plate', 'inkFaint', 'plate', 4.5);
check('单位小字 inkFaint / paper', 'inkFaint', 'paper', 4.5);
check('单位小字 inkFaint / plateAlt', 'inkFaint', 'plateAlt', 4.5);
check('次文本 inkSub / plateAlt', 'inkSub', 'plateAlt', 4.5);

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

// —— 旧令牌层级差
check('层级 ink / inkSub 至少 1.3:1', 'ink', 'inkSub', 1.3);
check('层级 inkSub / inkFaint 至少 1.4:1', 'inkSub', 'inkFaint', 1.4);

// —— V7 色板（真实 rgb 值，不再让 V7 逃逸）
function checkV7(name, fg, bg, min) {
  const f = V7[fg]?.hex;
  const b = V7[bg]?.hex;
  if (!f || !b) { fails.push(`V7 ${name}: 令牌缺失 ${!f ? fg : bg}`); return; }
  const r = ratio(f, b);
  if (r >= min) pass++;
  else fails.push(`V7 ${name} ${fg}#${f} on ${bg}#${b} = ${r.toFixed(2)}:1 < ${min}:1`);
}

checkV7('正文 text2 / bg', 'text2', 'bg', 4.5);
checkV7('正文 text2 / card', 'text2', 'card', 4.5);
checkV7('次文本 text3 / card', 'text3', 'card', 4.5);
checkV7('芯片标签 text4 / chipTop', 'text4', 'chipTop', 4.5);
checkV7('主环标签 text5 / bg', 'text5', 'bg', 4.5);
checkV7('卡头 text8 / card', 'text8', 'card', 4.5);
checkV7('卡标题 text6 / card', 'text6', 'card', 3);
checkV7('焦点 text7 / card', 'text7', 'card', 4.5);
checkV7('正文 text9 / card', 'text9', 'card', 4.5);
checkV7('i 字形 infoGlyph / infoBG（非文本）', 'infoGlyph', 'infoBG', 3);
checkV7('图表轴标 axisLabel / bg', 'axisLabel', 'bg', 4.5);
checkV7('警告 warning / bg（非文本）', 'warning', 'bg', 3);
checkV7('危险 critical / bg（非文本）', 'critical', 'bg', 3);
checkV7('正常 rewardGreen / bg（非文本）', 'rewardGreen', 'bg', 3);
checkV7('按钮白字 text1 / blue（17pt 粗体按大字号 3:1）', 'text1', 'blue', 3);
checkV7('按钮白字 text1 / red（17pt 粗体按大字号 3:1）', 'text1', 'red', 3);

// —— 黑名单：V7 色板里出现旧的低对比值 → 必须换达标替代
for (const [hex, info] of Object.entries(BANNED_V7)) {
  const hit = Object.entries(V7).find(([, v]) => v.hex === hex);
  if (hit) {
    fails.push(`V7 低对比色 #${hex} 仍作为 V.C.${hit[0]} 存在（原 ${info.was}，${info.ratio}）→ 必须换成 ${info.fix}`);
  } else {
    pass++;
  }
}

// 输出
console.log(`contrast: 解析到 ${Object.keys(DUAL).length} 个旧色令牌 × 2 模式 + ${Object.keys(V7).length} 个 V7 色令牌`);
if (fails.length === 0) {
  console.log(`contrast: OK — ${pass} 条断言全部达标（含 V7 色板与低对比黑名单）`);
  process.exit(0);
}
console.log(`contrast: FAIL — ${fails.length} 条不达标（${pass} 条通过）\n`);
for (const f of fails) console.log('  ' + f);
process.exit(1);
