#!/usr/bin/env node
// presenting.js - gate 28: every presenting: value must be a declared @State
//
// Scope is deliberately narrow. On 2026-11-03 a type mismatch between the
// @State and the value handed to presenting: cost a build, and I tried to
// catch that shape statically. The injection test proved the heuristic could
// not: a wrapper struct with two fields slipped straight through.
//
// So this gate only checks what is reliably checkable - that the name passed
// to presenting: corresponds to an @State declared in the same file. That
// catches typos and forgotten declarations, and produces no false positives.
// The type question stays with the compiler; it is the right owner.
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
  const src = fs.readFileSync(f, 'utf8');
  const declared = new Set();
  for (const m of src.matchAll(/@State\s+(?:private\s+)?var\s+([A-Za-z_]\w*)/g)) declared.add(m[1]);
  const lines = src.split('\n');
  lines.forEach(function (line, i) {
    const m = /presenting:\s*([A-Za-z_]\w*)/.exec(line);
    if (!m) return;
    if (!declared.has(m[1])) {
      bad++;
      report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) +
                  '  presenting: ' + m[1] + ' is not a declared @State in this file');
    }
  });
}
if (bad === 0) {
  console.log('presenting: OK - every presenting: value is a declared @State');
  process.exit(0);
}
console.log('presenting: FAIL - ' + bad + ' issue(s):');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);