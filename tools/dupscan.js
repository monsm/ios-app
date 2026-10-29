#!/usr/bin/env node
// tools/dupscan.js — 同文件重复声明扫描（判失败）
//
// 为什么需要：2026-10-29 用「按块替换」改代码时，把旧函数留在原地没删干净
// （DiagKit 的 all()/today()/append()），本地所有静态闸门全绿、到 CI 编译才报
// "invalid redeclaration"。这类错误完全可以本地判掉。
//
// 判据：**同一类型作用域内**出现完全相同的函数签名（函数名 + 归一化参数标签序列）。
// Swift 允许重载，但本仓没有需要"同签名重载"的地方；一旦命中就是漏删。
// 通过大括号深度追踪 struct/enum/class/extension/protocol 与 func 作用域，
// 避免把「不同 struct 各自实现的 makeBody(configuration:)」误报。
//
// 用法：node tools/dupscan.js
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

function normalizeParams(s) {
  const inner = s.trim();
  if (!inner) return '';
  return inner.split(',')
    .map(p => p.trim())
    .filter(Boolean)
    .map(p => p.split(':')[0].trim())
    .join(',');
}

function stripComment(line) {
  let out = '';
  let inStr = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"' && line[i - 1] !== '\\') inStr = !inStr;
    if (!inStr && c === '/' && line[i + 1] === '/') break;
    out += c;
  }
  return out;
}

const problems = [];

for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const P = path.join(dir, f);
    const L = fs.readFileSync(P, 'utf8').split(/\r?\n/);

    let depth = 0;
    const stack = [];   // { kind: 'type'|'func', name, depth }
    const seen = new Map();  // scope+sig -> [line]

    for (let i = 0; i < L.length; i++) {
      const raw = L[i];
      const t = raw.trim();
      if (t.startsWith('//') || t.startsWith('///')) continue;
      const code = stripComment(raw);

      const typeM = /^(?:@\w+(?:\([^)]*\))?\s+)?(?:final\s+|private\s+|fileprivate\s+|internal\s+|public\s+|open\s+)?(struct|enum|class|extension|protocol|actor)\s+(\w+)/.exec(t);
      const funcM = /^(?:@\w+(?:\([^)]*\))?\s+)?(?:private\s+|fileprivate\s+|internal\s+|public\s+|open\s+)?(?:static\s+|class\s+)?(?:mutating\s+)?func\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)/.exec(t);

      // 记录（只记"直接位于类型作用域内"的函数）
      if (funcM && stack.length && stack[stack.length - 1].kind === 'type') {
        const scope = stack.map(s => s.name).join('.');
        const sig = scope + '|' + funcM[1] + '(' + normalizeParams(funcM[2]) + ')';
        if (!seen.has(sig)) seen.set(sig, []);
        seen.get(sig).push(i + 1);
      }

      // 更新大括号深度（同时数本行开/闭，判断这个声明是不是"单行闭合"）
      let opened = 0, closed = 0;
      for (const ch of code) {
        if (ch === '{') { depth++; opened++; }
        else if (ch === '}') { depth--; closed++; }
      }
      const net = opened - closed;

      // 入栈：只有**跨行**的声明才占作用域（单行 { } 不占）
      if (typeM && net > 0) stack.push({ kind: 'type', name: typeM[2], depth });
      else if (funcM && net > 0) stack.push({ kind: 'func', name: funcM[1], depth });

      // 出栈
      while (stack.length && depth < stack[stack.length - 1].depth) stack.pop();
    }

    for (const [sig, lines] of seen) {
      if (lines.length > 1) problems.push({ file: `${d}/${f}`, sig, lines });
    }
  }
}

console.log(`重复函数声明扫描: ${problems.length} 组`);
if (problems.length) {
  for (const p of problems) {
    console.error(`  ✗ ${p.file}  ${p.sig}  出现在行 ${p.lines.join(', ')}`);
  }
  console.error('修法：删除多留的那一份（通常是"按块替换"没删旧定义）。');
  process.exit(1);
}
console.log('✓ 同类型作用域内无重复函数签名');
