#!/usr/bin/env node
// argorder.js —— 第 42 道闸门：共享组件的调用点，参数必须按声明顺序传。
//
// 为什么需要它（2026-11-06 的真事故）：
//   Swift 的 memberwise init **要求实参按声明顺序**。V10 新增 VTextField 后，
//   RecordDetailHomeScreen 写成 `autocorrection: false, onSubmit: {…}` ——
//   本地 41 道闸门全绿（swiftparse 只看语法，tokens 只看字面量），
//   直到云端 xcodebuild 才报：
//     error: argument 'onSubmit' must precede argument 'autocorrection'
//   也就是说：**这类错本地查不出来，只能等一轮云编译**（约 15–25 分钟）。
//
// 判据：把共享组件的参数名与声明顺序列在表里，逐个调用点比对 ——
//   ① 用了表里没有的参数名 → 判红（拼错了或组件改了签名）；
//   ② 具名参数的序号不是递增 → 判红（顺序错，云编译器会拒）。
// 只查这几个组件：它们是本轮新增、且调用点最多的那几个；全仓泛化会误报。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

// 声明顺序 = Swift 里属性/参数的书写顺序。
const SIGS = {
  VTextField: ['placeholder', 'text', 'secure', 'keyboard', 'contentType', 'submitLabel',
               'onSubmit', 'autocorrection', 'capitalization', 'hasError', 'isDisabled', 'autofocus'],
  V8ActionButton: ['title', 'style', 'systemImage', 'busy', 'fullWidth', 'action'],
  VEmptyHint: ['text', 'systemImage', 'actionTitle', 'action'],
  VButtonRow: ['spacing', 'content'],
};

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 把实参按顶层逗号切开（括号内、字符串内的逗号不算）。
function splitArgs(args) {
  const parts = [];
  let depth = 0, cur = '', inStr = false, esc = false;
  for (const ch of args) {
    if (esc) { cur += ch; esc = false; continue; }
    if (ch === '\\') { cur += ch; esc = true; continue; }
    if (ch === '"') { inStr = !inStr; cur += ch; continue; }
    if (!inStr) {
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      else if (ch === ')' || ch === ']' || ch === '}') depth--;
      else if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; continue; }
    }
    cur += ch;
  }
  parts.push(cur);
  return parts;
}

const findings = [];
for (const f of walk(APP)) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  for (const [name, order] of Object.entries(SIGS)) {
    const re = new RegExp('\\b' + name + '\\(', 'g');
    let m;
    while ((m = re.exec(src)) !== null) {
      const open = m.index + m[0].length - 1;
      let depth = 0, j = open;
      while (j < src.length) {
        const c = src[j];
        if (c === '(') depth++;
        else if (c === ')') { depth--; if (depth === 0) break; }
        j++;
      }
      const args = src.slice(open + 1, j);
      const labels = [];
      for (const part of splitArgs(args)) {
        const t = part.trim();
        if (!t) continue;
        const mm = /^([a-zA-Z_]\w*)\s*:/.exec(t);
        labels.push(mm ? mm[1] : null);   // null = 位置参数 / 尾随闭包
      }
      const named = labels.filter((l) => l !== null);
      const unknown = named.filter((l) => !order.includes(l));
      const line = src.slice(0, m.index).split('\n').length;
      if (unknown.length) {
        findings.push({ file: rel, line, name, why: '未知参数名：' + unknown.join(', ') });
        continue;
      }
      const idx = named.map((l) => order.indexOf(l));
      const sorted = idx.slice().sort((a, b) => a - b);
      if (idx.join(',') !== sorted.join(',')) {
        findings.push({ file: rel, line, name, why: '参数顺序与声明不一致（应为 ' + order.slice(0, order.length).join(' < ') + '）' });
      }
    }
  }
}

if (findings.length === 0) {
  console.log('argorder: OK — 共享组件的调用点参数顺序都对');
  process.exit(0);
}
console.log('argorder: FAIL — ' + findings.length + ' 处参数顺序/名称不对（云编译器会拒）');
for (const f of findings) console.log('  ' + f.file + ':' + f.line + '  ' + f.name + '  ' + f.why);
process.exit(1);
