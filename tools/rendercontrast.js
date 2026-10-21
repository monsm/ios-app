#!/usr/bin/env node
// tools/rendercontrast.js —— 叠加透明度后的**实际**对比度
//
// 为什么需要它：
//   tools/contrast.js 验的是**令牌对令牌**的静态比值（98 条断言全过）。
//   但界面里大量用 `XPalette.textSub.opacity(0.5)` 这种叠法 ——
//   叠完之后实际对比度会掉得比想象快：
//       textSub           = 6.99 : 1  ✓
//       textSub×0.5       = 2.68 : 1  ✗ 低于信息性图形的 3:1
//       textTertiary×0.55 = 2.37 : 1  ✗
//   而闸门对此**一无所知**。本工具补这一段。
//
// 用法: node tools/rendercontrast.js
'use strict';

const hex = h => [(h >> 16) & 255, (h >> 8) & 255, h & 255];
const lum = ([r, g, b]) => {
  const f = c => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const contrast = (a, b) => {
  const l1 = lum(a), l2 = lum(b);
  const [hi, lo] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (hi + 0.05) / (lo + 0.05);
};
const blend = (fg, bg, a) => fg.map((c, i) => Math.round(c * a + bg[i] * (1 - a)));

// 深色模式令牌（Theme.swift）
const DARK = {
  canvas: hex(0x0A0A0B), surface: hex(0x161618), surfaceAlt: hex(0x1F1F22), surfaceSunken: hex(0x121214),
  text: hex(0xF5F5F7), textSub: hex(0xA0A0AC), textTertiary: hex(0x888892),
  accentText: hex(0xE8A05C), ok: hex(0x3DD68C), warn: hex(0xF5A524), danger: hex(0xFF6B6B),
  hairline: hex(0x323236),
};

const BGS = ['canvas', 'surface', 'surfaceAlt', 'surfaceSunken'];
// 代码里实际出现过的透明度
const OPS = [1, 0.9, 0.85, 0.8, 0.7, 0.6, 0.55, 0.5, 0.4];
const TEXT_TOKENS = ['text', 'textSub', 'textTertiary', 'accentText', 'ok', 'warn', 'danger'];

let fails = 0;
console.log('深色模式 · 合成后的实际对比度（文字需 ≥4.5:1，信息性图形 ≥3:1）');
console.log('');
console.log('前景 × 透明度'.padEnd(24) + BGS.map(b => b.padEnd(14)).join(''));
for (const t of TEXT_TOKENS) {
  for (const a of OPS) {
    if (a < 1 && t === 'text') continue;          // 正文不会降透明度
    let row = (t + (a < 1 ? '×' + a : '')).padEnd(24);
    let worst = 99;
    for (const bg of BGS) {
      const eff = a === 1 ? DARK[t] : blend(DARK[t], DARK[bg], a);
      const c = contrast(eff, DARK[bg]);
      worst = Math.min(worst, c);
      row += (c.toFixed(2) + (c < 3 ? ' ✗' : (c < 4.5 ? ' ⚠' : ''))).padEnd(14);
    }
    if (worst < 4.5) {
      console.log(row);
      if (a >= 0.95) fails++;
    }
  }
}
console.log('');
console.log('✗ = 低于 3:1（连图形都不够）  ⚠ = 低于 4.5:1（正文不够）');
console.log('只列出有问题的组合；全部达标的组合不打印。');
console.log('');
console.log('判读要点：');
console.log('  · 用于**正文/标签**的组合必须 ≥4.5:1 —— 也就是说这些文字**不要叠透明度**');
console.log('  · 用于**信息性图形**（图表柱/状态点）的必须 ≥3:1');
console.log('  · 用于**装饰/网格线**的可以低，但要不低于约 1.4:1 才看得见');
