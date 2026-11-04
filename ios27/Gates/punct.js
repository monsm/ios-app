#!/usr/bin/env node
// punct.js - gate 38: no space after Chinese punctuation inside string literals
//
// 2026-11-04: 全仓 73 处用户可见文案写成「， 」「： 」——中文排版不这么排，读起来像译文。
// 一次性清了，这道闸门保证它不会回来。只查双引号内的片段，注释与代码不查。
'use strict';
const fs = require('fs');
const path = require('path');
const APP = path.join(__dirname, '..', 'App');

function walk(d, out) {
  out = out || [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}

const PUNCT = /[\u4e00-\u9fa5][，。；：、]\s+/;
let bad = 0;
const report = [];
for (const f of walk(APP)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    const parts = line.split('"');
    for (let k = 1; k < parts.length; k += 2) {
      if (PUNCT.test(parts[k])) {
        bad++;
        report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + parts[k].slice(0, 50));
        return;
      }
    }
  });
}
if (bad === 0) {
  console.log('punct: OK - 字符串里没有中文标点后的多余空格');
  process.exit(0);
}
console.log('punct: FAIL - ' + bad + ' 处中文标点后带空格：');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);