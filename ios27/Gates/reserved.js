#!/usr/bin/env node
// reserved.js —— RESERVED 清单与源码标记的对账闸门。
//
// 为什么需要：2026-11-01 的教训 —— 我按「注释里写着【保留未接】」采信，
// 结果 6 条里有一半其实早就接线了（标记过期没删）。反过来也可能有"标记了但没登记"。
// 两边的真值必须对齐，而人对齐不可靠。
//
// 判什么：
//   ① RESERVED.md 里每一行提到的**符号**，在 App/ 里必须存在；
//   ② 每个被登记的符号，在源码注释里必须有 `【保留未接` 标记（可共用一个标记，如 markDisabled/disableMark）。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');
const DOC = path.join(ROOT, 'docs', 'RESERVED.md');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

if (!fs.existsSync(DOC)) {
  console.log('reserved: SKIP — 没有 docs/RESERVED.md');
  process.exit(0);
}

const doc = fs.readFileSync(DOC, 'utf8');
const files = walk(APP);
const src = files.map((f) => fs.readFileSync(f, 'utf8')).join('\n');

const findings = [];
let checked = 0;

// ① 清单里的每个符号必须真实存在
for (const line of doc.split(/\r?\n/)) {
  if (!/^\|\s*\d+\s*\|/.test(line)) continue;
  // 只取第 2 列（符号列）里的反引号标识；行内其它反引号是说明文字，不是符号。
  const cells = line.split('|').map((c) => c.trim());
  const syms = [...(cells[2] || '').matchAll(/`([A-Za-z_][\w]*)/g)].map((m) => m[1]);
  for (const s of syms) {
    if (['CredentialOrg', 'CredentialOrgState', 'CredentialOrgBatch', 'MemberHub', 'HexKit',
         'RecordSearch', 'RecordSearchBuild', 'AutoOpenKit'].includes(s)) continue; // 文件名列
    checked++;
    if (!new RegExp('\\bfunc ' + s + '|' + '\\benum ' + s).test(src)) {
      findings.push('RESERVED 登记了 ' + s + '，但 App/ 里找不到这个符号（已删却没出表？）');
    }
  }
}



// ② 每个被登记的符号：在它自己的定义前 1200 字符内必须有【保留未接 标记。
// （不能只看"文件里有没有" —— 同一文件里另一个符号的标记会掩盖这一条。
//  我第一版就是文件级判定，验证时发现删掉一个标记仍判绿。）
const COLS = ['CredentialOrg', 'CredentialOrgState', 'CredentialOrgBatch', 'MemberHub', 'HexKit',
              'RecordSearch', 'RecordSearchBuild', 'AutoOpenKit'];
for (const line of doc.split(/\r?\n/)) {
  if (!/^\|\s*\d+\s*\|/.test(line)) continue;
  const cells = line.split('|').map((c) => c.trim());
  const syms = [...(cells[2] || '').matchAll(/`([A-Za-z_][\w]*)/g)].map((m) => m[1]);
  for (const s2 of syms) {
    const defFiles = files.filter((f) => new RegExp('\\bfunc ' + s2 + '\\b').test(fs.readFileSync(f, 'utf8')));
    if (defFiles.length === 0) continue;   // 已在 ① 报过
    let ok = false;
    for (const f of defFiles) {
      const txt = fs.readFileSync(f, 'utf8');
      const k = txt.search(new RegExp('\\bfunc ' + s2 + '\\b'));
      if (k >= 0 && txt.slice(Math.max(0, k - 1200), k).includes('【保留未接')) { ok = true; break; }
    }
    if (!ok) findings.push('RESERVED 登记了 ' + s2 + '，但它定义前没有【保留未接 标记（接线了却没删表？）');
  }
}

console.log('reserved: 登记符号 ' + checked + ' 个');
if (findings.length === 0) {
  console.log('reserved: OK — 清单与源码标记一致');
  process.exit(0);
}
console.log('reserved: FAIL — ' + findings.length + ' 处');
for (const f of findings) console.log('  ' + f);
process.exit(1);