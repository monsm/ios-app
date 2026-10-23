'use strict';
// 24-dongles + 23-gateway —— 严格按源码
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 24 蓝牙钥匙串（DonglesPage：hero + 无锁横幅 + 空态/列表）══
fs.writeFileSync(D+'24-dongles.html', L.page('蓝牙钥匙串', `
  <div class="h1" style="margin-top:8px">蓝牙钥匙串</div>

  <!-- headerCard：hero 渐变 + 图标 + 标题（源码 XPanel(kind: .hero)）-->
  <div class="card" style="margin-top:24px;background:linear-gradient(160deg,#5E5CE6,#3C489C);padding:20px">
    <div style="display:flex;align-items:center;gap:14px">
      <span style="color:#FFF;width:28px;height:28px;display:block;flex:0 0 auto">${sv('key')}</span>
      <div>
        <div style="font-size:16px;font-weight:600;color:#FFF">随身开门</div>
        <div style="font-size:12px;color:rgba(255,255,255,.75);margin-top:3px">
          钥匙串靠近门锁即可开门，不用掏手机</div>
      </div>
    </div>
    <div style="height:1px;background:rgba(255,255,255,.18);margin:16px 0"></div>
    <button class="btn" style="background:rgba(255,255,255,.16);color:#FFF">
      搜索中… / 搜索钥匙串
    </button>
  </div>

  <!-- emptyState：源码 XEmptyState -->
  <div class="card">
    <div class="empty-state">
      <div class="es-icon">${sv('key','28px')}</div>
      <div class="es-title">还没有配对的钥匙串</div>
      <div class="es-desc">上电后点上方「搜索钥匙串」<br>搜索到之后可以给门锁写入钥匙</div>
    </div>
  </div>

  <!-- 源码 dongleCard 的操作区（有钥匙串时才有）-->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">操作<span class="ch">${sv('chevron')}</span></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('search')}</div>
      <div class="tx"><div class="tt">读取状态</div><div class="sb">查电量与固件版本</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('key')}</div>
      <div class="tx"><div class="tt">给当前门锁写入钥匙</div><div class="sb">写入后钥匙串可开门</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('list')}</div>
      <div class="tx"><div class="tt">查询全部钥匙</div><div class="sb">列出钥匙串里存的所有凭证</div></div>
    </div>
    <div class="footer">尚未配对门锁 — 写入钥匙前需先配对门锁。</div>
  </div>
`, 2, {nav:true, back:'03-devices'}));

// ══ 23 智能网关（GatewayPage：重置 → WiFi → 配网进度）══
fs.writeFileSync(D+'23-gateway.html', L.page('智能网关', `
  <div class="h1" style="margin-top:8px">智能网关</div>
  <div class="sub">仅支持 2.4GHz 网络</div>

  <!-- 步骤 1：先把网关重置（源码原文）-->
  <div class="card" style="margin-top:24px;background:linear-gradient(160deg,#5E5CE6,#3C489C);padding:20px">
    <div style="text-align:center;padding:4px 0 8px">
      <div style="color:#FFF;width:34px;height:34px;margin:0 auto">${sv('wifi','34px')}</div>
      <div style="font-size:18px;font-weight:700;color:#FFF;margin-top:12px">先把网关重置</div>
      <div style="font-size:13px;color:rgba(255,255,255,.78);margin-top:10px;line-height:1.6">
        接通电源 → 长捅重置孔约 5 秒<br>→ 等待指示灯变成橙色</div>
    </div>
    <div style="height:1px;background:rgba(255,255,255,.18);margin:14px 0"></div>
    <div style="display:flex;align-items:center;gap:12px">
      <span style="font-size:15px;color:#FFF;flex:1">指示灯已变成橙色</span>
      <span class="sw on"></span>
    </div>
    <div style="text-align:center;font-size:12px;color:rgba(255,255,255,.6);margin-top:10px">
      勾选后进入下一步</div>
  </div>

  <!-- 步骤 2：配置 WiFi（源码原文）-->
  <div class="card">
    <div class="cardlink">配置 WiFi<span class="ch">${sv('chevron')}</span></div>
    <input class="inp" style="margin-top:12px" placeholder="WiFi 名称">
    <input class="inp" style="margin-top:10px" placeholder="输入密码" type="password">
    <div style="font-size:12px;color:#FF9F0A;margin-top:10px">仅支持 2.4GHz —— 5GHz 连不上</div>
    <div style="display:flex;gap:10px;margin-top:14px">
      <button class="btn sec" style="flex:1">上一步</button>
      <button class="btn" style="flex:1">开始配网</button>
    </div>
  </div>

  <!-- 步骤 3：配网进度 -->
  <div class="card">
    <div class="cardlink">配网进度<span class="ch">${sv('chevron')}</span></div>
    <div class="sep" style="margin-top:12px"></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:12px">
      ${[['1','重置网关','指示灯变橙','ok'],
         ['2','配置 WiFi','仅 2.4GHz',''],
         ['3','添加完成','给网关起个名字','']].map(([n,t,s2,c])=>
        `<div style="display:flex;gap:12px;align-items:center">
          <div style="width:24px;height:24px;border-radius:50%;flex:0 0 auto;
            background:${c?'rgba(48,209,88,.16)':'rgba(255,255,255,.06)'};
            color:${c?'#30D158':'#6A6A6E'};display:flex;align-items:center;
            justify-content:center;font-size:12px;font-weight:600">${c?'✓':n}</div>
          <div style="flex:1"><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:2px">${s2}</div></div>
        </div>`).join('')}
    </div>
    <div class="sep"></div>
    <div style="display:flex;justify-content:space-between;font-size:14px">
      <span style="color:#8D8D93">状态</span><span style="color:#FF9F0A">未联网</span>
    </div>
    <div class="footer">重新配网会清除网关里已保存的 WiFi 信息。</div>
  </div>
`, 2, {nav:true, back:'03-devices'}));

console.log('✓ 24-dongles / 23-gateway 按源码重做');
