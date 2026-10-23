'use strict';
// ══ 44 审计流水 ══ 参考图4 Sports 完整两层结构
// 图4 特征：① 顶部深色品牌头（比内容板亮约 2×）+ 圆角胶囊按钮
//          ② 内容板顶部圆角 17 上叠 22px 压住头部
//          ③ 分段标签无下划线指示条，选中仅亮白
//          ④ 分组头居中、小字、灰色
//          ⑤ 行内大数字 + 彩色状态点 + 右侧 chevron
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 图4 的行：左时间 → 图标 → 标题/副标 → 右状态
const row4 = (time, icon, color, title, sub, tag) => `
  <div style="display:flex;align-items:center;gap:12px;padding:13px 0;border-bottom:.5px solid rgba(255,255,255,.07)">
    <span style="width:42px;font-size:12px;color:#7A93AC;font-variant-numeric:tabular-nums;flex:0 0 auto">${time}</span>
    <span style="width:26px;height:26px;border-radius:8px;background:${color}1F;color:${color};
      display:inline-flex;align-items:center;justify-content:center;flex:0 0 auto">${sv(icon,'15px')}</span>
    <div style="flex:1;min-width:0">
      <div style="font-size:15px;font-weight:600;color:#FFF">${title}</div>
      <div style="font-size:11px;color:#7A93AC;margin-top:2px">${sub}</div>
    </div>
    ${tag ? `<span style="font-size:11px;font-weight:600;color:${tag.c};background:${tag.c}1F;
      padding:3px 8px;border-radius:999px">${tag.t}</span>` : ''}
    <span style="color:#4A6480;font-size:15px;flex:0 0 auto">${sv('chevron','14px')}</span>
  </div>`;

// 图4 分组头（居中、小字）
const groupHead = (t) => `<div style="text-align:center;font-size:11px;font-weight:600;letter-spacing:1.4px;
  color:#5E7A96;padding:20px 0 10px;text-transform:uppercase">${t}</div>`;

fs2.writeFileSync(D+'44-audit.html', `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>审计流水</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone"><div class="dsheet">
  <!-- ① 图4 品牌头：深蓝渐变 + 大标题 + 圆角胶囊按钮 -->
  <div class="dtop">
    <div class="dtitle">审计流水</div>
    <a class="dact" href="48-export.html">导出</a>
  </div>

  <!-- ② 内容板：顶部圆角 + 上叠 -->
  <div class="dbody">
    <!-- ③ 图4 分段：无指示条 -->
    <div class="dtabs">
      <div class="t on">管理操作 2</div><div class="t">开门事件 5</div><div class="t">全部 7</div>
    </div>

    <!-- 图5 大数字主角：校验横幅（绿=通过） -->
    <div style="display:flex;align-items:center;gap:12px;padding:14px 16px;border-radius:14px;
      background:linear-gradient(180deg,rgba(47,214,92,.14),rgba(47,214,92,.07));
      box-shadow:inset 0 0 0 .5px rgba(47,214,92,.24);margin:6px 0 4px">
      <span style="color:#2FD65C;width:22px;height:22px;flex:0 0 auto">${sv('shieldCheck')}</span>
      <div style="flex:1;min-width:0">
        <div style="font-size:14px;font-weight:600;color:#2FD65C">校验完整性 · 逐链重算通过</div>
        <div style="font-size:11px;color:#6E9B7C;margin-top:3px;line-height:1.5">每条管理日志前附条 SHA-256，篡改即断链</div>
      </div>
      <span style="font-size:11px;color:#6E9B7C;flex:0 0 auto">SHA-256</span>
    </div>

    ${groupHead('10-23 周四')}
    ${row4('06:20','gear','#4FC3FF','改 · 然然家','管理 · 归属与授权')}
    ${row4('06:22','gear','#4FC3FF','改 · 免密开门','管理 · 策略调整')}

    ${groupHead('10-22 周三')}
    ${row4('09:15','lockOpen','#30D158','开 · 密码','朕 · 手动',{c:'#30D158',t:'成功'})}
    ${row4('18:30','lockOpen','#30D158','开 · 指纹 10','爱妃 · 手动',{c:'#30D158',t:'成功'})}
    ${row4('21:40','lockOpen','#30D158','开 · 自动','朕 · 接近自动开',{c:'#30D158',t:'成功'})}

    ${groupHead('10-21 周二')}
    ${row4('07:08','lockOpen','#30D158','开 · 密码','朕 · 手动',{c:'#30D158',t:'成功'})}
    ${row4('19:22','warn','#FF453A','试错锁定','连续 5 次密码错误',{c:'#FF453A',t:'告警'})}

    <!-- 图2 卡解剖：底部操作 -->
    <div class="dpanel" style="margin-top:22px">
      <a class="rw" href="05-system.html">
        <div class="ic" style="background:transparent;color:#7A93AC">${sv('calendar')}</div>
        <div class="tx"><div class="tt">保留期</div><div class="sb">永久保留</div></div>
        <div class="ch">${sv('chevron')}</div></a>
      <div class="sep"></div>
      <a class="rw" href="48-export.html">
        <div class="ic" style="background:transparent;color:#7A93AC">${sv('export')}</div>
        <div class="tx"><div class="tt">导出审计 JSON</div><div class="sb">脱敏</div></div>
        <div class="ch">${sv('chevron')}</div></a>
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
