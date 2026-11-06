#!/usr/bin/env node
// primitives.js —— 与 SwiftUI 组件一一对应的 HTML 原语（视觉验收台专用）。
'use strict';

const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const primitives = {
  kicker: (t) => `<div class="kicker">${esc(t)}</div>`,
  serif: (t, size = 44) => `<div class="serif" style="font-size:${size}px">${t}</div>`,

  pane: (inner, h = 330, cls = '') =>
    `<div class="pane ${cls}" style="height:${h}px">
       <div class="sky"></div><div class="blob a"></div><div class="blob b"></div><div class="streak"></div>
       <div class="inner" style="height:100%;display:flex;flex-direction:column">${inner}</div>
       <div class="edge"></div>
     </div>`,

  hero: (paneHtml, lensHtml, extra = '') =>
    `<div class="hero" style="position:relative;margin-top:6px">
       ${paneHtml}
       ${lensHtml ? `<div style="position:absolute;left:50%;bottom:-56px;transform:translateX(-50%)">${lensHtml}</div>` : ''}
       ${extra}
     </div>`,

  lens: (state = 'idle', progress = 0, label = '轻点开锁') => {
    const cls = state === 'busy' ? 'lensbusy' : state === 'fail' ? 'lensfail' : '';
    const lock = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="5.5" y="10.5" width="13" height="9.5" rx="2.6"/><path d="M8.6 10.5V8a3.4 3.4 0 016.8 0v2.5"/></svg>';
    const glyph = state === 'busy' ? '<span style="width:7px;height:7px;border-radius:50%;background:#FFF9EE;display:block"></span>'
      : state === 'fail' ? '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M6 6l12 12M18 6L6 18"/></svg>' : lock;
    const word = state === 'busy' ? '正在开锁' : state === 'fail' ? '没打开' : label;
    return `<div class="lens ${cls}" style="--p:${progress}%"><div class="ring"></div><div class="core"></div><div class="glyph">${glyph}</div><div class="word">${esc(word)}</div></div>`;
  },

  readings: (items) =>
    `<div class="readings">${items.map((it) =>
      `<div class="r"><div class="k">${esc(it.k)}</div><div class="v">${it.v}${it.u ? `<span class="u">${esc(it.u)}</span>` : ''}</div></div>`).join('')}</div>`,

  row: (o = {}) => {
    const kind = o.kind === 'cool' ? ' cool' : o.kind === 'red' ? ' red' : '';
    const icon = o.icon ? `<div class="tile${kind}">${o.icon}</div>` : '';
    const trail = o.trail ? `<div class="trail">${o.trail}</div>` : '';
    const chev = o.chev ? `<div class="chev">&#8250;</div>` : '';
    const sub = o.sub ? `<div class="s">${o.sub}</div>` : '';
    return `<div class="row">${icon}<div class="main"><div class="t">${o.title}</div>${sub}</div>${trail}${chev}</div>`;
  },

  section: (n, title, trailing = '') =>
    `<div class="sect"><span class="n">${esc(n)}</span><span class="t">${esc(title)}</span><span class="rule"></span>${trailing ? `<span class="kicker">${esc(trailing)}</span>` : ''}</div>`,

  chips: (items) => `<div class="chips">${items.map((c) =>
    `<div class="chip${c.on ? ' on' : ''}"><span class="g">${c.icon || ''}</span>${esc(c.title)}</div>`).join('')}</div>`,

  events: (items) => `<div class="rail">${items.map((e) =>
    `<div class="ev${e.tone === 'calm' ? ' calm' : e.tone === 'bad' ? ' bad' : ''}">
       <div class="time">${esc(e.time)}</div>
       <div class="t" style="padding-right:56px">${esc(e.title)}</div>
       <div class="s">${esc(e.sub || '')}</div>
     </div>`).join('')}</div>`,

  dayLabel: (t) => `<div class="daylabel">${esc(t)}</div>`,

  badge: (t, kind = '') => `<span class="badge ${kind}">${esc(t)}</span>`,

  seg: (items, on) => `<div class="seg">${items.map((t, i) => `<div class="s${i === on ? ' on' : ''}">${esc(t)}</div>`).join('')}</div>`,

  field: (ph, icon = '&#9906;') => `<div class="fieldInput"><span style="color:var(--ink3);font-size:14px">${icon}</span><span class="ph">${esc(ph)}</span></div>`,

  btn: (t, kind = '') => `<div class="btn ${kind}">${t}</div>`,

  hair: () => '<div class="hair"></div>',
  hairStrong: () => '<div class="hairStrong"></div>',
};

module.exports = { P: primitives, esc };
