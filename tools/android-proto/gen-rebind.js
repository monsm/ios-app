'use strict';
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;
fs2.writeFileSync(D+'05-rebind.html', L.page('换绑确认', `
  <div class="h1" style="margin-top:8px">更新这把锁的凭证?</div>
  <div class="sub">本机已绑定「然然家」</div>

  <!-- 图2 卡解剖：新旧锁对照（主/副双卡语言，参考 iOS 34-merge） -->
  <div class="duo" style="margin-top:24px">
    <div class="duo-card" style="background:linear-gradient(180deg,#202020,#191919)">
      <div class="dt">本机当前</div>
      <div style="display:flex;align-items:center;gap:10px;margin-top:12px">
        <span style="width:40px;height:40px;border-radius:50%;background:rgba(10,132,255,.16);color:#4FC3FF;display:inline-flex;align-items:center;justify-content:center">${sv('lock','19px')}</span>
        <div><div style="font-size:15px;font-weight:600">然然家</div><div style="font-size:11px;color:#8A8A90">有效钥匙</div></div>
      </div>
    </div>
    <div class="duo-card" style="background:linear-gradient(180deg,#202020,#191919)">
      <div class="dt">扫到的锁</div>
      <div style="display:flex;align-items:center;gap:10px;margin-top:12px">
        <span style="width:40px;height:40px;border-radius:50%;background:rgba(255,159,10,.16);color:#FFA31A;display:inline-flex;align-items:center;justify-content:center">${sv('key','19px')}</span>
        <div><div style="font-size:15px;font-weight:600">婆婆家 · 入户门</div><div style="font-size:11px;color:#8A8A90">新凭证</div></div>
      </div>
    </div>
  </div>

  <!-- 图2 红色警告卡（源码解绑全文） -->
  <div class="card" style="margin-top:22px;border-radius:16px;
    background:linear-gradient(180deg,#2A1517,#1F1012);box-shadow:inset 0 0 0 .5px rgba(255,69,58,.24)">
    <div class="cardlink" style="color:#FF453A">换绑后果<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:14px;line-height:1.65;color:#E8B0AE;margin-top:10px">
      换成「婆婆家 · 入户门」之后，原来那把锁要从这台手机重新扫码才能再用。</div>
    <div class="sep" style="background:rgba(255,69,58,.18)"></div>
    <div style="font-size:14px;line-height:1.65;color:#E8B0AE">
      解绑则删除「然然家」的钥匙与全部本机设置，删掉之后无法从本机找回 —— 要再用这把锁，得先在门锁键盘上重置、再重新扫码配对。门锁里的密码和指纹不受影响。</div>
  </div>

  <div style="display:flex;gap:12px;margin-top:22px">
    <button class="btn" style="flex:1;background:rgba(255,255,255,.10);color:#FFF;height:52px;border-radius:999px;font-size:16px">取消</button>
    <button class="btn" style="flex:1;background:#FFF;color:#0A0A0C;font-weight:700;height:52px;border-radius:999px;font-size:16px">换绑</button>
  </div>
  <button class="btn" style="margin-top:12px;background:rgba(255,69,58,.14);color:#FF453A;font-weight:600;height:52px;border-radius:999px;font-size:16px">只解绑，不换</button>
`, 0, {nav:true, back:'03-settings', tabbar:false}));
