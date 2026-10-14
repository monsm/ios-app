#!/usr/bin/env node
// 布局对抗式审计 —— 从 Swift 源码算几何，不靠截图、不靠编译器
//   node tools/layout-audit/run.js              全档扫描 + 控制台摘要
//   node tools/layout-audit/run.js --quiet      只出摘要
//   node tools/layout-audit/run.js --worst      每个问题只保留最糟的那一档条件 (推荐看这份)
// 输出: tools/layout-audit/findings.json
//
// 扫描条件: 2 档密度 (标准/宽松) × 3 机型宽 (375/390/430) × 3 档字号 (0.8/1.0/1.75)
//   —— 字号档取 App 自己的 kf_font_scale 两端与中间，密度取令牌缩放两端。
'use strict';
const fs = require('fs');
const path = require('path');
const A = require('./ast.js');
const R = require('./rules.js');
const ROOT = path.resolve(__dirname, '../..');
const QUIET = process.argv.includes('--quiet');
const WORST = process.argv.includes('--worst');

function walk(d, out = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (!/Assets\.xcassets/.test(p)) walk(p, out); }
    else if (p.endsWith('.swift')) out.push(p);
  }
  return out;
}
const tk = A.loadTokens(path.join(ROOT, 'App/Core/DesignSystem.swift'));
if (!Object.keys(tk.SPACE).length) { console.error('DesignSystem 令牌没解析到，停'); process.exit(1); }
const files = walk(path.join(ROOT, 'App')).sort();
const DENS = [1.0, 1.18], SCALES = [0.8, 1.0, 1.75];
const cache = {};
const all = [];
for (const dens of DENS) {
  const pre = R.parseAll(files, tk, dens, cache);
  for (const dev of A.DEVICES) for (const scale of SCALES) {
    R.runAll(pre, { tk, scale, deviceW: dev.w, dens }).forEach((f) => all.push({ ...f, cond: `${dev.n}/${scale}/${dens === 1 ? '标准' : '宽松'}` }));
  }
}
// 每条问题只留最严重的一档条件（重叠按 高>中>低 再按"超出量"取最大）
const sev = { hi: 0, md: 1, lo: 2 };
const best = new Map();
for (const f of all) {
  const k = f.rule + '|' + f.file + '|' + f.line;
  const cur = best.get(k);
  if (!cur || sev[f.sev || 'lo'] < sev[cur.sev || 'lo']) best.set(k, f);
}
const list = WORST ? [...best.values()] : all;
const byRule = {}, byFile = {};
list.forEach((f) => { byRule[f.rule] = (byRule[f.rule] || 0) + 1; const b = path.basename(f.file); byFile[b] = (byFile[b] || 0) + 1; });
fs.writeFileSync(path.join(__dirname, 'findings.json'), JSON.stringify(list, null, 1));

console.log(`扫描 ${files.length} 个文件 · 条件 ${DENS.length * A.DEVICES.length * SCALES.length} 档 · 原始命中 ${all.length} · 去重后 ${list.length} 条`);
console.log('\n按判据:');
Object.entries(byRule).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log('  ' + String(v).padStart(4) + '  ' + k));
console.log('\n问题最多的文件 top 12:');
Object.entries(byFile).sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([k, v]) => console.log('  ' + String(v).padStart(4) + '  ' + k));
if (!QUIET) {
  console.log('\n=== 高严重度 (会切字/挤爆/触达不足) ===');
  list.filter((f) => f.sev === 'hi').slice(0, 40).forEach((f) => console.log(`  [${f.rule}] ${path.basename(f.file)}:${f.line}  ${f.msg}\n        条件 ${f.cond} · ${f.calc || ''}`));
}
const blind = new Set(all.filter((f) => f.rule.startsWith('R0')).map((f) => path.basename(f.file) + ':' + f.line));
console.log(`\nAST 盲区 (这些区域未参与判定): ${blind.size} 处 —— ${[...blind].slice(0, 6).join(' ')}`);
console.log('findings.json 已写出:', path.join(__dirname, 'findings.json'));
