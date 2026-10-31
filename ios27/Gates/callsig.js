#!/usr/bin/env node
// callsig.js —— 共享组件的调用签名闸门。
//
// 为什么需要它：Swift 要求具名实参**按声明顺序**出现。这类错误（参数顺序错、
// 标签拼错）本地没编译器时查不出来，只能等云端编译红了才知道，一次往返十几分钟。
//
// 判什么：具名实参顺序与声明一致。
// 不判什么：缺参数 —— trailing closure 会补最后一个参数，静态判不准，宁可漏报不误报。
//
// 数据来源：解析 Design/Components/ 里的 struct 声明（**深度感知**：跳过嵌套 struct，
// 否则 ReadingGrid 内嵌的 Item 字段会被当成 ReadingGrid 自身的参数）。
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

// ---------- 1. 解析组件签名（深度感知） ----------
const SIGNATURES = {};
for (const f of walk(path.join(APP, 'Design', 'Components'))) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  let depth = 0;
  let current = null;
  let structDepth = -1;
  for (const line of lines) {
    const structM = /^struct\s+(\w+)\s*(?:<[^>]*>)?\s*:\s*View\s*\{/.exec(line);
    if (structM && !current) {
      current = { name: structM[1], params: [] };
      SIGNATURES[structM[1]] = current;
      structDepth = depth;
    } else if (current && depth === structDepth + 1) {
      // 只在 struct 的直接层看属性；嵌套 struct / 函数体都在更深的层
      const propM = /^\s*(?:var|let)\s+(\w+)\s*:\s*([^=]+?)\s*(=.*)?$/.exec(line);
      if (propM && !/\bbody\b/.test(propM[1])) {
        current.params.push(propM[1]);
      }
    }
    for (const c of line) {
      if (c === '{') depth++;
      else if (c === '}') {
        depth--;
        if (current && depth === structDepth) { current = null; structDepth = -1; }
      }
    }
  }
}

const tracked = Object.keys(SIGNATURES).filter((k) => SIGNATURES[k].params.length >= 2);

// ---------- 2. 扫调用 ----------
const findings = [];
let checked = 0;

for (const f of walk(APP)) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  if (rel.startsWith('Design/Components/')) continue;
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  for (const name of tracked) {
    const order = SIGNATURES[name].params;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (/\bstruct\s+' + name/.test(line)) continue;
      const startRe = new RegExp('(?<![\\w.])' + name + '\\(\\s*(?:$|\\w+\\s*:)');
      if (!startRe.test(line)) continue;

      const chunk = lines.slice(i, i + 10).join(' ');
      const startIdx = chunk.search(new RegExp('(?<![\\w.])' + name + '\\(', 'g'));
      if (startIdx < 0) continue;
      // 截到第一个 ')' 之前的这一段（调用实参区）
      const tail = chunk.slice(startIdx + name.length + 1);
      const closeIdx = tail.indexOf(')');
      const argZone = closeIdx >= 0 ? tail.slice(0, closeIdx) : tail;

      const usedLabels = [...argZone.matchAll(/(?<![\\w.])(\w+)\s*:\s/g)].map((m) => m[1]).filter((l) => order.includes(l));
      if (usedLabels.length < 2) continue;
      checked++;

      const idxs = usedLabels.map((l) => order.indexOf(l));
      for (let k = 1; k < idxs.length; k++) {
        if (idxs[k] < idxs[k - 1]) {
          findings.push({ file: rel, line: i + 1, why: name + ' 实参顺序错：' + usedLabels.join(', ') + '（声明 ' + order.join(', ') + '）' });
          break;
        }
      }
    }
  }
}

console.log('callsig: 跟踪 ' + tracked.length + ' 个组件，检查 ' + checked + ' 处具名调用');
if (findings.length === 0) {
  console.log('callsig: OK — 全部调用的实参顺序符合声明');
  process.exit(0);
}
console.log('callsig: FAIL — ' + findings.length + ' 处\n');
for (const f of findings) console.log('  ' + f.file + ':' + f.line + '  ' + f.why);
process.exit(1);
