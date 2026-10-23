'use strict';
// tools/imgkit.js —— 纯 Node PNG 工具（无外部依赖）
// 抠背景 / 缩放 / 输出多档。从 lockhero.js 的 decodePNG/encodePNG 提炼。
const zlib = require('zlib');

function decodePNG(b) {
  let off = 8; const chunks = {};
  while (off < b.length) {
    const len = b.readUInt32BE(off);
    const type = b.toString('ascii', off + 4, off + 8);
    (chunks[type] ||= []).push(b.subarray(off + 8, off + 8 + len));
    off += 12 + len;
  }
  const ihdr = chunks['IHDR'][0];
  const w = ihdr.readUInt32BE(0), h = ihdr.readUInt32BE(4);
  const colorType = ihdr[9];
  const bpp = colorType === 6 ? 4 : colorType === 2 ? 3 : 1;
  const stride = w * bpp;
  const inf = zlib.inflateSync(Buffer.concat(chunks['IDAT']));
  const out = Buffer.alloc(w * h * 4);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const ft = inf[y * (stride + 1)];
    const line = Buffer.from(inf.subarray(y*(stride+1)+1, (y+1)*(stride+1)));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? line[x-bpp] : 0;
      const up = prev[x];
      const c = x >= bpp ? prev[x-bpp] : 0;
      switch (ft) {
        case 1: line[x] = (line[x] + a) & 255; break;
        case 2: line[x] = (line[x] + up) & 255; break;
        case 3: line[x] = (line[x] + ((a+up)>>1)) & 255; break;
        case 4: {
          const p = a + up - c, pa = Math.abs(p-a), pb = Math.abs(p-up), pc = Math.abs(p-c);
          line[x] = (line[x] + (pa<=pb && pa<=pc ? a : pb<=pc ? up : c)) & 255; break;
        }
      }
    }
    for (let x = 0; x < w; x++) {
      const s = x*bpp;
      out[(y*w+x)*4]   = line[s];
      out[(y*w+x)*4+1] = bpp >= 3 ? line[s+1] : line[s];
      out[(y*w+x)*4+2] = bpp >= 3 ? line[s+2] : line[s];
      out[(y*w+x)*4+3] = bpp === 4 ? line[s+3] : 255;
    }
    prev = line;
  }
  return { w, h, data: out };
}

function encodePNG(w, h, rgba) {
  const raw = Buffer.alloc((w*4+1)*h);
  for (let y = 0; y < h; y++) {
    raw[y*(w*4+1)] = 0;
    rgba.copy(raw, y*(w*4+1)+1, y*w*4, (y+1)*w*4);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  const chunks = [];
  const sig = Buffer.from([137,80,78,71,13,10,26,10]);
  const mkChunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const t = Buffer.from(type, 'ascii');
    const crcBuf = Buffer.concat([t, data]);
    const crc = Buffer.alloc(4);
    let c = 0xFFFFFFFF;
    for (const byte of crcBuf) {
      c ^= byte;
      for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xEDB88320 & -(c & 1));
    }
    crc.writeUInt32BE((c ^ 0xFFFFFFFF) >>> 0);
    return Buffer.concat([len, t, data, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  chunks.push(sig, mkChunk('IHDR', ihdr), mkChunk('IDAT', idat), mkChunk('IEND', Buffer.alloc(0)));
  return Buffer.concat(chunks);
}

// 抠背景：把接近纯黑的像素变透明（保留边缘抗锯齿）
function keyOut(img, opts) {
  const o = opts || {};
  const thresh = o.threshold || 26;      // 低于此亮度视为背景
  const feather = o.feather || 30;       // 过渡带
  const { w, h, data } = img;
  for (let i = 0; i < w*h; i++) {
    const r = data[i*4], g = data[i*4+1], b = data[i*4+2];
    const lum = 0.2126*r + 0.7152*g + 0.0722*b;
    if (lum < thresh) data[i*4+3] = 0;
    else if (lum < thresh + feather) {
      // 边缘：按亮度做 alpha 渐变（保抗锯齿）
      data[i*4+3] = Math.round((lum - thresh) / feather * 255);
    }
  }
  return img;
}

// 最近邻缩放（保持锐利）
function resize(img, nw, nh) {
  const { w, h, data } = img;
  const out = Buffer.alloc(nw*nh*4);
  for (let y = 0; y < nh; y++) {
    const sy = Math.min(h-1, Math.floor(y*h/nh));
    for (let x = 0; x < nw; x++) {
      const sx = Math.min(w-1, Math.floor(x*w/nw));
      const si = (sy*w+sx)*4, di = (y*nw+x)*4;
      out[di]=data[si]; out[di+1]=data[si+1]; out[di+2]=data[si+2]; out[di+3]=data[si+3];
    }
  }
  return { w: nw, h: nh, data: out };
}

module.exports = { decodePNG, encodePNG, keyOut, resize };
