'use strict';
// 42-peek —— 严格按 SecurityCenterView.swift 的真实结构重做
// 源码结构：
//   ① 剪贴板自动清除（Picker: 关闭/30秒/60秒/5分钟）+ 说明
//   ② 遮蔽样式（Picker: 圆点打码/星号打码/保留末4位）
//   ③ 隐私总览 → 隐私仪表盘（导航）
//   ④ 后台即糊 / 限时可见 / 水印 / 访客通道（MePage 里的真实开关）
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs.writeFileSync(D+'42-peek.html', L.page('防窥与遮蔽', `
  <div class="h1" style="margin-top:8px">防窥与遮蔽</div>
  <div class="sub">口令与码值在本机怎么藏</div>

  <!-- ① 剪贴板自动清除（源码：SecRow + Picker，当前 60 秒）-->
  <div class="card" style="margin-top:24px">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="flex:1">
        <div class="tt" style="font-size:16px">剪贴板自动清除</div>
        <div class="sb" style="margin-top:4px">复制口令后 60 秒清除；只对口令与 OTP 生效</div>
      </div>
      <span style="font-size:15px;color:#E8A05C;font-weight:500">60 秒 ›</span>
    </div>
    <div class="sep"></div>
    <div style="font-size:12px;color:#8D8D93;line-height:1.6">
      加密钥匙包与交接包不走这条：那是密文，且你要粘进聊天工具，定时清掉只会打断交接。
    </div>
  </div>

  <!-- ② 遮蔽样式 -->
  <div class="card">
    <div class="cardlink">遮蔽样式<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:2px">
      <div style="flex:1">
        <div class="tt" style="font-size:16px">码值遮蔽样式</div>
        <div class="sb" style="margin-top:4px">圆点打码（••••）— 默认</div>
      </div>
      <span style="font-size:15px;color:#E8A05C;font-weight:500">圆点打码 ›</span>
    </div>
    <div class="sep"></div>
    <div style="display:flex;gap:16px;align-items:center">
      <div style="flex:1"><div class="clabel" style="margin-top:0">圆点</div>
        <div class="cvalue" style="font-size:19px;letter-spacing:3px">••••••</div></div>
      <div style="flex:1"><div class="clabel" style="margin-top:0">星号</div>
        <div class="cvalue" style="font-size:19px;letter-spacing:3px">******</div></div>
      <div style="flex:1"><div class="clabel" style="margin-top:0">末4位</div>
        <div class="cvalue" style="font-size:19px;letter-spacing:2px">••3456</div></div>
    </div>
    <div class="footer">遮蔽只影响显示。复制出来的仍是明文，所以剪贴板清除要配合用。</div>
  </div>

  <!-- ③ 隐私总览 → 隐私仪表盘 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">隐私总览<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="43-privacy-dash.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('shieldCheck')}</div>
      <div class="tx"><div class="tt">隐私仪表盘</div><div class="sb">2 项防窥已启用</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <!-- ④ 真实开关（MePage 里的四项）-->
  <div class="card">
    <div class="cardlink">遮蔽与通道<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:18px;margin-top:12px">
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">后台即糊</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:3px">切到后台时整屏糊掉，多任务里看不到内容</div></div>
        <span class="sw"></span>
      </div>
      <div class="sep" style="margin:0"></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">限时可见</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:3px">码值显示 30 秒后自动遮回去</div></div>
        <span class="sw"></span>
      </div>
      <div class="sep" style="margin:0"></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">水印</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:3px">整屏浮一层淡字标，截图会带上</div></div>
        <span class="sw"></span>
      </div>
      <div class="sep" style="margin:0"></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">访客通道</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:3px">递给别人时只开四页，本次会话内不再复核</div></div>
        <span class="sw"></span>
      </div>
    </div>
    <div class="footer">这四项都在「本机设置 → 隐私与伪装」里，改这里等于改那里。</div>
  </div>
`, 4, {nav:true, back:'05-system'}));

console.log('✓ 42-peek 按源码真实结构重做');
