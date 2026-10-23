'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';

// 画廊流的双列图文卡（图 1 Face Gallery 的形态）
// 关键：标题在上 → 图居中 → 说明在下
const gcard = (title, visual, desc) => `
<div class="duo-card">
  <div class="dt">${title}</div>
  <div class="dm">${visual}</div>
  <div class="dd">${desc}</div>
</div>`;
const iconBox = (emoji, color, size=76) =>
  `<div style="width:${size}px;height:${size}px;border-radius:${Math.round(size*0.26)}px;
    background:${color}22;border:1px solid ${color}44;display:flex;align-items:center;
    justify-content:center;font-size:${Math.round(size*0.45)}px">${emoji}</div>`;

// ══ 21 锁档案 —— 模板 A：符号选择是图，正适合画廊 ══
const syms = [['🔒','经典','#5E5CE6'],['🏠','家','#30D158'],['🏢','楼栋','#0090FC'],
              ['🚗','车库','#E8A05C'],['🏬','办公','#FF694E'],['🔑','钥匙','#0ADBD8'],
              ['🚪','侧门','#8D8D93'],['🛡','布防','#F11B51']];
// [已移交给 gen-lockprofile2.js] fs.writeFileSync(D+'21-lock-profile.html', L.page('锁档案', `
/* ... 省略 ...

  <!-- HERO：当前锁的锁牌（图 1 的 New Watch Faces 卡）-->
  <div class="gallery-hero" style="background:linear-gradient(180deg,#7B7BE8 0%,#5E5CE6 35%,#2A2F45 75%,#1C1C1E 100%)">
    <div class="gt">然然家</div>
    <div class="gm">
      <div style="width:96px;height:96px;border-radius:50%;
        background:radial-gradient(circle at 35% 30%,rgba(255,255,255,.35),transparent 60%),
                   rgba(255,255,255,.14);
        display:flex;align-items:center;justify-content:center;font-size:44px;
        box-shadow:0 0 60px rgba(123,123,232,.7)">🔒</div>
    </div>
    <div class="gd">JZ · 固件 1.0.2 · 已连接</div>
  </div>

  <div class="h1" style="margin-top:20px">符号</div>
  <div class="sub">选一个能一眼认出的样子</div>

  <div class="duo" style="margin-top:20px">
    ${syms.map(([e,n,c])=>gcard(n, iconBox(e,c), '')).join('')}
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('32-member-detail','👥','rgba(0,144,252,.16)','#0090FC','成员与钥匙','5 位成员 · 13 项钥匙')}
    <div class="sep"></div>
    ${L.row('22-firmware','⬇','rgba(232,160,92,.18)','#E8A05C','固件','1.0.2 · 已是最新')}
    <div class="sep"></div>
    ${L.row('25-synctime','🕐','rgba(10,219,216,.16)','#0ADBD8','锁内时钟','偏差 −3 秒')}
  </div>

  <button class="btn dgr" style="margin-top:12px">解绑这把锁</button>
`, 2, {nav:true, back:'20-locks', right:'保存'}));

*/
// ══ 49 外观工作室 —— 模板 A：色板是视觉选择 ══
const accents = [['#D98B45','铜'],['#7B7BE8','靛蓝'],['#3CDE02','森林'],
                 ['#FF9F0A','琥珀'],['#8D8D93','石墨'],['#FF694E','玫瑰'],['#0ADBD8','极光']];
fs.writeFileSync(D+'49-appearance.html', L.page('外观工作室', `
  <!-- HERO：当前强调色的预览 -->
  <div class="gallery-hero" style="background:linear-gradient(180deg,#3A2A18 0%,#2A1E10 40%,#1C1C1E 100%)">
    <div class="gt">强调色</div>
    <div class="gm">
      <div style="display:flex;align-items:center;gap:16px">
        <div style="width:64px;height:64px;border-radius:50%;background:#D98B45;
          box-shadow:0 0 40px rgba(217,139,69,.65)"></div>
        <div style="width:54px;height:54px;border:8px solid rgba(217,139,69,.35);
          border-top-color:#D98B45;border-radius:50%"></div>
      </div>
    </div>
    <div class="gd">只换按钮、开锁环、当前小时这些地方</div>
  </div>

  <div class="h1" style="margin-top:20px">七种强调色</div>
  <div class="sub">正文始终是正文的颜色，不会因此变得看不清</div>

  <div class="duo" style="margin-top:20px">
    ${accents.map(([c,n],i)=>gcard(n,
      `<div style="width:72px;height:72px;border-radius:50%;background:${c};
        border:3px solid ${i===0?'#FFF':'transparent'};
        box-shadow:0 0 24px ${c}66"></div>`, i===0?'当前':'')).join('')}
  </div>

  <div class="card">
    <div class="cardlink">看得清 / 每周从哪天算<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:12px">
      <div style="flex:1"><div style="font-size:17px">高对比</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px;line-height:1.5">
        系统里开了「增加对比度」时，这里也会跟着加强</div></div>
      <span class="sw"></span>
    </div>
    <div class="sep"></div>
    ${[['一周从跟随系统开始',true],['一周从周一开始',false],['一周从周日开始',false],['一周从周六开始',false]].map(([n,on],i)=>`
      ${i>0?'<div class="sep" style="margin:12px 0"></div>':''}
      <div style="display:flex;align-items:center;gap:12px;padding:6px 0">
        <span style="flex:1;font-size:17px">${n}</span>
        <div style="width:24px;height:24px;border-radius:50%;
          border:2px solid ${on?'#D98B45':'rgba(255,255,255,.24)'};
          background:${on?'rgba(217,139,69,.20)':'transparent'};
          display:flex;align-items:center;justify-content:center;font-size:13px;color:#D98B45">${on?'✓':''}</div>
      </div>`).join('')}
  </div>
`, 4, {nav:true, back:'05-system'}));

// ══ 31 添加成员 —— 模板 A：emoji 代号是图文选择 ══
const emojis = [['🐻','熊','#E8A05C'],['🐱','猫','#FF9F0A'],['🐸','蛙','#3CDE02'],
                ['🐙','章鱼','#FF694E'],['🦊','狐','#F11B51'],['🐧','企鹅','#0090FC'],
                ['🐯','虎','#FF9F0A'],['🐼','熊猫','#8D8D93']];
// [已移交给 gen-hero3.js] fs.writeFileSync(D+'31-member-wizard.html', L.page('添加成员', `
/* ... 省略 ...

  <div style="display:flex;gap:6px;justify-content:center;margin:8px 0 20px">
    <span style="width:32px;height:4px;border-radius:2px;background:#E8A05C"></span>
    <span style="width:32px;height:4px;border-radius:2px;background:rgba(255,255,255,.16)"></span>
    <span style="width:32px;height:4px;border-radius:2px;background:rgba(255,255,255,.16)"></span>
  </div>

  <div class="h1">步骤 1/3 · 称呼</div>
  <div class="sub">给这位成员起个名字，之后全家都用它称呼</div>

  <div class="card" style="margin-top:22px">
    <div class="clabel" style="margin-top:0">称呼</div>
    <input class="inp" style="margin-top:8px" placeholder="汉字 / 英文 / 数字，上限 20" value="奶奶">
  </div>

  <div class="h1" style="margin-top:24px;font-size:var(--f-title3)">emoji 代号</div>
  <div class="sub" style="font-size:13px;margin-top:6px">选一个能在头像上一眼认出的</div>

  <div class="duo" style="margin-top:16px">
    ${emojis.map(([e,n,c],i)=>gcard(n,
      `<div style="width:68px;height:68px;border-radius:50%;
        background:${c}22;border:2px solid ${i===0?c:'transparent'};
        display:flex;align-items:center;justify-content:center;font-size:32px">${e}</div>`,
      i===0?'已选':'')).join('')}
  </div>

  <div class="tip info">成员只是「谁能开门」的名录。分配钥匙在下一步。</div>
  <button class="btn" style="margin-top:8px">下一步</button>
`, 3, {nav:true, back:'04-members'}));

*/
console.log('✓ 21-lock-profile / 49-appearance / 31-member-wizard 改用模板 A');
