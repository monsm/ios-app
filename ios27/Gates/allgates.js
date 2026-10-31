#!/usr/bin/env node
// allgates.js —— 一次跑全部闸门。
'use strict';
const { execFileSync } = require('child_process');
const path = require('path');

const GATES = ['swiftparse', 'types', 'swiftcheck', 'tokens', 'contrast', 'glass', 'motion', 'a11y', 'dynamictype', 'reducedmotion', 'crosprivate', 'callsig', 'callsig2', 'lineage', 'workflow', 'destmap'];

let failed = 0;
for (const g of GATES) {
  const p = path.join(__dirname, g + '.js');
  try {
    const out = execFileSync(process.execPath, [p], { encoding: 'utf8' });
    console.log(out.trim().split('\n')[0]);
  } catch (e) {
    failed++;
    console.log((e.stdout || '').trim());
    console.log((e.stderr || '').trim());
  }
}
console.log('');
if (failed === 0) {
  console.log(`allgates: 全部 ${GATES.length} 道闸门通过`);
  process.exit(0);
}
console.log(`allgates: ${failed}/${GATES.length} 道闸门失败`);
process.exit(1);
