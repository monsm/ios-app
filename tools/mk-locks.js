'use strict';
const fs = require('fs'), path = require('path');
const K = require('./imgkit.js');
const PRISM = path.join(__dirname, 'prism');
const OUT = path.join(__dirname, 'proto/img');
for (const n of ['lock-front','lock-45','lock-side']) {
  const src = path.join(PRISM, n + '-raw.png');
  if (!fs.existsSync(src)) { console.log('缺 ' + n); continue; }
  const img = K.decodePNG(fs.readFileSync(src));
  K.keyOut(img, { threshold: 12, feather: 26 });
  fs.writeFileSync(path.join(OUT, n + '.png'), K.encodePNG(img.w, img.h, img.data));
  const r = K.resize(img, 128, 128);
  fs.writeFileSync(path.join(OUT, n + '-128.png'), K.encodePNG(128, 128, r.data));
  console.log('✓ ' + n);
}
