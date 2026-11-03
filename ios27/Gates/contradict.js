#!/usr/bin/env node
// contradict.js - gate 32: one screen must not claim both 'not wired' and 'really sends'
//
// 2026-11-04: 新增凭证 step 2 said 本机这条链路还没接 (only records locally) while step 4
// said 这一步会真连锁录入指纹，连续 8 次 (cmd13/14 actually go to the lock). The
// implementation agreed with step 4. A user reading step 2 would not prepare to stand
// at the lock and press it eight times.
//
// Same class as the defend note ('the protocol cannot express an all-day window' while
// three engine functions define exactly that) - a sentence asserting a limitation the
// code does not have. Those are invisible to screenshot review (the user cannot know
// what the protocol supports) and invisible to reading one function at a time.
//
// Rule: within a single Swift file, if one user-facing string claims a capability is
// absent (未接 / 还没接 / 不支持 / 无法) AND another claims it really acts (真下发 /
// 真连锁 / 会真 / 真的写), flag it for human review. Deliberately narrow: it does not
// try to decide which sentence is right, only that both cannot be.
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
// 只在**字符串字面量**里找，且跳过注释行
const ABSENT = /(链路还没接|链路未接|还没接上|本机链路未接)/;
const ACTS = /(真下发|真连锁|会真|真的写|真链路)/;
let bad = 0;
const report = [];
for (const f of walk(ROOT)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  let absentAt = -1, actsAt = -1;
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (t.startsWith('//')) continue;
    // 抽字符串字面量
    const lits = t.match(/"([^"\\]|\\.)*"/g) || [];
    for (const lit of lits) {
      if (ABSENT.test(lit) && absentAt < 0) absentAt = i + 1;
      if (ACTS.test(lit) && actsAt < 0) actsAt = i + 1;
    }
  }
  if (absentAt > 0 && actsAt > 0) {
    bad++;
    report.push(path.relative(path.join(__dirname, '..'), f) +
                '  「未接」@' + absentAt + ' 与「真下发」@' + actsAt + ' 并存 —— 两者不可能都对');
  }
}
if (bad === 0) {
  console.log('contradict: OK - 没有同文件内自相矛盾的能力断言');
  process.exit(0);
}
console.log('contradict: FAIL - ' + bad + ' 处：');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);