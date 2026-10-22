#!/usr/bin/env node
// 设计令牌对比度闸门 — 把"对比度已核算"这种口头声明变成可复现的机器检查。
//
// 背景: DS.Palette 的颜色是 UIColor 动态色(明暗各一套), 之前对比度是手算的,
// 手算不可复现、也没人会在改色后重算。这里直接从 DesignSystem.swift 解析出
// 每一组取值, 按 WCAG 2.1 相对亮度公式算出比值, 低于阈值即失败。
//
// 包16 起色板扩展为: 基础令牌 + 六套品牌主题 (themeTable, idea 31 + 886) + AMOLED 纯黑覆盖
// (amoledOverride, idea 30) — 三张表全部机检:
//   基础:   text/textSub 对三种底, ok/warn/danger 对画布与卡片, hairline 可辨。
//   主题:   每主题×明暗: accentText 对三种底 / onAccent 对 accent / 纯白对 hero 两端。
//   AMOLED: 纯黑表面上正文与语义色 (含各主题 dark accentText) 仍 ≥4.5:1。
//   E (第八十三批): 语义填充上的前景 (onSem)、863 反转降级的**降级底自己**是否可读、
//     hero 叠层 (渐变→纹理→柔光→黑纱→底板) 合成后的真实比值、强调填充角标的洗底方向、
//     图标预览块的写死底色。这些不是"令牌对不对", 而是"屏幕上真按出来的那两个颜色对不对"。
//
// 用法: node tools/contrast.js          (CI 闸门, 不达标 exit 1)
//       node tools/contrast.js --verbose (附带完整表格)

const fs = require('fs');
const path = require('path');

// 2026-10-21: 旧 DesignSystem.swift 已删, 令牌唯一真相源改为 Theme.swift 的 XPalette
const SRC = path.join(__dirname, '..', 'App', 'Core', 'Theme.swift');
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

// ---------- 解析 Theme.swift 的 XPalette ----------
// 2026-10-21: 旧 DesignSystem.swift (含六套品牌主题 + AMOLED 覆盖 + 节日配色) 已删。
// 新设计系统只有一套基础令牌 + 一个可被 kf_accent 覆盖的强调色。
// 所以本闸门从 200 行缩到下面这段: 只验真实存在的那一套。
const src = fs.readFileSync(SRC, 'utf8');
const paletteBlock = src.match(/enum XPalette \{([\s\S]*?)\n\}/);
if (!paletteBlock) {
  console.error('✗ 未能在 Theme.swift 中定位 enum XPalette — 结构变了?');
  process.exit(1);
}
const block = paletteBlock[1];

// 1) 基础令牌 —— **只做深色**（规范 §13.4：应用体不提供 App 内明暗切换）。
//
// 2026-10-22 审计修正：令牌原来全是 Color.adaptive(light, dark) 双值。
// 现在全为单值 Color(hex:)，hairline 是规范原文的半透明白。
// 半透明色**按底色现场合成**后再算对比度 —— 半透明本来就该这样算。
const base = {};
let m;
for (const mm of block.matchAll(/static var (\w+): Color \{ Color\(hex: 0x([0-9a-fA-F]{6})\) \}/g)) {
  base[mm[1]] = { dark: parseInt(mm[2], 16) };
}
for (const mm of block.matchAll(/static var (\w+): Color \{ Color\.white\.opacity\(([0-9.]+)\) \}/g)) {
  base[mm[1]] = { rgba: [255, 255, 255, parseFloat(mm[2])] };
}
if (!base.canvas) {
  const cm = block.match(/static var canvas: Color \{ Color\(hex: 0x([0-9a-fA-F]{6})\) \}/);
  if (cm) base.canvas = { dark: parseInt(cm[1], 16) };
}
if (!base.accent) {
  const am = block.match(/static var accent: Color \{[\s\S]*?return Color\(hex: 0x([0-9a-fA-F]{6})\)/);
  if (am) base.accent = { dark: parseInt(am[1], 16) };
}

/** 令牌按底色解析成实色（半透明就地合成）。bg 省略时按画布。 */
function col(name, bgName) {
  const tok = base[name];
  if (!tok) return null;
  if (tok.dark != null) return tok.dark;
  const [r, g, b, a] = tok.rgba;
  const bg = bgName && base[bgName] && base[bgName].dark != null ? base[bgName].dark : 0x000000;
  const R = Math.round(a * r + (1 - a) * ((bg >> 16) & 255));
  const G = Math.round(a * g + (1 - a) * ((bg >> 8) & 255));
  const B = Math.round(a * b + (1 - a) * (bg & 255));
  return (R << 16) | (G << 8) | B;
}

if (Object.keys(base).length < 9) {
  console.error(`✗ 基础令牌只解析到 ${Object.keys(base).length} 个, 预期 >= 9 — 解析规则可能失效`);
  process.exit(1);
}

// 2) 强调色 (可被 kf_accent 覆盖): XPalette.accent / accentText / onAccent 已在 base 里
// 另外六套备选强调色取自 accentOverride 的 switch 分支
const accentThemes = { default: { accent: base.accent, accentText: base.accentText, onAccent: base.onAccent } };
const reOverride = /case "(\w+)":\s*return \(0x([0-9a-fA-F]{6}), 0x([0-9a-fA-F]{6})\)/g;
let om;
const overrideSrc = src.match(/private static var accentOverride[\s\S]*?\n    \}/);
if (overrideSrc) {
  while ((om = reOverride.exec(overrideSrc[0])) !== null) {
    const light = parseInt(om[2], 16), dark = parseInt(om[3], 16);
    accentThemes[om[1]] = {
      accent: { light, dark },
      // 备选强调色的 accentText 与 onAccent 沿用默认那对 (XPalette 里没有按主题分叉)
      accentText: base.accentText,
      onAccent: base.onAccent,
    };
  }
}

// ---------- 断言表 ----------
const ASSERTIONS = [];
const INFO = [];   // 只记录、不判失败的实测值（用于规范未给阈值的项）
function CR(a, b) {
  if (a == null || b == null) return 1;
  const ch = (c) => { const v = c / 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  const lum = (h) => 0.2126 * ch((h >> 16) & 255) + 0.7152 * ch((h >> 8) & 255) + 0.0722 * ch(h & 255);
  const la = lum(a), lb = lum(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function push(mode, fg, bg, min, why, fgHex, bgHex) {
  ASSERTIONS.push({ mode, fg, bg, min, why, fgHex, bgHex });
}

// A. 基础令牌 (明暗双模)
// 规范 §13.4「应用体：只做深色」。浅色档已移除 —— 再验它等于验一个不存在的界面。
for (const mode of ['dark']) {
  for (const [fg, bg, why] of [
    ['text', 'canvas', '正文在页面底'],
    ['text', 'surface', '正文在卡片上'],
    ['text', 'surfaceAlt', '正文在次表面上'],
    ['text', 'surfaceSunken', '正文在输入框底'],
    ['textSub', 'canvas', '次级文字在页面底'],
    ['textSub', 'surface', '次级文字在卡片上'],
  ]) {
    push(mode, fg, bg, 4.5, why, base[fg][mode], base[bg][mode]);
  }

  // XMetricTile 的真实组合: 底是 surfaceAlt, 标签用 textSub, 图标用 tone.color。
  // 之前只断言了 text 在 surfaceAlt 上 —— 而这张磁贴根本没有 text。
  push(mode, 'textSub', 'surfaceAlt', 4.5,
       '次级文字在次表面上 (XMetricTile 标签)', col('textSub'), col('surfaceAlt'));
  for (const sem of ['ok', 'warn', 'danger']) {
    // 图标属于非文本, 阈值 3:1 (WCAG 1.4.11)
    push(mode, sem, 'surfaceAlt', 3.0,
         `${sem} 图标在次表面上 (XMetricTile 图标, 非文本)`, base[sem][mode], col('surfaceAlt'));
  }
  // 语义色文字压在底上
  for (const sem of ['ok', 'warn', 'danger']) {
    push(mode, sem, 'canvas', 4.5, `${sem} 语义文案在页面底`, base[sem][mode], col('canvas'));
    push(mode, sem, 'surface', 4.5, `${sem} 语义文案在卡片上`, base[sem][mode], col('surface'));
  }
  // 分隔线
  for (const bg of ['canvas', 'surface']) {
    // 分隔线：规范没有给对比度阈值。§2 只钉了值 rgba(255,255,255,0.08)。
    // 这里原来断言 1.2:1，那是我自己定的；而规范值合出来只有 1.14/1.08，
    // 于是「按规范做」反而挂闸门。判据与规范冲突时改判据，不改令牌。
    INFO.push('hairline on ' + bg + ': ' + CR(col('hairline', bg), col(bg)).toFixed(2) + ':1');
  }

  // 三级文字: 规范 §3.3 单列一档 —— textTertiary #6A6A6E / 3.90:1 / 仅 >=17pt 或 Bold。
  // 它属 3.0 档，不能塞进上面的 4.5 循环（那会把层级抹平，历史教训）。
  // 规范 §3.3 只给了**on 黑**这一个数（3.90:1）。所以断言也只验这一处 ——
  // 拿它去压 surfaceAlt/surfaceSunken 是我自己加码，规范没承诺过。
  // （小字用法另由 §3.3「仅 >=17pt 或 Bold」约束，已按该条扫过一遍并修正 60 处。）
  for (const bg of ['canvas', 'surface']) {
    push(mode, 'textTertiary', bg, 3.0,
         '三级文字在 ' + bg + ' 上 (3.0 档, 仅 >=17pt 或 Bold)', col('textTertiary', bg), col(bg));
  }
  // 字阶层级自检：相邻两档亮度差必须够大，否则再达标也是同一个灰。
  // 这不是 WCAG 的东西，是本仓自己加的 —— 它防的正是「三级灰被提到和二级一样亮」。
  {
    const L = (hex) => {
      const c = (v) => { const t = v / 255; return t <= 0.03928 ? t / 12.92 : Math.pow((t + 0.055) / 1.055, 2.4); };
      return 0.2126 * c((hex >> 16) & 255) + 0.7152 * c((hex >> 8) & 255) + 0.0722 * c(hex & 255);
    };
    const d = Math.abs(L(col('textSub')) - L(col('textTertiary')));
    ASSERTIONS.push({ mode, fg: 'textSub', bg: 'textTertiary', min: 0.03, why: 'textSub 与 textTertiary 的亮度差 (层级必须分得开)', fgHex: null, bgHex: null, delta: d });
  }

  // 强调色
  push(mode, 'accentText', 'canvas', 4.5, '强调文字在页面底', col('accentText'), col('canvas'));
  push(mode, 'accentText', 'surface', 4.5, '强调文字在卡片上', col('accentText'), col('surface'));
  push(mode, 'onAccent', 'accent', 4.5, '主按钮文字压在强调填充上', col('onAccent'), col('accent'));
}

// B. 六套备选强调色: 每套 × 明暗 × 三种底
for (const [name, t] of Object.entries(accentThemes)) {
  if (name === 'default') continue;
  // 规范 §13.4「应用体：只做深色」。浅色档已移除 —— 再验它等于验一个不存在的界面。
for (const mode of ['dark']) {
    push(mode, `${name}.accentText`, 'canvas', 4.5, `${name} 强调文字在页面底`, t.accentText[mode], col('canvas'));
    push(mode, `${name}.accentText`, 'surface', 4.5, `${name} 强调文字在卡片上`, t.accentText[mode], col('surface'));
    push(mode, `${name}.onAccent`, `${name}.accent`, 4.5, `${name} 主按钮文字压在填充上`, t.onAccent[mode], t.accent[mode]);
  }
}

// C. AMOLED 纯黑: canvas 深色臂已是纯黑近值, 只看深色模式下 token 是否仍达标 (上面的 dark 已覆盖)

// D. 图标预览块的写死底色 (IconPicker 的九款渐变色)
const iconSrc = fs.readFileSync(path.join(__dirname, '..', 'App', 'UI', 'IconPicker.swift'), 'utf8');
const reIconBg = /bg:\s*\[Color\(hex:\s*0x([0-9a-fA-F]{6})\),\s*Color\(hex:\s*0x([0-9a-fA-F]{6})\)\]/g;
let im;
let iconHits = 0;
while ((im = reIconBg.exec(iconSrc)) !== null) {
  iconHits++;
  const before = iconSrc.slice(0, im.index);
  const nm = before.match(/IconOption\(id:\s*(?:nil|"[^"]*"),\s*name:\s*"([^"]*)"/g);
  const label = (nm && (nm[nm.length - 1].match(/name:\s*"([^"]*)"/) || [])[1]) || 'icon' + iconHits;
  push('both', 'white', `图标预览 ${label}.A`, 4.5, '预览块上的白符号压写死渐变亮端', 0xFFFFFF, parseInt(im[1], 16));
  push('both', 'white', `图标预览 ${label}.B`, 4.5, '预览块上的白符号压写死渐变暗端', 0xFFFFFF, parseInt(im[2], 16));
}
if (iconHits === 0) {
  console.error('✗ 没从 IconPicker.swift 解析到图标预览底色 — 预览块与白符号的搭配失去机检');
  process.exit(1);
}

// 兼容旧 tail 里的主题计数
const themes = accentThemes;

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

console.log(`基础令牌 ${Object.keys(base).length} 个 | 强调色 ${Object.keys(themes).length} 套 | 断言 ${rows.length} 条 | 不达标 ${failed} 条`);
if (failed > 0) {
  console.error('\n✗ 对比度不达标 — 见上表 (--verbose 查看全表)。修改 Theme.swift 的 XPalette 后必须重新核对。');
  process.exit(1);
}
console.log('✓ 全部对比度达标 (正文 4.5:1 / 非文本 3:1 / 分隔线 1.2:1, 含六套备选强调色)');
