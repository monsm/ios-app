#!/usr/bin/env node
// tools/entrymap.js —— 页面入口审计（第 34 道闸门，**判失败**）
//
// 由来：2026-10-24 用户问「每个功能点是不是都在页面、页面被合理归位、是否有入口」。
// 手查发现 5 个页面级 View 零入口（3 个是被 2026-10-21「全新重写」取代的旧页、
// 2 个是同一功能点的重复实现），以及 QuickPool 快捷格指向旧页 —— 用户从入口进去
// 看到的取决于哪套被引用。
//
// 本工具强制三条：
//   ① 每个页面级 View（*Page/*View/*Studio/*Dashboard/*Console/*Picker/*Sheet/*Wizard）
//      必须至少有 1 个**真调用点**（Name( 或 Name {），排除定义行与注释行
//   ② 排除 QuickPool.swift（它是快捷格数据源，用这些 View 渲染预览图，不是真入口）
//   ③ 报多入口清单（不判失败）—— 多入口不一定是错（同一页从不同语境可达是设计），
//      但超过 2 个通常意味着「同一功能点散落多处菜单」，需要人读
//
// 已知豁免：X 前缀（组件库）、ToastView/MomentCardView 这类覆盖层组件、
//          RootView（App 根）。

'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function swiftFiles(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) swiftFiles(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const files = swiftFiles(APP);
const srcMap = {};
for (const f of files) srcMap[path.basename(f)] = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');

// 页面级命名后缀
const PAGE = /(Page|View|Studio|Dashboard|Console|Picker|Sheet|Wizard)$/;
// 豁免：根视图 / 覆盖层组件 / 已知共享组件
const EXEMPT = new Set(['RootView', 'ToastView', 'MomentCardView', 'XGlassTabBar',
                        'AlarmShareCardView', 'RecordShareCardView', 'FpOwnerPicker',
                        'CodeScanSheet', 'ReportScanSheet']);

const pageViews = [];
for (const [f, s] of Object.entries(srcMap)) {
  for (const m of s.matchAll(/struct (\w+): View\b/g)) {
    const n = m[1];
    if (!PAGE.test(n)) continue;
    if (n.startsWith('X')) continue;
    if (EXEMPT.has(n)) continue;
    pageViews.push({ name: n, file: f });
  }
}

function entryCount(name) {
  const out = [];
  for (const [f, s] of Object.entries(srcMap)) {
    if (f === 'QuickPool.swift') continue;          // 数据源，不是入口
    const lines = s.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (/^\s*\/\//.test(lines[i])) continue;    // 注释不算
      if (new RegExp('struct ' + name + '\\b').test(lines[i])) continue;   // 定义行不算
      if (new RegExp('\\b' + name + '\\s*[({]').test(lines[i])) out.push(f + ':' + (i + 1));
    }
  }
  return out;
}

const zero = [], multi = [];
for (const p of pageViews) {
  const e = entryCount(p.name);
  if (e.length === 0) zero.push(p.name + '  (' + p.file + ')');
  else if (e.length > 2) multi.push(p.name + '  ×' + e.length + '  ' + e.join(' '));
}

console.log('页面级 View ' + pageViews.length + ' 个（扫 ' + files.length + ' 个 .swift）');

if (zero.length === 0) {
  console.log('✓ 每个页面都有入口');
} else {
  console.log('✗ 零入口页面 ' + zero.length + ' 个 —— 定义了却没有任何调用点：');
  zero.forEach(z => console.log('  · ' + z));
}

if (multi.length) {
  console.log('· 多入口（>2，需人读是否重复菜单）' + multi.length + ' 个：');
  multi.forEach(m => console.log('  · ' + m));
}

process.exit(zero.length === 0 ? 0 : 1);
