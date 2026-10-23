'use strict';
// tools/apicheck.js —— 成员级符号存在性检查（补 apisig 只查 X 前缀的空档）
//
// 为什么需要：静态门禁查括号/字号/令牌，**不查类型**。
// 实证：我给审计行写了 SecFmt.timeStr(...) —— 8 道门禁全绿，但 SecFmt 没有 timeStr，
// 这是 Xcode 编译期才爆的错。本工具把这一类提前到本地。
//
// 做法：
//   ① 扫全仓 Swift，收集「本仓声明的类型」及其成员（func / var / let / case / init）
//   ② 扫所有 TypeName.member 引用
//   ③ 若 TypeName 是本仓类型、且 member 不在其成员表里 → 报错
// 局限：动态派发、协议扩展、泛型约束、枚举 case 的简写形式会误报，所以只对
//       「本仓声明的类型 + 点号直取」这一种形态开火。
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const APPDIRS = ['App', 'android-app'].map(d => path.join(ROOT, d));

function walk(d, acc) {
  if (!fs.existsSync(d)) return;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (e.name.endsWith('.swift')) acc.push(p);
  }
}
const files = [];
for (const d of APPDIRS) walk(d, files);
if (!files.length) { console.log('apicheck: 没找到 .swift，跳过'); process.exit(0); }

// ── ① 收集类型与成员 ──
// 记录: typeName -> Set(member)
const types = new Map();
// 也记录类型别名/结构名本身（用于判断"这是本仓类型"）
const declared = new Set();

const DECL_RE = /\b(?:struct|class|enum|actor|protocol)\s+([A-Z]\w*)/g;
// 成员: 在类型体内出现的 func/var/let/case/init/subscript
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
  const lines = src.split('\n');
  // 找类型声明及其体范围（花括号平衡）
  for (let i = 0; i < lines.length; i++) {
    DECL_RE.lastIndex = 0;
    const m = DECL_RE.exec(lines[i]);
    if (!m) continue;
    const name = m[1];
    declared.add(name);
    if (!types.has(name)) types.set(name, new Set());
    const set = types.get(name);
    // 从声明行起做括号平衡直到闭合
    let depth = 0, started = false;
    for (let k = i; k < lines.length; k++) {
      const l = lines[k];
      depth += (l.match(/{/g) || []).length - (l.match(/}/g) || []).length;
      if (l.includes('{')) started = true;
      // 收集成员
      for (const mm of l.matchAll(/\b(?:func|var|let|case|init|subscript)\s+([A-Za-z_]\w*)/g)) {
        set.add(mm[1]);
      }
      // 枚举 case a, b, c
      const cm = /^\s*case\s+(.+)$/.exec(l);
      if (cm && !cm[1].includes('(')) {
        for (const c of cm[1].split(',')) {
          const t = c.trim().split(/\s|=/)[0];
          if (/^[a-z_]\w*$/i.test(t)) set.add(t);
        }
      }
      if (started && depth <= 0) break;
    }
  }
}

// ── ①b 收集 extension 成员（我第一版漏了这层，导致 90% 误报）──
const EXT_RE = /\bextension\s+([A-Z]\w*)/g;
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
  for (let i = 0; i < lines.length; i++) {
    EXT_RE.lastIndex = 0;
    const m = EXT_RE.exec(lines[i]);
    if (!m) continue;
    const name = m[1];
    if (!types.has(name)) types.set(name, new Set());
    const set = types.get(name);
    let depth = 0, started = false;
    for (let k = i; k < lines.length; k++) {
      const l = lines[k];
      depth += (l.match(/{/g) || []).length - (l.match(/}/g) || []).length;
      if (l.includes('{')) started = true;
      for (const mm of l.matchAll(/\b(?:func|var|let|case|init|subscript|typealias)\s+([A-Za-z_]\w*)/g)) {
        set.add(mm[1]);
      }
      if (started && depth <= 0) break;
    }
  }
}

// ── ② 扫引用 ──
const ALLOW = new Set([
  // 系统类型里常见同名成员，误报源，直接放过
  'self','Self','Type','Error','Optional','Array','String','Int','Double','Bool','Void','Date'
]);
const bad = [];
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
  lines.forEach((raw, i) => {
    // 去注释
    const code = raw.replace(/\/\/.*$/, '');
    for (const m of code.matchAll(/\b([A-Z]\w*)\.([a-z_]\w*)/g)) {
      const [, t, mem] = m;
      if (ALLOW.has(t)) continue;
      if (mem === 'self' || mem === 'none' || mem === 'some') continue;   // 元类型 / Optional 简写
      if (mem === 'allCases') continue;   // CaseIterable 合成成员，枚举自动有
      if (!declared.has(t)) continue;          // 系统/外部类型，不管
      const set = types.get(t);
      if (!set) continue;
      // 成员表为空说明这个类型体没解析到，放过（避免整类误报）
      if (set.size === 0) continue;
      if (set.has(mem)) continue;
      bad.push(path.relative(ROOT, f) + ':' + (i + 1) + '  ' + t + '.' + mem);
    }
  });
}

if (bad.length) {
  for (const b of bad.slice(0, 20)) console.error('  ' + b);
  console.error('✗ ' + bad.length + ' 处引用了本仓类型的未声明成员（编译期错误）');
  process.exit(1);
}
console.log('成员符号存在性 ✓ ' + declared.size + ' 个本仓类型，无未声明成员引用');
