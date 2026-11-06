#!/usr/bin/env node
// contrast.js —— 从 DesignLab/tokens.json 现场算 WCAG 对比度。
// 断言的是「文字色 vs 页面底」；叠了半透明之后的真实渲染只能靠真机。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const t = JSON.parse(fs.readFileSync(path.join(ROOT, 'DesignLab', 'tokens.json'), 'utf8'));

function lum(hex) {
  const h = hex.replace('#', '');
  const rgb = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  const f = (c) => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  return 0.2126 * f(rgb[0]) + 0.7152 * f(rgb[1]) + 0.0722 * f(rgb[2]);
}
function ratio(a, b) {
  const la = lum(a), lb = lum(b);
  const hi = Math.max(la, lb), lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const checks = [
  ['ink', 7.0, '正文/标题'],
  ['ink2', 4.5, '次级正文'],
  ['ink3', 4.5, '说明文字'],
  ['brass', 4.5, '强调色文字'],
  ['danger', 4.5, '危险文字'],
  ['ok', 4.5, '成功文字'],
];

let bad = 0;
for (const mode of ['light', 'dark']) {
  const c = t.colors[mode];
  for (const [fg, min, label] of checks) {
    const r = ratio(c[fg], c.canvas);
    const ok = r >= min;
    if (!ok) bad++;
    console.log(`contrast: ${mode.padEnd(5)} ${fg.padEnd(7)} ${r.toFixed(2)}:1  ${ok ? 'OK ' : 'FAIL'} (>= ${min}) ${label}`);
  }
}
if (bad) {
  console.error(`contrast: ${bad} 条不达标`);
  process.exit(1);
}
console.log('contrast: OK — 明暗两套文字色全部达到 WCAG AA');
