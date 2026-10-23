'use strict';
const fs = require('fs'), path = require('path');
const K = require('../imgkit.js');
const D = __dirname;
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
// 统计每页的亮度分布：深/中/亮 三档占比
console.log('页'.padEnd(20) + '深(<30) 中(30-120) 亮(>150)');
console.log('-'.repeat(52));
let totDark=0, totMid=0, totBright=0, n=0;
for (const p of reg) {
  const fp = path.join(D, p.f + '.png');
  if (!fs.existsSync(fp)) continue;
  const img = K.decodePNG(fs.readFileSync(fp));
  let dark=0, mid=0, bright=0, tot=0;
  for (let y = 50; y < img.h - 60; y += 3) {
    for (let x = 30; x < img.w - 30; x += 3) {
      const i = (y*img.w+x)*4;
      const l = 0.2126*img.data[i] + 0.7152*img.data[i+1] + 0.0722*img.data[i+2];
      tot++;
      if (l < 30) dark++; else if (l < 120) mid++; else if (l > 150) bright++;
    }
  }
  const dp = Math.round(dark/tot*100), mp = Math.round(mid/tot*100), bp = Math.round(bright/tot*100);
  totDark+=dp; totMid+=mp; totBright+=bp; n++;
  console.log(p.f.padEnd(18) + String(dp).padStart(5) + '%' + String(mp).padStart(7) + '%' + String(bp).padStart(8) + '%');
}
console.log('\n平均: 深 ' + Math.round(totDark/n) + '% / 中 ' + Math.round(totMid/n) + '% / 亮 ' + Math.round(totBright/n) + '%');
console.log('\n参考图 1 实测: 深 76% / 中 18% / 亮 6%');
