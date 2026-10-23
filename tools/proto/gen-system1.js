'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';

// ── 40 隐私看板 ──
// [已移交给 gen-fix4.js] fs.writeFileSync(D+'40-security.html', L.page('本机保护', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="font-size:28px">⚠️</div>
      <div><div style="font-size:19px;font-weight:700">有需要处理的项目</div>
      <div style="font-size:13px;color:rgba(255,255,255,.75);margin-top:4px">应用锁未开启 · 从未备份</div></div>
    </div>
    <div class="sep" style="background:rgba(255,255,255,.18)"></div>
    <div style="display:flex;justify-content:space-around;text-align:center">
      ${[['钥匙','无风险'],['审计链','完整'],['数据','正常']].map(([k,v])=>`
        <div><svg width="17" height="17" viewBox="0 0 17 17"><circle cx="8.5" cy="8.5" r="7" fill="#30D158"/></svg>
        <div style="font-size:12px;color:rgba(255,255,255,.72);margin-top:7px">${k}</div>
        <div style="font-size:12px;color:#30D158;margin-top:2px">${v}</div></div>`).join('')}
    </div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('41-applock','🔒','rgba(255,159,10,.16)','#FF9F0A','应用锁','未开启 · 现在设置')}
    <div class="sep"></div>
    ${L.row('42-peek','👁','rgba(10,219,216,.16)','#0ADBD8','防窥与遮蔽','后台即糊 / 限时可见 / 水印')}
    <div class="sep"></div>
    ${L.row('44-audit','📋','rgba(0,144,252,.16)','#0090FC','审计日志','谁在什么时候做了什么')}
    <div class="sep"></div>
    <a class="rw" href="45-destroy.html">
      <div class="ic" style="background:rgba(255,59,48,.17)">🗑</div>
      <div class="tx"><div class="tt" style="color:#FF3B30">彻底销毁</div><div class="sb">不可恢复</div></div>
      <div class="ch">›</div></a>
  </div>
`, 4, {nav:true, back:'05-system'}));

*/
// ── 41 应用锁 ──
// [已移交给 gen-fill3.js] fs.writeFileSync(D+'41-applock.html', L.page('应用锁', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="font-size:28px">🔓</div>
      <div><div style="font-size:19px;font-weight:700">应用锁未开启</div>
      <div style="font-size:13px;color:rgba(255,255,255,.75);margin-top:4px">现在谁拿起这台手机，都能直接看到你保存的密码</div></div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">设置口令<span class="ch">›</span></div>
    <input class="inp" style="margin-top:10px" placeholder="口令（至少 6 位）" type="password">
    <input class="inp" style="margin-top:10px" placeholder="再输一遍" type="password">
    <button class="btn" style="margin-top:14px;background:rgba(255,255,255,.10);color:#5A5A5E">启用应用锁</button>
    <div class="footer">我们只保存口令的一串校验值，不保存口令本身 —— 所以忘记后谁也找不回来，只能重装或从备份恢复。</div>
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">它保护什么</div>
    <div style="margin-top:14px;display:flex;flex-direction:column;gap:14px">
      ${[['要输口令才能打开 App；手机离手时别人看不到你的密码'],
         ['彻底销毁、离职清除这类动作，会要求你再输一次它'],
         ['口令的校验值会一起备份；换机恢复后仍然是同一个口令']].map(t=>
        `<div style="display:flex;gap:10px;font-size:14px;line-height:1.5">
          <span style="color:#30D158;flex:0 0 auto">✓</span><span style="color:var(--text-sub)">${t}</span></div>`).join('')}
    </div>
  </div>
`, 4, {nav:true, back:'05-system'}));

*/
// ── 42 防窥与遮蔽 ──
// [已移交给 gen-peek.js] fs.writeFileSync(D+'42-peek.html', L.page('防窥与遮蔽', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="font-size:22px">📋</div>
      <div style="flex:1"><div style="font-size:16px">剪贴板自动清除</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px">复制口令后 60 秒清除；只对口令与 OTP 生效</div></div>
      <span style="font-size:14px;color:#E8A05C">60 秒 ›</span>
    </div>
    <div class="footer">加密钥匙包与交接包不走这条：那是密文，且你要粘进聊天工具，定时清掉只会打断交接。</div>
  </div>

  <div class="card">
    <div class="cardlink">遮蔽样式<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;justify-content:space-between;margin-top:8px">
      <div><div style="font-size:16px">码值遮蔽样式</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px">圆点打码（••••）— 默认</div></div>
      <span style="font-size:14px;color:#E8A05C">圆点打码 ›</span>
    </div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('43-privacy-dash','🛡','rgba(0,144,252,.16)','#0090FC','隐私仪表盘','1 项防窥已启用')}
  </div>

  <div class="card">
    <div class="cardlink">背景与限时<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:10px">
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">切后台即糊</div>
        <div style="font-size:12px;color:var(--text-sub);margin-top:2px">关闭</div></div><span class="sw"></span></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">限时可见</div>
        <div style="font-size:12px;color:var(--text-sub);margin-top:2px">关</div></div>
        <span style="font-size:14px;color:#E8A05C">关 ›</span></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">磨砂挡片</div>
        <div style="font-size:12px;color:var(--text-sub);margin-top:2px">关闭</div></div><span class="sw"></span></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="flex:1"><div style="font-size:16px">分享遮半</div>
        <div style="font-size:12px;color:var(--text-sub);margin-top:2px">已开：码值在完成页与详情卡上默认遮半</div></div><span class="sw on"></span></div>
    </div>
  </div>
`, 4, {nav:true, back:'05-system'}));

*/
// ── 43 隐私仪表盘 ──
// [已移交给 gen-fill.js] fs.writeFileSync(D+'43-privacy-dash.html', L.page('隐私仪表盘', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="font-size:28px">🛡</div>
      <div><div style="font-size:17px;font-weight:700">已启用 1 / 5 项防窥</div>
      <div style="font-size:13px;color:rgba(255,255,255,.75);margin-top:4px">还有 4 项未开启，轻点下方对应一行即可补上。</div></div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">逐项状态（轻点即切换）<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;margin-top:6px">
      ${[['切后台即糊',false],['磨砂挡片',false],['分享遮半',true],['访客通道',false],['常驻水印',false]].map(([n,on],i)=>`
        ${i>0?'<div class="sep" style="margin:12px 0"></div>':''}
        <div style="display:flex;align-items:center;gap:12px;padding:8px 0">
          <div style="width:26px;height:26px;border-radius:50%;border:2px solid ${on?'#30D158':'rgba(255,255,255,.24)'};
            background:${on?'rgba(48,209,88,.16)':'transparent'};
            display:flex;align-items:center;justify-content:center;font-size:14px;color:#30D158">${on?'✓':''}</div>
          <span style="flex:1;font-size:16px">${n}</span>
          <span style="font-size:13px;color:${on?'#30D158':'var(--text-tert)'}">${on?'已启用':'未启用'}</span>
        </div>`).join('')}
    </div>
  </div>
`, 4, {nav:true, back:'42-peek'}));

*/
// ── 44 安全审计 ──
// [已移交给 gen-fill-sections.js] fs.writeFileSync(D+'44-audit.html', L.page('审计流水', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">双流水<span class="ch">›</span></div>
    <div class="segctl2" style="margin-top:10px">
      <div class="o on">管理操作 1</div><div class="o">开门事件 0</div>
    </div>
    <div style="display:flex;align-items:center;gap:10px;margin-top:16px;font-size:15px">
      <span style="color:#FF9F0A">⚙</span><span style="flex:1">改 · 然然家</span>
      <span style="color:var(--text-tert);font-size:13px;font-variant-numeric:tabular-nums">10-23 06:20</span>
      <span style="color:var(--text-tert)">⌄</span>
    </div>
  </div>

  <a class="btn sec" style="margin-top:0">＋ 记一条管理事件</a>

  <div class="card" style="margin-top:20px">
    <div class="cardlink">防篡改<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;gap:10px;margin-top:8px">
      <span style="color:#0090FC">✓</span><span style="font-size:16px;color:#0090FC">校验完整性</span>
    </div>
    <div class="footer">每条管理日志前附条 SHA-256，逐链重算验证；本地轻量口径，篡改即断链</div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('05-system','📅','rgba(255,255,255,.08)','#8D8D93','保留期','永久保留','<span style="font-size:14px;color:#E8A05C">永久 ›</span>')}
  </div>

  <div class="card">
    <div class="cardlink">脱敏导出<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:10px">
      <div style="display:flex;align-items:center;gap:10px;font-size:16px;color:#0090FC">
        <span>⬆</span><span>导出审计 JSON（脱敏）</span></div>
      <div style="display:flex;align-items:center;gap:10px;font-size:16px;color:#E8A05C">
        <span>👁</span><span>导出含明文（需确认）</span></div>
    </div>
  </div>
`, 4, {nav:true, back:'40-security'}));

*/
// ── 45 销毁与应急 ──
// [已移交给 gen-destroy.js] fs.writeFileSync(D+'45-destroy.html', L.page('销毁与应急', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">备份闸<span class="ch">›</span></div>
    <div class="tip dgr" style="margin:10px 0 0">
      <span>⚠</span><span>7 天内无备份 — 触发销毁将先跳导出向导（接线点：设置 → 备份）</span>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">三级销毁<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="font-size:16px;flex:1">我理解销毁不可恢复</span><span class="sw"></span>
    </div>
    <div style="font-size:13px;color:var(--text-sub);margin-top:8px">
      删除+随机覆写全部本地缓存（钥匙串/台账/日志/审计）
    </div>
    <button class="btn dgr" style="margin-top:14px;background:#FF3B30;color:#FFF">销毁全部数据</button>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    <div style="padding:8px 20px 4px;font-size:12px;color:var(--text-tert)">回收站</div>
    ${L.row('45-destroy','♻','rgba(232,160,92,.18)','#E8A05C','查看回收站（可恢复）','0 项')}
    <div class="sep"></div>
    <div style="padding:14px 20px">
      <div style="display:flex;justify-content:space-between;font-size:16px;margin-bottom:10px">
        <span>清空回收站</span><span style="font-size:13px;color:var(--text-tert)">长按 2 秒释放，松手取消</span></div>
      <button class="btn sec">按住</button>
    </div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    <div style="padding:8px 20px 4px;font-size:12px;color:var(--text-tert)">离职清除</div>
    ${[['爱妃','#E8A05C'],['母上','#0ADBD8'],['父上','#FF3B30'],['朕','#7B7BE8'],['皇子','#30D158']].map(([n,c],i)=>`
      ${i>0?'<div class="sep"></div>':''}
      <div class="rw">
        <div class="ic" style="background:${c}22;color:${c};border-radius:50%">${n[0]}</div>
        <div class="tx"><div class="tt">${n}</div><div class="sb">名下钥匙入归档，记录保留并标「已离开」</div></div>
        <span style="font-size:14px;color:#FF3B30;font-weight:600">清除</span></div>`).join('')}
  </div>

  <div class="card">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="flex:1"><div style="font-size:16px">只读安全模式</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:2px">关闭（异常时手动打开）</div></div>
      <span class="sw"></span>
    </div>
  </div>
`, 4, {nav:true, back:'40-security'}));

*/
// ── 46 安全模式说明 ──
// [已移交给 gen-fill3.js] fs.writeFileSync(D+'46-safemode.html', L.page('安全模式说明', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">门锁的安全模式介绍<span class="ch">›</span></div>
    <div style="font-size:17px;font-weight:600;margin-top:8px;line-height:1.5">门锁的安全模式分为 A 模式和 B 模式</div>
    <div style="font-size:14px;color:var(--text-sub);margin-top:12px;line-height:1.6">
      <b style="color:#FFF">A 模式</b>：只需要单一方式（密码／指纹／手机）验证通过就可以开锁
    </div>
    <div style="font-size:14px;color:var(--text-sub);margin-top:10px;line-height:1.6">
      <b style="color:#FFF">B 模式</b>：需要用两种不同方式（指纹+密码／指纹+手机／手机+密码）组合验证通过才可开锁
    </div>
  </div>

  <div class="card">
    <div class="cardlink">怎么设置<span class="ch">›</span></div>
    <div style="font-size:14px;color:var(--text-sub);margin-top:8px;line-height:1.7">
      当前模式在「锁信息名片」(设备页) 读取后显示。本 App 只给变严的方向 (A→B)；要放宽回 A 模式请在门锁键盘上操作或联系管理员。
    </div>
    <div class="footer">还没读到锁状态 —— 先在设备页读一次锁信息，这里才会出现切换按钮。</div>
  </div>
`, 4, {nav:true, back:'05-system'}));

*/
console.log('✓ 系统域 7 页（前段）');
