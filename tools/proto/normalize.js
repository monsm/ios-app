'use strict';
// tools/proto/normalize.js —— 把控件尺寸收敛到规范值
//
// 为什么需要这一步：生成器里各页随手写了 72/88/92/96/104/120 各种环径，
// 规范 §7.8 只给两个值 —— 小环 84、三环 128。
// 「每个控件都要精准」意味着不能有 8 种环径。
const fs = require('fs');
const path = require('path');
const D = __dirname;

// 环径收敛表：偏离值 → 规范值
const RING = { 72: 84, 88: 84, 92: 84, 96: 84, 100: 84, 104: 84, 112: 84, 120: 128 };

const reg = JSON.parse(fs.readFileSync(path.join(D, 'registry.json'), 'utf8'));
let n = 0;
for (const p of reg) {
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  const before = s;
  for (const [from, to] of Object.entries(RING)) {
    const k = to / Number(from);
    // 只认「首个子元素是灰色轨道圆」的 svg —— 那是环形图
    const re = new RegExp(
      '(<svg width="' + from + '" height="' + from + '" viewBox="0 0 ' + from + ' ' + from + '">)([\\s\\S]*?)(</svg>)', 'g');
    s = s.replace(re, function (m, open, inner, close) {
      if (inner.indexOf('rgba(255,255,255,.10)') < 0) return m;   // 不是环形图，跳过
      const scaled = inner
        .replace(/(cx|cy|r)="([\d.]+)"/g, function (mm, a, v) { return a + '="' + (parseFloat(v) * k).toFixed(2) + '"'; })
        .replace(/stroke-width="([\d.]+)"/g, function (mm, v) { return 'stroke-width="' + (parseFloat(v) * k).toFixed(2) + '"'; })
        .replace(/stroke-dasharray="([\d.]+) ([\d.]+)"/g, function (mm, a, b) {
          return 'stroke-dasharray="' + (parseFloat(a) * k).toFixed(2) + ' ' + (parseFloat(b) * k).toFixed(2) + '"'; })
        .replace(/font-size="([\d.]+)"/g, function (mm, v) { return 'font-size="' + (parseFloat(v) * k).toFixed(2) + '"'; })
        .replace(/rotate\(([-\d.]+) ([\d.]+) ([\d.]+)\)/g, function (mm, deg, rx, ry) {
          return 'rotate(' + deg + ' ' + (parseFloat(rx) * k).toFixed(2) + ' ' + (parseFloat(ry) * k).toFixed(2) + ')';
        });
      return '<svg width="' + to + '" height="' + to + '" viewBox="0 0 ' + to + ' ' + to + '">' + scaled + close;
    });
  }
  if (s !== before) { fs.writeFileSync(fp, s, 'utf8'); n++; }
}
console.log('✓ 环径收敛 ' + n + ' 页（小环 84 / 三环 128）');
