#!/usr/bin/env node
// 闸门：注释里引用的 `文件名:行号` 是否越界。
//
// 2026-10-30 新增（第 100 轮）：本仓经历过多次文件拆分（LockKeeperApp 1138→616 行、
// LockService 1081→122 行 …），而注释里的 `Xxx.swift:123` 引用**不会自动跟着改**。
// 第 99 轮就发现 `Store.swift:124` 引用「AuditChain:242」，而那个文件只有 53 行。
//
// 纪律（本仓第二批 #13 已定）：这类注释**只写符号名，不写行号**。
// 本闸门兜住已经写了的那些：只判「行号是否超出该文件当前行数」，不判内容对不对
// （后者需要人读，静态做不到）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const byBase = new Map();
const allFiles = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const p = path.join(dir, f);
    const src = fs.readFileSync(p, 'utf8');
    const base = f.replace(/\.swift$/, '');
    if (!byBase.has(base)) byBase.set(base, []);
    byBase.get(base).push({ rel: `${d}/${f}`, lines: src.split(/\r?\n/).length });
    allFiles.push({ rel: `${d}/${f}`, src });
  }
}

const bad = [];
const checked = new Set();
for (const { rel, src } of allFiles) {
  const L = src.split(/\r?\n/);
  L.forEach((l, i) => {
    const t = l.trim();
    if (!/^\/\//.test(t)) return;
    const ms = [...t.matchAll(/([A-Za-z_][\w.]+?)(?:\.swift)?:(\d{2,4})\b/g)];
    for (const m of ms) {
      const base = m[1].replace(/\.swift$/, '');
      const ln = Number(m[2]);
      const key = base + ':' + ln;
      if (checked.has(key)) continue;
      checked.add(key);
      const files = byBase.get(base);
      if (!files) continue;
      if (!files.some(x => ln <= x.lines)) {
        bad.push({ loc: `${rel}:${i + 1}`, ref: m[0], max: Math.max(...files.map(x => x.lines)) });
      }
    }
  });
}

if (bad.length) {
  console.log(`✗ 注释里的行号引用越界 ${bad.length} 处：`);
  for (const b of bad) console.log(`  ${b.loc}  引用 \`${b.ref}\` —— 该文件最多 ${b.max} 行`);
  console.log('\n修法：改成只写符号名（本仓纪律：这类注释不写行号）。');
  process.exit(1);
}
console.log(`✓ 注释里的行号引用全部在范围内（检查 ${checked.size} 个不同引用）`);
