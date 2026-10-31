#!/usr/bin/env node
// reducedmotion.js —— 减弱动态覆盖闸门。
//
// 判什么：所有 .animation( 与 withAnimation( 必须带 reduceMotion 守卫。
//
// 例外（写理由）：
//   · 按压反馈（configuration.isPressed 驱动）—— 它是直接操作回执，
//     减弱动态要减的是内容滑动/视差/装饰缩放，不是手指按下没有回执。
//   · Design/Tokens.swift —— 令牌定义处。
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

const EXEMPT = { 'Design/Tokens.swift': '动效令牌定义处，不含调用' };
const findings = [];
let guarded = 0;

for (const f of walk(APP)) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  if (EXEMPT[rel]) continue;
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    if (!/\.animation\(/.test(line) && !/withAnimation\(/.test(line)) return;
    if (/configuration\.isPressed/.test(line)) return;
    // 环境值可能叫 reduceMotion / systemReduceMotion / axReduceMotion 等 —— 认"含 ReduceMotion 的标识符"
    if (/[A-Za-z_]\w*[Rr]educeMotion/.test(line) || /reduceMotion/.test(line)) { guarded++; return; }
    findings.push(rel + ':' + (i + 1) + ' 动效没尊重减弱动态: ' + t.slice(0, 80));
  });
}

console.log('reducedmotion: ' + guarded + ' 处已守卫');
if (findings.length === 0) {
  console.log('reducedmotion: OK — 所有装饰动效都尊重减弱动态');
  process.exit(0);
}
console.log('reducedmotion: FAIL — ' + findings.length + ' 处\n');
for (const x of findings) console.log('  ' + x);
process.exit(1);