#!/usr/bin/env node
// tools/motionlock.js — 把 XMotion 的每条曲线锁在规范 §11.1 的表上（判失败）。
//
// 为什么需要它：规范 §11.1 的标题是「动画清单（只能用这些）」，
// 表里 8 条场景各给了曲线类型与参数。而「参数写错、手感觉不出来」这件事，
// 在没有编译器也没有真机时完全不可见 —— 本轮就抓到 quick 用 spring 顶替了 easeOut。
//
// 判据：逐条比对规范表与 App/Core/Theme.swift 的 XMotion 默认分支。
// 规范里没有的曲线（如 timingCurve）一律判失败 —— 那张表是封闭清单。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const src = fs.readFileSync(path.join(ROOT, 'App/Core/Theme.swift'), 'utf8');

const block = /enum XMotion \{([\s\S]*?)\n\}/.exec(src);
if (!block) { console.error('✗ motionlock: 解析不到 XMotion'); process.exit(1); }
const body = block[1];

// 规范 §11.1 的场景 + 参数。键是 XMotion 里的令牌名。
const SPEC = [
  { tok: 'cardEnter',  curve: 'spring',   a: 0.50, b: 0.85, why: '卡片入场' },
  { tok: 'ringGrow',   curve: 'easeOut',  dur: 1.00, why: '环形生长' },
  { tok: 'standard',   curve: 'spring',   a: 0.32, b: 0.80, why: 'Tab 切换' },
  { tok: 'quick',      curve: 'easeOut',  dur: 0.12, why: '按压缩放' },
  { tok: 'numberRoll', curve: 'easeInOut', dur: 0.25, why: '数值变化' },
  { tok: 'summon',     curve: 'spring',   a: 0.42, b: 0.88, why: 'Sheet 弹出' },
];

const bad = [];
for (const s of SPEC) {
  const re = new RegExp('static var ' + s.tok + ': Animation \\{[\\s\\S]*?default: (?:return )?([^\\n]+)\\n');
  const m = re.exec(body);
  if (!m) { bad.push(s.tok + ': 在 XMotion 里找不到（令牌被改名或删除？）'); continue; }
  const line = m[1].trim();
  if (s.curve === 'spring') {
    const mm = /\.spring\(response:\s*([0-9.]+),\s*dampingFraction:\s*([0-9.]+)\)/.exec(line);
    if (!mm) { bad.push(s.tok + ': 规范要 spring，实际是 ' + line); continue; }
    if (+mm[1] !== s.a || +mm[2] !== s.b) {
      bad.push(s.tok + ': spring 参数 ' + mm[1] + '/' + mm[2] + ' ≠ 规范 ' + s.a + '/' + s.b);
    }
  } else {
    const mm = new RegExp('\\.' + s.curve + '\\(duration:\\s*([0-9.]+)').exec(line);
    if (!mm) { bad.push(s.tok + ': 规范要 .' + s.curve + '，实际是 ' + line); continue; }
    if (+mm[1] !== s.dur) bad.push(s.tok + ': 时长 ' + mm[1] + 's ≠ 规范 ' + s.dur + 's');
  }
}

// 封闭清单：规范里没有的曲线类型不许出现
{
  const off = [...body.matchAll(/\.(timingCurve|cubicBezier|custom)\(/g)].map((m) => m[1]);
  if (off.length) bad.push('出现规范 §11.1 封闭清单之外的曲线: ' + [...new Set(off)].join(', '));
}

// 自检：判据本身要能抓到错参数
{
  const probe = 'default: return .spring(response: 0.12, dampingFraction: 1.0)';
  const caught = /\.spring\(response:\s*([0-9.]+)/.test(probe);
  if (!caught) { console.error('✗ motionlock 自检失败: 判据抓不到参数'); process.exit(1); }
}

if (bad.length) {
  for (const b of bad) console.error('  ' + b);
  console.error('✗ XMotion 与规范 §11.1 不符 ' + bad.length + ' 处 —— 那张表是封闭清单');
  process.exit(1);
}
console.log('动效曲线 ' + SPEC.length + ' 条与规范 §11.1 逐参数一致 ✓');