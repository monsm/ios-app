'use strict';
// 30-members-list —— 成员列表：参考图 2 的卡解剖 + 本业务的成员数据
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 成员数据（来自源码语义：朕/爱妃/皇子/父上/母上）
const M = [
  { n:'朕',   c:'#7B7BE8', keys:4, fp:1, tmp:0, last:'今天 07:12', role:'管理员' },
  { n:'爱妃', c:'#E8A05C', keys:2, fp:1, tmp:0, last:'昨天 21:40', role:'成员' },
  { n:'皇子', c:'#30D158', keys:5, fp:2, tmp:1, last:'今天 08:03', role:'成员' },
  { n:'父上', c:'#FF3B30', keys:2, fp:0, tmp:0, last:'10-19 07:45', role:'长辈' },
  { n:'母上', c:'#0ADBD8', keys:2, fp:2, tmp:0, last:'10-21 18:22', role:'长辈' },
];

// 成员标识：色环 + 姓名首字（源码里 emoji 代号是"纯文字头像"）
const avatar = (m, size) => `<div style="width:${size}px;height:${size}px;border-radius:50%;
  background:${m.c}22;border:2px solid ${m.c};display:flex;align-items:center;
  justify-content:center;font-size:${Math.round(size*0.40)}px;font-weight:600;
  color:${m.c};flex:0 0 auto">${m.n}</div>`;

fs.writeFileSync(D+'30-members-list.html', L.page('成员', `
  <div class="h1" style="margin-top:8px">成员</div>
  <div class="sub">5 位 · 共 15 份钥匙 · 6 枚指纹</div>

  <!-- 卡 1：参考图 2 的完整解剖 —— 成员分布 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">成员分布<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:2px">
      <div style="flex:1">
        <div class="ctitle">5 位成员</div>
        <div style="margin-top:14px">
          ${M.map(m => `<div class="drow"><span class="dot" style="background:${m.c}"></span>
            <span class="dv">${m.keys}<span class="du"> 份 · ${m.n}</span></span></div>`).join('')}
        </div>
      </div>
      <div style="flex:0 0 auto;margin-right:-4px">
        <svg width="128" height="128" viewBox="0 0 101 101">
          <circle cx="50.5" cy="50.5" r="43.5" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="11"/>
          <circle cx="50.5" cy="50.5" r="43.5" fill="none" stroke="#7B7BE8" stroke-width="11"
            stroke-linecap="round" stroke-dasharray="76.6 273.3" transform="rotate(-90 50.5 50.5)"/>
          <circle cx="50.5" cy="50.5" r="30" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="10"/>
          <circle cx="50.5" cy="50.5" r="30" fill="none" stroke="#E8A05C" stroke-width="10"
            stroke-linecap="round" stroke-dasharray="37.7 188.5" transform="rotate(-90 50.5 50.5)"/>
          <circle cx="50.5" cy="50.5" r="16" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="9"/>
          <circle cx="50.5" cy="50.5" r="16" fill="none" stroke="#30D158" stroke-width="9"
            stroke-linecap="round" stroke-dasharray="50.3 100.5" transform="rotate(-90 50.5 50.5)"/>
          <circle cx="50.5" cy="50.5" r="8" fill="#0A0A0C"/>
        </svg>
      </div>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">钥匙总数</div><div class="cvalue">15 份</div></div>
      <div><div class="clabel" style="margin-top:0">指纹总数</div><div class="cvalue">6 枚</div></div>
    </div>
    <div class="footer">每位成员可持有多个钥匙。管理员可分配，长辈默认只读。</div>
  </div>

  <!-- 卡 2：成员明细列表 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 10px">全部成员<span class="ch">${sv('chevron')}</span></div>
    ${M.map((m, i) => `
      ${i>0 ? '<div class="sep"></div>' : ''}
      <a class="rw" href="32-member-detail.html" style="min-height:68px">
        ${avatar(m, 40)}
        <div class="tx">
          <div style="display:flex;align-items:center;gap:8px">
            <span class="tt">${m.n}</span>
            <span style="font-size:11px;color:${m.c};background:${m.c}1A;padding:1px 6px;border-radius:999px">${m.role}</span>
          </div>
          <div class="sb">${m.keys} 份钥匙 · ${m.fp} 枚指纹 · ${m.last}</div>
        </div>
        <div class="ch">${sv('chevron')}</div>
      </a>`).join('')}
  </div>

  <!-- 卡 3：管理入口 -->
  <div class="card" style="padding:6px 0">
    <a class="rw" href="31-member-wizard.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('personPlus')}</div>
      <div class="tx"><div class="tt">添加成员</div><div class="sb">三步向导 · 称呼 / 密钥 / 角色</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="34-merge.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('refresh')}</div>
      <div class="tx"><div class="tt">重复合并</div><div class="sb">同一人的两条记录</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="33-archived.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('archive')}</div>
      <div class="tx"><div class="tt">已归档</div><div class="sb">1 位待恢复</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>
`, 3));

console.log('✓ 30-members-list 重做：卡解剖 + 成员明细');
