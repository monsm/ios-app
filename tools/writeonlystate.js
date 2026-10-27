#!/usr/bin/env node
// 只写不读状态闸门 —— 判失败。
//
// 2026-10-27 新增（B 线审核 §1.2）：13 轮功能精简留下一批「状态声明了、赋值了、但没人读」的孤儿。
// 它们比死代码更隐蔽：编译通过、闸门全绿，但对应的 UI 更新链路已断（订阅了拿不到变化）。
//
// 判据（读/写分离，这是 B 线审核给出的正确方法学）：
//   · `$name` 投影        → 算读
//   · `name.xxx` / `name)` → 算读
//   · `name =` / `name +=` → 算写
//   · 全仓统计，不只本文件（跨文件读取是常态）
//
// 已知的合法「只写不读」（人工审核过，写进 ALLOW）：
//   · 只用于 `.animation(value:)` 或 `.id()` 的刷新触发位 —— 那是合法用法
//   · @FocusState / @Environment 这类框架绑定
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

// 已知合法：只作为刷新触发器 / 框架绑定
const ALLOW = [
  { name: 'refreshTick', why: '只用作 List 的 .id() 刷新触发器' },
  { name: 'orderTick', why: '同上' },
  { name: 'tick', why: '定时刷新触发器' },
  { name: 'alarmTick', why: '角标刷新触发器' },
  { name: 'themeSeed', why: '外观重建触发器（.id 用）' },
  { name: 'appearanceSeed', why: '同上' },
  { name: 'prefSeed', why: '同上' },
  { name: 'launchBootstrapped', why: '幂等标志，只写一次后靠副作用生效' },
  { name: 'flashKey', why: '触发高亮动画' },
  { name: 'flashOnClose', why: '同上' },
  { name: 'isBusy', why: '框架绑定' },
];

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const files = walk(path.join(ROOT, 'App'));
const cache = new Map();
for (const f of files) cache.set(f, fs.readFileSync(f, 'utf8'));

// 收集所有 @State / @Published 声明
const decls = [];
for (const [f, txt] of cache) {
  txt.split(/\r?\n/).forEach((l, i) => {
    const t = l.trim();
    if (t.startsWith('//')) return;
    const m1 = /^@State(?:\([^)]*\))?\s+(?:private\s+)?var\s+(\w+)/.exec(t);
    const m2 = /^@Published(?:\([^)]*\))?\s+(?:private\(set\)\s+)?var\s+(\w+)/.exec(t);
    const m3 = /^@FocusState\s+(?:private\s+)?var\s+(\w+)/.exec(t);
    const nm = m1 ? m1[1] : (m2 ? m2[1] : (m3 ? m3[1] : null));
    if (!nm) return;
    if (m3) return;   // @FocusState 是框架绑定，跳过
    decls.push({ file: path.relative(ROOT, f).replace(/\\/g, '/'), line: i + 1, name: nm });
  });
}

// 对每个声明，统计全仓「读」与「写」
const problems = [];
for (const d of decls) {
  if (ALLOW.some(a => a.name === d.name)) continue;
  let reads = 0, writes = 0;
  const reWord = new RegExp('\\b' + d.name + '\\b');
  const reRead1 = new RegExp('\\$' + d.name + '\\b');                     // $name 投影
  const reRead2 = new RegExp('\\b' + d.name + '\\s*[.\\[)\\]},?!<>=]');     // name.xxx / name) 等
  const reRead3 = new RegExp('(?:value:|of:)\\s*' + d.name + '\\b');       // .animation(value: name)
  // 赋值必须**不是**比较运算：`=` 后面不能再跟 `=`，前面不能是 `!<>+-*/%`
  const reWrite = new RegExp('(?<![!<>+\\-*/%])' + '\\b' + d.name + '\\s*(?:=(?!=)|\\+=|-=)');

  for (const [, txt] of cache) {
    for (const line of txt.split(/\r?\n/)) {
      const t = line.trim();
      if (t.startsWith('//') || t.startsWith('///')) continue;
      if (!reWord.test(line)) continue;
      // 声明行本身不算
      if (/^\s*@(State|Published|FocusState|AppStorage)/.test(line)) continue;

      // 2026-10-27：判定顺序改成**读优先**。原实现先判写，于是
      // `if let m = pendingMac, ... pendingMac = nil` 这种「同一行既读又写」被算成纯写
      // ⇒ 该状态被判「只写不读」。实际它在这一行里先被读了。
      if (reRead1.test(line) || reRead3.test(line)) { reads++; continue; }
      if (reRead2.test(line)) { reads++; continue; }
      if (reWrite.test(line)) { writes++; continue; }
      reads++;   // 其他出现（实参、返回、条件）一律算读
    }
  }

  if (reads === 0) {
    problems.push({ ...d, writes });
  }
}

if (problems.length === 0) {
  console.log('只写不读状态闸门 ✓ 零命中');
  process.exit(0);
}

console.log(`✗ 只写不读的 @State/@Published ${problems.length} 个：\n`);
for (const p of problems) {
  console.log(`  ${p.file}:${p.line}  ${p.name}  （写了 ${p.writes} 次，读了 0 次）`);
}
console.log('\n修法：删掉该状态与所有赋值点；若它是刷新触发器，加进本文件的 ALLOW 并写明理由。');
process.exit(1);
