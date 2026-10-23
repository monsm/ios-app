'use strict';
// 02-keys —— 图 2 的完整形态（胶囊三段环 + 三色数据行 + 101 三环 + 卡解剖）
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 小分段环（图 2 胶囊内，三段独立起点 + 缺口）
const chipRing = (segs) => {
  const r=9, w=4, c=13, circ=2*Math.PI*r, GAP=0.06;
  let acc = 0;
  const arcs = segs.map(([col,p]) => {
    const rot = -90 + acc*360;
    const d = `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${Math.max(1,circ*p-2).toFixed(2)} ${circ.toFixed(2)}" transform="rotate(${rot.toFixed(1)} ${c} ${c})"/>`;
    acc += p + GAP;
    return d;
  }).join('');
  return `<svg class="ringico" viewBox="0 0 26 26"><circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="${w}"/>${arcs}</svg>`;
};

// 同心三环（图 2 的 Fitness 卡，101pt，中心空洞，12点缺口）
const triple = (size) => {
  const C = size/2;
  const R1 = C*0.86, R2 = C*0.60, R3 = C*0.34;
  const W1 = size*0.115, W2 = size*0.105, W3 = size*0.095;
  const g = (R, w, col, p) => {
    const circ = 2*Math.PI*R;
    return `<circle cx="${C}" cy="${C}" r="${R.toFixed(2)}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="${w.toFixed(2)}"/>` +
           `<circle cx="${C}" cy="${C}" r="${R.toFixed(2)}" fill="none" stroke="${col}" stroke-width="${w.toFixed(2)}" stroke-linecap="round" stroke-dasharray="${(circ*p).toFixed(2)} ${circ.toFixed(2)}" transform="rotate(-84 ${C} ${C})"/>`;
  };
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    g(R1,W1,'#F11B51',0.67) + g(R2,W2,'#3CDE02',0.48) + g(R3,W3,'#0ADBD8',0.33) +
    `<circle cx="${C}" cy="${C}" r="${(C*0.20).toFixed(1)}" fill="#0A0A0C"/>` +
    `<circle cx="${C}" cy="${(C-R1).toFixed(1)}" r="${(size*0.045).toFixed(1)}" fill="#000"/></svg>`;
};

fs.writeFileSync(D+'02-keys.html', L.page('钥匙', `
  <!-- 胶囊行：图 2 形态 —— 第一枚 56×56 纯图标方块，其余三段环 -->
  <div class="chiprow">
    <div class="chip compact">${sv('heart','24px')}</div>
    <a class="chip" href="50-events.html">
      ${chipRing([['#0ADBD8',.42],['#FF694E',.28],['#5E5CE6',.24]])}
      <div><div class="lbl">密码</div><div class="val">11 条</div></div>
    </a>
    <a class="chip" href="11-fingerprint.html">
      ${chipRing([['#3CDE02',.40],['#0ADBD8',.32],['#0090FC',.22]])}
      <div><div class="lbl">指纹</div><div class="val">2 枚</div></div>
    </a>
    <a class="chip" href="12-tempcode.html">
      ${chipRing([['#FF9F0A',.55],['#FF694E',.24],['#5E5CE6',.16]])}
      <div><div class="lbl">临时码</div><div class="val">0 个</div></div>
    </a>
  </div>

  <div style="margin-top:30px">
    <div class="h1">钥匙</div>
    <div class="sub">13 项钥匙 · 2 类凭证 · 本周 2 项到期</div>
  </div>

  <div style="height:24px"></div>

  <div style="display:flex"><div class="segctl" style="flex:1">
    <div class="o on">全部</div><div class="o">密码</div><div class="o">指纹</div><div class="o">临时码</div>
  </div></div>

  <!-- 卡 1：图 2 的完整解剖（卡头→标题→label→value→分隔线→第二组→页脚）-->
  <div class="card" style="margin-top:12px">
    <div class="cardlink">本周到期<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;justify-content:center;margin:8px 0 -2px">
      <img src="img/key-render-192.png" alt="" style="width:104px;height:104px;
        filter:drop-shadow(0 12px 24px rgba(0,0,0,.6))">
    </div>
    <div class="ctitle">2 项即将到期</div>
    <div class="clabel" style="margin-top:14px">总计</div>
    <div class="cvalue" style="margin-top:2px">13 项</div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">密码</div><div class="cvalue">11</div></div>
      <div><div class="clabel" style="margin-top:0">指纹</div><div class="cvalue">2</div></div>
    </div>
    <div class="footer">到期前 7 天会在门厅提示。临时码用完即弃，不进台账。</div>
  </div>

  <!-- 卡 2：图 2 的 Fitness 形态 —— 左三色数据行 + 右同心三环 -->
  <div class="card">
    <div class="cardlink">本周用量<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:2px">
      <div style="flex:1">
        <div class="drow"><span class="dot" style="background:#F11B51"></span>
          <span class="dv">8<span class="du">/13 项使用中</span></span></div>
        <div class="drow"><span class="dot" style="background:#3CDE02"></span>
          <span class="dv">2<span class="du">/2 枚指纹</span></span></div>
        <div class="drow"><span class="dot" style="background:#0ADBD8"></span>
          <span class="dv">0<span class="du">/5 个临时码</span></span></div>
      </div>
      ${triple(101)}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">本周开门</div><div class="cvalue">47 次</div></div>
      <div><div class="clabel" style="margin-top:0">日均</div><div class="cvalue">6.7 次</div></div>
    </div>
    <div class="footer">三项都在正常范围，本周用量平稳。</div>
  </div>

  <!-- 钥匙列表 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink">全部钥匙<span class="ch">${sv('chevron')}</span></div>
    ${[
      ['key','朕-大门-长期','朕 · 长期有效','进行中','blue'],
      ['fingerprint','指纹 12','母上 · 2026-09-01','有效','ok'],
      ['fingerprint','指纹 11','母上 · 2026-09-01','有效','ok'],
      ['fingerprint','指纹 10','爱妃 · 2026-08-20','有效','ok'],
      ['timer','临时码 #A7','10 分钟后失效','即将失效','warn'],
    ].map(([ic,n2,s2,b,cls],i)=>
      `${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="13-key-detail.html">
        <div class="ic" style="background:transparent;color:#8D8D93">${sv(ic)}</div>
        <div class="tx"><div class="tt">${n2}</div><div class="sb">${s2}</div></div>
        <span class="badge ${cls}">${b}</span>
        <div class="ch">${sv('chevron')}</div></a>`).join('')}
  </div>
`, 1));

console.log('✓ 02-keys 按图 2 完整重写');
