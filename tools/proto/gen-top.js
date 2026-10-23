'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;
const row = (href, icon, name, sub, tone, badge) => `<a class="rw" href="${href}">
  <div class="ic" style="background:${tone}22;color:${tone}">${sv(icon)}</div>
  <div class="tx"><div class="tt">${name}</div><div class="sb">${sub}</div></div>
  ${badge||''}<div class="ch">${sv('chevron')}</div></a>`;

fs.writeFileSync(D+'05-system.html', L.page('系统', `
  <div class="chiprow">
    <div class="chip compact">${L.ring([['#FF9F0A',.4]])}</div>
    <div class="chip">${L.ring([['#FF9F0A',.3]])}<div><div class="lbl">应用锁</div><div class="val">未开启</div></div></div>
    <div class="chip">${L.ring([['#F11B51',.1]])}<div><div class="lbl">备份</div><div class="val">从未</div></div></div>
    <div class="chip">${L.ring([['#3CDE02',.6]])}<div><div class="lbl">门锁</div><div class="val">1 把</div></div></div>
  </div>

  <div style="margin-top:28px">
    <div class="h1">系统</div>
    <div class="sub">应用锁、审计与备份都在这台手机上 · 全程离线</div>
  </div>

  <!-- 图 5 的 MetricCard 形态：44px 大数字当主角 + 环 + 三列读数 -->
  <div class="card grad-hero" style="margin-top:26px;padding:22px 20px">
    <div style="display:flex;align-items:flex-start;gap:16px">
      <div style="flex:1">
        <div style="font-size:13px;color:rgba(255,255,255,.74)">待处理项目</div>
        <div style="font-size:44px;font-weight:700;line-height:1;margin-top:8px;font-variant-numeric:tabular-nums;letter-spacing:-1.2px">2</div>
        <div style="font-size:12px;color:rgba(255,255,255,.66);margin-top:8px;line-height:1.5">应用锁未开启 · 从未备份</div>
      </div>
      <svg width="84" height="84" viewBox="0 0 84 84" style="flex:0 0 auto">
        <circle cx="42" cy="42" r="34.36" fill="none" stroke="rgba(255,255,255,.16)" stroke-width="6.68"/>
        <circle cx="42" cy="42" r="34.36" fill="none" stroke="#FFA31A" stroke-width="6.68" stroke-linecap="round" stroke-dasharray="43.15 215.91" transform="rotate(-90 42 42)"/>
        <circle cx="42" cy="42" r="22.91" fill="rgba(0,0,0,.24)"/>
        <text x="42" y="42" text-anchor="middle" dominant-baseline="central"
          font-size="16.15" font-weight="700" fill="#FFF" font-family="system-ui,-apple-system">2/6</text>
      </svg>
    </div>
    <div style="height:1px;background:rgba(255,255,255,.16);margin:18px 0 16px"></div>
    <div style="display:flex">
      <div style="text-align:center;flex:1">
        <div style="font-size:15px;font-weight:600;color:#FFF">无风险</div>
        <div style="font-size:11px;color:rgba(255,255,255,.60);margin-top:3px">钥匙</div>
      </div>
      <div style="text-align:center;flex:1;border-left:1px solid rgba(255,255,255,.12)">
        <div style="font-size:15px;font-weight:600;color:#FFF">完整</div>
        <div style="font-size:11px;color:rgba(255,255,255,.60);margin-top:3px">审计链</div>
      </div>
      <div style="text-align:center;flex:1;border-left:1px solid rgba(255,255,255,.12)">
        <div style="font-size:15px;font-weight:600;color:#FFF">正常</div>
        <div style="font-size:11px;color:rgba(255,255,255,.60);margin-top:3px">数据</div>
      </div>
    </div>
  </div>

  <div class="card" style="padding:6px 0">
    ${row('41-applock','lock','应用锁','未开启 · 现在设置','#FF9F0A')}
    <div class="sep"></div>
    ${row('42-peek','eye','防窥与遮蔽','后台即糊 / 限时可见 / 水印','#0ADBD8')}
    <div class="sep"></div>
    ${row('44-audit','list','审计日志','谁在什么时候做了什么','#0090FC')}
    <div class="sep"></div>
    ${row('45-destroy','trash','彻底销毁','不可恢复','#FF3B30')}
  </div>

  <div class="card">
    <div class="cardlink">备份恢复<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:16px">
      <div style="flex:1">
        <div class="ctitle">从未备份</div>
        <div class="clabel">上次导出</div>
        <div class="cvalue">—</div>
      </div>
      ${L.donut(88,[['#FF9F0A',0.04]],'!')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">本机门锁</div><div class="cvalue">1 把</div></div>
      <div><div class="clabel" style="margin-top:0">钥匙总数</div><div class="cvalue">13</div></div>
    </div>
    <div class="footer">备份包含全部钥匙与设置，全程离线加密。AES-128-CBC + HMAC-SHA256。</div>
  </div>

  <div class="card" style="padding:6px 0">
    ${row('49-appearance','star','外观工作室','强调色 / 对比度 / 周起始','#E8A05C')}
    <div class="sep"></div>
    ${row('48-export','export','导出中心','PDF / CSV / 分享','#8D8D93')}
    <div class="sep"></div>
    ${row('4a-me','gear','本机设置','应用锁 / 备份 / 关于','#8D8D93')}
  </div>
`, 4));

console.log('✓ 05-system 已改为可重建');
