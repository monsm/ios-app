#!/usr/bin/env node
// datefmtcheck —— 日期格式串**单一来源**闸门（判失败）。
//
// 2026-10-30 新增（第 111 轮）：`DateFormats.swift` 的 `DF` 已经给最高频的几档开了具名访问器
// （`DF.stamp` / `DF.day` / `DF.shortDayTime` / `DF.stampUTC` / `DF.minuteUTC`），
// 但全仓还有 17 处**绕过它们直接传裸格式串**：
//
//     let f = DF.cached("yyyy-MM-dd HH:mm:ss")     ← 与 DF.stamp 同一个格式，写了两份
//
// 风险：改 `DF.stamp` 的格式时，这 17 处**不会跟着变** —— 而它们产出的是
// 记录时间、凭证到期提示、导出文件名这些用户可见/可解析的东西。
// 这正是本仓反复清理的「同一语义两份实现静默漂移」。
//
// 判据：除 `DateFormats.swift` 本身外，`DF.cached("<已有访问器的格式>")` 一律判失败。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

// 格式 → 应改用的访问器
const HAS_ACCESSOR = new Map([
  ['yyyy-MM-dd HH:mm:ss', 'DF.stamp'],
  ['yyyy-MM-dd', 'DF.day'],
  ['MM-dd HH:mm', 'DF.shortDayTime'],
  ['yyyy-MM-dd HH:mm', 'DF.minuteUTC（带 UTC 时区时）'],
]);

const hits = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const rel = `${d}/${f}`;
    if (rel === 'App/Core/DateFormats.swift') continue;   // 格式串的**唯一来源**（`DF` 定义处），当然要含裸格式串
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
    L.forEach((l, i) => {
      const code = l.replace(/\/\/.*$/, '');
      const m = /DF\.cached\(\s*"([^"]+)"/.exec(code);
      if (!m) return;
      const acc = HAS_ACCESSOR.get(m[1]);
      if (acc) hits.push({ loc: `${rel}:${i + 1}`, fmt: m[1], acc });
    });
  }
}

if (hits.length) {
  console.log(`✗ 绕过具名访问器直接传裸格式串 ${hits.length} 处：`);
  for (const h of hits) console.log(`  ${h.loc}  "${h.fmt}"  → 应改用 ${h.acc}`);
  console.log('\n修法：换成 `DateFormats.swift` 里已有的访问器 —— 格式串只该有一个来源。');
  process.exit(1);
}
console.log('✓ 日期格式串单一来源（除 DateFormats.swift 外无裸格式串绕过访问器）');
