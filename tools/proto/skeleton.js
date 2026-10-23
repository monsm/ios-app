'use strict';
// tools/proto/skeleton.js —— 标题 → 首卡 间距统一
//
// 历史：旧版在这里插一个 .sp74 占位 div（74px），本意是「状态栏+navbar」的
// 视觉呼吸，但实测参考图 1/2 的标题到首卡只有 24px（图1：标题底 412 → 卡顶 436）。
// 74px 的断层让每页顶部都有一块"空地"，是"不精致"的直接原因之一。
//
// 现在：不注入任何 DOM。间距完全由 .sub + .card 的 CSS margin 控制。
// 这个脚本保留为幂等清理器 —— 移除历史遗留的 .sp74。
const fs = require('fs'), path = require('path');
const D = __dirname;
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));

let cleaned = 0;
for (const p of reg) {
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  const before = s;
  if (s.indexOf('sp74') < 0) continue;
  // 删除所有 sp74 占位
  s = s.replace(/\s*<div class="sp74"><\/div>/g, '');
  if (s !== before) { fs.writeFileSync(fp, s, 'utf8'); cleaned++; }
}
console.log('✓ 清理 sp74：' + cleaned + ' 页');
