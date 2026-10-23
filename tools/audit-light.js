'use strict';
// tools/audit-light.js —— 浅色版像素审计：找未适配的深色残留
const fs = require('fs'), path = require('path');
const K = require('./imgkit.js');
const D = path.join(__dirname, 'proto');
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
console.log('页'.padEnd(20) + '深色占比 状态');
console.log('-'.repeat(44));
const dark = [];
for (const p of reg) {
  const fp = path.join(D, 'light-' + p.f + '.png');
  if (!fs.existsSync(fp)) continue;
  const img = K.decodePNG(fs.readFileSync(fp));
  let darkCount = 0, total = 0;
  // 只查 phone 内部
  for (let y = 50; y < img.h - 50; y += 4) {
    for (let x = 40; x < img.w - 40; x += 4) {
      const i = (y*img.w + x)*4;
      const l = 0.2126*img.data[i] + 0.7152*img.data[i+1] + 0.0722*img.data[i+2];
      total++;
      if (l < 40) darkCount++;
    }
  }
  const pct = Math.round(darkCount/total*100);
  const bad = pct > 22;
  if (bad) dark.push(p.f + '(' + pct + '%)');
  console.log((bad?'✗ ':'  ') + p.f.padEnd(18) + String(pct).padStart(4) + '%');
}
console.log('\n深色占比 >22% 的页:', dark.length);
dark.forEach(x=>console.log('  ' + x));
