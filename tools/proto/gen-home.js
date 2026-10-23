'use strict';
// 01-home —— 标杆页：按图 1 逐项复刻
const L = require('./lib.js');
const M = require('./media.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

const ringIcon = (segs, size) => {
  const s = size || 30, r = s*0.36, w = s*0.15, c = s/2, circ = 2*Math.PI*r;
  let acc = 0;
  return `<svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}">
    <circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="${w}"/>` +
    segs.map(([col,p])=>{
      const d = `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${col}" stroke-width="${w}"
        stroke-linecap="round" stroke-dasharray="${circ*p} ${circ}"
        transform="rotate(${-90+acc*360} ${c} ${c})"/>`;
      acc += p + 0.04; return d; }).join('') + '</svg>';
};

// 图 1 的大环：300pt，轨道几乎不可见，亮色 20%，游标在亮段末端
const heroRing = () => {
  const size = 300, C = 150, R = 120, W = 34;
  const circ = 2*Math.PI*R, sweep = circ*300/360, pct = 0.20, lit = sweep*pct;
  const startDeg = 210, rot = startDeg - 90;
  const endDeg = startDeg + 300*pct;
  const rad = (endDeg-90)*Math.PI/180;
  const px = (C + R*Math.cos(rad)).toFixed(1), py = (C + R*Math.sin(rad)).toFixed(1);
  return `<div style="position:relative;width:${size}px;height:${size}px;margin:0 auto">
  <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
    <defs>
      <linearGradient id="hrg" x1="0" y1="1" x2="1" y2="0">
        <stop offset="0" stop-color="#00C6FF"/><stop offset="1" stop-color="#0090FC"/>
      </linearGradient>
      <linearGradient id="htg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#243050"/><stop offset=".5" stop-color="#182034"/><stop offset="1" stop-color="#10141F"/>
      </linearGradient>
    </defs>
    <circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="url(#htg)" stroke-width="${W}"
      stroke-linecap="round" stroke-dasharray="${sweep.toFixed(1)} ${circ.toFixed(1)}"
      transform="rotate(${rot} ${C} ${C})"/>
    <circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="url(#hrg)" stroke-width="${W}"
      stroke-linecap="round" stroke-dasharray="${lit.toFixed(1)} ${circ.toFixed(1)}"
      transform="rotate(${rot} ${C} ${C})"/>
    <rect x="${C-4}" y="14" width="8" height="21" rx="4" fill="#4A4A7A"/>
    <circle cx="${px}" cy="${py}" r="10" fill="#00C6FF"/>
  </svg>
  <div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center">
    <div style="font-size:56px;font-weight:700;letter-spacing:-1.5px;line-height:1;color:#0090FC;
      font-variant-numeric:tabular-nums">0</div>
    <div style="font-size:11px;color:#8D8D93;letter-spacing:2.6px;margin-top:10px">次 · 今日</div>
  </div>
  <div style="position:absolute;right:6px;top:26px;width:26px;height:26px;border-radius:50%;
    background:rgba(255,255,255,.10);display:flex;align-items:center;justify-content:center;
    color:#8D8D93">${sv('info','13px')}</div>
</div>`;
};

fs.writeFileSync(D+'01-home.html', L.page('门厅', `
  <!-- 胶囊行：图 1 只有 **2 枚并排**（Overview / Health Age）—— 不是 4-5 枚滚动 -->
  <div class="chiprow">
    <a class="chip" href="50-events.html" style="flex:1">
      ${ringIcon([['#F11B51',.28],['#3CDE02',.24],['#0ADBD8',.22],['#5E5CE6',.26]])}
      <div><div class="lbl">Overview</div><div class="val">1 良好</div></div>
    </a>
    <a class="chip" href="52-stats.html" style="flex:1">
      ${ringIcon([['#0090FC',.62]])}
      <div><div class="lbl">今日开门</div><div class="val">0 次</div></div>
    </a>
  </div>

  <div style="margin-top:24px">${heroRing()}</div>

  <!-- 标题块：图 1 是**两行**大标题 + **四行**正文 -->
  <div style="margin-top:24px">
    <div class="h1" style="font-size:30px;line-height:1.18;letter-spacing:-.5px">今天还没有开门<br>靠近门锁就能开</div>
    <div class="sub" style="font-size:16px;line-height:1.42;margin-top:10px;color:#98989E">
      这个家的记录都在这台手机上。靠近门锁，<br>或者在下方按住圆盘，两种方式都能开门。<br>
      每次开门都会留一条记录，谁、什么时候、<br>用什么方式。
    </div>
  </div>

  <!-- 两列读数：图 1 只有**一组**两列（Health Age / Actual Age）-->
  <div class="cols" style="margin-top:20px;padding:0 8px">
    <div><div class="clabel" style="margin-top:0;font-size:12px">今日开门</div>
      <div class="cvalue" style="font-size:19px;font-weight:700;margin-top:6px">0 次</div></div>
    <div><div class="clabel" style="margin-top:0;font-size:12px">最活跃成员</div>
      <div class="cvalue" style="font-size:19px;font-weight:700;margin-top:6px">爱妃</div></div>
  </div>

  <!-- 本周卡：图 2 的卡解剖 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">本周<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:2px">
      <div style="flex:1">
        <div class="ctitle">三环都在线</div>
        <div style="margin-top:14px">
          ${[['#F11B51','开门','12/30'],['#3CDE02','成员','5/5'],['#0ADBD8','电量','47%']].map(([c,n,v])=>
            `<div class="drow"><span class="dot" style="background:${c}"></span>
              <span class="dv">${v}<span class="du"> ${n}</span></span></div>`).join('')}
        </div>
      </div>
      ${M.face(7, 96, ['#F11B51','#3CDE02','#0ADBD8']).replace('<svg ', '<svg style="border-radius:50%" ')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">握手</div>
        <div class="cvalue">1,033 ms</div></div>
      <div><div class="clabel" style="margin-top:0">信号</div>
        <div class="cvalue">−76 dBm</div></div>
    </div>
  </div>

  <!-- 趋势卡：图 1 的 Health Age History -->
  <div class="card">
    <div class="ctitle" style="font-size:18px">今日开门分布</div>
    <div style="position:relative;height:96px;margin-top:14px">
      <div class="dash"><i></i><i></i><i></i><i></i><i></i><i></i></div>
      <svg width="100%" height="96" viewBox="0 0 320 96" preserveAspectRatio="none" style="position:absolute;inset:0">
        <defs><linearGradient id="ar" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#00C6FF" stop-opacity=".42"/>
          <stop offset="1" stop-color="#0090FC" stop-opacity="0"/></linearGradient></defs>
        <path d="M0,90 L40,86 L80,68 L120,32 L160,54 L200,76 L240,84 L280,88 L320,90 L320,96 L0,96 Z" fill="url(#ar)"/>
        <path d="M0,90 L40,86 L80,68 L120,32 L160,54 L200,76 L240,84 L280,88 L320,90"
          fill="none" stroke="#00C6FF" stroke-width="2"/>
        <line x1="0" y1="36" x2="320" y2="36" stroke="rgba(255,255,255,.22)" stroke-width="1" stroke-dasharray="3 4"/>
      </svg>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:11px;color:#6A6A6E;margin-top:10px">
      <span>0</span><span>6</span><span>12</span><span>18</span><span>24</span>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">最早一次</div><div class="cvalue">—</div></div>
      <div><div class="clabel" style="margin-top:0">最后一次</div><div class="cvalue">昨天 21:40</div></div>
    </div>
    <div class="footer">今天 0 次开门，其中 0 位成员参与。柱高是该小时的开门次数。</div>
  </div>
`, 0));

console.log('✓ 01-home 标杆页重做');
