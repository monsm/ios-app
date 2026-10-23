'use strict';
// 剩余 6 页补视觉主角
const L = require('./lib.js');
const V = require('./viz.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 11-fingerprint：容量大环做主角 ══
// [已移交给 gen-credential.js] fs.writeFileSync(D+'11-fingerprint.html', L.page('指纹', `
/* ... 省略 ...

  <div style="margin-top:8px;display:flex;justify-content:center">
    ${V.ring(220, 0.76, '#0ADBD8', '38', '38 / 50')}
  </div>

  <div class="h1" style="margin-top:32px">指纹</div>
  <div class="sub">本机登记 3 枚 · 锁内还可录 12 枚</div>

  <div class="cols" style="margin-top:26px;padding:0 8px">
    <div><div class="clabel" style="margin-top:0">本机登记</div><div class="cvalue" style="font-size:19px;font-weight:700">3 枚</div></div>
    <div><div class="clabel" style="margin-top:0">锁内余量</div><div class="cvalue" style="font-size:19px;font-weight:700">12 枚</div></div>
  </div>

  <div class="card" style="margin-top:26px;padding:6px 0">
    <div style="padding:8px 20px 6px;font-size:12px;color:#6A6A6E">本机登记</div>
    ${[['1','指纹 12','母上 · 2026-09-01'],['2','指纹 11','母上 · 2026-09-01'],['3','指纹 10','爱妃 · 2026-08-20']].map(([n,t,s],i)=>
      `${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="13-key-detail.html">
        <div class="ic" style="background:transparent;color:#8D8D93">${sv('fingerprint')}</div>
        <div class="tx"><div class="tt">${t}</div><div class="sb">${s}</div></div>
        <span class="badge ok">有效</span>
        <div class="ch">${sv('chevron')}</div></a>`).join('')}
  </div>

  <div class="card">
    <div style="font-size:13px;color:#8D8D93;line-height:1.6">
      指纹录在锁里，本机只记「谁的第几枚」。删一枚要去锁上操作。
    </div>
  </div>

  <button class="btn" style="margin-top:4px">录入新指纹</button>
  <div style="text-align:center;font-size:12px;color:#6A6A6E;margin-top:12px">需要手机靠近门锁</div>
`, 1, {nav:true, back:'02-keys', right:'编辑'}));

*/
// ══ 13-key-detail：密码大数字做主角 ══
// [已移交给 gen-fix4.js] fs.writeFileSync(D+'13-key-detail.html', L.page('密码详情', `
/* ... 省略 ...

  <div style="margin-top:8px;display:flex;align-items:center;gap:12px">
    <img src="img/app-key.png" alt="" style="width:44px;height:44px;border-radius:12px">
    <div style="flex:1"><div style="font-size:19px;font-weight:700">朕-大门-长期</div>
      <div style="font-size:13px;color:#8D8D93;margin-top:3px">密码 · 6 位</div></div>
    <span class="badge blue">进行中</span>
  </div>

  <div style="text-align:center;padding:36px 0 28px">
    <div style="font-size:52px;font-weight:700;letter-spacing:14px;line-height:1;
      font-variant-numeric:tabular-nums;color:#5E5CE6">••••••</div>
    <div style="font-size:12px;color:#8D8D93;margin-top:16px">点「显示」查看明文</div>
  </div>

  <div style="display:flex;gap:10px">
    <button class="btn sec" style="flex:1">显示</button>
    <button class="btn sec" style="flex:1">复制</button>
  </div>

  <div class="duo" style="margin-top:16px">
    <div class="metric-card">
      <div class="mh"><span class="mt">已使用</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">累计</div><div class="mv">24<small>次</small></div>
      ${V.bars([2,3,1,4,6,3,2,5,8,4,3,6,9,5],{h:34,a0:'10-10',a1:'10-14',a2:'10-18',a3:'10-23'})}
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">最近一次</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">今天</div><div class="mv" style="font-size:21px">07:12</div>
      <div style="font-size:11px;color:#8D8D93;margin-top:12px">朕 · 手动</div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">归属与授权<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:4px">
      ${[['归属成员','朕'],['授权来源','管理员创建'],['创建时间','2026-10-18 10:05'],['有效期','长期']].map(([k,v])=>
        `<div style="display:flex;justify-content:space-between;font-size:15px">
          <span style="color:#8D8D93">${k}</span><span>${v}</span></div>`).join('')}
    </div>
    <div class="footer">台账记录了这把钥匙的归属与授权链。改归属会写一条审计。</div>
  </div>

  <button class="btn dgr" style="margin-top:4px">删除这项钥匙</button>
`, 1, {nav:true, back:'10-keys-manage', right:'编辑'}));

*/
// ══ 22-firmware：版本对比 + 进度环做主角 ══
fs.writeFileSync(D+'22-firmware.html', L.page('固件升级', `
  <div style="margin-top:8px;display:flex;align-items:center;justify-content:center;gap:24px">
    <div style="text-align:center">
      <div style="font-size:11px;color:#8D8D93">当前</div>
      <div style="font-size:30px;font-weight:700;margin-top:4px;font-variant-numeric:tabular-nums">1.0.2</div>
    </div>
    <div style="color:#6A6A6E;font-size:20px">→</div>
    <div style="text-align:center">
      <div style="font-size:11px;color:#8D8D93">目标</div>
      <div style="font-size:30px;font-weight:700;margin-top:4px;color:#5E5CE6">未选</div>
    </div>
  </div>

  <div class="h1" style="margin-top:30px">固件升级</div>
  <div class="sub">升级前请完成全部检查项</div>

  <div class="card" style="margin-top:26px">
    <div class="cardlink">升级进度<span class="ch">${sv('chevron')}</span></div>
    ${V.steps(['检查','传输','写入','完成'],1,'#5E5CE6')}
    <div class="sep"></div>
    <div style="font-size:13px;color:#8D8D93;line-height:1.6">
      请保持手机靠近门锁，升级过程中不要离开页面。
    </div>
  </div>

  <div class="duo">
    <div class="metric-card">
      <div class="mh"><span class="mt">电量</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">升级需 ≥30%</div>
      <div class="mv" style="color:#30D158">47<small>%</small></div>
      <div style="font-size:11px;color:#30D158;margin-top:10px">✓ 充足</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">连接</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">蓝牙</div>
      <div class="mv" style="font-size:19px;color:#30D158">已就绪</div>
      <div style="font-size:11px;color:#8D8D93;margin-top:10px">−76 dBm</div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">升级前检查<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:12px">
      ${[['电量充足','当前 47%'],['蓝牙已开启','已就绪']].map(([n,s])=>
        `<div style="display:flex;align-items:center;gap:10px">
          <span class="badge ok">✓</span>
          <div style="flex:1"><div style="font-size:15px">${n}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:2px">${s}</div></div></div>`).join('')}
      <div style="display:flex;align-items:center;gap:10px">
        <span class="sw on" style="transform:scale(.8);transform-origin:left"></span>
        <span style="font-size:15px;flex:1">已生成升级前备份</span></div>
      <div style="display:flex;align-items:center;gap:10px">
        <span class="sw on" style="transform:scale(.8);transform-origin:left"></span>
        <span style="font-size:15px;flex:1">时间充足，不会中途离开</span></div>
    </div>
  </div>

  <button class="btn ghost" style="margin-top:4px">选择固件包（.zip）</button>
  <button class="btn" style="margin-top:10px;background:rgba(255,255,255,.10);color:#5A5A5E">开始升级</button>
`, 2, {nav:true, back:'03-devices'}));

console.log('✓ 11 / 13 / 22 补主角');
