#!/usr/bin/env node
// 空块闸门 —— 判失败。
//
// 2026-10-27 新增（B 线审核 §1.1）：本工程 13 轮功能精简留下了大量「删了内容但括号还在」的空壳。
// 这类缺陷 38 道现有闸门**结构上抓不到**（它们查形状、查跨语言差分、查文档一致性，
// 没有一道查「这个 if 块里还有没有东西」）。
//
// 判据（字符串感知，跳过注释与字符串字面量）：
//   ① 空 if / else / for / while / switch：本行开 `{`，下一个非空非注释行立即是 `}`
//   ② 空 case：`case xxx:` 之后到下一个 case/default/} 之间没有可执行语句
//   ③ 空 catch
//   ④ 空 Section / Group / VStack / HStack（SwiftUI 特有，删功能后常见）
//
// 允许的例外（写进 ALLOW）：
//   · 函数体只有注释 —— 那是「记录删除原因」，有价值（如 revokeSessionGrants）
//   · `default: break` 这类合法空分支
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

// 已知的合法空块（人工审核过，不是缺陷）
const ALLOW = [
  // 访客通道删除后，这个函数的语义已并入 handleScenePhase；保留空壳只为不改调用链
  { file: 'App/LockKeeperApp.swift', pattern: /revokeSessionGrants/, why: '访客撤权已并入 handleScenePhase' },
  // Swift 协议要求实现但本类型无内容（如空 @ViewBuilder 分支）
  { file: 'App/Core/DesignSystem.swift', pattern: /var body: some View \{\s*EmptyView\(\)/, why: 'EmptyView 是合法的' },
];

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 把一行拆成「代码部分」（去掉字符串字面量与行尾注释）
function codeOf(line) {
  let out = '';
  let inStr = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    const prev = i > 0 ? line[i - 1] : '';
    if (ch === '"' && prev !== '\\') { inStr = !inStr; out += ' '; continue; }
    if (!inStr) out += ch;
  }
  const ci = out.indexOf('//');
  return ci >= 0 ? out.slice(0, ci) : out;
}

function isBlankOrComment(line) {
  const t = line.trim();
  return t === '' || t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*');
}

const files = walk(path.join(ROOT, 'App')).concat(walk(path.join(ROOT, 'Tests')));
const problems = [];

for (const file of files) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const L = fs.readFileSync(file, 'utf8').split(/\r?\n/);

  for (let i = 0; i < L.length; i++) {
    const code = codeOf(L[i]);
    const t = code.trim();

    // ① 空 if/else/for/while/switch
    if (/^(if|else if|else|for|while|switch|guard)\b.*\{\s*$/.test(t) || /^else\s*\{\s*$/.test(t)) {
      let j = i + 1;
      while (j < L.length && isBlankOrComment(L[j])) j++;
      if (j < L.length && codeOf(L[j]).trim() === '}') {
        // 检查是否在 ALLOW 里
        const allowed = ALLOW.some(a => rel === a.file && a.pattern.test(L[i]));
        if (!allowed) {
          // 函数体只有注释的情况不算（那是记录删除原因）
          const hasComment = L.slice(i + 1, j).some(x => x.trim().startsWith('//'));
          if (!hasComment) problems.push({ rel, line: i + 1, kind: '空块', text: t.slice(0, 70) });
        }
      }
    }

    // ② 空 case
    // 只认「纯 case 标签」：整行以 : 结尾且不含 return/赋值（排除三目表达式被误切）
    const rawT = L[i].trim();
    if (/^(case .*|default):\s*$/.test(t) && !/return|=/.test(rawT)) {
      let j = i + 1;
      while (j < L.length && isBlankOrComment(L[j])) j++;
      if (j < L.length) {
        const next = codeOf(L[j]).trim();
        if (/^(case |default:|\})/.test(next)) {
          // default: break 是合法的
          if (!(t.startsWith('default') && next === 'break')) {
            problems.push({ rel, line: i + 1, kind: '空 case', text: t.slice(0, 70) });
          }
        }
      }
    }

    // ③ 空 catch
    if (/catch(\s*\([^)]*\))?\s*\{\s*$/.test(t)) {
      let j = i + 1;
      while (j < L.length && isBlankOrComment(L[j])) j++;
      if (j < L.length && codeOf(L[j]).trim() === '}') {
        const hasComment = L.slice(i + 1, j).some(x => x.trim().startsWith('//'));
        if (!hasComment) problems.push({ rel, line: i + 1, kind: '空 catch', text: t.slice(0, 70) });
      }
    }

    // ④ 空 Section / Group / VStack / HStack
    if (/^(Section|Group|VStack|HStack|List|Form|ZStack)(\([^)]*\))?\s*\{\s*$/.test(t)) {
      let j = i + 1;
      while (j < L.length && isBlankOrComment(L[j])) j++;
      if (j < L.length && codeOf(L[j]).trim() === '}') {
        const hasComment = L.slice(i + 1, j).some(x => x.trim().startsWith('//'));
        if (!hasComment) problems.push({ rel, line: i + 1, kind: '空容器', text: t.slice(0, 70) });
      }
    }
  }
}

if (problems.length === 0) {
  console.log('空块闸门 ✓ 零命中');
  process.exit(0);
}

console.log(`✗ 空块 ${problems.length} 处 —— 这些块里没有任何可执行语句：\n`);
for (const p of problems) {
  console.log(`  ${p.rel}:${p.line}  [${p.kind}]  ${p.text}`);
}
console.log('\n修法：删掉整个空块，或补回原语义（若原语义已删，至少留一句注释说明为什么留空）。');
process.exit(1);
