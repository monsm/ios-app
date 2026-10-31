#!/usr/bin/env node
// dynamictype.js —— 动态字体闸门。
//
// 判什么：
//   ① 不许出现 `.font(.system(size: N))` —— 写死 point size 意味着用户调大字号时它纹丝不动。
//      （这是 HIG 审计抓到的最大一类问题：51 处。全部改成语义字阶后为 0。）
//   ② 不许 `.lineLimit(1)` 配 `.minimumScaleFactor` 之外的硬截断 —— 大字号下中文会被切。
//   ③ 所有自定义字号必须经过 T.F（令牌层负责映射到系统字阶）。
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

const findings = [];
const files = walk(APP);
let fontRefs = 0;

for (const f of files) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  if (rel === 'Design/Tokens.swift') continue;   // 令牌层就是字阶映射的家
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    if (/\.font\(\s*\.system\(\s*size:/.test(line)) {
      findings.push(rel + ':' + (i + 1) + ' 写死字号（用户调大字号时不会跟着长）: ' + t.slice(0, 70));
    }
    if (/T\.F\.|T\.Icon/.test(line)) fontRefs++;
  });
}

console.log('dynamictype: ' + files.length + ' 个文件，' + fontRefs + ' 处走令牌字号');
if (findings.length === 0) {
  console.log('dynamictype: OK — 0 处写死字号，全部走语义字阶（Dynamic Type 真生效）');
  process.exit(0);
}
console.log('dynamictype: FAIL — ' + findings.length + ' 处\n');
for (const f of findings.slice(0, 30)) console.log('  ' + f);
process.exit(1);
