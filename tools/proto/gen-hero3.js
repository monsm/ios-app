'use strict';
// 成员域 3 页补视觉主角（图 6 的画廊流 + 图 5 的 Activity Rings）
const L = require('./lib.js');
const V = require('./viz.js');
const fs = require('fs');
const D = __dirname + '/';
const SYM_SVG = {"hex":"<path d=\"M50 16 L82 33 L82 67 L50 84 L18 67 L18 33 Z\" fill=\"none\" stroke=\"CUR\" stroke-width=\"12\" stroke-linejoin=\"round\"/>","ring":"<circle cx=\"50\" cy=\"50\" r=\"34\" fill=\"none\" stroke=\"CUR\" stroke-width=\"13\"/>","tri":"<path d=\"M50 18 L84 78 L16 78 Z\" fill=\"none\" stroke=\"CUR\" stroke-width=\"13\" stroke-linejoin=\"round\"/>","square":"<rect x=\"20\" y=\"20\" width=\"60\" height=\"60\" rx=\"12\" fill=\"none\" stroke=\"CUR\" stroke-width=\"13\"/>","drop":"<path d=\"M50 16 Q78 46 78 60 A28 28 0 1 1 22 60 Q22 46 50 16 Z\" fill=\"CUR\"/>","star":"<path d=\"M50 14 L60 40 L88 40 L65 57 L74 84 L50 67 L26 84 L35 57 L12 40 L40 40 Z\" fill=\"CUR\"/>","dot":"<circle cx=\"50\" cy=\"50\" r=\"30\" fill=\"CUR\"/>","leaf":"<path d=\"M22 78 Q22 26 78 22 Q74 78 22 78 Z\" fill=\"CUR\"/>"};
const sym = (id, color, size) => `<svg width="${size}" height="${size}" viewBox="0 0 100 100">${SYM_SVG[id].replace(/CUR/g, color)}</svg>`;
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

const M = [['朕','#7B7BE8','4'],['爱妃','#E8A05C','2'],['皇子','#30D158','5'],['父上','#FF3B30','2'],['母上','#0ADBD8','2']];

// ══ 30-members-list：图 6 画廊流（头像 2 列大卡）══
// [已移交给 gen-members-list.js] fs.writeFileSync(D+'30-members-list.html', L.page('成员', `
/* ... 省略 ...

  <!-- HERO：图 6 的 New Watch Faces 形态 —— 5 个重叠头像 -->
  <div class="gallery-hero" style="background:linear-gradient(180deg,#6B7BE8 0%,#546CE4 28%,#3C489C 62%,#141418 100%);
    display:flex;flex-direction:column;justify-content:space-between;padding:22px 20px 18px">
    <div style="font-size:17px;font-weight:700;color:#FFF">5 位成员</div>
    <div style="flex:1;display:flex;align-items:center;justify-content:center">
      <div style="display:flex;align-items:center">
        ${M.map(([n,c],i)=>`
          <div style="width:${i===2?76:56}px;height:${i===2?76:56}px;border-radius:50%;
            background:${c}2E;border:2px solid ${c};display:flex;align-items:center;
            justify-content:center;
            margin-left:${i>0?-14:0}px;z-index:${i===2?5:Math.abs(2-i)};
            transform:rotate(${(i-2)*4}deg);box-shadow:0 8px 20px rgba(0,0,0,.45);position:relative">
            ${sym(['hex','ring','tri','square','drop'][i], c, i===2?34:25)}</div>`).join('')}
      </div>
    </div>
    <div style="font-size:13px;color:rgba(255,255,255,.78);text-align:center">13 项钥匙 · 分布在 5 位成员</div>
  </div>

  <div class="h1" style="margin-top:8px">成员</div>
  <div class="sub">点一位看名下钥匙与授权来源</div>

  <!-- 双列图文卡：图 6 的 Health and Fitness / Photos 形态 -->
  <div class="duo" style="margin-top:18px">
    ${M.map(([n,c,k],i)=>`
      <a class="duo-card" href="32-member-detail.html" style="text-decoration:none;color:inherit">
        <div class="dm">
          <div style="width:86px;height:86px;border-radius:50%;background:${c}26;
            border:${i===0?'3px':'2px'} solid ${c};display:flex;align-items:center;
            justify-content:center">
            ${sym(['hex','ring','tri','square','drop'][i], c, 38)}</div>
        </div>
        <div class="dt" style="text-align:center;font-size:16px">${n}</div>
        <div class="dd" style="text-align:center">${k} 份钥匙</div>
      </a>`).join('')}
  </div>

  <div class="card" style="margin-top:4px;padding:6px 0">
    <a class="rw" href="31-member-wizard.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('personPlus')}</div>
      <div class="tx"><div class="tt">添加成员</div><div class="sb">三步向导</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="34-merge.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('refresh')}</div>
      <div class="tx"><div class="tt">合并重复</div><div class="sb">同一人的两条记录</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="33-archived.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('archive')}</div>
      <div class="tx"><div class="tt">已归档</div><div class="sb">1 位待恢复</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>
`, 3, {nav:true, back:'04-members', right:'编辑'}));

*/
// ══ 31-member-wizard：emoji 代号选择做主角（图 6 的画廊选择）══
const EMO = [['🐻','熊'],['🐱','猫'],['🐸','蛙'],['🐙','章鱼'],['🦊','狐'],['🐧','企鹅'],['🐯','虎'],['🐼','熊猫']];
fs.writeFileSync(D+'31-member-wizard.html', L.page('添加成员', `
  <div class="h1">步骤 1/3 · 称呼</div>
  <div class="sub">给这位成员起个名字，之后全家都用它称呼</div>

  <div class="card" style="margin-top:24px">
    <div class="clabel" style="margin-top:0">称呼</div>
    <input class="inp" style="margin-top:8px" placeholder="汉字 / 英文 / 数字，上限 20" value="奶奶">
  </div>

  <!-- 主角：emoji 代号 2 列画廊（图 6 形态）-->
  <div class="h1" style="margin-top:26px;font-size:19px;font-weight:700">emoji 代号</div>
  <div class="sub" style="font-size:13px;margin-top:6px">选一个能在头像上一眼认出的</div>

  <div style="display:flex;gap:12px;overflow-x:auto;scrollbar-width:none;margin-top:16px;padding-bottom:4px">
    ${EMO.map(([e,n],i)=>`<div style="flex:0 0 auto;width:92px;
      background:${i===0?'linear-gradient(180deg,#2A2418 0%,#1F1B12 100%)':'linear-gradient(180deg,#202022 0%,#191919 100%)'};
      border-radius:20px;padding:16px 10px;text-align:center;
      box-shadow:inset 0 .5px 0 rgba(255,255,255,.055),inset 0 0 0 .5px ${i===0?'rgba(255,159,10,.40)':'rgba(255,255,255,.03)'}">
      <div style="font-size:34px;line-height:1">${e}</div>
      <div style="font-size:13px;font-weight:600;color:${i===0?'#FFA31A':'#FFF'};margin-top:10px">${n}</div>
      <div style="font-size:11px;color:${i===0?'#FFA31A':'#6A6A72'};margin-top:3px">${i===0?'已选':'轻点选'}</div>
    </div>`).join('')}
  </div>

  <div class="tip info" style="margin-top:4px">成员只是「谁能开门」的名录。分配钥匙在下一步。</div>
  <button class="btn" style="margin-top:8px">下一步</button>
`, 3, {nav:true, back:'04-members'}));

// ══ 32-member-detail：头像 + 钥匙环做主角 ══
fs.writeFileSync(D+'32-member-detail.html', L.page('爱妃', `
  <div style="text-align:center;padding:16px 0 8px">
    <div style="width:104px;height:104px;border-radius:50%;margin:0 auto;
      background:rgba(232,160,92,.20);border:3px solid #E8A05C;
      display:flex;align-items:center;justify-content:center;font-size:44px;
      color:#E8A05C;font-weight:600;box-shadow:0 0 48px rgba(232,160,92,.28)">爱</div>
    <div style="font-size:26px;font-weight:700;margin-top:18px;letter-spacing:-.3px">爱妃</div>
    <div style="font-size:13px;color:#8D8D93;margin-top:6px">成员 · 2026-03-12 加入</div>
    <div style="display:flex;gap:8px;justify-content:center;margin-top:14px">
      <span class="badge ok">有效</span>
      <span class="badge" style="background:rgba(255,255,255,.08);color:#8D8D93">久未用</span>
    </div>
  </div>

  <div class="h1" style="margin-top:26px">名下钥匙</div>
  <div class="sub">2 份钥匙 · 1 枚指纹 · 0 个临时码</div>

  <div class="duo" style="margin-top:20px">
    <div class="metric-card">
      <div class="mh"><span class="mt">钥匙</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">名下</div><div class="mv" style="color:#E8A05C">2<small>份</small></div>
      <div style="font-size:11px;color:#8D8D93;margin-top:10px">1 枚指纹 · 1 个密码</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">最近活动</span><span class="mc">${sv('chevron')}</span></div>
      <div class="ms">10-21</div><div class="mv" style="font-size:19px">18:22</div>
      <div style="font-size:11px;color:#8D8D93;margin-top:10px">开门 · 指纹 10</div>
    </div>
  </div>

  <div class="card" style="padding:6px 0">
    <a class="rw" href="13-key-detail.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('fingerprint')}</div>
      <div class="tx"><div class="tt">指纹 10</div><div class="sb">2026-08-20 录入</div></div>
      <span class="badge ok">有效</span>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="13-key-detail.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('key')}</div>
      <div class="tx"><div class="tt">密码-爱妃-长期</div><div class="sb">2026-03-12 创建</div></div>
      <span class="badge ok">有效</span>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <div class="card">
    <div class="cardlink">最近活动<span class="ch">${sv('chevron')}</span></div>
    <div style="margin-top:12px;display:flex;flex-direction:column;gap:12px">
      ${[['10-21 18:22','开门 · 指纹 10'],['10-19 07:45','开门 · 指纹 10'],['10-12 21:10','开门 · 密码']].map(([t,w])=>
        `<div style="display:flex;justify-content:space-between;font-size:14px">
          <span>${t}</span><span style="color:#8D8D93">${w}</span></div>`).join('')}
    </div>
    <div class="footer">最近 30 天没开过门 —— 这位成员的钥匙可能该复查了。</div>
  </div>

  <div style="display:flex;gap:10px;margin-top:4px">
    <button class="btn sec" style="flex:1">编辑</button>
    <button class="btn dgr" style="flex:1">归档</button>
  </div>
`, 3, {nav:true, back:'30-members-list', right:'···'}));

console.log('✓ 30 / 31 / 32 补主角');
