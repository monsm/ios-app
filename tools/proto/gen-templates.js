'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';

// ══ 模板 A · 画廊流（图 1 Face Gallery）→ App 图标选择 ══
const icons = ['🔒','🔐','🛡','🏠','🔑','🚪','⚙','❤️','🔔','📍'];
const galleryHero = `
<div class="gallery-hero">
  <div class="gt">App 图标</div>
  <div class="gm">
    <div style="display:flex;align-items:center;gap:-10px">
      ${icons.slice(0,3).map((e,i)=>`
        <div style="width:${i===1?96:72}px;height:${i===1?96:72}px;border-radius:${i===1?24:18}px;
          background:linear-gradient(135deg,#5E5CE6,#0090FC);
          display:flex;align-items:center;justify-content:center;font-size:${i===1?40:30}px;
          box-shadow:0 8px 24px rgba(0,0,0,.5);transform:rotate(${(i-1)*8}deg);
          margin-left:${i>0?-14:0}px;z-index:${i===1?2:1}">${e}</div>`).join('')}
    </div>
  </div>
  <div class="gd">点任意一款换图标，桌面立即更新</div>
</div>`;

const duos = [
  ['经典','🔒','锁形，最直观','#5E5CE6'],
  ['守护','🛡','盾形，强调安全','#0090FC'],
  ['家','🏠','房子，强调归属','#30D158'],
  ['钥匙','🔑','钥匙，强调凭证','#E8A05C'],
  ['门','🚪','门形，强调出入','#FF694E'],
  ['齿轮','⚙','机械，强调设置','#8D8D93'],
].map(([t,e,d,c])=>`
<div class="duo-card">
  <div class="dt">${t}</div>
  <div class="dm">
    <div style="width:76px;height:76px;border-radius:20px;background:${c}22;
      border:1px solid ${c}44;display:flex;align-items:center;justify-content:center;font-size:34px">${e}</div>
  </div>
  <div class="dd">${d}</div>
</div>`).join('');

// [已移交给 gen-iconpicker.js] fs.writeFileSync(D+'70-icon-picker.html', L.page('App 图标', `
/* ... 省略 ...

  <div class="h1">App 图标</div>
  <div class="sub">10 款可选 · 当前：经典</div>
  ${galleryHero}
  <div class="duo">${duos}</div>
  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">预览</div>
    <div style="display:flex;gap:16px;margin-top:14px;align-items:center">
      <div style="width:60px;height:60px;border-radius:14px;background:linear-gradient(135deg,#5E5CE6,#0090FC);
        display:flex;align-items:center;justify-content:center;font-size:28px">🔒</div>
      <div><div style="font-size:15px">KF Key</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px">预览块底色与生成的图标位图逐字相同</div></div>
    </div>
  </div>
`, 4, {nav:true, back:'4a-me'}));

*/
// ══ 模板 D · 主题化列表（图 5 Sports）→ 事件记录 ══
const evRows = [
  ['07:12','开门 · 密码','朕','手动'],
  ['07:45','开门 · 指纹 10','爱妃','手动'],
  ['08:03','开门 · 自动','朕','自动'],
  ['12:30','开门 · 临时码','—','临时'],
  ['18:22','开门 · 指纹 10','爱妃','手动'],
  ['19:10','⚠ 试错锁定','—','告警'],
  ['21:40','开门 · 密码','朕','手动'],
  ['22:05','上锁','—','自动'],
];
fs.writeFileSync(D+'50-events.html', L.page('事件', `
  <div class="chiprow">
    <div class="chip compact">${L.ring([['#0090FC',.6]])}</div>
    <div class="chip">${L.ring([['#3CDE02',.8]])}<div><div class="lbl">今日</div><div class="val">8 条</div></div></div>
    <div class="chip">${L.ring([['#FF9F0A',.1]])}<div><div class="lbl">告警</div><div class="val">1 条</div></div></div>
    <div class="chip">${L.ring([['#0ADBD8',.3]])}<div><div class="lbl">同步</div><div class="val">06:30</div></div></div>
  </div>

  <div style="margin-top:28px">
    <div class="h1">事件</div>
    <div class="sub">10-23 周四 · 本机保留 20 条</div>
  </div>

  <div class="segctl2" style="margin-top:22px">
    <div class="o on">今日 8</div><div class="o">本周 47</div><div class="o">全部 127</div>
  </div>

  <div class="dpanel" style="margin-top:14px">
    <div class="dhead">10-23 · 今天</div>
    ${evRows.map(([t,n,w,k])=>`
      <a class="drow72" href="13-key-detail.html">
        <div class="dm">${t}</div>
        <div class="dl"><div class="dt">${n}</div>
          <div class="ds">${w}${k?' · '+k:''}</div></div>
        <div style="color:var(--text-tert);font-size:18px">›</div>
      </a>`).join('')}
  </div>

  <div class="dpanel">
    <div class="dhead">10-22 · 昨天</div>
    ${[['07:08','开门 · 密码','朕','手动'],['18:30','开门 · 指纹 10','爱妃','手动'],['21:40','开门 · 密码','朕','手动']].map(([t,n,w,k])=>`
      <a class="drow72" href="13-key-detail.html">
        <div class="dm">${t}</div>
        <div class="dl"><div class="dt">${n}</div><div class="ds">${w} · ${k}</div></div>
        <div style="color:var(--text-tert);font-size:18px">›</div>
      </a>`).join('')}
  </div>
`, 0, {nav:true, back:'01-home', right:'🔍'}));

// ══ 模板 B 补强 · 双列 MetricCard（图 2 Activity Details）→ 统计 ══
const miniBars = (h) => Array.from({length:24},(_,i)=>
  `<i style="height:${Math.max(2,h[i]||2)}px"></i>`).join('');
// [已移交给 gen-stats.js] fs.writeFileSync(D+'52-stats.html', L.page('统计', `
/* ... 省略 ...

  <div class="chiprow">
    <div class="chip compact">${L.ring([['#0090FC',.6]])}</div>
    <div class="chip">${L.ring([['#0ADBD8',.8]])}<div><div class="lbl">总开门</div><div class="val">127 次</div></div></div>
    <div class="chip">${L.ring([['#FF9F0A',.2]])}<div><div class="lbl">告警</div><div class="val">2 条</div></div></div>
  </div>

  <div style="margin-top:28px">
    <div class="h1">统计</div>
    <div class="sub">近 30 天 · 1 把门锁 · 5 位成员</div>
  </div>

  <!-- 图 2 的 Activity Rings 卡：三行数据 + 同心三环 -->
  <div class="card" style="margin-top:26px">
    <div class="ctitle" style="font-size:var(--f-title3)">开门环</div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${L.tripleRing(101, .62, .55, .5)}
      <div style="flex:1">
        ${L.drow('#F11B51','92','/127 次开门')}
        ${L.drow('#3CDE02','41','% 自动')}
        ${L.drow('#0ADBD8','4.2',' 次日均')}
      </div>
    </div>
  </div>

  <!-- 图 2 的双列 MetricCard -->
  <div class="duo" style="margin-top:0">
    <div class="metric-card">
      <div class="mh"><span class="mt">开门次数</span><span class="mc">›</span></div>
      <div class="ms">今日</div>
      <div class="mv">8</div>
      <div class="minibar">${miniBars([2,2,2,2,2,2,14,22,2,2,2,2,2,2,2,2,2,10,16,2,2,2,2,2])}</div>
      <div style="display:flex;justify-content:space-between;font-size:9px;color:var(--text-tert);margin-top:6px">
        <span>0</span><span>6</span><span>12</span><span>18</span><span>24</span>
      </div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">成员</span><span class="mc">›</span></div>
      <div class="ms">今日参与</div>
      <div class="mv">3<small>位</small></div>
      <div class="minibar">${miniBars([2,2,2,2,2,2,8,20,2,2,2,2,2,2,2,2,2,12,18,2,2,2,2,2])}</div>
      <div style="display:flex;justify-content:space-between;font-size:9px;color:var(--text-tert);margin-top:6px">
        <span>0</span><span>6</span><span>12</span><span>18</span><span>24</span>
      </div>
    </div>
  </div>

  <!-- 图 1 的面积趋势 -->
  <div class="card">
    <div class="cardlink">开门趋势<span class="ch">›</span></div>
    <div style="position:relative;height:100px;margin-top:12px">
      <div class="dash"><i></i><i></i><i></i><i></i><i></i><i></i></div>
      <svg width="100%" height="100" viewBox="0 0 320 100" preserveAspectRatio="none" style="position:absolute;inset:0">
        <defs><linearGradient id="st" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#00C6FF" stop-opacity=".42"/>
          <stop offset="1" stop-color="#0090FC" stop-opacity="0"/></linearGradient></defs>
        <path d="M0,72 L36,64 L72,48 L108,58 L144,32 L180,46 L216,38 L252,56 L288,50 L320,62 L320,100 L0,100 Z" fill="url(#st)"/>
        <path d="M0,72 L36,64 L72,48 L108,58 L144,32 L180,46 L216,38 L252,56 L288,50 L320,62"
          fill="none" stroke="#00C6FF" stroke-width="2"/>
      </svg>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:11px;color:var(--text-tert);margin-top:8px">
      <span>9-22</span><span>9-27</span><span>10-2</span><span>10-7</span><span>10-12</span><span>10-21</span>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">日均</div><div class="cvalue">4.2 次</div></div>
      <div><div class="clabel" style="margin-top:0">最忙一天</div><div class="cvalue">9 次</div></div>
    </div>
    <div class="footer">127 次开门里，自动开锁占 41%，手动 52%，临时码 7%。</div>
  </div>

  <!-- 图 3 的 Fitness 卡：三行彩色读数 + 段分布 -->
  <div class="card">
    <div class="cardlink">成员活跃度<span class="ch">›</span></div>
    <div style="display:flex;gap:14px;margin-top:4px">
      <div style="flex:1">
        ${[['#7B7BE8','朕','24 次'],['#E8A05C','爱妃','18 次'],['#30D158','皇子','32 次'],['#FF3B30','父上','9 次'],['#0ADBD8','母上','16 次']].map(([c,n,v])=>
          L.drow(c,n,' · '+v)).join('')}
      </div>
      ${L.donut(96,[['#7B7BE8',.25],['#E8A05C',.18],['#30D158',.33],['#FF3B30',.09],['#0ADBD8',.15]])}
    </div>
    <div class="sep"></div>
    <div class="footer" style="margin-top:0">皇子近 7 天开门约 32 次，工作日 8–9 点最活跃。</div>
  </div>
`, 0, {nav:true, back:'01-home'}));

*/
console.log('✓ 模板 A / D / 双列卡 三页已重做');
