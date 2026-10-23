'use strict';
// tools/mkmaterials.js —— 素材批处理：抠背景 + 输出多档 + 写入 img/
const fs = require('fs'), path = require('path');
const K = require('./imgkit.js');
const PRISM = path.join(__dirname, 'prism');
const OUT = path.join(__dirname, 'proto/img');
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

const ITEMS = [
  { name: 'medal',          sizes: [128, 192, 256] },
  { name: 'key-render',     sizes: [96, 192] },
  { name: 'member-avatar',  sizes: [96, 192] },
  { name: 'finger-render',  sizes: [96, 192] },
];

for (const it of ITEMS) {
  const src = path.join(PRISM, it.name + '-raw.png');
  if (!fs.existsSync(src)) { console.log('缺 ' + it.name); continue; }
  const img = K.decodePNG(fs.readFileSync(src));
  K.keyOut(img, { threshold: 14, feather: 24 });
  const base = path.join(OUT, it.name + '.png');
  fs.writeFileSync(base, K.encodePNG(img.w, img.h, img.data));
  for (const s of it.sizes) {
    const r = K.resize(img, s, s);
    fs.writeFileSync(path.join(OUT, it.name + '-' + s + '.png'), K.encodePNG(s, s, r.data));
  }
  console.log('✓ ' + it.name + ' → ' + it.sizes.join('/') + ' + 原尺寸');
}
console.log('\n输出目录: tools/proto/img/');
