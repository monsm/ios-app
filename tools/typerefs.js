#!/usr/bin/env node
// tools/typerefs.js —— 检查 Type.member 的成员归属
//
// 为什么需要它：
//   本会话有两次 CI 失败都是同一个原因 —— 把成员挂到了错的类型下：
//     · RecordSearch.note(...)      实际在 RecordOverlay
//     · RecordSearch.NamedView      实际是顶层 NamedView
//     · RecordSearch.QueryFilters() 实际是顶层 QueryFilters
//   本地 23 道闸门一道都抓不到：它们只查括号、形状、命名，没有类型系统。
//   而 CI 一次要等好几分钟。
//
// 做法：把每个类型的成员名收集起来（含 extension 合并），
//   再扫全仓的 X.member 引用，检查 member 是否真在该类型里。
//
// 局限：只看「名字在不在」，不看可见性/重载/泛型/协议合成成员。
//   所以报出来要人工确认，但**漏报比误报少**。
//
// 诊断工具。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
function allSwift() {
  const out = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (e.name[0] !== '.') walk(p); }
      else if (e.name.endsWith('.swift')) out.push(p);
    }
  };
  walk(path.join(ROOT, 'App'));
  return out;
}

const MEMBER_RE = /^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|internal\s+|private\s+|fileprivate\s+|static\s+|class\s+|final\s+|override\s+|nonisolated\s+|mutating\s+|lazy\s+)*(func|var|let|case|init|subscript|typealias|struct|enum|class)\s+([A-Za-z_]\w*)/;

// typeName -> Set(memberNames)
const members = new Map();
const typeNames = new Set();

for (const f of allSwift()) {
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split('\n');
  // 逐行维护花括号深度与「当前类型栈」
  let depth = 0;
  let stack = [];   // [{name, depth}]
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const code = line.replace(/\/\/.*$/, '');

    // 类型声明（顶层或嵌套）
    // ⚠ 第一版漏了修饰符：`final class LinkSense {` 匹配不上，
    //   于是 LinkSense 的成员一个都没收集到，它的所有引用全成了假阳性。
    const tm = code.match(/^\s*(?:(?:public|internal|private|fileprivate|final|@\w+(?:\([^)]*\))?)\s+)*(enum|struct|class|actor|extension)\s+([A-Za-z_]\w*)\s*(?::[^{]*)?\{/);
    if (tm) {
      const name = tm[2];
      typeNames.add(name);
      if (!members.has(name)) members.set(name, new Set());
      stack.push({ name, depth });
    } else if (stack.length) {
      // 成员声明：必须正好在当前类型体内一层
      const mm = code.match(MEMBER_RE);
      if (mm && stack.length) {
        const cur = stack[stack.length - 1];
        if (depth === cur.depth + 1) members.get(cur.name).add(mm[2]);
      }
    }

    for (const ch of code) {
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        while (stack.length && stack[stack.length - 1].depth >= depth) stack.pop();
      }
    }
  }
}

// 扫 X.member 引用
const problems = [];
for (const f of allSwift()) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  lines.forEach((line, i) => {
    if (/^\s*\/\//.test(line)) return;
    // 成员名允许大写开头：内嵌类型（如 CredentialOrg.CredBinEntry）也是成员。
    // 只匹配小写会漏掉这一类 —— CI 就是这么报出 'CredBinEntry' is not a member type 的。
    for (const m of line.matchAll(/\b([A-Z][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)/g)) {
      const [_, type, member] = m;
      if (type === 'Self') continue;
      if (!typeNames.has(type)) continue;        // 不是本仓类型（Foundation / SwiftUI）
      const set = members.get(type);
      if (!set) continue;
      if (set.has(member)) continue;
      // 关键降噪：只在 member 确实声明在本仓**另一个**类型里时才报。
      // 这样 Color.black / UIApplication.shared 这类系统成员不会进列表，
      // 而 RecordSearch.note（真实属于 RecordOverlay）会被抓住。
      const ownedBy = [];
      for (const [tn, ms] of members) if (ms.has(member)) ownedBy.push(tn);
      if (!ownedBy.length) {
        // 没有哪个类型把 member 声明成自己的成员 —— 但如果 member 本身
        // 就是一个**已知类型**，说明有人把顶层类型当成了嵌套类型：
        //   CredentialOrg.CredBinEntry   ← CredBinEntry 其实是顶层
        // 这一条是 CI 报出来的，而工具第一版因为降噪过滤把它跳过了。
        if (typeNames.has(member)) ownedBy.push('(顶层类型 ' + member + ')');
        else continue;
      }
      // 常见非成员访问：init、枚举 case 的 rawValue 等由编译器合成
      if (['init', 'self', 'Type', 'self'].includes(member)) continue;
      problems.push({ file: rel, line: i + 1, type, member, owners: ownedBy, text: line.trim().slice(0, 90) });
    }
  });
}

console.log('扫描 ' + typeNames.size + ' 个本仓类型，发现 ' + problems.length + ' 处可疑成员引用');
console.log('-'.repeat(104));
const seen = new Set();
for (const p of problems) {
  const k = p.type + '.' + p.member;
  if (seen.has(k)) continue;
  seen.add(k);
  console.log((p.type + '.' + p.member).padEnd(40) + p.file + ':' + p.line);
  console.log('    实际属于: ' + p.owners.join(', '));
  console.log('    ' + p.text);
}
if (!problems.length) console.log('OK 没有发现挂错类型的成员引用');
