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
// Tests 目录整体纳入 (旧实现硬编码两个文件名 → 新增测试文件根本不进闸门)
  // 2026-10-30 修正（第 110 轮）：原注释写「Widget 目录 (927 哑按钮扩展) 同样必须进来」，但该扩展已随 `3d28ff7`（波2b「删桌面小组件」）**整族删除**（`project.yml` 现在只有 `OfflineLock` 与 `OfflineLockTests`）。数组里保留 `Widget` 无害（`existsSync` 会跳过），但注释不该让人去找一个不存在的目录。
(function walkMore(dirs) {
  for (const d of dirs) {
    if (!fs.existsSync(d)) continue;
    (function walk(x) {
      for (const e of fs.readdirSync(x, { withFileTypes: true })) {
        const f = x + '/' + e.name;
        if (e.isDirectory()) walk(f);
        else if (f.endsWith('.swift')) files.push(f);
      }
    })(d);
  }
})(['Tests', 'Widget']);
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
