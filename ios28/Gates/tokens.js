#!/usr/bin/env node
// tokens.js —— 页面层不许出现样式字面量。
//
// 判据（只扫页面层：App/Features、App/Core、App/ThresholdApp.swift）：
//   · 颜色字面量：#RRGGBB / Color(red: / Color(.sRGB
//   · 文字字号字面量：.font(.system(size:…, … design: …))  ← 图标字号不带 design，不算文字
//   · 间距字面量：.padding(<数字>) / .frame(width: <数字>）不做静态判定（组件几何本来就是数），
//     但颜色与字号是"设计系统是否真的在被使用"的硬指标，必须判。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SCOPES = ['App/Features', 'App/Core', 'App/ThresholdApp.swift'];

function walk(target, out = []) {
  const p = path.join(ROOT, target);
  if (!fs.existsSync(p)) return out;
  const stat = fs.statSync(p);
  if (stat.isFile()) {
    if (p.endsWith('.swift')) out.push(p);
    return out;
  }
  for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    const q = path.join(p, e.name);
    if (e.isDirectory()) walk(path.relative(ROOT, q), out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}

const files = SCOPES.flatMap((s) => walk(s));
const findings = [];

const RULES = [
  [/Color\(\s*red\s*:/, '颜色字面量 Color(red:…)'],
  [/Color\(\s*\.sRGB/, '颜色字面量 Color(.sRGB…)'],
  [/"#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?"/, '十六进制颜色字面量'],
  [/\.font\(\.system\(size:[^)]*design:/, '文字字号字面量（应走 .type(T.F.…)）'],
  [/\.foregroundStyle\(\.(red|blue|green|orange|yellow|purple|pink|teal|indigo|mint|cyan|brown)\)/, '系统色名（应走 T.C.*）'],
];

for (const file of files) {
  const rel = path.relative(ROOT, file).split(path.sep).join('/');
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    if (line.trim().startsWith('//')) return;
    for (const [re, why] of RULES) {
      if (re.test(line)) findings.push(`${rel}:${i + 1}  ${why}\n      ${line.trim()}`);
    }
  });
}

if (findings.length) {
  console.error('tokens: FAIL — 页面层出现样式字面量：');
  for (const f of findings) console.error('  ' + f);
  process.exit(1);
}
console.log(`tokens: OK — ${files.length} 个页面文件，0 处颜色/字号字面量`);
