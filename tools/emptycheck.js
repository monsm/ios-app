#!/usr/bin/env node
// emptycheck —— 页面空态闸门（判失败）。
//
// 2026-10-30 新增（第 112 轮）：收尾「空态缺失」这个维度。
// 全仓 32 个页面级 View 会渲染集合，逐个核实：
//   · 29 个有显式空态判据（isEmpty / ContentUnavailableView / EmptyState / 文案 / if 判据）
//   · 3 个渲染的是**固定内容**（Picker 选项 / 三条写死的入口），空态不适用 —— 见 WHITELIST
//
// 判据：新增页面若渲染集合却既没有空态判据、也不在 WHITELIST 里 ⇒ 判失败。
//
// 为什么 WHITELIST 是写死的而不是自动判「内容是否固定」：
// 「这堆 ForEach 的元素来自常量数组还是用户数据」静态分不清 ——
// 前者不需要空态，后者必须有。硬白名单至少让每次新增都要**显式想一遍**。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

// 渲染固定内容、空态不适用的页面（每条写清理由）
const WHITELIST = new Map([
  ['DefendView', 'ForEach 是 15 分钟一档的时段选项（常量），不是用户数据'],
  ['TailgateView', 'ForEach 是 2~6 秒的等待时长选项（常量）'],
  ['StudioHome', 'List 是三条写死的凭证类型入口 + 一段说明'],
]);

const strip = (s) => s.replace(/\/\/[^\n]*/g, '');
const bad = [];
let checked = 0;

for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      const m = /^\s*(?:private\s+)?struct\s+(\w+)\s*:\s*View\b/.exec(L[i]);
      if (!m) continue;
      let dep = 0, s = false, end = i;
      for (let k = i; k < L.length; k++) {
        const code = strip(L[k]);
        for (const ch of code) { if (ch === '{') { dep++; s = true; } else if (ch === '}') dep--; }
        if (s && dep <= 0) { end = k; break; }
      }
      const body = strip(L.slice(i, end + 1).join('\n'));
      const isPage = /\.destined\s*\(/.test(body) || /\.navigationTitle\s*\(/.test(body);
      if (!isPage) continue;
      if (!/\bForEach\s*\(/.test(body) && !/\bList\s*(\(|\{)/.test(body)) continue;

      checked++;
      const name = m[1];
      if (WHITELIST.has(name)) continue;

      const hasEmpty = /isEmpty/.test(body)
        || /\.count\s*(==|<=)\s*0/.test(body)
        || /ContentUnavailableView|EmptyState/.test(body)
        || /还没有|暂无|没有.{0,6}记录/.test(body);
      if (!hasEmpty) bad.push({ name, loc: `${d}/${f}:${i + 1}` });
    }
  }
}

if (bad.length) {
  console.log(`✗ 渲染集合但没有空态判据 ${bad.length} 个页面：`);
  for (const b of bad) console.log(`  ${b.name}  ${b.loc}`);
  console.log('\n修法：补空态（`ContentUnavailableView` 或 `EmptyState` 组件，带一句下一步动作）；');
  console.log('若该页面渲染的是**固定内容**（常量选项 / 写死的入口），把它加进本工具的 WHITELIST 并写清理由。');
  process.exit(1);
}
console.log(`✓ ${checked} 个渲染集合的页面都有空态判据（${WHITELIST.size} 个固定内容页面已白名单）`);
