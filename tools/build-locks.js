#!/usr/bin/env node
// ============================================================================
// build-locks.js — 把 docs/redesign/locks/*.js 里的所有设计汇总成一个总览页
// ============================================================================
//
// 5 个设计子代理各写一个文件，导出 DESIGNS 数组。
// 这个脚本把它们全部读进来（去掉 import/export 语句），拼成一个场景模块，
// 再套上离线外壳（three.js 内联 + Blob URL + importmap）。
//
// 用法: node tools/build-locks.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const LOCKDIR = path.join(ROOT, 'docs', 'redesign', 'locks');
const OUT = path.join(ROOT, 'docs', 'redesign', 'locks-gallery.html');

const VENDOR = path.join(ROOT, '.vendor3d');
const three = fs.readFileSync(path.join(VENDOR, 'three.js'), 'utf8');
const orbit = fs.readFileSync(path.join(VENDOR, 'orbit.js'), 'utf8');
const room = fs.readFileSync(path.join(VENDOR, 'room.js'), 'utf8');

// ── 收集所有设计文件 ──
const files = fs.readdirSync(LOCKDIR)
  .filter((f) => f.endsWith('.js') && !f.startsWith('_'))
  .sort();

if (!files.length) {
  console.error('没有找到设计文件（docs/redesign/locks/*.js）');
  process.exit(1);
}

console.log('设计文件: ' + files.length + ' 个');
let total = 0;
const parts = [];
const meta = [];

for (const f of files) {
  let src = fs.readFileSync(path.join(LOCKDIR, f), 'utf8');

  // 去掉 import 语句（three 由外层统一提供）
  src = src.replace(/^\s*import\s+\*\s+as\s+THREE\s+from\s+['"]three['"];?\s*$/gm, '');
  src = src.replace(/^\s*import\s+[^;]+from\s+['"][^'"]+['"];?\s*$/gm, '');

  // 把 export const DESIGNS = [...] 改成 const DESIGNS_N = [...]
  const idx = files.indexOf(f);
  const varName = 'DESIGNS_' + idx;
  const hadExport = /export\s+const\s+DESIGNS\s*=/.test(src);
  src = src.replace(/export\s+const\s+DESIGNS\s*=/, 'const ' + varName + ' =');
  if (!hadExport) {
    console.error('  ✗ ' + f + ': 没有找到 export const DESIGNS =');
    process.exit(1);
  }

  // 检查禁用的几何 —— 必须**先剥掉注释**再查,
  // 否则注释里写 "No ExtrudeGeometry" 这种承诺会被误判成使用了它。
  const codeOnly = src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/\/\/[^\n]*$/gm, '');
  const banned = ['TorusGeometry', 'ExtrudeGeometry', 'LatheGeometry', 'TubeGeometry'];
  for (const b of banned) {
    if (codeOnly.includes(b)) {
      console.error('  ✗ ' + f + ': 使用了 iOS 做不出来的 ' + b);
      process.exit(1);
    }
  }

  parts.push('// ═══════════════════════════════════════════════════════════');
  parts.push('// ' + f);
  parts.push('// ═══════════════════════════════════════════════════════════');
  parts.push('(function(){');
  parts.push(src);
  parts.push('window.__DESIGNS = (window.__DESIGNS || []).concat(' + varName + ');');
  parts.push('})();');

  // 粗略统计（用于报告）
  const n = (src.match(/\{[\s\S]*?id:\s*'([^']+)'/g) || []).length;
  meta.push({ file: f, count: n });
  total += n;
}

console.log('设计总数: 约 ' + total + ' 个');
meta.forEach((m) => console.log('  ' + m.file + ': ~' + m.count));

const scene = parts.join('\n');

// ── 校验不能有 </script> ──
if (/<\/script/i.test(scene)) {
  console.error('设计代码里含 </script>，无法安全内联');
  process.exit(1);
}

const CSS = fs.readFileSync(path.join(ROOT, '.lock-gallery.css'), 'utf8');
const BODY = fs.readFileSync(path.join(ROOT, '.lock-gallery.body.html'), 'utf8');
const BOOT = fs.readFileSync(path.join(ROOT, '.lock-gallery.boot.js'), 'utf8');

const html = [
  '<!DOCTYPE html>',
  '<html lang="zh-CN">',
  '<head>',
  '<meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width,initial-scale=1">',
  '<title>锁体设计总览</title>',
  '<style>' + CSS + '</style>',
  '</head>',
  '<body>',
  BODY,
  '',
  '<script type="text/plain" id="vendor-three">' + three + '</script>',
  '<script type="text/plain" id="vendor-orbit">' + orbit + '</script>',
  '<script type="text/plain" id="vendor-room">' + room + '</script>',
  '<script type="text/plain" id="vendor-scene">' + scene + '</script>',
  '',
  '<script type="module">' + BOOT + '</script>',
  '</body>',
  '</html>',
].join('\n');

fs.writeFileSync(OUT, html, 'utf8');
console.log('\n已生成: ' + OUT);
console.log('大小: ' + (html.length / 1024 / 1024).toFixed(2) + ' MB');
