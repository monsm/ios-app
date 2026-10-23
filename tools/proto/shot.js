'use strict';
// tools/proto/shot.js —— 统一截图（窗口 454 = body padding 32*2 + phone 390）
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const D = __dirname;
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
const only = process.argv.slice(2);
const list = only.length ? reg.filter(p=>only.includes(p.f)) : reg;
let n = 0;
for (const p of list) {
  const src = path.join(D, p.f + '.html');
  if (!fs.existsSync(src)) { console.error('缺 ' + p.f); continue; }
  const out = path.join(D, p.f + '.png');
  try { fs.unlinkSync(out); } catch {}
  // 模板 D 用两层结构，高度同 phone
  execFileSync(EDGE, [
    '--headless=new','--disable-gpu','--use-angle=swiftshader',
    '--allow-file-access-from-files','--window-size=454,908',
    '--screenshot=' + out,'--virtual-time-budget=5000',
    'file:///' + src.replace(/\\/g,'/'),
  ], { stdio: 'ignore' });
  n++;
}
console.log('✓ 截图 ' + n + ' 页（454×908）');
