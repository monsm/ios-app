'use strict';
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;
fs2.writeFileSync(D+'04-success.html', L.page('已开锁', `
  <!-- 图1 环语言：成功态 = 满环绿色渐变 + 对勾游标 -->
  <div style="position:relative;margin:34px auto 0;width:300px;height:300px">
    <svg width="300" height="300" viewBox="0 0 300 300">
      <defs><linearGradient id="gOk" x1="0" y1="1" x2="1" y2="0">
        <stop offset="0%" stop-color="#2FD65C"/><stop offset="55%" stop-color="#30D158"/><stop offset="100%" stop-color="#7CE89A"/>
      </linearGradient></defs>
      <circle cx="150" cy="150" r="136" fill="none" stroke="rgba(255,255,255,.085)" stroke-width="27" stroke-linecap="round"/>
      <circle cx="150" cy="150" r="136" fill="none" stroke="url(#gOk)" stroke-width="27" stroke-linecap="round"
        stroke-dasharray="740 854.5" transform="rotate(-69 150 150)"/>
      <circle cx="150" cy="150" r="136" fill="none" stroke="transparent" stroke-width="27"/>
    </svg>
    <div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center">
      <div style="width:74px;height:74px;border-radius:50%;background:rgba(47,214,92,.16);
        display:flex;align-items:center;justify-content:center;color:#2FD65C;margin-bottom:16px">${sv('check','34px')}</div>
      <div style="font-size:52px;font-weight:800;color:#2FD65C;letter-spacing:-1.5px;text-shadow:0 0 44px rgba(47,214,92,.4)">已开锁</div>
      <div style="font-size:13px;font-weight:600;color:#6A6A72;margin-top:12px;letter-spacing:4px">手动 · 16:41:07</div>
    </div>
    <span style="position:absolute;left:50%;top:14px;width:12px;height:12px;border-radius:50%;
      background:#2FD65C;stroke:#FFF;box-shadow:0 0 0 3.2px #FFF,0 0 18px rgba(47,214,92,.9);transform:translateX(-50%)"></span>
  </div>

  <!-- 图2 卡解剖：谁把我门开了（事件回执） -->
  <div class="card" style="margin-top:34px">
    <div class="cardlink">开锁回执<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="width:38px;height:38px;border-radius:50%;background:rgba(47,214,92,.14);
        color:#2FD65C;display:inline-flex;align-items:center;justify-content:center;font-weight:700">${sv('person','20px')}</span>
      <div style="flex:1"><div style="font-size:16px;font-weight:600">朕 · 手动</div>
      <div style="font-size:12px;color:#8A8A90;margin-top:2px">04 接近事件 · 一次靠近只开一次</div></div>
      <span style="font-size:12px;color:#30D158;font-weight:600">成功</span>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">命令</div><div class="cvalue">04</div></div>
      <div><div class="clabel" style="margin-top:0">触发</div><div class="cvalue">手动轻点</div></div>
    </div>
    <div class="sep"></div>
    <div class="footer">手动/自动开锁成功都会在这里留一条回执 —— 谁把我门开了，一看便知。</div>
  </div>

  <button class="btn" style="margin-top:20px;background:rgba(255,255,255,.14);color:#FFF;font-weight:700;height:54px;border-radius:999px;font-size:17px">点任意处关闭</button>
`, 0, {nav:false, tabbar:false}));
