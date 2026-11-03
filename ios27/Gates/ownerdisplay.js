#!/usr/bin/env node
// ownerdisplay.js —— 闸门 24：**归属字段不得直接显示原始值**
//
// 为什么需要这道闸门（2026-11-03，真机 bug 驱动）：
//   `owner` 这个字段在本仓历史上有两种口径 —— 成员 **id** 与成员 **名字**。
//   写侧现在统一成 id（AppModel.addPassword / enrollFingerprint），
//   而读侧必须过 `CredentialOrg.ownerName(_:)` 才能拿到人话的名字。
//
//   漏掉这一步的后果是真机上看到的：凭证详情页「归属」一栏显示一串 UUID；
//   新增指纹时 ownerName 恒 nil，录完的指纹直接落进「未归属」。
//   编译器不会报错（String? 直接进 Text 完全合法），所以只能靠这道闸门。
//
// 判据：Features/ 下不允许出现下面这些「把 owner 原样当显示值」的形状。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', 'App', 'Features');
// 注意 `entry.owner` **不在此列**：LedgerEntry.owner 存的就是**成员名**
// （RecordsModels.owner(_:members:) 只回名字），它没有 id 口径问题。
// 这里盯的是凭证域 —— KeyItem.owner / LedgerFp.owner / MobileKey 的 memberID 系。
const CRED = '(?:key|fp|k|item|row)\\.owner';
const BAD = [
  new RegExp(CRED + '\\s*\\?\\?\\s*"未归属"'),
  new RegExp('Text\\(\\s*' + CRED + '\\s*\\?\\?'),
  new RegExp('VFieldRow\\(label:\\s*"归属",\\s*value:\\s*' + CRED + '\\s*,'),
];
const ALLOW = [
  /CredentialOrg\.ownerName\(/,          // 正确形状
];

function walk(d, out = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}

const bad = [];
for (const f of walk(ROOT)) {
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split('\n');
  lines.forEach((line, i) => {
    if (line.trim().startsWith('//')) return;
    if (ALLOW.some(r => r.test(line))) return;
    if (BAD.some(r => r.test(line))) {
      bad.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + line.trim().slice(0, 100));
    }
  });
}

if (bad.length === 0) {
  console.log('ownerdisplay: OK — 没有把归属字段原样当显示值的地方');
  process.exit(0);
}
console.log('ownerdisplay: FAIL — 归属字段必须过 CredentialOrg.ownerName() 再显示：');
for (const b of bad) console.log('  ' + b);
process.exit(1);
