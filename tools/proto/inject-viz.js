'use strict';
// tools/proto/inject-viz.js —— 给 21 页注入"数据主角"
const fs = require('fs'), path = require('path');
const D = __dirname;
const V = require('./viz.js');
const PLAN = JSON.parse(fs.readFileSync(path.join(D,'viz-plan.json'),'utf8'));
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));

// 每页的具体数据（按功能内容填真实数字）
const DATA = {
  '11-fingerprint': () => `<div class="card"><div class="cardlink">锁内容量<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0.76,'#0ADBD8','76%','已用')}
      <div style="flex:1">${V.compare([['已录',38,50,'#0ADBD8'],['余量',12,50,'rgba(255,255,255,.24)']])}</div>
    </div></div>`,
  '13-key-detail': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">已使用</span><span class="mc">›</span></div>
      <div class="ms">累计</div>
      <div class="mv">24<small>次</small></div>
      ${V.bars([2,3,1,4,6,3,2,5,8,4,3,6,9,5,4,7,10,6,4,8,5,3,7,4],{h:36,a0:'1',a1:'7',a2:'14',a3:'21'})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">最近一次</span><span class="mc">›</span></div>
      <div class="ms">今天</div><div class="mv" style="font-size:22px">07:12</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:12px">朕 · 手动</div></div></div>`,
  '20-locks': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">电量</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv" style="color:#30D158">47<small>%</small></div>
      ${V.bars([42,43,44,43,45,44,46,45,47,46,47,47,47,47,47,47,47,47,47,47,47,47,47,47],{h:36})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">信号</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv">−76<small>dBm</small></div>
      ${V.bars([3,3,3,5,10,20,40,70,92,64,36,20,12,8,6,5,6,10,20,34,22,12,7,4],{h:36})}</div></div>`,
  '13-key-detail': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">已使用</span><span class="mc">›</span></div>
      <div class="ms">累计</div>
      <div class="mv">24<small>次</small></div>
      ${V.bars([2,3,1,4,6,3,2,5,8,4,3,6,9,5,4,7,10,6,4,8,5,3,7,4],{h:36,a0:'1',a1:'7',a2:'14',a3:'21'})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">最近一次</span><span class="mc">›</span></div>
      <div class="ms">今天</div><div class="mv" style="font-size:22px">07:12</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:12px">朕 · 手动</div></div></div>`,
  '20-locks': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">电量</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv" style="color:#30D158">47<small>%</small></div>
      ${V.bars([42,43,44,43,45,44,46,45,47,46,47,47,47,47,47,47,47,47,47,47,47,47,47,47],{h:36})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">信号</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv">−76<small>dBm</small></div>
      ${V.bars([3,3,3,5,10,20,40,70,92,64,36,20,12,8,6,5,6,10,20,34,22,12,7,4],{h:36})}</div></div>`,
  '21-lock-profile': () => `<div class="card" style="margin-top:12px"><div class="cardlink">指纹余量<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0.24,'#5E5CE6','12','可录')}
      <div style="flex:1"><div class="ctitle">38 / 50 已用</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:6px">指纹录在锁里，本机只记「谁的第几枚」</div></div>
    </div></div>`,
  '13-key-detail': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">已使用</span><span class="mc">›</span></div>
      <div class="ms">累计</div>
      <div class="mv">24<small>次</small></div>
      ${V.bars([2,3,1,4,6,3,2,5,8,4,3,6,9,5,4,7,10,6,4,8,5,3,7,4],{h:36,a0:'1',a1:'7',a2:'14',a3:'21'})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">最近一次</span><span class="mc">›</span></div>
      <div class="ms">今天</div><div class="mv" style="font-size:22px">07:12</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:12px">朕 · 手动</div></div></div>`,
  '20-locks': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">电量</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv" style="color:#30D158">47<small>%</small></div>
      ${V.bars([42,43,44,43,45,44,46,45,47,46,47,47,47,47,47,47,47,47,47,47,47,47,47,47],{h:36})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">信号</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv">−76<small>dBm</small></div>
      ${V.bars([3,3,3,5,10,20,40,70,92,64,36,20,12,8,6,5,6,10,20,34,22,12,7,4],{h:36})}</div></div>`,
  '13-key-detail': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">已使用</span><span class="mc">›</span></div>
      <div class="ms">累计</div>
      <div class="mv">24<small>次</small></div>
      ${V.bars([2,3,1,4,6,3,2,5,8,4,3,6,9,5,4,7,10,6,4,8,5,3,7,4],{h:36,a0:'1',a1:'7',a2:'14',a3:'21'})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">最近一次</span><span class="mc">›</span></div>
      <div class="ms">今天</div><div class="mv" style="font-size:22px">07:12</div>
      <div style="font-size:11px;color:var(--text-sub);margin-top:12px">朕 · 手动</div></div></div>`,
  '20-locks': () => `<div class="duo" style="margin-top:12px">
    <div class="metric-card"><div class="mh"><span class="mt">电量</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv" style="color:#30D158">47<small>%</small></div>
      ${V.bars([42,43,44,43,45,44,46,45,47,46,47,47,47,47,47,47,47,47,47,47,47,47,47,47],{h:36})}</div>
    <div class="metric-card"><div class="mh"><span class="mt">信号</span><span class="mc">›</span></div>
      <div class="ms">当前</div><div class="mv">−76<small>dBm</small></div>
      ${V.bars([3,3,3,5,10,20,40,70,92,64,36,20,12,8,6,5,6,10,20,34,22,12,7,4],{h:36})}</div></div>`,
  '21-lock-profile': () => `<div class="card" style="margin-top:12px"><div class="cardlink">指纹余量<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0.24,'#5E5CE6','12','可录')}
      <div style="flex:1"><div class="ctitle">38 / 50 已用</div>
      <div style="font-size:12px;color:var(--text-sub);margin-top:6px">指纹录在锁里，本机只记「谁的第几枚」</div></div>
    </div></div>`,
  '22-firmware': () => `<div class="card" style="margin-top:12px"><div class="cardlink">升级进度<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0,'#5E5CE6','—','未开始')}
      <div style="flex:1">${V.steps(['检查','传输','写入','完成'],1,'#5E5CE6')}</div>
    </div></div>`,
  '23-gateway': () => `<div class="card" style="margin-top:12px"><div class="cardlink">配网步骤<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.steps(['重置网关','连接 WiFi','添加到 App'],1,'#5E5CE6')}</div>`,
  '24-dongles': () => `<div class="card" style="margin-top:12px"><div class="cardlink">已配对<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0,'#5E5CE6','0','台')}
      <div style="flex:1;font-size:13px;color:var(--text-sub);line-height:1.6">上电后点「搜索钥匙串」即可添加。钥匙串靠近门锁即可开门。</div>
    </div></div>`,
  '25-synctime': () => `<div class="card" style="margin-top:12px"><div class="cardlink">偏差范围<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.gauge(-3,-10,10,'#FF9F0A','s')}
    <div style="font-size:13px;color:var(--text-sub);margin-top:14px">校准会把手机时间写进锁内（cmd 0E）。</div></div>`,
  '30-members-list': () => `<div class="card" style="margin-top:12px"><div class="cardlink">钥匙分布<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.compare([['朕',4,5,'#5E5CE6'],['爱妃',2,5,'#E8A05C'],['皇子',5,5,'#30D158'],['父上',2,5,'#FF3B30'],['母上',2,5,'#0ADBD8']])}</div>`,
  '31-member-wizard': () => `<div style="margin:20px 0 8px">${V.steps(['称呼','密钥','角色'],1,'#FF9F0A')}</div>`,
  '33-archived': () => `<div class="card" style="margin-top:12px"><div class="cardlink">归档<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(80,0.2,'#8D8D93','1','位')}
      <div style="flex:1;font-size:13px;color:var(--text-sub);line-height:1.6">归档不删数据。名下钥匙会转成「未分配」，可以再认领。</div>
    </div></div>`,
  '34-merge': () => `<div class="card" style="margin-top:12px"><div class="cardlink">将迁移<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.compare([['主档钥匙',4,6,'#5E5CE6'],['副档钥匙',2,6,'#FF3B30']])}</div>`,
  '41-applock': () => `<div class="card" style="margin-top:12px"><div class="cardlink">保护项<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0,'#FF9F0A','0/3','已启用')}
      <div style="flex:1">${V.compare([['打开 App',0,3,'rgba(255,255,255,.24)'],['敏感动作',0,3,'rgba(255,255,255,.24)'],['换机恢复',0,3,'rgba(255,255,255,.24)']])}</div>
    </div></div>`,
  '42-peek': () => `<div class="card" style="margin-top:12px"><div class="cardlink">防窥项<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0.4,'#0ADBD8','2/5','已启用')}
      <div style="flex:1;font-size:13px;color:var(--text-sub);line-height:1.6">分享遮半已开 · 其余四项还没启用</div>
    </div></div>`,
  '44-audit': () => `<div class="card" style="margin-top:12px;background:#132436">
    <div class="cardlink">近 14 天操作<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.bars([1,0,2,1,0,3,2,1,4,2,1,3,2,1],{h:44,a0:'10-10',a1:'10-14',a2:'10-18',a3:'10-23'})}</div>`,
  '45-destroy': () => `<div class="card" style="margin-top:12px"><div class="cardlink">三级销毁<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.steps(['删缓存','覆写台账','全盘覆写'],2,'#FF3B30')}</div>`,
  '46-safemode': () => `<div class="card" style="margin-top:12px"><div class="cardlink">验证强度<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.compare([['A 模式（单一验证）',1,2,'#30D158'],['B 模式（组合验证）',2,2,'#FF9F0A']])}</div>`,
  '47-backup': () => `<div class="card" style="margin-top:12px"><div class="cardlink">备份时效<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(88,0,'#FF9F0A','!','从未')}
      <div style="flex:1">${V.compare([['钥匙',0,13,'rgba(255,255,255,.24)'],['设置',0,8,'rgba(255,255,255,.24)']])}</div>
    </div></div>`,
  '48-export': () => `<div class="card" style="margin-top:12px"><div class="cardlink">历史导出<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.bars([2,1,3,0,2,4,1,2,5,3,1,2,4,2],{h:40,a0:'9月',a1:'10月',a2:'',a3:'现在'})}</div>`,
  '51-feed': () => `<div class="card" style="margin-top:12px;background:#0C1826">
    <div class="cardlink">今日时段<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    ${V.bars([0,0,0,0,0,1,3,4,1,0,0,1,0,0,0,0,0,2,1,0,0,0,0,0],{h:44})}</div>`,
  '61-reminders': () => `<div class="card" style="margin-top:12px"><div class="cardlink">生日填写<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:6px">
      ${V.ring(84,0,'#F11B51','0/5','已填')}
      <div style="flex:1;font-size:13px;color:var(--text-sub);line-height:1.6">格式 MM-dd，在「成员管理 → 补全信息」里填写</div>
    </div></div>`,
};

let n = 0;
for (const p of reg) {
  const fn = DATA[p.f];
  if (!fn) continue;
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  if (s.indexOf('<!--VIZ-->') >= 0) continue;   // 已注入
  // 插到第一个 .card 之前（作为数据主角），或 page 开头
  const block = '<!--VIZ-->\n  ' + fn() + '\n  ';
  if (/<div class="card"/.test(s)) {
    s = s.replace(/<div class="card"/, block + '<div class="card"');
  } else {
    s = s.replace(/(<div class="page[^"]*">)/, '$1\n  ' + block);
  }
  fs.writeFileSync(fp, s, 'utf8');
  n++;
}
console.log('✓ 注入数据主角 ' + n + ' 页');
