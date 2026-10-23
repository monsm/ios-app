'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 42 防窥与遮蔽 —— 加「已启用」环 ══
// [已移交给 gen-peek.js] fs.writeFileSync(D+'42-peek.html', L.page('防窥与遮蔽', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div style="display:flex;align-items:center;gap:16px">
      <div style="flex:1">
        <div style="font-size:16px;font-weight:600">已启用 2 / 5 项</div>
        <div style="font-size:13px;color:var(--text-sub);margin-top:6px;line-height:1.5">
          分享遮半已开 · 其余四项还没启用</div>
      </div>
      ${L.donut(72,[['#0ADBD8',0.40]],'2')}
    </div>
  </div>

  <div class="card">
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
    ${L.row('43-privacy-dash','🛡','rgba(0,144,252,.16)','#0090FC','隐私仪表盘','2 项防窥已启用')}
  </div>

  <div class="card">
    <div class="cardlink">背景与限时<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:10px">
      ${[['切后台即糊',false,'关闭'],['磨砂挡片',false,'关闭'],['分享遮半',true,'已开：码值默认遮半'],['访客通道',false,'四页照常']].map(([n,on,s])=>`
        <div style="display:flex;align-items:center;gap:12px">
          <div style="flex:1"><div style="font-size:16px">${n}</div>
          <div style="font-size:12px;color:var(--text-sub);margin-top:2px">${s}</div></div>
          <span class="sw${on?' on':''}"></span></div>`).join('')}
    </div>
  </div>
`, 4, {nav:true, back:'05-system'}));

*/
// ══ 45 销毁与应急 —— 步骤 + 危险色 ══
// [已移交给 gen-destroy.js] fs.writeFileSync(D+'45-destroy.html', L.page('销毁与应急', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">备份闸<span class="ch">›</span></div>
    <div class="tip dgr" style="margin:10px 0 0">
      <span>⚠</span><span>7 天内无备份 — 触发销毁将先跳导出向导（接线点：设置 → 备份）</span>
    </div>
  </div>

  <!-- 三级销毁：三段落进度的视觉（危险色）-->
  <div class="card">
    <div class="cardlink">三级销毁<span class="ch">›</span></div>
    <div style="display:flex;gap:10px;margin-top:14px">
      ${[['一级','删缓存','#FF9F0A',1],['二级','覆写台账','#FF694E',1],['三级','全盘覆写','#FF3B30',0]].map(([t,s,c,on])=>`
        <div style="flex:1;text-align:center">
          <div style="height:6px;border-radius:3px;background:${on?c:'rgba(255,255,255,.10)'};margin-bottom:10px"></div>
          <div style="font-size:13px;font-weight:600;color:${on?c:'var(--text-tert)'}">${t}</div>
          <div style="font-size:11px;color:var(--text-tert);margin-top:3px">${s}</div>
        </div>`).join('')}
    </div>
    <div class="sep"></div>
    <div style="display:flex;align-items:center;gap:12px">
      <span style="font-size:16px;flex:1">我理解销毁不可恢复</span><span class="sw"></span>
    </div>
    <div style="font-size:13px;color:var(--text-sub);margin-top:8px">
      删除+随机覆写全部本地缓存（钥匙串/台账/日志/审计）
    </div>
    <button class="btn dgr" style="margin-top:14px;background:#FF3B30;color:#FFF">销毁全部数据</button>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    <div style="padding:8px 20px 4px;font-size:12px;color:var(--text-tert)">回收站</div>
    <div class="rw">
      <div class="ic" style="background:rgba(232,160,92,.18);color:#E8A05C">♻</div>
      <div class="tx"><div class="tt">查看回收站（可恢复）</div><div class="sb">0 项</div></div>
      <div class="ch">›</div></div>
    <div class="sep"></div>
    <div style="padding:14px 20px">
      <button class="btn sec">按住清空回收站</button>
      <div style="text-align:center;font-size:11px;color:var(--text-tert);margin-top:8px">长按 2 秒释放，松手取消</div>
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
// ══ 4a 本机设置 —— 四读数 + 环 ══
fs.writeFileSync(D+'4a-me.html', L.page('本机设置', `
  <div class="h1">本机设置</div>
  <div class="sub">应用锁 · 备份 · 外观 · 关于</div>

  <!-- 图1 顶部双 chip：主状态 + 次状态（玻璃胶囊）-->
  <div style="display:flex;gap:12px;margin-top:18px">
    <div class="chip" style="flex:1;display:flex;align-items:center;gap:11px;padding:11px 16px">
      <span style="width:26px;height:26px;border-radius:8px;background:rgba(255,163,26,.18);
        display:inline-flex;align-items:center;justify-content:center;color:#FFA31A">${sv('lock','15px')}</span>
      <span style="flex:1;min-width:0">
        <span style="display:block;font-size:12px;color:#8A8A90">应用锁</span>
        <span style="display:block;font-size:16px;font-weight:700;color:#FFA31A;margin-top:1px">未开启</span></span>
    </div>
    <div class="chip" style="flex:1;display:flex;align-items:center;gap:11px;padding:11px 16px">
      <span style="width:26px;height:26px;border-radius:8px;background:rgba(47,214,92,.18);
        display:inline-flex;align-items:center;justify-content:center;color:#2FD65C">${sv('check','15px')}</span>
      <span style="flex:1;min-width:0">
        <span style="display:block;font-size:12px;color:#8A8A90">待处理</span>
        <span style="display:block;font-size:16px;font-weight:700;color:#FFF;margin-top:1px">0 项</span></span>
    </div>
  </div>

  <!-- 图2 卡解剖：本机状态（44px 大数字 + 环 + 三列细线）-->
  <div class="card" style="margin-top:20px">
    <div class="cardlink">本机状态<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:2px">
      <div style="flex:1;min-width:0">
        <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
          font-variant-numeric:tabular-nums;color:#FFA31A">1<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:4px">项待办</span></div>
        <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">应用锁未开启 —— 现在谁拿起这台手机，都能直接看到你存的密码。</div>
      </div>
      <svg width="76" height="76" viewBox="0 0 76 76" style="flex:0 0 auto">
        <circle cx="38" cy="38" r="31" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="6"/>
        <circle cx="38" cy="38" r="31" fill="none" stroke="#FFA31A" stroke-width="6"
          stroke-linecap="round" stroke-dasharray="58.4 194.8" transform="rotate(-90 38 38)"/>
      </svg>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel">门锁</div><div class="cvalue">1 把</div></div>
      <div><div class="clabel">上次备份</div><div class="cvalue" style="color:#FFA31A">从未</div></div>
      <div><div class="clabel">设备</div><div class="cvalue">iPhone</div></div>
    </div>
    <div class="footer">四个读数都在这一张卡里 —— 动任何一项都会先二次确认。</div>
  </div>

  <!-- 图2 卡解剖：本机数据与访问权限 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px">本机数据与访问权限<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="40-security.html">
      <div class="ic" style="background:rgba(255,163,26,.14);color:#FFA31A">${sv('shieldCheck')}</div>
      <div class="tx"><div class="tt">本机数据保护</div><div class="sb">应用锁 / 审计 / 销毁</div></div>
      <span style="font-size:13px;color:#6A6A72;margin-right:8px">未开启</span>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="42-peek.html">
      <div class="ic" style="background:rgba(10,219,216,.14);color:#0ADBD8">${sv('eye')}</div>
      <div class="tx"><div class="tt">隐私与伪装</div><div class="sb">后台即糊 / 限时可见 / 水印</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="84-diagnostics.html">
      <div class="ic" style="background:rgba(79,195,255,.14);color:#4FC3FF">${sv('cpu')}</div>
      <div class="tx"><div class="tt">诊断与自检</div><div class="sb">自检 · 数据健康 · 启动耗时</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <div class="footer" style="padding:12px 20px 10px;margin:0">这一组动的是本机数据与访问权限，改动前会二次确认。</div>
  </div>

  <!-- 图2 卡解剖：门锁与设备 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px">门锁与设备<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="21-lock-profile.html">
      <div class="ic" style="background:rgba(255,255,255,.06);color:#8A8A90">${sv('lock')}</div>
      <div class="tx"><div class="tt">这台锁</div><div class="sb">容量 / 固件 / 信号</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="20-locks.html">
      <div class="ic" style="background:rgba(255,255,255,.06);color:#8A8A90">${sv('phone')}</div>
      <div class="tx"><div class="tt">设备管理</div><div class="sb">1 把</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="47-backup.html">
      <div class="ic" style="background:rgba(255,163,26,.14);color:#FFA31A">${sv('archive')}</div>
      <div class="tx"><div class="tt">备份与恢复</div><div class="sb">全量导出 / 导入</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="49-appearance.html">
      <div class="ic" style="background:rgba(217,139,69,.16);color:#D98B45">${sv('star')}</div>
      <div class="tx"><div class="tt">外观工作室</div><div class="sb">强调色 / 对比度 / 周起始</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <!-- 图2 卡解剖：导出与关怀 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px">导出与关怀<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="48-export.html">
      <div class="ic" style="background:rgba(255,255,255,.06);color:#8A8A90">${sv('export')}</div>
      <div class="tx"><div class="tt">导出中心</div><div class="sb">PDF / CSV / 分享</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="60-care.html">
      <div class="ic" style="background:rgba(255,255,255,.06);color:#8A8A90">${sv('timer')}</div>
      <div class="tx"><div class="tt">维护与保养</div><div class="sb">周期 / 待办 / 历史</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="61-reminders.html">
      <div class="ic" style="background:rgba(255,110,180,.14);color:#FF6EB4">${sv('heart')}</div>
      <div class="tx"><div class="tt">关怀提醒</div><div class="sb">公告板 / 纪念日 / 生日</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="70-icon-picker.html">
      <div class="ic" style="background:rgba(255,255,255,.06);color:#8A8A90">${sv('star')}</div>
      <div class="tx"><div class="tt">App 图标</div><div class="sb">8 款可选</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>


`, 4, {nav:true, back:'05-system'}));

// ══ 61 关怀提醒 —— 彩色数据行 ══
fs.writeFileSync(D+'61-reminders.html', L.page('关怀提醒', `
  <div class="card" style="margin-top:8px">
    <div class="cardlink">家庭公告板<span class="ch">›</span></div>
    <input class="inp" style="margin-top:10px" placeholder="写一句常驻家里的话">
    <div class="footer">这句便签会贴在几处空态旁：设备页、记录页，以及走引导空态卡的页面。</div>
  </div>

  <div class="duo">
    <div class="metric-card">
      <div class="mh"><span class="mt">纪念日</span><span class="mc">›</span></div>
      <div class="ms">结缘日</div>
      <div class="mv" style="font-size:20px">2026-10-18</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">每年提醒</div>
    </div>
    <div class="metric-card">
      <div class="mh"><span class="mt">生日</span><span class="mc">›</span></div>
      <div class="ms">5 位成员</div>
      <div class="mv" style="color:#FF9F0A">0<small>位已填</small></div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:10px">格式 MM-dd</div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">纪念日<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:12px">
      <span style="width:8px;height:8px;border-radius:50%;background:#F11B51;flex:0 0 auto"></span>
      <div style="flex:1"><div style="font-size:16px">结缘纪念日提醒</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px">2026-10-18 · 每年</div></div>
      <span class="sw"></span>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">成员生日<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:12px">
      <span style="font-size:16px;flex:1">成员生日提醒（提前一天）</span><span class="sw"></span>
    </div>
    <div class="sep"></div>
    <div style="display:flex;flex-direction:column;gap:14px">
      ${[['朕','#7B7BE8','9999'],['爱妃','#E8A05C','9999'],['皇子','#30D158','9999'],
         ['父上','#FF3B30','9999'],['母上','#0ADBD8','9999']].map(([n,c,d])=>`
        <div style="display:flex;align-items:center;gap:10px;font-size:15px">
          <span style="width:24px;height:24px;border-radius:50%;background:${c}22;color:${c};
            display:flex;align-items:center;justify-content:center;font-size:11px;
            font-weight:600;flex:0 0 auto">${n[0]}</span>
          <span style="flex:1">${n}</span>
          <span style="color:var(--text-tert);font-size:13px;font-variant-numeric:tabular-nums">${d} 天后</span>
        </div>`).join('')}
    </div>
    <div class="footer">生日在「设置 → 成员管理 → 补全信息」里填写（格式 MM-dd）。提醒通过本地通知送达，全程离线，不依赖任何服务器。</div>
  </div>
`, 4, {nav:true, back:'4a-me'}));

console.log('✓ 42 / 45 / 4a / 61 补完');
