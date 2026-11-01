#!/usr/bin/env node
// glass.js —— 玻璃纪律闸门。
//
// 判什么（DESIGN-CONTRACT §6）：
//   ① 内容层不许出现 glassEffect（玻璃只在功能层，系统控件自己会加）
//   ② 同屏自定义玻璃面 ≤2
//   ③ 玻璃不叠玻璃
//   ④ 不许自己铺半透明底替代 scroll edge effect
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

const files = walk(APP);
const findings = [];
let totalGlass = 0;

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  let glassInFile = 0;
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;

    if (/\.glassEffect\s*\(/.test(line)) {
      glassInFile++;
      totalGlass++;
      // 允许：只在 Shell（浮动功能层）与明确的 control 文件里
      if (!rel.startsWith('Shell/') && !rel.includes('Components/Glass')) {
        findings.push({ file: rel, line: i + 1, why: '内容层出现 glassEffect（玻璃只属于功能层）' });
      }
    }
    // 2026-11-01 收紧：Material 只允许出现在**唯一的玻璃入口**里。
    // 为什么：本轮把浮动 Tab 栏从 `.ultraThinMaterial` + 自家染色换成了原生 `.glassEffect`
    // —— 前者只是"模糊 + 一层半透明色"，后者才采样背后内容做折射。
    // 若允许各处再用 Material 搓玻璃，两种观感会混在同一屏里，且「减少透明度」的退化判断会散掉。
    if (/\.(ultraThin|thin|regular|thick)Material\b/.test(line)) {
      if (!rel.includes('Components/GlassSurface.swift')) {
        findings.push({ file: rel, line: i + 1, why: 'Material 只允许出现在 Components/GlassSurface.swift（玻璃的唯一入口）' });
      }
    }
    // 自己铺半透明底当滚动边缘（应该用 .scrollEdgeEffectStyle）
    if (/\.background\(\s*Ink\.paper\.opacity|Color\.black\.opacity\(0\.\d+\)\s*,\s*in:\s*\.rect/.test(line)) {
      findings.push({ file: rel, line: i + 1, why: '疑似自铺半透明底（应走 scrollEdgeEffectStyle）' });
    }
  });

  if (glassInFile > 2) {
    findings.push({ file: rel, line: 0, why: `同屏自定义玻璃面 ${glassInFile} 个 > 2` });
  }
}

console.log(`glass: 扫 ${files.length} 个文件，自定义玻璃面 ${totalGlass} 处`);
if (findings.length === 0) {
  console.log('glass: OK — 玻璃只在功能层，同屏 ≤2，无叠玻璃');
  process.exit(0);
}
console.log(`glass: FAIL — ${findings.length} 处\n`);
for (const f of findings) console.log(`  ${f.file}:${f.line}  ${f.why}`);
process.exit(1);
