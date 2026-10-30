#!/usr/bin/env node
// add_ci_step —— **安全地**往 .github/workflows/ios.yml 插一个 step。
//
// 2026-10-30 新增（第 109 轮）：本轮我三次用「找 run: 行然后插在它后面」的脚本插 step，
// 三次都把 `run: |` 块头和它的缩进体拆开了 —— GitHub 在解析阶段就 0 job，
// 而本地 56 道闸门全绿（它们不读 workflow）。
//
// 正确做法（本脚本实现）：
//   ① 找到锚点 step 的 `- name:` 行；
//   ② 从它往下扫，**跳过整个 step**（含 run: | 的缩进体、多行 with:/env: 等），
//      直到遇到下一条 `      - name:` 或 job 边界；
//   ③ 插在「下一条 step 之前」，而不是「锚点 run: 之后」。
//
// 用法：
//   node tools/add_ci_step.js <锚点step名子串> "<新step名>" "<run 命令>"
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WF = path.join(ROOT, '.github/workflows/ios.yml');

const [anchor, newName, newRun] = process.argv.slice(2);
if (!anchor || !newName || !newRun) {
  console.log('用法: node tools/add_ci_step.js <锚点step名子串> "<新step名>" "<run 命令>"');
  process.exit(2);
}

const raw = fs.readFileSync(WF, 'utf8');
const eol = raw.includes('\r\n') ? '\r\n' : '\n';
const L = raw.replace(/\r\n/g, '\n').split('\n');

const a = L.findIndex(l => /^ {6}- name:/.test(l) && l.includes(anchor));
if (a < 0) { console.log('✗ 未找到锚点 step: ' + anchor); process.exit(1); }

// 从锚点往下，找下一条同级 step（或 job 边界 `  xxx:`）
let z = -1;
for (let k = a + 1; k < L.length; k++) {
  if (/^ {6}- name:/.test(L[k])) { z = k; break; }
  if (/^ {2}[A-Za-z0-9_-]+:\s*$/.test(L[k])) { z = k; break; }
}
if (z < 0) z = L.length;

const step = [
  `      - name: '${newName}'`,
  `        run: ${newRun}`,
  '',
];

L.splice(z, 0, ...step);
fs.writeFileSync(WF, L.join('\n').replace(/\n/g, eol), 'utf8');
console.log(`OK 已插在「${anchor}」整个 step 之后（第 ${z + 1} 行前）`);
console.log('⚠ 插完**必须**跑一次 `node tools/workflowcheck.js` —— 它自己就是被插进来的。');
