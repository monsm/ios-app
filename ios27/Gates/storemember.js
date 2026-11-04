#!/usr/bin/env node
// storemember.js - gate 34: store.<name> must exist on SettingsStore,
//                              DB.store.<name> must exist on Store
//
// 2026-11-04: five incidents where a field was renamed, deleted, or invented and one
// consumer was missed (rssiHistoryCap across types, pwdCount wording, a duplicated
// warning, store.calibrationAt assigned after the property was removed, and
// DB.store.setBool which has never existed). swiftparse sees legal syntax; types.js
// checks type names, not members. The cloud build catches these, a round trip later.
//
// Two member tables, two patterns:
//   · bare `store.<name>` in files that mention SettingsStore  -> SettingsStore members
//   · `DB.store.<name>` anywhere                               -> Store members
// Scope discipline: the first version flagged 85 false positives because Engine files
// use a bare `store` for the DB wrapper - a different type.
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

function membersOf(file, re) {
  const src = fs.readFileSync(file, 'utf8');
  const set = new Set();
  for (const m of src.matchAll(re)) set.add(m[1]);
  return set;
}

const settingsModel = path.join(APP, 'Features', 'Settings', 'SettingsModel.swift');
const settingsMembers = membersOf(settingsModel,
  /^\s{0,8}(?:private\(set\) )?(?:static )?(?:var|let)\s+([A-Za-z_]\w*)/gm);
for (const m of fs.readFileSync(settingsModel, 'utf8').matchAll(/^\s{4}(?:private )?(?:static )?func\s+([A-Za-z_]\w*)/gm)) settingsMembers.add(m[1]);

const storeFile = path.join(APP, 'Engine', 'Store.swift');
const storeMembers = membersOf(storeFile,
  /^\s{4}(?:@\w+ )?(?:static )?(?:func|var|let)\s+([A-Za-z_]\w*)/gm);

let bad = 0;
const report = [];
function flag(f, line, what) {
  bad++;
  report.push(path.relative(path.join(__dirname, '..'), f) + ':' + line + '  ' + what);
}

for (const f of walk(APP)) {
  const text = fs.readFileSync(f, 'utf8');
  const lines = text.split('\n');
  const mentionsSettings = text.includes('SettingsStore');
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    let m;
    // DB.store.<name>
    const reDB = /DB\.store\.([A-Za-z_]\w*)/g;
    while ((m = reDB.exec(line)) !== null) {
      if (!storeMembers.has(m[1])) flag(f, i + 1, 'DB.store.' + m[1]);
    }
    // bare store.<name>（只在前者未匹配的位置，且文件提到 SettingsStore）
    if (!mentionsSettings) return;
    if (f === settingsModel) return;
    const re = /(^|[^\w.])store\.([A-Za-z_]\w*)/g;
    while ((m = re.exec(line)) !== null) {
      if (settingsMembers.has(m[2])) continue;
      flag(f, i + 1, 'store.' + m[2]);
    }
  });
}
if (bad === 0) {
  console.log('storemember: OK - store./DB.store. 的成员都存在');
  process.exit(0);
}
console.log('storemember: FAIL - ' + bad + ' 处引用了不存在的成员：');
report.slice(0, 25).forEach(function (r) { console.log('  ' + r); });
process.exit(1);