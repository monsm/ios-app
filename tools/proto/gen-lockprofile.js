'use strict';
// 21-lock-profile：HERO 用**真实锁渲染图**（LockHero PNG），§6.4 I2
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

const SYMS = [["lock-hero","经典"],["app-key","钥匙"],["app-home","家"],["app-shield","守护"],["app-ring","圆环"],["app-heart","心形"],["app-bell","铃"],["app-pin","图钉"]];

// [已移交给 gen-lockprofile2.js] fs.writeFileSync(D+'21-lock-profile.html', L.page('锁档案', `
/* ... 省略 ...

  <!-- HERO：真实锁渲染图（PNG 带 alpha），不是 CSS 画的圆 -->
  <div class="gallery-hero" style="background:linear-gradient(180deg,#6B7BE8 0%,#546CE4 30%,#2A2F45 68%,#1C1C1E 100%);
    display:flex;flex-direction:column;justify-content:space-between;padding:22px 20px 18px">
    <div style="font-size:var(--f-title3);font-weight:700;color:#FFF">然然家</div>
    <div style="flex:1;display:flex;align-items:center;justify-content:center">
      <img src="img/lock-45.png" alt=""
        style="width:150px;height:auto;filter:drop-shadow(0 16px 30px rgba(0,0,0,.65))">
    </div>
    <div style="font-size:13px;color:rgba(255,255,255,.8);text-align:center">JZ · 固件 1.0.2 · 已连接</div>
  </div>

  <div class="h1" style="margin-top:8px">符号</div>
  <div class="sub">选一个能一眼认出的样子</div>

  <!-- 双列图文卡：真实 App 图标 PNG -->
  <div class="duo" style="margin-top:18px">
    ${SYMS.map(([n,t],i)=>`
      <div class="duo-card">
        <div class="dm">
          <img src="img/${n}.png" alt=""
            style="width:76px;height:76px;border-radius:19px;object-fit:cover;
            ${i===0?'outline:2px solid rgba(255,255,255,.55);outline-offset:3px;':''}
            box-shadow:0 8px 18px rgba(0,0,0,.4)">
        </div>
        <div class="dt" style="text-align:center;font-size:15px">${t}</div>
      </div>`).join('')}
  </div>

  <div class="card" style="padding:6px 0">
    <a class="rw" href="32-member-detail.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('people')}</div>
      <div class="tx"><div class="tt">成员与钥匙</div><div class="sb">5 位成员 · 13 项钥匙</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="22-firmware.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('arrowDown')}</div>
      <div class="tx"><div class="tt">固件</div><div class="sb">1.0.2 · 已是最新</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="25-synctime.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('clock')}</div>
      <div class="tx"><div class="tt">锁内时钟</div><div class="sb">偏差 −3 秒</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <button class="btn dgr" style="margin-top:12px">解绑这把锁</button>
`, 2, {nav:true, back:'20-locks', right:'保存'}));

*/
console.log('✓ 21-lock-profile 用真实锁渲染图');
