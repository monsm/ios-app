'use strict';
// tools/mkall.js —— 一键处理所有 3D 素材：抠背景 + 多档输出
const fs = require('fs'), path = require('path');
const K = require('./imgkit.js');
const PRISM = path.join(__dirname, 'prism');
const OUT = path.join(__dirname, 'proto/img');
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

const ITEMS = [
  { name: 'medal',         sizes: [128, 192, 256] },
  { name: 'key-render',    sizes: [96, 192] },
  { name: 'member-avatar', sizes: [96, 192] },
  { name: 'finger-render', sizes: [96, 192] },
  { name: 'lock-front',    sizes: [128, 192] },
  { name: 'lock-45',       sizes: [128, 192] },
  { name: 'lock-side',     sizes: [128, 192] },
];

let ok = 0;
for (const it of ITEMS) {
  const src = path.join(PRISM, it.name + '-raw.png');
  if (!fs.existsSync(src)) { console.log('缺 ' + it.name); continue; }
  const img = K.decodePNG(fs.readFileSync(src));
  K.keyOut(img, { threshold: 13, feather: 24 });
  fs.writeFileSync(path.join(OUT, it.name + '.png'), K.encodePNG(img.w, img.h, img.data));
  for (const s of it.sizes) {
    const r = K.resize(img, s, s);
    fs.writeFileSync(path.join(OUT, it.name + '-' + s + '.png'), K.encodePNG(s, s, r.data));
  }
  ok++;
  console.log('✓ ' + it.name);
}
// 成员头像变体
const MEMBERS = ['wo','fei','huang','fu','mu'];
for (const m of MEMBERS) {
  const src = path.join(PRISM, 'av-' + m + '-raw.png');
  if (!fs.existsSync(src)) continue;
  const img = K.decodePNG(fs.readFileSync(src));
  K.keyOut(img, { threshold: 13, feather: 24 });
  fs.writeFileSync(path.join(OUT, 'avatar-' + m + '.png'), K.encodePNG(img.w, img.h, img.data));
  const r = K.resize(img, 128, 128);
  fs.writeFileSync(path.join(OUT, 'avatar-' + m + '-128.png'), K.encodePNG(128, 128, r.data));
}
console.log('\n✓ ' + ok + ' 个素材处理完成');
