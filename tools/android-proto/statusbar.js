'use strict';
// tools/proto/statusbar.js —— 状态栏（6 张参考图全有，此前全站缺失）
//
// 图 1/2/3/6 实测：
//   高 44pt，时间在左（17 Semibold），右侧三枚图标
//   图标：信号（4 格）/ WiFi / 电池
//   颜色：白（在深色页面上）
const fs = require('fs'), path = require('path');
const D = __dirname;
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));

const SBAR = `<div class="statusbar">
  <span class="sb-time" data-real-time>9:41</span>
  <span class="sb-right">
    <svg width="17" height="11" viewBox="0 0 17 11" fill="#FFF"><rect x="0" y="7.5" width="3" height="3.5" rx="1"/><rect x="4.5" y="5.5" width="3" height="5.5" rx="1"/><rect x="9" y="3" width="3" height="8" rx="1"/><rect x="13.5" y="0" width="3" height="11" rx="1"/></svg>
    <svg width="16" height="11" viewBox="0 0 16 11" fill="none" stroke="#FFF" stroke-width="1.6" stroke-linecap="round"><path d="M1 3.4a10.5 10.5 0 0 1 14 0"/><path d="M3.6 6.2a6.6 6.6 0 0 1 8.8 0"/><path d="M6.2 8.9a2.9 2.9 0 0 1 3.6 0"/><circle cx="8" cy="10.2" r=".7" fill="#FFF" stroke="none"/></svg>
    <svg width="25" height="12" viewBox="0 0 25 12" fill="none"><rect x=".5" y=".5" width="21" height="11" rx="3.2" stroke="#FFF" stroke-opacity=".4"/><rect x="2" y="2" width="15" height="8" rx="2" fill="#FFF"/><path d="M23 4.2v3.6a2 2 0 0 0 0-3.6z" fill="#FFF" fill-opacity=".5"/></svg>
  </span>
</div>`;

let n = 0;
for (const p of reg) {
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  if (s.indexOf('class="statusbar"') >= 0) continue;
  // 模板 D（dsheet/themed）的头部要高一些容纳状态栏
  if (/class="themed"/.test(s)) {
    s = s.replace(/(<div class="themed-head"[^>]*>)/, '$1\n  ' + SBAR);
  } else if (/class="dsheet"/.test(s)) {
    s = s.replace(/(<div class="dtop"[^>]*>)/, '$1\n  ' + SBAR);
  } else {
    // 普通页：插到 .phone 之后
    s = s.replace(/(<div class="phone">)/, '$1\n' + SBAR);
  }
  fs.writeFileSync(fp, s, 'utf8');
  n++;
}
console.log('✓ 补状态栏 ' + n + ' 页');
