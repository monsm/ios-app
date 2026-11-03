#!/usr/bin/env node
// jargon.js - gate 30: protocol vocabulary must not appear in user-facing copy
//
// 2026-11-03: seven section headers carried the BLE command that fetched them
// (运行状态 · cmd03, 当前布防 · cmd25, 时间对照 · cmd03 / cmd0E ...), and ZOTP
// appeared on seven screens including the dynamic-code page title.
//
// Scope: string literals in App/Features, excluding the pages that exist to show
// protocol facts - God mode, the protocol test page and the diagnostic stream.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'App', 'Features');
const ALLOW_FILES = ['GodModeScreen.swift', 'ProtocolTestScreen.swift', 'DiagStreamScreen.swift'];
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
  if (ALLOW_FILES.indexOf(path.basename(f)) >= 0) continue;
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//')) return;
    // 只看双引号字符串里的内容
    const lit = /"([^"\\]|\\.)*"/g;
    let m;
    while ((m = lit.exec(t))) {
      const body = m[0];
      // 2026-11-04：中文写法「命令 19」与英文 cmd19 是同一件事，之前漏判。
      // 2026-11-04：rc= 是协议返回码，同样不该出现在用户文案里。
      // 2026-11-04：`TODO(engine)` 这类开发标记同样不该出现在用户文案里。
      if (/cmd[0-9A-Fa-f]{2}/.test(body) || /\bZOTP\b/.test(body) || /命令\s*[0-9]+/.test(body) || /rc\s*=\s*[0-9]/.test(body) || /TODO\(/i.test(body) || /FIXME/i.test(body)) {
        bad++;
        report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + body.slice(0, 60));
        break;
      }
    }
  });
}
if (bad === 0) {
  console.log('jargon: OK - no protocol vocabulary in user-facing copy');
  process.exit(0);
}
console.log('jargon: FAIL - ' + bad + ' user-facing string(s) carry protocol terms:');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);