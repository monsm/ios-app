#!/usr/bin/env node
// modal.js —— 第 19 道闸门：**同一时刻只呈现一个模态**。
//
// 依据 HIG `sheets` › Best practices：
//   "Display only one sheet at a time from the main interface."
//
// 为什么需要自动检查：SwiftUI 里同一个视图挂多个 `.sheet(isPresented:)` 时，
// 若两个布尔**同时**为 true，只有一个会真正呈现，另一个被**静默丢弃** ——
// 不崩、不报错、不留日志。表现是"点了按钮，什么都没弹"。
//
// 判什么：
//   ① 从 `confirmationDialog` / `.alert` 的按钮闭包里**直接**把某个 sheet 布尔置 true ⇒ 红。
//      对话框还在退场动画中，SwiftUI 可能丢掉这次呈现。正确做法是排队，
//      在对话框 isPresented 落回 false 之后（onChange 里）再呈现。
//   ② 同一视图里 `.sheet(isPresented:)` 多于 3 个 ⇒ 只提示不判红。
//
// 判红（仅 ①）。用法：node Gates/modal.js
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

const SHEET_VAR = /\.sheet\(isPresented:\s*\$([A-Za-z0-9_]+)/g;
const DIALOG = /\.(?:confirmationDialog|alert)\(/;

const fails = [];
const warns = [];

for (const f of walk(APP)) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  const sheetVars = [];
  let mm;
  SHEET_VAR.lastIndex = 0;
  while ((mm = SHEET_VAR.exec(src)) !== null) sheetVars.push(mm[1]);
  if (sheetVars.length > 3) {
    warns.push(rel + '  ' + sheetVars.length + ' 个 sheet 入口（' + sheetVars.join(', ') + '）');
  }
  if (sheetVars.length === 0) continue;

  for (let i = 0; i < lines.length; i++) {
    if (!DIALOG.test(lines[i])) continue;
    let depth = 0, started = false, body = '';
    for (let j = i; j < Math.min(lines.length, i + 60); j++) {
      body += lines[j] + '\n';
      for (const ch of lines[j]) {
        if (ch === '{') { depth++; started = true; }
        else if (ch === '}') depth--;
      }
      if (started && depth === 0) break;
    }
    for (const v of sheetVars) {
      const re = new RegExp(v + '\\s*=\\s*true');
      if (re.test(body)) {
        fails.push(rel + ':' + (i + 1) + '  对话框里直接置 ' + v + ' = true —— 对话框退场会吞掉这次呈现');
      }
    }
  }
}

for (const w of warns) console.log('  (提示) ' + w);
if (fails.length === 0) {
  console.log('modal: OK — 对话框不会直接抢 sheet，' + warns.length + ' 处多入口已提示');
  process.exit(0);
}
console.log('modal: FAIL — ' + fails.length + ' 处模态呈现会撞车（HIG sheets）\n');
for (const x of fails) console.log('  ' + x);
console.log('\n  处置：改成排队 —— 把意图存进 pending 状态，在对话框 isPresented 变 false 的 onChange 里再呈现。');
process.exit(1);