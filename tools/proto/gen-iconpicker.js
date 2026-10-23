'use strict';
// 70-icon-picker：图 6 的画廊流，用**真实 App 图标 PNG**（§6.4 铁律 I1：禁止渐变冒充图像）
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

const ICONS = [
  ['key','钥匙','Key'],['ring','圆环','Ring'],['shield','盾牌','Shield'],['heart','心形','Heart'],
  ['home','家','Home'],['guard','守护','Guard'],['bell','铃','Bell'],['pin','图钉','Pin'],
];

fs.writeFileSync(D+'70-icon-picker.html', L.page('App 图标', `
  <!-- HERO：图 6 的 New Watch Faces 形态 —— 多个重叠的真实图标 -->
  <div class="gallery-hero" style="background:linear-gradient(180deg,#6B7BE8 0%,#546CE4 28%,#3C489C 62%,#141418 100%);
    display:flex;flex-direction:column;justify-content:space-between;padding:22px 20px 18px">
    <div style="font-size:var(--f-title3);font-weight:700;color:#FFF">New Icons</div>
    <div style="flex:1;display:flex;align-items:center;justify-content:center">
      <div style="display:flex;align-items:center">
        ${[0,1,2,3,4].map((n,i)=>`
          <img src="img/face-${n}.png" alt=""
            style="width:${i===2?112:84}px;height:${i===2?112:84}px;
            border-radius:${i===2?28:21}px;object-fit:cover;
            margin-left:${i>0?-18:0}px;z-index:${i===2?5:Math.abs(2-i)};
            transform:rotate(${(i-2)*7}deg);
            box-shadow:0 12px 30px rgba(0,0,0,.6);position:relative">`).join('')}
      </div>
    </div>
    <div style="font-size:13px;color:rgba(255,255,255,.78);text-align:center">桌面立即更新，随时换回</div>
  </div>

  <div class="h1" style="margin-top:8px">全部图标</div>
  <div class="sub">8 款 · 当前：钥匙</div>

  <!-- 双列图文卡：真实 PNG 居中（图 6 的 Health and Fitness / Photos 卡）-->
  <div class="duo" style="margin-top:18px">
    ${ICONS.map(([n,t,alt],i)=>`
      <div class="duo-card">
        <div class="dt">${t}</div>
        <div class="dm">
          <img src="img/app-${n}.png" alt="${alt}"
            style="width:84px;height:84px;border-radius:21px;object-fit:cover;
            ${i===0?'outline:2px solid rgba(255,255,255,.55);outline-offset:3px;':''}
            box-shadow:0 8px 20px rgba(0,0,0,.45)">
        </div>
        <div class="dd">${i===0?'当前':'轻点切换'}</div>
      </div>`).join('')}
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">桌面预览</div>
    <div style="display:flex;gap:16px;margin-top:14px;align-items:center">
      <img src="img/app-key.png" alt="" style="width:60px;height:60px;border-radius:14px">
      <div><div style="font-size:15px">KF Key</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px">真实图标位图，与桌面一致</div></div>
    </div>
  </div>
`, 4));

console.log('✓ 70-icon-picker 改用真实 PNG');
