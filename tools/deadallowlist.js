#!/usr/bin/env node
// 死白名单闸门 —— 判失败。
//
// 2026-10-27 新增（B 线审核 §4.1）：13 轮精简后，多个闸门的白名单里还留着**已删文件/符号**的条目。
// 它们不会让闸门出错，但会让「白名单 = 已审核例外」这个约定失效 ——
// 后人看到一条指向不存在文件的豁免，无从判断它当初为什么存在。
//
// 判据：扫 tools/*.js 里的白名单数组，取每条里的文件路径/符号名，验证它还在不在。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = path.join(ROOT, 'tools');

// 收集 App 下所有 swift 文件与其文本
const swift = new Map();
function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.swift')) swift.set(path.relative(ROOT, p).replace(/\\/g, '/'), fs.readFileSync(p, 'utf8'));
  }
}
walk(path.join(ROOT, 'App'));

const problems = [];

for (const f of fs.readdirSync(TOOLS).filter(x => x.endsWith('.js'))) {
  if (f === 'deadallowlist.js') continue;
  const txt = fs.readFileSync(path.join(TOOLS, f), 'utf8');
  const L = txt.split(/\r?\n/);

  L.forEach((line, i) => {
    // 只扫注释里出现 `App/...swift:NNN` 或 `App/...swift` 的白名单式引用
    const m = /App\/[A-Za-z0-9_/]+\.swift(?::(\d+))?/g;
    let mm;
    while ((mm = m.exec(line)) !== null) {
      const rel = mm[0].split(':')[0];
      if (!swift.has(rel)) {
        problems.push({ file: `tools/${f}`, line: i + 1, ref: rel, why: '文件已删除' });
        continue;
      }
      if (mm[1]) {
        const n = parseInt(mm[1], 10);
        const total = swift.get(rel).split(/\r?\n/).length;
        if (n > total) problems.push({ file: `tools/${f}`, line: i + 1, ref: mm[0], why: `行号越界（文件仅 ${total} 行）` });
      }
    }
  });
}

if (problems.length === 0) {
  console.log('死白名单闸门 ✓ 零命中');
  process.exit(0);
}

console.log(`✗ 白名单/注释引用了已失效的代码位置 ${problems.length} 处：\n`);
for (const p of problems) {
  console.log(`  ${p.file}:${p.line}  → ${p.ref}  （${p.why}）`);
}
console.log('\n修法：删掉该白名单条目，或把它指向现存的文件/行。');
process.exit(1);
