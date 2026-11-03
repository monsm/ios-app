#!/usr/bin/env node
// attrattach.js —— 闸门 27：一个声明不能同时带 @MainActor 与 nonisolated
//
// 2026-11-03 真实事故：`@MainActor` 原本修饰 cascadeBinMember，我在属性与函数之间插了
// 一个新函数 ownerMatches，而它自己标了 `nonisolated` ⇒ 属性落到新函数上，
// 编译器报「has multiple actor-isolation attributes (@MainActor and 'nonisolated')」。
// 本地 26 道闸门全绿 —— 因为这在**语法上**完全合法，只有语义检查器能抓。
//
// 判据（精确、可静态判定）：收集每个声明**紧邻上方**的属性集合（跨注释与空行），
//   若同时含 `@MainActor` 与 `nonisolated`，判红。同类冲突对也一并覆盖。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'App');
function walk(d, out) {
  out = out || [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}
const DECL = /^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|static|class|mutating|nonisolated|override|convenience|required|lazy|weak|unowned|dynamic|indirect)\s+)*(func|var|let|struct|class|enum|actor|protocol|extension|init|subscript|typealias)\b/;
const CONFLICTS = [
  ['@MainActor', 'nonisolated'],
  ['@Sendable', 'nonisolated'],
];
let bad = 0;
const report = [];
for (const f of walk(ROOT)) {
  const src = fs.readFileSync(f, 'utf8');
  const lines2 = src.split('\n');
  for (let i = 0; i < lines2.length; i++) {
    const t = lines2[i].trim();
    if (!DECL.test(t)) continue;
    if (t.startsWith('//')) continue;
    // 收集本行及上方紧邻的属性（允许中间夹注释与空行）
    const attrs = t.match(/@\w+/g) || [];
    let j = i - 1;
    while (j >= 0) {
      const u = lines2[j].trim();
      if (!u || u.startsWith('//')) { j--; continue; }
      if (/^(@\w+(?:\([^)]*\))?\s*)+$/.test(u)) {
        const more = u.match(/@\w+/g) || [];
        for (const a of more) attrs.push(a);
        j--;
        continue;
      }
      break;
    }
    // 同一行里带的修饰符也算（例如 `nonisolated static func`）
    if (/\bnonisolated\b/.test(t)) attrs.push('nonisolated');
    for (const pair of CONFLICTS) {
      if (attrs.indexOf(pair[0]) >= 0 && attrs.indexOf(pair[1]) >= 0) {
        bad++;
        report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) +
                    '  ' + pair[0] + ' 与 ' + pair[1] + ' 同时出现在一个声明上');
      }
    }
  }
}
if (bad === 0) {
  console.log('attrattach: OK — 没有声明同时带互斥的隔离属性');
  process.exit(0);
}
console.log('attrattach: FAIL — ' + bad + ' 处互斥属性共存：');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);