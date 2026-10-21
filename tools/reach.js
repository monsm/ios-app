#!/usr/bin/env node
// tools/reach.js —— 页面可达性分析
//
// 为什么需要它：
//   EventsPage 重写了 620 行，带查询引擎 / 筛选视图 / 事件备注 / 日志同步，
//   但**全仓零引用** —— 没有任何入口能打开它，用户看到的还是旧的 FeedPage。
//   五轮的功能全落在一个打不开的页面上。
//
//   tools/destmap.js 数的是「有多少条呈现通道」，不是「用户能不能走到」；
//   本工具从 RootView 做 BFS，回答后者。
//
// 做法：
//   1. 按花括号截出每个 struct/class/enum 的自身 body
//   2. 在 body 里找 `SomeType(` 形式的实例化（导航/呈现都长这样）
//   3. 从 RootView 起 BFS
//   4. 报出「零引用」与「从根走不到」的 View
//
// 局限：动态构造（字符串查表、反射）看不到；共享组件（如 XRow）会被算作可达节点。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
function allSwift() {
  const out = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (e.name[0] !== '.') walk(p); }
      else if (e.name.endsWith('.swift')) out.push(p);
    }
  };
  walk(path.join(ROOT, 'App'));
  return out;
}

const files = allSwift();
const bodies = new Map();   // typeName -> body text
const isView = new Set();

for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split('\n');
  for (let i = 0; i < lines.length; i++) {
    // ⚠ 边必须从**所有类型**收集，不能只看 View struct。
    //   AlarmCenterView / BackupView 是在 QuickPool 的 switch 里实例化的，
    //   Gate / MomentCardView 在 ViewModifier 里，两个 ShareCard 在
    //   ImageRenderer 的载体函数里 —— 父都不是 View，只看 View 会全部漏掉，
    //   把它们误判成孤立页。
    const mV = lines[i].match(/^\s*(?:public\s+|private\s+|final\s+|@\w+\s+)*struct\s+(\w+)\s*:\s*View\b/);
    const m = mV ||
      lines[i].match(/^\s*(?:public\s+|private\s+|final\s+|@\w+\s+)*(?:struct|class|enum|actor|extension)\s+(\w+)/);
    if (!m) continue;
    const name = m[1];
    if (mV) isView.add(name);
    // 花括号配平截取
    let depth = 0, started = false, buf = [];
    for (let k = i; k < lines.length; k++) {
      const code = lines[k].replace(/\/\/.*$/, '').replace(/"(?:[^"\\]|\\.)*"/g, '""');
      for (const ch of code) { if (ch === '{') { depth++; started = true; } else if (ch === '}') depth--; }
      buf.push(lines[k]);
      if (started && depth === 0) break;
    }
    // ⚠ 同名声明必须**拼接**而不是覆盖：一个类型可能有 `extension Foo { ... }`，
    //   覆盖会让 RootView 的 body 被某个空 extension 顶掉，于是可达集只剩 1 个。
    bodies.set(name, (bodies.get(name) || '') + '\n' + buf.join('\n'));
  }
}

// 所有已知类型名（用于识别实例化目标）
const known = new Set(isView);
for (const f of files) {
  const L2 = fs.readFileSync(f, 'utf8').split('\n');
  L2.forEach(t => {
    const mm = t.match(/^\s*(?:public\s+|private\s+|final\s+)*(struct|class|enum|actor)\s+(\w+)/);
    if (mm) known.add(mm[2]);
  });
}

// 边：body 里出现 `Name(` 即视为实例化
const edges = new Map();
for (const [name, body] of bodies) {
  const targets = new Set();
  for (const t of known) {
    if (t === name) continue;
    // ⚠ 只认 `Name(` 会漏掉尾随闭包写法 `Name { ... }` —— 而 SwiftUI 里
    //   BLEOffBanner { ... } / CodeScanSheet { ... } / Gate { ... } 全是这种形态。
    //   第一版因此把 8 个完全正常的视图当成了孤立页。
    // 用「名字提及」而不是「实例化」建边：
    //   AlarmCenterView 是通过 QuickPool 的 switch(字符串) 造出来的，
    //   命名空间 enum 永远不会被 new，静态分析追不到。
    //   而误判成孤立页比漏掉一个孤立页危险得多（上一轮我差点据此下错结论）。
    //   宁可高估可达，只保留确凿的孤立页。
    if (new RegExp('\\b' + t + '\\b').test(body)) targets.add(t);
  }
  edges.set(name, targets);
}

// BFS
const start = bodies.has('RootView') ? 'RootView' : null;
if (!start) { console.log('找不到 RootView'); process.exit(1); }
const seen = new Set([start]);
const queue = [start];
while (queue.length) {
  const cur = queue.shift();
  for (const nxt of (edges.get(cur) || [])) {
    if (seen.has(nxt)) continue;
    seen.add(nxt);
    queue.push(nxt);
  }
}

const reachableViews = [...isView].filter(v => seen.has(v)).sort();
const unreachableViews = [...isView].filter(v => !seen.has(v)).sort();

console.log('View struct 共 ' + isView.size + ' 个');
console.log('从 RootView 可达: ' + reachableViews.length + '   不可达: ' + unreachableViews.length);
console.log('-'.repeat(96));
if (unreachableViews.length) {
  console.log('⚠ 从根走不到的 View（可能是孤立页，也可能是被别的页面内联了）:');
  for (const v of unreachableViews) {
    const refs = [...bodies.entries()].filter(([, b]) => new RegExp('\\b' + v + '\\b').test(b)).map(([n]) => n);
    console.log('  ' + v.padEnd(30) + (refs.length ? '被 ' + refs.join(', ') + ' 实例化（但这些父也不可达）' : '零实例化'));
  }
} else {
  console.log('✓ 所有 View 都能从 RootView 走到');
}
