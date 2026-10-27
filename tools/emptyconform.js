#!/usr/bin/env node
// 空协议实现闸门 —— 判失败。
//
// 2026-10-27 新增（B 线审核 §2.7）：`HeroSurface` 被删成空 conformer 那次是编译级缺陷 ——
// `struct HeroSurface: ShapeStyle { }` 缺少协议要求的 `resolve(in:)`，三个在役消费点拿不到样式。
// 38 道现有闸门没有一道查「声明 conform 了协议，但协议要求的方法不在实现里」。
//
// 判据：
//   ① `struct X: SomeProtocol { }` —— 体完全为空，但协议有 @required 成员
//   ② `struct X: SomeProtocol` 体非空，但缺该协议的关键方法
//
// 协议成员表：只收本仓实际用到、且能静态确定签名的（Apple 框架协议太多，不能穷举）。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

// 协议 → 必须实现的方法（正则）
const PROTOCOLS = {
  ShapeStyle: [/func\s+resolve\s*\(\s*in\b/],
  View: [/var\s+body\s*:\s*some\s+View/, /func\s+body\s*\(/],
  ViewModifier: [/func\s+body\s*\(\s*(?:content\s*:\s*)?Content/],
  Animatable: [/var\s+animatableData/],
  Codable: [],          // 合成实现合法
  Equatable: [],
  Hashable: [],
  // Identifiable: 只要有 id 成员即可 —— let id: String 与 ar id: X { } 都合法
  Identifiable: [/(?:let|var)\s+id\b/],
  Comparable: [/static\s+func\s+<\s*\(/],
  Error: [],
  Sendable: [],
  CustomStringConvertible: [/var\s+description\b/],
  ButtonStyle: [/func\s+makeBody\s*\(/],
  ToggleStyle: [/func\s+makeBody\s*\(/],
  LabelStyle: [/func\s+makeBody\s*\(/],
  ProgressViewStyle: [/func\s+makeBody\s*\(/],
  TableRowContent: [/var\s+body\b/],
  Layout: [/func\s+sizeThatFits\s*\(/, /func\s+placeSubviews\s*\(/],
};

// 已知合法（人工审核过）
const ALLOW = [
  // 空 conformer 但靠 extension 补实现的情况，写在这里
];

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

function codeOf(line) {
  let out = '', inStr = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i], prev = i > 0 ? line[i - 1] : '';
    if (ch === '"' && prev !== '\\') { inStr = !inStr; out += ' '; continue; }
    if (!inStr) out += ch;
  }
  const ci = out.indexOf('//');
  return ci >= 0 ? out.slice(0, ci) : out;
}

const files = walk(path.join(ROOT, 'App'));
const all = new Map();
for (const f of files) all.set(f, fs.readFileSync(f, 'utf8').split(/\r?\n/));

const problems = [];

for (const [file, L] of all) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  for (let i = 0; i < L.length; i++) {
    const code = codeOf(L[i]);
    // 匹配 `struct/class/enum X: Proto` 或 `, Proto`
    const m = /(?:struct|class|enum|extension)\s+(\w+)\s*(?::|,)\s*([A-Za-z0-9_,\s.]+)/.exec(code);
    if (!m) continue;
    const typeName = m[1];
    const protos = m[2].split(',').map(s => s.trim()).filter(Boolean);
    if (ALLOW.some(a => a === typeName)) continue;

    // 找体范围
    let d = 0, start = -1, end = -1;
    for (let k = i; k < L.length; k++) {
      const c = codeOf(L[k]);
      for (const ch of c) {
        if (ch === '{') { if (d === 0 && start < 0) start = k; d++; }
        else if (ch === '}') { d--; if (d === 0 && start >= 0) { end = k; break; } }
      }
      if (end >= 0) break;
    }
    if (start < 0 || end < 0) continue;

    const body = L.slice(start, end + 1).map(codeOf).join('\n');

    for (const p of protos) {
      const reqs = PROTOCOLS[p];
      if (!reqs || reqs.length === 0) continue;
      // 该协议要求的每个方法都要在体内出现
      const missing = reqs.filter(r => !r.test(body));
      // 也可能是 extension 补的：全仓搜 `extension TypeName`
      const extBody = [];
      for (const [, LL] of all) {
        for (let k = 0; k < LL.length; k++) {
          if (new RegExp('extension\\s+' + typeName + '\\b').test(LL[k])) {
            let dd = 0, ss = -1, ee = -1;
            for (let q = k; q < LL.length; q++) {
              for (const ch of codeOf(LL[q])) {
                if (ch === '{') { if (dd === 0 && ss < 0) ss = q; dd++; }
                else if (ch === '}') { dd--; if (dd === 0 && ss >= 0) { ee = q; break; } }
              }
              if (ee >= 0) break;
            }
            if (ss >= 0 && ee >= 0) extBody.push(LL.slice(ss, ee + 1).map(codeOf).join('\n'));
          }
        }
      }
      const extTxt = extBody.join('\n');
      const stillMissing = missing.filter(r => !r.test(extTxt));
      if (stillMissing.length === reqs.length) {
        problems.push({ rel, line: i + 1, type: typeName, proto: p, missing: stillMissing.length });
      }
    }
  }
}

if (problems.length === 0) {
  console.log('空协议实现闸门 ✓ 零命中');
  process.exit(0);
}

console.log(`✗ 声明 conform 了协议但缺实现 ${problems.length} 处：\n`);
for (const p of problems) {
  console.log(`  ${p.rel}:${p.line}  ${p.type} : ${p.proto}  —— 缺 ${p.missing} 个必需方法`);
}
console.log('\n修法：补回协议要求的方法，或去掉 conform（若该协议已无消费点）。');
process.exit(1);
