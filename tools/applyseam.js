#!/usr/bin/env node
// 给目的地挂上变体语法缝 — node tools/applyseam.js [--only=A,B] [--dry-run] [--verbose]
//
// 做什么：对 App/Core/Destination.swift 里每个 case，找到它对应的那个 `struct XView: View`，
// 把它的 body 改成经过 `.destined(.case)` 的缝。
//
// 为什么用「重命名 + 插一行」而不是「在 body 表达式尾巴上接一个 modifier」：
//   body 是 `var body: some View { <表达式> }`，而 <表达式> 可能是多语句、ViewBuilder、
//   带 switch、带 let —— 想定位它的"结尾"就得完整解析 Swift 表达式，我这边没有编译器兜底。
//   重命名与 body 内部长什么样**无关**：
//       var body: some View { vkBody.destined(.alpha) }
//       var vkBody: some View { ...原来那一整段，一个字都不动... }
//   代价是每个页面多一个计算属性。收益是可以逐文件回退、且不会把 modifier 接错位置。
//
// 深度判定：只在**该 struct 自己的第一层花括号内**找 `var body`。
//   不判深度就会命中嵌套 struct / 内部 extension 的 body，把别人的 body 改名 —— 那是最坏的一类
//   "改对了名字改错了宿主"。
//   数花括号时要跳过字符串与注释里的括号，否则会在 `"{"` 上多进一层，整段错位。
'use strict';
const fs = require('fs');
const path = require('path');

const ENUM = path.join('App', 'Core', 'Destination.swift');
const args = process.argv.slice(2);
const DRY = args.includes('--dry-run');
const VERBOSE = args.includes('--verbose');
const only = (args.find((a) => a.startsWith('--only=')) || '').replace('--only=', '')
  .split(',').filter(Boolean);

function walk(dir, out) {
  out = out || [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) walk(f, out);
    else if (f.endsWith('.swift')) out.push(f);
  }
  return out;
}
const FILES = walk('App').concat(walk('Widget')).concat(walk('Shared'));

/** 从 open 处的 '{' 找配对 '}' 的下标；跳过字符串与注释里的括号。 */
function closeBrace(src, open) {
  let depth = 0, i = open, inLine = false, inBlock = false, inStr = false;
  for (; i < src.length; i++) {
    const c = src[i], p = src[i - 1];
    if (inLine) { if (c === '\n') inLine = false; continue; }
    if (inBlock) { if (c === '/' && p === '*') inBlock = false; continue; }
    if (inStr) { if (c === '\\') { i++; continue; } if (c === '"') inStr = false; continue; }
    if (c === '/' && src[i + 1] === '/') { inLine = true; continue; }
    if (c === '/' && src[i + 1] === '*') { inBlock = true; continue; }
    if (c === '"') { inStr = true; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return i; }
  }
  return -1;
}

function readEnum() {
  const src = fs.readFileSync(ENUM, 'utf8');
  const re = /^\s*case\s+([a-zA-Z0-9_]+)\s*=\s*"([A-Za-z0-9_]+View)"/gm;
  const out = []; let m;
  while ((m = re.exec(src))) out.push({ swCase: m[1], typeName: m[2] });
  return out;
}

/** 在 files 里找 `struct X: View`，返回 {file, bodyStart(改名插入点), indent} */
function findBody(entry, files) {
  const decl = new RegExp(`^\\s*(?:(?:public|internal|fileprivate|private)\\s+)?struct\\s+${entry.typeName}\\s*:\\s*[^{]*\\bView\\b`, 'm');
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    const dm = decl.exec(src);
    if (!dm) continue;
    const open = src.indexOf('{', dm.index + dm[0].length - 1);
    if (open < 0) continue;
    const close = closeBrace(src, open);
    if (close < 0) continue;
    // 在 struct 自己这一层扫 var body
    let depth = 1, i = open + 1, inLine = false, inBlock = false, inStr = false;
    for (; i < close; i++) {
      const c = src[i], p = src[i - 1];
      if (inLine) { if (c === '\n') inLine = false; continue; }
      if (inBlock) { if (c === '/' && p === '*') inBlock = false; continue; }
      if (inStr) { if (c === '\\') { i++; continue; } if (c === '"') inStr = false; continue; }
      if (c === '/' && src[i + 1] === '/') { inLine = true; continue; }
      if (c === '/' && src[i + 1] === '*') { inBlock = true; continue; }
      if (c === '"') { inStr = true; continue; }
      if (c === '{') { depth++; continue; }
      if (c === '}') { depth--; continue; }
      if (depth !== 1) continue;
      const rest = src.slice(i);
      const bm = /^(var|func)\s+body\s*(?::\s*some\s+View\s*\{|\s*->\s*some\s+View\s*\{|\s*\{)/.exec(rest);
      if (!bm) continue;
      // 回溯缩进
      const lineStart = src.lastIndexOf('\n', i) + 1;
      return { file: f, src, at: lineStart, kind: bm[1], braceAt: i + bm[0].length - 1,
               indent: src.slice(lineStart, i).match(/^\s*/)[0],
               declEnd: src.indexOf('\n', i) };
    }
    return { file: f, notFound: true };
  }
  return { file: null };
}

function main() {
  const entries = readEnum().filter((e) => !only.length || only.includes(e.typeName) || only.includes(e.swCase));
  const done = [], skipped = [], missing = [];
  for (const e of entries) {
    const r = findBody(e, FILES);
    if (!r.file) { missing.push(e.typeName + ' (找不到 struct 声明)'); continue; }
    if (r.notFound) { missing.push(e.typeName + ' (声明在但第一层没有 var body)'); continue; }
    if (/\.destined\(\./.test(r.src.slice(r.at, r.at + 400))) { skipped.push(e.typeName + ' (已挂过)'); continue; }
    const openBrace = r.braceAt;
    const close = closeBrace(r.src, openBrace);
    if (close < 0) { missing.push(e.typeName + ' (body 花括号不配对，跳过)'); continue; }
    const wrapper = `${r.indent}var body: some View { vkBody.destined(.${e.swCase}) }\n`;
    // 只改属性名，body 里的内容一个字不动
    const head = r.src.slice(0, r.at);
    const origLine = r.src.slice(r.at, r.declEnd);
    const renamed = origLine.replace(/\bbody\b/, 'vkBody');
    const tail = r.src.slice(r.declEnd);
    const next = head + wrapper + renamed + tail;
    if (DRY) {
      console.log(`  [dry] ${e.typeName.padEnd(28)} ${r.file}`);
      if (VERBOSE) console.log(renamed.slice(0, 90).replace(/^/gm, '         '));
    } else {
      fs.writeFileSync(r.file, next);
    }
    done.push(e.typeName);
  }
  console.log('');
  console.log(`${DRY ? '预演' : '已挂缝'} ${done.length}   跳过 ${skipped.length}   未命中 ${missing.length}   共 ${entries.length}`);
  if (skipped.length && VERBOSE) skipped.forEach((s) => console.log('   skip  ' + s));
  if (missing.length) {
    console.log('   ⚠ 未命中清单 (这些目的地没有缝，"完整"就还差它们):');
    missing.forEach((s) => console.log('     · ' + s));
  }
}
main();
