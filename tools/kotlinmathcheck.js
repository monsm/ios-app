#!/usr/bin/env node
// kotlinmathcheck —— Kotlin「隐式数值提升」闸门（判失败）。
//
// 2026-10-31（第 31 轮）：我在第 28 轮给 AutoOpenKit 加 p95 时写了
//     return (a[lo] + (a[hi] - a[lo]) * frac).roundToInt()
// 而 `a[lo]` 是 Int、`frac` 是 Double ⇒ `Int + Double` 在 **Kotlin 没有隐式提升**，
// 编译必拒。CI 连红 4 次（3ebbaae / 42906de / 1ec936d / 163fe03）。
//
// Swift 有隐式提升，所以从 Swift 逐行搬 Kotlin 时最容易踩这个坑。
// 本地 64 道闸门**没有一道看它** —— `kotlinshadow` 只做 JS 复刻的算术对拍，
// 不复刻"能不能编译"。
//
// 判据（保守，只报高置信度）：
//   一行里同时出现「整型下标/整型变量」与「浮点变量」参与 + - * 运算，
//   且该行**没有** toDouble()/toFloat()/toInt() 之类的显式转换，且不是注释。
//   具体实现：找形如 `X[i] + ... * frac` / `intVar + ... * doubleVar` 的模式。
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

// 浮点标识符（从全仓收集：`val x = ...Double` / `: Double` / `* 0.5` / `Math` 运算）
const floatVars = new Set(['frac', 'rank', 'log10', 'toDouble']);
const intVars = new Set();

const files = fs.readdirSync(KT_DIR).filter(f => f.endsWith('.kt'));
const srcs = {};
for (const f of files) srcs[f] = fs.readFileSync(path.join(KT_DIR, f), 'utf8');

// 收集变量类型
for (const [f, src] of Object.entries(srcs)) {
  for (const line of src.split(/\r?\n/)) {
    const c = strip(line);
    let m;
    if ((m = c.match(/\bval\s+(\w+)\s*:\s*Double\b/))) floatVars.add(m[1]);
    if ((m = c.match(/\bval\s+(\w+)\s*:\s*Int\b/))) intVars.add(m[1]);
    if ((m = c.match(/\bval\s+(\w+)\s*=\s*[^=]*\b(Double|roundToInt|toDouble|log10)\b/))) floatVars.add(m[1]);
  }
}

const bad = [];
for (const [f, src] of Object.entries(srcs)) {
  const L = src.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    const c = strip(L[i]);
    if (!c.trim()) continue;
    // 已显式转换的行放行
    if (/\bto(Double|Float|Int|Long)\s*\(/.test(c)) continue;
    // 模式: `<intExpr> + ... * <floatVar>` 且没有转换
    // 具体: `a[lo] + (a[hi] - a[lo]) * frac` 这类 —— 下标访问 + 乘浮点
    const idxArith = /\w+\[[^\]]+\]\s*[+\-]/.test(c) && /\*\s*\w+/.test(c);
    const floatMul = [...floatVars].some(v => new RegExp('\\*\\s*' + v + '\\b').test(c));
    if (idxArith && floatMul) bad.push(`${f}:${i + 1}  ${c.trim().slice(0, 76)}`);
  }
}

if (bad.length) {
  console.log(`✗ Kotlin 隐式数值提升 ${bad.length} 处（Int + Double 编译必拒）：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n修法：每个参与运算的量显式转 Double，例：');
  console.log('  a[lo].toDouble() + (a[hi].toDouble() - a[lo].toDouble()) * frac');
  process.exit(1);
}
console.log('✓ 未发现 Kotlin 隐式数值提升');
