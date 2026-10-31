#!/usr/bin/env node
// allgates.js —— 一次跑全部闸门。
'use strict';
const { execFileSync } = require('child_process');
const path = require('path');

// callsig 已退役（2026-10-31）：它只扫 App/Design/Components 的旧组件，V7 页面根本不调用它们，
// 实测恒为「检查 0 处具名调用」= no-op。真正的调用签名闸门是 callsig2（7 类判据 + 成员表）。
// privacy 是第 16 道（2026-10-31 安全审计后新增）：把 AUDIT-F 的 7 类回归判据做成**判红**闸门 ——
// 剪贴板直写 / 备份明文 / 空壳只清界面 / 帧脱敏只处理首个 hex= / WebDAV http / 密钥文件无文件保护 / CSV 公式注入。
const GATES = ['swiftparse', 'types', 'swiftcheck', 'tokens', 'contrast', 'glass', 'motion', 'a11y', 'dynamictype', 'reducedmotion', 'crosprivate', 'callsig2', 'lineage', 'workflow', 'destmap', 'privacy'];

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
