#!/usr/bin/env node
// tools/rendercontrast.js —— 叠加透明度后的**实际**对比度
//
// 为什么需要它：
//   tools/contrast.js 验的是**令牌对令牌**的静态比值（98 条断言全过）。
//   但界面里大量用 `XPalette.textSub.opacity(0.5)` 这种叠法 ——
//   叠完之后实际对比度会掉得比想象快：
//       textSub           = 6.99 : 1  ✓
//       textSub×0.5       = 2.68 : 1  ✗ 低于信息性图形的 3:1
//       textTertiary×0.55 = 2.37 : 1  ✗
//   而闸门对此**一无所知**。本工具补这一段。
//
// 用法: node tools/rendercontrast.js
'use strict';

const hex = h => [(h >> 16) & 255, (h >> 8) & 255, h & 255];
const lum = ([r, g, b]) => {
  const f = c => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const contrast = (a, b) => {
  const l1 = lum(a), l2 = lum(b);
  const [hi, lo] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (hi + 0.05) / (lo + 0.05);
};
const blend = (fg, bg, a) => fg.map((c, i) => Math.round(c * a + bg[i] * (1 - a)));

// 深色模式令牌（Theme.swift）
const DARK = {
  canvas: hex(0x0A0A0B), surface: hex(0x161618), surfaceAlt: hex(0x1F1F22), surfaceSunken: hex(0x121214),
  text: hex(0xF5F5F7), textSub: hex(0xA0A0AC), textTertiary: hex(0x888892),
  accentText: hex(0xE8A05C), ok: hex(0x3DD68C), warn: hex(0xF5A524), danger: hex(0xFF6B6B),
  hairline: hex(0x323236),
};

const BGS = ['canvas', 'surface', 'surfaceAlt', 'surfaceSunken'];
// 代码里实际出现过的透明度
const OPS = [1, 0.9, 0.85, 0.8, 0.7, 0.6, 0.55, 0.5, 0.4];
const TEXT_TOKENS = ['text', 'textSub', 'textTertiary', 'accentText', 'ok', 'warn', 'danger'];

// ══════════════════════════════════════════════════════════════
// --scan：反查代码里**实际用到的**组合，而不是穷举矩阵
// ══════════════════════════════════════════════════════════════
// 穷举表只能告诉我"哪些组合不达标"，但界面里到底用了哪些、
// 用在文字还是装饰上，得回到代码里看。
if (process.argv.includes('--scan')) {
  const fsx = require('fs');
  const px = require('path');
  const ROOT = px.resolve(__dirname, '..');
  const walk = d => {
    const out = [];
    for (const e of fsx.readdirSync(d, { withFileTypes: true })) {
      const p = px.join(d, e.name);
      if (e.isDirectory()) { if (e.name[0] !== '.') out.push(...walk(p)); }
      else if (e.name.endsWith('.swift')) out.push(p);
    }
    return out;
  };
  const files = walk(px.join(ROOT, 'App'));
  const rows = [];
  for (const f of files) {
    const lines = fsx.readFileSync(f, 'utf8').split('\n');
    lines.forEach((t, i) => {
      if (/^\s*\/\//.test(t)) return;
      // 与仓里已有的 @layout-allow 同形：就地写明为什么这个低对比度是合理的。
      // 豁免不是"放过"，是**留下判断依据**；没有依据的仍然会被报出来。
      // 标注写在上一行（跟在 .fill 后面会破坏链式调用），所以这里回看一行。
      // 标注可能是多行注释块，所以回看 3 行。
      const recent = [t, lines[i - 1] || '', lines[i - 2] || '', lines[i - 3] || ''].join('\n');
      if (/@contrast-allow/.test(recent)) return;
      const m = t.match(/XPalette\.(textSub|textTertiary|accentText|ok|warn|danger|text)\.opacity\(([0-9.]+)\)/);
      if (!m) return;
      const tok = m[1], a = parseFloat(m[2]);
      if (a >= 1) return;
      const isText = /foregroundStyle|foregroundColor/.test(t);
      // ⚠ 不能把 fill / strokeBorder / background / shadow 一律当"信息图形"。
      //   界面里绝大多数低透明度用法是**底衬 / 描边 / 光晕**：
      //     .fill(danger.opacity(0.10))        告警行的淡红底
      //     .strokeBorder(ok.opacity(0.3))     卡片描边
      //     .shadow(color: ok.opacity(0.4))    光晕
      //   这些不承载信息（信息在图标与文字里），套 3:1 只会制造假警报。
      //   只有**数据标记**（图表柱、状态点）才受 3:1 约束。
      const kind = isText ? 'text'
        : /shadow\(/.test(t) ? 'glow'
        : /strokeBorder|stroke\(/.test(t) ? 'border'
        : /background\(/.test(t) ? 'surface'
        : /fill\(/.test(t) ? 'fill' : 'other';
      let worst = 99, worstBg = '';
      for (const bg of BGS) {
        const c = contrast(blend(DARK[tok], DARK[bg], a), DARK[bg]);
        if (c < worst) { worst = c; worstBg = bg; }
      }
      // 只有 text 与 fill（数据标记候选）才判定；其余仅列出供参考
      const judged = kind === 'text' || kind === 'fill';
      const need = kind === 'text' ? 4.5 : 3.0;
      rows.push({ file: px.basename(f), line: i + 1, tok, a, kind, worst, worstBg, need,
                  bad: judged && worst < need, text: t.trim().slice(0, 62) });
    });
  }
  rows.sort((x, y) => x.worst - y.worst);
  console.log('代码里实际用到的「令牌 × 透明度」组合：' + rows.length + ' 处\n');
  console.log('对比度  用途  组合                    位置');
  console.log('-'.repeat(96));
  const label = { text: '文字', fill: '填充', border: '描边', glow: '光晕', surface: '底衬', other: '其他' };
  for (const r of rows) {
    const mark = r.bad ? '✗' : (r.kind === 'text' || r.kind === 'fill' ? '✓' : '—');
    console.log(r.worst.toFixed(2).padStart(6) + '  ' + label[r.kind] + '  ' + mark + '  ' +
      (r.tok + '×' + r.a).padEnd(22) + r.file + ':' + r.line);
    if (r.bad) console.log('        ' + r.text + '   （最差背景 ' + r.worstBg + '，需要 ' + r.need + '）');
  }
  const badRows = rows.filter(r => r.bad);
  console.log('-'.repeat(96));
  console.log('不达标: ' + badRows.length + ' / ' + rows.length);
  process.exit(0);
}

let fails = 0;
console.log('深色模式 · 合成后的实际对比度（文字需 ≥4.5:1，信息性图形 ≥3:1）');
console.log('');
console.log('前景 × 透明度'.padEnd(24) + BGS.map(b => b.padEnd(14)).join(''));
for (const t of TEXT_TOKENS) {
  for (const a of OPS) {
    if (a < 1 && t === 'text') continue;          // 正文不会降透明度
    let row = (t + (a < 1 ? '×' + a : '')).padEnd(24);
    let worst = 99;
    for (const bg of BGS) {
      const eff = a === 1 ? DARK[t] : blend(DARK[t], DARK[bg], a);
      const c = contrast(eff, DARK[bg]);
      worst = Math.min(worst, c);
      row += (c.toFixed(2) + (c < 3 ? ' ✗' : (c < 4.5 ? ' ⚠' : ''))).padEnd(14);
    }
    if (worst < 4.5) {
      console.log(row);
      if (a >= 0.95) fails++;
    }
  }
}
console.log('');
console.log('✗ = 低于 3:1（连图形都不够）  ⚠ = 低于 4.5:1（正文不够）');
console.log('只列出有问题的组合；全部达标的组合不打印。');
console.log('');
console.log('判读要点：');
console.log('  · 用于**正文/标签**的组合必须 ≥4.5:1 —— 也就是说这些文字**不要叠透明度**');
console.log('  · 用于**信息性图形**（图表柱/状态点）的必须 ≥3:1');
console.log('  · 用于**装饰/网格线**的可以低，但要不低于约 1.4:1 才看得见');
