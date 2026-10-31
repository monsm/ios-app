#!/usr/bin/env node
// lineage.js —— 与上一版的切割闸门（DESIGN-CONTRACT §12）。
//
// 判什么：新 App 里不许残留上一版设计系统的任何符号。
// 判据：VKTypography / DS.Space / DS.Radius / DS.Motion / DS.Palette / heroFg / HeroTexture / LockFace
//       出现即失败 —— 说明有人在旧壳上缝补，而不是从 0 做。
//
// 唯一允许：App/Engine/ 里从上一版照搬的**纯逻辑**文件（协议/密码学/存储/BLE）。
// 它们不含任何 UI 符号；若含，说明搬错了文件。
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

const BANNED = [
  'VKTypography', 'DS.Space', 'DS.Radius', 'DS.Motion', 'DS.Palette', 'DS.Icon', 'DS.Haptics',
  'DS.Hit', 'DS.Stroke', 'heroFg', 'heroPlate', 'HeroTexture', 'LockFace', 'VariantGrammar',
  'vkFont', 'axGlass', 'PageGrammar', 'KfPage',
];

const files = walk(APP);
const findings = [];

for (const f of files) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    for (const sym of BANNED) {
      // 单词边界，避免 'DS.Space' 命中 'DS.Spaces' 之类
      const re = new RegExp('\\b' + sym.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b');
      if (re.test(line)) findings.push({ file: rel, line: i + 1, sym, text: t.slice(0, 110) });
    }
  });
}

if (findings.length === 0) {
  console.log('lineage: OK — ' + files.length + ' 个文件，0 处上一版设计系统残留');
  process.exit(0);
}
console.log('lineage: FAIL — ' + findings.length + ' 处上一版残留（说明在旧壳上缝补）\n');
for (const f of findings) console.log('  ' + f.file + ':' + f.line + '  ' + f.sym + '  ' + f.text);
process.exit(1);
