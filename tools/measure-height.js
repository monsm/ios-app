'use strict';
// tools/measure-height.js —— 量页面内容真实高度（像素分析）
const fs = require('fs'), path = require('path');
const { execFileSync } = require('child_process');
const K = require('./imgkit.js');
const D = path.join(__dirname, 'proto');
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
const only = process.argv.slice(2);
const list = only.length ? reg.filter(p=>only.includes(p.f)) : reg;

const results = [];
for (const p of list) {
  const src = path.join(D, p.f + '.html');
  if (!fs.existsSync(src)) continue;
  // 生成超高 iframe 探针
  const probe = `<!DOCTYPE html><html><head><meta charset="utf-8">
<style>html,body{margin:0;background:#000;overflow:hidden}
iframe{width:390px;height:2400px;border:0;display:block}</style></head>
<body><iframe src="${p.f}.html" scrolling="no"></iframe></body></html>`;
  const pf = path.join(D, '_hh.html');
  fs.writeFileSync(pf, probe, 'utf8');
  const shot = path.join(D, '_hh.png');
  try { fs.unlinkSync(shot); } catch {}
  try {
    execFileSync(EDGE, ['--headless=new','--disable-gpu','--use-angle=swiftshader',
      '--allow-file-access-from-files','--window-size=400,2400',
      '--screenshot='+shot,'--virtual-time-budget=4000',
      'file:///'+pf.replace(/\\/g,'/')], { stdio:'ignore' });
  } catch(e) { console.log(p.f + ' 渲染失败'); continue; }
  const img = K.decodePNG(fs.readFileSync(shot));
  // phone 宽 390，在 400 窗口里左对齐 x=0..390
  // 只看 phone 内部，且跳过 .phone 自带的 844 高度边界
  // 真正要测的是：page 内容是否超过 .scroll 的可视高度
  // 做法：找 phone 区域内**最后一行有内容**的 y，但限制在 y<2200
  let lastY = 0;
  const xEnd = Math.min(390, img.w);
  for (let y = 0; y < Math.min(2300, img.h); y++) {
    for (let x = 4; x < xEnd - 4; x++) {
      const i = (y*img.w + x)*4;
      if (img.data[i] > 22 || img.data[i+1] > 22 || img.data[i+2] > 22) { lastY = y; break; }
    }
  }
  results.push({ f:p.f, t:p.t, h:lastY });
}
results.sort((a,b)=>b.h-a.h);
console.log('页'.padEnd(20) + '内容高 超出844');
console.log('-'.repeat(42));
let over = 0;
for (const r of results) {
  const o = r.h - 844;
  if (o > 0) over++;
  console.log((o>0?'✗ ':'  ') + r.f.padEnd(18) + String(r.h).padStart(5) + String(o>0?'+'+o:o).padStart(8));
}
console.log('\n超屏:', over, '/', results.length);
