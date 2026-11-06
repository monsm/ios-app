#!/usr/bin/env node
// allgates.js —— 本地可跑的静态闸门。CI 与本地是同一套。
'use strict';
const { execFileSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const gates = [
  ['swiftparse', '真 Swift 语法树'],
  ['tokensync', '令牌单一来源'],
  ['tokens', '页面层无样式字面量'],
  ['lineage', '与上一版设计切割'],
  ['destmap', 'Dest ↔ View 一一对应'],
  ['contrast', 'WCAG 对比度'],
];

let failed = 0;
for (const [name, what] of gates) {
  try {
    const out = execFileSync(process.execPath, [path.join(ROOT, 'Gates', name + '.js')], { encoding: 'utf8' });
    process.stdout.write(out);
  } catch (e) {
    failed++;
    if (e.stdout) process.stdout.write(e.stdout);
    if (e.stderr) process.stderr.write(e.stderr);
    console.error(`× ${name}（${what}）失败`);
  }
}

console.log('');
if (failed) {
  console.error(`allgates: ${failed} / ${gates.length} 道闸门失败`);
  process.exit(1);
}
console.log(`allgates: 全部 ${gates.length} 道闸门通过`);
