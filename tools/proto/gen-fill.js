'use strict';

// 图5 环形（MetricCard 右侧）
const mRing = (pct, color, size=76, label='') => {
  const R = size/2 - 4, C = size/2, W = 6, circ = 2*Math.PI*R;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="flex:0 0 auto">
    <circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="${W}"/>
    <circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="${color}" stroke-width="${W}"
      stroke-linecap="round" stroke-dasharray="${(circ*pct).toFixed(1)} ${circ.toFixed(1)}" transform="rotate(-90 ${C} ${C})"/>
    ${label?`<text x="${C}" y="${C+5}" text-anchor="middle" font-size="${Math.round(size*0.22)}" font-weight="700" fill="${color}" font-family="system-ui">${label}</text>`:''}
  </svg>`;
};

const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const gcard = (title, visual, desc) => `
<div class="duo-card">
  <div class="dt">${title}</div>
  <div class="dm">${visual}</div>
  <div class="dd">${desc}</div>
</div>`;

// ══ 12 临时密码 —— 图 3 的 displayNumber 大读数 + 三段落环 ══
// [已移交给 gen-credential.js] fs.writeFileSync(D+'12-tempcode.html', L.page('临时密码', `
/* ... 省略 ...

  <div class="h1">临时密码</div>
  <div class="sub">6 位数字 · 10 分钟内有效 · 只能用一次</div>

  <!-- 图 3/4 的形态：大读数 + 三段落环（有效期/次数/冷却）-->
  <div class="card" style="margin-top:24px">
    <div style="display:flex;align-items:center;gap:18px">
      <div style="flex:1">
        <div class="clabel" style="margin-top:0">当前码</div>
        <div style="font-size:38px;font-weight:700;letter-spacing:6px;
          font-variant-numeric:tabular-nums;color:#E8A05C;margin-top:6px">—— —— ——</div>
        <div style="font-size:13px;color:var(--text-sub);margin-top:10px">还没生成</div>
      </div>
      ${L.donut(104,[['#0ADBD8',0.001],['#FF694E',0.001],['#3C60FC',0.001]],'—')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">有效期</div><div class="cvalue">10 分钟</div></div>
      <div><div class="clabel" style="margin-top:0">可用次数</div><div class="cvalue">1 次</div></div>
    </div>
    <div class="footer">生成前请先校准门锁时间（0E），否则时间窗不同步会导致密码不匹配。</div>
  </div>

  <button class="btn" style="margin-top:4px">生成临时密码</button>

  <!-- 图 2 的双列：三种临时码形态 -->
  <div class="duo" style="margin-top:20px">
    ${gcard('一次性', `<div style="width:64px;height:64px;border-radius:50%;background:rgba(255,105,78,.16);
      display:flex;align-items:center;justify-content:center;font-size:28px">1</div>`, '用一次即失效')}
    ${gcard('周期', `<div style="width:64px;height:64px;border-radius:50%;background:rgba(10,219,216,.16);
      display:flex;align-items:center;justify-content:center;font-size:28px">∞</div>`, '每 30 分钟轮换')}
    ${gcard('限时', `<div style="width:64px;height:64px;border-radius:50%;background:rgba(60,96,252,.16);
      display:flex;align-items:center;justify-content:center;font-size:28px">⏱</div>`, '指定时段有效')}
    ${gcard('批量', `<div style="width:64px;height:64px;border-radius:50%;background:rgba(232,160,92,.16);
      display:flex;align-items:center;justify-content:center;font-size:28px">▦</div>`, '一次发多个')}
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">历史</div>
    <div class="empty" style="padding:28px 0">
      <div class="ic">⏱</div>
      <div class="t" style="font-size:16px">还没有生成过</div>
      <div class="s">临时码用完即弃，不进台账</div>
    </div>
  </div>
`, 1, {nav:true, back:'02-keys'}));

*/
// ══ 30 成员列表 —— 模板 A 画廊流（成员是头像）══
const M = [['朕','#7B7BE8','4'],['爱妃','#E8A05C','2'],['皇子','#30D158','5'],['父上','#FF3B30','2'],['母上','#0ADBD8','2']];
// [已移交给 gen-members-list.js] fs.writeFileSync(D+'30-members-list.html', L.page('成员列表', `
/* ... 省略 ...

  <div class="h1">成员列表</div>
  <div class="sub">5 位 · 点一位看名下钥匙与授权来源</div>

  <div class="duo" style="margin-top:22px">
    ${M.map(([n,c,k],i)=>`
      <a class="duo-card" href="32-member-detail.html" style="text-decoration:none;color:inherit">
        <div class="dm">
          <div style="width:68px;height:68px;border-radius:50%;background:${c}22;
            border:2px solid ${i===0?c:'transparent'};display:flex;align-items:center;
            justify-content:center;font-size:28px;color:${c};font-weight:600">${n[0]}</div>
        </div>
        <div class="dt" style="text-align:center">${n}</div>
        <div class="dd" style="text-align:center">${k} 份钥匙</div>
      </a>`).join('')}
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('34-merge','⇄','rgba(0,144,252,.16)','#0090FC','合并重复成员','先选一位作为主档案')}
    <div class="sep"></div>
    ${L.row('33-archived','🗄','rgba(141,141,147,.16)','#8D8D93','已归档','1 位待恢复')}
  </div>
`, 3, {nav:true, back:'04-members', right:'编辑'}));

*/
// ══ 33 已归档 —— 模板 D（72pt 行）══
// [已移交给 gen-archived.js] fs.writeFileSync(D+'33-archived.html', `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
/* ... 省略 ...

<title>归档成员</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone"><div class="dsheet">
  <div class="dtop" style="background:linear-gradient(180deg,#2A2A30 0%,#1E1E24 100%)">
    <div class="dtitle">已归档</div>
    <a class="dact" href="30-members-list.html">返回</a>
  </div>
  <div class="dbody">
    <div style="padding:16px 14px">
      <div class="tip info">归档不删数据。名下的钥匙会转成「未分配」，可以再认领。</div>
    </div>
    <div style="padding:0 14px">
      <div class="dpanel">
        <div class="dhead">2026-08-01 归档</div>
        <a class="drow72" href="32-member-detail.html">
          <div style="width:38px;height:38px;border-radius:50%;background:rgba(141,141,147,.16);
            color:#8D8D93;display:flex;align-items:center;justify-content:center;
            font-size:16px;flex:0 0 auto">伯</div>
          <div class="dl"><div class="dt">伯伯</div><div class="ds">名下 0 份钥匙</div></div>
          <span class="badge" style="background:rgba(141,141,147,.16);color:#8D8D93">已归档</span>
          <div style="color:var(--text-tert);font-size:18px;margin-left:6px">›</div>
        </a>
      </div>
      <button class="btn sec" style="margin-top:12px">恢复选中成员</button>
    </div>
  </div>
  <div class="tabbar">
    <a class="tab" href="01-home.html">${L.ICONS.home}<span>门厅</span></a>
    <a class="tab" href="02-keys.html">${L.ICONS.key}<span>钥匙</span></a>
    <a class="tab" href="03-devices.html">${L.ICONS.device}<span>设备</span></a>
    <a class="tab on" href="04-members.html">${L.ICONS.people}<span>成员</span></a>
    <a class="tab" href="05-system.html">${L.ICONS.gear}<span>系统</span></a>
  </div>
</div></div><script src="interact.js"></script></body></html>`);

*/
// ══ 47 备份与恢复 —— 加备份时效环（图 3 三段环）══
fs.writeFileSync(D+'47-backup.html', L.page('备份与恢复', `
  <div class="h1">备份与恢复</div>
  <div class="sub">数据只在这台 iPhone · 全程离线加密</div>

  <!-- 图5 MetricCard 主角：备份状态（44px 大数字 + 灰环）+ 三列细线 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">备份状态<span class="ch">›</span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:2px">
      <div style="flex:1;min-width:0">
        <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
          font-variant-numeric:tabular-nums;color:#FFA31A">0<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:4px">次备份</span></div>
        <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">从未备份 —— 建议先做一份完整备份再动别的。</div>
      </div>
      ${mRing(0.035, '#FFA31A', 76, '!')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel">钥匙</div><div class="cvalue">13 把</div></div>
      <div><div class="clabel">设置</div><div class="cvalue">全部</div></div>
      <div><div class="clabel">加密</div><div class="cvalue" style="color:#2FD65C">AES-128</div></div>
    </div>
    <div class="footer">备份包含全部钥匙与设置，全程离线加密 —— 生成的文件离开本机后也解不开。</div>
  </div>

  <!-- 图5 双列 MetricCard：导出 / 恢复（各带环 + 三列细线）-->
  <div class="duo" style="margin-top:14px">
    <div class="metric-card">
      <div class="mh"><span class="mt">导出</span><span class="mc">›</span></div>
      <div style="display:flex;align-items:flex-start;gap:10px;margin-top:6px">
        <div style="flex:1;min-width:0">
          <div class="mv">0<small>次</small></div>
          <div style="font-size:11px;color:#8A8A90;margin-top:8px">本机 → 文件</div>
        </div>
        ${mRing(0.02, '#4FC3FF', 54)}
      </div>
      <div class="sep"></div>
      <div style="font-size:11px;color:#8A8A90">生成一份备份</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">恢复</span><span class="mc">›</span></div>
      <div style="display:flex;align-items:flex-start;gap:10px;margin-top:6px">
        <div style="flex:1;min-width:0">
          <div class="mv">0<small>次</small></div>
          <div style="font-size:11px;color:#8A8A90;margin-top:8px">文件 → 本机</div>
        </div>
        ${mRing(0.02, '#7B7BE8', 54)}
      </div>
      <div class="sep"></div>
      <div style="font-size:11px;color:#8A8A90">同机覆盖，其它保留</div>
    </div>
  </div>

  <button class="btn" style="margin-top:18px">生成备份</button>
  <button class="btn ghost" style="margin-top:10px">从文件导入</button>
  <button class="btn ghost" style="margin-top:10px">粘贴备份文本</button>

  <!-- 图2 卡解剖：备份工作室 -->
  <div class="card" style="margin-top:18px">
    <div class="cardlink">备份工作室<span class="ch">›</span></div>
    <div style="font-size:14px;color:#8A8A90;margin-top:8px">导出 / 恢复 / 校验</div>
    <div class="sep"></div>
    <div class="footer">工作室里可以做分区勾选、自描述命名、二维码搬运 —— 一整套离线流程都在这。</div>
  </div>

  <!-- 图2 + 图5 三列：加密参数 -->
  <div class="card">
    <div class="cardlink">加密参数<span class="ch">›</span></div>
    <div class="cols" style="margin-top:8px">
      <div><div class="clabel">算法</div><div class="cvalue" style="font-size:14px">AES-128-CBC</div></div>
      <div><div class="clabel">认证</div><div class="cvalue" style="font-size:14px">HMAC-SHA256</div></div>
      <div><div class="clabel">派生</div><div class="cvalue" style="font-size:14px">PBKDF2 6万轮</div></div>
    </div>
    <div class="sep"></div>
    <div class="footer">密钥只由你的口令派生，不存任何恢复密钥 —— 忘记口令等于这份备份作废。</div>
  </div>
`, 4, {nav:true, back:'05-system'}));

// ══ 60 维护与保养 —— 图 4 的三段分色环 ══
// [已移交给 gen-fix4.js] fs.writeFileSync(D+'60-care.html', L.page('维护与保养', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div class="cardlink" style="color:rgba(255,255,255,.7)">保养<span class="ch" style="color:rgba(255,255,255,.5)">›</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      <div style="flex:1">
        <div style="font-size:19px;font-weight:700">还没记录过保养</div>
        <div style="display:flex;gap:16px;margin-top:16px">
          <div><div style="font-size:11px;color:rgba(255,255,255,.7)">状态</div>
          <div style="font-size:15px;font-weight:600;margin-top:4px">未记录</div></div>
          <div><div style="font-size:11px;color:rgba(255,255,255,.7)">周期</div>
          <div style="font-size:15px;font-weight:600;margin-top:4px">90 天</div></div>
        </div>
      </div>
      <div style="position:relative">
        ${L.donut(96,[['#0ADBD8',0.01],['#FF694E',0.01],['#3C60FC',0.01]],'—')}
        <div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
          font-size:11px;color:rgba(255,255,255,.6);padding-top:44px">未记录</div>
      </div>
    </div>
    <div class="sep" style="background:rgba(255,255,255,.18)"></div>
    <div style="font-size:13px;color:rgba(255,255,255,.75)">记录一次保养，之后会按周期提醒。</div>
    <button class="btn" style="margin-top:12px;background:rgba(255,255,255,.16);color:#FFF">记录本次保养</button>
  </div>

  <!-- 图 2 的双列：三项待办读数 -->
  <div class="duo" style="margin-top:12px">
    <div class="metric-card">
      <div class="mh"><span class="mt">换电池</span><span class="mc">›</span></div>
      <div class="ms">预计</div>
      <div class="mv" style="color:#30D158">3<small>月</small></div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">当前 47%</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">清洁锁体</span><span class="mc">›</span></div>
      <div class="ms">距上次</div>
      <div class="mv" style="color:#FF9F0A">92<small>天</small></div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">建议每 90 天清一次</div>
    </div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('60-care','✨','rgba(255,255,255,.08)','#8D8D93','清洁锁体','还没记录过')}
    <div class="sep"></div>
    ${L.row('60-care','🕐','rgba(255,255,255,.08)','#8D8D93','保养历史','查看做过的保养记录')}
    <div class="sep"></div>
    ${L.row('61-reminders','🎂','rgba(232,160,92,.18)','#E8A05C','关怀提醒','公告板 / 纪念日 / 生日')}
  </div>

  <div class="card">
    <div style="display:flex;align-items:center;gap:12px">
      <span style="width:8px;height:8px;border-radius:50%;background:#8D8D93;flex:0 0 auto"></span>
      <div style="flex:1"><div style="font-size:15px">年度电池体检</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px">已设为每年 11-01</div></div>
    </div>
    <div class="footer">高频使用会把保养周期缩短到 60 天。上次记录在 92 天前。</div>
  </div>
`, 4, {nav:true, back:'4a-me'}));

*/
// ══ 43 隐私仪表盘 —— 环 + 彩色数据行 ══
fs.writeFileSync(D+'43-privacy-dash.html', L.page('隐私仪表盘', `
  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:16px">
      <div style="flex:1">
        <div style="font-size:17px;font-weight:700">已启用 1 / 5 项防窥</div>
        <div style="font-size:13px;color:rgba(255,255,255,.75);margin-top:6px">
          还有 4 项未开启，轻点下方对应一行即可补上。</div>
      </div>
      ${L.donut(84,[['#30D158',0.20]],'1')}
    </div>
  </div>

  <div class="card">
    <div class="cardlink">逐项状态（轻点即切换）<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:6px;margin-top:6px">
      ${[['切后台即糊','截图与多任务里都是糊的',false],
         ['磨砂挡片','切走时整屏蒙一层磨砂',false],
         ['分享遮半','码值在完成页与详情卡默认遮半',true],
         ['访客通道','四页照常，打开即生效',false],
         ['常驻水印','整屏浮一层淡字标',false]].map(([n,s,on],i)=>`
        <div style="display:flex;align-items:center;gap:12px;padding:12px 0">
          <div style="width:26px;height:26px;border-radius:50%;border:2px solid ${on?'#30D158':'rgba(255,255,255,.20)'};
            background:${on?'rgba(48,209,88,.16)':'transparent'};
            display:flex;align-items:center;justify-content:center;font-size:14px;color:#30D158;
            flex:0 0 auto">${on?'✓':''}</div>
          <div style="flex:1;min-width:0">
            <div style="font-size:16px">${n}</div>
            <div style="font-size:12px;color:var(--text-sub);margin-top:3px">${s}</div>
          </div>
          <span style="font-size:12px;color:${on?'#30D158':'var(--text-tert)'};flex:0 0 auto">${on?'已启用':'未启用'}</span>
        </div>${i<4?'<div class="sep" style="margin:0"></div>':''}`).join('')}
    </div>
  </div>
`, 4, {nav:true, back:'42-peek'}));

console.log('✓ 补了 6 页的形态');
