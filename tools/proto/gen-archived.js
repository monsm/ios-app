'use strict';
// 33-archived：归档页完整化（图 2 的卡解剖 + 归档语义）
const L = require('./lib.js');
const V = require('./viz.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs.writeFileSync(D+'33-archived.html', L.page('已归档', `
  <div class="h1" style="margin-top:8px">已归档</div>
  <div class="sub">归档不删数据，名下钥匙转成「未分配」</div>

  <div class="duo" style="margin-top:24px">
    <div class="metric-card">
      <div class="mh"><span class="mt">已归档</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">成员</div>
      <div class="mv">1<small>位</small></div>
      <div style="font-size:11px;color:#8D8D93;margin-top:10px">2026-08-01 归档</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">待认领</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">钥匙</div>
      <div class="mv" style="color:#FF9F0A">0<small>份</small></div>
      <div style="font-size:11px;color:#8D8D93;margin-top:10px">无人认领</div>
    </div>
  </div>

  <div class="card" style="margin-top:4px;padding:6px 0">
    <div class="cardlink">归档记录<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="32-member-detail.html" style="margin-top:2px">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('person')}</div>
      <div class="tx"><div class="tt">伯伯</div><div class="sb">2026-08-01 归档 · 名下 0 份钥匙</div></div>
      <span class="badge" style="background:rgba(141,141,147,.16);color:#8D8D93">已归档</span>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="footer">归档的成员不占名额，可以随时恢复。恢复后钥匙仍是「未分配」，需要重新指定。</div>
  </div>

  <div class="card">
    <div class="cardlink">归档规则<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:12px">
      ${[['钥匙不删','转成「未分配」，可再认领','#FF9F0A'],
         ['记录保留','开门记录与审计都不变','#30D158'],
         ['不占名额','家庭成员上限只算活跃成员','#0090FC']].map(([t,d,c])=>
        `<div style="display:flex;gap:12px">
          <span style="width:7px;height:7px;border-radius:50%;background:${c};margin-top:7px;flex:0 0 auto"></span>
          <div style="flex:1"><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:3px;line-height:1.5">${d}</div></div>
        </div>`).join('')}
    </div>
  </div>

  <button class="btn sec" style="margin-top:4px">恢复选中成员</button>
  <div style="text-align:center;font-size:12px;color:#6A6A6E;margin-top:12px">恢复后可重新分配钥匙</div>
`, 3, {nav:true, back:'30-members-list'}));

console.log('✓ 33-archived 完整化');
