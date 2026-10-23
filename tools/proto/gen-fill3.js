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

// ══ 34 重复合并 —— 双列对比 ══
fs.writeFileSync(D+'34-merge.html', L.page('重复合并', `
  <div class="h1">重复合并</div>
  <div class="sub">选一位作为主档案，另一位并入</div>

  <div class="duo" style="margin-top:22px">
    ${gcard('主档（保留）',
      `<div style="width:64px;height:64px;border-radius:50%;background:rgba(123,123,232,.20);
        border:2px solid #7B7BE8;display:flex;align-items:center;justify-content:center;
        font-size:26px;color:#7B7BE8;font-weight:600">朕</div>`,
      '4 份钥匙 · 3 条活动')}
    ${gcard('副档（并入后删除）',
      `<div style="width:64px;height:64px;border-radius:50%;background:rgba(255,59,48,.14);
        border:2px dashed rgba(255,59,48,.5);display:flex;align-items:center;
        justify-content:center;font-size:26px;color:#FF3B30">?</div>`,
      '从下方选择')}
  </div>

  <div class="card">
    <div class="cardlink">选择副档<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:10px;margin-top:12px">
      ${[['爱妃','#E8A05C','2'],['皇子','#30D158','5'],['父上','#FF3B30','2']].map(([n,c,k])=>`
        <div style="display:flex;align-items:center;gap:12px;padding:14px;
          background:rgba(255,255,255,.04);border-radius:12px">
          <div style="width:34px;height:34px;border-radius:50%;background:${c}22;color:${c};
            display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600">${n[0]}</div>
          <span style="flex:1;font-size:15px">${n}</span>
          <span style="font-size:12px;color:var(--text-tert)">${k} 份钥匙</span>
          <div style="width:22px;height:22px;border-radius:50%;border:2px solid rgba(255,255,255,.20)"></div>
        </div>`).join('')}
    </div>
  </div>

  <div class="tip dgr">合并后副档会被删除，名下钥匙与活动记录迁到主档。这一步不可撤销。</div>
  <button class="btn dgr" style="margin-top:8px">合并</button>
`, 3, {nav:true, back:'30-members-list'}));

// ══ 46 安全模式说明 —— 双列对比 ══
fs.writeFileSync(D+'46-safemode.html', L.page('安全模式说明', `
  <div class="h1">安全模式</div>
  <div class="sub">门锁的验证方式分 A / B 两种</div>

  <div class="duo" style="margin-top:22px">
    ${gcard('A 模式',
      `<div style="width:64px;height:64px;border-radius:50%;background:rgba(48,209,88,.16);
        display:flex;align-items:center;justify-content:center;font-size:30px;color:#30D158;font-weight:700">A</div>`,
      '单一方式即可开锁')}
    ${gcard('B 模式',
      `<div style="width:64px;height:64px;border-radius:50%;background:rgba(255,159,10,.16);
        display:flex;align-items:center;justify-content:center;font-size:30px;color:#FF9F0A;font-weight:700">B</div>`,
      '两种方式组合验证')}
  </div>

  <div class="card">
    <div class="cardlink">两种模式的差别<span class="ch">›</span></div>
    <div style="margin-top:12px;display:flex;flex-direction:column;gap:16px">
      <div>
        <div style="display:flex;align-items:center;gap:8px">
          <span class="badge ok">A</span><span style="font-size:15px;font-weight:600">只需要一种</span></div>
        <div style="font-size:13px;color:var(--text-sub);margin-top:8px;line-height:1.6">
          密码／指纹／手机，任选其一验证通过就可以开锁。</div>
      </div>
      <div class="sep" style="margin:0"></div>
      <div>
        <div style="display:flex;align-items:center;gap:8px">
          <span class="badge warn">B</span><span style="font-size:15px;font-weight:600">需要两种不同方式</span></div>
        <div style="font-size:13px;color:var(--text-sub);margin-top:8px;line-height:1.6">
          指纹+密码／指纹+手机／手机+密码，组合验证通过才可开锁。</div>
      </div>
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

// ══ 40 隐私看板 —— 加三段状态环 ══
// [已移交给 gen-fix4.js] fs.writeFileSync(D+'40-security.html', L.page('本机保护', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:16px">
      <div style="flex:1">
        <div style="display:flex;align-items:center;gap:10px">
          <span style="font-size:22px">⚠️</span>
          <span style="font-size:18px;font-weight:700">有需要处理的项目</span>
        </div>
        <div style="font-size:13px;color:rgba(255,255,255,.75);margin-top:8px">
          应用锁未开启 · 从未备份</div>
      </div>
      ${L.donut(84,[['#30D158',0.28],['#30D158',0.28],['#FF9F0A',0.20]],'2')}
    </div>
    <div class="sep" style="background:rgba(255,255,255,.18)"></div>
    <div style="display:flex;justify-content:space-around;text-align:center">
      ${[['钥匙','无风险','#30D158'],['审计链','完整','#30D158'],['数据','正常','#30D158']].map(([k,v,c])=>`
        <div><svg width="15" height="15" viewBox="0 0 15 15"><circle cx="7.5" cy="7.5" r="6" fill="${c}"/></svg>
        <div style="font-size:12px;color:rgba(255,255,255,.72);margin-top:6px">${k}</div>
        <div style="font-size:12px;color:${c};margin-top:2px">${v}</div></div>`).join('')}
    </div>
  </div>

  <div class="duo">
    <div class="metric-card">
      <div class="mh"><span class="mt">应用锁</span><span class="mc">›</span></div>
      <div class="ms">状态</div>
      <div class="mv" style="font-size:20px;color:#FF9F0A">未开启</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">点进设置</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">备份</span><span class="mc">›</span></div>
      <div class="ms">上次</div>
      <div class="mv" style="font-size:20px;color:#FF9F0A">从未</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">建议立即导出</div>
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
// ══ 41 应用锁 —— 彩色数据行 ══
fs.writeFileSync(D+'41-applock.html', L.page('应用锁', `
  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:14px">
      <div style="font-size:28px">🔓</div>
      <div style="flex:1">
        <div style="font-size:18px;font-weight:700">应用锁未开启</div>
        <div style="font-size:13px;color:rgba(255,255,255,.75);margin-top:6px;line-height:1.5">
          现在谁拿起这台手机，都能直接看到你保存的密码</div>
      </div>
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
    <div style="margin-top:16px;display:flex;flex-direction:column;gap:16px">
      ${[['打开 App','每次都要输口令','#30D158'],
         ['敏感动作','彻底销毁 / 离职清除要再输一次','#FF9F0A'],
         ['换机恢复','校验值随备份走，口令不变','#0090FC']].map(([t,s,c])=>`
        <div style="display:flex;gap:12px">
          <span style="width:8px;height:8px;border-radius:50%;background:${c};margin-top:6px;flex:0 0 auto"></span>
          <div style="flex:1"><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:var(--text-sub);margin-top:3px;line-height:1.5">${s}</div></div>
        </div>`).join('')}
    </div>
  </div>
`, 4, {nav:true, back:'05-system'}));

console.log('✓ 34 / 46 / 40 / 41 补完');
