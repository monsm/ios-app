#!/usr/bin/env node
// destmap.js —— Dest 台账 ↔ 实现 一一对应。
// 多一个 Dest 没有实现，会导航到空白页；多一个实现没有 Dest，是死页面。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const router = fs.readFileSync(path.join(ROOT, 'App', 'Core', 'Router.swift'), 'utf8');
const map = fs.readFileSync(path.join(ROOT, 'App', 'Features', 'Shared', 'Destinations.swift'), 'utf8');

const enumBody = router.slice(router.indexOf('enum Dest'), router.indexOf('var id: String'));
const declared = [...enumBody.matchAll(/^\s{4}case\s+([a-zA-Z0-9_]+)\s*$/gm)].map((m) => m[1]);

const implemented = [...map.matchAll(/case\s+\.([a-zA-Z0-9_]+)\s*:/g)].map((m) => m[1]);

const missing = declared.filter((d) => !implemented.includes(d));
const extra = implemented.filter((d) => !declared.includes(d));

if (missing.length || extra.length) {
  if (missing.length) console.error('destmap: 没有实现的 Dest：' + missing.join(', '));
  if (extra.length) console.error('destmap: 没有声明的实现：' + extra.join(', '));
  process.exit(1);
}
console.log(`destmap: OK — Dest ${declared.length} 项，实现 ${implemented.length} 项，一一对应`);
