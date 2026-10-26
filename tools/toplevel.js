#!/usr/bin/env node
/**
 * tools/toplevel.js — 顶层成员闸门（判失败）
 *
 * 为什么要有这一道：
 *   2026-10-26 这一轮精简里，我两次把「本该在类型内部的成员」挪到了文件顶层
 *   （AccessibilityKit 的 notConnected/rowSentence、LockStats 的 orderKey/group）。
 *   括号是平衡的 —— `swiftcheck` 全绿 —— 但 Swift 编译器会报
 *   「Static properties may only be declared on a type」。
 *   这类错误只有真编译才抓得到，而本机没有 Xcode，于是连着四次 CI 红。
 *
 *   括号平衡 ≠ 结构合理。这一道补上「成员必须在类型内部」的那一半。
 *
 * 判据：
 *   文件顶层（花括号深度 0）出现带缩进的成员声明 ⇒ 红。
 *   顶层合法的东西只有：import / 类型声明 / extension / 全局 let-var-func（顶格）/ 注释 / 指令。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 顶层允许的关键字前缀（这些出现在深度 0 且顶格是正常的）
const TOP_OK = /^(import|@testable|@_exported|#if|#else|#endif|#warning|#error)\b/;

const problems = [];

for (const file of walk(path.join(ROOT, 'App'))) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  let depth = 0;
  let inBlockComment = false;

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    let line = raw;

    // 粗略剥掉块注释（不追求完美，只避免误判）
    if (inBlockComment) {
      const end = line.indexOf('*/');
      if (end < 0) { continue; }
      line = ' '.repeat(end + 2) + line.slice(end + 2);
      inBlockComment = false;
    }
    while (true) {
      const s = line.indexOf('/*');
      if (s < 0) break;
      const e = line.indexOf('*/', s + 2);
      if (e < 0) { line = line.slice(0, s); inBlockComment = true; break; }
      line = line.slice(0, s) + ' '.repeat(e + 2 - s) + line.slice(e + 2);
    }
    // 剥行注释（注意别把字符串里的 // 当注释 —— 够用了，误判方向是"少报"而非"多报"）
    const slash = line.indexOf('//');
    if (slash >= 0) line = line.slice(0, slash);

    const trimmed = line.trim();

    if (depth === 0 && trimmed) {
      const indented = /^\s{2,}/.test(line);
      // 顶格声明一律放行（全局函数/常量是合法的）
      if (indented && !TOP_OK.test(trimmed)) {
        // 类型声明的续行（如 enum 的 attribute）也可能缩进，但它不会以成员关键字开头
        if (/^(static |private |fileprivate |internal |public |nonisolated |override |mutating |lazy |weak |final |func |var |let |case )/.test(trimmed)) {
          problems.push({ rel, line: i + 1, text: trimmed.slice(0, 90) });
        }
      }
    }

    for (const ch of line) {
      if (ch === '{') depth++;
      else if (ch === '}') depth--;
    }
  }
}

if (problems.length === 0) {
  console.log('顶层成员闸门 (成员必须在类型内部) ✓ 零命中');
  process.exit(0);
}

console.error('✗ 顶层出现带缩进的成员声明 —— Swift 会报「Static properties may only be declared on a type」');
console.error('  这多半是删/插代码时把某个类型的闭合 } 弄丢了，或成员被挪到了类型外面。\n');
for (const p of problems) {
  console.error(`  ${p.rel}:${p.line}  ${p.text}`);
}
console.error(`\n共 ${problems.length} 处。括号平衡抓不到这类问题（swiftcheck 会是绿的），本闸门专门补这一半。`);
process.exit(1);
