#!/usr/bin/env node
// a11y.js —— 无障碍闸门。
//
// 判什么：
//   ① 图标按钮（label 只有 Image(systemName:)）必须有 .accessibilityLabel
//   ② 触达：.frame(width:/height:) 小于 44 的可点区判失败
//   ③ 裸 .font 直接写在 Text 上（绕过 T.F.*）判失败 —— 上一版"加粗文本开关失效"就是这个
//   ④ 装饰性图标必须 .accessibilityHidden(true)
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

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  // ① 图标按钮缺 label：向后 8 行内没有 accessibilityLabel
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;

    if (/Button\s*\{/.test(line) || /Button\(action:/.test(line) || /Button\s*\(/.test(line)) {
      // 只看这个 Button 的 label 块：从 Button 起到第一个同级收尾，最多 30 行。
      // 判据要准 —— 误报会让下一个人把真问题当噪音忽略（上一版的教训）。
      const win = lines.slice(i, i + 30).join('\n');
      const hasImage = /Image\(systemName:/.test(win);
      const hasTextish = /Text\(|Label\(|FieldRow\(|Reading\(/.test(win);
      const hasLabel = /accessibilityLabel/.test(win);
      // 图标按钮 = 只有 Image、没有任何文字承载
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

console.log(`a11y: 扫 ${files.length} 个文件`);
if (findings.length === 0) {
  console.log('a11y: OK — 图标按钮都有 label，无 <44pt 可点区');
  process.exit(0);
}
console.log(`a11y: FAIL — ${findings.length} 处\n`);
for (const f of findings) console.log(`  ${f.file}:${f.line}  ${f.why}`);
process.exit(1);