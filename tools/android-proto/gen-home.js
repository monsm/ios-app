'use strict';
// tools/android-proto/gen-home.js —— AND-01 主屏开锁
// 参考：图1 Health Age（渐变开口大环 + 游标白边 + 中心大字 + 顶部 chips + 两列数据）
// 源码功能：UnlockDial 信号转盘（tier: 正在寻找/寻找中/很近/近/有点远/远/信号已满）、
//           SignalMetric（当前信号）、AutoOpen（已武装/RSSI ≥ -38 且距上次 >8 秒）、
//           白底黑字胶囊开锁（源码规范）
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 图1 渐变开口环：连续 5-stop（青绿→蓝→深蓝），信号越近点亮越多
// RSSI 映射：-38 dBm=秒开(100%)，-42=很近(83%)，-55=近(66%)，-65=有点远(50%)，-75=远(33%)
const dial = (size, pct, rssi, tier) => {
  const W = Math.round(size * 0.092);          // 图1 环宽 ~9.2%
  const C = size/2, R = C - W/2;
  const circ = 2*Math.PI*R;
  // 5-stop 连续渐变（图1 实测）
  const grad = ['#4A9E96','#2E8FC0','#1E6AAE','#1560A8','#0A84FF'];
  const stops = grad.map((c,i)=>`<stop offset="${(i/(grad.length-1)*100).toFixed(0)}%" stop-color="${c}"/>`).join('');
  const GAP = 0.115;                            // 图1 底部开口
  const sweep = 1 - GAP;
  const arcLen = circ * sweep * pct;
  // 开口朝下：从底部左侧开始顺时针
  const rot = -90 + (GAP/2)*360;
  const track = `<circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="rgba(255,255,255,.085)" stroke-width="${W}"
      stroke-linecap="round" stroke-dasharray="${(circ*sweep).toFixed(1)} ${circ.toFixed(1)}" transform="rotate(${rot.toFixed(1)} ${C} ${C})"/>`;
  const lit = `<circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="url(#gAnd1)" stroke-width="${W}"
      stroke-linecap="round" stroke-dasharray="${Math.max(1,arcLen).toFixed(1)} ${circ.toFixed(1)}" transform="rotate(${rot.toFixed(1)} ${C} ${C})"/>`;
  // 顶部 tick（图1 顶部短竖条）
  const tick = `<rect x="${C-3.5}" y="${C-R-W/2-2}" width="7" height="${(W*0.34).toFixed(1)}" rx="3.5" fill="rgba(255,255,255,.34)" transform="rotate(0 ${C} ${C})"/>`;
  // 游标：白描边亮蓝圆点（图1），放在点亮弧末端
  const ang = (rot + sweep*pct*360) * Math.PI/180;
  const px = C + R*Math.cos(ang), py = C + R*Math.sin(ang);
  const cursor = pct > 0.02 ? `<circle cx="${px.toFixed(1)}" cy="${py.toFixed(1)}" r="${(W*0.62).toFixed(1)}" fill="#0A84FF" stroke="#FFF" stroke-width="3.2"/>` : '';
  const nf = Math.round(size * 0.30);
  const centerNum = `<div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center">
    <div style="font-size:${nf}px;font-weight:800;line-height:1;color:#0A84FF;font-variant-numeric:tabular-nums;letter-spacing:${-(nf*0.026).toFixed(1)}px;text-shadow:0 0 ${Math.round(nf*0.5)}px rgba(10,132,255,.42)">${rssi}</div>
    <div style="font-size:${Math.max(11,Math.round(nf*0.13))}px;font-weight:600;color:#6A6A72;margin-top:${Math.round(nf*0.13)}px;letter-spacing:4px">dBm · ${tier}</div>
  </div>`;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="display:block;position:relative">
    <defs><linearGradient id="gAnd1" x1="0" y1="1" x2="1" y2="0">${stops}</linearGradient></defs>
    ${track}${lit}${tick}${cursor}
  </svg>
  ${centerNum}`;
};

fs2.writeFileSync(D+'01-home.html', L.page('KF Key', `
  <!-- 图1 顶部 chips：两枚玻璃 chip（左=锁，右=信号 tier） -->
  <div style="display:flex;gap:12px;margin-top:14px">
    <div class="chip" style="flex:1;display:flex;align-items:center;gap:11px;padding:11px 16px">
      <span style="width:26px;height:26px;border-radius:8px;background:rgba(48,209,88,.18);display:inline-flex;align-items:center;justify-content:center">${sv('key','15px')}</span>
      <span style="flex:1;min-width:0"><span style="display:block;font-size:12px;color:#8A8A90">然然家</span>
      <span style="display:block;font-size:16px;font-weight:700;color:#FFF;margin-top:1px">已武装</span></span>
    </div>
    <div class="chip" style="flex:1;display:flex;align-items:center;gap:11px;padding:11px 16px">
      <span style="width:26px;height:26px;display:inline-flex;align-items:center;justify-content:center">
        <svg width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="rgba(255,255,255,.16)" stroke-width="3.4"/>
        <circle cx="12" cy="12" r="9" fill="none" stroke="#0A84FF" stroke-width="3.4" stroke-linecap="round" stroke-dasharray="40 56.5" transform="rotate(-90 12 12)"/></svg>
      </span>
      <span style="flex:1;min-width:0"><span style="display:block;font-size:12px;color:#8A8A90">信号</span>
      <span style="display:block;font-size:16px;font-weight:700;color:#FFF;margin-top:1px">−42 dBm</span></span>
    </div>
  </div>

  <!-- 图1 巨大渐变开口环 = UnlockDial：信号越近点亮越多 -->
  <div style="position:relative;margin:26px auto 0;width:322px;height:322px">
    ${dial(322, .83, '−42', '很近')}
  </div>

  <!-- 图1 两行标题 + 正文 -->
  <div class="h1" style="margin-top:34px;font-size:30px;line-height:1.2;letter-spacing:-.3px">信号最强，靠近就<br>能秒开</div>
  <div class="sub" style="margin-top:12px;font-size:16px;line-height:1.55">当前 −42 dBm，达到秒开线（≥ −38 dBm 即 100% 点亮）。靠近门锁，转到信号最强的朝向。</div>

  <!-- 图1 两列数据 -->
  <div class="cols" style="margin-top:26px">
    <div><div class="clabel">当前信号</div><div class="cvalue">−42 dBm</div></div>
    <div><div class="clabel">链路状态</div><div class="cvalue">已热</div></div>
  </div>

  <!-- 图2 卡解剖：自动开锁说明（源码 SettingsCard 真实文案） -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">自动开锁<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="color:#30D158;width:22px;height:22px">${sv('shieldCheck')}</span>
      <div style="flex:1"><div style="font-size:16px;font-weight:600">已武装</div>
      <div style="font-size:12px;color:#8A8A90;margin-top:2px">RSSI ≥ −38 dBm 且距上次 &gt; 8 秒</div></div>
    </div>
    <div class="sep"></div>
    <div class="footer">开着它：手机解了锁、App 在前台时，靠近到 −38 dBm 以内会自动开一次。一次靠近只开一次 —— 要走开让信号掉到 −55 dBm 以下，隔 6 秒后再靠近才会再开。</div>
  </div>

  <!-- 源码规范：开锁按钮 = 白底黑字胶囊 -->
  <button class="btn" style="margin-top:20px;background:#FFF;color:#0A0A0C;font-weight:700;height:54px;border-radius:999px;font-size:17px">轻点开锁</button>
`, 0, {nav:false, tabbar:false}));
