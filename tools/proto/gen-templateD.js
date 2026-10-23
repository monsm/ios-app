'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';

// ══ 44 安全审计 —— 图 5 的完整形态（两层头部 + 文字分段 + 分组同构行）══
const auditGroups = [
  ['10-23 周四', [
    ['06:20','⚙','改 · 然然家','管理','#FF9F0A'],
    ['06:22','⚙','改 · 免密开门','管理','#FF9F0A'],
  ]],
  ['10-22 周三', [
    ['09:15','🔓','开 · 密码','朕','#0090FC'],
    ['18:30','🔓','开 · 指纹 10','爱妃','#0090FC'],
    ['21:40','🔓','开 · 自动','朕','#3CDE02'],
  ]],
  ['10-21 周二', [
    ['07:08','🔓','开 · 密码','朕','#0090FC'],
    ['19:22','⚠','试错锁定','—','#FF3B30'],
  ]],
];
const auditBody = auditGroups.map(([day, rows]) => `
  <div class="dpanel">
    <div class="dhead">${day}</div>
    ${(rows).map(([t,ic,n,w,c])=>`
      <div class="drow72">
        <div class="dm">${t}</div>
        <div class="dl" style="display:flex;align-items:center;gap:10px">
          <span style="color:${c};font-size:15px">${ic}</span>
          <div><div class="dt">${n}</div><div class="ds">${w}</div></div>
        </div>
        <div style="color:var(--text-tert);font-size:18px">›</div>
      </div>`).join('')}
  </div>`).join('');

// [已移交给 gen-fill-sections.js] fs.writeFileSync(D+'44-audit.html', `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
/* ... 省略 ...

<title>审计流水</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone"><div class="dsheet">
  <div class="dtop">
    <div class="dtitle">审计流水</div>
    <a class="dact" href="05-system.html">导出</a>
  </div>
  <div class="dbody">
    <div class="dtabs">
      <div class="t on">管理操作 2</div><div class="t">开门事件 5</div><div class="t">全部 7</div>
    </div>
    <div style="padding:14px 14px 0">
      <div class="card" style="margin-bottom:12px">
        <div style="display:flex;align-items:center;gap:10px">
          <span style="color:#0090FC;font-size:16px">✓</span>
          <span style="font-size:15px;color:#0090FC;flex:1">校验完整性 · 逐链重算通过</span>
          <span style="font-size:12px;color:var(--text-tert)">SHA-256</span>
        </div>
        <div class="footer" style="margin-top:10px">每条管理日志前附条 SHA-256，逐链重算验证；本地轻量口径，篡改即断链。</div>
      </div>
    </div>
    <div style="padding:0 14px">
      ${auditBody}
    </div>
    <div style="padding:0 14px">
      <div class="card rowlist" style="padding:6px 0">
        ${L.row('05-system','📅','rgba(255,255,255,.08)','#8D8D93','保留期','永久保留','<span style="font-size:14px;color:#E8A05C">永久 ›</span>')}
        <div class="sep"></div>
        ${L.row('48-export','⬆','rgba(0,144,252,.16)','#0090FC','导出审计 JSON','脱敏')}
        <div class="sep"></div>
        ${L.row('48-export','👁','rgba(232,160,92,.18)','#E8A05C','导出含明文','需确认')}
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
</div></div><script src="interact.js"></script></body></html>`);

*/
// ══ 51 动态 —— 图 5 的形态用在时间线 ══
const feedGroups = [
  ['今天', [
    ['07:12','lockOpen','开门 · 密码','朕 · 手动','#4FC3FF'],
    ['07:45','fingerprint','开门 · 指纹 10','爱妃 · 手动','#2FD65C'],
    ['08:03','bolt','开门 · 自动','朕 · 靠近自动开','#2FD65C'],
  ]],
  ['昨天', [
    ['18:22','fingerprint','开门 · 指纹 10','爱妃 · 手动','#2FD65C'],
    ['19:10','warn','试错锁定','连续 5 次密码错误','#FF453A'],
    ['21:40','lockOpen','开门 · 密码','朕 · 手动','#4FC3FF'],
  ]],
  ['10-21 周二', [
    ['07:08','lockOpen','开门 · 密码','朕 · 手动','#4FC3FF'],
    ['12:30','timer','开门 · 临时码','访客 · 一次性','#FFA31A'],
  ]],
];
const feedBody = feedGroups.map(([day, rows]) => `
  <div style="text-align:center;font-size:11px;font-weight:600;letter-spacing:1.4px;
    color:#5A5A62;padding:22px 0 8px;text-transform:uppercase">${day}</div>
  <div class="card" style="padding:2px 0;margin-bottom:14px">
    ${rows.map(([t,ic,n,w,c],i)=>`
      <div class="rw" style="min-height:62px">
        <div style="width:38px;font-size:12px;color:#7A7A82;font-variant-numeric:tabular-nums;flex:0 0 auto">${t}</div>
        <div class="ic" style="background:${c}1F;color:${c}"><span class="svgi" data-i="${ic}" data-sz="17px"></span></div>
        <div class="tx"><div class="tt">${n}</div><div class="sb">${w}</div></div>
        <span style="font-size:11px;font-weight:600;color:${c};background:${c}1F;
          padding:3px 8px;border-radius:999px;flex:0 0 auto">${c==='#FF453A'?'告警':'成功'}</span>
      </div>${i < rows.length-1 ? '<div class="sep"></div>' : ''}
    `).join('')}
  </div>
`).join('');

fs.writeFileSync(D+'51-feed.html', `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>动态</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone"><div class="dsheet">
  <div class="dtop">
    <div class="dtitle">动态</div>
    <a class="dact" href="50-events.html">同步</a>
  </div>
  <div class="dbody">
    <div class="dtabs">
      <div class="t on">全部</div><div class="t">开门 7</div><div class="t">告警 1</div>
    </div>

    <!-- 图5 MetricCard：今日时段（44px 大数字 + 环 + 24h 柱图 + 轴标）-->
    <div class="card" style="margin:14px 0">
      <div class="cardlink">今日时段<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
      <div style="display:flex;align-items:flex-start;gap:16px;margin-top:2px">
        <div style="flex:1;min-width:0">
          <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
            font-variant-numeric:tabular-nums;color:#4FC3FF">3<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:4px">次开门</span></div>
          <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">2 位成员参与 · 无告警</div>
        </div>
        <svg width="76" height="76" viewBox="0 0 76 76" style="flex:0 0 auto">
          <circle cx="38" cy="38" r="31" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="6"/>
          <circle cx="38" cy="38" r="31" fill="none" stroke="#4FC3FF" stroke-width="6"
            stroke-linecap="round" stroke-dasharray="48.7 194.8" transform="rotate(-90 38 38)"/>
        </svg>
      </div>
      <div style="display:flex;align-items:flex-end;gap:3px;height:48px;margin-top:16px">
        ${[1,0,0,0,0,2,14,6,4,2,3,1,0,1,2,0,0,1,3,5,2,1,0,0].map(h=>
          `<div style="flex:1;height:${Math.max(2,h/14*48).toFixed(0)}px;border-radius:2px;
            background:${h>=10?'#4FC3FF':'rgba(79,195,255,.32)'}"></div>`).join('')}
      </div>
      <div style="display:flex;justify-content:space-between;font-size:10px;color:#6A6A72;margin-top:8px">
        <span>0</span><span>6AM</span><span>12PM</span><span>6PM</span><span>24</span>
      </div>
    </div>

    <div style="padding:0 14px">${feedBody}</div>
  </div>
  <div class="tabbar">
    <a class="tab on" href="01-home.html">${L.ICONS.home}<span>门厅</span></a>
    <a class="tab" href="02-keys.html">${L.ICONS.key}<span>钥匙</span></a>
    <a class="tab" href="03-devices.html">${L.ICONS.device}<span>设备</span></a>
    <a class="tab" href="04-members.html">${L.ICONS.people}<span>成员</span></a>
    <a class="tab" href="05-system.html">${L.ICONS.gear}<span>系统</span></a>
  </div>
</div></div><script src="icons-render.js"></script><script src="interact.js"></script></body></html>`);
