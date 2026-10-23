'use strict';
// 13 密码详情 / 15 添加密码 —— 拆开两个不同的页面
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 13 密码详情（点一把钥匙进去看）══
fs.writeFileSync(D+'13-key-detail.html', L.page('密码详情', `
  <div class="h1" style="margin-top:8px">朕-大门-长期</div>
  <div class="sub">密码 · 长期有效 · 归属朕</div>

  <!-- 码值主角卡（大字号显示）-->
  <div class="card" style="margin-top:24px;text-align:center;padding:26px 20px">
    <div class="cardlink" style="text-align:left">码值<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:44px;font-weight:700;letter-spacing:8px;line-height:1;
      font-variant-numeric:tabular-nums;color:#FFF;margin:16px 0 6px">483 921</div>
    <div style="font-size:12px;color:#8D8D93">轻点复制 · 复制后 60 秒自动清除</div>
    <div class="sep" style="margin-top:20px"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">锁内编号</div><div class="cvalue">#12</div></div>
      <div><div class="clabel" style="margin-top:0">指纹位</div><div class="cvalue">—</div></div>
    </div>
  </div>

  <!-- 归属与授权 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">归属与授权<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="32-member-detail.html">
      <div style="width:36px;height:36px;border-radius:50%;background:#7B7BE81F;
        border:2px solid #7B7BE8;display:flex;align-items:center;justify-content:center;
        font-size:16px;color:#7B7BE8;font-weight:600;flex:0 0 auto">朕</div>
      <div class="tx"><div class="tt">朕</div><div class="sb">管理员 · 2026-03-12 创建</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('clock')}</div>
      <div class="tx"><div class="tt">有效期</div><div class="sb">长期 — 不过期</div></div>
    </div>
  </div>

  <!-- 使用记录 -->
  <div class="card">
    <div class="cardlink">使用记录<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:12px;margin-top:10px">
      ${[['今天 07:12','开门成功'],['昨天 21:40','开门成功'],['10-21 18:22','开门成功']].map(([t,r])=>
        `<div style="display:flex;justify-content:space-between;font-size:14px">
          <span>${t}</span><span style="color:#30D158">${r}</span></div>`).join('')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">本月使用</div><div class="cvalue">23 次</div></div>
      <div><div class="clabel" style="margin-top:0">最后使用</div><div class="cvalue">今天</div></div>
    </div>
    <div class="footer">每次使用都会进审计流水，可以按这个密码筛。</div>
  </div>

  <!-- 操作 -->
  <div class="card">
    <button class="btn sec">改个名字</button>
    <button class="btn sec" style="margin-top:10px">改有效期</button>
    <button class="btn dgr" style="margin-top:10px">删除这项钥匙</button>
    <div class="footer">删除撤销命令会排队等待门锁连接，断网也不会丢。</div>
  </div>
`, 1, {nav:true, back:'10-keys-manage', right:'编辑'}));

// ══ 15 添加密码（AddKeyPage 的真实内容）══
fs.writeFileSync(D+'15-add-key.html', L.page('添加密码', `
  <div class="h1" style="margin-top:8px">添加密码</div>
  <div class="sub">6~8 位数字 · 写入门锁</div>

  <div class="card" style="margin-top:24px">
    <div class="cardlink">密码库存<span class="ch">${sv('chevron')}</span></div>
    <div class="ctitle">还可录 1 条</div>
    <div class="clabel">锁内已用</div>
    <div class="cvalue" style="font-size:19px;font-weight:700">63 / 64</div>
    <div class="footer">密码库存已满时，新增前要先删一条。临时码也占这个池子。</div>
  </div>

  <!-- 数字大字盘（源码：48pt 等宽大字，未填位是空心方框）-->
  <div class="card">
    <div class="cardlink">密码<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;gap:8px;justify-content:center;margin:20px 0 8px">
      ${[1,2,3,4,5,6].map(i => `<div style="width:40px;height:52px;border-radius:9px;
        background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.10);
        display:flex;align-items:center;justify-content:center;
        font-size:24px;font-weight:600;font-variant-numeric:tabular-nums;
        color:${i<=3?'#FFF':'rgba(255,255,255,.20)'}">${i<=3?['4','8','3'][i-1]:''}</div>`).join('')}
    </div>
    <div style="text-align:center;font-size:12px;color:#8D8D93">6~8 位纯数字</div>
    <div style="display:flex;gap:10px;margin-top:16px">
      <button class="btn sec" style="flex:1">生成随机码</button>
      <button class="btn sec" style="flex:1">粘贴</button>
    </div>
    <div class="footer">逐位回显。相同码值会被拦截，避免两把锁用同一个密码。</div>
  </div>

  <div class="card">
    <div class="cardlink">有效期<span class="ch">${sv('chevron')}</span></div>
    <div class="segctl2" style="margin-top:12px">
      <div class="o on">长期</div><div class="o">7 天</div><div class="o">30 天</div><div class="o">自定义</div>
    </div>
  </div>

  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">归属<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="30-members-list.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('person')}</div>
      <div class="tx"><div class="tt">未归属</div><div class="sb">备注自动填命名模板</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <div class="card">
    <button class="btn" style="background:#5E5CE6;color:#FFF">添加密码</button>
    <button class="btn sec" style="margin-top:10px">下发 10 分钟临时密码</button>
    <div class="footer">点了没反应 —— 请先选择门锁。</div>
  </div>
`, 1, {nav:true, back:'10-keys-manage'}));

console.log('✓ 13 密码详情 / 15 添加密码 已拆分');
