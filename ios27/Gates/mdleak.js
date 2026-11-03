#!/usr/bin/env node
// mdleak.js - gate 33: ** in a Text("...") literal renders as asterisks
//
// 2026-11-04: found three places writing emphasis into Text("..."). SwiftUI parses
// Markdown only when the argument is a LocalizedStringKey; a plain String literal
// reaches the view as characters. So the user sees **合并进** rather than bold text.
// The same trap hit SettingsNote earlier in this pass, and Text(cond ? a : b) - a
// ternary yields String too.
//
// Rule: a Text(...) call whose argument starts with a double-quoted literal may not
// contain **. Text(LocalizedStringKey(...)) and Text(.init(...)) are the fixed forms
// and are not matched, because the pattern requires the quote immediately after '('.
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
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//')) return;
    // Text(" 开头的字面量（不含 LocalizedStringKey / .init 包装）
    if (!/Text\(\s*"/.test(t)) return;
    // 本行内 Text( 之后的双引号内容里出现 **
    const after = t.slice(t.indexOf('Text('));
    const lits = after.match(/"([^"\\]|\\.)*"/g) || [];
    for (const lit of lits) {
      if (lit.indexOf('**') >= 0) {
        bad++;
        report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + lit.slice(0, 60));
        break;
      }
    }
  });
}
if (bad === 0) {
  console.log('mdleak: OK - 没有把 Markdown 强调写进 Text 的字面量');
  process.exit(0);
}
console.log('mdleak: FAIL - ' + bad + ' 处星号会原样显示：');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);