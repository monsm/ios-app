#!/usr/bin/env node
// static-audit.js —— ios27 高危模式静态检查（报告型，默认不判红）。
//
// 目的：本机没有 Swift/Xcode，编译器看不见的"会崩/会泄密/会竞态"模式只能静态扫。
// 覆盖六类（与 docs/VERIFY-FINAL.md §2 一一对应）：
//   A 强解包 try! / as! / 后缀 !
//   B 数组下标 [0] / [1] / first! / last!
//   C await 后使用可能失效的索引
//   D 空集合上的 max()!/min()!/reduce
//   E 密码/密钥被 print 或写进日志
//   F 并发：Task.detached / 非 @MainActor 的 @Observable / Task 强引用 self
//
// 用法：node Tools/static-audit.js [--strict]
//   --strict 时 P0 命中即退出 1；默认只报告。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');
const STRICT = process.argv.includes('--strict');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 注释换空格、字符串内容换 '~'（保留换行与长度，行号不漂）
function mask(src) {
  const a = src.split('');
  const n = a.length;
  let i = 0;
  while (i < n) {
    const c = a[i], d = a[i + 1];
    if (c === '/' && d === '/') { while (i < n && a[i] !== '\n') { a[i] = ' '; i++; } continue; }
    if (c === '/' && d === '*') {
      let depth = 1; a[i] = ' '; a[i + 1] = ' '; i += 2;
      while (i < n && depth > 0) {
        if (a[i] === '/' && a[i + 1] === '*') { depth++; a[i] = ' '; a[i + 1] = ' '; i += 2; continue; }
        if (a[i] === '*' && a[i + 1] === '/') { depth--; a[i] = ' '; a[i + 1] = ' '; i += 2; continue; }
        if (a[i] !== '\n') a[i] = ' ';
        i++;
      }
      continue;
    }
    if (c === '"') {
      if (a[i + 1] === '"' && a[i + 2] === '"') {
        a[i] = '~'; a[i + 1] = '~'; a[i + 2] = '~'; i += 3;
        while (i < n) {
          if (a[i] === '"' && a[i + 1] === '"' && a[i + 2] === '"') { a[i] = '~'; a[i + 1] = '~'; a[i + 2] = '~'; i += 3; break; }
          if (a[i] !== '\n') a[i] = '~';
          i++;
        }
        continue;
      }
      a[i] = '~'; i++;
      while (i < n) {
        const ch = a[i];
        if (ch === '\\') { a[i] = '~'; if (a[i + 1] && a[i + 1] !== '\n') a[i + 1] = '~'; i += 2; continue; }
        if (ch === '"') { a[i] = '~'; i++; break; }
        if (ch === '\n') break;
        a[i] = '~'; i++;
      }
      continue;
    }
    i++;
  }
  return a.join('');
}

const files = walk(APP).map((f) => ({
  rel: path.relative(APP, f).split(path.sep).join('/'),
  raw: fs.readFileSync(f, 'utf8'),
}));
for (const f of files) {
  f.lines = f.raw.split(/\r?\n/);
  f.masked = mask(f.raw).split(/\r?\n/);
}

const findings = [];
function add(rule, severity, rel, line, code, fix) {
  findings.push({ rule, severity, file: rel, line, code: code.trim().slice(0, 160), fix });
}

// ---------- A. 强解包 ----------
for (const f of files) {
  f.masked.forEach((line, i) => {
    if (/\btry!/.test(line)) add('A/force-unwrap', 'P0', f.rel, i + 1, f.lines[i], '改 try? + guard/throw，或 do-catch 显式处理');
    if (/\bas!/.test(line)) add('A/force-unwrap', 'P0', f.rel, i + 1, f.lines[i], '改 as? + guard let，或按类型分支');
    // 后缀 ! —— 排除 != 与前缀取反
    const m = line.match(/([A-Za-z_][A-Za-z0-9_\.\)\]]*)!(?!=)/g);
    if (m) {
      for (const hit of m) {
        if (/^(if|guard|while|return|else|!)$/.test(hit.replace(/!$/, ''))) continue;
        add('A/force-unwrap', 'P2', f.rel, i + 1, f.lines[i], '改可选绑定 / ?? 默认值；确属不可能为空时加注释说明不变量');
      }
    }
  });
}

// ---------- B. 下标 / first! / last! ----------
for (const f of files) {
  f.masked.forEach((line, i) => {
    if (/\[0\]|\[1\]/.test(line)) add('B/index', 'P2', f.rel, i + 1, f.lines[i], '确认前方有 count/isEmpty 守卫；否则改 first/last 或 guard');
    if (/\.first!|\.last!/.test(line)) add('B/index', 'P1', f.rel, i + 1, f.lines[i], '改 .first/.last + guard let');
  });
}

// ---------- C. await 后使用旧索引 ----------
for (const f of files) {
  for (let i = 0; i < f.masked.length; i++) {
    const m = f.masked[i].match(/(?:let|var)\s+(\w+)\s*=.*firstIndex\(/);
    if (!m) continue;
    const name = m[1];
    let sawAwait = false;
    for (let j = i + 1; j < Math.min(i + 40, f.masked.length); j++) {
      const line = f.masked[j];
      if (/^\s*\}/.test(line) && j > i + 3) break;
      if (/\bawait\b/.test(line)) sawAwait = true;
      if (sawAwait && new RegExp(name + '\\s*\\]').test(line)) {
        add('C/await-stale-index', 'P1', f.rel, j + 1, f.lines[j], 'await 之后重新取 firstIndex（或先拷贝值再写回），不要复用 await 前的下标');
        break;
      }
    }
  }
}

// ---------- D. 空集合 ----------
for (const f of files) {
  f.masked.forEach((line, i) => {
    if (/\.max\(\)!|\.min\(\)!|\.sorted\(\)\.first!|\.sorted\(\)\.last!/.test(line)) {
      add('D/empty-collection', 'P1', f.rel, i + 1, f.lines[i], '改 max()/min() 可选 + guard，或先判 isEmpty');
    }
  });
}

// ---------- E. 密钥/密码进日志 ----------
const secretWord = /(pwd|password|passcode|skey|ekey|bkey|secret|token|pin|duress|密码|密钥|口令)/i;
for (const f of files) {
  f.lines.forEach((line, i) => {
    if (!/\b(print|debugPrint|NSLog|os_log|logger\.\w+|log)\s*\(/.test(line)) return;
    if (!secretWord.test(line)) return;
    if (/\b(count|长度|位数|len|length|shape|fingerprint|hash)\b/i.test(line)) return; // 只打长度/指纹的放行
    if (/privacy:\s*\.private/.test(line)) return;
    add('E/secret-log', 'P1', f.rel, i + 1, line, '删除该行或只打长度/指纹；OSLog 用 privacy: .private');
  });
}

// ---------- F. 并发 ----------
for (const f of files) {
  const isView = /\bstruct\s+\w+\s*:\s*View\b/.test(f.raw);
  f.masked.forEach((line, i) => {
    if (/Task\.detached/.test(line)) add('F/concurrency', 'P2', f.rel, i + 1, f.lines[i], '确认无 UI 状态写入；否则改 Task { @MainActor in }');
    if (/@Observable/.test(f.lines[i]) && !/@MainActor/.test(f.lines.slice(Math.max(0, i - 3), i + 1).join(' '))) {
      add('F/concurrency', 'P1', f.rel, i + 1, f.lines[i], '@Observable 类加 @MainActor（UI 状态必须主线程隔离）');
    }
    if (/Task\s*\{\s*$/.test(line) && isView) {
      // 视图里的 Task 默认继承 MainActor（SwiftUI View 是 @MainActor）；只提示，不判红
      add('F/concurrency', 'P3', f.rel, i + 1, f.lines[i], 'View 内 Task 继承 MainActor；若闭包跨 @Sendable 边界，显式写 @MainActor');
    }
    if (/Task\s*\{[^}]*\bself\./.test(line) && /class\s/.test(f.raw) && !/\[weak self\]/.test(line)) {
      add('F/concurrency', 'P2', f.rel, i + 1, f.lines[i], 'class 内 Task 用 [weak self] 避免强引用延长生命周期');
    }
  });
}

// ---------- 输出 ----------
const bySeverity = { P0: 0, P1: 0, P2: 0, P3: 0 };
for (const x of findings) bySeverity[x.severity] = (bySeverity[x.severity] || 0) + 1;
console.log('static-audit: ' + files.length + ' 个 Swift 文件');
console.log('static-audit: P0=' + bySeverity.P0 + ' P1=' + bySeverity.P1 + ' P2=' + bySeverity.P2 + ' P3=' + bySeverity.P3);
for (const sev of ['P0', 'P1', 'P2']) {
  const list = findings.filter((x) => x.severity === sev);
  if (!list.length) continue;
  console.log('');
  console.log('== ' + sev + ' (' + list.length + ') ==');
  for (const x of list) console.log('  ' + x.file + ':' + x.line + '  [' + x.rule + ']  ' + x.code);
}
if (process.argv.includes('--json')) console.log(JSON.stringify(findings, null, 2));
if (STRICT && bySeverity.P0 > 0) process.exit(1);
