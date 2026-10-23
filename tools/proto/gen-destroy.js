'use strict';
// 45-destroy —— 按 SecurityDestroyView 源码结构重建 7 个区块
// 源码区块：备份闸 / 三级销毁 / 回收站 / 离职清除 / 安全模式 / 口令复用 / 密码保存 / 逐项状态
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs.writeFileSync(D+'45-destroy.html', L.page('销毁与应急', `
  <div class="h1" style="margin-top:8px">销毁与应急</div>
  <div class="sub">不可逆操作 · 需要二次确认</div>

  <!-- 备份闸 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">备份闸<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;gap:10px;padding:12px;border-radius:12px;
      background:rgba(255,59,48,.10);margin-top:12px">
      <span style="color:#FF3B30;width:18px;height:18px;flex:0 0 auto">${sv('warn')}</span>
      <div style="flex:1;font-size:12px;color:#FF3B30;line-height:1.5">
        7 天内无备份 — 触发销毁将先跳导出向导（接线点：设置 → 备份）
      </div>
    </div>
  </div>

  <!-- 三级销毁 -->
  <div class="card">
    <div class="cardlink">三级销毁<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;gap:8px;margin-top:14px">
      ${[['一级','删缓存','#FF9F0A',1],['二级','覆写台账','#FF694E',1],['三级','全盘覆写','#FF3B30',1]].map(([t,d,c,on])=>
        `<div style="flex:1;text-align:center">
          <div style="height:5px;border-radius:3px;background:${on?c:'rgba(255,255,255,.10)'};margin-bottom:10px"></div>
          <div style="font-size:13px;font-weight:600;color:${on?c:'#6A6A6E'}">${t}</div>
          <div style="font-size:11px;color:#6A6A6E;margin-top:3px">${d}</div>
        </div>`).join('')}
    </div>
    <div class="sep"></div>
    <div style="display:flex;align-items:center;gap:12px">
      <span style="font-size:15px;flex:1">我理解销毁不可恢复</span><span class="sw"></span>
    </div>
    <div style="font-size:12px;color:#8D8D93;margin-top:8px;line-height:1.5">
      删除+随机覆写全部本地缓存（钥匙串/台账/日志/审计）
    </div>
    <button class="btn dgr" style="margin-top:14px;background:#FF3B30;color:#FFF">销毁全部数据</button>
  </div>

  <!-- 回收站 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 6px">回收站<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="82-bin.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('refresh')}</div>
      <div class="tx"><div class="tt">查看回收站（可恢复）</div><div class="sb">0 项</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <div style="padding:14px 20px">
      <button class="btn sec" data-hold>按住清空回收站</button>
      <div style="text-align:center;font-size:11px;color:#6A6A6E;margin-top:8px">长按 2 秒释放，松手取消</div>
    </div>
  </div>

  <!-- 离职清除 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 6px">离职清除<span class="ch">${sv('chevron')}</span></div>
    ${[['爱妃','#E8A05C'],['母上','#0ADBD8'],['父上','#FF3B30'],['朕','#7B7BE8'],['皇子','#30D158']].map(([n,c],i)=>
      `${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="88-exit.html">
        <div class="ic" style="background:transparent;color:#8D8D93">${sv('person')}</div>
        <div class="tx"><div class="tt">${n}</div><div class="sb">名下钥匙入归档，记录保留并标「已离开」</div></div>
        <span style="font-size:13px;color:#FF3B30;font-weight:600">清除</span></a>`).join('')}
  </div>

  <!-- 安全模式 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 6px">安全模式<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="46-safemode.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('shieldCheck')}</div>
      <div class="tx"><div class="tt">A / B 模式说明</div><div class="sb">本 App 只给变严方向（A→B）</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <!-- 口令复用 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 6px">口令复用<span class="ch">${sv('chevron')}</span></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('lock')}</div>
      <div class="tx"><div class="tt">检测重复口令</div><div class="sb">没有发现弱口令或重复</div></div>
      <span style="font-size:13px;color:#30D158">通过</span>
    </div>
  </div>

  <!-- 密码保存 -->
  <div class="card">
    <div class="cardlink">密码保存<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="font-size:15px;flex:1">保存到系统钥匙串</span><span class="sw"></span>
    </div>
    <div class="footer">打开后口令会存进 iCloud 钥匙串。关掉只存本机。</div>
  </div>

  <!-- 敏感操作视图 -->
  <div class="card">
    <div class="cardlink">敏感操作视图<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="font-size:15px;flex:1">销毁前需重输应用锁密码</span><span class="sw on"></span>
    </div>
    <div class="sep"></div>
    <div style="display:flex;align-items:center;gap:12px">
      <span style="font-size:15px;flex:1">需键入「销毁」二字</span><span class="sw on"></span>
    </div>
  </div>
`, 4, {nav:true, back:'40-security'}));

console.log('✓ 45-destroy 按源码 8 区块重建');
