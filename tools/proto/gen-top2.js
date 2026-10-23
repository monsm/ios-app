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

  
  <!-- 图 2 的卡解剖：成员分布 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">成员分布<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:2px">
      <div style="flex:1">
        <div class="ctitle">5 位成员</div>
        <div style="margin-top:14px">
          ${M.map(([n,c,k2])=>`<div class="drow"><span class="dot" style="background:${c}"></span>
            <span class="dv">${k2}<span class="du"> 份 · ${n}</span></span></div>`).join('')}
        </div>
      </div>
      ${L.tripleRing(100, .40, 1.0, .40, '5')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">钥匙总数</div><div class="cvalue">15 份</div></div>
      <div><div class="clabel" style="margin-top:0">指纹总数</div><div class="cvalue">6 枚</div></div>
    </div>
    <div class="footer">每位成员可持有多个钥匙。管理员可分配，长辈默认只读。</div>
  </div>

  <!-- 图 6 的横向画廊：成员头像 -->
  <div style="display:flex;gap:12px;overflow-x:auto;scrollbar-width:none;margin-top:12px;padding-bottom:2px">
    ${M.map(([n,c,k2],idx)=>`<a href="32-member-detail.html" style="flex:0 0 auto;width:104px;
      background:linear-gradient(180deg,#202022 0%,#191919 100%);border-radius:20px;
      padding:18px 12px;text-decoration:none;color:inherit;text-align:center;
      box-shadow:inset 0 .5px 0 rgba(255,255,255,.055),inset 0 0 0 .5px rgba(255,255,255,.03)">
      <div style="width:56px;height:56px;border-radius:50%;margin:0 auto;
        background:${c}1F;border:2px solid ${idx===0?c:c+'66'};display:flex;
        align-items:center;justify-content:center;font-size:22px;color:${c};font-weight:600">${n[0]}</div>
      <div style="font-size:14px;font-weight:600;color:#FFF;margin-top:12px">${n}</div>
      <div style="font-size:11px;color:#8A8A90;margin-top:3px">${k2} 份钥匙</div>
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
