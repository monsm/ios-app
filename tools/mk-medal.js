'use strict';
const fs = require('fs'), path = require('path');
const K = require('./imgkit.js');
const src = path.join(__dirname, 'prism/medal-raw.png');
const img = K.decodePNG(fs.readFileSync(src));
K.keyOut(img, { threshold: 14, feather: 22 });
fs.writeFileSync(path.join(__dirname, 'prism/medal.png'), K.encodePNG(img.w, img.h, img.data));
console.log('✓ medal.png 透明底输出', img.w + 'x' + img.h);
