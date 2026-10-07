// Swift 文件括号/字符串平衡粗检 (编译前静态闸门) — node tools/swiftcheck.js
'use strict';
const fs = require('fs');
const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = d + '/' + e.name;
    if (e.isDirectory()) walk(f);
    else if (f.endsWith('.swift')) files.push(f);
  }
})('App');
files.push('Tests/GoldenDiffTests.swift');
let fail = 0;
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const depth = { curly: 0, paren: 0, bracket: 0 };
  let inStr = false, inLine = false, inBlock = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    const two = src.substr(i, 2);
    if (inLine) { if (c === '\n') inLine = false; continue; }
    if (inBlock) { if (two === '*/') { inBlock = false; i++; } continue; }
    if (inStr) {
      if (c === '\\') { i++; continue; }
      if (c === '"') inStr = false;
      continue;
    }
    if (two === '//') { inLine = true; i++; continue; }
    if (two === '/*') { inBlock = true; i++; continue; }
    if (c === '"') { inStr = true; continue; }
    if (c === '{') depth.curly++;
    else if (c === '}') depth.curly--;
    else if (c === '(') depth.paren++;
    else if (c === ')') depth.paren--;
    else if (c === '[') depth.bracket++;
    else if (c === ']') depth.bracket--;
    if (depth.curly < 0 || depth.paren < 0 || depth.bracket < 0) { console.log('NEGATIVE at', f, 'offset', i); fail++; break; }
  }
  if (depth.curly !== 0 || depth.paren !== 0 || depth.bracket !== 0) {
    console.log('UNBALANCED', f, JSON.stringify(depth));
    fail++;
  }
}
console.log(fail ? fail + ' 个文件不平衡' : files.length + ' 个 Swift 文件括号平衡 ✓');
process.exit(fail ? 1 : 0);
