'use strict';
// tools/subtitlesync.js —— SUBTITLES.md 基线 ↔ 代码零漂移闸门
//
// 第 32 轮起，40 个 XScreen 页全部带副标题（docs/SUBTITLES.md 有基线表）。
// 这把尺子保证文档与代码不脱节：
//   S1 代码里每个 XScreen(title, subtitle:) 都必须在基线表里
//   S2 基线表里每行都必须能在代码里找到原句
//   S3 代码里出现无副标题的 XScreen(title) { ⇒ 报（新页必须带副标题）
//   S4 副标题含数字 ⇒ 报（数字由读数卡承担，HTML 的 mock 数字不许搬）
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const UI = path.join(ROOT, 'App/UI');
const DOC = path.join(ROOT, 'docs/SUBTITLES.md');

// ① 读基线表
const doc = fs.readFileSync(DOC, 'utf8');
const baseline = new Map();   // title -> sub
for (const m of doc.matchAll(/^\| ([^|]+) \| ([^|]+) \|/gm)) {
  const t = m[1].trim(), s = m[2].trim();
  if (t && t !== '页' && !t.startsWith('---') && s && s !== '副标题') baseline.set(t, s);
}
// ② 扫代码
const code = new Map();       // title -> sub ('' = 无)
let noSub = [];
for (const f of fs.readdirSync(UI).filter(x => x.endsWith('.swift'))) {
  const s = fs.readFileSync(path.join(UI, f), 'utf8').replace(/\r\n/g, '\n');
  for (const m of s.matchAll(/XScreen\(\s*"([^"]+)"\s*(?:,\s*subtitle:\s*"([^"]*)")?\s*\)/g)) {
    code.set(m[1], m[2] || '');
    if (!m[2]) noSub.push(f + ' 「' + m[1] + '」');
  }
}
// ③ 对账
const problems = [];
for (const [t, sub] of code) {
  if (!sub) continue;
  if (!baseline.has(t)) problems.push('S1 基线表缺页: 「' + t + '」');
  else if (baseline.get(t) !== sub) problems.push('S2 漂移: 「' + t + '」 表="' + baseline.get(t) + '" 码="' + sub + '"');
}
for (const [t, sub] of baseline) {
  if (!code.has(t)) problems.push('S2 基线表多余行: 「' + t + '」（代码里没有这个标题）');
  else if (code.get(t) !== sub) problems.push('S2 漂移: 「' + t + '」');
}
for (const n of noSub) problems.push('S3 新页无副标题: ' + n);
for (const [t, sub] of code) if (sub && /\d/.test(sub)) problems.push('S4 副标题含数字: 「' + t + '」');

if (problems.length) {
  problems.slice(0, 15).forEach(p => console.error('  ' + p));
  console.error('✗ 副标题基线漂移 ' + problems.length + ' 处');
  process.exit(1);
}
console.log('副标题基线 ✓ ' + code.size + ' 页与 SUBTITLES.md 逐字一致（S1-S4）');
