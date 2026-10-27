// 调用点实参个数闸门 —— 改签名后漏改调用点，编译期才报错。
//
// 2026-10-27 新增：CI 报 `Tests/GoldenDiffTests.swift:74: argument passed to call that takes no arguments`，
// 原因是我把 `cmd03StatusPlain(_ macHex:)` 改成无参，却漏了测试文件里的调用点。
// 39 道闸门全都没抓到这个 —— 它们查形状/命名/一致性，不查「实参个数对不对得上声明」。
//
// 本闸门只查 ZKCmdBuilder / ZKProtocol / HexKit 这三个协议构造器，
// 因为它们是被跨文件调用最多、且签名最容易变动的地方。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');

function walk(d, o = []) {
  if (!fs.existsSync(d)) return o;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, o);
    else if (e.name.endsWith('.swift')) o.push(p.replace(/\\/g, '/'));
  }
  return o;
}

// ① 收集签名
const defFiles = walk(path.join(ROOT, 'App/Core')).filter(f => /ZKCmdBuilder|ZKProtocol|HexKit/.test(f));
const sigs = new Map();

for (const f of defFiles) {
  const src = fs.readFileSync(f, 'utf8');
  const re = /static\s+func\s+(\w+)\s*\(/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const name = m[1];
    let i = m.index + m[0].length - 1;
    let depth = 0, start = i;
    for (; i < src.length; i++) {
      if (src[i] === '(') depth++;
      else if (src[i] === ')') { depth--; if (depth === 0) break; }
    }
    const params = src.slice(start + 1, i);
    if (!params.trim()) { sigs.set(name, { min: 0, max: 0, closure: false }); continue; }

    let d2 = 0, count = 0, defs = 0, cur = '';
    for (const ch of params) {
      if ('([<'.includes(ch)) d2++;
      else if (')]>'.includes(ch)) d2--;
      if (ch === ',' && d2 === 0) { count++; if (cur.includes('=')) defs++; cur = ''; continue; }
      cur += ch;
    }
    if (cur.trim()) { count++; if (cur.includes('=')) defs++; }
    const hasClosure = /->/.test(params);

    const prev = sigs.get(name);
    const min = count - defs, max = count;
    if (!prev) sigs.set(name, { min, max, closure: hasClosure });
    else sigs.set(name, { min: Math.min(prev.min, min), max: Math.max(prev.max, max), closure: prev.closure || hasClosure });
  }
}

// ② 检查调用点
const callFiles = [...walk(path.join(ROOT, 'Tests')), ...walk(path.join(ROOT, 'App'))];
const problems = [];

for (const f of callFiles) {
  const src = fs.readFileSync(f, 'utf8');
  const L = src.split(/\r?\n/);
  for (let li = 0; li < L.length; li++) {
    const line = L[li];
    if (line.trim().startsWith('//')) continue;
    const re = /(?:ZKCmdBuilder|ZKProtocol|HexKit)\.(\w+)\s*\(/g;
    let m;
    while ((m = re.exec(line)) !== null) {
      const name = m[1];
      const s = sigs.get(name);
      if (!s) continue;
      const joined = L.slice(li, li + 8).join('\n');
      const openAt = joined.indexOf(m[0]) + m[0].length - 1;
      let depth = 0, endAt = -1;
      for (let k = openAt; k < joined.length; k++) {
        if (joined[k] === '(') depth++;
        else if (joined[k] === ')') { depth--; if (depth === 0) { endAt = k; break; } }
      }
      if (endAt < 0) continue;
      const argsStr = joined.slice(openAt + 1, endAt);
      let d3 = 0, n = 0, hasAny = false;
      for (const ch of argsStr) {
        if ('([{<'.includes(ch)) d3++;
        else if (')]}>'.includes(ch)) d3--;
        if (d3 === 0 && ch === ',') n++;
        if (d3 === 0 && ch !== ',' && ch !== ' ' && ch !== '\n') hasAny = true;
      }
      let argc = hasAny ? n + 1 : 0;
      const afterClose = joined.slice(endAt + 1).trimStart();
      if (afterClose.startsWith('{') && s.closure) argc++;
      if (argc < s.min || argc > s.max) {
        problems.push({ f: path.relative(ROOT, f), line: li + 1, name, argc, min: s.min, max: s.max, text: line.trim().slice(0, 90) });
      }
    }
  }
}

if (!problems.length) {
  console.log('调用点实参个数检查 ✓ 零命中');
  process.exit(0);
}
console.log(`✗ 实参个数不符 ${problems.length} 处（改签名后漏改调用点）：\n`);
for (const p of problems.slice(0, 30)) {
  console.log(`  ${p.f}:${p.line}  ${p.name}() 给了 ${p.argc}，声明要 ${p.min}..${p.max}`);
  console.log(`     ${p.text}`);
}
process.exit(1);
