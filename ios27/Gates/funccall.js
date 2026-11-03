#!/usr/bin/env node
// funccall.js —— 闸门 26：同文件内私有方法的调用参数标签必须与声明一致
//
// 2026-11-03 两次真实事故驱动：
//   ① legendRow 声明改成少一个参数，三个调用点还传 total: —— 本地全绿，云端 3 个 error。
//   ② 同文件里给 CredBinSheet 加 @State，而对话框挂在 CredHistorySheet 上。
//
// 判据（只看**同一文件内**的 private func）：声明 private func name(a: T, b: U)
//   → 调用 name(x: 1, y: 2) 的标签序列必须完全一致。带默认值的允许省略尾部。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'App');
function walk(d, out) {
  out = out || [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}
function labelsOf(paramList) {
  const out = [];
  let depth = 0, cur = '';
  const parts = [];
  for (const ch of paramList) {
    if ('(<['.includes(ch)) depth++;
    else if (')>]'.includes(ch)) depth--;
    if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; }
    else cur += ch;
  }
  if (cur.trim()) parts.push(cur);
  for (const p of parts) {
    const t = p.trim();
    if (!t) continue;
    const hasDefault = /=\s*[^=]/.test(t) || /->/.test(t);
    const m = /^([A-Za-z_]\w*|_)\s+([A-Za-z_]\w*)\s*:|^([A-Za-z_]\w*)\s*:/.exec(t);
    let label = '';
    if (m) label = m[1] === '_' ? '' : (m[1] || m[3] || '');
    out.push({ label: label, hasDefault: hasDefault });
  }
  return out;
}
let bad = 0;
const report = [];
for (const f of walk(ROOT)) {
  const raw = fs.readFileSync(f, 'utf8');
  const src = raw.split('\n').map(function (l) { return l.replace(/\/\/.*$/, ''); }).join('\n');
  const decls = new Map();
  // 收本文件全部 func（private/internal 都收）：同文件内调用一律校验。
  const re = /func\s+([A-Za-z_]\w*)\s*\(/g;
  let m;
  while ((m = re.exec(src))) {
    const name = m[1];
    let i = m.index + m[0].length - 1, depth = 0, j = i;
    for (; j < src.length; j++) {
      if (src[j] === '(') depth++;
      else if (src[j] === ')') { depth--; if (depth === 0) break; }
    }
    if (!decls.has(name)) decls.set(name, []);
    decls.get(name).push(labelsOf(src.slice(i + 1, j)));
  }
  if (decls.size === 0) continue;
  for (const entry of decls) {
    const name = entry[0], overloads = entry[1];
    const callRe = new RegExp('(?<![.\\w])' + name + '\\(', 'g');
    let cm;
    while ((cm = callRe.exec(src))) {
      let i = cm.index + cm[0].length - 1, depth = 0, j = i;
      for (; j < src.length; j++) {
        if (src[j] === '(') depth++;
        else if (src[j] === ')') { depth--; if (depth === 0) break; }
      }
      // 先抹掉字符串字面量：\(...) 插值里的逗号会被误当成参数分隔。
      const argText = src.slice(i + 1, j).replace(/"(?:[^"\\]|\\.)*"/g, '""');
      const argLabels = labelsOf(argText).map(function (x) { return x.label; });
      // 尾部闭包：`) {` 形式会额外补上一个参数（Swift trailing closure）
      let after = j + 1;
      while (after < src.length && /\s/.test(src[after])) after++;
      const hasTrailing = src[after] === '{';
      let matched = false;
      // Swift 语义：任何**带默认值**的参数都可以省略（不只是尾部），其余必须按序出现。
      // 于是判据是「调用标签序列是声明标签序列的子序列，且被跳过的声明参数都有默认值」。
      function subseq(wantDecl, args) {
        let wi = 0;
        for (let ai = 0; ai < args.length; ai++) {
          const lab = args[ai];
          let found = -1;
          for (let k = wi; k < wantDecl.length; k++) {
            if (lab === '__trailing__' || wantDecl[k].label === lab) { found = k; break; }
            if (!wantDecl[k].hasDefault) return false;
          }
          if (found < 0) return false;
          wi = found + 1;
        }
        for (let k = wi; k < wantDecl.length; k++) if (!wantDecl[k].hasDefault) return false;
        return true;
      }
      let ok = false;
      const trials = hasTrailing ? [argLabels, argLabels.concat(['__trailing__'])] : [argLabels];
      for (const declLabels of overloads) {
        for (const trial of trials) {
          if (subseq(declLabels, trial)) { ok = true; break; }
        }
        if (ok) break;
      }      if (!ok) {
        bad++;
        const line = src.slice(0, cm.index).split('\n').length;
        const wants = overloads.map(function (o) { return '(' + o.map(function (x) { return x.label; }).join(', ') + ')'; }).join(' 或 ');
        report.push(path.relative(path.join(__dirname, '..'), f) + ':' + line + '  ' + name + '(' + argLabels.join(', ') + ') ≠ 声明' + wants);
      }
    }
  }
}
if (bad === 0) {
  console.log('funccall: OK — 同文件内私有方法调用的参数标签全部对得上');
  process.exit(0);
}
console.log('funccall: FAIL — ' + bad + ' 处参数标签与声明不符：');
report.slice(0, 30).forEach(function (r) { console.log('  ' + r); });
process.exit(1);