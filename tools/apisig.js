#!/usr/bin/env node
// ============================================================================
// apisig.js — 组件签名闸门
// ============================================================================
//
// 为什么需要这一道:
//   21 道闸门查的是语法结构 / 令牌 / 对比度 / 括号, 它们都不知道
//   xFont 只收两个参数。而这类错误在 Swift 里是编译期报错,
//   CI 要 20 分钟才回话 —— 一轮下来只前进一小步。
//
//   这一道把「组件签名能静态判定的部分」提前到本地:
//     · xFont 只收 (Font, weight:), 传 design:/size:/relativeTo: 都是错的
//     · XStatusPill / XBusyButton / XMetricTile / XEmptyState 的参数名
//
// 判据全部来自 App/Core/Components.swift 的真实声明 —— 不是手抄的第二份。
// 每次跑都重新读声明, 所以改组件签名时这道闸门会自动跟上。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const LIB = path.join(ROOT, 'App', 'Core', 'Components.swift');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === '.git' || e.name === 'fixtures') continue;
    const q = path.join(dir, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (q.endsWith('.swift')) out.push(q);
  }
  return out;
}

let lib = '';
try { lib = fs.readFileSync(LIB, 'utf8'); } catch (e) {}
if (!lib) { console.error('✗ 读不到 App/Core/Components.swift'); process.exit(1); }

// ── 1. xFont 参数表 (从真实声明推) ──────────────────────────────────
const xfDecl = lib.match(/func xFont\(([^)]*)\)/);
let xfLabels = [];
if (xfDecl) {
  xfLabels = xfDecl[1].split(',').map(function (s) {
    const beforeColon = s.split(':')[0].trim();
    const toks = beforeColon.split(/\s+/);
    return toks[0] === '_' ? (toks[1] || '_') : toks[0];
  }).filter(Boolean);
}

// ── 2. 结构体参数表 ────────────────────────────────────────────────
// 用大括号配平取出 struct 的完整正文 —— 不能用"到下一个 struct 为止",
// 因为外层的枚举/扩展会把后面的内容也吞进来 (踩过一次)。
function structParams(name) {
  const head = lib.indexOf('struct ' + name);
  if (head < 0) return null;
  const open = lib.indexOf('{', head);
  if (open < 0) return null;
  let depth = 0, end = -1;
  for (let i = open; i < lib.length; i++) {
    const ch = lib[i];
    if (ch === '"') {                        // 跳过字符串
      i++;
      while (i < lib.length && lib[i] !== '"') { if (lib[i] === '\\') i++; i++; }
      continue;
    }
    if (ch === '{') depth++;
    else if (ch === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  if (end < 0) return null;
  const body = lib.slice(open, end + 1);
  const out = [];
  for (const line of body.split('\n')) {
    // 只认 4 空格缩进的存储属性 —— let 与 var 都要认。
    // (XStepBar 的 titles/current 是 let, 只匹配 var 会漏掉,
    //  于是 external 调用被误判成"没有这个参数"。)
    // computed var 后面跟 { 的不算。
    const pm = line.match(/^\s{4}(?:let|var) (\w+):\s*[^={]/);
    if (pm) out.push(pm[1]);
  }
  return out;
}

const STRUCTS = ['XStatusPill', 'XBusyButton', 'XMetricTile', 'XEmptyState', 'XRow', 'XStepBar'];
const structDefs = {};
for (const s of STRUCTS) {
  const ps = structParams(s);
  if (ps && ps.length) structDefs[s] = ps;
}

// ── 3. 扫全仓 ─────────────────────────────────────────────────────
const files = walk(path.join(ROOT, 'App'));
// xFont 的顶层实参里出现 design/size/relativeTo 才算错 ——
// 嵌在 .system(...) 里的是合法写法, 不能只看"有没有出现过"。
const XFONT_BAD_LABEL = /^(design|size|relativeTo|textStyle)$/;

function badXFontArgs(src) {
  const out = [];
  const re = /\bxFont\(/g;
  let m;
  while ((m = re.exec(src))) {
    let i = m.index + m[0].length, depth = 1, buf = '';
    while (i < src.length && depth > 0) {
      const ch = src[i];
      if (ch === '(') depth++;
      else if (ch === ')') { depth--; if (depth === 0) break; }
      buf += ch; i++;
    }
    for (const raw of topLevelLabels(buf)) {
      const lm = raw.trim().match(/^(\w+)\s*:/);
      if (lm && XFONT_BAD_LABEL.test(lm[1])) {
        out.push({ line: src.slice(0, m.index).split('\n').length, label: lm[1] });
      }
    }
  }
  return out;
}

function topLevelLabels(argstr) {
  let depth = 0, cur = '', out = [];
  for (const ch of argstr) {
    if ('([{'.indexOf(ch) >= 0) depth++;
    else if (')]}'.indexOf(ch) >= 0) depth--;
    if (ch === ',' && depth === 0) { out.push(cur); cur = ''; }
    else cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out;
}

function checkStructArgs(name, src) {
  const known = new Set(structDefs[name]);
  const problems = [];
  const re = new RegExp('\\b' + name + '\\(', 'g');
  let m;
  while ((m = re.exec(src))) {
    let i = m.index + m[0].length, depth = 1, buf = '';
    while (i < src.length && depth > 0) {
      const ch = src[i];
      if (ch === '(') depth++;
      else if (ch === ')') { depth--; if (depth === 0) break; }
      buf += ch; i++;
    }
    for (const raw of topLevelLabels(buf)) {
      const lm = raw.trim().match(/^(\w+)\s*:/);
      if (!lm) continue;
      if (!known.has(lm[1])) {
        problems.push({
          line: src.slice(0, m.index).split('\n').length,
          msg: name + ' 没有参数 ' + lm[1] + ' (可用: ' + Array.from(known).join(', ') + ')'
        });
      }
    }
  }
  return problems;
}

const allProblems = [];
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(ROOT, f);
  for (const b of badXFontArgs(src)) {
    allProblems.push({ rel: rel, line: b.line,
      msg: 'xFont 顶层不能传 ' + b.label + ' (只收 ' + xfLabels.join(', ') + ') —— 圆体请写 .xFont(.system(size: N, design: .rounded), weight: .w)' });
  }
  for (const nm of Object.keys(structDefs)) {
    for (const pr of checkStructArgs(nm, src)) {
      allProblems.push({ rel: rel, line: pr.line, msg: pr.msg });
    }
  }
}

// ── 4. 自检: 正控 / 反控 ───────────────────────────────────────────
const probes = [
  { src: '.xFont(.title2, weight: .semibold, design: .rounded)', bad: true,  why: 'xFont 传 design' },
  { src: '.xFont(.system(.title2, design: .rounded), weight: .semibold)', bad: false, why: '合法圆体写法' },
  { src: 'XStatusPill(text: "a", tone: .ok, systemImage: "x")', bad: false, why: 'XStatusPill 合法' },
  { src: 'XStatusPill(text: "a", image: "x")', bad: true, why: 'XStatusPill 错参数名' }
];
let probeFail = 0;
for (const pr of probes) {
  let got = badXFontArgs(pr.src).length > 0;
  if (!got && structDefs.XStatusPill) {
    for (const q of checkStructArgs('XStatusPill', pr.src)) { got = true; break; }
  }
  if (got !== pr.bad) {
    console.error('✗ 自检失败: ' + pr.why + ' (期望 ' + pr.bad + ', 实际 ' + got + ')');
    probeFail++;
  }
}
if (probeFail > 0) { console.error('✗ 闸门自检不通过, 判据已失效'); process.exit(1); }

// ── 5. 输出 ───────────────────────────────────────────────────────
if (allProblems.length === 0) {
  console.log('组件签名检查 ✓ (' + files.length + ' 文件, ' + Object.keys(structDefs).length + ' 组件, 自检 ' + probes.length + '/' + probes.length + ')');
  process.exit(0);
}
for (const p of allProblems) console.error(p.rel + ':' + p.line + ': ' + p.msg);
console.error('✗ 组件签名 ' + allProblems.length + ' 处不符');
process.exit(1);