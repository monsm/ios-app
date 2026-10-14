// 间距归一变换器 (dry 默认；--apply 才写)
// 两类改动：
//   A 脱档字面量   padding(6) / spacing: 3  ⇒ 就近换成 **令牌引用** (不是换成另一个数字: 数字在别的密度档还会脱档)
//   B 未声明 spacing  VStack { / HStack {   ⇒ 补 spacing: DS.Space.s (VStack/HStack 系统默认≈8pt ⇒ 视觉不变, 只是把隐藏的第三套间距写成显式令牌)
// 规则: 就近吸附, 平距取大档 (不让胶囊/徽标变瘦)。表达式值 (DS.Space.xs + 1) 一律不自动改, 交人工。
'use strict';
const fs = require('fs');
const path = require('path');
const A = require('./ast.js');
const ROOT = path.resolve(__dirname, '../..');
const APPLY = process.argv.includes('--apply');
const only = (process.argv.find((a) => a.startsWith('--file=')) || '').slice(7);
const tk = A.loadTokens(path.join(ROOT, 'App/Core/DesignSystem.swift'));
const findings = JSON.parse(fs.readFileSync(path.join(__dirname, 'findings.json'), 'utf8'));

const TOKEN_NAME = Object.entries(tk.SPACE).map(([k, v]) => [v, 'DS.Space.' + k]);   // 2→xxs 4→xs 8→s ...
function snap(v) {
  const legal = [...new Set(Object.values(tk.SPACE))].sort((a, b) => a - b);
  let best = null, bd = Infinity;
  for (const t of legal) { const d = Math.abs(v - t); if (d < bd || (d === bd && t > best)) { bd = d; best = t; } }
  const name = (TOKEN_NAME.find(([x]) => x === best) || [])[1] || String(best);
  return { v: best, name, delta: best - v };
}
const byFile = {};
findings.filter((f) => f.rule.startsWith('R3 ')).forEach((f) => { if (!only || f.file.endsWith(only)) (byFile[f.file] = byFile[f.file] || []).push(f); });

let stats = { A: 0, B: 0, skip: [], files: 0 };
for (const file of Object.keys(byFile)) {
  const src = fs.readFileSync(file, 'utf8');
  const L = src.split('\n');
  const crlf = src.includes('\r\n');
  if (crlf) for (let i = 0; i < L.length; i++) L[i] = L[i].replace(/\r$/, '');
  for (const f of byFile[file]) {
    let line = L[f.line - 1];
    if (line === undefined) { stats.skip.push(`${path.basename(file)}:${f.line} 行号对不上`); continue; }
    if (f.rule === 'R3 间距脱离令牌') {
      const raw = (f.calc || '').trim();
      if (!/^-?\d+(\.\d+)?$/.test(raw)) { stats.skip.push(`${path.basename(file)}:${f.line} 值不是纯数字 (${raw}) ⇒ 留人工`); continue; }
      const v = +raw, s = snap(v);
      if (s.v === v) { continue; }
      // 只在该行里换"这个数出现在 padding(...) 或 spacing: 位置"的那一处
      const re = new RegExp('((?:\\.|\\b)padding\\s*\\(\\s*(?:\\.[a-zA-Z]+\\s*,\\s*)?)' + raw.replace('.', '\\.') + '\\s*\\)');
      const re2 = new RegExp('(spacing\\s*:\\s*)' + raw.replace('.', '\\.') + '\\s*(?=[,)])');
      let done = false;
      if (re.test(line)) { line = line.replace(re, (m, p1) => p1 + s.name + ')'); done = true; }
      else if (re2.test(line)) { line = line.replace(re2, (m, p1) => p1 + s.name); done = true; }
      if (!done) { stats.skip.push(`${path.basename(file)}:${f.line} 在该行没定位到 ${raw} ⇒ 不动`); continue; }
      L[f.line - 1] = line; stats.A++;
      (f.rep = { from: raw, to: s.name, delta: s.delta });
    } else {
      // B: VStack/HStack 未声明 spacing ⇒ 补显式令牌 (VStack{ / VStack(alignment: .leading){)
      const nm = /VStack/.test(line) ? 'VStack' : 'HStack';
      let done = false;
      line = line.replace(new RegExp(nm + '\\s*\\{'), (m) => { done = true; return nm + '(spacing: DS.Space.s) {'; });
      if (!done) line = line.replace(new RegExp(nm + '\\s*\\(\\s*(alignment\\s*:\\s*[^)]+)\\)\\s*\\{'), (m, p1) => { done = true; return nm + '(' + p1 + ', spacing: DS.Space.s) {'; });
      if (!done) { stats.skip.push(`${path.basename(file)}:${f.line} ${nm} 形态没认出来 ⇒ 不动`); continue; }
      L[f.line - 1] = line; stats.B++;
    }
  }
  const outText = (crlf ? L.map((x) => x + '\r') : L).join('\n');
  // 写前自检: 只允许"新增令牌名长度"的差, 且花括号配平不变
  const bal = (t) => (t.match(/\{/g) || []).length - (t.match(/\}/g) || []).length;
  if (bal(src) !== bal(outText)) { console.log('✗ ' + path.basename(file) + ' 花括号配平变了, 放弃该文件'); continue; }
  stats.files++;
  if (APPLY) fs.writeFileSync(file, outText);
  console.log(`${APPLY ? '✓' : '[dry]'} ${path.basename(file).padEnd(24)} 脱档换令牌 ${byFile[file].filter((x) => x.rep).length} · 补显式 spacing ${byFile[file].filter((x) => !x.rep).length}`);
}
console.log(`\n合计: ${stats.files} 文件 · A 换令牌 ${stats.A} · B 补 spacing ${stats.B} · 跳过 ${stats.skip.length}`);
stats.skip.slice(0, 14).forEach((s) => console.log('   ○ ' + s));
