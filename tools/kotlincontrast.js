#!/usr/bin/env node
// kotlincontrast —— Android 调色板对比度机检（判失败）。
//
// 2026-10-31（第 41 轮）：iOS 有 `tools/contrast.js`（319 条断言，7 套主题 + AMOLED 全覆盖），
// 而 Android 的 `KfTheme.kt` **一条机检都没有** —— 注释里那几行对比度数字（"#8F6119 对白底 5.40"）
// 是手算的，改了色值没人会重算。深色模式可读性只能靠肉眼，不符合「全维度合理」。
//
// 判据（WCAG 2.1 / HIG `color.md`）：
//   · 正文（ink / inkSub）对**所有**背景层（bgTop / bgBottom / surface）≥ 4.5:1
//   · 语义色（ok / bad / accent）对**所有**背景层 ≥ 3:1（它们是图标/强调，非长文本）
//   · onAccent 对 accent ≥ 4.5:1（强调色上的文字）
//   · 分隔/边框类不做（本工程无独立 hairline 令牌）
//
// 两套主题都查：KfDarkColors / KfLightColors。
// 正控：把浅色 accent 从 `#8F6119` 改回 `#B8862F` ⇒ 报出 3 条不达标（2.69~3.26:1）。
//      把「门锁设置」标题改回 `inkSub.copy(alpha = 0.6f)` ⇒ 报出「正文用了 alpha 稀释色」。
// 负控：32 条调色板断言全达标，alpha 检查零误报（开关轨道/边框已排除）。

const fs = require('fs');
const path = require('path');

const KT = path.join(path.resolve(__dirname, '..'), 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'KfTheme.kt');
if (!fs.existsSync(KT)) {
  console.log('✓ 无 android-app 工程，跳过');
  process.exit(0);
}
const src = fs.readFileSync(KT, 'utf8');

// ── 解析两套调色板 ──
function parsePalette(name) {
  const re = new RegExp(`internal val ${name} = KfColors\\(([\\s\\S]*?)\\n\\)`, 'm');
  const m = src.match(re);
  if (!m) return null;
  const out = {};
  for (const line of m[1].split('\n')) {
    const mm = line.match(/\s*(\w+)\s*=\s*Color\(0x(?:FF)?([0-9A-Fa-f]{6})\)/);
    if (mm) out[mm[1]] = mm[2].toUpperCase();
  }
  return out;
}

const DARK = parsePalette('KfDarkColors');
const LIGHT = parsePalette('KfLightColors');
if (!DARK || !LIGHT) {
  console.log('✗ 解析不到 KfDarkColors / KfLightColors（调色板结构变了，先更新本闸门的解析）');
  process.exit(1);
}

// ── WCAG 相对亮度 / 对比度 ──
function srgb(c) { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.05) / 1.05, 2.4); }
function lum(hex) {
  const r = parseInt(hex.slice(0, 2), 16), g = parseInt(hex.slice(2, 4), 16), b = parseInt(hex.slice(4, 6), 16);
  return 0.2126 * srgb(r) + 0.7152 * srgb(g) + 0.0722 * srgb(b);
}
function ratio(a, b) {
  const la = lum(a), lb = lum(b);
  const hi = Math.max(la, lb), lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const BGS = ['bgTop', 'bgBottom', 'surface'];
const TEXT = ['ink', 'inkSub'];      // 正文，4.5:1
const SEM = ['ok', 'bad', 'accent'];  // 语义色，3:1

let total = 0, fails = 0;
const bad = [];

for (const [label, P] of [['暗色 KfDarkColors', DARK], ['浅色 KfLightColors', LIGHT]]) {
  console.log(`\n--- ${label} ---`);
  for (const t of TEXT) {
    for (const bg of BGS) {
      total++;
      const r = ratio(P[t], P[bg]);
      const ok = r >= 4.5;
      if (!ok) { fails++; bad.push(`${label}: ${t}(#${P[t]}) 对 ${bg}(#${P[bg]}) = ${r.toFixed(2)}:1 < 4.5`); }
      console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${t.padEnd(7)} 对 ${bg.padEnd(9)} = ${r.toFixed(2)}:1  (需 ≥4.5)`);
    }
  }
  for (const s of SEM) {
    for (const bg of BGS) {
      total++;
      const r = ratio(P[s], P[bg]);
      const ok = r >= 3.0;
      if (!ok) { fails++; bad.push(`${label}: ${s}(#${P[s]}) 对 ${bg}(#${P[bg]}) = ${r.toFixed(2)}:1 < 3.0`); }
      console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${s.padEnd(7)} 对 ${bg.padEnd(9)} = ${r.toFixed(2)}:1  (需 ≥3.0)`);
    }
  }
  total++;
  const ra = ratio(P.onAccent, P.accent);
  const okA = ra >= 4.5;
  if (!okA) { fails++; bad.push(`${label}: onAccent(#${P.onAccent}) 对 accent(#${P.accent}) = ${ra.toFixed(2)}:1 < 4.5`); }
  console.log(`  ${okA ? 'ok  ' : 'FAIL'} onAccent 对 accent   = ${ra.toFixed(2)}:1  (需 ≥4.5)`);
}


// ── 2026-10-31（第 42 轮）：**alpha 稀释的正文对比度** ──
//
// `inkSub.copy(alpha = 0.55f)` 这类写法在 Compose 里很自然，但它把有效前景色稀释了：
// 叠在底上后实测 2.8~4.1:1（六种底全部低于 4.5:1）。而它们用在**用户要读的说明正文**上
// （失败详情 / 自动开锁规则 / MAC 地址），不是装饰。
//
// 判据：`colors.ink` 或 `colors.inkSub` 上挂 `.copy(alpha = X)` 且 X < 1.0，且该行不是
// `uncheckedTrackColor` / `uncheckedBorderColor` / `background` / `border`（那些是非文本元素，3:1 即可）。
const MAIN = path.join(path.resolve(__dirname, ".."), "android-app", "app", "src", "main", "java", "com", "aapk", "kfkey", "MainActivity.kt");
if (fs.existsSync(MAIN)) {
  const ml = fs.readFileSync(MAIN, "utf8").split(/\r?\n/);
  for (let k = 0; k < ml.length; k++) {
    const c = ml[k];
    if (/^\s*\/\//.test(c)) continue;                                  // 注释
    if (!/colors\.(ink|inkSub)\.copy\(\s*alpha\s*=/.test(c)) continue;  // 只查这两个前景色
    // 非文本元素放行（开关轨道/边框/背景）
    if (/uncheckedTrackColor|uncheckedBorderColor|TrackColor|BorderColor|background\(/.test(c)) continue;
    // 只看「这一行是给 Text 的 color」（同一行或上一行有 color =）
    const isTextColor = /color\s*=\s*colors\.(ink|inkSub)\.copy/.test(c);
    if (!isTextColor) continue;
    total++; fails++;
    bad.push("MainActivity.kt:" + (k + 1) + "  正文用了 alpha 稀释色（有效对比度会低于 4.5:1）: " + c.trim().slice(0, 70));
  }
}
console.log(`\n断言 ${total} 条 | 不达标 ${fails} 条`);
if (fails) {
  console.log('\n✗ 不达标明细：');
  bad.forEach(x => console.log('  ' + x));
  console.log('\n修法：改 KfTheme.kt 里的色值，让对比度达标（不要改判据阈值 —— 那是 WCAG 硬指标）。');
  process.exit(1);
}
console.log('✓ Android 调色板对比度全部达标（正文 4.5:1 / 语义 3:1，含深浅两档）');
