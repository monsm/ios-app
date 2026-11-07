#!/usr/bin/env node
// stringlit.js —— 字符串字面量的完整性闸门。
//
// 为什么要有它：`Gates/swiftparse.js`（tree-sitter）**没有**抓到这个真实缺陷 ——
// 一行 Swift 字符串里混进了**裸换行**（本该是 `\n`），tree-sitter 把它当多行字符串
// 解析过去了，编译时才报 "Unterminated string literal"。
// 真编译只在 CI 上跑，而 CI 一轮几分钟 —— 这种错误应该在本地一秒内红。
//
// 规则（Swift 语法）：
//   · 普通字符串（`"..."`）**不能跨行** —— 跨行就是没闭合；
//   · 多行字符串（`"""..."""`）可以跨行；
//   · 字符串里的 `\"` 是转义引号，不算闭合。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const findings = [];

for (const file of walk(APP)) {
  const rel = path.relative(ROOT, file).split(path.sep).join('/');
  const src = fs.readFileSync(file, 'utf8');
  let state = 'normal';       // normal | lineComment | string | multiline
  let line = 1;
  let i = 0;
  const n = src.length;
  while (i < n) {
    const ch = src[i];
    const next = src[i + 1];
    if (ch === '\n') {
      if (state === 'string') {
        findings.push(`${rel}:${line}  字符串没有闭合就换行了（多半是 "\\n" 写成了真换行）`);
        state = 'normal';
      } else if (state === 'lineComment') {
        state = 'normal';
      }
      line++;
      i++;
      continue;
    }
    if (state === 'normal') {
      if (ch === '/' && next === '/') { state = 'lineComment'; i += 2; continue; }
      if (ch === '"' && src.startsWith('"""', i)) { state = 'multiline'; i += 3; continue; }
      if (ch === '"') { state = 'string'; i++; continue; }
      i++;
      continue;
    }
    if (state === 'lineComment') { i++; continue; }
    if (state === 'string') {
      if (ch === '\\') { i += 2; continue; }   // 转义：跳过下一个字符
      if (ch === '"') { state = 'normal'; }
      i++;
      continue;
    }
    if (state === 'multiline') {
      if (src.startsWith('"""', i)) { state = 'normal'; i += 3; continue; }
      i++;
      continue;
    }
  }
  if (state === 'string') {
    findings.push(`${rel}:${line}  文件结束时字符串仍未闭合`);
  }
}

if (findings.length) {
  console.error('stringlit: FAIL — 字符串字面量没闭合：');
  for (const f of findings) console.error('  ' + f);
  process.exit(1);
}
console.log(`stringlit: OK — ${walk(APP).length} 个 Swift 文件的字符串字面量全部闭合`);
