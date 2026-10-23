'use strict';
const fs = require('fs'), path = require('path');
const K = require('./imgkit.js');
const IMG = path.join(__dirname, 'proto/img');
for (let i = 0; i < 5; i++) {
  const f = path.join(IMG, 'badge-' + i + '.png');
  if (!fs.existsSync(f)) continue;
  const img = K.decodePNG(fs.readFileSync(f));
  K.keyOut(img, { threshold: 8, feather: 18 });
  fs.writeFileSync(f, K.encodePNG(img.w, img.h, img.data));
  console.log('✓ badge-' + i + ' 透明底');
}
