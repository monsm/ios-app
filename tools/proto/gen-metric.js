'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';

// 迷你柱图
const mb = (h) => Array.from({length:24},(_,i)=>`<i style="height:${Math.max(2,h[i]||2)}px"></i>`).join('');

// ══ 20 我的门锁 —— 图 2 的双列 MetricCard ══
// [已移交给 gen-locks.js] fs.writeFileSync(D+'20-locks.html', L.page('我的门锁', `
/* ... 省略 ...

  <div class="h1">我的门锁</div>
  <div class="sub">1 把 · 顺序即启动默认</div>

  <!-- 双列 MetricCard：锁的三个读数（图 2 Step Count 形态） -->
  <div class="duo" style="margin-top:24px">
    <div class="metric-card">
      <div class="mh"><span class="mt">电量</span><span class="mc">›</span></div>
      <div class="ms">当前</div>
      <div class="mv" style="color:#30D158">47<small>%</small></div>
      <div class="minibar">${mb([42,43,44,43,45,44,46,45,47,46,47,47,47,47,47,47,47,47,47,47,47,47,47,47])}</div>
      <div style="font-size:10px;color:var(--text-tert);margin-top:6px">近 24 小时</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">信号</span><span class="mc">›</span></div>
      <div class="ms">当前</div>
      <div class="mv">−76<small>dBm</small></div>
      <div class="minibar">${mb([-0,-0,-0,2,4,8,14,22,18,10,6,4,3,2,2,2,2,3,5,8,6,4,3,2].map(v=>Math.max(2,v)))}</div>
      <div style="font-size:10px;color:var(--text-tert);margin-top:6px">近 24 小时</div>
    </div>
  </div>

  <div class="duo">
    <div class="metric-card">
      <div class="mh"><span class="mt">握手</span><span class="mc">›</span></div>
      <div class="ms">最近一次</div>
      <div class="mv">1,033<small>ms</small></div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">均值 980 ms</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">固件</span><span class="mc">›</span></div>
      <div class="ms">当前版本</div>
      <div class="mv">1.0.2</div>
      <div style="font-size:11px;color:#30D158;margin-top:10px">✓ 已是最新</div>
    </div>
  </div>

  <!-- 锁列表：图 5 的 72pt 行形态（单条） -->
  <div class="dpanel" style="margin-top:12px">
    <div class="dhead">门锁</div>
    <a class="drow72" href="21-lock-profile.html">
      <div style="width:38px;height:38px;border-radius:11px;background:rgba(0,144,252,.16);
        display:flex;align-items:center;justify-content:center;font-size:18px;flex:0 0 auto">🔒</div>
      <div class="dl"><div class="dt">然然家</div><div class="ds">JZ · 固件 1.0.2 · 12 指纹</div></div>
      <span class="badge blue">当前</span>
      <div style="color:var(--text-tert);font-size:18px;margin-left:6px">›</div>
    </a>
  </div>

  <div style="padding:0 4px;font-size:12px;color:var(--text-tert);line-height:1.6">
    顺序就是启动时默认选中的顺序。左滑可隐藏，长按可拖动排序。
  </div>

  <a class="btn ghost" href="23-gateway.html" style="margin-top:16px">添加门锁</a>
`, 2, {nav:true, back:'03-devices', right:'排序'}));

*/
// ══ 11 指纹 —— 双列 MetricCard ══
// [已移交给 gen-credential.js] fs.writeFileSync(D+'11-fingerprint.html', L.page('指纹', `
/* ... 省略 ...

  <div class="h1">指纹</div>
  <div class="sub">锁内 38 / 50 · 本机登记 3 枚</div>

  <div class="duo" style="margin-top:24px">
    <div class="metric-card">
      <div class="mh"><span class="mt">锁内已用</span><span class="mc">›</span></div>
      <div class="ms">指纹</div>
      <div class="mv">38<small>/50</small></div>
      <div class="minibar">${Array.from({length:50},(_,i)=>`<i style="height:${i<38?28:8}px;background:${i<38?'#0ADBD8':'rgba(255,255,255,.08)'}"></i>`).join('')}</div>
      <div style="font-size:10px;color:var(--text-tert);margin-top:6px">每格一枚</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">本机登记</span><span class="mc">›</span></div>
      <div class="ms">有归属</div>
      <div class="mv">3<small>枚</small></div>
      <div style="margin-top:14px;display:flex;flex-direction:column;gap:8px">
        ${[['母上','#E8A05C','2'],['爱妃','#0ADBD8','1']].map(([n,c,k])=>`
          <div style="display:flex;align-items:center;gap:8px;font-size:12px">
            <span style="width:18px;height:18px;border-radius:50%;background:${c}22;color:${c};
              display:flex;align-items:center;justify-content:center;font-size:10px">${n[0]}</span>
            <span style="flex:1;color:var(--text-sub)">${n}</span>
            <span style="font-variant-numeric:tabular-nums">${k}</span></div>`).join('')}
      </div>
    </div>
  </div>

  <div class="card">
    <div style="font-size:13px;color:var(--text-sub);line-height:1.6">
      指纹录在锁里，本机只记「谁的第几枚」。删一枚要去锁上操作。
    </div>
  </div>

  <div class="dpanel">
    <div class="dhead">本机登记</div>
    ${[['1','指纹 12','母上 · 2026-09-01','ok','有效'],
       ['2','指纹 11','母上 · 2026-09-01','ok','有效'],
       ['3','指纹 10','爱妃 · 2026-08-20','ok','有效']].map(([n,t,s,cls,b])=>`
      <a class="drow72" href="13-key-detail.html">
        <div style="width:38px;height:38px;border-radius:11px;background:rgba(232,160,92,.18);
          color:#E8A05C;display:flex;align-items:center;justify-content:center;
          font-size:15px;font-weight:600;flex:0 0 auto">${n}</div>
        <div class="dl"><div class="dt">${t}</div><div class="ds">${s}</div></div>
        <span class="badge ${cls}">${b}</span>
        <div style="color:var(--text-tert);font-size:18px;margin-left:6px">›</div>
      </a>`).join('')}
  </div>

  <button class="btn" style="margin-top:4px">录入新指纹</button>
  <div style="text-align:center;font-size:12px;color:var(--text-tert);margin-top:12px">
    需要手机靠近门锁
  </div>
`, 1, {nav:true, back:'02-keys', right:'编辑'}));

*/
// ══ 25 校准时间 —— 双列 MetricCard ══
// [已移交给 gen-synctime.js] fs.writeFileSync(D+'25-synctime.html', L.page('同步时间', `
/* ... 省略 ...

  <div class="h1">同步时间</div>
  <div class="sub">锁比手机慢 3 秒</div>

  <!-- 一个大读数（图 3 的 displayNumber 形态）-->
  <div class="card" style="margin-top:24px;text-align:center;padding:28px 20px">
    <div style="font-size:64px;font-weight:700;letter-spacing:-2px;
      font-variant-numeric:tabular-nums;color:#FF9F0A">−3<span style="font-size:24px">s</span></div>
    <div style="font-size:13px;color:var(--text-sub);margin-top:10px">锁比手机慢 3 秒</div>
  </div>

  <!-- 双列：锁钟 vs 手机钟（图 2 形态）-->
  <div class="duo">
    <div class="metric-card">
      <div class="mh"><span class="mt">锁内时钟</span><span class="mc">›</span></div>
      <div class="ms">读到的</div>
      <div class="mv" style="font-size:22px">06:41:57</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">手机时间</span><span class="mc">›</span></div>
      <div class="ms">现在</div>
      <div class="mv" style="font-size:22px;color:#30D158">06:42:00</div>
    </div>
  </div>

  <div class="card">
    <div style="font-size:13px;color:var(--text-sub);line-height:1.6">
      校准会把手机时间写进锁内（cmd 0E）。偏差为正即锁慢，为负即锁快。
    </div>
  </div>

  <button class="btn" style="margin-top:4px">🕐 将手机时间同步到锁内</button>
  <div style="text-align:center;font-size:12px;color:var(--text-tert);margin-top:12px;line-height:1.6">
    请将手机靠近门锁 · 请确保手机时间准确
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
console.log('✓ 20-locks / 11-fingerprint / 25-synctime 改用双列 MetricCard');
