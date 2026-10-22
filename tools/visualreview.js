#!/usr/bin/env node
// tools/visualreview.js —— 把"改了哪些视觉属性"按界面列出来，供人工验收
//
// 为什么需要它：
//   这个会话改了 51 个 swift 文件（32 个在 App/UI）。人工验收时面对 diff 无从下手 ——
//   而真正需要"用眼睛看"的，只是其中碰了字体/间距/颜色/frame 的那些行。
//
//   本工具不判断好坏，只把**需要看的地方**按界面列整齐。
//
// 用法:
//   node tools/visualreview.js            # 默认看最近 60 个 commit
//   node tools/visualreview.js <baseRef>  # 指定起点，例如 v1.0 或某个 sha
'use strict';
const { execSync } = require('child_process');

const base = process.argv[2] || 'HEAD~130';   // 覆盖本会话全部提交
const VISUAL = /\.xFont\(|XSpace\.|XPalette\.|XRadius\.|XIcon\.|XHit\.|XOpacity\.|\.frame\(|\.padding\(|\.xPlate\(|opacity\(|font\(\.system\(size:|lineLimit|minimumScaleFactor/;

let diff = '';
try {
  // ⚠ 路径不能带引号：execSync 在 Windows 上走 cmd.exe，单引号不是引号字符，
  //   会被当成路径的一部分传给 git → 匹配不到任何文件（第一版就是这样空跑的）。
  diff = execSync(`git diff ${base}..HEAD --unified=0 -- App/UI/`, {
    cwd: require('path').resolve(__dirname, '..'),
    encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
} catch (e) {
  console.log('取 diff 失败（base=' + base + '）：' + e.message);
  process.exit(1);
}

const byFile = new Map();
let cur = null, lineNo = 0;
for (const raw of diff.split('\n')) {
  if (raw.startsWith('+++ b/')) { cur = raw.slice(6); if (!byFile.has(cur)) byFile.set(cur, []); continue; }
  if (!cur) continue;
  const m = raw.match(/^@@ -[0-9,]+ \+([0-9]+)/);
  if (m) { lineNo = parseInt(m[1], 10); continue; }
  if (raw.startsWith('+') && !raw.startsWith('+++')) {
    const text = raw.slice(1);
    if (VISUAL.test(text)) byFile.get(cur).push({ line: lineNo, text: text.trim() });
    lineNo++;
  }
}

// 哪些是本次**新建**的文件 —— 它们风险最高，因为从来没人看过一眼。
const added = new Set();
try {
  const ns = execSync(`git diff --name-status ${base}..HEAD -- App/UI/`, {
    cwd: require('path').resolve(__dirname, '..'), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
  });
  for (const l of ns.split('\n')) { const m = l.match(/^A\s+(.+)$/); if (m) added.add(m[1].trim()); }
} catch {}

const rows = [...byFile.entries()].filter(([, v]) => v.length).sort((a, b) => b[1].length - a[1].length);
if (!rows.length) { console.log('没有视觉属性改动。'); process.exit(0); }

console.log('视觉改动汇总（' + base + '..HEAD）');
console.log('共 ' + rows.length + ' 个界面文件需要"用眼睛看"，' + rows.reduce((s, [, v]) => s + v.length, 0) + ' 处。');
if (added.size) {
  console.log('');
  console.log('⚠ 其中 ' + added.size + ' 个是本次**新建**的文件（从没人看过一眼，优先验）：');
  for (const a of added) console.log('   ' + a.replace('App/UI/', ''));
}
console.log('');
for (const [file, items] of rows) {
  console.log('── ' + file.replace('App/UI/', '') + '  (' + items.length + ' 处)');
  for (const it of items.slice(0, 6)) console.log('   ' + String(it.line).padStart(5) + ': ' + it.text.slice(0, 96));
  if (items.length > 6) console.log('   … 另有 ' + (items.length - 6) + ' 处');
  console.log('');
}
console.log('验收提示：这份清单只说明"哪里动了"，不说明"动得对不对"。');
console.log('逐文件打开、对照 MANUAL-ACCEPTANCE.md 的 C1–C5 看观感，比读 diff 有效。');

