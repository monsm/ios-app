#!/usr/bin/env node
// screens.js —— 每一屏的 1:1 视觉镜像。与 SwiftUI 页面同构。
'use strict';
const { P, esc } = require('./primitives.js');

const I = {
  today: '<svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="4.2"/><path d="M12 2.6v2.2M12 19.2v2.2M2.6 12h2.2M19.2 12h2.2M5.4 5.4l1.6 1.6M17 17l1.6 1.6M18.6 5.4L17 7M7 17l-1.6 1.6"/></svg>',
  access: '<svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8.2" cy="8.2" r="3.6"/><path d="M10.8 10.8L20 20M17.2 17.2l1.7-1.7M14.6 14.6l1.7-1.7"/></svg>',
  log: '<svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M4 6.5h16M4 12h16M4 17.5h10"/></svg>',
  lock: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="5" y="10" width="14" height="10" rx="2.5"/><path d="M8.5 10V7.5a3.5 3.5 0 017 0V10"/></svg>',
  plus: '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 5v14M5 12h14"/></svg>',
  search: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="10.5" cy="10.5" r="5.5"/><path d="M15 15l4.5 4.5"/></svg>',
  key: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="3.4"/><path d="M10.5 10.5L20 20M17 17l1.8-1.8M14.3 14.3l1.8-1.8"/></svg>',
  finger: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M6 11a6 6 0 0112 0v4M9 11a3 3 0 016 0v6M12 11v8M4 14v3"/></svg>',
  clock: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
  shield: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M12 3l7 3v6c0 4.2-3 7.4-7 9-4-1.6-7-4.8-7-9V6l7-3z"/></svg>',
  alert: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M12 4l8.5 15h-17L12 4z"/><path d="M12 9.5v4M12 16.4v.2"/></svg>',
  dots: '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg>',
  bell: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M6.5 9.5a5.5 5.5 0 0111 0c0 4 1.2 5.5 2 6.2H4.5c.8-.7 2-2.2 2-6.2z"/><path d="M10 19a2 2 0 004 0"/></svg>',
  sun: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="4"/><path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6L18 18M18 6l-1.4 1.4M7.4 16.6L6 18"/></svg>',
};

const head = (kicker, sub, right) => ({
  nav: `<div><div class="kicker" style="display:flex;align-items:center;gap:7px"><span style="width:5px;height:5px;border-radius:50%;background:var(--brass)"></span>${kicker}</div>` +
    `<div style="font-size:12.5px;color:var(--ink2);margin-top:5px">${sub}</div></div>`,
  trailing: right,
});

function hero(line, sub, state = 'idle', progress = 0, label = '轻点开锁') {
  const inner = `
    <div style="display:flex;justify-content:space-between;align-items:flex-start">
      <div class="kicker" style="color:var(--ink2);display:flex;align-items:center;gap:8px">
        <span style="width:4px;height:4px;border-radius:50%;background:var(--brass);display:inline-block"></span>THRESHOLD · 前门</div>
      <div class="mono" style="font-size:12px;color:var(--ink2)">20:41</div>
    </div>
    <div style="flex:1"></div>
    <div style="padding-bottom:2px">
      <div class="serif" style="font-size:46px">${line}</div>
      <div style="font-size:13px;color:var(--ink2);margin-top:11px;letter-spacing:.1px">${sub}</div>
    </div>
    <div style="height:62px"></div>`;
  const pane = `<div class="pane" style="height:336px">
      <div class="sky"></div><div class="blob a"></div><div class="blob b"></div><div class="streak"></div>
      <div class="inner" style="height:100%;display:flex;flex-direction:column">${inner}</div>
      <div style="position:absolute;left:26px;right:26px;bottom:0;height:.5px;z-index:7;background:linear-gradient(90deg,transparent,var(--hairStrong),transparent)"></div>
      <div class="edge"></div>
    </div>`;
  return `<div style="position:relative;margin-top:4px">
      ${pane}
      <div style="position:absolute;left:50%;bottom:-58px;transform:translateX(-50%)">${P.lens(state, progress, label)}</div>
    </div>`;
}

const readings = (items) => `<div class="readings">${items.map((it) =>
  `<div class="r"><div class="k">${esc(it.k)}</div><div class="v">${it.v}${it.u ? `<span class="u">${it.u}</span>` : ''}</div></div>`).join('')}</div>`;

const tray = (items) => `<div class="tray glass">${items.map((it) =>
  `<div class="it"><span class="g">${it.icon}</span>${esc(it.title)}</div>`).join('')}</div>`;

function strip(bars) {
  const ticks = bars.map((b) => {
    const left = (b.at / 24) * 100;
    const h = Math.max(5, b.v * 3.4);
    return `<div class="tick${b.bad ? ' bad' : ''}" style="left:${left}%;height:${h}px"></div>`;
  }).join('');
  const labels = ['00', '06', '12', '18', '24'].map((t, i) =>
    `<div class="lab" style="left:${(i * 25)}%;transform:translateX(${i === 0 ? '0' : i === 4 ? '-100%' : '-50%'})">${t}</div>`).join('');
  return `<div class="strip"><div class="base"></div>${ticks}${labels}</div>`;
}

const SCREENS = [
  {
    id: 'today', name: '今日 · 就绪', tab: 0,
    ...head('前门 · 已连接', '晚上好，林知', '<div class="avatar">林</div>'),
    body: `
      ${hero('一切如常。', '上次开门 18:42 · 妈妈 · 指纹')}
      <div style="height:104px"></div>
      ${readings([{ k: '电量', v: '76', u: '%' }, { k: '信号', v: '满', u: '−52 dBm' }, { k: '固件', v: '1.4.2' }])}
      <div style="height:20px"></div>
      ${tray([{ title: '临时码', icon: I.clock }, { title: '布防', icon: I.shield }, { title: '静音', icon: I.bell }, { title: '成员', icon: I.key }])}
      ${P.section('01', '最近', '全部')}
      ${P.events([
        { time: '18:42', title: '指纹开锁', sub: '妈妈 · 前门' },
        { time: '12:09', title: '密码开锁', sub: '林知 · 前门' },
        { time: '08:15', title: '临时码开锁', sub: '访客 · 保洁阿姨' },
      ])}
`,
  },
  {
    id: 'today-busy', name: '今日 · 开锁中', tab: 0,
    ...head('前门 · 正在连接', '晚上好，林知', '<div class="avatar">林</div>'),
    body: `
      ${hero('稍等。', '正在把门打开 · 第 2 / 3 步', 'busy', 62, '')}
      <div style="height:104px"></div>
      ${readings([{ k: '电量', v: '76', u: '%' }, { k: '信号', v: '满', u: '−52 dBm' }, { k: '固件', v: '1.4.2' }])}
      <div style="height:20px"></div>
      <div class="glass" style="border-radius:20px;padding:15px 17px;display:flex;gap:12px;align-items:center">
        <div class="tile cool" style="width:34px;height:34px">${I.lock}</div>
        <div style="flex:1"><div style="font-size:14px;font-weight:500">已下发开锁命令</div><div class="note" style="margin-top:2px">正在等门锁回执 · 不要离开</div></div>
        <div class="mono" style="font-size:11px;color:var(--ink3)">2.1s</div>
      </div>
      ${P.section('01', '最近', '全部')}
      ${P.events([
        { time: '18:42', title: '指纹开锁', sub: '妈妈 · 前门' },
        { time: '12:09', title: '密码开锁', sub: '林知 · 前门' },
      ])}
`,
  },
  {
    id: 'today-empty', name: '今日 · 未配锁', tab: 0,
    ...head('还没有门锁', '从这里开始', '<div class="avatar">林</div>'),
    body: `
      <div style="height:20px"></div>
      ${P.pane(`
        <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:14px">
          <div class="serif" style="font-size:42px">先连上<br>你的门锁。</div>
          <div style="font-size:13.5px;color:var(--ink2);line-height:1.65;max-width:290px">把门锁恢复到配网状态，手机靠近它，按下一步。整个过程不需要网络。</div>
        </div>
        <div style="display:flex;gap:10px;margin-bottom:8px"><div class="btn" style="flex:1">开始配对</div></div>`, 396)}
      <div style="height:30px"></div>
      ${P.section('01', '配对之后')}
      ${P.row({ icon: I.key, title: '凭证', sub: '密码、指纹、临时码，一处管完', chev: true })}
      ${P.row({ icon: I.log, title: '记录', sub: '谁在什么时候开过门', chev: true })}
      ${P.row({ icon: I.shield, title: '安全', sub: '本机密码、布防、自动开门', chev: true })}
`,
  },
  {
    id: 'access', name: '通行 · 凭证', tab: 1,
    ...head('通行', '12 枚在册 · 2 枚临期', `<div style="display:flex;gap:14px;align-items:center"><span style="color:var(--ink2)">${I.search}</span><span style="color:var(--brass)">${I.plus}</span></div>`),
    body: `
      <div style="margin:8px 0 2px">${P.seg(['凭证', '成员', '手机钥匙'], 0)}</div>
      <div class="serif" style="font-size:36px;margin:24px 0 8px">两枚钥匙<br>这周到期。</div>
      <div style="font-size:13px;color:var(--ink2);margin-bottom:20px">「保洁」「快递柜」用了 28 天，剩下 2 天。</div>
      ${P.field('搜名字、成员或到期时间', I.search)}
      ${P.section('01', '临期', '2')}
      ${P.row({ icon: I.clock, title: '保洁阿姨', sub: '临时码 · 周四到期 · 09:00–11:00', trail: P.badge('剩 2 天', 'red'), chev: true })}
      ${P.row({ icon: I.clock, title: '快递柜', sub: '临时码 · 周六到期', trail: P.badge('剩 5 天'), chev: true })}
      ${P.section('02', '全部凭证', '12')}
      ${P.row({ icon: I.key, title: '前门密码', sub: '林知 · 长期有效', trail: '•••• 4', chev: true })}
      ${P.row({ icon: I.finger, title: '妈妈的指纹', sub: '妈妈 · 已录入 126 天', trail: '右手拇指', chev: true })}
      ${P.row({ icon: I.key, title: '书房密码', sub: '未归属 · 长期有效', trail: '•••• 2', chev: true })}
`,
  },
  {
    id: 'credential', name: '凭证 · 详情', tab: 1,
    nav: `<div class="kicker">通行 / 凭证</div>`,
    trailing: `<span style="color:var(--ink2)">${I.dots}</span>`,
    body: `
      <div style="height:6px"></div>
      <div class="pane" style="height:268px">
        <div class="sky"></div><div class="blob a"></div><div class="blob b"></div><div class="streak"></div>
        <div class="inner" style="height:100%;display:flex;flex-direction:column;justify-content:space-between">
          <div style="display:flex;justify-content:space-between;align-items:flex-start">
            <div class="kicker" style="color:var(--ink2)">临时码 · 保洁阿姨</div>
            ${P.badge('有效')}
          </div>
          <div>
            <div class="mono" style="font-size:34px;letter-spacing:7px;color:var(--ink)">••••••</div>
            <div style="font-size:12.5px;color:var(--ink2);margin-top:9px">长按显示 · 复制后 90 秒自动清除</div>
          </div>
          <div style="display:flex;gap:10px">
            <div class="chip" style="flex:1;justify-content:center">显示</div>
            <div class="chip" style="flex:1;justify-content:center">复制</div>
          </div>
        </div>
        <div class="edge"></div>
      </div>
      <div style="height:28px"></div>
      ${readings([{ k: '生效', v: '6/2', u: ' 09:00' }, { k: '到期', v: '6/5', u: ' 11:00' }, { k: '已用', v: '4', u: ' 次' }])}
      ${P.section('01', '归属')}
      ${P.row({ icon: '保', title: '保洁阿姨', sub: '访客 · 每周四 09:00–11:00', kind: 'cool', chev: true })}
      ${P.section('02', '更多')}
      ${P.row({ title: '修改有效期', chev: true })}
      ${P.row({ title: '停用这枚凭证', chev: true })}
      ${P.row({ title: '删除', chev: true, trail: '<span style="color:var(--danger)">不可恢复</span>' })}
`,
  },
  {
    id: 'log', name: '记录 · 今天', tab: 2,
    ...head('记录', '今天 · 7 次', `<span style="color:var(--ink2)">${I.search}</span>`),
    body: `
      <div class="serif" style="font-size:38px;margin:20px 0 7px">今天有人<br>来过。</div>
      <div style="font-size:13px;color:var(--ink2);margin-bottom:16px">7 次开门 · 3 位家人 · 没有异常</div>
      ${strip([{ at: 1.2, v: 1 }, { at: 7.4, v: 4 }, { at: 9.1, v: 1 }, { at: 16.7, v: 10 }, { at: 20.4, v: 2 }])}
      ${P.dayLabel('TODAY · 6 月 2 日')}
      ${P.events([
        { time: '18:42', title: '指纹开锁', sub: '妈妈 · 前门' },
        { time: '17:20', title: '密码开锁', sub: '林知 · 前门' },
        { time: '12:09', title: '临时码开锁', sub: '保洁阿姨 · 前门' },
        { time: '12:07', title: '密码连续错误', sub: '前门 · 键盘锁定 30 秒', tone: 'bad' },
        { time: '08:15', title: '密码开锁', sub: '林知 · 前门', tone: 'calm' },
      ])}
`,
  },
  {
    id: 'settings', name: '设置 · 索引', tab: 3,
    ...head('设置', '林知 · 一个家', '<div class="avatar">林</div>'),
    body: `
      <div style="height:8px"></div>
      <div class="serif" style="font-size:34px">家，<br>和它的边界。</div>
      <div style="height:26px"></div>
      ${P.section('01', '我的家')}
      ${P.row({ icon: I.lock, title: '前门', sub: 'KX 系列 · 已连接 · 固件 1.4.2', chev: true })}
      ${P.row({ icon: '3', title: '成员与分工', sub: '3 位成员 · 本周妈妈值班', kind: 'cool', chev: true })}
      ${P.row({ icon: I.shield, title: '安全', sub: '本机密码已设 · 布防未开启', chev: true })}
      ${P.section('02', '设备与工具')}
      ${P.row({ icon: I.key, title: '自动开门', sub: '关闭 · 靠近时自动解锁', chev: true })}
      ${P.row({ icon: I.clock, title: '钥匙串与网关', sub: '未绑定硬件', chev: true })}
      ${P.row({ icon: I.alert, title: '维护与诊断', sub: '固件、校时、协议测试', chev: true })}
      ${P.section('03', '数据')}
      ${P.row({ icon: '↧', title: '备份与恢复', sub: '上次备份 3 天前 · 已加密', kind: 'cool', chev: true })}
      ${P.row({ icon: I.sun, title: '外观', sub: '日光 · 自动明暗', kind: 'cool', chev: true })}
`,
  },
];

module.exports = { SCREENS, I };
