// tools/proto/icons-render.js —— 把 <span class="svgi" data-i="name"> 渲染成 SVG
(function () {
// tools/proto/icons.js —— SF Symbols 风格的线性图标（替代 emoji）
//
// **为什么必须换掉 emoji**：6 张参考图里**一个 emoji 都没有**。
// Apple 的界面语言是 SF Symbols —— 单色线性图标，跟随文字颜色，
// 在深色底上保持同一灰度层级。emoji 是彩色的、自带明度、
// 每个形状的笔画粗细都不一样 —— 一屏放三个以上就散架。
const S = (d, extra) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
  stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"${extra||''}>${d}</svg>`;

const I = {
  // 锁与钥匙
  lock:      S('<rect x="5" y="10.5" width="14" height="10.5" rx="2.6"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>'),
  lockOpen:  S('<rect x="5" y="10.5" width="14" height="10.5" rx="2.6"/><path d="M8 10.5V7.5a4 4 0 0 1 7.8-1.2"/>'),
  key:       S('<circle cx="8" cy="12" r="3.6"/><path d="M11.6 12H21"/><path d="M17.5 12v3.2"/><path d="M20.4 12v2.2"/>'),
  shield:    S('<path d="M12 3 5 6v5.2c0 4 2.8 7.6 7 9.8 4.2-2.2 7-5.8 7-9.8V6z"/>'),
  shieldCheck: S('<path d="M12 3 5 6v5.2c0 4 2.8 7.6 7 9.8 4.2-2.2 7-5.8 7-9.8V6z"/><path d="M9 12l2.2 2.2L15.4 10"/>'),
  // 人
  person:    S('<circle cx="12" cy="8" r="3.6"/><path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6"/>'),
  people:    S('<circle cx="9" cy="8.5" r="3.2"/><path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5"/><circle cx="17" cy="9.5" r="2.4"/><path d="M16 14.2c2.4.2 4.5 1.9 4.5 4.3"/>'),
  personPlus:S('<circle cx="10" cy="8" r="3.4"/><path d="M3.5 19c0-3.4 2.9-5.6 6.5-5.6 1 0 2 .2 2.8.5"/><path d="M17.5 14v6M14.5 17h6"/>'),
  // 设备
  phone:     S('<rect x="7" y="2.5" width="10" height="19" rx="2.6"/><path d="M10.6 5.5h2.8"/>'),
  wifi:      S('<path d="M4 9.5a13 13 0 0 1 16 0"/><path d="M7 13a9 9 0 0 1 10 0"/><path d="M10 16.4a4.6 4.6 0 0 1 4 0"/><circle cx="12" cy="19.5" r="1" fill="currentColor"/>'),
  signal:    S('<path d="M4 17h2.2M9 17h2.2M14 17h2.2M19 17h2.2" opacity="0"/><path d="M4 20v-3M9.3 20v-6M14.6 20v-9M20 20v-12"/>', ' stroke-width="2.4"'),
  cpu:       S('<rect x="6.5" y="6.5" width="11" height="11" rx="2"/><path d="M10 3v3M14 3v3M10 18v3M14 18v3M3 10h3M3 14h3M18 10h3M18 14h3"/>'),
  // 时间
  clock:     S('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 1.8"/>'),
  calendar:  S('<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>'),
  timer:     S('<circle cx="12" cy="13" r="7.5"/><path d="M12 9.5V13l2.4 1.4M9.5 2.5h5"/>'),
  // 动作
  plus:      S('<path d="M12 5v14M5 12h14"/>'),
  arrowUp:   S('<path d="M12 19V5M6 11l6-6 6 6"/>'),
  arrowDown: S('<path d="M12 5v14M6 13l6 6 6-6"/>'),
  arrowRight:S('<path d="M5 12h14M13 6l6 6-6 6"/>'),
  chevron:   S('<path d="M9 6l6 6-6 6"/>'),
  search:    S('<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>'),
  copy:      S('<rect x="8.5" y="8.5" width="11" height="11" rx="2"/><path d="M15.5 5.5h-9a2 2 0 0 0-2 2v9"/>'),
  eye:       S('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.8"/>'),
  eyeOff:    S('<path d="M4 4l16 16"/><path d="M9.9 5.9A9.6 9.6 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-3 3.7"/><path d="M6.4 7.4A17 17 0 0 0 2.5 12S6 18.5 12 18.5c1.4 0 2.7-.3 3.8-.9"/>'),
  trash:     S('<path d="M4.5 6.5h15M9 6.5V4h6v2.5M6.5 6.5l1 13h9l1-13"/><path d="M10.5 10v6M13.5 10v6"/>'),
  gear:      S('<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M4.2 7l2.6 1.5M17.2 15.5l2.6 1.5M4.2 17l2.6-1.5M17.2 8.5l2.6-1.5"/>'),
  doc:       S('<path d="M6.5 3.5h7L18 8v12.5H6.5z"/><path d="M13 3.5V8h5"/>'),
  folder:    S('<path d="M3.5 6.5h6l2 2.5h9v10h-17z"/>'),
  archive:   S('<rect x="3.5" y="4.5" width="17" height="4" rx="1"/><path d="M5 8.5v11h14v-11"/><path d="M9.5 12.5h5"/>'),
  chart:     S('<path d="M4 20V10M9.3 20V6M14.6 20v-7M20 20V9"/>'),
  list:      S('<path d="M8 6.5h12M8 12h12M8 17.5h12"/><circle cx="4.2" cy="6.5" r="1.1" fill="currentColor"/><circle cx="4.2" cy="12" r="1.1" fill="currentColor"/><circle cx="4.2" cy="17.5" r="1.1" fill="currentColor"/>'),
  star:      S('<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.8-5.2-2.8-5.2 2.8 1-5.8L3.5 9.7l5.9-.8z"/>'),
  heart:     S('<path d="M12 20s-7.5-4.7-7.5-9.5A4.3 4.3 0 0 1 12 7.6a4.3 4.3 0 0 1 7.5 2.9C19.5 15.3 12 20 12 20z"/>'),
  battery:   S('<rect x="2.5" y="8" width="16" height="8" rx="2"/><path d="M20.5 10.5v3"/><rect x="4.5" y="10" width="7" height="4" rx="1" fill="currentColor" stroke="none"/>'),
  house:     S('<path d="M3.5 10.5 12 3.5l8.5 7"/><path d="M6 9.5V20h12V9.5"/>'),
  warn:      S('<path d="M12 3.5 21 19H3z"/><path d="M12 9.5v4.5"/><circle cx="12" cy="16.8" r=".9" fill="currentColor"/>'),
  info:      S('<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/><circle cx="12" cy="8" r=".9" fill="currentColor"/>'),
  check:     S('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  xmark:     S('<path d="M6 6l12 12M18 6L6 18"/>'),
  export:    S('<path d="M12 15V4M8 8l4-4 4 4"/><path d="M4.5 14v4.5a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5V14"/>'),
  db:        S('<ellipse cx="12" cy="6.5" rx="7.5" ry="3"/><path d="M4.5 6.5v11c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3v-11"/><path d="M4.5 12c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3"/>'),
  refresh:   S('<path d="M20 12a8 8 0 1 1-2.4-5.7"/><path d="M20 4v4.5h-4.5"/>'),
  fingerprint: S('<path d="M12 4.5a7.5 7.5 0 0 0-7.5 7.5c0 1.6.3 3 .9 4.3"/><path d="M12 7.5A4.5 4.5 0 0 0 7.5 12c0 2.4.5 4.6 1.4 6.6"/><path d="M12 10.5a1.5 1.5 0 0 0-1.5 1.5c0 3 .7 5.6 1.9 8"/><path d="M14.4 12.6c0 2.8-.5 5.3-1.5 7.5"/><path d="M17 12c0 2.5-.4 4.8-1.2 6.9"/><path d="M19.5 12c0 1.8-.2 3.5-.7 5.1"/>'),
  ring:      S('<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="3.5" stroke-dasharray="1 3"/>'),
  qrcode:    S('<rect x="3.5" y="3.5" width="6.5" height="6.5" rx="1"/><rect x="14" y="3.5" width="6.5" height="6.5" rx="1"/><rect x="3.5" y="14" width="6.5" height="6.5" rx="1"/><path d="M14 14h2.5v2.5H14zM18 18h2.5v2.5H18z"/>'),
};

// 带容器的图标徽章
const badge = (name, color, size) => {
  const s = size || 34;
  return `<div style="width:${s}px;height:${s}px;border-radius:${Math.round(s*0.3)}px;
    background:${color}22;display:flex;align-items:center;justify-content:center;
    flex:0 0 auto"><span style="width:${Math.round(s*0.56)}px;height:${Math.round(s*0.56)}px;
    color:${color};display:block">${I[name]||I.info}</span></div>`;
};

  var CSS = 'display:inline-block;vertical-align:-0.14em;color:inherit;flex:0 0 auto';
  function paint() {
    document.querySelectorAll('.svgi').forEach(function (el) {
      if (el.dataset.done) return;
      var name = el.dataset.i;
      var svg = I[name];
      if (!svg) { el.textContent = '·'; el.dataset.done = '1'; return; }
      el.innerHTML = svg;
      var sz = el.dataset.sz || '1.15em';
      el.style.cssText = CSS + ';width:' + sz + ';height:' + sz;
      el.dataset.done = '1';
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', paint);
  else paint();
})();
