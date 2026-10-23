'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 屏内迷你界面（图 5 的 Summary 屏）
const miniScreen = (title, sub, body) => `
<div class="mock-scr">
  <div class="sbar"><span>9:41</span>
    <span style="display:flex;gap:4px;align-items:center">
      <svg width="15" height="10" viewBox="0 0 15 10" fill="#FFF"><rect x="0" y="6.5" width="2.6" height="3.5" rx=".8"/><rect x="4" y="4.5" width="2.6" height="5.5" rx=".8"/><rect x="8" y="2.5" width="2.6" height="7.5" rx=".8"/><rect x="12" y="0" width="2.6" height="10" rx=".8"/></svg>
      <svg width="13" height="9" viewBox="0 0 13 9" fill="none" stroke="#FFF" stroke-width="1.1" stroke-linecap="round"><path d="M1 3.2a8 8 0 0 1 11 0"/><path d="M3.4 5.6a5 5 0 0 1 6.2 0"/><circle cx="6.5" cy="7.8" r=".9" fill="#FFF" stroke="none"/></svg>
      <svg width="17" height="9" viewBox="0 0 17 9"><rect x=".5" y=".8" width="13" height="7.4" rx="2.2" fill="none" stroke="#FFF" stroke-opacity=".45"/><rect x="2" y="2.3" width="9.5" height="4.4" rx="1.2" fill="#FFF"/><path d="M15 3.4v3" stroke="#FFF" stroke-opacity=".45" stroke-width="1.2" stroke-linecap="round"/></svg>
    </span></div>
  <div style="padding:56px 16px 0;height:100%;background:#000">
    <div style="font-size:24px;font-weight:700;color:#FFF;letter-spacing:-.4px">${title}</div>
    <div style="font-size:11px;color:#9A9AA0;margin-top:2px">${sub}</div>
    ${body}
  </div>
</div>`;

// 迷你卡（深色 #1C1C1E）
const miniCard = (inner, extra) => `<div style="background:#1C1C1E;border-radius:14px;padding:12px;margin-top:10px;${extra||''}">${inner}</div>`;

// 迷你同心三环
const miniRing = (size) => {
  const C=size/2;
  const R1=C-size*0.075, R2=C-size*0.235, R3=C-size*0.395;
  const W1=size*0.117, W2=size*0.108, W3=size*0.10;
  const g=(r,w,col,p)=>{const circ=2*Math.PI*r;
    return `<circle cx="${C}" cy="${C}" r="${r}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="${w}"/>`+
      `<circle cx="${C}" cy="${C}" r="${r}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${circ*p} ${circ}" transform="rotate(-84 ${C} ${C})"/>`;};
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    g(R1,W1,'#F11B51',0.88) + g(R2,W2,'#3CDE02',0.96) + g(R3,W3,'#0ADBD8',0.33) + '</svg>';
};

const cards = [
  { t:'Activity Details', s:'Set goals, check progress, and view historical workouts.',
    inner: miniScreen('Summary','10-23 周四',
      miniCard(`<div style="display:flex;gap:10px;align-items:center">
        ${miniRing(56)}
        <div style="flex:1">
          <div style="font-size:10px;color:#8D8D93">开门</div>
          <div style="font-size:13px;font-weight:700;color:#F11B51">12/30 次</div>
          <div style="font-size:10px;color:#8D8D93;margin-top:4px">成员</div>
          <div style="font-size:13px;font-weight:700;color:#3CDE02">5/5 位</div>
        </div></div>`) +
      `<div style="display:flex;gap:8px;margin-top:10px">
        <div style="flex:1;background:#1C1C1E;border-radius:14px;padding:10px">
          <div style="font-size:10px;color:#8D8D93">今日</div>
          <div style="font-size:15px;font-weight:700;color:#0090FC;margin-top:2px">8</div></div>
        <div style="flex:1;background:#1C1C1E;border-radius:14px;padding:10px">
          <div style="font-size:10px;color:#8D8D93">本周</div>
          <div style="font-size:15px;font-weight:700;color:#0090FC;margin-top:2px">47</div></div>
      </div>`) },
  { t:'Keys', s:'Every key, who holds it, and when it expires.',
    inner: miniScreen('Keys','13 项 · 2 类',
      `<div style="display:flex;gap:6px;margin-top:10px">
        <div style="height:26px;padding:0 10px;border-radius:999px;background:#232326;display:flex;align-items:center;font-size:10px;color:#FFF">全部</div>
        <div style="height:26px;padding:0 10px;border-radius:999px;background:transparent;display:flex;align-items:center;font-size:10px;color:#8D8D93">密码</div>
        <div style="height:26px;padding:0 10px;border-radius:999px;background:transparent;display:flex;align-items:center;font-size:10px;color:#8D8D93">指纹</div>
      </div>` +
      ['朕-大门-长期','指纹 12','指纹 11'].map((n,i)=>
        `<div style="display:flex;align-items:center;gap:8px;padding:10px 0;${i?'border-top:1px solid rgba(255,255,255,.08)':''}">
          <span style="color:#8D8D93;width:11px;height:11px">${sv('key')}</span>
          <div style="flex:1"><div style="font-size:11px;color:#FFF">${n}</div>
          <div style="font-size:10px;color:#8D8D93">朕 · 长期有效</div></div>
          <span style="font-size:9px;font-weight:600;padding:2px 6px;border-radius:999px;background:rgba(0,144,252,.16);color:#0090FC">有效</span>
        </div>`).join('')) },
  { t:'This Lock', s:'Battery, signal, and firmware at a glance.',
    inner: miniScreen('这台锁','JZ · 1.0.2',
      miniCard(`<div style="display:flex;align-items:center;gap:10px">
        <div style="flex:1">
          <div style="font-size:10px;color:#8D8D93">电量</div>
          <div style="font-size:22px;font-weight:700;color:#30D158">47<span style="font-size:11px">%</span></div>
          <div style="font-size:10px;color:#8D8D93;margin-top:6px">信号</div>
          <div style="font-size:13px;font-weight:700;color:#FFF">−76 dBm</div>
        </div>
        ${miniRing(52)}
      </div>`) +
      `<div style="display:flex;gap:8px;margin-top:10px">
        <div style="flex:1;background:#1C1C1E;border-radius:14px;padding:10px">
          <div style="font-size:10px;color:#8D8D93">握手</div>
          <div style="font-size:13px;font-weight:700;color:#FFF;margin-top:2px">1,033<span style="font-size:10px">ms</span></div></div>
        <div style="flex:1;background:#1C1C1E;border-radius:14px;padding:10px">
          <div style="font-size:10px;color:#8D8D93">固件</div>
          <div style="font-size:13px;font-weight:700;color:#FFF;margin-top:2px">1.0.2</div></div>
      </div>`) },
];

const track = cards.map((c, i) => `
  <div class="shell-card">
    <div class="stt">${c.t}</div>
    <div class="ssub">${c.s}</div>
    <div class="mock">
      <div class="mock-in">
        <div class="island"></div>
        ${c.inner}
      </div>
    </div>
  </div>`).join('');

fs.writeFileSync(D+'75-shell.html', `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>功能导览</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone"><div class="shell">
  <a class="shell-close" href="03-devices.html">${sv('xmark')}</a>
  <div class="shell-track">${track}</div>
</div></div>
<script src="icons-render.js"></script><script src="interact.js"></script></body></html>`);

console.log('✓ 75-shell.html 生成（模板 A0 展示壳）');
