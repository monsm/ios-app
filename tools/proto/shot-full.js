'use strict';
// tools/proto/shot-full.js —— 整页截图（展开滚动内容）
const { execSync } = require('child_process');
const fs = require('fs'), path = require('path');
const D = __dirname;
const name = process.argv[2];
if (!name) { console.log('用法: node shot-full.js <页面名>'); process.exit(1); }
const src = path.join(D, name + '.html');
if (!fs.existsSync(src)) { console.log('页面不存在:', name); process.exit(1); }
// 生成一个临时版本：phone 高度 auto
let html = fs.readFileSync(src, 'utf8');
html = html.replace('</head>', '<style>html,body{height:auto!important;overflow:visible!important}' +
  '.phone{height:auto!important;min-height:0!important;overflow:visible!important}' +
  '.scroll{position:static!important;height:auto!important;overflow:visible!important}' +
  '.page{padding-bottom:32px!important}</style></head>');
const tmp = path.join(D, '_full_' + name + '.html');
fs.writeFileSync(tmp, html, 'utf8');
// 先测高度
const edge = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const out = path.join(D, '_full_' + name + '.png');
try { fs.unlinkSync(out); } catch {}
execSync('"' + edge + '" --headless=new --disable-gpu --use-angle=swiftshader --allow-file-access-from-files ' +
  '--window-size=520,3000 --screenshot="' + out + '" --virtual-time-budget=5000 "file:///' +
  tmp.replace(/\\/g,'/') + '"', { stdio: 'ignore' });
console.log('✓ _full_' + name + '.png');
try { fs.unlinkSync(tmp); } catch {}
