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
  // 2026-10-23: 六图补档新增 Type.hero(44) 与 Type.small(13)，与 iOS DSFont 同源。
  // 新增字号档时这里必须同步 —— 名单是封闭的。
  const SPEC = new Set([11, 12, 13, 14, 16, 18, 19, 30, 36, 44, 56]);   // §4.2 十一档
  const bad = [];
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((l, i) => {
      const m = /fontSize\s*=\s*([0-9]+(?:\.[0-9]+)?)\.sp/.exec(l);
      if (!m) return;
      if (!SPEC.has(parseFloat(m[1]))) bad.push(path.relative(ROOT, f) + ':' + (i + 1) + '  ' + m[1] + 'sp 不在 §4.2 档位上');
    });
  }
  // 注解必须紧贴函数签名 —— 实证：我把 LocalKfColors 插在 `@Composable` 与 `fun` 之间，
  // 注解就不再附着，报「Functions which invoke @Composable functions must be marked with
  // the @Composable annotation」。判据：凡是参数里出现 `@Composable` 或体内调
  // CompositionLocalProvider 的函数，紧邻上一行（跳过空行）必须是 @Composable。
  const annotBad = [];
  for (const f of walk(SRC)) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((l, i) => {
      if (!/^\s*(internal |private |public )?fun \w+\(/.test(l)) return;
      // 看这个函数签名（到闭合括号为止）里有没有 @Composable 参数
      // 用**括号深度**切签名：默认值里也有括号（@Suppress(...)、() -> Unit），
      // 靠正则找「) 后面跟 {」会被 `dark: Boolean = true` 里的 `=` 骗到。
      let sig = '', k = i, depth = 0, closed = false;
      while (k < lines.length && k < i + 14) {
        const L = lines[k];
        sig += L;
        for (const ch of L) { if (ch === '(') depth++; else if (ch === ')') depth--; }
        if (depth <= 0 && k > i - 1 && /\bfun\b/.test(sig)) {
          // 签名闭合：这一行 `)` 之后必须是 `{` 或 `:` 才算块状函数
          const after = L.slice(L.lastIndexOf(')') + 1);
          if (/^\s*(\{|:)/.test(after)) closed = true;
          break;
        }
        k++;
      }
      if (!closed) return;   // 表达式函数 / 单行签名，不归这条判据管
      const bodyHasProvider = lines.slice(k, Math.min(k + 4, lines.length)).some((x) => /CompositionLocalProvider/.test(x));      if (!/@Composable/.test(sig) && !bodyHasProvider) return;
      if (/^\s*@Composable/.test(l)) return;
      // 往上找最近的非空行
      let up = i - 1;
      while (up >= 0 && lines[up].trim() === '') up--;
      if (up >= 0 && /^\s*@Composable/.test(lines[up])) return;
      annotBad.push(path.relative(ROOT, f) + ':' + (i + 1) + '  ' + l.trim().slice(0, 50));
    });
  }
  if (annotBad.length) {
    for (const b of annotBad.slice(0, 6)) console.error('  ' + b);
    console.error('✗ 有 ' + annotBad.length + ' 个 @Composable 函数缺注解（或注解被注释行隔开）');
    process.exitCode = 1;
  } else {
    console.log('Composable 注解 ✓ 都紧贴函数签名');
// ── 间距上下文里不许硬编码与令牌同值的 dp ──
//
// 与 iOS 侧 XSpace 的作用相同：间距只有一个来源。
// 实证：MainActivity 里 `Spacer(Modifier.height(4.dp))` / `padding(vertical = 48.dp)` ——
// 两者分别等于 KfTokens.Space.xs 与 KfTokens.Hit.min，写在调用点就成了第二个来源。
//
// 只判**间距上下文**（Spacer 高度 / padding）：`.size(8.dp)` 是图标尺寸、
// `24.dp.toPx()` 是长度计算，都不归这条管。
{
  const TOKEN_DP = { 4: 'Space.xs', 8: 'Space.s', 12: 'Space.m', 16: 'Space.l', 24: 'Space.xl',
                     28: 'Space.section', 14: 'Space.gutter', 40: 'Space.pageTop', 48: 'Hit.min' };
  const SPACING = [
    /Spacer\(Modifier\.height\((\d+)\.dp\)\)/,
    /Spacer\(Modifier\.width\((\d+)\.dp\)\)/,
    /padding\([^)]*?[=,(]\s*(\d+)\.dp/
  ];
  const bad = [];
  for (const f of walk(SRC)) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((l, i) => {
      const code = l.replace(/\/\/.*$/, '');
      for (const re of SPACING) {
        const m = re.exec(code);
        if (!m) continue;
        const tok = TOKEN_DP[Number(m[1])];
        if (!tok) continue;
        bad.push(path.relative(ROOT, f) + ':' + (i + 1) + '  硬编码 ' + m[1] + '.dp（= KfTokens.' + tok + '）');
        break;
      }
    });
  }
  if (bad.length) {
    for (const b of bad.slice(0, 8)) console.error('  ' + b);
    console.error('✗ 有 ' + bad.length + ' 处间距硬编码了与令牌同值的 dp —— 间距只许有一个来源');
    process.exitCode = 1;
  } else {
    console.log('间距令牌 ✓ 间距上下文没有与令牌同值的硬编码 dp');
  }
}
  }
  if (bad.length) {
    for (const b of bad) console.error('  ' + b);
    console.error('✗ Android 字号有 ' + bad.length + ' 处不在规范 §4.2 档位上');
    process.exit(1);
  }
}
// ── 编译期错误的两类静态可判形态 ──
//
// 实证（2026-10-23 CI）：删 KfLightColors 时把**同一条 LocalKfColors 声明也删了**，
// 报 Unresolved reference；另一处是我的一次编辑把 Kotlin 字符串里的 `\n` 写成了真实换行，
// 报 Syntax error: Expecting '"'. 两条都不是设计问题，却让整包编不出来。
{
  const kf = fs.readFileSync(path.join(ROOT, 'android-app/app/src/main/java/com/aapk/kfkey/KfTheme.kt'), 'utf8');
  if (!/val LocalKfColors\s*=/.test(kf)) {
    console.error('✗ KfTheme.kt 里没有 LocalKfColors 声明 —— 它是唯一的色板通道，删了全端 Unresolved reference');
    process.exitCode = 1;
  } else {
    console.log('色板通道 ✓ LocalKfColors 声明存在');
  }

  // 字符串字面量里的真实换行（不是 \n 转义）在同一条语句里出现 = 语法错误。
  const bad = [];
  for (const f of walk(SRC)) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    let inRaw = false;
    lines.forEach((l, i) => {
      const code = l.replace(/\/\/.*$/, '');
      if (/"""/.test(code)) { const n = (code.match(/"""/g) || []).length; if (n % 2 === 1) inRaw = !inRaw; return; }
      if (inRaw) return;
      const q = (code.match(/(?<!\\)"/g) || []).length;
      if (q % 2 === 1) bad.push(path.relative(ROOT, f) + ':' + (i + 1) + '  ' + l.trim().slice(0, 60));
    });
  }
  if (bad.length) {
    for (const b of bad.slice(0, 8)) console.error('  ' + b);
    console.error('✗ 有 ' + bad.length + ' 行字符串未闭合 —— 多半是把 \\n 写成了真实换行');
    process.exitCode = 1;
  } else {
    console.log('字符串字面量 ✓ 没有未闭合行');
  }
}
console.log('Android 字号全部落在 §4.2 档位上 ✓');