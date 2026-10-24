#!/usr/bin/env node
// tools/apifield.js —— 字段级 API 检查（第 25 轮新增，**顾问级，不判失败**）
//
// 由来：2026-10-24 逐页对齐期间连续 5 轮触发同类编译错误：
//   CachedLog.at（无此字段）· KeyRow.mac（mac 是视图属性不是 KeyRow 成员）
//   DB.status（实为 readStatus）· IconOption 比较用错变量名
// 这几种都是**「我以为某结构有某字段」**——apicheck 查不出（只查类型级成员），
// 只有编译器能抓。本工具把它提前到本地**提示**。
//
// 为什么只做顾问级、不做闸门：
//   同一变量名（rec / log / row）在不同文件指向不同结构，静态名字匹配必然误报。
//   实测第一版报 59 处，逐条读后**全部是误报**（rec 在 StatsKit 是局部聚合结构、
//   log.append 是数组方法）。判失败会逼人加豁免注释，最后没人看。
//
// 因此：只覆盖**能确定来源**的一种情形 ——
//   for log in DB.readLogs(...) { log.<field> }   ← 一定是 CachedLog
// 其余一概不猜。

'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function swiftFiles(dir) {
  const out = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.swift')) out.push(p);
    }
  })(dir);
  return out;
}

// DB.readLogs 的返回类型固定是 [CachedLog]；取它的字段表
function fieldsOf(structName) {
  for (const f of swiftFiles(APP)) {
    const t = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
    const i = t.indexOf('struct ' + structName);
    if (i < 0) continue;
    let depth = 0, end = i;
    for (let j = t.indexOf('{', i); j < t.length; j++) {
      if (t[j] === '{') depth++;
      else if (t[j] === '}') { depth--; if (depth === 0) { end = j; break; } }
    }
    const set = new Set();
    for (const m of t.slice(i, end).matchAll(/(?:var|let)\s+(\w+)\s*[:=]/g)) set.add(m[1]);
    return set;
  }
  return null;
}

const cachedLogFields = fieldsOf('CachedLog');
if (!cachedLogFields) {
  console.log('字段级 API 检查 ⊘ 未找到 CachedLog 声明（结构改名了？）');
  process.exit(0);
}

let issues = [];
for (const f of swiftFiles(APP)) {
  const rel = f.replace(ROOT + path.sep, '');
  const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
  // 找 for log in DB.readLogs(...) 的作用域，只在该作用域内查 log.<field>
  let inScope = 0;
  lines.forEach((line, idx) => {
    if (/^\s*\/\//.test(line)) return;
    if (/for\s+log\s+in\s+DB\.readLogs\s*\(/.test(line)) inScope = 12;  // 粗粒度：后 12 行内
    if (inScope > 0) {
      for (const m of line.matchAll(/\blog\.(\w+)/g)) {
        const field = m[1];
        if (!cachedLogFields.has(field)) {
          issues.push(rel + ':' + (idx + 1) + '  log.' + field + ' —— CachedLog 无此字段');
        }
      }
      inScope--;
    }
  });
}

if (issues.length === 0) {
  console.log('字段级 API 检查 ✓ CachedLog 访问（' + [...cachedLogFields].join('/') + '）全部存在');
} else {
  console.log('字段级 API 可疑 ' + issues.length + ' 处（顾问级）：');
  issues.forEach(x => console.log('  · ' + x));
}
process.exit(0);
