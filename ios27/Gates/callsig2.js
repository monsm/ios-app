#!/usr/bin/env node
// callsig2.js —— 调用签名 / 成员 / 隔离闸门（第二版）。
//
// 为什么需要它：本地 15 道闸门全绿，CI 仍连着报真编译错（run 41201710690 / 41203581478 的 annotation）：
//   value of tuple type has no member 'after'          → R5
//   main actor-isolated ... in a sync nonisolated ctx  → R3
//   extra argument 'size' in call                      → R2
//   cannot assign to property: 'ssid' is a 'let'       → R4
//   missing argument label 'mac:' in call              → R1
//   value of type 'StatusSnapshot' has no member 'x'   → R6/R7
// 这些都不是语法错：括号闸门、tree-sitter 语法树闸门、类型名闸门全都看不见。
// 它们要的是一张**签名表 + 成员表**，而本地没有编译器，只能自己建。
//
// tier-1（命中即红）：
//   R1 调用标签与声明不符（同名只有一种签名时才判）
//   R2 构造调用（struct 成员逐一初始化器 / 显式 init）的标签与个数
//   R3 @MainActor 成员在非 MainActor 同步上下文被直接调用
//   R4 let 存储属性被赋值
//   R5 无标签 tuple 返回值用 .成员 访问
//   R6 类型名.成员 不存在（静态访问，base 是仓内类型）
// tier-2（只提示）：
//   R7 局部变量.成员 不存在
//
// Swift 实参匹配规则（本闸门的核心）：具名实参按**标签**匹配，不按位置；被跳过的中间参数
// 必须有默认值。所以 Reading(value:unit:size:tint:) 跳过 weight 是合法的。
// 属性包装器（@State/@Environment/…）不参与成员逐一初始化器的必填约束 —— 见 wrapperProps。
//
// 不判什么：泛型实参推导、协议见证、宏展开、KeyPath、运算符重载、Int/UInt32 之类类型不匹配。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

// ---------- 0. 读文件 ----------
function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 注释换成空格；字符串内容换成 '~'（不是空格）—— cached("yyyy") 仍要算「一个位置实参」。
// 保留长度与换行，后面所有正则都跑在这份遮罩文本上。
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

const FILES = walk(APP).map((f) => {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const code = mask(src);
  return { rel, src, code, lines: code.split('\n'), rawLines: src.split('\n') };
});
const fileByRel = new Map(FILES.map((f) => [f.rel, f]));

function lineOf(text, idx) {
  let n = 1;
  for (let i = 0; i < idx && i < text.length; i++) if (text[i] === '\n') n++;
  return n;
}

// ---------- 1. 括号配对 / 顶层切分 ----------
function matchClose(text, openIdx, open, close) {
  let depth = 0;
  for (let i = openIdx; i < text.length; i++) {
    const c = text[i];
    if (c === open) depth++;
    else if (c === close) { depth--; if (depth === 0) return i; }
  }
  return -1;
}

function splitTop(s, sep) {
  const out = []; let depth = 0; let angle = 0; let cur = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === '<' && depth === 0) { if (/[\w\])>]/.test(s[i - 1] || '')) angle++; }
    else if (c === '>' && depth === 0 && angle > 0 && s[i - 1] !== '-') angle--;
    if (c === sep && depth === 0 && angle === 0) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  out.push(cur);
  return out;
}

function topLevelIndexOf(s, ch) {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === ch && depth === 0) {
      if (ch === ':' && s[i + 1] === ':') continue;
      return i;
    }
  }
  return -1;
}

// 顶层语句切分：同一行的 \`struct A { var x: Int; var y: Int }\` 也要拆成两条成员声明
function statements(text) {
  const out = []; let depth = 0; let cur = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '{' || c === '(' || c === '[') depth++;
    else if (c === '}' || c === ')' || c === ']') depth--;
    if (depth === 0 && (c === '\n' || c === ';')) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  out.push(cur);
  return out;
}

// ---------- 2. 类型 / 扩展声明（带嵌套作用域） ----------
const SPANS = [];
const typeDeclRe = /\b(struct|class|enum|actor|extension|protocol)\s+([A-Za-z_]\w*)(\s*<[^{]*?>)?\s*([^{]*?)\{/g;

for (const f of FILES) {
  let m;
  typeDeclRe.lastIndex = 0;
  while ((m = typeDeclRe.exec(f.code))) {
    const kind = m[1], name = m[2];
    const start = m.index;
    const bodyStart = m.index + m[0].length - 1;
    const bodyEnd = matchClose(f.code, bodyStart, '{', '}');
    if (bodyEnd < 0) continue;
    const clause = (m[4] || '').trim();
    const conforms = clause.startsWith(':')
      ? clause.slice(1).split(',').map((s) => s.trim().split(/[\s<]/)[0]).filter(Boolean)
      : [];
    SPANS.push({ kind, name, rel: f.rel, line: lineOf(f.code, start), start, bodyStart, bodyEnd, conforms, mainActor: false, builder: false });
  }
}
// 嵌套：父 = 包含它的最内层类型声明
for (const s of SPANS) {
  let parent = null;
  for (const t of SPANS) {
    if (t === s || t.rel !== s.rel) continue;
    if (s.start > t.bodyStart && s.bodyEnd < t.bodyEnd) {
      if (!parent || (t.bodyEnd - t.bodyStart) < (parent.bodyEnd - parent.bodyStart)) parent = t;
    }
  }
  s.parent = parent;
  s.key = parent ? parent.key + '.' + s.name : s.name;
}

const MAIN_ACTOR_PROTOS = new Set(['View', 'App', 'Scene', 'ViewModifier', 'Shape', 'Layout', 'UIViewRepresentable', 'UIViewControllerRepresentable', 'Commands', 'ToolbarContent', 'AccessibilityRotorContent']);

function prefixOf(f, idx) {
  const lines = f.code.slice(Math.max(0, idx - 400), idx).split('\n');
  const picked = [];
  for (let i = lines.length - 1; i >= 0 && picked.length < 6; i--) {
    const t = lines[i].trim();
    if (!t) { if (picked.length === 0) continue; else break; }
    if (/^(@|private\b|fileprivate\b|internal\b|public\b|open\b|final\b|static\b|class\b|mutating\b|nonisolated\b|override\b|convenience\b|required\b|lazy\b|weak\b|unowned\b|dynamic\b|optional\b|indirect\b)/.test(t)) picked.push(t);
    else break;
  }
  return picked.join(' ');
}

for (const s of SPANS) {
  const f = fileByRel.get(s.rel);
  s.prefix = prefixOf(f, s.start);
  if (/@MainActor/.test(s.prefix)) { s.mainActor = true; s.explicitMainActor = true; }
  if (s.conforms.some((p) => MAIN_ACTOR_PROTOS.has(p))) s.mainActor = true;
  if (s.kind === 'extension') {
    if (MAIN_ACTOR_PROTOS.has(s.name)) s.mainActor = true;
    const base = SPANS.find((t) => t.key === s.key && t.kind !== 'extension');
    if (base && base.mainActor) s.mainActor = true;
    if (base && base.explicitMainActor) s.explicitMainActor = true;
  }
}

// TYPES: key -> 非 extension 声明（extension 只做成员合并）
const TYPES = new Map();
for (const s of SPANS) {
  if (s.kind === 'extension') continue;
  if (!TYPES.has(s.key)) TYPES.set(s.key, s);
}
const EXT_ONLY = new Set();
for (const s of SPANS) {
  if (s.kind !== 'extension') continue;
  if (!TYPES.has(s.key)) EXT_ONLY.add(s.key);
}

const SIMPLE = new Map();   // 简单名 -> [key]
for (const s of SPANS) {
  if (s.kind === 'extension') continue;
  if (!SIMPLE.has(s.name)) SIMPLE.set(s.name, []);
  if (!SIMPLE.get(s.name).includes(s.key)) SIMPLE.get(s.name).push(s.key);
}

function typeAt(rel, idx) {
  let best = null;
  for (const t of SPANS) {
    if (t.rel !== rel) continue;
    if (idx >= t.bodyStart && idx <= t.bodyEnd) {
      if (!best || (t.bodyEnd - t.bodyStart) < (best.bodyEnd - best.bodyStart)) best = t;
    }
  }
  if (!best) return null;
  const base = TYPES.get(best.key);
  return {
    key: best.key, name: best.name, kind: best.kind, rel: best.rel,
    mainActor: !!(best.mainActor || (base && base.mainActor)),          // 上下文用：View 体系也算 MainActor
    explicitMainActor: !!(best.explicitMainActor || (base && base.explicitMainActor)), // 隔离判定用：只认显式标注
  };
}

// ---------- 3. func / init 声明 ----------
const FUNCS = new Map();
const INITS_OWN = new Map();
const INITS_EXT = new Map();
const FUNC_SPANS = [];

function parseParams(txt) {
  const parts = splitTop(txt, ',');
  const out = [];
  for (const raw of parts) {
    let p = raw.trim();
    if (!p) continue;
    let guardN = 0;
    while (/^@\w+(\([^)]*\))?\s+/.test(p) && guardN++ < 6) p = p.replace(/^@\w+(\([^)]*\))?\s+/, '');
    p = p.replace(/^\s*(inout|borrowing|consuming|isolated|sending)\s+/, '');
    const ci = topLevelIndexOf(p, ':');
    if (ci < 0) { out.push({ label: null, name: p, hasDefault: false, variadic: false, type: '' }); continue; }
    const head = p.slice(0, ci).trim();
    const rest = p.slice(ci + 1).trim();
    const toks = head.split(/\s+/).filter(Boolean);
    let label = null;
    if (toks.length >= 2) label = toks[0] === '_' ? null : toks[0];
    else if (toks.length === 1) label = toks[0];
    const eq = topLevelIndexOf(rest, '=');
    const type = (eq >= 0 ? rest.slice(0, eq) : rest).trim();
    out.push({ label, name: toks[toks.length - 1] || head, hasDefault: eq >= 0, variadic: /\.\.\.\s*$/.test(type), type });
  }
  return out;
}

for (const f of FILES) {
  const re = /\bfunc\s+([A-Za-z_]\w*)\s*(<[^(]*?>)?\s*\(/g;
  let m;
  while ((m = re.exec(f.code))) {
    const name = m[1];
    const open = m.index + m[0].length - 1;
    const close = matchClose(f.code, open, '(', ')');
    if (close < 0) continue;
    const params = parseParams(f.code.slice(open + 1, close));
    const prefix = prefixOf(f, m.index);
    const after = f.code.slice(close + 1, close + 300);
    const head = after.split('{')[0];
    const arrow = /->\s*/.exec(head);
    let ret = '';
    if (arrow) ret = head.slice(arrow.index + 2).replace(/\bwhere\b[\s\S]*$/, '').trim();
    const braceIdx = f.code.indexOf('{', close);
    const nlIdx = f.code.indexOf('\n', close);
    let bodyStart = -1, bodyEnd = -1;
    if (braceIdx >= 0 && (nlIdx < 0 || braceIdx <= nlIdx + 1)) {
      bodyEnd = matchClose(f.code, braceIdx, '{', '}');
      bodyStart = braceIdx;
    }
    const sig = {
      kind: 'func', name, labels: params.map((p) => p.label), params,
      rel: f.rel, line: lineOf(f.code, m.index),
      mainActor: /@MainActor/.test(prefix),
      nonisolated: /nonisolated/.test(prefix),
      isStatic: /\bstatic\b|\bclass\b/.test(prefix),
      isAsync: /\basync\b/.test(head),
      returns: ret, start: m.index,
    };
    if (!FUNCS.has(name)) FUNCS.set(name, []);
    FUNCS.get(name).push(sig);
    if (bodyStart >= 0) FUNC_SPANS.push({ rel: f.rel, start: m.index, bodyStart, bodyEnd, name, mainActor: sig.mainActor, isAsync: sig.isAsync });
  }
  const re2 = /\binit\s*(\?|!)?\s*(<[^(]*?>)?\s*\(/g;
  while ((m = re2.exec(f.code))) {
    const open = m.index + m[0].length - 1;
    const close = matchClose(f.code, open, '(', ')');
    if (close < 0) continue;
    const t = typeAt(f.rel, m.index);
    if (!t) continue;
    const params = parseParams(f.code.slice(open + 1, close));
    const sig = { kind: 'init', name: t.name, labels: params.map((p) => p.label), params, rel: f.rel, line: lineOf(f.code, m.index), mainActor: /@MainActor/.test(prefixOf(f, m.index)) };
    const box = t.kind === 'extension' ? INITS_EXT : INITS_OWN;
    if (!box.has(t.key)) box.set(t.key, []);
    box.get(t.key).push(sig);
  }
}

// ---------- 4. 成员（存储 / 计算 / case / 嵌套 / func），extension 合并进基类型 ----------
const MEMBERS = new Map();
function membersOf(key) {
  if (!MEMBERS.has(key)) MEMBERS.set(key, { stored: new Set(), letProps: new Set(), computed: new Set(), cases: new Set(), funcs: new Set(), nested: new Set() });
  return MEMBERS.get(key);
}
const PROP_RE = /^(@\w+(\([^)]*\))?\s+)*((?:public|private|fileprivate|internal|static|class|final|lazy|weak|unowned|nonisolated|override|dynamic)\s+)*(let|var)\s+([A-Za-z_]\w*)\s*(?::\s*([^={\n]+))?\s*(=)?/;
const WRAPPER_RE = /@(State|Binding|AppStorage|SceneStorage|ObservedObject|ScalableMetric|ScaledMetric|Environment|EnvironmentObject|StateObject|FocusState|Namespace|FetchRequest|Query|GestureState|Published)\b/;

for (const t of SPANS) {
  if (t.kind === 'protocol') continue;
  const f = fileByRel.get(t.rel);
  if (!f) continue;
  const mem = membersOf(t.key);
  const body = f.code.slice(t.bodyStart + 1, t.bodyEnd);
  for (const raw of statements(body)) {
    const trimmed = raw.trim();
    const pm = PROP_RE.exec(trimmed);
    if (pm && !/\bfunc\b/.test(trimmed)) {
      const isLet = pm[4] === 'let';
      const name = pm[5];
      const rest = trimmed.slice(pm[0].length);
      if (/\{/.test(rest)) mem.computed.add(name);
      else {
        mem.stored.add(name);
        if (isLet) mem.letProps.add(name);
      }
      if (/@(ViewBuilder|ToolbarContentBuilder|CommandsBuilder|SceneBuilder|TableColumnBuilder|AccessibilityRotorContentBuilder)\b/.test(trimmed)) t.builder = true;
      for (const mm of trimmed.matchAll(/,\s*([A-Za-z_]\w*)\s*=/g)) { mem.stored.add(mm[1]); if (isLet) mem.letProps.add(mm[1]); }
    }
    const cm = /^case\s+(.+)$/.exec(trimmed);
    if (cm) for (const part of splitTop(cm[1], ',')) {
      const nm = /^\s*([A-Za-z_]\w*)/.exec(part);
      if (nm) mem.cases.add(nm[1]);
    }
    const nm2 = /^(?:public |private |fileprivate |internal )?(?:final )?(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_]\w*)/.exec(trimmed);
    if (nm2) mem.nested.add(nm2[1]);
  }
}

// func 归属类型（按行首偏移）
for (const [name, sigs] of FUNCS) {
  for (const s of sigs) {
    const f = fileByRel.get(s.rel);
    if (!f) continue;
    const lineStart = f.lines.slice(0, s.line - 1).join('\n').length;
    const t = typeAt(s.rel, lineStart + 4);
    if (t) {
      s.typeKey = t.key;
      membersOf(t.key).funcs.add(name);
      // 只有**显式** @MainActor 的类型才让成员方法变成隔离的；View 体系是隐式的，构造器并不隔离
      if (t.explicitMainActor) s.mainActor = true;
    }
  }
}

// ---------- 5. 构造签名 ----------
const CTORS = new Map();   // key -> [sig]
for (const t of SPANS) {
  if (t.kind !== 'struct' && t.kind !== 'actor') continue;
  if (INITS_OWN.has(t.key)) continue;          // 同一声明体内的 init 才会压制成员逐一初始化器
  if (t.builder) continue;                     // 有 result builder 属性，合成签名对不上
  const f = fileByRel.get(t.rel);
  if (!f) continue;
  const mem = membersOf(t.key);
  if (!mem.stored.size) continue;
  const params = [];
  for (const raw of statements(f.code.slice(t.bodyStart + 1, t.bodyEnd))) {
    const trimmed = raw.trim();
    const pm = PROP_RE.exec(trimmed);
    if (!pm || /\bfunc\b/.test(trimmed) || /\{/.test(trimmed.slice(pm[0].length))) continue;
    const attrs = trimmed.slice(0, trimmed.indexOf(pm[4] + ' '));
    // 没有类型标注的属性（@Environment(\.x) var y / var z = 5）签名里判不了类型，也不可能是必填 —— 直接不进参数表
    if (!pm[6] || !pm[6].trim()) continue;
    // 属性包装器不参与必填约束：AddLockScreen() 在 e45c804 编译通过，而它有 4 个 @State 可选属性
    const wrapped = WRAPPER_RE.test(attrs);
    params.push({ label: pm[5], name: pm[5], hasDefault: !!pm[7] || wrapped, variadic: false, type: pm[6].trim(), wrapped });
  }
  if (!params.length) continue;
  const synth = [{ kind: 'init', name: t.name, labels: params.map((p) => p.label), params, rel: t.rel, line: t.line, mainActor: !!t.explicitMainActor, synthesized: true }];
  // 扩展里的 init 不压制成员逐一初始化器 —— 两者并存，签名不唯一时调用点自然跳过判定
  const all = INITS_EXT.has(t.key) ? synth.concat(INITS_EXT.get(t.key)) : synth;
  CTORS.set(t.key, all);
}
// 同一声明体内的 init 与扩展里的 init 并存（扩展不会压制成员逐一初始化器）
for (const [key, sigs] of INITS_OWN) CTORS.set(key, sigs.concat(INITS_EXT.get(key) || []));

function ctorKeys(simpleName) {
  const keys = (SIMPLE.get(simpleName) || []).filter((k) => CTORS.has(k));
  return keys.length === 1 ? keys : [];
}

// ---------- 6. 调用点 ----------
const findings1 = [];
const findings2 = [];
let callChecked = 0;
const SKIP_WORD = /(func|class|struct|enum|actor|protocol|extension|typealias|import|case|let|var|inout|operator|precedencegroup|associatedtype|subscript|return)\s+$/;

for (const f of FILES) {
  const re = /([A-Za-z_]\w*)\s*\(/g;
  let m;
  while ((m = re.exec(f.code))) {
    const name = m[1];
    const at = m.index;
    const prevChar = at > 0 ? f.code[at - 1] : '';
    if (prevChar === '.' || prevChar === '@' || prevChar === '#' || /\w/.test(prevChar)) continue;
    if (SKIP_WORD.test(f.code.slice(Math.max(0, at - 18), at))) continue;

    const cKeys = ctorKeys(name);
    const isCtor = cKeys.length === 1;
    const isFunc = FUNCS.has(name);
    if (isFunc && isCtor) continue;
    const sigs = isCtor ? CTORS.get(cKeys[0]) : (isFunc ? FUNCS.get(name) : null);
    if (!sigs || sigs.length !== 1) continue;         // 重载 / 歧义 -> 不判
    const sig = sigs[0];


    const open = at + name.length;
    const close = matchClose(f.code, open, '(', ')');
    if (close < 0) continue;
    const argText = f.code.slice(open + 1, close);
    if (/[{}]/.test(argText)) continue;               // 含闭包 / 字典字面量，静态判不准
    const rawArgs = argText.trim() === '' ? [] : splitTop(argText, ',').map((s) => s.trim());
    const args = rawArgs.map((a) => {
      const lm = /^([A-Za-z_]\w*)\s*:(?!:)/.exec(a);
      return { label: lm ? lm[1] : null, text: a, trailing: false };
    });
    const lastParam = sig.params[sig.params.length - 1];
    if (lastParam && /->/.test(lastParam.type || '')) {
      let j = close + 1;
      while (j < f.code.length && /\s/.test(f.code[j])) j++;
      if (f.code[j] === '{') args.push({ label: null, text: '{…}', trailing: true });
    }
    callChecked++;

    const where = f.rel + ':' + lineOf(f.code, at);
    const P = sig.params;
    const desc = () => sig.labels.map((l) => (l === null ? '_' : l)).join(', ');
    let cursor = 0;
    let broke = false;

    for (let i = 0; i < args.length && !broke; i++) {
      const a = args[i];
      if (a.trailing) {
        const last = P.length - 1;
        const skipped = P.slice(cursor, last).filter((p) => !p.hasDefault && !p.variadic && !/->/.test(p.type || ''));
        if (skipped.length) {
          findings1.push(where + '  ' + name + ' trailing closure 之前缺参数 ' + skipped.map((p) => (p.label === null ? '_' : p.label + ':')).join(', '));
          broke = true;
        }
        cursor = P.length;
        continue;
      }
      if (a.label === null) {
        if (cursor >= P.length) {
          findings1.push(where + '  ' + name + ' 多出位置实参（声明只有 ' + P.length + ' 个参数：' + desc() + '）');
          broke = true;
          continue;
        }
        const p = P[cursor];
        if (p.label !== null) {
          findings1.push(where + '  ' + name + ' 第 ' + (i + 1) + ' 个实参缺标签，声明要求 "' + p.label + ':"');
          broke = true;
          continue;
        }
        if (!p.variadic) cursor++;
        continue;
      }
      let j = -1;
      for (let k = cursor; k < P.length; k++) if (P[k].label === a.label) { j = k; break; }
      if (j < 0) {
        const earlier = P.findIndex((p) => p.label === a.label);
        if (earlier >= 0) findings1.push(where + '  ' + name + ' 参数 "' + a.label + ':" 出现在已消费的参数之后（声明顺序：' + desc() + '）');
        else findings1.push(where + '  ' + name + ' 多出参数 "' + a.label + ':"（声明参数：' + desc() + '）');
        broke = true;
        continue;
      }
      const skipped = P.slice(cursor, j).filter((p) => !p.hasDefault && !p.variadic && !/->/.test(p.type || ''));
      if (skipped.length) {
        findings1.push(where + '  ' + name + ' 缺参数 ' + skipped.map((p) => (p.label === null ? '_' : p.label + ':')).join(', ') + '（在 "' + a.label + ':" 之前）');
        broke = true;
        continue;
      }
      cursor = j + 1;
    }
    if (broke) continue;
    if (cursor < P.length) {
      const rest = P.slice(cursor).filter((p) => !p.hasDefault && !p.variadic && !/->/.test(p.type || ''));
      if (rest.length) findings1.push(where + '  ' + name + ' 缺参数 ' + rest.map((p) => (p.label === null ? '_' : p.label + ':')).join(', ') + '（声明 ' + desc() + '）');
    }

    // R3 @MainActor 隔离
    if (sig.mainActor) {
      const caller = FUNC_SPANS.filter((s) => s.rel === f.rel && at >= s.bodyStart && at <= s.bodyEnd)
        .sort((a, b) => (a.bodyEnd - a.bodyStart) - (b.bodyEnd - b.bodyStart))[0];
      const t = typeAt(f.rel, at);
      if (!caller && !t) continue;                    // 顶层 / #Preview 宏体：不判
      const ctxMain = (caller && caller.mainActor) || (t && t.mainActor);
      if (ctxMain || sig.nonisolated) continue;
      if (/Task\s*(\.detached)?\s*\{[^}]*$/.test(f.code.slice(Math.max(0, at - 400), at))) continue;
      const lineText = f.rawLines[lineOf(f.code, at) - 1] || '';
      if (caller && !caller.isAsync) {
        findings1.push(where + '  ' + name + ' 是 @MainActor，调用方 ' + caller.name + ' 是同步 nonisolated 上下文');
      } else if (!/\bawait\b/.test(lineText)) {
        findings1.push(where + '  ' + name + ' 是 @MainActor，调用方非 MainActor 且此处没有 await');
      }
    }
  }
}

// ---------- 7. let 存储属性被赋值 ----------
for (const f of FILES) {
  const localTypes = new Map();
  for (const m of f.code.matchAll(/\b(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*\[([A-Za-z_]\w*)\]/g)) {
    if (SIMPLE.has(m[2])) localTypes.set(m[1], m[2]);
  }
  for (const m of f.code.matchAll(/\b(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*([A-Z][A-Za-z0-9_]*)\b/g)) {
    if (!localTypes.has(m[1]) && SIMPLE.has(m[2])) localTypes.set(m[1], m[2]);
  }
  for (const m of f.code.matchAll(/([A-Za-z_]\w*)\s*:\s*([A-Z][A-Za-z0-9_]*)\s*[,)]/g)) {
    if (!localTypes.has(m[1]) && SIMPLE.has(m[2])) localTypes.set(m[1], m[2]);
  }
  for (const m of f.code.matchAll(/([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*\.\s*([A-Za-z_]\w*)\s*(?:=|\+=|-=|\*=)(?!=)/g)) {
    const base = m[1], prop = m[3];
    const ty = localTypes.get(base);
    if (!ty) continue;
    for (const key of SIMPLE.get(ty)) {
      const mem = MEMBERS.get(key);
      if (mem && mem.letProps.has(prop)) findings1.push(f.rel + ':' + lineOf(f.code, m.index) + '  ' + base + '.' + prop + ' 被赋值，但 ' + key + '.' + prop + ' 声明为 let');
    }
  }
}

// ---------- 8. 无标签 tuple 的成员访问 ----------
const TUPLE_FUNCS = [];
for (const [name, sigs] of FUNCS) {
  if (sigs.length !== 1) continue;
  const s = sigs[0];
  if (!s.returns) continue;
  let rt = s.returns.trim();
  const rm = /^Result\s*<\s*(\([^)]*\))/.exec(rt);
  if (rm) rt = rm[1];
  if (!/^\(.*\)$/.test(rt)) continue;
  const inner = rt.slice(1, rt.lastIndexOf(')'));
  const parts = splitTop(inner, ',').map((x) => x.trim()).filter(Boolean);
  if (parts.length < 2) continue;
  if (parts.some((p) => /^[A-Za-z_]\w*\s*:/.test(p))) continue;
  TUPLE_FUNCS.push({ name, labels: parts });
}
for (const f of FILES) {
  for (const tf of TUPLE_FUNCS) {
    const callRe = new RegExp('\\b' + tf.name + '\\s*\\(', 'g');
    let cm;
    while ((cm = callRe.exec(f.code))) {
      const open = cm.index + cm[0].length - 1;
      const close = matchClose(f.code, open, '(', ')');
      if (close < 0) continue;
      let bind = null;
      const before = f.code.slice(Math.max(0, cm.index - 240), cm.index);
      const lb = /\blet\s+([A-Za-z_]\w*)\s*(?::[^=\n]*)?=\s*(?:await\s+)?(?:try\s*[?!]?\s*)?[\w.\[\]]*\.?$/.exec(before);
      if (lb) bind = lb[1];
      if (!bind) {
        const b2 = /case\s+\.success\s*\(\s*let\s+([A-Za-z_]\w*)\s*\)/.exec(f.code.slice(close, close + 3000));
        if (b2) bind = b2[1];
      }
      if (!bind) continue;
      const useRe = new RegExp('\\b' + bind + '\\s*\\.\\s*([A-Za-z_]\\w*)', 'g');
      let um;
      while ((um = useRe.exec(f.code))) {
        findings1.push(f.rel + ':' + lineOf(f.code, um.index) + '  ' + bind + '.' + um[1] + ' —— ' + tf.name + '() 返回无标签 tuple (' + tf.labels.join(', ') + ')，没有成员 .' + um[1] + '（用 .0/.1）');
      }
    }
  }
}

// ---------- 9. 类型名.成员（R6 静态访问）/ 局部变量.成员（R7） ----------
function enclosingFuncSpan(rel, idx) {
  let best = null;
  for (const s of FUNC_SPANS) {
    if (s.rel !== rel) continue;
    if (idx >= s.bodyStart && idx <= s.bodyEnd) {
      if (!best || (s.bodyEnd - s.bodyStart) < (best.bodyEnd - best.bodyStart)) best = s;
    }
  }
  return best;
}
const SYNTH = new Set(['rawValue', 'allCases', 'hashValue', 'description', 'debugDescription', 'init', 'self', 'newValue', 'oldValue', 'wrappedValue', 'projectedValue', 'Type', 'Protocol']);
const ALL_MEMBERS = new Set();
for (const mem of MEMBERS.values()) for (const set of [mem.stored, mem.computed, mem.cases, mem.funcs, mem.nested]) for (const x of set) ALL_MEMBERS.add(x);

for (const f of FILES) {
  const localTypes = new Map();
  for (const m of f.code.matchAll(/\b(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*([A-Z][A-Za-z0-9_]*)\b/g)) {
    if (SIMPLE.has(m[2]) && !EXT_ONLY.has(m[2])) localTypes.set(m[1], m[2]);
  }
  for (const m of f.code.matchAll(/([A-Za-z_]\w*)\s*:\s*([A-Z][A-Za-z0-9_]*)\s*[,)]/g)) {
    if (!localTypes.has(m[1]) && SIMPLE.has(m[2]) && !EXT_ONLY.has(m[2])) localTypes.set(m[1], m[2]);
  }
  for (const m of f.code.matchAll(/([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)/g)) {
    const base = m[1], prop = m[2];
    if (prop.startsWith('$') || prop.startsWith('_')) continue;
    if (SYNTH.has(prop)) continue;
    const where = f.rel + ':' + lineOf(f.code, m.index);

    // R6：base 是仓内类型名 -> 静态访问
    if (/^[A-Z]/.test(base) && SIMPLE.has(base)) {
      const keys = SIMPLE.get(base);
      if (keys.length === 1) {
        const key = keys[0];
        if (!EXT_ONLY.has(key)) {
          const mem = MEMBERS.get(key);
          if (mem && !mem.stored.has(prop) && !mem.computed.has(prop) && !mem.cases.has(prop) && !mem.funcs.has(prop) && !mem.nested.has(prop)) {
            findings1.push(where + '  ' + base + '.' + prop + ' —— ' + key + ' 没有成员 ' + prop);
          }
        }
      }
      continue;
    }
    // R7：局部变量 -> 只在「同一个函数体里有唯一类型标注」时才判（文件级解析会被同名参数带偏）
    const scope = enclosingFuncSpan(f.rel, m.index);
    if (!scope) continue;
    const scopeText = f.code.slice(scope.bodyStart, scope.bodyEnd);
    const tys = new Set();
    // 只认「声明位」的类型标注：( / , / let / var 之后，且类型名后紧跟 , ) = 或空白。
    // 三元表达式里的 `? raw : PidMap.productName` 不是标注 —— 早期版本在这里误报过。
    const annRe = new RegExp('(?:[(,]|\\blet\\s+|\\bvar\\s+|\\bfunc\\s+\\w+\\s*\\()\\s*' + base + '\\s*:\\s*([A-Z][A-Za-z0-9_]*)\\s*(?=[,)={\\n])', 'g');
    let am;
    while ((am = annRe.exec(scopeText))) tys.add(am[1]);
    if (tys.size !== 1) continue;
    const ty = [...tys][0];
    if (!SIMPLE.has(ty)) continue;
    const key = SIMPLE.get(ty)[0];
    if (!key || EXT_ONLY.has(key)) continue;
    const mem = MEMBERS.get(key);
    if (!mem) continue;
    if (mem.stored.has(prop) || mem.computed.has(prop) || mem.cases.has(prop) || mem.funcs.has(prop) || mem.nested.has(prop)) continue;
    if (ALL_MEMBERS.has(prop)) continue;
    findings2.push(where + '  ' + base + '.' + prop + ' —— ' + key + ' 没有成员 ' + prop + '，全仓也没有同名成员');
  }
}

// ---------- 输出 ----------
const uniq = (arr) => [...new Set(arr)];
const f1 = uniq(findings1);
const f2 = uniq(findings2);

console.log('callsig2: ' + FILES.length + ' 个文件，' + FUNCS.size + ' 个 func，' + CTORS.size + ' 个构造签名，检查 ' + callChecked + ' 处调用');
if (f2.length) {
  console.log('callsig2: 提示 ' + f2.length + ' 条（tier-2，不判红）');
  for (const x of f2.slice(0, 25)) console.log('  · ' + x);
  if (f2.length > 25) console.log('  · …还有 ' + (f2.length - 25) + ' 条');
}
if (f1.length === 0) {
  console.log('callsig2: OK — 标签/参数个数/@MainActor 隔离/let 赋值/tuple 成员/静态成员全部通过');
  process.exit(0);
}
console.log('callsig2: FAIL — ' + f1.length + ' 处高置信度问题\n');
for (const x of f1) console.log('  ' + x);
process.exit(1);
