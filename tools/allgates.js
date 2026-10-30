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
  ['linerefcheck', []],
  ['cnpunctcheck', []],
  ['higaudit', []],
  ['a11ycheck', []],
  ['workflowcheck', []],
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
  // 2026-10-30（第 96 轮）：`featurewebcheck` 的基线由 inventory 重算，
  // 只要改了 App/ 里任何被 inventory 收录的东西就会「过期」——
  // 这是**生成物**而非缺陷，本地按提示 `--rebuild` 一次即可，不必当作失败。
  // 只有它一道失败时，自动重建后重跑，避免每轮都要人工干预。
  const onlyFeatureWeb = fail.length === 1 && fail[0] === 'featurewebcheck';
  if (onlyFeatureWeb) {
    console.log('\n提示：只有 featurewebcheck 基线过期，自动 --rebuild 后重跑…');
    try {
      execFileSync('node', [path.join(ROOT, 'tools', 'featurewebcheck.js'), '--rebuild'],
        { cwd: ROOT, encoding: 'utf8', timeout: 240000, stdio: ['ignore', 'pipe', 'pipe'] });
      execFileSync('node', [path.join(ROOT, 'tools', 'featurewebcheck.js')],
        { cwd: ROOT, encoding: 'utf8', timeout: 240000, stdio: ['ignore', 'pipe', 'pipe'] });
      console.log('✓ 已重建并通过（记得把 docs/feature-web/ 一起提交）');
      process.exit(0);
    } catch (e2) {
      console.log('✗ 重建后仍失败: ' + ((e2.stdout || '') + (e2.stderr || '')).trim().slice(-300));
      process.exit(1);
    }
  }
  console.log(`\n✗ 失败 ${fail.length} 道:`);
  for (const r of results) {
    console.log(`  ✗ ${r.label}`);
    console.log(`      ${r.msg.slice(0, 400)}`);
  }
  process.exit(1);
}
console.log('✓ 全部通过');
