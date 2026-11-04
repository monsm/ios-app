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
    // 2026-11-04（覆盖扩展 · 我自己踩到）：闸门原来只认 `Text("` 字面量，而我这次把
    // `**不进备份包**` 写进了 `SettingsNote(text: "...")` —— 那同样是**普通 String**，
    // 同样会把星号原样渲出来，闸门却放过了。现在把「接受 String 的文案组件」一并纳入：
    // SettingsNote / KeysInlineNote / VSectionLabel / VFieldRow / VValueRow 的 text:/title:/value: 参数。
    const STRING_COMPONENTS = /(?:SettingsNote\(text:|KeysInlineNote\([^)]*text:|VSectionLabel\(text:|VFieldRow\([^)]*value:|VValueRow\([^)]*value:)\s*"/;
    if (!/Text\(\s*"/.test(t) && !STRING_COMPONENTS.test(t)) return;
    // 本行内 Text( 之后的双引号内容里出现 **；
    // 非 Text 的文案组件（SettingsNote 等）没有 Text( 锚点，就整行扫。
    // 2026-11-04（注入验证抓到）：原来无条件 `slice(indexOf('Text('))`，而 SettingsNote 行
    // `indexOf` 返回 -1 ⇒ `slice(-1)` 只剩最后一个字符 ⇒ **永远抓不到**。
    const anchor = t.indexOf('Text(');
    const after = anchor >= 0 ? t.slice(anchor) : t;
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