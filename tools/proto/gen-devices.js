'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';

// ── 20 我的门锁 ──
// [已移交给 gen-locks.js] fs.writeFileSync(D+'20-locks.html', L.page('我的门锁', `
/* ... 省略 ...

  <div class="h1">我的门锁</div>
  <div class="sub">1 把 · 顺序即启动默认</div>

  <div class="card rowlist" style="margin-top:24px;padding:6px 0">
    ${L.row('21-lock-profile','🔒','rgba(0,144,252,.16)','#0090FC','然然家','JZ · 固件 1.0.2 · 12 指纹','<span class="badge blue">当前</span>')}
    <div class="sep"></div>
    <div style="padding:14px 20px;font-size:12px;color:var(--text-tert);line-height:1.6">
      顺序就是启动时默认选中的顺序。左滑可隐藏，长按可拖动排序。
    </div>
  </div>

  <a class="btn ghost" href="23-gateway.html" style="margin-top:12px">添加门锁</a>
`, 2, {nav:true, back:'03-devices', right:'排序'}));

*/
// ── 21 锁档案 ──
// [已移交给 gen-lockprofile2.js] fs.writeFileSync(D+'21-lock-profile.html', L.page('锁档案', `
/* ... 省略 ...

  <div style="text-align:center;padding:20px 0 28px">
    <div style="width:110px;height:110px;border-radius:50%;margin:0 auto;
      background:linear-gradient(135deg,#7B7BE8,#5E5CE6);display:flex;align-items:center;
      justify-content:center;font-size:48px;box-shadow:0 0 60px rgba(123,123,232,.45)">🔒</div>
    <div style="font-size:28px;font-weight:700;margin-top:18px">然然家</div>
    <div style="font-size:13px;color:var(--text-sub);margin-top:6px">JZ · 固件 1.0.2</div>
  </div>

  <div class="card">
    <div class="cardlink">符号<span class="ch">›</span></div>
    <div style="display:flex;gap:14px;margin-top:10px;overflow-x:auto">
      ${['🔒','🏠','🏢','🚗','🏬','🔑','🚪'].map((s,i)=>
        `<div style="flex:0 0 auto;width:56px;height:56px;border-radius:50%;
          background:${i===0?'rgba(123,123,232,.20)':'rgba(255,255,255,.06)'};
          border:2px solid ${i===0?'#7B7BE8':'transparent'};
          display:flex;align-items:center;justify-content:center;font-size:24px">${s}</div>`).join('')}
    </div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('32-member-detail','👥','rgba(0,144,252,.16)','#0090FC','成员与钥匙','5 位成员 · 13 项钥匙')}
    <div class="sep"></div>
    ${L.row('22-firmware','⬇','rgba(232,160,92,.18)','#E8A05C','固件','1.0.2 · 已是最新')}
    <div class="sep"></div>
    ${L.row('25-synctime','🕐','rgba(10,219,216,.16)','#0ADBD8','锁内时钟','偏差 −3 秒')}
  </div>

  <button class="btn dgr" style="margin-top:12px">解绑这把锁</button>
`, 2, {nav:true, back:'20-locks', right:'保存'}));

*/
// ── 22 固件升级 ──
// [已移交给 gen-hero2.js] fs.writeFileSync(D+'22-firmware.html', L.page('固件升级', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;padding:0;overflow:hidden">
    <div style="background:linear-gradient(135deg,#5E5CE6,#0090FC);padding:24px 20px;
      display:flex;align-items:center;justify-content:space-around">
      <div style="text-align:center">
        <div style="font-size:11px;color:rgba(255,255,255,.7)">当前</div>
        <div style="font-size:24px;font-weight:700;margin-top:4px">1.0.2</div>
      </div>
      <div style="font-size:22px;color:rgba(255,255,255,.6)">→</div>
      <div style="text-align:center">
        <div style="font-size:11px;color:rgba(255,255,255,.7)">目标</div>
        <div style="font-size:24px;font-weight:700;margin-top:4px">未选包</div>
      </div>
    </div>
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">升级前检查</div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:16px">
      <div style="display:flex;align-items:center;gap:10px">
        <span class="badge ok">✓</span><span style="font-size:15px;flex:1">电量充足</span>
        <span style="font-size:13px;color:var(--text-sub)">当前 47%</span></div>
      <div style="display:flex;align-items:center;gap:10px">
        <span class="badge ok">✓</span><span style="font-size:15px;flex:1">蓝牙已开启</span>
        <span style="font-size:13px;color:var(--text-sub)">已就绪</span></div>
      <div style="display:flex;align-items:center;gap:10px">
        <span class="sw on" style="transform:scale(.8);transform-origin:left"></span>
        <span style="font-size:15px;flex:1">已生成升级前备份</span></div>
      <div style="font-size:13px;color:var(--warn)">上次备份：从未备份 — 建议先到「备份」页导出</div>
      <div style="display:flex;align-items:center;gap:10px">
        <span class="sw on" style="transform:scale(.8);transform-origin:left"></span>
        <span style="font-size:15px;flex:1">时间充足，不会中途离开</span></div>
    </div>
  </div>

  <a class="btn ghost" style="margin-top:4px">选择固件包（.zip）</a>
  <button class="btn" style="margin-top:10px;background:rgba(255,255,255,.10);color:#5A5A5E">开始升级</button>
  <div style="text-align:center;font-size:12px;color:var(--text-tert);margin-top:12px">
    请先完成上方全部检查项，并选择固件包
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
// ── 23 网关配网 ──
// [已移交给 gen-dongle-gw.js] fs.writeFileSync(D+'23-gateway.html', L.page('智能网关', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="text-align:center;padding:8px 0 4px">
      <div style="font-size:34px">💡</div>
      <div style="font-size:19px;font-weight:700;margin-top:10px">先把网关重置</div>
      <div style="font-size:13px;color:rgba(255,255,255,.7);margin-top:8px;line-height:1.5">
        接通电源 → 长捅重置孔约 5 秒 → 等待指示灯变成橙色
      </div>
    </div>
    <div class="sep" style="background:rgba(255,255,255,.18)"></div>
    <div style="display:flex;align-items:center;gap:12px">
      <span style="font-size:15px;flex:1">指示灯已变成橙色</span>
      <span class="sw on"></span>
    </div>
    <div style="text-align:center;font-size:12px;color:rgba(255,255,255,.6);margin-top:10px">
      勾选后进入下一步
    </div>
  </div>

  <div class="empty" style="padding:48px 28px">
    <div class="ic">📡</div>
    <div class="t">还没有添加网关</div>
    <div class="s">先在上方重置网关并勾选指示灯状态，再回来配网</div>
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
// ── 24 钥匙串 ──
// [已移交给 gen-dongle-gw.js] fs.writeFileSync(D+'24-dongles.html', L.page('蓝牙钥匙串', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="font-size:30px">🔑</div>
      <div><div style="font-size:17px;font-weight:700">随身开门</div>
      <div style="font-size:12px;color:rgba(255,255,255,.7);margin-top:4px">钥匙串靠近门锁即可开门，不用掏手机</div></div>
    </div>
    <div class="sep" style="background:rgba(255,255,255,.18)"></div>
    <button class="btn" style="background:rgba(255,255,255,.16);color:#FFF">📡 搜索钥匙串</button>
  </div>

  <div class="empty" style="padding:48px 28px">
    <div class="ic">🔑</div>
    <div class="t">还没有钥匙串</div>
    <div class="s">上电后点上方「搜索钥匙串」即可添加</div>
    <button class="btn sec" style="margin-top:20px;width:auto;padding:0 28px">搜索钥匙串</button>
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
// ── 25 校准时间 ──
// [已移交给 gen-synctime.js] fs.writeFileSync(D+'25-synctime.html', L.page('同步时间', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">锁钟偏差<span class="ch">›</span></div>
    <div style="text-align:center;padding:16px 0">
      <div style="font-size:52px;font-weight:700;font-variant-numeric:tabular-nums;color:#FF9F0A">−3<span style="font-size:20px">s</span></div>
      <div style="font-size:13px;color:var(--text-sub);margin-top:8px">锁比手机慢 3 秒</div>
    </div>
    <div class="sep"></div>
    <div style="font-size:13px;color:var(--text-sub);line-height:1.6">
      校准会把手机时间写进锁内（cmd 0E）。偏差为正即锁慢，为负即锁快。
    </div>
  </div>

  <div class="card">
    <div class="cardlink">对照<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:4px">
      <div style="display:flex;justify-content:space-between;font-size:15px">
        <span style="color:var(--text-sub)">锁内时钟</span>
        <span style="font-variant-numeric:tabular-nums">06:41:57</span></div>
      <div style="display:flex;justify-content:space-between;font-size:15px">
        <span style="color:var(--text-sub)">手机时间</span>
        <span style="font-variant-numeric:tabular-nums">06:42:00</span></div>
    </div>
  </div>

  <button class="btn" style="margin-top:4px">🕐 将手机时间同步到锁内</button>
  <div style="text-align:center;font-size:12px;color:var(--text-tert);margin-top:12px;line-height:1.6">
    请将手机靠近门锁 · 请确保手机时间准确
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
console.log('✓ 设备域 6 页');
