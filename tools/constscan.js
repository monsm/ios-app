#!/usr/bin/env node
// 全仓符号索引 + 常量/属性零引用扫描（一次性建索引，避免逐符号 spawn git）
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const LF = String.fromCharCode(10);
const BSLASH = String.fromCharCode(92);

function swiftFiles(dir) {
  let out = [];
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(swiftFiles(f));
    else if (e.name.endsWith('.swift')) out.push(f);
  }
  return out;
}

function stripComments(text) {
  let out = '', i = 0, n = text.length, inBlock = false;
  while (i < n) {
    const c = text[i], d = text[i + 1];
    if (inBlock) { if (c === '*' && d === '/') { inBlock = false; i += 2; continue; } if (c === LF) out += c; i++; continue; }
    if (c === '/' && d === '/') { while (i < n && text[i] !== LF) i++; continue; }
    if (c === '/' && d === '*') { inBlock = true; i += 2; continue; }
    if (c === '"') {
      if (text.slice(i, i + 3) === '"""') { out += text.slice(i, i + 3); i += 3; while (i < n && text.slice(i, i + 3) !== '"""') { out += text[i]; i++; } out += '"""'; i += 3; continue; }
      out += c; i++;
      while (i < n && text[i] !== '"') { if (text[i] === BSLASH) { out += text[i]; i++; } if (i < n) { out += text[i]; i++; } }
      out += '"'; i++; continue;
    }
    out += c; i++;
  }
  return out;
}

const DIRS = ['App', 'Widget', 'Shared'];
const files = DIRS.flatMap(d => swiftFiles(path.join(ROOT, d)));
const norm = f => path.relative(ROOT, f).split(path.sep).join('/');

// 建索引: name -> [{file, line, kind}]
const occ = new Map();
const srcByFile = new Map();
for (const f of files) {
  const rel = norm(f);
  const src = stripComments(fs.readFileSync(f, 'utf8').replace(/\r\n/g, LF));
  srcByFile.set(rel, src);
  const lines = src.split(LF);
  for (let i = 0; i < lines.length; i++) {
    const toks = lines[i].match(/\b[A-Za-z_][A-Za-z0-9_]*\b/g) || [];
    for (const t of toks) {
      if (!occ.has(t)) occ.set(t, []);
      occ.get(t).push({ file: rel, line: i + 1 });
    }
  }
}

// 收集声明: 成员/顶层 let 与 var
const decls = [];
const RE_LET = /^\s{0,12}(?:(?:public|private|fileprivate|internal|open|static|class|final|nonisolated|@MainActor|@Published|@State)\s+)*(let|var)\s+([a-z_]\w*)\s*[:=]/;
for (const [rel, src] of srcByFile) {
  const lines = src.split(LF);
  let depth = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(RE_LET);
    if (m) decls.push({ file: rel, line: i + 1, kind: m[1], name: m[2], depth });
    depth += (lines[i].match(/{/g) || []).length - (lines[i].match(/}/g) || []).length;
  }
}

// 判定: 该名字全仓出现 <= 1 次 = 只在自己声明行出现
const dead = [];
for (const d of decls) {
  const hits = occ.get(d.name) || [];
  const others = hits.filter(h => !(h.file === d.file && h.line === d.line));
  if (others.length === 0) dead.push(d);
}

console.log('声明总数 ' + decls.length + ' · 零引用 ' + dead.length);
for (const d of dead) console.log('  ' + d.file + ':' + d.line + '  ' + d.kind + ' ' + d.name);