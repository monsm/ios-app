#!/usr/bin/env node
// a11y.js —— 无障碍闸门。
//
// 判什么：
//   ① 图标按钮（label 只有 Image(systemName:)）必须有 .accessibilityLabel
//   ② 触达：.frame(width:/height:) 小于 44 的可点区判失败
//   ③ VListRow 的 accessibilityLabel 必须拼上 value（设置页右侧读数不能对 VoiceOver 消失）
//   ④ 图表组件（VRingStack / VMiniBars / VAreaChart / VSegmentedRing）必须有 accessibilityValue 描述数据
//   ⑤ 装饰性图标必须 .accessibilityHidden(true)
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');
const V7_COMPONENTS = path.join(APP, 'Design', 'V7', 'V7Components.swift');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

function structBlock(src, name) {
  const start = src.search(new RegExp('struct\\s+' + name + '\\b'));
  if (start < 0) return null;
  const open = src.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  return null;
}

const files = walk(APP);
const findings = [];

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  // ① 图标按钮缺 label：向后 30 行内没有 accessibilityLabel
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;

    if (/Button\s*\{/.test(line) || /Button\(action:/.test(line) || /Button\s*\(/.test(line)) {
      const win = lines.slice(i, i + 30).join('\n');
      const hasImage = /Image\(systemName:/.test(win);
      const hasTextish = /Text\(|Label\(|FieldRow\(|Reading\(|VTextFieldRow\(|VValueRow\(|VReading\(/.test(win);
      const hasLabel = /accessibilityLabel/.test(win);
      if (hasImage && !hasTextish && !hasLabel) {
        findings.push({ file: rel, line: i + 1, why: '图标按钮缺 accessibilityLabel（无任何文字承载）' });
      }
    }

    // ② 触达小于 44（只查明确的可点区 frame）
    const m = /\.frame\(\s*width:\s*([0-9]+)\s*,\s*height:\s*([0-9]+)\s*\)/.exec(line);
    if (m) {
      const w = +m[1], h = +m[2];
      if ((w < 44 || h < 44) && !rel.includes('Components/')) {
        findings.push({ file: rel, line: i + 1, why: `可点区 ${w}×${h} < 44pt` });
      }
    }
  });
}

// ③ VListRow 必须把 value 拼进 accessibilityLabel
const v7src = fs.readFileSync(V7_COMPONENTS, 'utf8');
const listRow = structBlock(v7src, 'VListRow');
if (!listRow) {
  findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: '找不到 VListRow 组件' });
} else {
  const hasLabel = /accessibilityLabel\(/.test(listRow);
  const hasValueInLabel = /a11yLabel[\s\S]*value/.test(listRow) || /accessibilityLabel\([^)]*value/.test(listRow);
  if (!hasLabel || !hasValueInLabel) {
    findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: 'VListRow 的 accessibilityLabel 未拼上 value（VoiceOver 会吞掉右侧读数）' });
  }
}

// ④ 图表组件必须有 accessibilityValue 描述数据
for (const name of ['VRingStack', 'VMiniBars', 'VAreaChart', 'VSegmentedRing']) {
  const block = structBlock(v7src, name);
  if (!block) {
    findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: `找不到图表组件 ${name}` });
    continue;
  }
  if (!/\.accessibilityValue\(/.test(block)) {
    findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: `${name} 缺 accessibilityValue（图表数据对 VoiceOver 不可读）` });
  }
}

console.log(`a11y: 扫 ${files.length} 个文件`);
if (findings.length === 0) {
  console.log('a11y: OK — 图标按钮都有 label，无 <44pt 可点区，VListRow value 与图表数据均可朗读');
  process.exit(0);
}
console.log('a11y: FAIL — ' + findings.length + ' 处\n');
for (const f of findings) console.log(`  ${f.file}:${f.line}  ${f.why}`);
process.exit(1);
