'use strict';
// tools/proto/converge-color.js —— 每页强调色收敛到 ≤3 种（规范 §3.4 铁律）
//
// 之前 17/37 页用了 4–7 种强调色，主页各 7 种。
// 参考图的克制在于「每屏只让一个色说话」——颜色多了就没有主角。
//
// 做法：读 color-bind.json 的 {main, accent}，把页面里其它强调色
// 替换成 main（除非它在语义上必须保留：告警红、成功绿）。
const fs = require('fs');
const path = require('path');
const D = __dirname;
const BIND = JSON.parse(fs.readFileSync(path.join(D,'color-bind.json'),'utf8'));
const reg  = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));

const PALETTE = ['#0090FC','#F11B51','#FF3B30','#FF694E','#FF9F0A','#3CDE02',
                 '#0ADBD8','#30D158','#5E5CE6','#BF5AF2'];

// 语义上**必须保留**的色：告警红、成功绿、白、黑、中性灰
const KEEP = new Set(['#FF3B30','#30D158','#FFFFFF','#000000','#8D8D93','#6A6A6E']);

let n = 0;
const report = [];
for (const p of reg) {
  const b = BIND[p.f];
  if (!b) continue;
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  const before = s;
  const allowed = new Set([b.main.toUpperCase(), (b.accent||'').toUpperCase()].filter(Boolean));
  // 统计并替换
  // **只替换"数据语义"用色**，不碰渐变定义（linear-gradient 里的色是视觉基底，
  //  改了渐变卡就塌了 —— 03-devices 的 #5E5CE6 被换掉 101 次就是教训）
  // 做法：先把所有渐变声明整体挖出来存好，替换完再放回
  const grads = [];
  s = s.replace(/linear-gradient\([^)]*\)/g, function(m){ grads.push(m); return '__GRAD' + (grads.length-1) + '__'; });
  s = s.replace(/radial-gradient\([^)]*\)/g, function(m){ grads.push(m); return '__GRAD' + (grads.length-1) + '__'; });

  for (const c of PALETTE) {
    if (allowed.has(c)) continue;
    if (KEEP.has(c)) continue;
    const re = new RegExp(c, 'gi');
    if (re.test(s)) {
      const cnt = (s.match(re)||[]).length;
      s = s.replace(re, b.main);
      report.push('  ' + p.f + ': ' + c + ' ×' + cnt + ' → ' + b.main);
    }
  }
  // 放回渐变
  s = s.replace(/__GRAD(\d+)__/g, function(m, i){ return grads[+i]; });
  // 放回三环
  s = s.replace(/__RING(\d+)__/g, function(m, i){ return rings[+i]; });
  if (s !== before) { fs.writeFileSync(fp, s, 'utf8'); n++; }
}
console.log('✓ 颜色收敛 ' + n + ' 页');
if (report.length) console.log(report.slice(0, 30).join('\n'));
