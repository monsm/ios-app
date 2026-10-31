#!/usr/bin/env node
// workflow.js —— GitHub Actions 工作流结构闸门。
//
// 为什么需要它：2026-10-31 连着两次 run 秒红，报「Invalid workflow file」。
// 根因是 `--notes "..."` 字符串里有一个**未缩进的换行** —— YAML 把下一行当成新的键，
// 整份文档判为非法。这类错 CI 只会告诉你 invalid，不告诉你在哪，且本地无感知。
//
// 判什么：
//   ① 文件里不许有 TAB（YAML 禁止）
//   ② `run: |` 块内每一行的缩进必须**大于**该 run 键的缩进（裸换行会掉到 0）
//   ③ 顶层必须只有 name / on / permissions / defaults / jobs 这些已知键
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FILES = [
  path.join(ROOT, '..', '.github', 'workflows', 'ios27.yml'),
];

const findings = [];
let checked = 0;

for (const f of FILES) {
  if (!fs.existsSync(f)) continue;
  checked++;
  const rel = path.basename(f);
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);

  lines.forEach((line, i) => {
    if (line.includes('\t')) findings.push(rel + ':' + (i + 1) + ' 含 TAB（YAML 禁止）');
  });

  // ② run: | 块缩进
  for (let i = 0; i < lines.length; i++) {
    const m = /^(\s*)(- )?run:\s*\|\s*$/.exec(lines[i]);
    if (!m) continue;
    const baseIndent = m[1].length + (m[2] ? 2 : 0);
    for (let j = i + 1; j < lines.length; j++) {
      const line = lines[j];
      if (line.trim() === '') continue;
      const indent = line.length - line.trimStart().length;
      // 回到同级或更浅 = run 块结束
      if (indent <= baseIndent - (m[2] ? 2 : 0)) break;
      if (indent <= baseIndent) {
        findings.push(rel + ':' + (j + 1) + ' run 块里的行缩进不足（疑似裸换行截断文档）: ' + line.trim().slice(0, 60));
        break;
      }
    }
  }

  // ③ 顶层键白名单
  const ALLOW = new Set(['name', 'on', 'permissions', 'defaults', 'jobs', 'env', 'concurrency', 'run-name']);
  lines.forEach((line, i) => {
    const m = /^([A-Za-z_][\w-]*):/.exec(line);
    if (m && !ALLOW.has(m[1])) findings.push(rel + ':' + (i + 1) + ' 未知顶层键 ' + m[1]);
  });
}

if (checked === 0) {
  console.log('workflow: SKIP — 没找到 .github/workflows/ios27.yml');
  process.exit(0);
}
console.log('workflow: 检查 ' + checked + ' 个文件');
if (findings.length === 0) {
  console.log('workflow: OK — 无 TAB，run 块缩进正确，顶层键合法');
  process.exit(0);
}
console.log('workflow: FAIL — ' + findings.length + ' 处\n');
for (const f of findings) console.log('  ' + f);
process.exit(1);
