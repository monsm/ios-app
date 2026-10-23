'use strict';
// tools/proto/inject-rings.js —— 52-stats 活动环（图 5 核心组件），幂等
const fs = require('fs'), path = require('path');
const fp = path.join(__dirname, '52-stats.html');
if (!fs.existsSync(fp)) { console.log('52-stats 不存在'); process.exit(0); }
let s = fs.readFileSync(fp, 'utf8').replace(/\r\n/g, '\n');
if (s.indexOf('活动环') >= 0) { console.log('✓ 已有活动环'); process.exit(0); }
const sv = (n) => '<span class="svgi" data-i="' + n + '"></span>';
const block = [
  '<!-- 图 5 Activity Rings -->',
  '<div class="card">',
  '  <div class="cardlink">活动环<span class="ch">' + sv('chevron') + '</span></div>',
  '  <div style="display:flex;align-items:center;gap:20px;margin-top:6px">',
  '    <svg width="120" height="120" viewBox="0 0 120 120" style="flex:0 0 auto">' + "<circle cx=\"60\" cy=\"60\" r=\"44\" fill=\"none\" stroke=\"rgba(255,255,255,.07)\" stroke-width=\"13\"/><circle cx=\"60\" cy=\"60\" r=\"44\" fill=\"none\" stroke=\"#FF2D6F\" stroke-width=\"13\" stroke-linecap=\"round\" stroke-dasharray=\"246.0 276.5\" transform=\"rotate(-90 60 60)\"/><circle cx=\"60\" cy=\"60\" r=\"31\" fill=\"none\" stroke=\"rgba(255,255,255,.07)\" stroke-width=\"13\"/><circle cx=\"60\" cy=\"60\" r=\"31\" fill=\"none\" stroke=\"#A8F02C\" stroke-width=\"13\" stroke-linecap=\"round\" stroke-dasharray=\"140.2 194.8\" transform=\"rotate(-90 60 60)\"/><circle cx=\"60\" cy=\"60\" r=\"18\" fill=\"none\" stroke=\"rgba(255,255,255,.07)\" stroke-width=\"13\"/><circle cx=\"60\" cy=\"60\" r=\"18\" fill=\"none\" stroke=\"#00C8D8\" stroke-width=\"13\" stroke-linecap=\"round\" stroke-dasharray=\"37.3 113.1\" transform=\"rotate(-90 60 60)\"/>" + '</svg>',
  '    <div style="flex:1">',
  '      <div style="margin-bottom:14px"><div style="font-size:12px;color:#8A8A90">开门</div><div style="font-size:17px;font-weight:700;color:#FF2D6F;margin-top:2px">127<span style="font-size:12px;font-weight:500;color:#8A8A90">/150 次</span></div></div>',
  '      <div style="margin-bottom:14px"><div style="font-size:12px;color:#8A8A90">指纹</div><div style="font-size:17px;font-weight:700;color:#A8F02C;margin-top:2px">52<span style="font-size:12px;font-weight:500;color:#8A8A90">/72 次</span></div></div>',
  '      <div><div style="font-size:12px;color:#8A8A90">成员活跃</div><div style="font-size:17px;font-weight:700;color:#00C8D8;margin-top:2px">5<span style="font-size:12px;font-weight:500;color:#8A8A90">/5 位</span></div></div>',
  '    </div>',
  '  </div>',
  '  <div class="sep"></div>',
  '  <div class="cols">',
  '    <div><div class="clabel" style="margin-top:0">日均开门</div><div class="cvalue">4.2 次</div></div>',
  '    <div><div class="clabel" style="margin-top:0">最忙一天</div><div class="cvalue">12 次</div></div>',
  '  </div>',
  '  <div class="footer">三环都在正常范围，本周用量平稳。</div>',
  '</div>',
  ''
].join('\n');
const anchor = s.indexOf('怎么开的门');
const cardStart = s.lastIndexOf('<div class="card"', anchor);
s = s.slice(0, cardStart) + block + s.slice(cardStart);
fs.writeFileSync(fp, s, 'utf8');
console.log('✓ 52-stats 注入活动环');
