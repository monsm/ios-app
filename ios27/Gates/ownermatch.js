#!/usr/bin/env node
// ownermatch.js - gate 35: owner equality must go through CredentialOrg.ownerMatches
//
// 2026-11-04: the owner field carries two historical conventions - new writes store
// the member id, legacy rows store the member name. CredentialOrg.ownerMatches has
// accepted both since 2026-11-03, but six call sites in Features still spelled the
// comparison by hand, and each new one is a chance to forget the second convention
// (which is exactly how the attribution map shipped broken one round earlier).
//
// Rule: a line comparing an owner to BOTH `X.id` and `X.name` is re-implementing the
// helper. Use CredentialOrg.ownerMatches(owner, memberID:name:) instead.
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

let bad = 0;
const report = [];
for (const f of walk(FEATURES)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    // 同一行里既有 == <id> 又有 == <name>，且没有走 ownerMatches
    if (t.includes('ownerMatches')) return;
    const hasId = /\.owner\s*==\s*[A-Za-z_]\w*\.id\b/.test(t) || /==\s*[A-Za-z_]\w*\.id\b[^\n]*\.owner/.test(t);
    const hasName = /\.owner\s*==\s*[A-Za-z_]\w*\.name\b/.test(t);
    if (hasId && hasName) {
      bad++;
      report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + t.slice(0, 70));
    }
  });
}
if (bad === 0) {
  console.log('ownermatch: OK - owner 匹配统一走 CredentialOrg.ownerMatches');
  process.exit(0);
}
console.log('ownermatch: FAIL - ' + bad + ' 处手写了两套口径：');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);