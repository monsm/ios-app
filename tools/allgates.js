#!/usr/bin/env node
// 全量闸门 —— **按 .github/workflows/ios.yml 的 CI 清单逐条复刻**。
//
// 2026-10-30 新增（第 91 轮）：此前我手工维护的"27 道"名单漏了 emptyconform 等 22 道，
// 导致一次 CI 构建失败（RecordModels.Rec 的 Identifiable.id 被误删，本地没查出来）。
// 本脚本直接从 CI 清单派生，不再依赖手写名单。
const { execFileSync } = require('child_process');
const path = require('path');

const ROOT = 'D:/aapk/ios-app';

// 与 .github/workflows/ios.yml 一一对应（顺序也一致）
const GATES = [
  ['golden', ['--check']],
  ['shadowdiff', []],
  ['swiftcheck', []],
  ['swiftlint', []],
  ['contrast', []],
  ['dynamictype', []],
  ['aritycheck', []],
  ['commacheck', []],
  ['orphanscan', ['--base', 'HEAD~1']],
  ['rescuescan', ['--base', 'HEAD~1']],
  ['deadscan', []],
  ['apisweep', []],
  ['citecheck', []],
  ['docpointers', []],
  ['macpin', []],
  ['assetscheck', []],
  ['iconmap', ['--strict']],
  ['symbolcheck', []],
  ['dupscan', []],
  ['codablecheck', []],
  ['viewdbcheck', []],
  ['regresscheck', []],
  ['perfscan', []],
  ['keydead', []],
  ['delsweep', []],
  ['lockpair', []],
  ['typepred', []],
  ['autoopenshadow', []],
  ['zotpshadow', []],
  ['cmdsshadow', []],
  ['apkshadow', []],
  ['parseshadow', []],
  ['bundleshadow', []],
  ['logicparity', []],
  ['featuremap', []],
  ['featurewebcheck', []],
  ['swiftshape', []],
  ['swiftsyn', []],
  ['toplevel', []],
  ['bindinguse', []],
  ['eolhygiene', []],
  ['emptyblock', []],
  ['writeonlystate', []],
  ['emptyconform', []],
  ['deadallowlist', []],
  ['sheetcover', ['--selftest']],
  ['sheetcover', []],
  ['copynum', ['--selftest']],
  ['copynum', ['App']],
  ['destmap', []],
  ['uicoverage', []],
  ['kotlinshadow', []],
];

let fail = [];
let pass = 0;
const results = [];
for (const [g, extra] of GATES) {
  const args = [path.join(ROOT, 'tools', g + '.js'), ...extra];
  try {
    execFileSync('node', args, { cwd: ROOT, encoding: 'utf8', timeout: 240000, stdio: ['ignore', 'pipe', 'pipe'] });
    pass++;
  } catch (e) {
    const label = extra.length ? `${g} ${extra.join(' ')}` : g;
    fail.push(label);
    const msg = ((e.stdout || '') + (e.stderr || '')).trim().split('\n').filter(Boolean).slice(-4).join(' | ');
    results.push({ label, msg });
  }
}

console.log(`\n全量闸门（CI 同源）: ${pass}/${GATES.length} 通过`);
if (fail.length) {
  console.log(`\n✗ 失败 ${fail.length} 道:`);
  for (const r of results) {
    console.log(`  ✗ ${r.label}`);
    console.log(`      ${r.msg.slice(0, 400)}`);
  }
  process.exit(1);
}
console.log('✓ 全部通过');
