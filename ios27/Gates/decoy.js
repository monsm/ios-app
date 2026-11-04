#!/usr/bin/env node
// decoy.js - gate 36: every user-data reader must honour 空壳 (decoy) mode
//
// 2026-11-04: 胁迫码进空壳模式后，门能开但数据必须看不见。审计时逐个核过六个读入口
// （成员 / 单成员 / 锁清单 / 单锁 / 台账 / 日志 / 记录备注·标旗·处置），全部有 isDecoy 守卫。
// 这一层的风险不是「现在错了」，而是**下一个新增读取器忘了写**：漏一个就把真实数据
// 送到被胁迫者面前，而那种 bug 在正常使用中永远看不见。
//
// 判据：列出的每个函数体前 12 行内必须出现 isDecoy。名单是显式的 —— 新增读入口时
// 把它加进来，闸门就会替你记住这条纪律。
'use strict';
const fs = require('fs');
const path = require('path');
const APP = path.join(__dirname, '..', 'App');

const TARGETS = [
  ['Engine/Store.swift', 'static func members()'],
  ['Engine/Store.swift', 'static func member(_ id'],
  ['Engine/StoreKeychain.swift', 'static func keychains()'],
  ['Engine/StoreKeychain.swift', 'static func keychain(_'],
  ['Engine/StoreLedger.swift', 'static func ledger(_ mac'],
  ['Engine/StoreState.swift', 'static func readLogs(_ mac'],
  ['Engine/RecordSearch.swift', 'static func notes(_ mac'],
  ['Engine/RecordSearch.swift', 'static func flags(_ mac'],
  ['Engine/RecordSearch.swift', 'static func dispositions(_ mac'],
  // 写入口同理：空壳里写会污染真实数据（`addMember` 曾把新成员写进真实表）。
  ['Engine/Store.swift', 'static func addMember(_ name'],
  ['Engine/Store.swift', 'static func renameMember(_ id'],
  ['Engine/Store.swift', 'static func setMemberInfo(_ id'],
  ['Engine/StoreLedger.swift', 'static func saveLedger(_ mac'],
  ['Engine/MemberHub.swift', 'static func saveExt(_ id'],
  ['Engine/MemberHub.swift', 'static func claim(_ mac'],
  ['Engine/DiagKit.swift', 'static func loadIntoCache()'],
  ['Engine/RecordSearch.swift', 'static func setNote(_ mac'],
  ['Engine/RecordSearch.swift', 'static func setFlags(_ mac'],
  ['Engine/RecordSearch.swift', 'static func setDisposition(_ mac'],
  ['Engine/RecordSearch.swift', 'static func setNotes(_ mac'],
  ['Engine/RecordSearch.swift', 'static func setDispositions(_ mac'],
];

let bad = 0;
for (const [rel, sig] of TARGETS) {
  const f = path.join(APP, rel);
  if (!fs.existsSync(f)) { console.log('decoy: 找不到 ' + rel); bad++; continue; }
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  const i = lines.findIndex(l => l.includes(sig));
  if (i < 0) { console.log('decoy: ' + rel + ' 里找不到 ' + sig); bad++; continue; }
  const body = lines.slice(i, i + 12).join('\n');
  if (!/isDecoy/.test(body)) {
    console.log('decoy: ' + rel + ' 的 ' + sig + ' 前 12 行没有 isDecoy 守卫');
    bad++;
  }
}
if (bad === 0) {
  console.log('decoy: OK - ' + TARGETS.length + ' 个用户数据读/写入口都判空壳模式');
  process.exit(0);
}
console.log('decoy: FAIL - ' + bad + ' 个读入口缺少空壳守卫');
process.exit(1);