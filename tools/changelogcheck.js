#!/usr/bin/env node
// 43/44 更新说明的**反吹牛**闸门 —— 这一条是**判失败**的 (不是顾问级)。
//
// 起因: 2026-10-10 拍板"新变化/更新说明的内容不许手写"。手写意味着它会先于代码说谎 ——
// 而一份没人能对账的 release notes，正是"看起来在工作但其实是缺省值"那一类缺陷的文档版。
//
// 口径: ChangelogView 里每条 `ChangeEntry(id: N, …)` 的 N 必须在**覆盖表**认账的实现证据里出现
// (代码里有编号标注，或判定行自带 `已接线 @file:line`)。判据不在这里重写，直接问 featuremap ——
// 两处各写一遍"什么算实现了"，早晚会各自漂。
//
// 它证明什么: 这一行不会说出一个没做出来的功能。
// 它不证明什么: 界面长得对、真机上可用。那些仍然只有眼睛与真机能定论 (docs/VERIFY-CHECKLIST.md)。
'use strict';
const fs = require('fs');
const cp = require('child_process');

const SRC = 'App/UI/ChangelogView.swift';
if (!fs.existsSync(SRC)) {
  console.log('更新说明页不存在 (' + SRC + ') ⇒ 本闸门无事可做');
  process.exit(0);
}
const text = fs.readFileSync(SRC, 'utf8');
const ids = [...text.matchAll(/ChangeEntry\(\s*id:\s*(\d+)/g)].map((m) => +m[1]);
if (!ids.length) { console.log('✗ 更新说明一条都没有 —— 页面存在却空的，比没有这页更坏'); process.exit(1); }

const dup = ids.filter((n, i) => ids.indexOf(n) !== i);
let out = '';
try {
  out = cp.execSync('node tools/featuremap.js --verbose', { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
} catch (e) {
  console.log('✗ 覆盖表跑不起来，无法核对更新说明: ' + String(e.message).slice(0, 120));
  process.exit(1);
}
// C #N = 代码里有编号标注;  W 档行 = 判定行自带 file:line 证据
const credited = new Set([...out.matchAll(/^\s*C #(\d+)\b/gm)].map((m) => +m[1]));
for (const m of out.matchAll(/^ {4}#(\d+).*@/gm)) credited.add(+m[1]);

const missing = ids.filter((n) => !credited.has(n));
console.log(`更新说明 ${ids.length} 条 · 覆盖表认账 ${ids.filter((n) => credited.has(n)).length} 条 · 重号 ${dup.length} 条`);
if (missing.length) {
  console.log('✗ 下列条目在代码里**查不到实现证据** —— 要么先把它做出来，要么把这一行删掉:');
  for (const n of missing) {
    const line = (text.split(/\r?\n/).find((l) => l.includes('id: ' + n)) || '').trim().slice(0, 90);
    console.log(`   #${n}  ${line}`);
  }
}
if (dup.length) console.log(`✗ 同一条编号出现了两次 (SwiftUI 的 id 必须唯一): ${dup.join(',')}`);
process.exit(missing.length || dup.length ? 1 : 0);
