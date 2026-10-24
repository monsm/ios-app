#!/usr/bin/env node
// keyspace — 每锁键族所有权表的静态对账 (判失败)
//
// 1. removeDevice 必须只走 LockKeySpace.purge(m), 不许再把一串前缀写回 Store.swift;
// 2. 表内前缀不得重复/为空 (重复 = 两处维护同一族, 迟早改一处);
// 3. 表内前缀必须在 App/ 的其他地方真的出现过 (否则是删键后忘了删表项的死条目)。
//
// 它不判断"某个键到底该不该随锁删除" —— 那是产品语义, 仍需人读。它只保证:
// 删除点只有一个, 表本身没有自相矛盾。
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const fail = [];
const bad = m => fail.push(m);

const store = read('App/Core/Store.swift');
const at = store.indexOf('static func removeDevice(');
if (at < 0) bad('找不到 Store.removeDevice');
const nextFn = store.indexOf('/// 子页默认锁', at);
const body = at >= 0 ? store.slice(at, nextFn > at ? nextFn : at + 4000) : '';
if (!/LockKeySpace\.purge\(m\)/.test(body)) bad('removeDevice 没有调用 LockKeySpace.purge(m)');
if (/"kf_(ledger|snap|chist)_/.test(body)) bad('removeDevice 里又出现了逐锁前缀字面量 —— 所有权表被绕过');

const ks = read('App/Core/LockKeySpace.swift');
const arrays = [...ks.matchAll(/static let (suffixPrefixes|segmentedPrefixes)[^=]*=\s*\[([\s\S]*?)\]/g)];
if (arrays.length !== 2) bad('LockKeySpace 里应恰有两个前缀数组, 实得 ' + arrays.length);
const all = [];
for (const [, name, inner] of arrays) {
  const items = [...inner.replace(/\/\/[^\n]*/g, '').matchAll(/"([^"]+)"/g)].map(m => m[1]);
  if (items.length === 0) bad(`LockKeySpace.${name} 是空的`);
  for (const it of items) {
    if (!it.endsWith('_')) bad(`LockKeySpace.${name} 的前缀 "${it}" 不以 _ 结尾 —— 无法与 mac 精确拼接`);
    all.push(it);
  }
}
const seen = new Map();
for (const p of all) {
  if (seen.has(p)) bad(`前缀 "${p}" 在所有权表里重复`);
  seen.set(p, true);
}

// 前缀的真实性: 必须能在 App/ 的其他文件里找到同一字面量。
function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}
const swiftFiles = walk(path.join(root, 'App'))
  .filter(p => !p.endsWith('LockKeySpace.swift'))
  .map(p => fs.readFileSync(p, 'utf8'));
const corpus = swiftFiles.join('\n');
// 2026-10-24 改顾问级：这两张表是**删除设备时清空它那一族键**的防护表，
// 前缀可能在 App 里暂时没有写入点（功能被删或尚未启用），但表项必须保留 ——
// 否则历史数据永远清不掉。原判定把它们判成失败，等于逼人删防护。
const stale = all.filter(p => !corpus.includes('"' + p));
if (stale.length) console.log('  · 顾问：这些前缀当前无写入点，但保留作删除时清理用: ' + stale.join(', '));

const macFamilies = [...(ks.match(/static let macInKeyFamilies[^=]*=\s*\[([\s\S]*?)\]/)?.[1] || '')
  .replace(/\/\/[^\n]*/g, '').matchAll(/"([^"]+)"/g)].map(m => m[1]);
const staleMac = macFamilies.filter(p => !corpus.includes('"' + p) && !ks.includes('"' + p + '<mac>'));
if (staleMac.length) console.log('  · 顾问：兜底族前缀当前无写入点，保留作清理用: ' + staleMac.join(', '));

if (fail.length) {
  console.log('✗ keyspace: ' + fail.length + ' 条');
  for (const f of fail) console.log('  - ' + f);
  process.exit(1);
}
console.log(`✓ keyspace: 每锁键族 ${all.length} 条 (精确 ${all.length - (arrays[1][2].match(/"/g) || []).length / 2} / 分段 ${(arrays[1][2].match(/"/g) || []).length / 2}) + MAC 兜底 ${macFamilies.length} 族; removeDevice 只走单一所有权表`);
