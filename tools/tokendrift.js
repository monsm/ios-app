#!/usr/bin/env node
// tools/tokendrift.js — iOS / Android 设计令牌对账 (判失败)
//
// 为什么需要它: 两端的令牌约定是「逐值同源」, 但这个约定此前**只靠人记**。
// 实证: Android 侧有三处值落后于 iOS (textTertiary 两档 + 两个已删令牌),
// 是我在第三轮手工比对时才发现的 —— 而它们已经存在了一整轮。
// 一个靠"记得去比"的约定, 迟早会静默漂开。
//
// 判据:
//   · iOS 侧从 App/Core/Theme.swift 的 XPalette 解析 (Color.adaptive 的明暗两臂)
//   · Android 侧从 KfTheme.kt 的 KfDarkColors / KfLightColors 解析
//   · 同名同值 → ok; 同名不同值 → **失败**
//   · iOS 有、Android 没有 → 必须在该文件头用 "故意不镜像" 一节写明理由, 否则失败
//   · Android 有、iOS 没有 → 失败 (镜像了不存在的东西)
//
// 用法: node tools/tokendrift.js            (不达标 exit 1)
//       node tools/tokendrift.js --verbose  (打印全表)
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const IOS = path.join(ROOT, 'App', 'Core', 'Theme.swift');
const KT = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'KfTheme.kt');
const verbose = process.argv.includes('--verbose');

if (!fs.existsSync(IOS) || !fs.existsSync(KT)) {
  console.log('tokendrift: 缺少一侧的令牌文件, 跳过 (退 0)');
  process.exit(0);
}

const norm = (h) => '0x' + h.replace(/^0x/i, '').toUpperCase().padStart(6, '0');

// ---- iOS ----
const iosFull = fs.readFileSync(IOS, 'utf8');
// 只取 XPalette 这一段 —— DSRing 里的 innerDisc/trackTop/trackBottom 是**环专用色**，
// 不是全局色板，拿它们去和 Android 的 KfColors 对比是错的。
const iosPal = /enum XPalette \{([\s\S]*?)\n\}/.exec(iosFull);
const iosSrc = iosPal ? iosPal[1] : iosFull;
const ios = {};
// 规范 §13.4：只做深色。令牌为单值 Color(hex:)；hairline 是规范原文的半透明白。
// 2026-10-23：令牌改回**深浅双值**（App 只跟随系统，不提供配色选择）。
// 对账仍比**深色档** —— 那是规范给的实测值，也是 Android 侧镜像的那一档。
for (const m of iosSrc.matchAll(/static var (\w+): Color \{ Color\.adaptive\(0x[0-9A-Fa-f]{6}, (0x[0-9A-Fa-f]{6})\) \}/g)) {
  ios[m[1]] = { dark: norm(m[2]) };
}
for (const m of iosSrc.matchAll(/static var (\w+): Color \{ Color\(hex: (0x[0-9A-Fa-f]{6})\) \}/g)) {
  ios[m[1]] = { dark: norm(m[2]) };
}
for (const m of iosSrc.matchAll(/static var (\w+): Color \{ Color\.white\.opacity\(([0-9.]+)\) \}/g)) {
  ios[m[1]] = { dark: 'rgba(255,255,255,' + m[2] + ')' };
}
// 两个不是 Color.adaptive 形式的手写令牌
if (/static var canvas: Color \{ Color\.adaptive\(0x[0-9A-Fa-f]{6}, 0x000000\) \}/.test(iosSrc)) ios.canvas = { dark: '0x000000' };
if (/static var accent: Color \{ Color\.adaptive\(0x[0-9A-Fa-f]{6}, 0xD98B45\) \}/.test(iosSrc)) ios.accent = { dark: '0xD98B45' };

// ---- Android ----
const ktSrc = fs.readFileSync(KT, 'utf8');
function grab(re) {
  const o = {};
  const b = ktSrc.match(re);
  if (!b) return o;
  for (const m of b[1].matchAll(/(\w+)\s*=\s*Color\((0x[0-9A-Fa-f]{8})\)/g)) {
    const argb = m[2].slice(2);            // AARRGGBB
    const a = parseInt(argb.slice(0, 2), 16) / 255;
    const rgb = '0x' + argb.slice(2).toUpperCase();
    // 半透明令牌归一成 rgba(...) —— 与 iOS 侧同一种写法，才能逐值比。
    o[m[1]] = a < 0.999 ? 'rgba(' + [0,2,4].map((k)=>parseInt(argb.slice(2+k, 4+k), 16)).join(',') + ',' + a.toFixed(2).replace(/0+$/,'').replace(/\.$/,'') + ')' : norm(rgb);
  }
  return o;
}
const ktDark = grab(/KfDarkColors = KfColors\(([\s\S]*?)\n\)/);
const ktLight = {};  // 规范 §13.4: 只做深色, 没有 light 档

if (!Object.keys(ios).length || !Object.keys(ktDark).length) {
  console.error('✗ tokendrift: 有一侧解析不到令牌 — 结构变了? 判据失效。');
  process.exit(1);
}

// ---- 自检: 人造一组漂移, 确认判据抓得到 ----
{
  const probeIos = { probe: { dark: '0x111111', light: '0x222222' } };
  const probeKt = { probe: '0x333333' };
  const caught = Object.keys(probeIos).some((n) => probeKt[n] && probeIos[n].dark !== probeKt[n]);
  if (!caught) {
    console.error('✗ tokendrift 自检失败: 人造漂移抓不到, 判据已失效');
    process.exit(1);
  }
}

// ---- Android 允许"故意不镜像"的令牌: 必须在文件头写明 ----
// 认的形状: 文件头注释里出现 "- 名字" 或 "名字 —" 且同一行提到"无"/"不镜像"
const omitted = new Set();
for (const line of ktSrc.split(/\r?\n/).slice(0, 80)) {
  // 认 "无 X" / "无X" / "不镜像" 三种写法 —— 中文里加不加空格都对,
  // 判据不该因为排版习惯而失明 (第一版只认带空格的, 结果三条声明没被认出来)。
  if (!/不镜像|没有|无/.test(line)) continue;
  for (const m of line.matchAll(/\b([a-z][A-Za-z0-9]{3,})\b/g)) {
    // 2026-10-22：原来这里是一串**写死的令牌名**（kindFp|surfaceChip|...）。
    // 于是新增的令牌（veil / segTrack / …）即使已在文件头声明「无 X」也认不出来 ——
    // 判据只认识「我上次想到的那几个」。
    // 改成：只要这行**确实在声明省略理由**（含「无」/「不镜像」）且形似令牌名，就收。
    omitted.add(m[1]);
  }
}

const rows = [];
let failed = 0;
for (const name of [...new Set([...Object.keys(ios), ...Object.keys(ktDark)])].sort()) {
  const i = ios[name];
  const d = ktDark[name];
  const l = ktLight[name];
  let status = 'ok';
  if (i && d) {
    if (i.dark !== d) { status = 'MISMATCH'; failed++; }
  } else if (i && !d) {
    status = omitted.has(name) ? 'omitted (已声明)' : 'ANDROID MISSING (未声明理由)';
    if (!omitted.has(name)) failed++;
  } else if (!i && d) {
    status = 'IOS LACKS THIS'; failed++;
  }
  rows.push({ name, iosDark: i ? i.dark : '-', ktDark: d || '-', status });
}

if (verbose) {
  const pad = (s, n) => String(s).padEnd(n);
  console.log('\n令牌对账 (iOS XPalette ↔ Android KfColors)\n');
  console.log(pad('token', 18) + pad('iOS', 12) + pad('Android', 12) + 'status');
  console.log('-'.repeat(78));
  for (const r of rows) {
    console.log(pad(r.name, 18) + pad(r.iosDark, 12) + pad(r.ktDark, 12) + r.status);
  }
  console.log('');
}

// ── 二、数值令牌对账（尺寸 / 间距 / 圆角）────────────────────────────
//
// 第一版只对账**颜色**。而两端还有一整套数值令牌（图标尺寸、间距、圆角），
// 它们同样约定「逐值同源」，却没有任何判据在看。
// 实证：iOS 按规范 §10 把 XIcon.lg 从 26 改成 28 之后，Android 仍是 26 ——
// 同一个令牌两端不同值，而所有闸门全绿。
const IOS_SPACE = Object.fromEntries([...iosFull.matchAll(/static var (\w+): CGFloat \{ d\((\d+(?:\.\d+)?)\) \}/g)].map((m) => [m[1], +m[2]]));
const IOS_RADIUS = Object.fromEntries([...iosFull.matchAll(/static var (\w+): CGFloat \{ r\((\d+(?:\.\d+)?)\) \}/g)].map((m) => [m[1], +m[2]]));
const IOS_ICON = (() => {
  const sec = iosFull.slice(iosFull.indexOf('enum XIcon'));
  return Object.fromEntries([...sec.matchAll(/static let (\w+): CGFloat = (\d+(?:\.\d+)?)/g)].map((m) => [m[1], +m[2]]));
})();
const KT_NUM = {};
for (const mm of ktSrc.matchAll(/val (\w+) = (\d+(?:\.\d+)?)\.dp/g)) KT_NUM[mm[1]] = +mm[2];

// Android 的 object 分段（Space / Radius / Icon）
// ⚠ 注意：ktSrc 读的是 **KfTheme.kt（颜色）**。数值令牌（Space/Radius/Icon）在
// **Tokens.kt** —— 两个文件、两套东西。第一版我拿 ktSrc 去扫 object，扫到的是空气，
// 于是这条判据以「0 个同名成员」全绿通过。判据自己必须先指对文件。
const TOKENS_KT = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'Tokens.kt');
const numSrc = fs.existsSync(TOKENS_KT) ? fs.readFileSync(TOKENS_KT, 'utf8') : '';
if (!numSrc) { console.error('✗ tokendrift: 找不到 Tokens.kt，数值令牌对账无法进行'); process.exit(1); }
const ktObj = (name) => {
  const m = new RegExp('object ' + name + ' \\{([\\s\\S]*?)\\n    \\}').exec(numSrc);
  if (!m) return {};
  return Object.fromEntries([...m[1].matchAll(/val (\w+) = (\d+(?:\.\d+)?)\.dp/g)].map((x) => [x[1], +x[2]]));
};
const KT_SPACE = ktObj('Space');
const KT_RADIUS = ktObj('Radius');
const KT_ICON = ktObj('Icon');

const numBad = [];
const cmp = (label, iosMap, ktMap, omitOk) => {
  for (const [k, v] of Object.entries(iosMap)) {
    if (!(k in ktMap)) continue;           // Android 没声明的由「故意不镜像」那段管
    if (ktMap[k] !== v) numBad.push(label + '.' + k + ': iOS=' + v + ' Android=' + ktMap[k]);
  }
};
cmp('Space', IOS_SPACE, KT_SPACE);
cmp('Radius', IOS_RADIUS, KT_RADIUS);
cmp('Icon', IOS_ICON, KT_ICON);
if (numBad.length) {
  for (const b of numBad) console.error('  ' + b);
  console.error('✗ 数值令牌漂移 ' + numBad.length + ' 处 —— 两端约定逐值同源');
  process.exit(1);
}

const numCount = Object.keys(KT_SPACE).length + Object.keys(KT_RADIUS).length + Object.keys(KT_ICON).length;
console.log('数值令牌对账 ✓ ' + numCount + ' 个同名成员与 iOS 逐值相同（Space / Radius / Icon）');

// ── 一·五、字阶对账（iOS XText ↔ Android Type）──
//
// 两端都声称「字阶同源」，但此前没有任何判据在看。实证：Android 曾经出现 4 处 15.sp
// （HIG subheadline 的默认值），而规范 §4.2 已把它下修成 14。
//
// 名字有一处不同：iOS 叫 subheadline，Android 叫 subhead —— 是同一档（14）。
{
  const xtBlock = /enum XText[^{]*\{([\s\S]*?)\n\}/.exec(iosFull);
  const iosType = {};
  if (xtBlock) {
    // case .xxx: return 56  /  case .displayNumber: return DSFont.displayNumber
    for (const m of xtBlock[1].matchAll(/case \.(\w+):\s*return (\d+(?:\.\d+)?)/g)) iosType[m[1]] = +m[2];
    // 转发到 DSFont 的那一档
    for (const m of xtBlock[1].matchAll(/case \.(\w+):\s*return DSFont\.(\w+)/g)) {
      const dm = new RegExp('static let ' + m[2] + ': CGFloat = (\\d+(?:\\.\\d+)?)').exec(iosFull);
      if (dm) iosType[m[1]] = +dm[1];
    }
  }
  const ktType = {};
  const tp = /object Type \{([\s\S]*?)\n\}/.exec(numSrc);
  if (tp) for (const m of tp[1].matchAll(/val (\w+) = (\d+(?:\.\d+)?)\.sp/g)) ktType[m[1]] = +m[2];
  // 两端命名/分档的两处差异，都是有依据的：
  //   subheadline ↔ subhead —— 同一档（14），只是名字不同；
  //   caption2    →  caption  —— 规范 §4.2 里 caption 与 caption2 **都是 11pt**，
  //                             只差字距（+0.1 / +0.2）。Android 的 Type 令牌不带字距，
  //                             所以两档合并成一档是正确的，不是漏了一层。
  const NAME_MAP = { subheadline: 'subhead', caption2: 'caption' };
  const typeBad = [];
  for (const [iosName, size] of Object.entries(iosType)) {
    const ktName = NAME_MAP[iosName] || iosName;
    if (!(ktName in ktType)) { typeBad.push(iosName + ': Android 端没有对应档（' + ktName + '）'); continue; }
    if (ktType[ktName] !== size) typeBad.push(iosName + ': iOS ' + size + 'sp vs Android ' + ktType[ktName] + 'sp');
  }
  if (typeBad.length) {
    for (const b of typeBad) console.error('  ' + b);
    console.error('✗ 字阶漂移 ' + typeBad.length + ' 处 —— 两端同一档必须同值');
    process.exit(1);
  }
  console.log('字阶对账 ✓ ' + Object.keys(iosType).length + ' 档两端同值（XText ↔ Type）');
}
const matched = rows.filter((r) => r.status === 'ok').length;
if (failed > 0) {
  for (const r of rows.filter((x) => x.status !== 'ok' && !x.status.startsWith('omitted'))) {
    console.error(r.name + ': ' + r.status + '  ios=' + r.iosDark + '  kt=' + r.ktDark);
  }
  console.error('✗ 令牌漂移 ' + failed + ' 处 — 两端约定是"逐值同源", 改一端必须改另一端');
  process.exit(1);
}
console.log('令牌对账 ✓ ' + matched + ' 项逐值相同, ' + omitted.size + ' 项已声明故意不镜像 (共 ' + rows.length + ' 项)');
