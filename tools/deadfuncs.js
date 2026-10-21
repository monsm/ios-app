#!/usr/bin/env node
// tools/deadfuncs.js —— 找出「声明了但从不被调用」的函数
//
// 与 statewrites.js 同源：都是「假机制」家族。
// 这类代码不崩溃、不报错，只是从不执行 —— 读代码时看起来完全正常。
// 实例：CredentialOrg.setArchived 零调用，而 isArchived 在 15 处被当过滤条件用，
//       于是那 15 处过滤全是空操作。
//
// 口径（保守，只报高置信度的）：
//   · 只看 App/Core 与 App/Services 下的 static func / 普通 func
//   · 跳过 @objc / dynamic / override / protocol 要求的方法（框架或运行时调用）
//   · 跳过 body / makeBody / init / deinit
//   · 调用点 = 全仓任意位置出现「funcName(」或「.funcName」
//   · 声明行本身不计入
//
// 诊断工具，不参与 CI 判定。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
function allSwift(dir) {
  const out = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (e.name[0] !== '.') walk(p); }
      else if (e.name.endsWith('.swift')) out.push(p);
    }
  };
  walk(dir);
  return out;
}

const appFiles = allSwift(path.join(ROOT, 'App'));
const allSources = appFiles.map(f => ({
  f,
  rel: path.relative(ROOT, f).split(path.sep).join('/'),
  text: fs.readFileSync(f, 'utf8'),
}));

const SKIP_NAMES = new Set(['body', 'makeBody', 'init', 'deinit']);
const SKIP_PREFIX = ['_'];

const decls = [];
for (const { f, text } of allSources) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  if (!(rel.includes('App/Core/') || rel.includes('App/Services/'))) continue;
  const ls = text.split('\n');
  ls.forEach((l, i) => {
    const t = l.trimStart();
    if (t.startsWith('//')) return;
    if (t.includes('@objc') || t.includes('dynamic ') || t.includes('override ')) return;
    const m = t.match(/^(?:@\w+\s+)*(?:nonisolated\s+)?(?:public\s+|internal\s+|private\s+|fileprivate\s+)?(?:static\s+)?func\s+(\w+)/);
    if (!m) return;
    const name = m[1];
    if (SKIP_NAMES.has(name)) return;
    if (SKIP_PREFIX.some(p => name.startsWith(p))) return;
    decls.push({ file: rel, name, line: i + 1 });
  });
}

const rows = [];
for (const d of decls) {
  let calls = 0;
  for (const { rel, text } of allSources) {
    const ls = text.split('\n');
    ls.forEach((l, i) => {
      // 跳过声明行本身 —— 否则每个函数都会把自己算成一个调用者，
      // 结果永远是"零调用 0 个"。（第一版就是栽在这里：Windows 反斜杠
      // 路径与正斜杠常量比较不相等，跳过从未生效。）
      if (rel === d.file && i + 1 === d.line) return;
      if (l.includes(d.name + '(')) calls++;
    });
  }
  if (calls === 0) rows.push({ ...d, calls });
}

rows.sort((a, b) => a.file.localeCompare(b.file));
console.log('扫描 ' + decls.length + ' 个函数声明   零调用 ' + rows.length + ' 个');
console.log('-'.repeat(96));
console.log('file'.padEnd(46) + 'func'.padEnd(32) + 'line'.padStart(5));
for (const r of rows) console.log(r.file.padEnd(46) + r.name.padEnd(32) + String(r.line).padStart(5));
if (!rows.length) console.log('OK 没有发现零调用的函数');
