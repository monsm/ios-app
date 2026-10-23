'use strict';
// tools/proto/viz.js —— 页面"数据主角"组件库
//
// 为什么需要：参考图的每一屏都有**一个数据可视化主角**（§0 总则 3）。
// 我此前 21 页只有文字列表 —— 数据没有"被看见"，这是 45% 的主因。
//
// 五种形态全部来自参考图实测：
//   ring    环形（图 2 睡眠环 / 图 5 Activity Rings）
//   bars    柱状（图 5 Step Count 的 24 根细柱 + 时间轴）
//   steps   进度条（图 4 的三级销毁那种）
//   compare 双条对比（图 2 的 30/70 cal 那种比例条）
//   gauge   双向刻度（图 1 的 -4.7 / 20.4 对照）

// ── ring：环形 + 中心大数字 + 下方 label（图 2 形态）──
const ring = (size, pct, color, center, label, track) => {
  const c = size/2, r = c - size*0.09, w = size*0.115, circ = 2*Math.PI*r;
  const lit = circ * Math.max(0.001, Math.min(1, pct));
  return `<div style="position:relative;width:${size}px;height:${size}px;flex:0 0 auto">
  <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
    <circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${track||'rgba(255,255,255,.08)'}" stroke-width="${w}"/>
    <circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${color}" stroke-width="${w}"
      stroke-linecap="round" stroke-dasharray="${lit} ${circ}" transform="rotate(-90 ${c} ${c})"/>
  </svg>
  <div style="position:absolute;inset:0;display:flex;flex-direction:column;
    align-items:center;justify-content:center">
    <div style="font-size:${Math.round(size*0.26)}px;font-weight:700;color:#FFF;
      font-variant-numeric:tabular-nums;line-height:1">${center}</div>
    ${label?`<div style="font-size:${Math.min(11, Math.round(size*0.075))}px;color:#8D8D93;margin-top:${Math.round(size*0.03)}px;max-width:${Math.round(size*0.62)}px;text-align:center;line-height:1.3">${label}</div>`:''}
  </div></div>`;
};

// ── bars：24 根细柱 + 时间轴（图 5 形态）──
const bars = (series, opts) => {
  const o = opts || {};
  const hi = Math.max(...series, 1);
  const cols = series.map(v => {
    const h = Math.max(3, Math.round(v/hi*100));
    const isHi = v/hi > 0.6;
    return `<i${isHi?' class="hi"':''} style="height:${h}%"></i>`;
  }).join('');
  return `<div class="mchart" style="height:${o.h||44}px">${cols}</div>` +
    (o.axis === false ? '' :
    `<div class="maxis"><span>${o.a0||'12AM'}</span><span>${o.a1||'6AM'}</span><span>${o.a2||'12PM'}</span><span>${o.a3||'6PM'}</span></div>`);
};

// ── steps：水平分段进度（图 4 三级销毁）──
const steps = (labels, active, color) => {
  return '<div style="display:flex;gap:8px;margin-top:14px">' + labels.map((l,i)=>`
    <div style="flex:1;text-align:center">
      <div style="height:5px;border-radius:3px;background:${i<active?color:'rgba(255,255,255,.10)'}"></div>
      <div style="font-size:12px;color:${i<active?color:'#6A6A6E'};margin-top:9px;font-weight:${i<active?600:400}">${l}</div>
    </div>`).join('') + '</div>';
};

// ── compare：双条对比（图 2 的 30/70 比例）──
const compare = (rows) => {
  return '<div style="display:flex;flex-direction:column;gap:12px;margin-top:6px">' +
    rows.map(([label, val, max, color])=>`
    <div>
      <div style="display:flex;justify-content:space-between;font-size:13px;margin-bottom:6px">
        <span style="color:#8D8D93">${label}</span>
        <span style="color:#FFF;font-weight:600;font-variant-numeric:tabular-nums">${val}</span>
      </div>
      <div style="height:5px;border-radius:3px;background:rgba(255,255,255,.08)">
        <div style="height:5px;border-radius:3px;background:${color};width:${Math.min(100,Math.round(val/max*100))}%"></div>
      </div>
    </div>`).join('') + '</div>';
};

// ── gauge：双向刻度（图 1 的 -4.7 那种）──
const gauge = (value, min, max, color, unit) => {
  const range = max - min;
  const pos = Math.max(0, Math.min(1, (value - min)/range));
  return `<div style="margin-top:14px">
    <div style="position:relative;height:6px;border-radius:3px;background:rgba(255,255,255,.08)">
      <div style="position:absolute;left:${Math.round(pos*100)}%;top:-5px;width:3px;height:16px;
        border-radius:2px;background:${color};transform:translateX(-50%)"></div>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:11px;color:#6A6A6E;margin-top:8px">
      <span>${min}${unit||''}</span><span>${max}${unit||''}</span>
    </div></div>`;
};

module.exports = { ring, bars, steps, compare, gauge };
