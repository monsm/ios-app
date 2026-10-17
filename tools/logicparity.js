#!/usr/bin/env node
// tools/logicparity.js — **逻辑面**差分闸门 (第一百八十批新增, 判失败)
//
// 已有闸门的分工:
//   golden.js       —— 数据面: 同一输入两边算出同一帧 (字节)
//   cmdsshadow.js   —— 数据面: Swift 帧构造逐字节复刻
//   parseshadow.js  —— 数据面: 回包解析
// 它们都不管"**什么时候发、等多久、失败怎么办**"。这一支补这一段:
//   L* 时序/流程不变量, D* 已裁定的有意分歧, forbid 反向围栏 (防退回旧实现)。
//
// 它不是编译器: 规则是正则, 断言的是"这段逻辑还在、数字没被改小"。
// 所以它抓的是**回归**(把 8s 改回 3s、把无条件刷令牌改成 TTL 跳过、把单 waiter 改成覆盖),
// 不是"证明语义正确" —— 语义由 golden/cmdsshadow/单测兜。规则表 fixtures/logic-parity.json 里
// 每条都带 APK 证据的 file:re, 反编译产物若改动而证据对不上, 同样判失败 (引用不许腐烂)。
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');          // ios-app/ = 本仓库根
const REPO = path.resolve(ROOT, '..');               // 仓库根的上一级 (历史路径 /d/aapk/... 仍可用)
const SPEC = path.join(ROOT, 'fixtures/logic-parity.json');
const VERBOSE = process.argv.includes('-v') || process.argv.includes('--verbose');
const MD = process.argv.includes('--md');   // 生成文档用的表格 (给 PARITY-FULL-AUDIT §9 抄, 不落盘)

const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
const cache = new Map();
// 解析顺序: 仓库根 → 上一级 (兼容旧表里 `ios-app/...` 的写法)。
// 为什么要落到仓库根: 云端 checkout 只有 ios-app 这一层, 上一级里没有 jzzns22561_v2/ 与
// miniprogram-app/ —— 第一百八十批首跑就是这样红的 (20 条全报"文件不存在")。
// 结论不是让闸门在云端静默跳过, 而是把证据搬进仓库: APK 反编译的 BleLockConnector.java
// 落在 vendor/apk/, 小程序侧 JS 与 vendor/app/ 同源同步 (见 540f4a3)。
function load(rel) {
  if (cache.has(rel)) return cache.get(rel);
  const cands = [path.join(ROOT, rel), path.join(REPO, rel)];
  let txt = null;
  for (const abs of cands) {
    try { txt = fs.readFileSync(abs, 'utf8'); break; } catch (e) { txt = null; }
  }
  cache.set(rel, txt);
  return txt;
}
// 行号: 命中的第一处, 报给用户点进去看
function lineOf(txt, re) {
  const m = re.exec(txt);
  if (!m) return 0;
  return txt.slice(0, m.index).split('\n').length;
}
function checkEntry(e) {
  const txt = load(e.file);
  if (txt === null) return { ok: false, why: '文件不存在: ' + e.file };
  const re = new RegExp(e.re);
  const line = lineOf(txt, re);
  if (!line) return { ok: false, why: e.file + ' 未命中 /' + e.re + '/' + (e.note ? ' (' + e.note + ')' : '') };
  return { ok: true, where: e.file + ':' + line };
}

let pass = 0, fail = 0, div = 0;
const rows = [];
const failures = [];

for (const r of spec.rules) {
  const bad = [];
  const hits = [];
  for (const side of ['apk', 'impl']) {
    for (const e of r[side] || []) {
      const res = checkEntry(e);
      if (!res.ok) bad.push(side + ': ' + res.why);
      else hits.push(res.where);
    }
  }
  const kind = r.kind || 'parity';
  if (bad.length) {
    fail++;
    failures.push({ id: r.id, title: r.title, bad });
  } else if (kind === 'divergence') {
    div++;
    rows.push({ state: 'DIV', id: r.id, title: r.title, hits });
  } else {
    pass++;
    rows.push({ state: ' OK', id: r.id, title: r.title, hits });
  }
}

// 反向围栏: 出现即失败 (旧实现/退化写法)
for (const f of spec.forbid || []) {
  const txt = load(f.file);
  if (txt === null) { fail++; failures.push({ id: 'FORBID', title: f.re, bad: ['文件不存在: ' + f.file] }); continue; }
  const re = new RegExp(f.re);
  if (re.test(txt)) {
    fail++;
    const line = lineOf(txt, re);
    failures.push({ id: 'FORBID', title: f.why, bad: [f.file + ':' + line + ' 命中 /' + f.re + '/'] });
  } else {
    pass++;
  }
}

if (MD) {
  console.log('| 规则 | 面 | 内容 | 本机证据 |');
  console.log('|---|---|---|---|');
  for (const r of spec.rules) {
    const first = (r.impl && r.impl[0]) ? checkEntry(r.impl[0]) : { where: '-' };
    console.log('| `' + r.id + '` | ' + (r.kind === 'divergence' ? '有意分歧' : '一致') + ' | ' + r.title + ' | ' + (first.where || '—') + ' |');
  }
  process.exit(fail ? 1 : 0);
}

if (VERBOSE) {
  for (const row of rows) {
    console.log(row.state + '  ' + row.id.padEnd(28) + row.title);
    for (const h of row.hits) console.log('       · ' + h);
  }
  console.log('');
}

if (failures.length) {
  console.error('逻辑面差分: ' + fail + ' 条不成立');
  for (const f of failures) {
    console.error('  ✗ ' + f.id.padEnd(28) + f.title);
    for (const b of f.bad) console.error('      - ' + b);
  }
  console.error('\n结论: 逻辑面与 APK 证据不一致 — 这不是排版问题, 是"该等多久/该不该重发/该不该刷令牌"变了。');
  process.exit(1);
}

console.log('逻辑面差分 OK: ' + pass + ' 条逐条对上 APK 证据' +
  (div ? ', ' + div + ' 条已裁定分歧 (D*, 两侧各自对得上, 见 --verbose)' : '') +
  ', 反向围栏 ' + ((spec.forbid || []).length) + ' 条未触发');
console.log('注: 本闸门是正则级回归护栏, 不替代编译/XCTest; 语义面由 golden.js + cmdsshadow.js + 小程序单测兜底。');
