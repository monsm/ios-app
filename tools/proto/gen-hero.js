'use strict';
// 3 页补「视觉主角」（§0 总则 3：一屏只有一个主角）
const L = require('./lib.js');
const V = require('./viz.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 52-stats：大环做主角（图 1 的形态：缺口大弧 + 中心大数字）══
const heroArc = (size, pct, center, unit, color, colorB) => {
  const C = size/2, R = C - size*0.115;
  const circ = 2*Math.PI*R, sweep = circ*300/360;
  const lit = sweep*pct;
  const rot = 210 - 90;
  const endDeg = 210 + 300*pct;
  const rad = (endDeg-90)*Math.PI/180;
  const px = C + R*Math.cos(rad), py = C + R*Math.sin(rad);
  return `<div style="position:relative;width:${size}px;height:${size}px;margin:0 auto">
  <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
    <defs>
      <linearGradient id="hr${size}" x1="0" y1="1" x2="1" y2="0">
        <stop offset="0" stop-color="${color}"/><stop offset="1" stop-color="${colorB}"/>
      </linearGradient>
      <linearGradient id="ht${size}" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#1E2640"/><stop offset="1" stop-color="#10141F"/>
      </linearGradient>
    </defs>
    <circle cx="${C}" cy="${C}" r="${R.toFixed(1)}" fill="none" stroke="url(#ht${size})"
      stroke-width="${(size*0.113).toFixed(1)}" stroke-linecap="round"
      stroke-dasharray="${sweep.toFixed(1)} ${circ.toFixed(1)}" transform="rotate(${rot} ${C} ${C})"/>
    <circle cx="${C}" cy="${C}" r="${R.toFixed(1)}" fill="none" stroke="url(#hr${size})"
      stroke-width="${(size*0.113).toFixed(1)}" stroke-linecap="round"
      stroke-dasharray="${lit.toFixed(1)} ${circ.toFixed(1)}" transform="rotate(${rot} ${C} ${C})"/>
    <rect x="${(C-4).toFixed(1)}" y="${(size*0.045).toFixed(1)}" width="8" height="${(size*0.072).toFixed(1)}" rx="4" fill="#4A4A7A"/>
    <circle cx="${px.toFixed(1)}" cy="${py.toFixed(1)}" r="${(C*0.075).toFixed(1)}" fill="${colorB}"/>
  </svg>
  <div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center">
    <div style="font-size:56px;font-weight:700;letter-spacing:-1.5px;line-height:1;color:${colorB}">${center}</div>
    <div style="font-size:11px;color:#8D8D93;letter-spacing:2.5px;margin-top:8px">${unit}</div>
  </div></div>`;
};

// [已移交给 gen-stats.js] fs.writeFileSync(D+'52-stats.html', L.page('统计', `
/* ... 省略 ...

  <div style="margin-top:8px">${heroArc(300, 0.62, '127', '次 · 近 30 天', '#00C6FF', '#0090FC')}</div>

  <div style="margin-top:34px">
    <div class="h1">统计</div>
    <div class="sub">1 把门锁 · 5 位成员 · 自动开锁占 41%</div>
  </div>

  <div class="cols" style="margin-top:28px;padding:0 8px">
    <div><div class="clabel" style="margin-top:0">日均</div><div class="cvalue" style="font-size:19px;font-weight:700">4.2 次</div></div>
    <div><div class="clabel" style="margin-top:0">最忙一天</div><div class="cvalue" style="font-size:19px;font-weight:700">9 次</div></div>
  </div>

  <div class="card" style="margin-top:28px">
    <div class="cardlink">开门趋势<span class="ch">${sv('chevron')}</span></div>
    <div style="position:relative;height:104px;margin-top:12px">
      <div class="dash"><i></i><i></i><i></i><i></i><i></i><i></i></div>
      <svg width="100%" height="104" viewBox="0 0 320 104" preserveAspectRatio="none" style="position:absolute;inset:0">
        <defs><linearGradient id="st2" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#00C6FF" stop-opacity=".42"/>
          <stop offset="1" stop-color="#0090FC" stop-opacity="0"/></linearGradient></defs>
        <path d="M0,76 L36,68 L72,50 L108,60 L144,34 L180,48 L216,40 L252,58 L288,52 L320,64 L320,104 L0,104 Z" fill="url(#st2)"/>
        <path d="M0,76 L36,68 L72,50 L108,60 L144,34 L180,48 L216,40 L252,58 L288,52 L320,64"
          fill="none" stroke="#00C6FF" stroke-width="2"/>
      </svg>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:11px;color:#6A6A6E;margin-top:10px">
      <span>9-22</span><span>9-29</span><span>10-6</span><span>10-13</span><span>10-21</span>
    </div>
    <div class="sep"></div>
    <div class="footer">127 次开门里，自动 41% / 手动 52% / 临时码 7%。</div>
  </div>

  <div class="card">
    <div class="cardlink">成员活跃度<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${L.donut(84,[['#F11B51',0.30],['#3CDE02',0.42],['#0ADBD8',0.22]],'32')}
      <div style="flex:1">
        ${[['#F11B51','朕','24 次'],['#3CDE02','皇子','32 次'],['#0ADBD8','母上','16 次']].map(([c,n,v])=>
          `<div class="drow"><span class="dot" style="background:${c}"></span><span class="dv">${n}<span class="du"> ${v}</span></span></div>`).join('')}
      </div>
    </div>
    <div class="footer">皇子近 7 天开门约 32 次，工作日 8–9 点最活跃。</div>
  </div>
`, 0));

*/
// ══ 12-tempcode：6 位大数字做主角（图 3 displayNumber）══
// [已移交给 gen-credential.js] fs.writeFileSync(D+'12-tempcode.html', L.page('临时密码', `
/* ... 省略 ...

  <div class="h1" style="margin-top:8px">临时密码</div>
  <div class="sub">6 位数字 · 10 分钟内有效 · 只能用一次</div>

  <div class="card" style="margin-top:28px;padding:28px 20px">
    <div style="text-align:center">
      <div style="font-size:48px;font-weight:700;letter-spacing:8px;line-height:1;
        font-variant-numeric:tabular-nums;color:#FF694E;white-space:nowrap">••••••</div>
      <div style="font-size:12px;color:#8D8D93;margin-top:18px">还没生成</div>
    </div>
    <div class="sep" style="margin-top:22px"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">有效期</div><div class="cvalue">10 分钟</div></div>
      <div><div class="clabel" style="margin-top:0">可用次数</div><div class="cvalue">1 次</div></div>
    </div>
    <div class="footer">生成前请先校准门锁时间（0E），否则时间窗不同步会导致密码不匹配。</div>
  </div>

  <button class="btn" style="margin-top:16px;background:#FF694E;color:#1A0A06">生成临时密码</button>

  <div class="card" style="margin-top:16px">
    <div class="cardlink">四种形态<span class="ch">${sv('chevron')}</span></div>
    <div class="duo" style="margin-top:12px;margin-bottom:0">
      ${[['一次性','用一次即失效','#FF694E','1'],['周期','每 30 分钟轮换','#0ADBD8','∞'],['限时','指定时段有效','#5E5CE6','⏱'],['批量','一次发多个','#FF9F0A','▦']].map(([t,d,c,i])=>
        `<div class="duo-card"><div class="dm"><div style="width:56px;height:56px;border-radius:50%;
          background:${c}22;display:flex;align-items:center;justify-content:center;
          font-size:22px;color:${c};font-weight:700">${i}</div></div>
          <div class="dt" style="text-align:center;font-size:15px">${t}</div>
          <div class="dd" style="text-align:center">${d}</div></div>`).join('')}
    </div>
  </div>
`, 1));

*/
// ══ 25-synctime：−3s 大数字做主角 ══
// [已移交给 gen-synctime.js] fs.writeFileSync(D+'25-synctime.html', L.page('同步时间', `
/* ... 省略 ...

  <div style="margin-top:8px;text-align:center;padding:24px 0">
    <div style="font-size:76px;font-weight:700;letter-spacing:-3px;line-height:1;
      font-variant-numeric:tabular-nums;color:#FF9F0A">−3<span style="font-size:28px;margin-left:4px">s</span></div>
    <div style="font-size:13px;color:#8D8D93;margin-top:14px">锁比手机慢 3 秒</div>
  </div>

  <div class="h1">同步时间</div>
  <div class="sub">校准会把手机时间写进锁内（cmd 0E）</div>

  <div class="duo" style="margin-top:28px">
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

  ${V.gaugeClient ? '' : ''}

  <div class="card">
    <div class="cardlink">偏差刻度<span class="ch">${sv('chevron')}</span></div>
    ${V.gauge(-3,-10,10,'#FF9F0A','s')}
    <div class="footer">偏差为正即锁慢，为负即锁快。超过 ±30 秒建议立即校准。</div>
  </div>

  <button class="btn" style="margin-top:4px">🕐 将手机时间同步到锁内</button>
  <div style="text-align:center;font-size:12px;color:#6A6A6E;margin-top:12px;line-height:1.6">
    请将手机靠近门锁 · 请确保手机时间准确
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
console.log('✓ 52-stats / 12-tempcode / 25-synctime 补主角');
