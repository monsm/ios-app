'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const M = [['朕','#7B7BE8','4'],['爱妃','#E8A05C','2'],['皇子','#30D158','5'],['父上','#FF3B30','2'],['母上','#0ADBD8','2']];

// ── 30 成员列表 ──
// [已移交给 gen-members-list.js] fs.writeFileSync(D+'30-members-list.html', L.page('成员列表', `
/* ... 省略 ...

  <div class="h1">成员列表</div>
  <div class="sub">点一位成员看名下钥匙与授权来源</div>

  <div class="card rowlist" style="margin-top:24px;padding:6px 0">
    ${M.map(([n,c,k],i)=>`
      ${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="32-member-detail.html">
        <div class="ic" style="background:${c}22;color:${c};border-radius:50%">${n[0]}</div>
        <div class="tx"><div class="tt">${n}</div><div class="sb">成员 · ${k} 份钥匙</div></div>
        <div class="ch">›</div></a>`).join('')}
  </div>

  <a class="btn ghost" href="34-merge.html" style="margin-top:12px">合并重复成员</a>
  <div style="text-align:center;font-size:12px;color:var(--text-tert);margin-top:12px;line-height:1.6">
    合并要从一条具体成员发起 —— 先选一位作为主档案
  </div>
`, 3, {nav:true, back:'04-members', right:'编辑'}));

*/
// ── 31 添加成员（三步向导）──
// [已移交给 gen-hero3.js] fs.writeFileSync(D+'31-member-wizard.html', L.page('添加成员', `
/* ... 省略 ...

  <div style="display:flex;gap:6px;justify-content:center;margin:8px 0 24px">
    <span style="width:24px;height:4px;border-radius:2px;background:#E8A05C"></span>
    <span style="width:24px;height:4px;border-radius:2px;background:rgba(255,255,255,.16)"></span>
    <span style="width:24px;height:4px;border-radius:2px;background:rgba(255,255,255,.16)"></span>
  </div>

  <div class="h1">步骤 1/3 · 称呼</div>
  <div class="sub">给这位成员起个名字，之后全家都用它称呼</div>

  <div class="card" style="margin-top:24px">
    <div class="clabel" style="margin-top:0">称呼</div>
    <input class="inp" style="margin-top:8px" placeholder="汉字 / 英文 / 数字，上限 20" value="奶奶">
    <div class="clabel">emoji 代号</div>
    <div style="display:flex;gap:10px;margin-top:10px;flex-wrap:wrap">
      ${['🐻','🐱','🐸','🐙','🦊','🐧','🐯'].map((e,i)=>
        `<div style="width:48px;height:48px;border-radius:50%;
          background:${i===0?'rgba(232,160,92,.20)':'rgba(255,255,255,.06)'};
          border:2px solid ${i===0?'#E8A05C':'transparent'};
          display:flex;align-items:center;justify-content:center;font-size:22px">${e}</div>`).join('')}
    </div>
  </div>

  <div class="tip info">成员只是「谁能开门」的名录。分配钥匙在下一步。</div>
  <button class="btn" style="margin-top:8px">下一步</button>
`, 3, {nav:true, back:'04-members'}));

*/
// ── 32 成员详情 360 ──
// [已移交给 gen-hero3.js] fs.writeFileSync(D+'32-member-detail.html', L.page('爱妃', `
/* ... 省略 ...

  <div style="text-align:center;padding:16px 0 24px">
    <div style="width:96px;height:96px;border-radius:50%;margin:0 auto;
      background:rgba(232,160,92,.20);border:3px solid #E8A05C;
      display:flex;align-items:center;justify-content:center;font-size:40px;color:#E8A05C">爱</div>
    <div style="font-size:26px;font-weight:700;margin-top:16px">爱妃</div>
    <div style="font-size:13px;color:var(--text-sub);margin-top:6px">成员 · 2026-03-12 加入</div>
    <div style="display:flex;gap:8px;justify-content:center;margin-top:14px">
      <span class="badge ok">有效</span><span class="badge" style="background:rgba(255,255,255,.08);color:#8D8D93">久未用</span>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">名下钥匙<span class="ch">›</span></div>
    <div style="display:flex;gap:14px;margin-top:4px">
      <div style="flex:1">
        ${L.drow('#E8A05C','2',' 份钥匙')}
        ${L.drow('#0ADBD8','1',' 枚指纹')}
        ${L.drow('#8D8D93','0',' 个临时码')}
      </div>
      ${L.donut(84,[['#E8A05C',0.66],['#0ADBD8',0.2],['rgba(255,255,255,.10)',0.14]],'2')}
    </div>
    <div class="sep"></div>
    ${L.row('13-key-detail','🔑','rgba(232,160,92,.18)','#E8A05C','指纹 10','2026-08-20 录入','<span class="badge ok">有效</span>')}
    <div class="sep"></div>
    ${L.row('13-key-detail','🔑','rgba(232,160,92,.18)','#E8A05C','密码-爱妃-长期','2026-03-12 创建','<span class="badge ok">有效</span>')}
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">最近活动</div>
    <div style="margin-top:12px;display:flex;flex-direction:column;gap:12px">
      ${[['10-21 18:22','开门 · 指纹 10'],['10-19 07:45','开门 · 指纹 10'],['10-12 21:10','开门 · 密码']].map(([t,w])=>
        `<div style="display:flex;justify-content:space-between;font-size:14px">
          <span>${t}</span><span style="color:var(--text-sub)">${w}</span></div>`).join('')}
    </div>
    <div class="footer">最近 30 天没开过门 —— 这位成员的钥匙可能该复查了。</div>
  </div>

  <div style="display:flex;gap:10px;margin-top:4px">
    <button class="btn sec" style="flex:1">编辑</button>
    <button class="btn dgr" style="flex:1">归档</button>
  </div>
`, 3, {nav:true, back:'30-members-list', right:'···'}));

*/
// ── 33 已归档 ──
// [已移交给 gen-archived.js] fs.writeFileSync(D+'33-archived.html', L.page('归档成员', `
/* ... 省略 ...

  <div class="card rowlist" style="margin-top:8px;padding:6px 0">
    <div style="padding:4px 20px 10px;font-size:12px;color:var(--text-tert)">已归档 1 位</div>
    <a class="rw" href="32-member-detail.html">
      <div class="ic" style="background:rgba(141,141,147,.16);color:#8D8D93;border-radius:50%">伯</div>
      <div class="tx"><div class="tt">伯伯</div><div class="sb">2026-08-01 归档 · 名下 0 份钥匙</div></div>
      <div class="ch">›</div></a>
  </div>

  <div class="tip info">归档不删数据。名下的钥匙会转成「未分配」，可以再认领。</div>
  <button class="btn sec" style="margin-top:4px">恢复选中成员</button>
`, 3, {nav:true, back:'04-members'}));

*/
// ── 34 合并 ──
// [已移交给 gen-fill3.js] fs.writeFileSync(D+'34-merge.html', L.page('重复合并', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">主档（保留）<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <div style="width:40px;height:40px;border-radius:50%;background:rgba(123,123,232,.20);
        display:flex;align-items:center;justify-content:center;color:#7B7BE8;font-weight:600">朕</div>
      <div><div style="font-size:16px">朕</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:2px">4 份钥匙 · 3 条活动</div></div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">副档（钥匙将迁移至主档）<span class="ch">›</span></div>
    <div class="clabel">选择副档</div>
    <div style="display:flex;flex-direction:column;gap:10px;margin-top:12px">
      ${[['爱妃','#E8A05C'],['皇子','#30D158'],['父上','#FF3B30']].map(([n,c])=>
        `<div style="display:flex;align-items:center;gap:12px;padding:12px;
          background:rgba(255,255,255,.04);border-radius:12px">
          <div style="width:32px;height:32px;border-radius:50%;background:${c}22;
            display:flex;align-items:center;justify-content:center;color:${c};font-size:14px">${n[0]}</div>
          <span style="flex:1;font-size:15px">${n}</span>
          <span style="font-size:12px;color:var(--text-tert)">2 份钥匙</span></div>`).join('')}
    </div>
  </div>

  <div class="tip dgr">合并后副档会被删除，名下钥匙与活动记录迁到主档。这一步不可撤销。</div>
  <button class="btn dgr" style="margin-top:8px">合并</button>
`, 3, {nav:true, back:'30-members-list'}));

*/
// ── 50 事件记录 ──
// [已移交给 gen-templates.js] fs.writeFileSync(D+'50-events.html', L.page('事件', `
/* ... 省略 ...

  <div class="h1">事件</div>
  <div class="sub">本机还没有从门锁读过日志</div>

  <div class="empty" style="padding:56px 28px">
    <div class="ic">📋</div>
    <div class="t">还没有记录</div>
    <div class="s">连上门锁后点下面同步一次，之后按天浏览。</div>
    <button class="btn" style="margin-top:24px;width:auto;padding:0 32px">从门锁同步日志</button>
  </div>
`, 0, {nav:true, back:'01-home', right:'🔍'}));

*/
// ── 51 动态 ──
// [已移交给 gen-templateD.js] fs.writeFileSync(D+'51-feed.html', L.page('动态', `
/* ... 省略 ...

  <div class="h1">动态</div>
  <div class="sub">全部门锁的开门与告警汇总</div>

  <div class="empty" style="padding:56px 28px">
    <div class="ic">🔔</div>
    <div class="t">还没有动态</div>
    <div class="s">连接门锁读取记录后，这里会汇总全部门锁的开门与告警事件。</div>
    <a class="btn sec" href="23-gateway.html" style="margin-top:24px;width:auto;padding:0 28px">去添加门锁</a>
  </div>
`, 0, {nav:true, back:'01-home'}));

*/
// ── 52 统计 ──
// [已移交给 gen-stats.js] fs.writeFileSync(D+'52-stats.html', L.page('统计', `
/* ... 省略 ...

  <div class="chiprow">
    <div class="chip compact">${L.ring([['#0090FC',.6]])}</div>
    <div class="chip">${L.ring([['#0ADBD8',.8]])}<div><div class="lbl">总开门</div><div class="val">127 次</div></div></div>
    <div class="chip">${L.ring([['#FF9F0A',.2]])}<div><div class="lbl">告警</div><div class="val">2 条</div></div></div>
  </div>

  <div style="margin-top:28px">
    <div class="h1">统计</div>
    <div class="sub">近 30 天 · 1 把门锁 · 5 位成员</div>
  </div>

  <div class="card" style="margin-top:26px">
    <div class="cardlink">开门趋势<span class="ch">›</span></div>
    <div style="position:relative;height:100px;margin-top:12px">
      <div class="dash"><i></i><i></i><i></i><i></i><i></i><i></i></div>
      <svg width="100%" height="100" viewBox="0 0 320 100" preserveAspectRatio="none" style="position:absolute;inset:0">
        <defs><linearGradient id="st" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#00C6FF" stop-opacity=".42"/>
          <stop offset="1" stop-color="#0090FC" stop-opacity="0"/></linearGradient></defs>
        <path d="M0,72 L36,64 L72,48 L108,58 L144,32 L180,46 L216,38 L252,56 L288,50 L320,62 L320,100 L0,100 Z" fill="url(#st)"/>
        <path d="M0,72 L36,64 L72,48 L108,58 L144,32 L180,46 L216,38 L252,56 L288,50 L320,62"
          fill="none" stroke="#00C6FF" stroke-width="2"/>
      </svg>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:11px;color:var(--text-tert);margin-top:8px">
      <span>9-22</span><span>9-27</span><span>10-2</span><span>10-7</span><span>10-12</span><span>10-21</span>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">日均</div><div class="cvalue">4.2 次</div></div>
      <div><div class="clabel" style="margin-top:0">最忙一天</div><div class="cvalue">9 次</div></div>
    </div>
    <div class="footer">127 次开门里，自动开锁占 41%，手动 52%，临时码 7%。</div>
  </div>

  <div class="card">
    <div class="cardlink">成员活跃度<span class="ch">›</span></div>
    <div style="display:flex;gap:14px;margin-top:4px">
      <div style="flex:1">
        ${M.map(([n,c,k])=>L.drow(c,n,' ' + Math.round(parseInt(k)*6) + ' 次')).join('')}
      </div>
      ${L.donut(96,[['#7B7BE8',.35],['#E8A05C',.22],['#30D158',.26],['#FF3B30',.09],['#0ADBD8',.08]])}
    </div>
    <div class="sep"></div>
    <div class="footer" style="margin-top:0">朕近 7 天开门约 24 次，工作日 8–9 点最活跃。</div>
  </div>

  <div class="card">
    <div class="cardlink">时段分布<span class="ch">›</span></div>
    <div style="display:flex;gap:2px;align-items:flex-end;height:64px;margin-top:12px">
      ${Array.from({length:24},(_,i)=>{const h=[2,0,0,0,0,1,8,14,22,10,6,8,12,6,4,5,9,18,26,14,8,5,3,1][i];
        return `<div style="flex:1;height:${Math.max(2,h*2.2)}px;background:${h>15?'#F11B51':h>8?'#FF9F0A':'rgba(0,144,252,.55)'};border-radius:1px"></div>`}).join('')}
    </div>
    <div style="display:flex;justify-content:space-between;font-size:11px;color:var(--text-tert);margin-top:8px">
      <span>0</span><span>6</span><span>12</span><span>18</span><span>24</span>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">高峰</div><div class="cvalue">18–19 点</div></div>
      <div><div class="clabel" style="margin-top:0">低谷</div><div class="cvalue">1–5 点</div></div>
    </div>
  </div>
`, 0, {nav:true, back:'01-home'}));

*/
console.log('✓ 成员域 5 页 + 事件与统计 3 页');
