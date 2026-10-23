'use strict';
// 44-audit：图 4 的完整模板 D（两层头部 + 文字分段 + 分组同构行）
// 主题色用审计域的蓝（#0090FC）而非体育绿 —— 结构学图4，色服从本 App 语义
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

const GROUPS = [
  ['10-23 周四', [
    ['06:20','gear','改 · 然然家','管理操作','#FF9F0A'],
    ['06:22','gear','改 · 免密开门','管理操作','#FF9F0A'],
  ]],
  ['10-22 周三', [
    ['09:15','lockOpen','开 · 密码','朕','#0090FC'],
    ['18:30','lockOpen','开 · 指纹 10','爱妃','#0090FC'],
    ['21:40','lockOpen','开 · 自动','朕','#30D158'],
  ]],
  ['10-21 周二', [
    ['07:08','lockOpen','开 · 密码','朕','#0090FC'],
    ['19:22','warn','试错锁定','连续 5 次错误','#FF3B30'],
  ]],
];

const rows = GROUPS.map(([day, list]) => `
  <div class="dpanel">
    <div class="dhead">${day}</div>
    ${list.map(([t,ic,name,who,col])=>`
      <div class="drow72">
        <div class="dm">${t}</div>
        <div class="dl" style="display:flex;align-items:center;gap:10px">
          <span style="color:${col};width:16px;height:16px;display:block">${sv(ic)}</span>
          <div><div class="dt">${name}</div><div class="ds">${who}</div></div>
        </div>
        <div style="color:var(--text-tert);font-size:17px">${sv('chevron')}</div>
      </div>`).join('')}
  </div>`).join('');

// [已移交给 gen-fill-sections.js] fs.writeFileSync(D+'44-audit.html', `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
/* ... 省略 ...

<title>审计流水</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone"><div class="themed">
  <!-- 头部：主题色，比内容板亮约 2×（图 4 的核心结构） -->
  <div class="themed-head" style="background:linear-gradient(180deg,#0A3A6E 0%,#062A52 100%)">
    <div class="th-title">审计流水</div>
    <div class="th-sub">2 条管理操作 · 5 条开门事件</div>
    <a class="th-act" href="48-export.html">${sv('export')}导出</a>
  </div>

  <div class="themed-body" style="background:#0C1826">
    <!-- 文字分段：图4 的 Yesterday/Today/Upcoming，无指示条 -->
    <div class="themed-seg">
      <a class="t on" href="#">管理 2</a>
      <a class="t" href="#">开门 5</a>
      <a class="t" href="#">全部 7</a>
    </div>

    <div style="padding:12px 14px 0">
      <div class="card" style="background:#132436;margin-bottom:12px">
        <div style="display:flex;align-items:center;gap:10px">
          <span style="color:#30D158;width:17px;height:17px;display:block">${sv('shieldCheck')}</span>
          <span style="font-size:14px;color:#30D158;flex:1">校验完整性 · 逐链重算通过</span>
          <span style="font-size:11px;color:#6E9B7C">SHA-256</span>
        </div>
        <div style="font-size:12px;color:#6E9B7C;line-height:1.6;margin-top:10px">
          每条管理日志前附条 SHA-256，逐链重算验证；本地轻量口径，篡改即断链。
        </div>
      </div>

      ${rows}

      <div class="card" style="background:#132436;padding:6px 0">
        <a class="rw" href="05-system.html">
          <div class="ic" style="background:transparent;color:#6E9B7C">${sv('calendar')}</div>
          <div class="tx"><div class="tt">保留期</div><div class="sb">永久保留</div></div>
          <div class="ch">${sv('chevron')}</div></a>
        <div class="sep"></div>
        <a class="rw" href="48-export.html">
          <div class="ic" style="background:transparent;color:#6E9B7C">${sv('export')}</div>
          <div class="tx"><div class="tt">导出审计 JSON</div><div class="sb">脱敏</div></div>
          <div class="ch">${sv('chevron')}</div></a>
      </div>
    </div>
  </div>

  <div class="tabbar">
    <a class="tab" href="01-home.html">${L.ICONS.home}<span>门厅</span></a>
    <a class="tab" href="02-keys.html">${L.ICONS.key}<span>钥匙</span></a>
    <a class="tab" href="03-devices.html">${L.ICONS.device}<span>设备</span></a>
    <a class="tab" href="04-members.html">${L.ICONS.people}<span>成员</span></a>
    <a class="tab on" href="05-system.html">${L.ICONS.gear}<span>系统</span></a>
  </div>
</div></div>
<script src="icons-render.js"></script><script src="interact.js"></script></body></html>`);

*/
console.log('✓ 44-audit 改为图 4 完整两层结构');
