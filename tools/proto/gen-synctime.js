'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs.writeFileSync(D+'25-synctime.html', L.page('同步时间', `
  <div class="h1" style="margin-top:8px">同步时间</div>
  <div class="sub">锁钟偏差 · 写入手机时间</div>

  <!-- skewCard：偏差 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">锁钟偏差<span class="ch">${sv('chevron')}</span></div>
    <div style="text-align:center;padding:18px 0 8px">
      <div style="font-size:96px;font-weight:700;letter-spacing:-3px;line-height:1;
        font-variant-numeric:tabular-nums;color:#FFA31A;text-shadow:0 0 44px rgba(255,163,26,.42)">−3<span style="font-size:24px">s</span></div>
      <div style="font-size:13px;color:#8D8D93;margin-top:12px">锁比手机慢 3 秒</div>
    </div>
    <div style="margin-top:10px">
      <div style="display:flex;justify-content:space-between;font-size:11px;color:#6A6A6E;margin-bottom:6px">
        <span>−30s</span><span>0</span><span>+30s</span>
      </div>
      <div style="position:relative;height:6px;border-radius:3px;background:rgba(255,255,255,.08)">
        <div style="position:absolute;left:45%;top:-5px;width:3px;height:16px;
          border-radius:2px;background:#FF9F0A;transform:translateX(-50%)"></div>
      </div>
    </div>
    <div class="footer">偏差为正即锁慢，为负即锁快。超过 ±30 秒建议立即校准。</div>
  </div>

  <!-- clockCard：两个时钟对照 -->
  <div class="card">
    <div class="cardlink">对照<span class="ch">${sv('chevron')}</span></div>
    <div class="duo" style="margin-top:12px;margin-bottom:0">
      <div class="metric-card">
        <div class="mh"><span class="mt">锁内时钟</span><span class="mc">${sv('chevron')}</span></div>
        <div class="ms">读到的</div>
        <div class="mv" style="font-size:21px">06:41:57</div>
      </div>
      <div class="metric-card">
        <div class="mh"><span class="mt">手机时间</span><span class="mc">${sv('chevron')}</span></div>
        <div class="ms">现在</div>
        <div class="mv" style="font-size:21px;color:#30D158">06:42:00</div>
      </div>
    </div>
  </div>

  <!-- actionCard：写入 -->
  <div class="card">
    <div class="cardlink">写入<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:13px;color:#8D8D93;line-height:1.6;margin-top:6px">
      校准会把手机时间写进锁内（cmd 0E）。写入前请确认手机时间准确。
    </div>
    <button class="btn" style="margin-top:14px">将手机时间同步到锁内</button>
    <div class="footer">请将手机靠近门锁。</div>
  </div>
`, 2, {nav:true, back:'03-devices'}));

console.log('✓ 25-synctime 按源码 3 区块重做');
