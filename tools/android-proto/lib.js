// tools/proto/lib.js —— 页面生成器共用片段
'use strict';
// ══ 规范 §3.4 强调色（语义绑定，不得混用）══
// 铁律：一屏 ≤3 种；一个数据系列颜色全 App 不变
const C = {
  blue:   '#0090FC',  // 数据主色、健康年龄
  pink:   '#F11B51',  // 心率、Move（3.98:1，仅 ≥18pt/Bold）
  red:    '#FF3B30',  // 告警
  coral:  '#FF694E',  // 睡眠分数（不是橙！）
  orange: '#FF9F0A',  // 警示、待机
  lime:   '#3CDE02',  // Exercise
  mint:   '#0ADBD8',  // 睡眠、Stand
  green:  '#30D158',  // 成功、正向
  indigo: '#5E5CE6',  // 渐变起点
  purple: '#BF5AF2',  // 冥想
  copper: '#D98B45',  // 品牌强调（外观工作室）
  grey:   '#8D8D93',  // 归档、禁用
};

const ICONS = {
  home:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.5 12 3l9 7.5"/><path d="M5.5 9.5V20h13V9.5"/></svg>',
  key:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="7.5" cy="12" r="3.5"/><path d="M11 12h9"/><path d="M17 12v3"/><path d="M20 12v2"/></svg>',
  device:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M10.5 5.5h3"/></svg>',
  people:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8.5" r="3.2"/><path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5"/><circle cx="17" cy="9.5" r="2.4"/><path d="M16 14.2c2.4.2 4.5 1.9 4.5 4.3"/></svg>',
  gear:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1.03 1.56V21a2 2 0 1 1-4 0v-.09a1.7 1.7 0 0 0-1.11-1.56 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.7 1.7 0 0 0 .34-1.87 1.7 1.7 0 0 0-1.56-1.03H3a2 2 0 1 1 0-4h.09A1.7 1.7 0 0 0 4.65 8.6a1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.7 1.7 0 0 0 1.87.34H9a1.7 1.7 0 0 0 1-1.56V3a2 2 0 1 1 4 0v.09a1.7 1.7 0 0 0 1.03 1.56 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.7 1.7 0 0 0-.34 1.87V9a1.7 1.7 0 0 0 1.56 1H21a2 2 0 1 1 0 4h-.09a1.7 1.7 0 0 0-1.51 1z"/></svg>',
};
const TABS = [['home','门厅'],['key','钥匙'],['device','设备'],['people','成员'],['gear','系统']];
const TABFILES = ['01-home','02-keys','03-devices','04-members','05-system'];

const tabbar = (a) => '<div class="tabbar">\n' + TABS.map(([k,t],i)=>
  `<a class="tab${i===a?' on':''}" href="${TABFILES[i]}.html">${ICONS[k]}<span>${t}</span></a>`).join('\n') + '\n</div>';

// 小分段环
// 小分段环（图 2 胶囊内的三色环）
// 关键：每段**起点按累计比例旋转**，段间留 6% 缺口
const ring = (segs) => {
  const r=9, w=4, c=13, circ=2*Math.PI*r;
  const GAP = 0.06;   // 段间缺口（占整圈比例）
  let acc = 0;
  const arcs = segs.map(([col,p]) => {
    const rot = -90 + acc*360;
    const d = `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${col}"
      stroke-width="${w}" stroke-linecap="round"
      stroke-dasharray="${Math.max(1, circ*p - 2).toFixed(2)} ${circ.toFixed(2)}"
      transform="rotate(${rot.toFixed(1)} ${c} ${c})"/>`;
    acc += p + GAP;
    return d;
  }).join('');
  return `<svg class="ringico" viewBox="0 0 26 26">
    <circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="${w}"/>${arcs}</svg>`;
};

// 圆环图（任意直径）
// 环形图：支持中心文字（图 2 的睡眠环中心是白色「53」）
// 图 2 实测：三段之间有**明显缺口**（每段首尾各缩 3-4°）
const donut = (size, segs, center='') => {
  const c=size/2, r=c-size*0.09, w=size*0.115, circ=2*Math.PI*r;
  // 缺口：按段数均分，每段两端各让 2.5%
  const gap = segs.length > 1 ? 0.025 : 0;
  let acc = 0;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="${w}"/>` +
  segs.map(([col,p])=>{
    const s=`<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${Math.max(1,circ*p-2)} ${circ}" transform="rotate(${-90+acc*360} ${c} ${c})"/>`;
    acc += p + gap; return s; }).join('') +
  (center ? `<text x="${c}" y="${c+size*0.085}" text-anchor="middle" font-size="${size*0.26}" font-weight="700" fill="#FFF" font-family="system-ui,-apple-system">${center}</text>` : '') +
  '</svg>';
};

// 同心三环（§7.8 形态3）
const tripleRing = (size, a=0.62, b=0.55, c=0.5, center='') => {
  // 图 2 的卡内三环：细环（线宽 ≈ size×0.045），间隙明显，中心可放数字
  const C = size/2;
  const W = size * 0.045;                     // 细环
  const R1 = C - W*0.5 - size*0.012;          // 外
  const R2 = R1 - W - size*0.055;             // 中
  const R3 = R2 - W - size*0.055;             // 内
  const g = (r, col, p) => {
    const circ = 2*Math.PI*r;
    return `<circle cx="${C}" cy="${C}" r="${r}" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="${W}"/>` +
           `<circle cx="${C}" cy="${C}" r="${r}" fill="none" stroke="${col}" stroke-width="${W}" stroke-linecap="round" ` +
           `stroke-dasharray="${(circ*p).toFixed(1)} ${circ.toFixed(1)}" transform="rotate(-90 ${C} ${C})"/>`;
  };
  const inner = center
    ? `<circle cx="${C}" cy="${C}" r="${(R3-W*1.6).toFixed(1)}" fill="#0A0A0C"/>` +
      `<text x="${C}" y="${C}" text-anchor="middle" dominant-baseline="central" ` +
      `font-size="${(size*0.22).toFixed(0)}" font-weight="700" fill="#FFF" ` +
      `font-family="system-ui,-apple-system" style="font-variant-numeric:tabular-nums">${center}</text>`
    : '';
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="flex:0 0 auto">` +
    g(R1,'#F11B51',a) + g(R2,'#3CDE02',b) + g(R3,'#0ADBD8',c) + inner + `</svg>`;
};

// 页面壳
const page = (title, body, active, opts={}) => `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>${title}</title><link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="pages.css"></head><body>
<div class="phone">${opts.nav ? navbar(title, opts.back||'01-home', opts.right||'') : ''}<div class="scroll"><div class="page${opts.nav?' hasnav':''}">
${body}
</div></div>${opts.tabbar === false ? '' : tabbar(active)}</div><script src="icons-render.js"></script><script src="interact.js"></script></body></html>`;

// 页面骨架（规范 §5.3）：页顶 40 → 胶囊行 → 29 → 大标题 → 74 → 首卡
// 不写在 page() 里是因为不是每页都有胶囊行与标题；
// 由调用方拼，但用这些 helper 保证数值只有一个来源。
const skel = {
  // 大标题块：LargeTitle 30/Bold + 副标 17/灰
  title: (t, sub) => `<div class="h1">${t}</div>` + (sub ? `<div class="sub">${sub}</div>` : ''),
  // 标题 → 首卡 74（扣掉下面 card 自带的 margin-bottom 12，再扣 title 的 10 行高）
  gap74: () => '<div style="height:calc(var(--title-to-card) - 34px)"></div>',
};

const navbar = (title, back, right) => `<div class="navbar">
  <a class="back" href="${back}.html">‹</a><span class="nt">${title}</span><span class="nr">${right}</span></div>`;

// 可点行
const row = (href, icon, iconBg, iconColor, title, sub, right='') => `<a class="rw" href="${href}.html">
  <div class="ic" style="background:${iconBg};color:${iconColor}">${icon}</div>
  <div class="tx"><div class="tt">${title}</div>${sub?`<div class="sb">${sub}</div>`:''}</div>
  ${right}<div class="ch">›</div></a>`;

// 数据行
const drow = (color, value, unit) => `<div class="drow"><span class="dot" style="background:${color}"></span><span class="dv">${value}${unit?`<span class="du">${unit}</span>`:''}</span></div>`;

module.exports = { C, skel, ICONS, TABS, tabbar, ring, donut, tripleRing, page, navbar, row, drow };
