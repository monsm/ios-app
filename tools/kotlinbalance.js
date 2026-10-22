#!/usr/bin/env node
// tools/kotlinbalance.js — Kotlin 源码括号码平衡检查 (判失败)
//
// 为什么需要: 本机**没有 java / javac / gradle / kotlinc**(实测全 NOT FOUND),
// Android 侧唯一能跑的是 tools/kotlinshadow.js —— 而它做的是**字节面正则对拍**,
// 只管自动开锁状态机那八处源码形状, 对"我少写了一个右括号"完全无感。
//
// 所以这条闸门补的是最基础的一层: 括号、方括号、圆括号是否配平。
// 它不能证明能编译 —— 它能证明的是"结构没有当场破掉", 这是无编译器环境下的最低防线。
//
// 判据要点:
//   · 必须跳过 Kotlin 的四种字符串形态: 普通串 "…"、原始串 """…"""、字符 '…'、注释
//     (漏掉原始串会让带引号的文案把后面整段吃掉 —— 第一版就栽在这)
//   · 只对**改动过的**文件跑没有意义, 全量跑很快 (9 个文件)
//
// 用法: node tools/kotlinbalance.js   (不配平 exit 1)
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java');

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.kt')) out.push(p);
  }
  return out;
}

function scan(src) {
  const r = { braces: 0, parens: 0, brackets: 0 };
  let i = 0;
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    // 行注释
    if (c === '/' && n === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    // 块注释 (Kotlin 的块注释可嵌套 —— 本仓未用到, 但按可嵌套处理不会更糟)
    if (c === '/' && n === '*') {
      let depth = 1; i += 2;
      while (i < src.length && depth > 0) {
        if (src[i] === '/' && src[i + 1] === '*') { depth++; i += 2; continue; }
        if (src[i] === '*' && src[i + 1] === '/') { depth--; i += 2; continue; }
        i++;
      }
      continue;
    }
    // 原始字符串 """…"""  —— 里面可以有任何括号与引号, 必须整段跳过
    if (c === '"' && n === '"' && src[i + 2] === '"') {
      i += 3;
      while (i < src.length && !(src[i] === '"' && src[i + 1] === '"' && src[i + 2] === '"')) i++;
      i += 3;
      continue;
    }
    // 普通字符串 (可含 \\ 转义 与 \$ 插值 —— 插值里的括号属于代码,
    // 但本仓插值内没有裸括号, 按整段跳过更安全: 漏跳会把文案里的 ( ) 数进去)
    if (c === '"') {
      i++;
      while (i < src.length && src[i] !== '"') { if (src[i] === '\\') i++; i++; }
      i++;
      continue;
    }
    // 字符字面量
    if (c === "'") {
      i++;
      while (i < src.length && src[i] !== "'") { if (src[i] === '\\') i++; i++; }
      i++;
      continue;
    }
    if (c === '{') r.braces++;
    else if (c === '}') r.braces--;
    else if (c === '(') r.parens++;
    else if (c === ')') r.parens--;
    else if (c === '[') r.brackets++;
    else if (c === ']') r.brackets--;
    i++;
  }
  return r;
}

// ---- 自检: 四种字符串形态都必须被跳过 ----
{
  const probes = [
    { src: 'val a = "("',  why: '普通串里的左括号' },
    { src: 'val a = """("""', why: '原始串里的左括号' },
    { src: "val a = '('\n", why: '字符字面量里的左括号' },
    { src: '// (\nval a = 1', why: '行注释里的左括号' },
    { src: '/* ( */ val a = 1', why: '块注释里的左括号' },
  ];
  let bad = 0;
  for (const p of probes) {
    const r = scan(p.src);
    if (r.parens !== 0 || r.braces !== 0) { console.error('✗ 自检失败: ' + p.why + ' 被数进去了'); bad++; }
  }
  const real = scan('fun f() { if (true) { } }');
  if (real.braces !== 0 || real.parens !== 0) { console.error('✗ 自检失败: 真代码被漏数'); bad++; }
  if (bad > 0) { console.error('✗ kotlinbalance 自检不通过, 判据已失效'); process.exit(1); }
}

const files = walk(SRC);
if (!files.length) {
  console.log('kotlinbalance: 没找到 .kt —— 目录结构变了? 跳过 (退 0)');
  process.exit(0);
}

let fail = 0;
for (const f of files) {
  const rel = path.relative(ROOT, f);
  const r = scan(fs.readFileSync(f, 'utf8'));
  if (r.braces !== 0 || r.parens !== 0 || r.brackets !== 0) {
    console.error(rel + ': braces=' + r.braces + ' parens=' + r.parens + ' brackets=' + r.brackets);
    fail++;
  }
}

if (fail > 0) {
  console.error('✗ ' + fail + ' 个 Kotlin 文件括号不配平');
  process.exit(1);
}
console.log(files.length + ' 个 Kotlin 文件括号配平 ✓ (这**不证明**能编译 —— 本机无 kotlinc)');

// ── 二、字号必须走 Type 令牌（规范 §4.2）───────────────────────────────
//
// 本端此前把字号散写在调用点，于是出现了 `15.sp` —— 那正是规范点名批评的
// HIG subheadline 默认值（规范已下修成 14）。iOS 侧 766 处已全部收到 XText，
// 本端现在也补了 Type 令牌，这条判据防它退回去。
{
  const SPEC = new Set([11, 12, 14, 16, 18, 19, 30, 36, 56]);   // §4.2 的十档
  const bad = [];
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((l, i) => {
      const m = /fontSize\s*=\s*([0-9]+(?:\.[0-9]+)?)\.sp/.exec(l);
      if (!m) return;
      if (!SPEC.has(parseFloat(m[1]))) bad.push(path.relative(ROOT, f) + ':' + (i + 1) + '  ' + m[1] + 'sp 不在 §4.2 档位上');
    });
  }
  if (bad.length) {
    for (const b of bad) console.error('  ' + b);
    console.error('✗ Android 字号有 ' + bad.length + ' 处不在规范 §4.2 档位上');
    process.exit(1);
  }
}
console.log('Android 字号全部落在 §4.2 档位上 ✓');