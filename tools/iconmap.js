#!/usr/bin/env node
// 210 图标一致性检查 (顾问级, 不判失败) — node tools/iconmap.js [--list]
// 为什么本批才补：210 在 FEATURE-TRIAGE 里一直挂 "✅ CI 脚本"，而 tools/ 与 ios.yml 里**没有任何**图标校验
// (docs/AUDIT-E.md:21 早判 MISS，ROADMAP-DRAFT:184 却把它列在"收录") —— 又一个"把计划记成已做"。
//
// 判据（可证伪）：**同一条标签文字**在 App 里出现多次时，它配的图标基名必须一致。
//   标签取 `Label("文字", systemImage: "图标")` / 同行 `Image(systemName:)+Text("文字")` / `Button("文字")…systemImage:` 三种形状，
//   并把标签里的 `(编号)` 尾巴与空白去掉后做**整串相等**比较。
//   图标只差 `.fill` 后缀不算违例 —— 那是有意的状态对（未选中/选中）。
// 为什么不是"按动词子串"分组（前两版都试过）：`彻底删除`(xmark.bin) 与 `删除`(trash) 是**两个不同操作**、
//   `告警分享卡` 与 `告警一页纸` 也是两个不同产物 —— 按子串归组会把它们报成不一致，23 族命中里一大半是这个形状。
//   噪音会毁掉顾问闸门的可信度（本仓已记过两次同族教训），所以判据收紧到"同一串文字"，宁可少报。
// --list 顺带产出"标签 → 图标"对照表（210 要求的另一半：清单本身由代码生成，不手抄）。
'use strict';
const fs = require('fs');
const path = require('path');
// ROOT 探测要跳过 `--out <file>` 的值 —— 否则 `--out docs/ICONMAP.md` 会被当成要扫描的目录 (踩过一次)。
const ROOT = (() => {
  const oi = process.argv.indexOf('--out');
  const skip = oi > 1 ? process.argv[oi + 1] : '';
  return process.argv.find((a, i) => i > 1 && !a.startsWith('--') && a !== skip) || 'App';
})();
const LIST = process.argv.includes('--list');
// 210 硬闸门 (2026-10-13 接线): 此前只有"顾问级"输出, 从不判失败 —— 原句要的是"并入构建闸门"。
// 现在 --strict 在有任一"同标签多图标基名"族时以非零码退出; CI 里那一步是真闸门。
// 之所以敢上硬闸门: 判据已收紧到"同一条标签文字" (按子串分组会把'彻底删除'与'删除'误报成不一致),
// 接线当日的实测是 **0 族命中** (671 处引用 / 236 处可配对 / 214 个标签族), 不是靠"反正是顾问级"糊过去。
const STRICT = process.argv.includes('--strict');
const OUT = (() => { const i = process.argv.indexOf('--out'); return i > 1 ? process.argv[i + 1] : ''; })();

const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (p.endsWith('.swift')) files.push(p);
  }
})(ROOT);

const norm = (s) => s.replace(/\s+/g, '').replace(/[（(][0-9/、§·A-Za-z]{1,14}[)）]\s*$/, '').trim();
const pairs = [];   // {label, sym, file, line}
let iconTotal = 0;
for (const f of files) {
  const text = fs.readFileSync(f, 'utf8');
  iconTotal += (text.match(/systemImage:|Image\(systemName:/g) || []).length;
  text.split(/\r?\n/).forEach((raw, i) => {
    const line = raw.replace(/^\s*\/\/.*$/, '');
    if (!line.trim()) return;
    const push = (label, sym) => { const l = norm(label); if (l && sym) pairs.push({ label: l, sym, f, line: i + 1 }); };
    for (const m of line.matchAll(/Label\(\s*"([^"]{1,40})"[^)]*?systemImage:\s*"([a-zA-Z0-9.]+)"/g)) push(m[1], m[2]);
    for (const m of line.matchAll(/Label\(\s*systemImage:\s*"([a-zA-Z0-9.]+)"[^)]*?"([^"]{1,40})"/g)) push(m[2], m[1]);
    const im = /Image\(systemName:\s*"([a-zA-Z0-9.]+)"/.exec(line);
    const tx = /Text\(\s*"([^"]{1,40})"/.exec(line);
    if (im && tx) push(tx[1], im[1]);
    const bt = /Button\(\s*(?:role:\s*\.\w+,\s*)?"([^"]{1,40})"/.exec(line);
    const sy = /systemImage:\s*"([a-zA-Z0-9.]+)"/.exec(line);
    if (bt && sy) push(bt[1], sy[1]);
  });
}
const byLabel = new Map();
for (const p of pairs) {
  if (!byLabel.has(p.label)) byLabel.set(p.label, new Map());
  const fam = byLabel.get(p.label);
  const base = p.sym.replace(/\.fill$/, '');
  if (!fam.has(base)) fam.set(base, { count: 0, sites: [] });
  const e = fam.get(base);
  e.count++;
  if (e.sites.length < 3) e.sites.push(`${p.f}:${p.line}`);
}
let flagged = 0;
for (const [label, fam] of [...byLabel.entries()].sort()) {
  if (fam.size <= 1) continue;
  flagged++;
  const parts = [...fam.entries()].sort((a, b) => b[1].count - a[1].count)
    .map(([base, e]) => `${base}×${e.count} @${e.sites[0]}`);
  console.log(`  「${label}」同一标签配了 ${fam.size} 个不同基名: ${parts.join('  |  ')}`);
}
const tableLines = [];
if (LIST || OUT) {
  tableLines.push('—— 标签 → 图标 对照表 (210 的另一半, 由代码生成, 不手抄) ——');
  for (const [label, fam] of [...byLabel.entries()].sort((a, b) => b[1].count - a[1].count)) {
    const [base, e] = [...fam.entries()].sort((x, y) => y[1].count - x[1].count)[0];
    tableLines.push(`  ${('「' + label + '」').padEnd(14, ' ')} ${base}  ×${e.count}`);
  }
}
if (LIST) console.log('\n' + tableLines.join('\n'));
if (OUT) {
  // 清单落盘 (生成物, 不手改): node tools/iconmap.js --list --out docs/ICONMAP.md
  const head = ['# 图标对照清单 (210)', '',
    '> 生成物 —— 由 `node tools/iconmap.js --list --out docs/ICONMAP.md` 产出, 不要手改。',
    '> 判据: 同一条标签文字在 App 里出现多次时, 它配的图标基名必须一致 (只差 `.fill` 不算违例)。',
    ''].join('\n');
  fs.writeFileSync(OUT, head + '```\n' + tableLines.join('\n') + '\n```\n');
  console.log('清单已写入 ' + OUT);
}
console.log(`图标一致性 (210${STRICT ? ', 硬闸门' : ', 顾问级'}): 图标引用 ${iconTotal} 处 · 能与标签配成"同一条"的 ${pairs.length} 处 · 标签族 ${byLabel.size} 个 · 同标签多图标 ${flagged} 族`);
if (STRICT && flagged > 0) {
  console.error(`\n✗ 210 图标一致性: ${flagged} 族"同一条标签配了不同图标基名" —— 要么统一基名, 要么把差异写清 (--list 看对照表)。`);
  process.exit(1);
}
if (STRICT) console.log('✓ 210 图标一致性: 0 族不一致');
