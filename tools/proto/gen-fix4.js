'use strict';
// 10 / 13 / 40 / 60 —— 严格按源码区块结构重做
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 10 钥匙管理（KeysPage：expiringCard / segmentBar / credentialCard / emptyCard）══
fs.writeFileSync(D+'10-keys-manage.html', L.page('钥匙管理', `
  <div class="h1" style="margin-top:8px">钥匙管理</div>
  <div class="sub">13 项 · 密码 11 / 指纹 2 / 临时码 0</div>

  <!-- 图 2 的卡解剖：库存分布（彩色数据行 + 三环）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">库存分布<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:2px">
      <div style="flex:1">
        <div class="ctitle">13 项凭证</div>
        <div style="margin-top:14px">
          <div class="drow"><span class="dot" style="background:#F11B51"></span>
            <span class="dv">11<span class="du"> 密码</span></span></div>
          <div class="drow"><span class="dot" style="background:#3CDE02"></span>
            <span class="dv">2<span class="du"> 指纹</span></span></div>
          <div class="drow"><span class="dot" style="background:#0ADBD8"></span>
            <span class="dv">0<span class="du"> 临时码</span></span></div>
        </div>
      </div>
      ${L.tripleRing(100, .85, .15, .0, '13')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">本周新增</div><div class="cvalue">2 项</div></div>
      <div><div class="clabel" style="margin-top:0">即将到期</div><div class="cvalue">2 项</div></div>
    </div>
    <div class="footer">到期前 7 天会在门厅提示。临时码用完即弃，不进台账。</div>
  </div>

  <!-- 即将到期：每条显示真实剩余天数 -->
  <div class="card">
    <div class="cardlink">即将到期<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:10px">
      ${[['密码 #皇子-临时','10-25 失效','#FF694E','2'],['密码 #访客','10-28 失效','#FF9F0A','5']].map(([n,d,c,days])=>
        `<div style="display:flex;align-items:center;gap:11px">
          <span style="width:6px;height:6px;border-radius:50%;background:${c};flex:0 0 auto"></span>
          <div style="flex:1">
            <div style="font-size:15px;color:#FFF">${n}</div>
            <div style="font-size:12px;color:#8A8A90;margin-top:2px">${d}</div>
          </div>
          <span style="font-size:13px;font-weight:600;color:${c}">${days} 天</span>
        </div>`).join('')}
    </div>
    <div class="footer">到期后自动失效，不会写进门锁。</div>
  </div>

  <!-- 分段控件（带外边距，不贴卡）-->
  <div style="display:flex;margin-top:16px">
    <div class="segctl" style="flex:1">
      <div class="o on">全部</div><div class="o">密码</div><div class="o">指纹</div><div class="o">临时码</div>
    </div>
  </div>

  <div class="card" style="margin-top:14px;padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">密码<span class="ch">${sv('chevron')}</span></div>
    ${[['朕-大门-长期','朕 · 长期有效','进行中','blue'],
       ['密码 #皇子-临时','皇子 · 2 天后失效','即将失效','warn'],
       ['密码 #访客','访客 · 5 天后失效','即将失效','warn']].map(([n,s2,b,cls],i)=>
      `${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="13-key-detail.html">
        <div class="ic" style="color:#8D8D93">${sv('key')}</div>
        <div class="tx"><div class="tt">${n}</div><div class="sb">${s2}</div></div>
        <span class="badge ${cls}">${b}</span>
        <div class="ch">${sv('chevron')}</div></a>`).join('')}
  </div>

  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">指纹<span class="ch">${sv('chevron')}</span></div>
    ${[['指纹 12','母上 · 09-01 录入','有效'],
       ['指纹 11','母上 · 09-01 录入','有效']].map(([n,s2,b],i)=>
      `${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="13-key-detail.html">
        <div class="ic" style="color:#8D8D93">${sv('fingerprint')}</div>
        <div class="tx"><div class="tt">${n}</div><div class="sb">${s2}</div></div>
        <span class="badge ok">${b}</span>
        <div class="ch">${sv('chevron')}</div></a>`).join('')}
    <div class="footer" style="padding:12px 20px 0;margin-top:0">
      删除撤销命令会排队等待门锁连接，断网也不会丢。
    </div>
  </div>

  <a class="btn" href="15-add-key.html" style="margin-top:4px;display:block;text-align:center;text-decoration:none">添加钥匙</a>
`, 1, {nav:true, back:'02-keys', right:'+'}));

// ══ 13 添加密码（AddKeyPage：capacity / password / validity / owner / action）══
fs.writeFileSync(D+'13-key-detail.html', L.page('添加密码', `
  <div class="h1" style="margin-top:8px">添加密码</div>
  <div class="sub">6~8 位数字 · 写入门锁</div>

  <!-- capacityCard -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">密码库存<span class="ch">${sv('chevron')}</span></div>
    <div class="ctitle">还可录 1 条</div>
    <div class="clabel">锁内已用</div>
    <div class="cvalue" style="font-size:19px;font-weight:700">63 / 64</div>
    <div class="footer">密码库存已满时，新增前要先删一条。临时码也占这个池子。</div>
  </div>

  <!-- passwordStage -->
  <div class="card">
    <div class="cardlink">密码<span class="ch">${sv('chevron')}</span></div>
    <div style="text-align:center;padding:16px 0 8px">
      <div style="font-size:40px;font-weight:700;letter-spacing:12px;line-height:1;
        font-variant-numeric:tabular-nums;color:#5E5CE6">••••••</div>
      <div style="font-size:12px;color:#8D8D93;margin-top:14px">输入码值，或点「生成」</div>
    </div>
    <div style="display:flex;gap:10px">
      <button class="btn sec" style="flex:1">生成随机码</button>
      <button class="btn sec" style="flex:1">粘贴</button>
    </div>
    <div class="footer">密码够长（6 位以上）才能写入。逐位回显，重复会被拦截。</div>
  </div>

  <!-- validitySection -->
  <div class="card">
    <div class="cardlink">有效期<span class="ch">${sv('chevron')}</span></div>
    <div class="segctl2" style="margin-top:12px">
      <div class="o on">长期</div><div class="o">7 天</div><div class="o">30 天</div><div class="o">自定义</div>
    </div>
  </div>

  <!-- ownerSection -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">归属<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="30-members-list.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('person')}</div>
      <div class="tx"><div class="tt">未归属</div><div class="sb">备注自动填命名模板</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <!-- actionSection -->
  <div class="card">
    <button class="btn" style="background:#5E5CE6;color:#FFF">添加密码</button>
    <button class="btn sec" style="margin-top:10px">下发 10 分钟临时密码</button>
    <div class="footer">点了没反应 —— 请先选择门锁。</div>
  </div>
`, 1, {nav:true, back:'10-keys-manage'}));

// ══ 40 本机保护（SecurityPage：status / risk / actions）══
fs.writeFileSync(D+'40-security.html', L.page('本机保护', `
  <div class="h1" style="margin-top:8px">本机保护</div>
  <div class="sub">现在安全吗 · 有没有事 · 有哪些功能</div>

  <!-- statusCard：图 5 的 MetricCard 形态 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">现在安全吗<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:4px">
      <div style="flex:1">
        <div style="font-size:44px;font-weight:700;line-height:1;color:#2FD65C;
          font-variant-numeric:tabular-nums;letter-spacing:-1.2px">0</div>
        <div style="font-size:15px;font-weight:600;color:#FFF;margin-top:8px">项风险</div>
        <div style="font-size:12px;color:#8A8A90;margin-top:5px">数据解析正常 · 审计链完整</div>
      </div>
      <svg width="80" height="80" viewBox="0 0 80 80" style="flex:0 0 auto">
        <circle cx="40" cy="40" r="32" fill="none" stroke="rgba(47,214,92,.16)" stroke-width="6"/>
        <circle cx="40" cy="40" r="32" fill="none" stroke="#2FD65C" stroke-width="6"
          stroke-linecap="round" stroke-dasharray="201 201" transform="rotate(-90 40 40)"/>
        <path d="M28 40l8 8 16-16" fill="none" stroke="#2FD65C" stroke-width="3.5"
          stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">钥匙</div><div class="cvalue" style="color:#30D158">无风险</div></div>
      <div><div class="clabel" style="margin-top:0">审计链</div><div class="cvalue" style="color:#30D158">完整</div></div>
      <div><div class="clabel" style="margin-top:0">数据</div><div class="cvalue" style="color:#30D158">正常</div></div>
    </div>
  </div>

  <!-- riskCard -->
  <div class="card">
    <div class="cardlink">有没有事<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:12px;margin-top:10px">
      ${[['需要处理','应用锁未开启 · 从未备份','#FF9F0A'],
         ['弱口令','没有弱口令','#30D158']].map(([t,d,c])=>
        `<div style="display:flex;align-items:center;gap:10px">
          <span style="width:7px;height:7px;border-radius:50%;background:${c};flex:0 0 auto"></span>
          <div style="flex:1"><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:2px">${d}</div></div>
        </div>`).join('')}
    </div>
  </div>

  <!-- actionsCard -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">有哪些功能<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="41-applock.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('lock')}</div>
      <div class="tx"><div class="tt">应用锁</div><div class="sb">未开启 · 现在设置</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="42-peek.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('eye')}</div>
      <div class="tx"><div class="tt">防窥与遮蔽</div><div class="sb">后台即糊 / 限时可见 / 水印</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="44-audit.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('list')}</div>
      <div class="tx"><div class="tt">审计日志</div><div class="sb">谁在什么时候做了什么</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="45-destroy.html">
      <div class="ic" style="background:transparent;color:#FF3B30">${sv('trash')}</div>
      <div class="tx"><div class="tt" style="color:#FF3B30">彻底销毁</div><div class="sb">不可恢复</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="footer">本机已经被锁住时，这一页仍然可读 —— 只是不能改。</div>
  </div>
`, 4, {nav:true, back:'05-system'}));

// ══ 60 维护与保养（CarePage：period / todo / history）══
fs.writeFileSync(D+'60-care.html', L.page('维护与保养', `
  <div class="h1" style="margin-top:8px">维护与保养</div>
  <div class="sub">机械件也该有保养记录</div>

  <!-- periodCard（还剩多少 / 保养周期）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">还剩多少<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      <div style="flex:1">
        <div class="ctitle">保养周期尚未记录</div>
        <div class="clabel" style="margin-top:14px">状态</div>
        <div class="cvalue" style="color:#FF9F0A">未记录</div>
      </div>
      <div style="position:relative;width:101px;height:101px;flex:0 0 auto">
        <svg width="101" height="101" viewBox="0 0 101 101">
          <circle cx="50.5" cy="50.5" r="43.5" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="11"/>
          <circle cx="50.5" cy="50.5" r="43.5" fill="none" stroke="#5E5CE6" stroke-width="11"
            stroke-linecap="round" stroke-dasharray="6 273" transform="rotate(-90 50.5 50.5)"/>
          <circle cx="50.5" cy="50.5" r="22" fill="#0A0A0C"/>
        </svg>
        <div style="position:absolute;inset:0;display:flex;flex-direction:column;
          align-items:center;justify-content:center">
          <div style="font-size:20px;font-weight:700;color:#FFF;line-height:1">—</div>
          <div style="font-size:10px;color:#8D8D93;margin-top:3px">天</div>
        </div>
      </div>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">上次保养</div><div class="cvalue">—</div></div>
      <div><div class="clabel" style="margin-top:0">下次保养</div><div class="cvalue">—</div></div>
    </div>
    <button class="btn" style="margin-top:14px;background:#5E5CE6;color:#FFF">记录本次保养</button>
    <div class="footer">记录一次保养，之后会按周期提醒。</div>
  </div>

  <!-- todoCard -->
  <div class="card">
    <div class="cardlink">该做的<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:10px">
      ${[['换电池','电量 47%，建议尽快更换','#30D158','ok'],
         ['清洁锁体','距上次 92 天，建议每 90 天清一次','#FF9F0A','warn'],
         ['年度电池体检','已设为每年 11-01','#8D8D93','']].map(([t,d,c])=>
        `<div style="display:flex;gap:12px">
          <span style="width:7px;height:7px;border-radius:50%;background:${c};margin-top:7px;flex:0 0 auto"></span>
          <div style="flex:1"><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:3px">${d}</div></div>
        </div>`).join('')}
    </div>
  </div>

  <!-- historyRow -->
  <div class="card" style="padding:6px 0">
    <a class="rw" href="86-checklist.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('check')}</div>
      <div class="tx"><div class="tt">锁体保养</div><div class="sb">五项清单</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="85-battery.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('battery')}</div>
      <div class="tx"><div class="tt">换电指引</div><div class="sb">四步换电 · 记录一次</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="60-care.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('clock')}</div>
      <div class="tx"><div class="tt">保养历史</div><div class="sb">查看做过的保养记录</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>
`, 4, {nav:true, back:'4a-me'}));

console.log('✓ 10 / 13 / 40 / 60 按源码区块重做');
