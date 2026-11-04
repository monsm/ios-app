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
    // 2026-11-05（对抗审查）：原判据只抓「同一行既有 .id 又有 .name」。
    // 真正的漏洞长这样：for p in DB.listPwds(mac) where p.owner == from
    // —— from 是裸成员 id 参数，没有 .id/.name 后缀，于是从未被这条闸门看见。
    // 后果：旧数据（owner 存成员名）既不移交也不计数，而界面承诺「全部」。
    // (?![.\w]) ：member.name 这种「已经是显示名」的写法不算 —— 后面跟着点就是取属性，
    // 不是裸标识符。只抓真的直接拿一个 id 参数来比的写法。
    const bare = /\.owner\s*==\s*([A-Za-z_][A-Za-z0-9_]*)(?![.\w])/.exec(t);
    if (bare && ["nil", "owner", "ownerID", "ownerId"].indexOf(bare[1]) < 0) {
      bad++;
      report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + t.slice(0, 70));
      return;
    }
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