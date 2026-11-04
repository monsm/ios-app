#!/usr/bin/env node
// switchstruct.js - gate 39: switch must not match .case on a struct
//
// 2026-11-04（真编译错驱动）：BatteryProfileHomeScreen 写了
//   switch tier { case .empty: … }   // BatteryCare.Tier 是 **struct**
// 本地 38 道闸门全绿（swiftparse 只看语法、types 只看类型名、callsig2 只查调用签名），
// CI 才报 "binary operator '~=' cannot be applied to two 'BatteryCare.Tier' operands"
// 外加三行 "reference to member 'empty' cannot be resolved without a contextual type"。
//
// 判据（窄且可静态判定）：
//   ① 收集全仓每个类型是 enum 还是 struct/class；
//   ② 对每个 `switch <ident> {`，往上找该 ident 最近的 `ident: Type` 声明；
//   ③ 若 Type 是仓内 struct/class，而 switch 块里出现 `case .Member` ⇒ 判红。
//
// 不判什么：Optional 解包（`switch x?.y`）、元组、类型推断出来的局部值 ——
// 静态解析做不到，宁可漏报不误报（与 callsig2 的取舍一致）。
'use strict';
const fs = require('fs');
const path = require('path');

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

const files = walk(APP);
const findings = [];

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  // 本文件内声明的类型种类（同名撞车时以本文件为准）
  const local = new Map();
  for (const m of src.matchAll(/^\s*(?:(?:public|private|fileprivate|internal)\s+)?(?:final\s+)?(enum|struct|class|actor)\s+(\w+)/gm)) {
    local.set(m[2], m[1]);
  }

  lines.forEach((line, i) => {
    if (line.trim().startsWith('//') || line.trim().startsWith('///')) return;
    const m = /^\s*switch\s+([A-Za-z_]\w*)\s*\{/.exec(line);
    if (!m) return;
    const subject = m[1];

    let type = null;
    for (let k = i; k >= 0; k--) {
      const mm = new RegExp('\\b' + subject + '\\s*:\\s*([A-Z][\\w]*)\\b').exec(lines[k]);
      if (mm) { type = mm[1]; break; }
    }
    if (!type) return;

    const kind = local.get(type);
    if (kind !== 'struct' && kind !== 'class') return;

    const block = lines.slice(i, i + 10).join('\n');
    if (/case\s+[.][A-Za-z]/.test(block)) {
      findings.push(rel + ':' + (i + 1) + '  switch ' + subject + '  （' + type + ' 是 ' + kind + '，不能用 case .成员）');
    }
  });
}

if (findings.length === 0) {
  console.log('switchstruct: OK — 没有对 struct/class 用 case .成员 的 switch');
  process.exit(0);
}
console.log('switchstruct: FAIL — ' + findings.length + ' 处');
for (const f of findings) console.log('  ' + f);
process.exit(1);
