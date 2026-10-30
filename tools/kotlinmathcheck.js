#!/usr/bin/env node
// kotlinmathcheck —— Kotlin「隐式数值提升」闸门（判失败）。
//
// 2026-10-31：第 28 轮我给 AutoOpenKit 加 p95 时写了
//     return (a[lo] + (a[hi] - a[lo]) * frac).roundToInt()
// 第 31 轮只修了这一处、判据也太窄，于是漏掉 disarmThreshold 里的
//     (base + 10 * log10(0.5))            ← base 是 Int，10*log10(0.5) 是 Double
// 同一个错误，CI 继续红。
//
// ⚠ 判据设计说明（第 32 轮推翻重写）：
//   第一版尝试"收集所有变量类型再判混算"，但 Compose 绘图代码里 `g`/`cx` 是 Float、
//   `0.42f` 也是 Float（合法），而我的收集器把它们误判成 Int ⇒ 25 处误报。
//   **误报率高的闸门会被训练成忽略**（本仓第 67 轮的教训），所以放弃那个方向。
//
//   现判据：只查**已知是 Int 的形参**与**浮点字面量/Double 表达式**在同一个算术里出现，
//   且该行没有 toDouble()/toInt() 转换。变量类型只从**函数签名**（`x: Int`）收集，
//   不从表达式推断 —— 签名是可靠的，推断不可靠。
//
//   为把误报降到 0：只扫**不含 Compose 绘图 API**的文件（drawCircle/Offset/Path 这些
//   天然全是 Float，不在本闸门的关注范围）。本仓的纯逻辑文件是 AutoOpenKit.kt / KfProtocol.kt。
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

// 只看纯逻辑文件（Compose 绘图天然全 Float，排除以免误报）
const TARGETS = ['AutoOpenKit.kt', 'KfProtocol.kt', 'LockStore.kt', 'BleUnlocker.kt'];

const bad = [];
for (const f of TARGETS) {
  const p = path.join(KT_DIR, f);
  if (!fs.existsSync(p)) continue;
  const src = fs.readFileSync(p, 'utf8');
  const L = src.split(/\r?\n/);

  // ① 从函数签名收集 Int 形参（同名在多个函数里都记，保守）
  const intParams = new Set();
  for (const line of L) {
    const c = strip(line);
    if (!/^\s*(fun|private fun|internal fun)\s+\w+\s*\(/.test(c) && !/\bfun\s+\w+\s*\(/.test(c)) continue;
    for (const arg of (c.match(/\b\w+\s*:\s*Int\b/g) || [])) {
      const m = arg.match(/\b(\w+)\s*:\s*Int\b/);
      if (m) intParams.add(m[1]);
    }
  }

  for (let i = 0; i < L.length; i++) {

  // ② 从 `val x = <含浮点>` 收集 Double 局部量。
  //    为什么这条可靠：纯逻辑文件里 `val frac = rank - lo` 这种，右侧含 Double 运算
  //    或浮点字面量，Kotlin 的类型推断必然得到 Double。Compose 文件已被 TARGETS 排除。
  const doubleLocals = new Set();
  for (const line of L) {
    const c = strip(line);
    const m = c.match(/\bval\s+(\w+)\s*=\s*(.+)$/);
    if (!m) continue;
    if (/\b\d+\.\d+|log10\s*\(|toDouble\s*\(\s*\)/.test(m[2])) doubleLocals.add(m[1]);
  }
    const c = strip(L[i]);
    if (!c.trim()) continue;
    if (/\bto(Double|Float|Int|Long)\s*\(/.test(c)) continue;   // 已显式转换
    if (!/[+\-*/]/.test(c)) continue;
    if (/^\s*\*/.test(L[i])) continue;                           // 块注释

    // 本行是否用到已知 Int 形参
    const usesInt = [...intParams].some(v => new RegExp('\\b' + v + '\\b').test(c));
    if (!usesInt) continue;

    // 本行是否含浮点字面量（0.5 / 0.95）或 log10/Double 运算
    const hasFloatLiteral = /\b\d+\.\d+\b/.test(c);
    const hasFloatOp = /\blog10\s*\(|\.toDouble\s*\(/.test(c);
    if (!hasFloatLiteral && !hasFloatOp) continue;

    // 本行是否用到已知 Double 局部量（如 `frac`）
    const usesDoubleLocal = [...doubleLocals].some(v => new RegExp('\\b' + v + '\\b').test(c));
    if (!hasFloatLiteral && !hasFloatOp && !usesDoubleLocal) continue;

    bad.push(`${f}:${i + 1}  ${c.trim().slice(0, 78)}`);
  }
}

if (bad.length) {
  console.log(`✗ Kotlin 隐式数值提升 ${bad.length} 处（Int 形参与浮点运算混用，编译必拒）：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n修法：把整型一侧显式转 Double，例：');
  console.log('  (base.toDouble() + 10 * log10(0.5)).roundToInt()');
  console.log('  a[lo].toDouble() + (a[hi].toDouble() - a[lo].toDouble()) * frac');
  process.exit(1);
}
console.log('✓ 未发现 Kotlin 隐式数值提升');
