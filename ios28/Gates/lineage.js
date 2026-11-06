#!/usr/bin/env node
// lineage.js —— 与上一版（ios27 的 V7/V8 设计系统）彻底切割。
// 新 App 里出现任何旧符号，即失败。这是"不要用现在任何前台设计"的机器证明。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const OLD = [
  'VKTypography', 'VGlassSurface', 'GlassTabBar', 'GlassSlideToUnlock',
  'VBearingArc', 'VGauge', 'VCard', 'VDotRule', 'VSegmentedRing',
  'VRingStack', 'VMiniBars', 'VAreaChart', 'VActionButton', 'VStatPair',
  'VHeroRing', 'VSpark', 'VDataRow', 'VChip2', 'VPage', 'VNavRow',
  'LockFace', 'heroFg', 'DS.Space', 'HHPageHeader', 'SettingsHeader',
  'KeysMaskedCode', 'V7Extras', 'V8.C', 'V8.T', 'V8.S',
];

const findings = [];
for (const file of walk(APP)) {
  const rel = path.relative(ROOT, file).split(path.sep).join('/');
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    const trimmed = line.trim();
    // 注释里提到旧令牌是历史说明，不是"又在用旧设计"；只看真正参与编译的行。
    if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) return;
    for (const sym of OLD) {
      if (line.includes(sym)) findings.push(`${rel}:${i + 1}  ${sym}\n      ${line.trim()}`);
    }
    // `V.` 命名空间（V7 令牌）—— 用词边界避免误伤普通单词
    if (/\bV\.[A-Z]/.test(line)) findings.push(`${rel}:${i + 1}  V.*\n      ${line.trim()}`);
  });
}

if (findings.length) {
  console.error('lineage: FAIL — 新 App 里出现旧设计系统符号：');
  for (const f of findings) console.error('  ' + f);
  process.exit(1);
}
console.log(`lineage: OK — ${walk(APP).length} 个文件，0 处上一版设计系统残留`);
