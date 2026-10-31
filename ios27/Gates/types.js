#!/usr/bin/env node
// types.js —— 类型解析闸门（本地无编译器时的第二道真检查）。
//
// 为什么需要它：swiftparse 只验语法。但「引用了不存在的类型」是语法正确的，编译器一跑就炸。
// 本次重建实际踩到 5 个，每一个都是「本地全绿、云端编译红」的那种：
//   · Member 重复声明（AppModel 与 Engine/StoreModels 各一份）
//   · ToneColor（旧设计系统里的，Engine/BatteryCare 引用）
//   · BackupBundle / BackupKit / CredPackage / AlarmMeta / LockArchive / StatsKit / AutoOpenKit / CryptoBox / DFUError
//   · AppState（界面状态类被塞进 Engine 的服务函数签名）
//   · SettingsGroups（纯 UI 组件混进了 Engine）
//
// 判什么：
//   ① 同一顶层类型名不得在两处声明（重复声明 = 编译错）
//   ② Engine/ 里引用的项目类型必须真的存在（SDK 类型走 Gates/sdk-types.txt）
// 不判什么：泛型参数 / 协议关联类型 / 局部类型 —— 静态解析做不到，宁可漏报不误报。
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

function codeOnly(src) {
  return src.split(/\r?\n/).map((l) => {
    let out = '', i = 0, q = false;
    while (i < l.length) {
      const c = l[i];
      if (q) { if (c === '\\') { i += 2; continue; } if (c === '"') { q = false; i++; continue; } i++; continue; }
      if (c === '/' && l[i + 1] === '/') break;
      if (c === '"') { q = true; i++; continue; }
      out += c; i++;
    }
    return out;
  }).join('\n');
}

const SDK = new Set(
  fs.readFileSync(path.join(__dirname, 'sdk-types.txt'), 'utf8').split(/\s+/).filter(Boolean)
);

const files = walk(APP);
const byRel = new Map();
for (const f of files) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  byRel.set(rel, codeOnly(fs.readFileSync(f, 'utf8')));
}

const findings = [];

// ---------- ① 顶层类型重复声明 ----------
// 只在「行首」的声明之间查重（嵌套类型在不同父类型里同名是合法的）。
const decls = new Map();     // 顶层
const known = new Set();     // 顶层 + 嵌套（供 ② 用）
for (const [rel, code] of byRel) {
  for (const m of code.matchAll(/^((?:public |private |fileprivate |internal )?(?:final )?(?:struct|class|enum|actor|protocol|typealias))\s+(\w+)/gm)) {
    const name = m[2];
    if (!decls.has(name)) decls.set(name, []);
    decls.get(name).push(rel);
    known.add(name);
  }
  // 嵌套类型：任意缩进（含 enum 内的 struct / struct 内的 enum）
  for (const m of code.matchAll(/^\s+(?:(?:public |private |fileprivate |internal )?(?:final )?)(?:struct|class|enum|actor|protocol|typealias)\s+(\w+)/gm)) {
    known.add(m[1]);
  }
  // 枚举 case 也会被当作类型名引用（如 .ok），把 case 名单也收进来
  for (const m of code.matchAll(/^\s*case\s+(\w+)/gm)) known.add(m[1]);
  // 一行里逗号分隔的常量声明：static let Z3 = 7891, Z3NFC = 7892 → 两个名字都要算已知
  for (const m of code.matchAll(/^\s*(?:public |private |fileprivate |internal )?(?:static )?(?:let|var)\s+([\w\s,=0-9."'()\[\]:-]+)$/gm)) {
    for (const n of m[1].matchAll(/(?:^|,)\s*(\w+)\s*=/g)) known.add(n[1]);
  }
  // 泛型参数（<T> / <Value>）与局部变量名
  for (const m of code.matchAll(/<\s*([A-Z]\w*)/g)) known.add(m[1]);
  // 泛型参数带约束的写法：<Type: Codable>
  for (const m of code.matchAll(/<\s*([A-Z]\w*)\s*:/g)) known.add(m[1]);
}
for (const [name, places] of decls) {
  if (places.length > 1) findings.push('重复声明 ' + name + ' → ' + places.join(' + '));
}

// ---------- ② Engine 引用的项目类型必须存在 ----------
const missing = new Map();
for (const [rel, code] of byRel) {
  if (!rel.startsWith('Engine/')) continue;
  const lines = code.split('\n');
  lines.forEach((line, i) => {
    for (const m of line.matchAll(/\b([A-Z][A-Za-z0-9]{2,})\b/g)) {
      const t = m[1];
      if (known.has(t) || SDK.has(t)) continue;
      if (/^[A-Z]{2,4}$/.test(t)) continue;   // 常量名（Z3NFC / ZKBBV1 这类）
      if (!missing.has(t)) missing.set(t, []);
      missing.get(t).push(rel + ':' + (i + 1));
    }
  });
}
for (const [t, locs] of missing) {
  findings.push('Engine 引用了不存在的类型 ' + t + ' → ' + locs.slice(0, 3).join(', '));
}

console.log('types: ' + files.length + ' 个文件，' + decls.size + ' 个顶层类型，SDK 白名单 ' + SDK.size + ' 项');
if (findings.length === 0) {
  console.log('types: OK — 无重复声明，Engine 无未解析类型引用');
  process.exit(0);
}
console.log('types: FAIL — ' + findings.length + ' 处\n');
for (const f of findings) console.log('  ' + f);
process.exit(1);