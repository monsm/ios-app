// primitives.js —— 每个函数镜像一个 Swift 组件。改这里等于改所有镜像屏。
'use strict';
const H = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt').replace(/>/g, '&gt;');

const panel = (inner) => '<section class="panel">' + inner + '</section>';
const inset = (inner) => '<section class="inset">' + inner + '</section>';
const sectionLabel = (text, trailing) => '<div class="slabel"><span>' + H(text) + '</span>' + (trailing ? '<em>' + H(trailing) + '</em>' : '') + '</div>';
const reading = (value, unit, size, tint, weight) =>
  '<span class="reading" style="font-size:' + (size || 'var(--f-reading)') + ';color:' + (tint || 'var(--ink)') + ';font-weight:' + (weight || 500) + '">' + H(value) + (unit ? '<i>' + H(unit) + '</i>' : '') + '</span>';
const fieldRow = (label, value, unit, tint) =>
  '<div class="frow"><span>' + H(label) + '</span>' + reading(value, unit, 'var(--f-body)', tint) + '</div>';
const readingGrid = (items, cols) => {
  const c = cols || 2;
  const rows = [];
  for (let i = 0; i < items.length; i += c) rows.push(items.slice(i, i + c));
  return rows.map((r, ri) => (ri ? '<hr class="hair">' : '') +
    '<div class="rgrid" style="grid-template-columns:repeat(' + c + ',1fr)">' +
    r.map((it) => '<div><span class="cap">' + H(it.label) + '</span>' + reading(it.value, it.unit, '22px', it.tint || 'var(--ink)') + '</div>').join('') +
    (r.length < c ? '<div></div>'.repeat(c - r.length) : '') + '</div>').join('');
};
const dot = (tone, word) => '<span class="dot t-' + tone + '" role="img" aria-label="' + H(word) + '"></span>';
const statusLine = (tone, text) => '<span class="sline">' + dot(tone, text) + '<span class="' + (tone === 'neutral' ? 'sub' : 't-' + tone) + '">' + H(text) + '</span></span>';
const chipRow = (items, active) => '<div class="chips">' + items.map((t) => '<button class="chip ' + (t === active ? 'on' : '') + '">' + H(t) + '</button>').join('') + '</div>';
const primary = (title) => '<button class="btn primary">' + H(title) + '</button>';
const secondary = (title) => '<button class="btn secondary">' + H(title) + '</button>';
const ledgerRow = (time, event, owner, tone, day) =>
  '<div class="lrow"><div class="stamp">' + H(time) + (day ? '<em>' + H(day) + '</em>' : '') + '</div><div class="lev"><span>' + H(event) + '</span>' + (owner ? '<em>' + H(owner) + '</em>' : '') + '</div>' + dot(tone, event) + '</div>';
const dayHeader = (title, count) => '<div class="dhead"><span>' + H(title) + '</span>' + reading(String(count), '条', 'var(--f-section)', 'var(--ink-faint)') + '</div>';
const shortcut = (title, glyph) => '<div class="srow"><span class="glyph">' + glyph + '</span><span>' + H(title) + '</span><i>&#8250;</i></div>';
const pageHeader = (title, status) => '<header class="phead"><h1>' + H(title) + '</h1>' + (status ? '<div class="pstat">' + status + '</div>' : '') + '</header>';
const badge = (text, kind) => '<span class="badge ' + (kind || '') + '">' + H(text) + '</span>';
const kv = (label, value, unit, tint) => '<div class="kv"><span>' + H(label) + '</span>' + reading(value, unit, 'var(--f-body)', tint) + '</div>';
const empty = (title, message, action, glyph) =>
  '<div class="empty"><span class="eglyph">' + (glyph || '&#9636;') + '</span><b>' + H(title) + '</b><p>' + H(message) + '</p><button class="btn primary narrow">' + H(action) + '</button></div>';

// 刻度盘：60 格蚀刻 + 真实进度弧。progress 来自 DialPhase，不是随机值。
const dial = (word, footnote, hint, progress, failed, size) => {
  const S = size || 260, R = S / 2, arcR = R - 14, circ = 2 * Math.PI * arcR;
  let ticks = '';
  for (let i = 0; i < 60; i++) {
    const ang = (90 + (i / 60) * 360) * Math.PI / 180;
    const major = i % 5 === 0;
    const len = major ? 10 : 5;
    const lit = i <= Math.round(progress * 60) && progress > 0;
    const x1 = R + Math.cos(ang) * (R - len), y1 = R + Math.sin(ang) * (R - len);
    const x2 = R + Math.cos(ang) * R, y2 = R + Math.sin(ang) * R;
    const stroke = lit ? (failed ? 'var(--critical)' : 'var(--base)') : 'var(--ink-faint)';
    ticks += '<line x1="' + x1.toFixed(1) + '" y1="' + y1.toFixed(1) + '" x2="' + x2.toFixed(1) + '" y2="' + y2.toFixed(1) + '" stroke="' + stroke + '" stroke-opacity="' + (lit ? 1 : (major ? .4 : .2)) + '" stroke-width="' + (major ? 1.4 : .7) + '"/>';
  }
  return '<div class="dial" style="width:' + S + 'px;height:' + S + 'px">' +
    '<svg width="' + S + '" height="' + S + '" viewBox="0 0 ' + S + ' ' + S + '" aria-hidden="true">' + ticks +
    (progress > 0 ? '<circle cx="' + R + '" cy="' + R + '" r="' + arcR + '" fill="none" stroke="var(--hairline)" stroke-width="2.5" stroke-linecap="round"/>' : '') +
    '<circle cx="' + R + '" cy="' + R + '" r="' + arcR + '" fill="none" stroke="' + (failed ? 'var(--critical)' : 'var(--base)') + '" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="' + circ + '" stroke-dashoffset="' + (circ * (1 - Math.max(progress, 0.0001))) + '" transform="rotate(-90 ' + R + ' ' + R + ')"/></svg>' +
    '<div class="hub"><b style="' + (failed ? 'color:var(--critical)' : '') + '">' + H(word) + '</b><em>' + H(footnote) + '</em><p>' + H(hint) + '</p></div></div>';
};

// 四步梯：只在真序列上用（配网 / 建档向导 / 开锁链）。这是契约 §11 唯一允许 01/02/03 的地方。
const ladder = (steps, current) =>
  '<div class="ladder">' + steps.map((s, i) =>
    '<div class="step ' + (i < current ? 'done' : i === current ? 'now' : '') + '">' +
    '<span class="num">' + String(i + 1).padStart(2, '0') + '</span>' +
    '<span class="lbl">' + H(s) + '</span></div>').join('') + '</div>';

module.exports = { H, panel, inset, sectionLabel, reading, fieldRow, readingGrid, dot, statusLine, chipRow, primary, secondary, ledgerRow, dayHeader, shortcut, pageHeader, badge, kv, empty, dial, ladder };