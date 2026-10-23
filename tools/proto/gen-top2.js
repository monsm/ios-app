'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;
const M = [['朕','#7B7BE8','4'],['爱妃','#E8A05C','2'],['皇子','#30D158','5'],['父上','#FF3B30','2'],['母上','#0ADBD8','2']];

fs.writeFileSync(D+'04-members.html', L.page('成员', `
  <div class="chiprow">
    <div class="chip compact">${L.ring([['#5E5CE6',.6]])}</div>
    <div class="chip">${L.ring([['#0090FC',.8]])}<div><div class="lbl">成员</div><div class="val">5 位</div></div></div>
    <div class="chip">${L.ring([['#3CDE02',1.0]])}<div><div class="lbl">有钥匙</div><div class="val">5 位</div></div></div>
  </div>

  <div style="margin-top:28px">
    <div class="h1">成员</div>
    <div class="sub">5 位成员 · 各自的钥匙与授权来源</div>
  </div>

  <div style="height:calc(var(--title-to-card) - 34px)"></div>

  <div class="duo">
    ${M.map(([n,c,k],i)=>`
      <a class="duo-card" href="32-member-detail.html">
        <div class="dm">
          <div style="width:68px;height:68px;border-radius:50%;background:${c}22;
            border:2px solid ${i===0?c:'transparent'};display:flex;align-items:center;
            justify-content:center;font-size:26px;color:${c};font-weight:600">${n[0]}</div>
        </div>
        <div class="dt" style="text-align:center">${n}</div>
        <div class="dd" style="text-align:center">${k} 份钥匙</div>
      </a>`).join('')}
  </div>

  <div class="card" style="padding:6px 0">
    <a class="rw" href="30-members-list.html">
      <div class="ic" style="background:rgba(0,144,252,.16);color:#0090FC">${sv('people')}</div>
      <div class="tx"><div class="tt">成员列表</div><div class="sb">合并 · 排序 · 归档</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="31-member-wizard.html">
      <div class="ic" style="background:rgba(232,160,92,.18);color:#E8A05C">${sv('personPlus')}</div>
      <div class="tx"><div class="tt">添加成员</div><div class="sb">三步向导</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="34-merge.html">
      <div class="ic" style="background:rgba(255,159,10,.16);color:#FF9F0A">${sv('refresh')}</div>
      <div class="tx"><div class="tt">合并重复</div><div class="sb">同一人的两条记录</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="33-archived.html">
      <div class="ic" style="background:rgba(141,141,147,.16);color:#8D8D93">${sv('archive')}</div>
      <div class="tx"><div class="tt">已归档</div><div class="sb">1 位待恢复</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <div class="card">
    <div style="display:flex;align-items:center;gap:12px">
      <div class="ic" style="background:rgba(255,255,255,.06);color:#8D8D93;width:34px;height:34px;
        border-radius:10px;display:flex;align-items:center;justify-content:center">${sv('info')}</div>
      <div style="flex:1;font-size:12px;color:var(--text-sub);line-height:1.5">
        点一位成员可看名下钥匙、授权来源与最近活动</div>
    </div>
  </div>
`, 3));

console.log('✓ 04-members 已重写为生成器');
