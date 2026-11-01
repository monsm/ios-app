#!/usr/bin/env node
// memberfill.js —— 逐字段重建时漏传「带默认值的字段」（2026-11-01）。
//
// 为什么需要：ROUND-93 给 KeyItem 加了 `var createdAt: Double = 0`，
// 而三处「逐字段重建 KeyItem」的地方没跟着加 —— 编译不报错（有默认值），
// 但语义静默丢失（停用/改到期日会把「已使用 N 天」清零）。
// CI 全绿、21 道闸门全绿，没有任何自动化能发现它。
//
// 判据：对已知类型，若某字段带默认值，则每一处 `TypeName(` 构造点都必须显式传该标签。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

const WATCHED = {
  KeyItem: ['createdAt'],
};

// 允许不传的构造点（file:line 前缀），每条都要有理由
const EXEMPT = [
  // 手机钥匙没有「创建时刻」这个概念 —— 保持默认 0 是对的。
  'App/Shell/AppModel.swift:189',
];

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const findings = [];
let checked = 0;

for (const f of walk(APP)) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (t.startsWith('//')) continue;
    for (const [typeName, fields] of Object.entries(WATCHED)) {
      if (!new RegExp('\\b' + typeName + '\\b\\s*\\(').test(lines[i])) continue;
      let depth = 0, buf = '', started = false;
      for (let j = i; j < Math.min(i + 20, lines.length); j++) {
        const seg = j === i ? lines[j].slice(lines[j].indexOf(typeName)) : lines[j];
        for (const ch of seg) {
          if (ch === '(') { depth++; started = true; }
          else if (ch === ')') { depth--; }
          if (started) buf += ch;
          if (started && depth === 0) break;
        }
        if (started && depth === 0) break;
      }
      const exempt = EXEMPT.some((e) => (rel + ':' + (i + 1)).startsWith(e));
      if (exempt) continue;
      checked++;
      for (const field of fields) {
        if (!new RegExp('\\b' + field + ':').test(buf)) {
          findings.push(rel + ':' + (i + 1) + '  构造 ' + typeName + ' 时没传 `' + field + '`（有默认值，编译不报错但语义丢失）');
        }
      }
    }
  }
}

console.log('memberfill: 检查 ' + checked + ' 处构造点');
if (findings.length === 0) {
  console.log('memberfill: OK — 带默认值的字段在重建时都显式传了');
  process.exit(0);
}
console.log('memberfill: FAIL — ' + findings.length + ' 处');
for (const x of findings) console.log('  ' + x);
process.exit(1);