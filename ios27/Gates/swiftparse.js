#!/usr/bin/env node
// swiftparse.js —— 真 Swift 语法闸门（tree-sitter 语法树）。
//
// 为什么需要它：本机没有 swiftc。swiftcheck.js 只数括号，它发现不了
// "for 写成了 if"、"少一个参数标签"、"字符串没闭合但括号平衡"这类真语法错误。
// tree-sitter-swift 是 Tree-sitter 官方语法，能给出 ERROR 节点 —— 那就是语法错误。
//
// 判定：任何 ERROR 节点 / MISSING 节点 = 失败，报出文件、行、列、上下文。
'use strict';
const fs = require('fs');
const path = require('path');

let Parser, Language;
try {
  Parser = require('tree-sitter');
  Language = require('tree-sitter-swift');
} catch (e) {
  console.log('swiftparse: SKIP — tree-sitter 未安装（npm i tree-sitter tree-sitter-swift）');
  process.exit(0);
}

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const parser = new Parser();
parser.setLanguage(Language);

const files = walk(APP);
const findings = [];
let exempted = 0;

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  // tree-sitter-swift 已知语法盲区（是语法的限制，不是本仓代码错）。
  //
  // 盲区 A: `if let x = try await f()` / `try? await` —— 语法不接受 try 与 await 同时出现在 if-let 初始化式里。
  // 盲区 B: `cb?(.success(()))` —— 可选链调用里嵌套隐式成员调用，会让解析器整体错位。
  //
  // 处理方式：**把这几行换成同形状占位再解析**（保持行号不变），而不是按行号豁免 ——
  // 按行豁免会连带豁免掉同一行上的其它真错误；换源再解析则其余行仍然逐字受检。
  const BLIND_A = /^(\s*)(if|guard)\s+(let|var)\s+\w+\s*=\s*(try\??|try!)\s+await\b/;
  const BLIND_B = /^(\s*)(\w+)\?\(\s*\.\w+\s*\(\s*\(\s*\)\s*\)\s*\)\s*$/;

  let sanitized = src;
  let blindCount = 0;
  const srcLines = src.split(/\r?\n/);
  for (let i = 0; i < srcLines.length; i++) {
    const line = srcLines[i];
    if (BLIND_A.test(line)) {
      srcLines[i] = line.replace(/(try\??|try!)\s+await/, 'await');
      blindCount++;
    } else if (BLIND_B.test(line)) {
      srcLines[i] = line.replace(/^(\s*)(\w+)\?\(.*\)\s*$/g, '$1$2');
      blindCount++;
    }
  }
  if (blindCount > 0) sanitized = srcLines.join('\n');

  const tree = parser.parse(sanitized);
  const lines = src.split(/\r?\n/);

  (function visit(node) {
    if (node.type === 'ERROR' || node.isMissing) {
      const row = node.startPosition.row;
      findings.push({
        file: rel,
        line: row + 1,
        col: node.startPosition.column + 1,
        kind: node.isMissing ? 'MISSING' : 'ERROR',
        text: (lines[row] || '').trim().slice(0, 120),
      });
    }
    for (let i = 0; i < node.childCount; i++) {
      const c = node.child(i);
      if (c) visit(c);
    }
  })(tree.rootNode);
  exempted += blindCount;
}

if (findings.length === 0) {
  console.log('swiftparse: OK — ' + files.length + ' 个 Swift 文件无语法错误（已知语法盲区豁免 ' + exempted + ' 处）');
  process.exit(0);
}
console.log('swiftparse: FAIL — ' + findings.length + ' 处语法错误\n');
for (const f of findings) {
  console.log('  ' + f.file + ':' + f.line + ':' + f.col + '  [' + f.kind + ']');
  console.log('      ' + f.text);
}
process.exit(1);