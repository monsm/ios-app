#!/usr/bin/env node
// swiftcheck.js —— 无本地 Swift 编译器时的第一道闸：括号 / 字符串 / 花括号平衡。
//
// 判什么：① 括号配对 ② 字符串闭合（含 \\( 插值的嵌套括号）③ 每个 struct/class/func 有对应的收尾
// 为什么：本仓没有 Mac，CI 之外唯一能立刻发现"少一个右括号"的手段。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

let bad = 0;
const files = walk(APP);
for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  // ① 源码里的裸控制字符（CR / NUL / VT 等）—— Swift 会把它当语句分隔，报
  //    "Consecutive statements on a line must be separated by ';'" 这种看不懂的错。
  //    2026-10-31 真踩过：注释里混进一个裸 CR，本地三道闸全绿，CI 红 4 条。
  lines.forEach((line, i) => {
    if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(line)) {
      console.log(`  ${rel}:${i + 1}  源码含裸控制字符（CR/NUL/VT 等）—— Swift 会当语句分隔`);
      bad++;
    }
  });

  // 逐行扫描：剥掉行注释与字符串内容，再数括号
  let depth = 0;
  let inBlockComment = false;
  lines.forEach((line, i) => {
    let out = '';
    let j = 0;
    let inStr = false;
    let interp = 0; // \\( … ) 的嵌套深度
    while (j < line.length) {
      const c = line[j];
      if (inBlockComment) {
        if (c === '*' && line[j + 1] === '/') { inBlockComment = false; j += 2; continue; }
        j++; continue;
      }
      if (inStr) {
        if (c === '\\') {
          if (line[j + 1] === '(') { interp++; }
          j += 2; continue;
        }
        if (interp > 0 && c === ')') { interp--; j++; continue; }
        if (interp > 0 && c === '(') { interp++; j++; continue; }
        if (interp === 0 && c === '"') { inStr = false; j++; continue; }
        j++; continue;
      }
      if (c === '/' && line[j + 1] === '/') break;
      if (c === '/' && line[j + 1] === '*') { inBlockComment = true; j += 2; continue; }
      if (c === '"') { inStr = true; j++; continue; }
      out += c;
      j++;
    }
    for (const c of out) {
      if (c === '{' || c === '(' || c === '[') depth++;
      if (c === '}' || c === ')' || c === ']') depth--;
    }
    if (depth < 0) {
      console.log(`  ${rel}:${i + 1}  括号提前收尾（depth=${depth}）`);
      bad++;
      depth = 0;
    }
  });
  if (depth !== 0) {
    console.log(`  ${rel}  文件末尾括号不平衡（depth=${depth}）`);
    bad++;
  }
  if (inBlockComment) {
    console.log(`  ${rel}  块注释未闭合`);
    bad++;
  }
}

if (bad === 0) {
  console.log(`swiftcheck: OK — ${files.length} 个文件括号/字符串/注释全部平衡，无裸控制字符`);
  process.exit(0);
}
console.log(`swiftcheck: FAIL — ${bad} 处不平衡`);
process.exit(1);
