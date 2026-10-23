'use strict';
// 补齐 9 个源码里有、HTML 缺的页面
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 81 备份工作室（BackupStudioView）══
fs.writeFileSync(D+'81-backup-studio.html', L.page('备份工作室', `
  <div class="h1" style="margin-top:8px">备份工作室</div>
  <div class="sub">数据只存在这台 iPhone</div>

  <div class="card" style="margin-top:24px">
    <div class="cardlink">状态<span class="ch">${sv('chevron')}</span></div>
    <div class="cols" style="margin-top:6px">
      <div><div class="clabel" style="margin-top:0">上次导出</div><div class="cvalue">—</div>
        <div class="csub">从未</div></div>
      <div><div class="clabel" style="margin-top:0">上次导入</div><div class="cvalue">—</div>
        <div class="csub">从未</div></div>
    </div>
    <div class="sep"></div>
    <div style="font-size:12px;color:#8D8D93;line-height:1.6">
      撤销本次恢复会回到恢复前自动打的快照。只回写快照里已有的内容，恢复后新建的东西不会被动。
    </div>
    <button class="btn sec" style="margin-top:12px">撤销本次恢复（24h 内）</button>
  </div>

  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">三个向导<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="47-backup.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('doc')}</div>
      <div class="tx"><div class="tt">立即备份</div><div class="sb">生成一份完整备份</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="48-export.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('export')}</div>
      <div class="tx"><div class="tt">导出向导</div><div class="sb">分区勾选 · 口令 · 自描述命名 · 二维码搬运</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="47-backup.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('refresh')}</div>
      <div class="tx"><div class="tt">恢复向导</div><div class="sb">从文件或备份文本恢复</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>
`, 4, {nav:true, back:'47-backup'}));

// ══ 82 回收站（CredentialBinView）══
// [已移交给 gen-fill-sections.js] fs.writeFileSync(D+'82-bin.html', L.page('回收站', `
/* ... 省略 ...

  <div class="h1" style="margin-top:8px">回收站</div>
  <div class="sub">删掉的钥匙在这里，可以恢复</div>

  <div class="card" style="margin-top:24px">
    <div class="empty-state" style="padding:36px 0">
      <div class="es-icon">${sv('trash','28px')}</div>
      <div class="es-title">回收站是空的</div>
      <div class="es-desc">删掉的钥匙会先放这里<br>刚删完就后悔还能捞回来</div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">下发状态<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:10px">
      ${[['等待门锁确认','最近 5 分钟内刚发生过下发','#FF9F0A'],
         ['等待连接门锁后发出','断网时排队的撤销指令','#0090FC']].map(([t,d,c])=>
        `<div style="display:flex;gap:12px">
          <span style="width:7px;height:7px;border-radius:50%;background:${c};margin-top:6px;flex:0 0 auto"></span>
          <div style="flex:1"><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:3px">${d}</div></div>
        </div>`).join('')}
    </div>
    <div class="footer">撤销命令会排队等待门锁连接，断网也不会丢。有写无读 —— 到底发出去没有，要等门锁确认。</div>
  </div>
`, 4, {nav:true, back:'10-keys-manage'}));

*/
// ══ 83 钥匙工坊（StudioPage：四个工作台入口）══
fs.writeFileSync(D+'83-studio.html', L.page('钥匙工坊', `
  <div class="h1" style="margin-top:8px">钥匙工坊</div>
  <div class="sub">密码 / 临时码 / 指纹 / OTP</div>

  <div class="card" style="margin-top:24px;padding:6px 0">
    ${[
      ['13-key-detail','key','密码','逐位回显 · 重复拦截','#5E5CE6'],
      ['12-tempcode','timer','临时码','五场景 · 重叠检测 · 装修黄条 · 批量下发','#FF694E'],
      ['11-fingerprint','fingerprint','指纹','归属先行 · 沉浸录入 · 删除双签','#0ADBD8'],
      ['14-otp','shieldCheck','OTP 与口令','时窗细条 · otpauth · 静态备份码','#0090FC'],
    ].map(([href,ic,title,sub,c],i)=>
      `${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="${href}.html" style="min-height:72px">
        <div class="ic" style="background:transparent;color:${c}">${sv(ic,'22px')}</div>
        <div class="tx"><div class="tt">${title}</div><div class="sb">${sub}</div></div>
        <div class="ch">${sv('chevron')}</div></a>`).join('')}
  </div>
  <div class="footer" style="padding:0 20px">四类凭证各有自己的录入规则。密码和临时码共用一个库存池。</div>
`, 1, {nav:true, back:'02-keys'}));

// ══ 84 诊断与自检（DiagnosticsPage）══
// [已移交给 gen-fill-sections.js] fs.writeFileSync(D+'84-diagnostics.html', L.page('诊断与自检', `
/* ... 省略 ...

  <div class="h1" style="margin-top:8px">诊断与自检</div>
  <div class="sub">进入时算一次，动作后重算</div>

  <div class="card" style="margin-top:24px">
    <div class="cardlink">数据健康<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="color:#30D158;width:20px;height:20px">${sv('check')}</span>
      <div style="flex:1"><div style="font-size:16px">没有发现数据问题</div>
      <div style="font-size:12px;color:#8D8D93;margin-top:3px">数据键都能解析，也没有孤立文件或日志断档</div></div>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">孤儿数据</div><div class="cvalue">0</div></div>
      <div><div class="clabel" style="margin-top:0">日志断档</div><div class="cvalue">0</div></div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">本机自检<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:10px">
      ${[['稳定性','最近有一次异常退出','#FF9F0A'],
         ['钥匙解析','13 项全部可读','#30D158'],
         ['备份完整性','从未备份','#FF9F0A']].map(([k,v,c])=>
        `<div style="display:flex;justify-content:space-between;align-items:center">
          <span style="font-size:15px">${k}</span>
          <span style="font-size:13px;color:${c}">${v}</span></div>`).join('')}
    </div>
  </div>

  <button class="btn sec" style="margin-top:4px">复制全部诊断信息</button>
  <div style="text-align:center;font-size:12px;color:#6A6A6E;margin-top:12px">已复制到剪贴板</div>
`, 4, {nav:true, back:'4a-me'}));

*/
console.log('✓ 补了 4 页：备份工作室 / 回收站 / 钥匙工坊 / 诊断与自检');
