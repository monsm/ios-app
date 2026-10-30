#!/usr/bin/env node
// workflowcheck —— GitHub Actions 工作流的**结构**校验（判失败）。
//
// 2026-10-30 新增（第 109 轮）：本轮我用脚本往 `ios.yml` 里插 step 时，
// 把新 step 插到了 `run: |` 块头和它的缩进体**之间** ——
//   run: |
// - name: 新 step            ← 插在这
//   run: node tools/xx.js
//   node tools/destmap.js    ← 原块体的第一行，变成孤儿
// 结果 GitHub 在**解析阶段**就失败：整个 workflow 0 个 job，
// 而本地 56 道闸门全绿（`allgates` 不校验 workflow）。
//
// 本闸门补上这个缺口。判据（不需要 YAML 库，按缩进结构判）：
//   W1 `run: |` / `run: >` 块标量后面必须至少有一行更深缩进的内容
//   W2 不允许「`- name:` 出现在比上一条 `run: |` 更浅或相等的缩进」——
//      即块体被新 step 截断
//   W3 step 名里不得出现**未加引号**的裸冒号（本仓工作流自检的既有规则，这里一并兜住）
//   W4 step 名不得重复（同一 job 内重名会让日志难以定位）
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WF = path.join(ROOT, '.github/workflows/ios.yml');

if (!fs.existsSync(WF)) {
  console.log('（无 .github/workflows/ios.yml，跳过）');
  process.exit(0);
}

const L = fs.readFileSync(WF, 'utf8').replace(/\r\n/g, '\n').split('\n');
const problems = [];
const indentOf = (s) => s.length - s.replace(/^\s+/, '').length;

for (let i = 0; i < L.length; i++) {
  const line = L[i];
  const t = line.trim();

  // W1/W2：块标量必须有体，且体不能被新 step 截断
  if (/^run:\s*[|>][-+]?\s*$/.test(t)) {
    const base = indentOf(line);
    let bodyLines = 0;
    for (let k = i + 1; k < L.length; k++) {
      const s = L[k];
      if (s.trim() === '') continue;
      if (indentOf(s) <= base) break;
      bodyLines++;
    }
    if (bodyLines === 0) {
      problems.push({ line: i + 1, msg: '`run: |` 块标量没有任何缩进体（下一条同级语句直接跟在后面）' });
    }
  }

  // W3：step 名裸冒号
  const nm = /^-\s*name:\s*(.*)$/.exec(t);
  if (nm) {
    const v = nm[1].trim();
    const quoted = (v.startsWith("'") && v.endsWith("'")) || (v.startsWith('"') && v.endsWith('"'));
    if (!quoted && /:\s/.test(v)) {
      problems.push({ line: i + 1, msg: 'step 名含未加引号的冒号（严格 YAML 解析器会拒收）: ' + v.slice(0, 60) });
    }
  }
}

// W4：step 名重复 —— **必须按 job 分组**（不同 job 里各有 Checkout 是正常的）
const jobOf = (idx) => {
  for (let k = idx; k >= 0; k--) {
    const m = /^ {2}([A-Za-z0-9_-]+):\s*$/.exec(L[k]);
    if (m) return m[1];
  }
  return '?';
};
const names = new Map();   // "job\u0000name" -> [line]
L.forEach((l, i) => {
  const m = /^ {6}-\s*name:\s*(.+)$/.exec(l);
  if (!m) return;
  const key = jobOf(i) + '\u0000' + m[1].trim();
  if (!names.has(key)) names.set(key, []);
  names.get(key).push(i + 1);
});
for (const [key, ls] of names) {
  if (ls.length > 1) {
    const [job, n] = key.split('\u0000');
    problems.push({ line: ls[1], msg: `job「${job}」内 step 名重复（${ls.join(', ')}）: ${n.slice(0, 50)}` });
  }
}

if (problems.length) {
  console.log(`✗ 工作流结构有问题 ${problems.length} 处：`);
  for (const p of problems) console.log(`  :${p.line}  ${p.msg}`);
  console.log('\n后果：GitHub 在**解析阶段**就失败 —— 整个 workflow 0 个 job，而本地闸门全绿。');
  process.exit(1);
}
console.log(`✓ 工作流结构正常（${L.length} 行，${names.size} 个 step 名唯一）`);
