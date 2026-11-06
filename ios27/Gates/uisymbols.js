#!/usr/bin/env node
// uisymbols.js —— 闸门 25：**引用了本仓风格、但没有声明的视图/组件名**
//
// 为什么需要它（2026-11-03 真实事故）：
//   我写过 `CanvasBg()`，而本仓只有 `CanvasBackground()`。本地 24 道闸门全绿 ——
//   swiftparse 只看语法，types 只校验**类型**（不校验构造调用），callsig2 只校验
//   已登记类型的参数标签。于是这个错只有云端编译器能抓，白等一轮 CI。
//
// 判据：只盯「看起来像本仓组件」的名字（前缀白名单），且要求**全仓无同名声明**。
//   SDK 类型（VStack/Color/…）不在此列；它们由 types.js 的 SDK 白名单负责。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOTS = [path.join(__dirname, '..', 'App')];
const PREFIXES = ['V', 'Canvas', 'HH', 'Settings', 'Keys', 'Cred', 'Lock', 'Member', 'Record',
                  'Door', 'Glass', 'Key', 'Device', 'Battery', 'Safe', 'Tail', 'Auto',
                  'Appear', 'Access', 'About', 'God', 'Hardware', 'Protocol', 'Diag',
                  'Backup', 'Unlock', 'DFU', 'Gateway', 'Defend', 'Module', 'Quick',
                  'Package', 'Import', 'Studio'];
// 这些 SDK/框架名字恰好前缀相同，显式排除
// 2026-11-06（V10）：ViewThatFits 是 SwiftUI 自带的容器（iOS 16+），
// 前缀恰好撞上「V」—— 加进白名单，与 VStack/HStack 同理。
const ALLOW = new Set(['VStack', 'HStack', 'ZStack', 'VStackLayout', 'HStackLayout', 'VM', 'VC',
                       'ViewThatFits']);

function walk(d, out = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}

const files = ROOTS.flatMap(r => walk(r));
const declared = new Set();
const calls = [];

for (const f of files) {
  const raw = fs.readFileSync(f, 'utf8');
  // 去掉行注释，避免注释里提到某个名字造成误报（刚踩过）
  const src = raw.split('\n').map(l => l.replace(/\/\/.*$/, '')).join('\n');
  for (const m of src.matchAll(/\b(?:struct|class|enum|actor)\s+([A-Z]\w*)/g)) declared.add(m[1]);
  for (const m of src.matchAll(/\b(?:typealias|protocol)\s+([A-Z]\w*)/g)) declared.add(m[1]);
  for (const m of src.matchAll(/(?<![\.\w])([A-Z][A-Za-z0-9_]*)\(/g)) {
    calls.push({ name: m[1], file: f, line: src.slice(0, m.index).split('\n').length });
  }
}

const bad = calls.filter(c =>
  !declared.has(c.name) &&
  !ALLOW.has(c.name) &&
  PREFIXES.some(p => c.name.startsWith(p))
);

if (bad.length === 0) {
  console.log('uisymbols: OK — 没有引用未声明的本仓组件名');
  process.exit(0);
}
console.log('uisymbols: FAIL — 这些名字像本仓组件，但全仓没有声明（编译器才会抓的那类错）：');
const seen = new Set();
for (const b of bad) {
  const k = b.name + '@' + b.file + ':' + b.line;
  if (seen.has(k)) continue;
  seen.add(k);
  console.log('  ' + path.relative(path.join(__dirname, '..'), b.file) + ':' + b.line + '  ' + b.name + '(...)');
}
process.exit(1);
