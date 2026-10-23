'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';

// ── 47 备份与恢复 ──
// [已移交给 gen-fill.js] fs.writeFileSync(D+'47-backup.html', L.page('备份与恢复', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="font-size:26px">⚠️</div>
      <div><div style="font-size:18px;font-weight:700">从未备份</div>
      <div style="font-size:13px;color:rgba(255,255,255,.75);margin-top:4px">备份包含全部钥匙与设置，全程离线加密。</div></div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">导出<span class="ch">›</span></div>
    <div style="font-size:14px;color:var(--text-sub);margin-top:8px;line-height:1.6">
      生成一份备份，存到 iCloud 云盘 / 我的 iPhone，或复制成文本。
    </div>
    <button class="btn" style="margin-top:14px">📄 生成备份</button>
  </div>

  <div class="card">
    <div class="cardlink">恢复<span class="ch">›</span></div>
    <div style="font-size:14px;color:var(--text-sub);margin-top:8px;line-height:1.6">
      从 iCloud 云盘 / 我的 iPhone 里选备份文件，或直接粘贴备份文本。相同设备会被覆盖，其它设备保留。
    </div>
    <button class="btn ghost" style="margin-top:14px">📂 从文件导入</button>
    <button class="btn ghost" style="margin-top:10px">📋 粘贴备份文本</button>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('05-system','🛠','rgba(255,255,255,.08)','#8D8D93','备份工作室','导出 / 恢复 / 校验')}
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">加密参数</div>
    <div style="margin-top:12px;display:flex;flex-direction:column;gap:10px;font-size:14px">
      <div style="display:flex;justify-content:space-between">
        <span style="color:var(--text-sub)">算法</span><span>AES-128-CBC</span></div>
      <div style="display:flex;justify-content:space-between">
        <span style="color:var(--text-sub)">认证</span><span>HMAC-SHA256</span></div>
      <div style="display:flex;justify-content:space-between">
        <span style="color:var(--text-sub)">密钥派生</span><span>PBKDF2 60000 轮</span></div>
    </div>
  </div>
`, 4, {nav:true, back:'05-system'}));

*/
// ── 48 导出中心 ──
// [已移交给 gen-export.js] fs.writeFileSync(D+'48-export.html', L.page('导出与分享', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">范围<span class="ch">›</span></div>
    <div class="segctl2" style="margin-top:10px">
      <div class="o on">当月</div><div class="o">全部</div><div class="o">仅告警</div><div class="o">单日</div>
    </div>
    <div class="footer">导出与分享会让文件离开本机（AirPrint/照片/聊天由你选）。生成过程纯本地，不经过任何网络。</div>
  </div>

  <div class="card">
    <div class="cardlink">列选择<span class="ch">›</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:10px">
      ${[['时间',true],['类型',true],['成员',true],['告警',true],['钥匙',false],['原始 hex',false]].map(([n,on])=>`
        <div style="display:flex;align-items:center;gap:12px">
          <span style="flex:1;font-size:16px">${n}</span><span class="sw${on?' on':''}"></span></div>`).join('')}
    </div>
  </div>

  <div class="card">
    <div style="display:flex;align-items:center;gap:12px">
      <div style="flex:1"><div style="font-size:16px">脱敏导出</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:3px;line-height:1.5">
        脱敏与格式独立：关时 JSON 含原始 hex；开时 hex 列留空、日志导出把连续数字掩码。</div></div>
      <span class="sw"></span>
    </div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('48-export','📊','rgba(232,160,92,.18)','#E8A05C','CSV 标准导出','表格软件可直接打开')}
    <div class="sep"></div>
    ${L.row('48-export','{}','rgba(0,144,252,.16)','#0090FC','原始 JSON + hex','含锁端原始报文，供开发核对')}
    <div class="sep"></div>
    ${L.row('48-export','📄','rgba(60,222,2,.16)','#3CDE02','月度 PDF 报告','排版好的可打印报告')}
  </div>

  <div class="card">
    <div class="cardlink">运行日志<span class="ch">›</span></div>
    <div class="segctl2" style="margin-top:10px">
      <div class="o on">CSV</div><div class="o">JSON</div><div class="o">纯文本</div>
    </div>
    <button class="btn" style="margin-top:12px">生成</button>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('48-export','✉','rgba(232,160,92,.18)','#E8A05C','用系统邮件发送','附件与 CSV 同源')}
    <div class="sep"></div>
    ${L.row('48-export','📧','rgba(232,160,92,.18)','#E8A05C','邮件模板 .eml','复制到邮件客户端')}
    <div class="sep"></div>
    ${L.row('48-export','🖼','rgba(255,159,10,.16)','#FF9F0A','单日长图','一天的全部记录拼成长图')}
    <div class="sep"></div>
    ${L.row('48-export','⚠','rgba(255,59,48,.16)','#FF3B30','告警分享卡','9:16 卡片，只含这一条告警')}
    <div class="sep"></div>
    ${L.row('48-export','📋','rgba(0,144,252,.16)','#0090FC','告警事实单页','与物业沟通用的 PDF')}
  </div>

  <div class="card">
    <div class="cardlink">加密压缩导出<span class="ch">›</span></div>
    <input class="inp" style="margin-top:10px" placeholder="加密口令（至少 6 位）" type="password">
    <button class="btn ghost" style="margin-top:12px">🔒 加密压缩导出</button>
  </div>
`, 4, {nav:true, back:'05-system', right:'关闭'}));

*/
// ── 49 外观工作室 ──
// [已移交给 gen-gallery.js] fs.writeFileSync(D+'49-appearance.html', L.page('外观工作室', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">强调色<span class="ch">›</span></div>
    <div style="font-size:13px;color:var(--text-sub);margin-top:8px;line-height:1.6">
      只换按钮、开锁环、当前小时这些地方的颜色。正文始终是正文的颜色，不会因此变得看不清。
    </div>
    <div style="display:flex;gap:14px;margin-top:16px;flex-wrap:wrap">
      ${[['#D98B45','铜'],['#7B7BE8','靛蓝'],['#3CDE02','森林'],['#FF9F0A','琥珀'],['#8D8D93','石墨'],['#FF694E','玫瑰'],['#0ADBD8','极光']].map(([c,n],i)=>
        `<div style="width:calc(25% - 11px);text-align:center">
          <div style="width:44px;height:44px;border-radius:50%;margin:0 auto;background:${c};
            border:3px solid ${i===0?'#FFF':'transparent'}"></div>
          <div style="font-size:11px;color:${i===0?'#FFF':'var(--text-sub)'};margin-top:7px">${n}</div></div>`).join('')}
    </div>
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

*/
// ── 4a 本机设置 ──
// [已移交给 gen-fill4.js] fs.writeFileSync(D+'4a-me.html', L.page('本机设置', `
/* ... 省略 ...

  <div class="h1">本机设置</div>
  <div class="sub">应用锁 · 备份 · 外观 · 关于</div>

  <div class="card" style="margin-top:24px;padding:18px 12px">
    <div style="display:flex;justify-content:space-around;text-align:center">
      ${[['未锁','应用锁','#FF9F0A'],['0','待处理','#30D158'],['从未','上次备份','#FF9F0A'],['1','门锁','#0090FC']].map(([v,l,c])=>`
        <div><div style="font-size:22px;font-weight:700;color:${c};font-variant-numeric:tabular-nums">${v}</div>
        <div style="font-size:11px;color:var(--text-sub);margin-top:5px">${l}</div></div>`).join('')}
    </div>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('40-security','🔒','rgba(255,159,10,.16)','#FF9F0A','本机数据保护','应用锁 / 审计 / 销毁','<span style="font-size:13px;color:var(--text-tert);margin-right:8px">未开启</span>')}
    <div class="sep"></div>
    ${L.row('42-peek','👁','rgba(10,219,216,.16)','#0ADBD8','隐私与伪装','后台即糊 / 限时可见 / 水印')}
    <div class="sep"></div>
    ${L.row('4a-me','🩺','rgba(0,144,252,.16)','#0090FC','诊断与自检','自检 · 数据健康 · 启动耗时')}
  </div>
  <div class="footer" style="padding:0 20px">这一组动的是本机数据与访问权限，改动前会二次确认。</div>

  <div class="card rowlist" style="margin-top:12px;padding:6px 0">
    ${L.row('21-lock-profile','🔒','rgba(255,255,255,.08)','#8D8D93','这台锁','容量 / 固件 / 信号')}
    <div class="sep"></div>
    ${L.row('20-locks','📱','rgba(255,255,255,.08)','#8D8D93','设备管理','1 把')}
    <div class="sep"></div>
    ${L.row('47-backup','💾','rgba(255,159,10,.16)','#FF9F0A','备份与恢复','全量导出 / 导入')}
    <div class="sep"></div>
    ${L.row('49-appearance','🎨','rgba(232,160,92,.18)','#E8A05C','外观工作室','强调色 / 对比度 / 周起始')}
  </div>

  <div class="card rowlist" style="margin-top:12px;padding:6px 0">
    ${L.row('48-export','📤','rgba(255,255,255,.08)','#8D8D93','导出中心','PDF / CSV / 分享')}
    <div class="sep"></div>
    ${L.row('60-care','<span class="svgi" data-i="gear"></span>','rgba(255,255,255,.08)','#8D8D93','维护与保养','周期 / 待办 / 历史')}
    <div class="sep"></div>
    ${L.row('61-reminders','🎂','rgba(255,255,255,.08)','#8D8D93','关怀提醒','公告板 / 纪念日 / 生日')}
  </div>

  <div style="text-align:center;font-size:12px;color:var(--text-tert);margin-top:24px">
    KF Key · 1.0.2 (2026.10.23)
  </div>
`, 4, {nav:true, back:'05-system'}));

*/
// ── 60 维护与保养 ──
// [已移交给 gen-fix4.js] fs.writeFileSync(D+'60-care.html', L.page('维护与保养', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px;background:linear-gradient(160deg,#5E5CE6,#3C489C)">
    <div class="cardlink" style="color:rgba(255,255,255,.7)">保养<span class="ch" style="color:rgba(255,255,255,.5)">›</span></div>
    <div style="font-size:19px;font-weight:700;margin-top:4px">还没记录过保养</div>
    <div style="display:flex;align-items:center;justify-content:space-between;margin-top:18px">
      <div><div style="font-size:12px;color:rgba(255,255,255,.7)">状态</div>
      <div style="font-size:16px;font-weight:600;margin-top:4px">未记录</div></div>
      ${L.donut(84,[['#30D158',0.02]],'—')}
    </div>
    <div class="sep" style="background:rgba(255,255,255,.18)"></div>
    <div style="font-size:13px;color:rgba(255,255,255,.75)">记录一次保养，之后会按周期提醒。</div>
    <button class="btn" style="margin-top:12px;background:rgba(255,255,255,.16);color:#FFF">记录本次保养</button>
  </div>

  <div class="card rowlist" style="padding:6px 0">
    ${L.row('60-care','✨','rgba(255,255,255,.08)','#8D8D93','清洁锁体','还没记录过')}
    <div class="sep"></div>
    ${L.row('60-care','🕐','rgba(255,255,255,.08)','#8D8D93','保养历史','查看做过的保养记录')}
  </div>

  <div class="card">
    <div class="ctitle" style="font-size:var(--f-title3)">待办</div>
    <div style="margin-top:14px;display:flex;flex-direction:column;gap:14px">
      ${[['换电池','电池 47%，预计 3 个月后需要更换','#30D158','ok'],
         ['清洁锁体','距上次 92 天，建议每 90 天清一次','#FF9F0A','warn'],
         ['年度电池体检','已设为每年 11-01','#8D8D93','']].map(([t,s,c])=>`
        <div style="display:flex;gap:12px">
          <span style="width:8px;height:8px;border-radius:50%;background:${c};margin-top:6px;flex:0 0 auto"></span>
          <div><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:var(--text-sub);margin-top:3px;line-height:1.5">${s}</div></div></div>`).join('')}
    </div>
    <div class="footer">高频使用会把保养周期缩短到 60 天。上次记录在 92 天前。</div>
  </div>
`, 4, {nav:true, back:'4a-me'}));

*/
// ── 61 关怀提醒 ──
// [已移交给 gen-fill4.js] fs.writeFileSync(D+'61-reminders.html', L.page('关怀提醒', `
/* ... 省略 ...

  <div class="card" style="margin-top:8px">
    <div class="cardlink">家庭公告板<span class="ch">›</span></div>
    <input class="inp" style="margin-top:10px" placeholder="写一句常驻家里的话">
    <div class="footer">这句便签会贴在几处空态旁：设备页、记录页，以及走引导空态卡的页面（设置门锁空态、成就陈列架、维护历史、诊断日志）。未接入的空态不会偷偷显示。</div>
  </div>

  <div class="card">
    <div class="cardlink">纪念日<span class="ch">›</span></div>
    <div style="display:flex;justify-content:space-between;align-items:center;margin-top:10px;font-size:16px">
      <span>结缘日</span><span style="color:var(--text-sub);font-variant-numeric:tabular-nums">2026-10-18</span>
    </div>
    <div class="sep"></div>
    <div style="display:flex;align-items:center;gap:12px">
      <span style="flex:1;font-size:17px">结缘纪念日提醒</span><span class="sw"></span>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">成员生日<span class="ch">›</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="flex:1;font-size:17px">成员生日提醒（提前一天）</span><span class="sw"></span>
    </div>
    <div class="sep"></div>
    <div style="display:flex;flex-direction:column;gap:12px">
      ${[['朕','#7B7BE8'],['爱妃','#E8A05C'],['皇子','#30D158'],['父上','#FF3B30'],['母上','#0ADBD8']].map(([n,c])=>`
        <div style="display:flex;align-items:center;gap:10px;font-size:15px">
          <span style="width:22px;height:22px;border-radius:50%;background:${c}22;color:${c};
            display:flex;align-items:center;justify-content:center;font-size:11px">${n[0]}</span>
          <span style="flex:1">${n}</span>
          <span style="color:var(--text-tert);font-size:13px">9999 天后</span></div>`).join('')}
    </div>
    <div class="footer">生日在「设置 → 成员管理 → 补全信息」里填写（格式 MM-dd）。提醒通过本地通知送达，全程离线，不依赖任何服务器。</div>
  </div>
`, 4, {nav:true, back:'4a-me'}));

*/
console.log('✓ 系统域后 4 页 + 维护 2 页');
