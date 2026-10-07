#!/usr/bin/env node
// 设计令牌对比度闸门 — 把"对比度已核算"这种口头声明变成可复现的机器检查。
//
// 背景: DS.Palette 的颜色是 UIColor 动态色(明暗各一套), 之前对比度是手算的,
// 手算不可复现、也没人会在改色后重算。这里直接从 DesignSystem.swift 解析出
// 每一组取值, 按 WCAG 2.1 相对亮度公式算出比值, 低于阈值即失败。
//
// 包16 起色板扩展为: 基础令牌 + 三套品牌主题 (themeTable, idea 31) + AMOLED 纯黑覆盖
// (amoledOverride, idea 30) — 三张表全部机检:
//   基础:   text/textSub 对三种底, ok/warn/danger 对画布与卡片, hairline 可辨。
//   主题:   每主题×明暗: accentText 对三种底 / onAccent 对 accent / 纯白对 hero 两端。
//   AMOLED: 纯黑表面上正文与语义色 (含各主题 dark accentText) 仍 ≥4.5:1。
//
// 用法: node tools/contrast.js          (CI 闸门, 不达标 exit 1)
//       node tools/contrast.js --verbose (附带完整表格)

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'App', 'Core', 'DesignSystem.swift');
const verbose = process.argv.includes('--verbose');

// ---------- WCAG 相对亮度 ----------
function channel(c) {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}
function luminance(hex) {
  const r = (hex >> 16) & 0xff, g = (hex >> 8) & 0xff, b = hex & 0xff;
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}
function contrast(a, b) {
  const la = luminance(a), lb = luminance(b);
  const hi = Math.max(la, lb), lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

// ---------- 解析 DesignSystem.swift ----------
const src = fs.readFileSync(SRC, 'utf8');
const paletteBlock = src.match(/enum Palette \{([\s\S]*?)\n    \}/);
if (!paletteBlock) {
  console.error('✗ 未能在 DesignSystem.swift 中定位 enum Palette — 结构变了?');
  process.exit(1);
}
const block = paletteBlock[1];

// 1) 基础令牌: static let xxx = Color.adaptive(light, dark)
const base = {};
const reBase = /static let (\w+)\s*=\s*Color\.adaptive\(\s*0x([0-9a-fA-F]{6})\s*,\s*0x([0-9a-fA-F]{6})\s*\)/g;
let m;
while ((m = reBase.exec(block)) !== null) {
  base[m[1]] = { light: parseInt(m[2], 16), dark: parseInt(m[3], 16) };
}
if (Object.keys(base).length < 9) {
  console.error(`✗ 基础令牌只解析到 ${Object.keys(base).length} 个, 预期 >= 9 — 解析规则可能失效`);
  process.exit(1);
}

// 2) 主题表: "主题": [ "light": [...], "dark": [...] ]
const themes = {};
const reTheme = /"(\w+)":\s*\[\s*"light":\s*\[([^\]]*)\],\s*"dark":\s*\[([^\]]*)\]/g;
const rePair = /"(\w+)":\s*0x([0-9a-fA-F]{6})/g;
while ((m = reTheme.exec(block)) !== null) {
  const t = {};
  for (const [idx, mode] of [[2, 'light'], [3, 'dark']]) {
    const roles = {};
    let p;
    rePair.lastIndex = 0;
    while ((p = rePair.exec(m[idx])) !== null) roles[p[1]] = parseInt(p[2], 16);
    t[mode] = roles;
  }
  themes[m[1]] = t;
}
if (Object.keys(themes).length !== 3) {
  console.error(`✗ 品牌主题解析到 ${Object.keys(themes).length} 套, 预期 3 (indigo/forest/amber)`);
  process.exit(1);
}
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) {
    for (const role of ['accent', 'accentText', 'onAccent', 'heroA', 'heroB', 'btnA', 'btnB']) {
      if (t[mode][role] === undefined) {
        console.error(`✗ 主题 ${name}/${mode} 缺少角色 ${role}`);
        process.exit(1);
      }
    }
  }
}

// 3) AMOLED 覆盖表
const amoMatch = block.match(/static let amoledOverride:\s*\[String: UInt32\]\s*=\s*\[([^\]]*)\]/);
if (!amoMatch) {
  console.error('✗ 未找到 amoledOverride 表 — idea 30 的纯黑覆盖缺失?');
  process.exit(1);
}
const amoled = {};
rePair.lastIndex = 0;
while ((m = rePair.exec(amoMatch[1])) !== null) amoled[m[1]] = parseInt(m[2], 16);
for (const k of ['canvas', 'surface', 'surfaceAlt']) {
  if (amoled[k] === undefined) {
    console.error(`✗ amoledOverride 缺少 ${k}`);
    process.exit(1);
  }
}

// ---------- 断言表 ----------
// ratio: 该前景色必须与其背景达到的最小对比度。WCAG AA 正文需 4.5,
// 非文本/大号文字需 3.0。分隔线按下限 1.2:1 (须"看得见", 苹果自身 separator 也在 1.2 上下)。
const ASSERTIONS = [];
const push = (mode, fg, bg, min, why, fgHex, bgHex) =>
  ASSERTIONS.push({ mode, fg, bg, min, why, fgHex, bgHex });

// A. 基础令牌 (明暗双模)
for (const mode of ['light', 'dark']) {
  for (const [fg, min] of [['text', 4.5], ['textSub', 4.5]]) {
    for (const bg of ['surfaceBase', 'canvasBase', 'surfaceAltBase']) {
      push(mode, fg, bg, min, `${fg === 'text' ? '正文' : '次级文本'}在${bg.includes('Alt') ? '指标块' : bg.includes('canvas') ? '页面底' : '卡片'}上`, base[fg][mode], base[bg][mode]);
    }
  }
  for (const fg of ['ok', 'warn', 'danger']) {
    for (const bg of ['canvasBase', 'surfaceBase']) {
      push(mode, fg, bg, 4.5, '语义文案在页面底/卡片上', base[fg][mode], base[bg][mode]);
    }
  }
  for (const bg of ['surfaceBase', 'canvasBase']) {
    push(mode, 'hairline', bg, 1.2, '分隔线需可辨', base.hairline[mode], base[bg][mode]);
  }
}

// B. 品牌主题 (idea 31): 每主题 × 明暗
const surfaceOf = { light: base.surfaceBase.light, dark: base.surfaceBase.dark };
const canvasOf = { light: base.canvasBase.light, dark: base.canvasBase.dark };
const altOf = { light: base.surfaceAltBase.light, dark: base.surfaceAltBase.dark };
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) {
    push(mode, `${name}.accentText`, 'surface', 4.5, '主题强调文字在卡片上', t[mode].accentText, surfaceOf[mode]);
    push(mode, `${name}.accentText`, 'canvas', 4.5, '主题强调文字在页面底上', t[mode].accentText, canvasOf[mode]);
    push(mode, `${name}.accentText`, 'surfaceAlt', 4.5, '主题强调文字在指标块上', t[mode].accentText, altOf[mode]);
    push(mode, `${name}.onAccent`, `${name}.accent`, 4.5, '主按钮文字压在主题填充上', t[mode].onAccent, t[mode].accent);
    push(mode, 'white', `${name}.heroA`, 4.5, '纯白压主题渐变亮端 (hero 卡文字)', 0xFFFFFF, t[mode].heroA);
    push(mode, 'white', `${name}.heroB`, 4.5, '纯白压主题渐变暗端 (hero 卡文字)', 0xFFFFFF, t[mode].heroB);
  }
}

// C. AMOLED 纯黑 (idea 30): kf_theme=="black" 时强制深色语义, 用各令牌 dark 值
for (const fg of ['text', 'textSub', 'ok', 'warn', 'danger']) {
  for (const [bgName, bgHex] of [['amoCanvas', amoled.canvas], ['amoSurface', amoled.surface], ['amoSurfaceAlt', amoled.surfaceAlt]]) {
    push('black', fg, bgName, 4.5, '纯黑表面上文字仍须达标', base[fg].dark, bgHex);
  }
}
push('black', 'hairline', 'amoSurface', 1.2, '纯黑表面上分隔线需可辨', base.hairline.dark, amoled.surface);
push('black', 'hairline', 'amoCanvas', 1.2, '纯黑页底上分隔线需可辨', base.hairline.dark, amoled.canvas);
for (const [name, t] of Object.entries(themes)) {
  push('black', `${name}.accentText`, 'amoSurface', 4.5, '主题强调文字在纯黑卡片上', t.dark.accentText, amoled.surface);
  push('black', `${name}.accentText`, 'amoCanvas', 4.5, '主题强调文字在纯黑页底上', t.dark.accentText, amoled.canvas);
  push('black', `${name}.accentText`, 'amoSurfaceAlt', 4.5, '主题强调文字在纯黑指标块上', t.dark.accentText, amoled.surfaceAlt);
  push('black', `${name}.onAccent`, `${name}.accent`, 4.5, '主按钮文字压在主题填充上 (纯黑模式)', t.dark.onAccent, t.dark.accent);
}

// D. 主按钮渐变 (包1): onAccent 压 DS.Gradient.button 两端。
//    浅色 onAccent=白, 压 hero 同值端点; 深色 onAccent=近黑(0x0A0E15),
//    压 accentText→accent 区间 — 旧案深色按钮复用 hero 暗端, 近黑字仅 ~2.4:1 (必修缺陷)。
//    6 组 = 3 主题 × 明暗, 每组两端; 纯黑模式沿用深色值, 一并锁定。
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) {
    push(mode, `${name}.onAccent`, `${name}.btnA`, 4.5, '主按钮文字压渐变亮端 (btnA)', t[mode].onAccent, t[mode].btnA);
    push(mode, `${name}.onAccent`, `${name}.btnB`, 4.5, '主按钮文字压渐变暗端 (btnB)', t[mode].onAccent, t[mode].btnB);
  }
  push('black', `${name}.onAccent`, `${name}.btnA`, 4.5, '纯黑模式主按钮文字压渐变亮端', t.dark.onAccent, t.dark.btnA);
  push('black', `${name}.onAccent`, `${name}.btnB`, 4.5, '纯黑模式主按钮文字压渐变暗端', t.dark.onAccent, t.dark.btnB);
}

// ---------- 求值 ----------
let failed = 0;
const rows = [];
for (const a of ASSERTIONS) {
  const r = contrast(a.fgHex, a.bgHex);
  const ok = r >= a.min;
  if (!ok) failed++;
  rows.push({ mode: a.mode, pair: `${a.fg} on ${a.bg}`, ratio: r, min: a.min, ok, why: a.why });
}

if (verbose) {
  const pad = (s, n) => String(s).padEnd(n);
  console.log('\n设计令牌对比度 (WCAG 2.1)\n');
  console.log(pad('模式', 7) + pad('前景', 20) + pad('背景', 16) + pad('实测', 8) + pad('阈值', 7) + '说明');
  console.log('-'.repeat(100));
  for (const r of rows) {
    console.log(
      pad(r.mode, 7) + pad(r.pair.split(' on ')[0], 20) + pad(r.pair.split(' on ')[1], 16) +
      pad(r.ratio.toFixed(2) + ':1', 8) + pad(r.min.toFixed(1), 7) +
      (r.ok ? '✓' : '✗') + ' ' + r.why
    );
  }
  console.log('');
}

console.log(`基础令牌 ${Object.keys(base).length} 个 | 主题 ${Object.keys(themes).length} 套 | 断言 ${rows.length} 条 | 不达标 ${failed} 条`);
if (failed > 0) {
  console.error('\n✗ 对比度不达标 — 见上表 (--verbose 查看全表)。修改 DS.Palette 后必须重新核对。');
  process.exit(1);
}
console.log('✓ 全部对比度达标 (正文 4.5:1 / 非文本 3:1 / 分隔线 1.2:1, 含三主题与 AMOLED)');
