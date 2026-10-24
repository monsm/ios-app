#!/usr/bin/env node
// tools/argsyntax.js —— 调用参数语法闸门（第 37 轮新增，**判失败**）
//
// 由来：2026-10-24 第 31 轮给 XGradientDial 加 solid 参数时，用字符串替换
// 把 `gradient: XGradient.dialOK : XGradient.dial` 改成 `solid: ...`，
// 但替换后留下了 `gradient: solid: XPalette.warn` —— **11 个文件、13 处**。
//
// 后果：从 0510914 到 abe324c **连续 5 次 CI 失败**，每次都要 15 分钟，
// 而本地 31 道闸门全绿 —— 因为 swiftcheck 只查括号平衡，
// `gradient: solid: X` 的括号是平的，看不出参数语法错。
//
// 本闸门补的就是这个洞：扫"参数标签后紧跟另一个参数标签"的形态。
// 这类错误 100% 是替换事故，没有正当写法。

'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function swiftFiles(dir) {
  const out = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.swift')) out.push(p);
    }
  })(dir);
  return out;
}

// 形如 `label: label2:` / `label: value: ` / `= label:` 的参数错位
// 只匹配**函数调用/声明括号内**的形态 —— 语句级的 `case let x where ...: r +=`
// 是合法的 Swift，不是参数错位。第一版没做这个区分，报了 2 处误报。
const PATTERNS = [
  { re: /\([^()]*\b\w+:\s*\w+:\s/, why: '括号内参数标签后紧跟另一个标签（替换事故典型形态）' },
  { re: /,\s*\w+:\s*\w+:\s/, why: '逗号后双参数标签' },
];
// 语句级豁免：以这些关键字开头的行不查
const STMT = /^\s*(case|where|if|guard|switch|for|while|return|let|var|else)/;

const problems = [];
for (const f of swiftFiles(APP)) {
  const rel = f.replace(ROOT + path.sep, '');
  const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
  lines.forEach((raw, i) => {
    // 去注释与字符串字面量（避免 "http://x: y" 这类误报）
    const code = raw.replace(/\/\/.*$/, '').replace(/"[^"]*"/g, '""');
    if (STMT.test(code)) return;
    for (const { re, why } of PATTERNS) {
      if (re.test(code)) {
        problems.push(rel + ':' + (i + 1) + '  ' + why + '\n      ' + raw.trim().slice(0, 90));
        break;
      }
    }
  });
}

if (problems.length === 0) {
  console.log('调用参数语法 ✓ 无参数标签错位（' + swiftFiles(APP).length + ' 个文件）');
  process.exit(0);
}
console.log('✗ 调用参数语法可疑 ' + problems.length + ' 处：');
problems.slice(0, 20).forEach(p => console.log('  · ' + p));
process.exit(1);
