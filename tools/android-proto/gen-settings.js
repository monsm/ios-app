'use strict';
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs2.writeFileSync(D+'03-settings.html', L.page('门锁设置', `
  <div class="h1" style="margin-top:8px">门锁设置</div>
  <div class="sub">然然家 · 已武装 · 信号 −42 dBm</div>

  <!-- 图2 卡解剖：开关组 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">自动开锁<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="color:#30D158;width:22px;height:22px">${sv('lockOpen')}</span>
      <div style="flex:1"><div style="font-size:16px;font-weight:600">靠近自动开锁</div>
      <div style="font-size:12px;color:#8A8A90;margin-top:2px">RSSI ≥ −38 dBm 且距上次 &gt; 8 秒</div></div>
      <span class="sw on"></span>
    </div>
    <div class="sep"></div>
    <div style="display:flex;align-items:center;gap:12px">
      <span style="color:#4FC3FF;width:22px;height:22px">${sv('bell')}</span>
      <div style="flex:1"><div style="font-size:16px;font-weight:600">提示音</div>
      <div style="font-size:12px;color:#8A8A90;margin-top:2px">开锁时「滴滴滴」</div></div>
      <span class="sw on"></span>
    </div>
    <div class="sep"></div>
    <div class="footer">一次靠近只开一次：要走开让信号掉到 −55 dBm 以下，隔 6 秒后再靠近才会再开。手机要解锁、App 在前台。</div>
  </div>

  <!-- 图2 卡解剖：凭证与绑定 -->
  <div class="card">
    <div class="cardlink">凭证与绑定<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="02-scan.html" style="min-height:60px">
      <div class="ic" style="background:rgba(10,132,255,.14);color:#4FC3FF">${sv('qrcode')}</div>
      <div class="tx"><div class="tt">重新扫码绑定</div><div class="sb">换一把锁或更新凭证</div></div>
      <div class="ch">${sv('chevron')}</div>
    </a>
    <div class="sep"></div>
    <a class="rw" href="03-settings.html" style="min-height:60px">
      <div class="ic" style="background:rgba(255,69,58,.14);color:#FF453A">${sv('trash')}</div>
      <div class="tx"><div class="tt" style="color:#FF453A">解绑这把锁</div><div class="sb">删除本机钥匙与全部设置</div></div>
      <div class="ch">${sv('chevron')}</div>
    </a>
    <div class="sep"></div>
    <div class="footer">本机会删除「然然家」的钥匙与全部本机设置，删掉之后无法从本机找回。门锁里的密码和指纹不受影响。</div>
  </div>

  <!-- 图2 数据行：当前绑定信息 -->
  <div class="card">
    <div class="cardlink">当前绑定<span class="ch">${sv('chevron')}</span></div>
    <div class="cols" style="margin-top:8px">
      <div><div class="clabel">门锁</div><div class="cvalue">然然家</div></div>
      <div><div class="clabel">绑定方式</div><div class="cvalue">扫码</div></div>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel">凭证类型</div><div class="cvalue">离线锁钥匙</div></div>
      <div><div class="clabel">协议</div><div class="cvalue">04 接近事件</div></div>
    </div>
    <div class="sep"></div>
    <div class="footer">每个接近事件只发一次 04 命令 —— 秒开在 RSSI ≥ −38 dBm 时触发。</div>
  </div>
`, 0, {nav:true, back:'01-home', tabbar:false}));
