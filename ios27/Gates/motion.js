#!/usr/bin/env node
// motion.js —— 动效纪律闸门。
//
// 判什么（DESIGN-CONTRACT §7）：
//   ① 所有 .animation 必须带 value:（无 value 的隐式动画会互相抢属性）
//   ② 无限循环动画必须独立成视图 + .transaction 切断继承
//   ③ 不许用 .linear 做 UI 动效（没有缓动 = 机械感）
//   ④ 不许在 .animation 里写裸时长（必须走 T.M.*）
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

const files = walk(APP);
const findings = [];
let animCount = 0;

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  if (rel === 'Design/Tokens.swift') continue;
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;

    // ① .animation( 必须带 value:
    if (/\.animation\s*\(/.test(line)) {
      animCount++;
      // 跨行写法：本行没有 value: 且以逗号或括号结尾 → 查下一行
      const hasValue = /value\s*:/.test(line);
      const next = (lines[i + 1] || '');
      const valueNext = /^\s*value\s*:/.test(next);
      if (!hasValue && !valueNext) {
        findings.push({ file: rel, line: i + 1, why: '.animation 缺 value:（会与其他隐式动画抢属性）' });
      }
    }

    // ③ .linear 用于 UI 动效
    if (/\.animation\(\s*\.linear/.test(line) || /\.linear\(duration:/.test(line)) {
      findings.push({ file: rel, line: i + 1, why: '.linear 无缓动（UI 动效不许用）' });
    }

    // ④ 裸时长
    if (/\.animation\(\s*\.(easeIn|easeOut|easeInOut|spring|timingCurve)\([^)]*duration:\s*[0-9]/.test(line)) {
      findings.push({ file: rel, line: i + 1, why: '.animation 里写裸时长（应走 T.M.*）' });
    }

    // ② 无限循环
    if (/\.repeatForever\s*\(/.test(line)) {
      findings.push({ file: rel, line: i + 1, why: 'repeatForever 必须独立成视图并用 .transaction { $0.animation = nil } 切断继承' });
    }
  });
}

console.log(`motion: 扫 ${files.length} 个文件，.animation 调用 ${animCount} 处`);
if (findings.length === 0) {
  console.log('motion: OK — 全部带动画带 value，无裸时长，无裸 repeatForever');
  process.exit(0);
}
console.log(`motion: FAIL — ${findings.length} 处\n`);
for (const f of findings) console.log(`  ${f.file}:${f.line}  ${f.why}`);
process.exit(1);
