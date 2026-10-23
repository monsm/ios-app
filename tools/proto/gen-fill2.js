'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const gcard = (title, visual, desc) => `
<div class="duo-card">
  <div class="dt">${title}</div>
  <div class="dm">${visual}</div>
  ${desc?`<div class="dd">${desc}</div>`:''}
</div>`;

// ══ 13 密码详情 —— 双列 MetricCard ══
// [已移交给 gen-fix4.js] fs.writeFileSync(D+'13-key-detail.html', L.page('密码详情', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="width:48px;height:48px;border-radius:14px;background:rgba(94,92,230,.20);
        display:flex;align-items:center;justify-content:center;font-size:24px">⚿</div>
      <div style="flex:1"><div style="font-size:19px;font-weight:700">朕-大门-长期</div>
      <div style="font-size:13px;color:var(--text-sub);margin-top:3px">密码 · 6 位</div></div>
      <span class="badge blue">进行中</span>
    </div>
    <div class="sep"></div>
    <div style="text-align:center;padding:8px 0">
      <div style="font-size:40px;font-weight:700;letter-spacing:10px;
        font-variant-numeric:tabular-nums">••••••</div>
      <div style="font-size:13px;color:var(--text-sub);margin-top:10px">点「显示」查看明文</div>
    </div>
    <div style="display:flex;gap:10px;margin-top:10px">
      <button class="btn sec" style="flex:1">显示</button>
      <button class="btn sec" style="flex:1">复制</button>
    </div>
  </div>

  <!-- 图 2 双列：使用次数 + 最近使用 -->
  <div class="duo">
    <div class="metric-card">
      <div class="mh"><span class="mt">已使用</span><span class="mc">›</span></div>
      <div class="ms">累计</div>
      <div class="mv">24<small>次</small></div>
      <div class="minibar">${Array.from({length:14},(_,i)=>`<i style="height:${[6,8,14,10,18,22,16,12,20,26,18,14,22,16][i]}px"></i>`).join('')}</div>
      <div style="font-size:10px;color:var(--text-tert);margin-top:6px">近 14 天</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">最近一次</span><span class="mc">›</span></div>
      <div class="ms">今天</div>
      <div class="mv" style="font-size:22px">07:12</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:14px">朕 · 手动</div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">归属与授权<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:4px">
      ${[['归属成员','朕'],['授权来源','管理员创建'],['创建时间','2026-10-18 10:05'],['有效期','长期']].map(([k,v])=>`
        <div style="display:flex;justify-content:space-between;font-size:15px">
          <span style="color:var(--text-sub)">${k}</span><span>${v}</span></div>`).join('')}
    </div>
    <div class="footer">台账记录了这把钥匙的归属与授权链。改归属会写一条审计。</div>
  </div>

  <button class="btn dgr" style="margin-top:4px">删除这项钥匙</button>
`, 1, {nav:true, back:'10-keys-manage', right:'编辑'}));

*/
// ══ 22 固件升级 —— 进度环 ══
// [已移交给 gen-hero2.js] fs.writeFileSync(D+'22-firmware.html', L.page('固件升级', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;padding:0;overflow:hidden">
    <div style="background:linear-gradient(135deg,#5E5CE6,#0090FC);padding:26px 20px;
      display:flex;align-items:center;justify-content:space-around">
      <div style="text-align:center">
        <div style="font-size:11px;color:rgba(255,255,255,.7)">当前</div>
        <div style="font-size:26px;font-weight:700;margin-top:4px">1.0.2</div>
      </div>
      <div style="font-size:24px;color:rgba(255,255,255,.55)">→</div>
      <div style="text-align:center">
        <div style="font-size:11px;color:rgba(255,255,255,.7)">目标</div>
        <div style="font-size:26px;font-weight:700;margin-top:4px">未选包</div>
      </div>
    </div>
  </div>

  <!-- 图 2 的双列：三项检查读数 -->
  <div class="duo">
    <div class="metric-card">
      <div class="mh"><span class="mt">电量</span><span class="mc">›</span></div>
      <div class="ms">升级需 ≥30%</div>
      <div class="mv" style="color:#30D158">47<small>%</small></div>
      <div style="font-size:11px;color:#30D158;margin-top:10px">✓ 充足</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">连接</span><span class="mc">›</span></div>
      <div class="ms">蓝牙</div>
      <div class="mv" style="font-size:20px;color:#30D158">已就绪</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">−76 dBm</div>
    </div>
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">升级前检查</div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:16px">
      ${[['电量充足','当前 47%','ok'],['蓝牙已开启','已就绪','ok']].map(([n,s,c])=>`
        <div style="display:flex;align-items:center;gap:10px">
          <span class="badge ok">✓</span>
          <div style="flex:1"><div style="font-size:15px">${n}</div>
          <div style="font-size:12px;color:var(--text-sub);margin-top:2px">${s}</div></div></div>`).join('')}
      <div style="display:flex;align-items:center;gap:10px">
        <span class="sw on" style="transform:scale(.8);transform-origin:left"></span>
        <span style="font-size:15px;flex:1">已生成升级前备份</span></div>
      <div class="tip" style="margin:0">
        <span>⚠</span><span>上次备份：从未备份 — 建议先到「备份」页导出</span></div>
      <div style="display:flex;align-items:center;gap:10px">
        <span class="sw on" style="transform:scale(.8);transform-origin:left"></span>
        <span style="font-size:15px;flex:1">时间充足，不会中途离开</span></div>
    </div>
  </div>

  <button class="btn ghost" style="margin-top:4px">选择固件包（.zip）</button>
  <button class="btn" style="margin-top:10px;background:rgba(255,255,255,.10);color:#5A5A5E">开始升级</button>
  <div style="text-align:center;font-size:12px;color:var(--text-tert);margin-top:12px">
    请先完成上方全部检查项，并选择固件包
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
// ══ 23 网关配网 —— 模板 D 步骤行 ══
// [已移交给 gen-dongle-gw.js] fs.writeFileSync(D+'23-gateway.html', `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
/* ... 省略 ...

<title>智能网关</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone"><div class="dsheet">
  <div class="dtop" style="background:linear-gradient(180deg,#3C2A18 0%,#2A1E10 100%)">
    <div class="dtitle">智能网关</div>
    <a class="dact" href="03-devices.html">返回</a>
  </div>
  <div class="dbody">
    <div style="padding:16px 14px">
      <div class="card" style="background:linear-gradient(160deg,#5E5CE6,#3C489C);margin-bottom:14px">
        <div style="text-align:center;padding:10px 0 6px">
          <div style="font-size:36px"><span class="svgi" data-i="ring"></span></div>
          <div style="font-size:19px;font-weight:700;margin-top:12px">先把网关重置</div>
          <div style="font-size:13px;color:rgba(255,255,255,.7);margin-top:10px;line-height:1.6">
            接通电源 → 长捅重置孔约 5 秒<br>等待指示灯变成橙色</div>
        </div>
        <div class="sep" style="background:rgba(255,255,255,.18)"></div>
        <div style="display:flex;align-items:center;gap:12px">
          <span style="font-size:15px;flex:1">指示灯已变成橙色</span>
          <span class="sw on"></span>
        </div>
      </div>
    </div>

    <div style="padding:0 14px">
      <div class="dpanel">
        <div class="dhead">配网步骤</div>
        ${[['1','重置网关','长捅 5 秒，灯变橙','ok'],
           ['2','连接 WiFi','输入家里 2.4G 的密码',''],
           ['3','添加到 App','给网关起个名字','']].map(([n,t,s,c])=>`
          <div class="drow72">
            <div style="width:32px;height:32px;border-radius:50%;
              background:${c==='ok'?'rgba(48,209,88,.16)':'rgba(255,255,255,.06)'};
              color:${c==='ok'?'#30D158':'var(--text-tert)'};
              display:flex;align-items:center;justify-content:center;
              font-size:14px;font-weight:600;flex:0 0 auto">${c==='ok'?'✓':n}</div>
            <div class="dl"><div class="dt">${t}</div><div class="ds">${s}</div></div>
          </div>`).join('')}
      </div>

      <div class="empty" style="padding:36px 20px">
        <div class="ic">📡</div>
        <div class="t" style="font-size:17px">还没有添加网关</div>
        <div class="s">先在上方重置网关并勾选指示灯状态，再回来配网</div>
      </div>
    </div>
  </div>
  <div class="tabbar">
    <a class="tab" href="01-home.html">${L.ICONS.home}<span>门厅</span></a>
    <a class="tab" href="02-keys.html">${L.ICONS.key}<span>钥匙</span></a>
    <a class="tab on" href="03-devices.html">${L.ICONS.device}<span>设备</span></a>
    <a class="tab" href="04-members.html">${L.ICONS.people}<span>成员</span></a>
    <a class="tab" href="05-system.html">${L.ICONS.gear}<span>系统</span></a>
  </div>
</div></div><script src="interact.js"></script></body></html>`);

*/
// ══ 24 蓝牙钥匙串 —— A 画廊流 ══
// [已移交给 gen-dongle-gw.js] fs.writeFileSync(D+'24-dongles.html', L.page('蓝牙钥匙串', `
/* ... 省略 ...

  <div class="gallery-hero" style="background:linear-gradient(180deg,#5E5CE6 0%,#3C489C 40%,#1C1C1E 100%)">
    <div class="gt">随身开门</div>
    <div class="gm">
      <div style="width:88px;height:88px;border-radius:50%;
        background:radial-gradient(circle at 35% 30%,rgba(255,255,255,.35),transparent 60%),
                   rgba(255,255,255,.14);
        display:flex;align-items:center;justify-content:center;font-size:40px;
        box-shadow:0 0 56px rgba(94,92,230,.7)">🔑</div>
    </div>
    <div class="gd">钥匙串靠近门锁即可开门，不用掏手机</div>
  </div>

  <div class="h1" style="margin-top:20px">钥匙串</div>
  <div class="sub">上电后点下方按钮搜索</div>

  <div class="duo" style="margin-top:20px">
    ${gcard('搜索', `<div style="width:64px;height:64px;border-radius:50%;background:rgba(94,92,230,.20);
      display:flex;align-items:center;justify-content:center;font-size:28px">📡</div>`, '找附近的钥匙串')}
    ${gcard('已配对', `<div style="width:64px;height:64px;border-radius:50%;background:rgba(48,209,88,.16);
      display:flex;align-items:center;justify-content:center;font-size:28px">0</div>`, '暂无')}
  </div>

  <div class="empty" style="padding:32px 20px">
    <div class="ic">🔑</div>
    <div class="t" style="font-size:17px">还没有钥匙串</div>
    <div class="s">上电后点「搜索钥匙串」即可添加</div>
    <button class="btn" style="margin-top:20px;width:auto;padding:0 32px">搜索钥匙串</button>
  </div>
`, 2, {nav:true, back:'03-devices'}));

*/
console.log('✓ 13 / 22 / 23 / 24 补完');
