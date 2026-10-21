#!/usr/bin/env node
// tools/statewrites.js —— 找出「声明了但从不被写入」的 @State
//
// 为什么需要它：
//   这几轮最难缠的一类 bug 不是崩溃、不是报错，而是**假机制** ——
//   代码声明了一个刷新/开关状态，挂了 .id(x) 或 if x，但全仓没有任何地方
//   给它赋值。它看起来在工作，实际执行路径根本不通。
//   （实例：refreshTick 在 3 个文件里永不递增；setArchived 零调用）
//
//   读代码很难发现这种问题，因为「它看起来对」。所以用机器去数写入点。
//
// 判定：直接赋值 / 下标赋值 / 复合赋值 / 集合变更 / inout / $Binding 都算写入。
// 第一版只认「x =」，漏了下标与集合变更，产生 3 个假阳性 ——
// 有假阳性的尺子没用，它会让人去改本来正确的代码。
//
// 诊断工具，不参与 CI 判定。
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

const isWordChar = c => c !== undefined && ('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.includes(c));
const MUTATORS = ['insert(', 'remove(', 'append(', 'removeAll(', 'removeFirst(', 'formUnion(', 'subtract(', 'toggle(', 'removeValue('];

// 判断某一行是否在写 name（不含声明行本身）
function isWrite(line, name) {
  let i = line.indexOf(name);
  while (i >= 0) {
    const before = i === 0 ? ' ' : line[i - 1];
    const after = line[i + name.length];
    if (!isWordChar(before) && !isWordChar(after)) {
      if (before === '$' || before === '&') return true;
      let rest = line.slice(i + name.length).replace(/^ /, '');
      if (rest.startsWith('=') && rest[1] !== '=') return true;
      // 复合赋值。注意 Swift 的溢出包装版本 &+= / &-= —— 本仓 SecTickCenter 就用 &+=，
      // 漏掉它会把 refreshToken 误报成「从不写入」（这次是工具自己抓到了自己）。
      if (rest[0] === '&') rest = rest.slice(1).replace(/^ /, '');
      if (rest.startsWith('+=') || rest.startsWith('-=') || rest.startsWith('*=') || rest.startsWith('/=')) return true;
      if (rest[0] === '[') {
        const close = rest.indexOf(']');
        if (close > 0) {
          const tail = rest.slice(close + 1).replace(/^ /, '');
          if (tail.startsWith('=') && tail[1] !== '=') return true;
          // checks[i].toggle() —— 下标之后紧跟集合变更，同样是写入。
          // 漏这一条会把 CareViews 的 checks 误报成"从不写入"。
          if (tail[0] === '.') {
            const inner = tail.slice(1);
            if (MUTATORS.some(m => inner.startsWith(m))) return true;
          }
        }
      }
      if (rest[0] === '.') {
        const call = rest.slice(1);
        if (MUTATORS.some(m => call.startsWith(m))) return true;
      }
    }
    i = line.indexOf(name, i + 1);
  }
  return false;
}

const rows = [];
let totalState = 0, neverWritten = 0, neverUsed = 0;

for (const f of allSwift()) {
  const src = fs.readFileSync(f, 'utf8');
  const ls = src.split('\n');
  const states = [];
  ls.forEach((l, i) => {
    const t = l.trimStart();
    if (!t.startsWith('@State')) return;
    const m = t.match(/^@State\s+(?:private\s+)?var\s+(\w+)/);
    if (m) states.push({ name: m[1], line: i + 1 });
  });
  if (!states.length) continue;
  for (const s of states) {
    totalState++;
    let writes = 0, uses = 0;
    ls.forEach((l, i) => {
      if (i + 1 === s.line) return;
      if (l.includes(s.name)) uses++;
      if (isWrite(l, s.name)) writes++;
    });
    if (writes === 0) {
      neverWritten++;
      if (uses === 0) neverUsed++;
      rows.push({ file: path.relative(path.join(ROOT, 'App'), f), name: s.name, line: s.line, uses });
    }
  }
}

rows.sort((a, b) => a.uses - b.uses);
console.log('@State 总数 ' + totalState + '   从不写入 ' + neverWritten + '   其中从不读取(完全死) ' + neverUsed);
console.log('-'.repeat(84));
console.log('file'.padEnd(34) + 'name'.padEnd(24) + 'line'.padStart(5) + 'reads'.padStart(7));
for (const r of rows) {
  console.log(r.file.padEnd(34) + r.name.padEnd(24) + String(r.line).padStart(5) + String(r.uses).padStart(7) + (r.uses === 0 ? '  <-- 完全死' : ''));
}
if (!rows.length) console.log('OK 没有发现从不写入的 @State');
