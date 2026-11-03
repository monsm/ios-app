#!/usr/bin/env node
// modifier.js - gate 31: a modifier chained onto an if/else block
//
// 2026-11-03: I rewrote a card so a VReadingGrid became an if/else of two grids,
// and left the old .padding(.top:) after the closing brace. Swift rejects that -
// 'reference to member padding cannot be resolved without a contextual type' -
// but swiftparse accepted it, so it cost a cloud build.
//
// Rule: a line that is only modifiers (starts with '.') immediately after a '}'
// that closes an if / else / for / switch block is an error. A modifier after a
// brace that closes a container view (VStack { ... }.padding()) is fine, so the
// brace's opener is checked.
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
let bad = 0;
const report = [];
for (const f of walk(ROOT)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (!t.startsWith('.')) continue;
    // 找上一行非空、非注释
    let j = i - 1;
    while (j >= 0 && (!lines[j].trim() || lines[j].trim().startsWith('//'))) j--;
    if (j < 0) continue;
    if (lines[j].trim() !== '}') continue;
    // 从 j 往上找匹配的 '{'
    let depth = 0, k = j;
    for (; k >= 0; k--) {
      for (let c = lines[k].length - 1; c >= 0; c--) {
        if (lines[k][c] === '}') depth++;
        else if (lines[k][c] === '{') {
          depth--;
          if (depth === 0) break;
        }
      }
      if (depth === 0) break;
    }
    if (k < 0) continue;
    const opener = lines[k].trim();
    if (/^(\}\s*)?(if|else|for|switch|guard|while)\b/.test(opener) || /\belse\b/.test(opener)) {
      bad++;
      report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + t.slice(0, 50) + '  ← 接在 if/else 块后（编译不过）');
    }
  }
}
if (bad === 0) {
  console.log('modifier: OK - no modifier chained onto a control-flow block');
  process.exit(0);
}
console.log('modifier: FAIL - ' + bad + ' dangling modifier(s):');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);