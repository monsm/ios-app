#!/usr/bin/env node
// txguard.js - gate 37: every raw BLE frame send must sit behind the read-only guard
//
// 2026-11-04: 只读试验模式（kf_trial_guard）的强制点挂在 LockServiceLink / HardwareService /
// DFUKit 三个出口上，而 LockServiceCredentials.fpStart 直接调 ble.writeFrameHex(0x13)，
// 把「录指纹」整条绕过 —— 文案却承诺「写凭证全部被拦下」。
// 护栏是白名单（只放行 01/02/03/12/16/23/30/38），所以危险不来自名单遗漏，
// 而来自**新的直发口**。本闸门盯的就是这件事：每个 writeFrameHex 调用点，
// 其前 60 行内必须出现 assertReadOnly 或 trial_guard 判据。
'use strict';
const fs = require('fs');
const path = require('path');
const APP = path.join(__dirname, '..', 'App');

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
for (const f of walk(APP)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  lines.forEach(function (line, i) {
    if (!/writeFrameHex\(/.test(line)) return;
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    if (/func writeFrameHex/.test(line)) return;
    // 2026-11-04（注入验证抓到 · 第一次写错了）：注释里提到 assertReadOnly 也算命中 ⇒
    // 把守卫删掉后闸门仍然是绿的。必须**只看非注释行**，并且要求是调用而不是文字。
    const backLines = lines.slice(Math.max(0, i - 60), i + 1).filter(function (l) {
      const t2 = l.trim();
      return !t2.startsWith('//') && !t2.startsWith('///') && !t2.startsWith('*');
    });
    if (/assertReadOnly\s*\(|trial_guard/.test(backLines.join('\n'))) return;
    bad++;
    report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + t.slice(0, 70));
  });
}
if (bad === 0) {
  console.log('txguard: OK - 每个直发帧点都在只读护栏之下');
  process.exit(0);
}
console.log('txguard: FAIL - ' + bad + ' 个直发帧点没有只读护栏：');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);