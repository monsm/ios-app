#!/usr/bin/env node
// l10n.js —— 文案 key 的完整性闸门（B65）。
//
// 判据：页面里用到的每一个 `L("…")` / `L10n.t("…")` 的 key，
// 都必须能在 `App/Core/L10n.swift` 的表里找到。
//
// 为什么要有它：key 化之后，漏一个 key 不会编译失败、也不会崩 ——
// 它只是**默默显示成那串 key**（L10n.t 的回落口径）。
// 没有这道闸，漏译要靠人眼在界面上找。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TABLE_FILE = path.join(ROOT, 'App', 'Core', 'L10n.swift');
const APP = path.join(ROOT, 'App');

if (!fs.existsSync(TABLE_FILE)) {
  console.log('l10n: SKIP — 没有 App/Core/L10n.swift');
  process.exit(0);
}

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 表里的 key：形如 "x.y": "文本",
const tableSrc = fs.readFileSync(TABLE_FILE, 'utf8');
const known = new Set();
const tableRe = /"([a-zA-Z0-9_.]+)"\s*:\s*"/g;
let m;
while ((m = tableRe.exec(tableSrc)) !== null) known.add(m[1]);

// 页面里的调用：L("key") 与 L10n.t("key")
const used = new Map(); // key -> [file:line]
const callRes = [/\bL10n\.t\(\s*"([a-zA-Z0-9_.]+)"/g, /(?<![A-Za-z0-9_.])L\(\s*"([a-zA-Z0-9_.]+)"/g];

for (const file of walk(APP)) {
  if (path.resolve(file) === path.resolve(TABLE_FILE)) continue;
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    const trimmed = line.trim();
    if (trimmed.startsWith('//')) return;
    for (const re of callRes) {
      re.lastIndex = 0;
      let mm;
      while ((mm = re.exec(line)) !== null) {
        const key = mm[1];
        if (!used.has(key)) used.set(key, []);
        used.get(key).push(`${path.relative(ROOT, file).split(path.sep).join('/')}:${i + 1}`);
      }
    }
  });
}

const missing = [...used.entries()].filter(([k]) => !known.has(k));
const unused = [...known].filter((k) => !used.has(k));

if (missing.length) {
  console.error('l10n: FAIL — 用到了表里没有的 key（界面上会显示成这串 key）：');
  for (const [k, locs] of missing) console.error(`  ${k}  ← ${locs.join(', ')}`);
  process.exit(1);
}
console.log(`l10n: OK — ${used.size} 个 key 全部在表里（表内共 ${known.size} 个，${unused.length} 个暂未使用）`);
