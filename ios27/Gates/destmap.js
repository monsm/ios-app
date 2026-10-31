#!/usr/bin/env node
// destmap.js —— 目的地台账对账。
//
// 判什么：Router.swift 里登记的每个 Dest，必须在 Destinations.swift 里有对应分支，
// 且该分支引用的 View 类型在 Features/ 里真的存在。少一条 = 有人会跳到一个不存在的页面。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

const router = fs.readFileSync(path.join(APP, 'Shell', 'Router.swift'), 'utf8');
const dests = fs.readFileSync(path.join(APP, 'Shell', 'Destinations.swift'), 'utf8');

// Router.swift 里的 case 列表（enum Dest 内部）
const enumBody = /enum Dest:[^{]*\{([\s\S]*?)\n\}/.exec(router);
if (!enumBody) {
  console.log('destmap: FAIL — 找不到 enum Dest');
  process.exit(1);
}
const declared = [...enumBody[1].matchAll(/^\s*case\s+(\w+)/gm)].map((m) => m[1]);
// 排除计算属性里的 case（tab 的 switch）
const tabSwitch = /var tab:\s*TabSlot[^{]*\{([\s\S]*?)\n    \}/.exec(enumBody[1]);
const tabCases = tabSwitch ? [...tabSwitch[1].matchAll(/case\s+([\w, .]+):/g)].flatMap((m) => m[1].split(',').map((s) => s.trim())) : [];
const realDests = declared.filter((d) => !tabCases.includes(d));

// Destinations.swift 的分支
const mapped = [...dests.matchAll(/case\s+\.(\w+):\s*(\w+)\(\)/g)].map((m) => ({ dest: m[1], view: m[2] }));

// 收集所有已声明的 View 类型
function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}
const swiftFiles = walk(APP);
const declaredViews = new Set();
for (const f of swiftFiles) {
  const src = fs.readFileSync(f, 'utf8');
  for (const m of src.matchAll(/(?:struct|final class|class)\s+(\w+)\s*:\s*View/g)) declaredViews.add(m[1]);
}

const findings = [];
const missingMap = realDests.filter((d) => !mapped.some((m) => m.dest === d));
for (const d of missingMap) findings.push(`Dest .${d} 没有在 Destinations.swift 里映射`);

const extraMap = mapped.filter((m) => !realDests.includes(m.dest));
for (const m of extraMap) findings.push(`Destinations.swift 映射了不存在的 Dest .${m.dest}`);

const missingView = mapped.filter((m) => !declaredViews.has(m.view));
for (const m of missingView) findings.push(`Dest .${m.dest} → ${m.view} 未声明（或不是 View）`);

console.log(`destmap: Dest ${realDests.length} 项，映射 ${mapped.length} 项，已声明 View ${declaredViews.size} 个`);
if (findings.length === 0) {
  console.log('destmap: OK — 台账与实现一一对应');
  process.exit(0);
}
console.log(`destmap: FAIL — ${findings.length} 处\n`);
for (const f of findings) console.log('  ' + f);
process.exit(1);
