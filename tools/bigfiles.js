#!/usr/bin/env node
// 大文件结构盘点（P4）—— 把"十个大文件 24,729 行从未读过源"变成一份可复算的清单。
//
// 为什么要工具而不是"读一遍"：
//   ① 24.7k 行读一遍是一次性的，而这份清单下个季度就要重算（文件还在长）；
//   ② 核对"归属表"只需要**结构**（有哪些视图类型、每个有哪几节），不需要读实现；
//   ③ 读一遍的结论是散文，会漂；工具的结论是数字，会红。
//
// 它报线索、不判失败（恒退出 0）：这里没有"应该有几个视图"这种先验，
// 唯一的作用是把"有哪些东西"钉在纸面上。
//
// 用法: node tools/bigfiles.js [--lines N] [--verbose]

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', 'App');
const argv = process.argv.slice(2);
const MIN_LINES = (() => {
  const i = argv.indexOf('--lines');
  return i >= 0 ? parseInt(argv[i + 1], 10) : 800;
})();
const verbose = argv.includes('--verbose');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 结构模式：视图类型 / 分节标题 / 私有视图件
const RE_TYPE = /^\s*(?:private\s+|internal\s+|public\s+|fileprivate\s+)?struct\s+(\w+)\s*:\s*(View|ViewModifier|ButtonStyle|ToggleStyle|LabelStyle|Shape|InsettableShape|ObservableObject|Identifiable)\b/;
const RE_EXT_VIEW = /^\s*extension\s+(\w+)\s*:\s*View\b/;
const RE_EXT = /^\s*extension\s+(\w+)\s*[:{]/;
const RE_SECTION = /^\s*\/\/\s*MARK:\s*-\s*(.+)$/;
const RE_FUNC = /^\s*(?:private\s+)?func\s+(\w+)/;
const RE_TODOSECTION = /^\s*\/\/\s*=+\s*$/;

const rows = [];
for (const f of walk(ROOT)) {
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split('\n');
  if (lines.length < MIN_LINES) continue;
  const types = [];
  const sections = [];
  const exts = [];
  let funcs = 0;
  lines.forEach((l, i) => {
    let m;
    if ((m = l.match(RE_TYPE))) types.push(`${m[1]}${m[2] === 'View' ? '' : ':' + m[2]}`);
    else if ((m = l.match(RE_EXT_VIEW))) exts.push(m[1]);
    else if ((m = l.match(RE_EXT)) && /(View|Style|Shape|Kit)\b/.test(l)) exts.push(m[1]);
    if ((m = l.match(RE_SECTION))) sections.push(m[1].trim());
    if (RE_FUNC.test(l)) funcs++;
  });
  rows.push({
    rel: path.relative(path.join(__dirname, '..'), f).replace(/\\/g, '/'),
    lines: lines.length,
    types,
    exts,
    sections,
    funcs,
  });
}

rows.sort((a, b) => b.lines - a.lines);
const total = rows.reduce((s, r) => s + r.lines, 0);
console.log(`大文件结构盘点 (>= ${MIN_LINES} 行): ${rows.length} 个文件, 合计 ${total} 行\n`);
for (const r of rows) {
  console.log(`${r.rel}  ${r.lines} 行  视图类型 ${r.types.length} 个  扩展 ${r.exts.length} 个  func ${r.funcs} 个`);
  if (verbose) {
    if (r.types.length) console.log('   类型: ' + r.types.join(' · '));
    if (r.exts.length) console.log('   扩展: ' + [...new Set(r.exts)].join(' · '));
    if (r.sections.length) console.log('   分节: ' + r.sections.join(' · '));
  }
}
console.log('\n提示: --verbose 打印逐文件的类型/扩展/分节清单（P4 的归属表核对照这个）。');
// 不判失败：这是一份线索，不是判决。
process.exit(0);
