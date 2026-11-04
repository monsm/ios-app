#!/usr/bin/env node
// storemember.js - gate 34: store.<name> must exist on SettingsStore
//
// 2026-11-04: four incidents where a field was renamed or deleted and one consumer was
// missed (rssiHistoryCap across types, pwdCount wording, a duplicated warning, and most
// recently store.calibrationAt assigned after the property was removed). swiftparse sees
// legal syntax; types.js checks type names, not members. The cloud build catches it, but
// only after a full round trip.
//
// Scope discipline (first version flagged 85 false positives): only files under
// App/Features that actually reference SettingsStore, because Engine files use a bare
// `store` for the DB wrapper - a different type.
'use strict';
const fs = require('fs');
const path = require('path');
const FEATURES = path.join(__dirname, '..', 'App', 'Features');

function walk(d, out) {
  out = out || [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}

const modelPath = path.join(FEATURES, 'Settings', 'SettingsModel.swift');
const model = fs.readFileSync(modelPath, 'utf8');
const members = new Set();
for (const m of model.matchAll(/^\s{0,8}(?:private\(set\) )?(?:static )?(?:var|let)\s+([A-Za-z_]\w*)/gm)) members.add(m[1]);
for (const m of model.matchAll(/^\s{4}(?:private )?(?:static )?func\s+([A-Za-z_]\w*)/gm)) members.add(m[1]);

let bad = 0;
const report = [];
for (const f of walk(FEATURES)) {
  if (f === modelPath) continue;
  const text = fs.readFileSync(f, 'utf8');
  if (!text.includes('SettingsStore')) continue;
  const lines = text.split('\n');
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    let m;
    const re = /(^|[^\w.])store\.([A-Za-z_]\w*)/g;
    while ((m = re.exec(line)) !== null) {
      const name = m[2];
      if (members.has(name)) continue;
      bad++;
      report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  store.' + name);
    }
  });
}
if (bad === 0) {
  console.log('storemember: OK - store.<name> 都是 SettingsStore 的成员');
  process.exit(0);
}
console.log('storemember: FAIL - ' + bad + ' 处引用了不存在的成员：');
report.slice(0, 25).forEach(function (r) { console.log('  ' + r); });
process.exit(1);