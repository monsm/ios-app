#!/usr/bin/env node
// kotlinsyntaxcheck —— Kotlin「Swift 属性误写成方法/方法误写成属性」闸门（判失败）。
//
// 2026-10-31（第 46 轮，**CI 连红 5 次的根因**）：
// 第 37 轮我给 Android 标定弹窗写 `if (calSamples.isEmpty)` —— Swift 里 `isEmpty` 是**属性**，
// Kotlin 里它是**方法**，必须带 `()`。CI 报：
//     MainActivity.kt:582:36  Function invocation 'isEmpty()' expected.
//
// 这类「Swift 属性 ↔ Kotlin 方法」的差异是从 Swift 搬 Kotlin 时的高危区，
// 本地 68 道闸门没有一道覆盖。
//
// 判据（只查**确定**的差异，零误报优先）：
//   · `.isEmpty` 后面没有 `(` ⇒ 判失败
//   · `.reversed` 后面没有 `(` ⇒ 判失败
//   · `.uppercased(` / `.lowercased(` / `.hasPrefix(` / `.hasSuffix(` ⇒ 判失败（Swift 名）
//   · `String(format:` ⇒ 判失败（Swift 构造器）
//
// 不查的（Kotlin 合法或有歧义）：
//   · `.count` —— 本仓无 List.count 用法，但 `it.count` 可能是 data class 属性
//   · `.first` / `.last` —— `Pair.first` 是合法属性
// 正控：把 `calSamples.isEmpty()` 改回 `calSamples.isEmpty` ⇒ 报出 `MainActivity.kt:583 .isEmpty 必须带 ()`。
// 负控：全仓零误报（`.first`/`.count` 不查，因为 `Pair.first` 是合法属性）。

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const KT_DIR = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey');

if (!fs.existsSync(KT_DIR)) {
  console.log('✓ 无 android-app 工程，跳过');
  process.exit(0);
}

function strip(line) {
  let inStr = false;
  for (let i = 0; i < line.length - 1; i++) {
    const ch = line[i], prev = i > 0 ? line[i - 1] : '';
    if (ch === '"' && prev !== '\\') inStr = !inStr;
    if (!inStr && ch === '/' && line[i + 1] === '/') return line.slice(0, i);
  }
  return line;
}

const RULES = [
  { re: /\.isEmpty(?![(\w])/, msg: '`.isEmpty` 必须带 `()`（Swift 属性 → Kotlin 方法）' },
  { re: /\.reversed(?![(\w])/, msg: '`.reversed` 必须带 `()`（Kotlin 是方法）' },
  { re: /\.uppercased\s*\(/, msg: '`.uppercased()` 是 Swift，Kotlin 用 `.uppercase()`' },
  { re: /\.lowercased\s*\(/, msg: '`.lowercased()` 是 Swift，Kotlin 用 `.lowercase()`' },
  { re: /\.hasPrefix\s*\(/, msg: '`.hasPrefix()` 是 Swift，Kotlin 用 `.startsWith()`' },
  { re: /\.hasSuffix\s*\(/, msg: '`.hasSuffix()` 是 Swift，Kotlin 用 `.endsWith()`' },
  { re: /String\s*\(\s*format\s*:/, msg: '`String(format:)` 是 Swift，Kotlin 用 `String.format()`' },
];

const bad = [];
for (const f of fs.readdirSync(KT_DIR).filter(x => x.endsWith('.kt'))) {
  const src = fs.readFileSync(path.join(KT_DIR, f), 'utf8');
  src.split(/\r?\n/).forEach((line, i) => {
    if (/^\s*\/\//.test(line)) return;
    const c = strip(line);
    if (!c.trim()) return;
    for (const r of RULES) if (r.re.test(c)) bad.push(`${f}:${i + 1}  ${r.msg}\n      ${c.trim().slice(0, 78)}`);
  });
}

if (bad.length) {
  console.log(`✗ Kotlin 里混进 Swift 写法 ${bad.length} 处（编译必拒）：`);
  bad.forEach(x => console.log('  ' + x));
    console.log("\n修法：Swift 里是属性的（isEmpty/reversed），Kotlin 里是方法要加 ()；");
  console.log("      Swift 名（uppercased/hasPrefix）改成 Kotlin 名（uppercase/startsWith）。");
process.exit(1);
}
console.log('✓ 未发现 Swift 写法混入 Kotlin');
