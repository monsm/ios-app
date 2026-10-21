#!/usr/bin/env node
// ============================================================================
// tools/prism-render.js — 三棱柱「所见即所得」渲染器
// ============================================================================
//
// 为什么需要它:
//   本机没有 Swift 编译器、也没有真机。三棱柱的观感只能靠真机验证 ——
//   这是过去十几轮反复失准的根因（"和 html 比只有 10%"）。
//
//   但 App 那边的变换全部是 scaleEffect / offset / opacity / clipShape,
//   数学上完全可复现。所以这里用 Node 直接画出「App 会画成什么样」,
//   再画一份「three.js 原型会画成什么样」, 并排输出 ——
//   于是「是否基本一致」变成一张可以看的图, 不再靠猜。
//
// 用法:
//   node tools/prism-render.js               → 静止态并排
//   node tools/prism-render.js 0.5           → 转场中间态并排
//   node tools/prism-render.js --app-only    → 只画 App
//
'use strict';
const fs = require('fs');
const zlib = require('zlib');
const path = require('path');

// ── 最小 PNG 编码器（RGBA8）──
function encodePNG(w, h, rgba) {
  const tbl = new Int32Array(256).map((_, n) => {
    let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c;
  });
  const crc = b => { let c = -1; for (const x of b) c = tbl[(c ^ x) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (t, d) => {
    const l = Buffer.alloc(4); l.writeUInt32BE(d.length);
    const ty = Buffer.from(t, 'ascii');
    const bd = Buffer.concat([ty, d]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(bd));
    return Buffer.concat([l, bd, c]);
  };
  const ih = Buffer.alloc(13);
  ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 6;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const s = (y * w + x) * 4, d = y * (w * 4 + 1) + 1 + x * 4;
      raw[d] = rgba[s]; raw[d + 1] = rgba[s + 1]; raw[d + 2] = rgba[s + 2]; raw[d + 3] = rgba[s + 3];
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── 画布 ──
class Canvas {
  constructor(w, h) { this.w = w; this.h = h; this.px = new Uint8Array(w * h * 4); }
  clear(r, g, b) {
    for (let i = 0; i < this.w * this.h; i++) {
      this.px[i * 4] = r; this.px[i * 4 + 1] = g; this.px[i * 4 + 2] = b; this.px[i * 4 + 3] = 255;
    }
  }
  dot(x, y, r, g, b, a = 255) {
    const xi = x | 0, yi = y | 0;
    if (xi < 0 || yi < 0 || xi >= this.w || yi >= this.h) return;
    const i = (yi * this.w + xi) * 4;
    const A = a / 255;
    this.px[i] = this.px[i] * (1 - A) + r * A;
    this.px[i + 1] = this.px[i + 1] * (1 - A) + g * A;
    this.px[i + 2] = this.px[i + 2] * (1 - A) + b * A;
    this.px[i + 3] = 255;
  }
  inRounded(x, y, x0, y0, w, h, rad) {
    if (x < x0 || y < y0 || x >= x0 + w || y >= y0 + h) return false;
    const dx = Math.max(x0 + rad - x, 0, x - (x0 + w - rad));
    const dy = Math.max(y0 + rad - y, 0, y - (y0 + h - rad));
    return dx * dx + dy * dy <= rad * rad;
  }
  fillRounded(x0, y0, w, h, rad, c, a = 255) {
    for (let y = Math.max(0, y0 | 0); y < Math.min(this.h, (y0 + h) | 0); y++)
      for (let x = Math.max(0, x0 | 0); x < Math.min(this.w, (x0 + w) | 0); x++)
        if (this.inRounded(x, y, x0, y0, w, h, rad)) this.dot(x, y, c[0], c[1], c[2], a);
  }
  // 圆角环（= SwiftUI strokeBorder）
  //
  // 判据: 像素在**外圆角矩形内**、但**不在内圆角矩形内** → 属于环带。
  // 只看"在某个嵌套矩形内"是错的（那样几乎整块都被画上）—— 这里踩过一次。
  strokeRounded(x0, y0, w, h, rad, t, colorAt, a = 255) {
    for (let y = Math.max(0, (y0 - 1) | 0); y < Math.min(this.h, (y0 + h + 1) | 0); y++) {
      for (let x = Math.max(0, (x0 - 1) | 0); x < Math.min(this.w, (x0 + w + 1) | 0); x++) {
        if (!this.inRounded(x, y, x0, y0, w, h, rad)) continue;              // 外框外
        if (this.inRounded(x, y, x0 + t, y0 + t, w - 2 * t, h - 2 * t,
                           Math.max(1, rad - t))) continue;                  // 内框内 = 内容区
        // 逐层数深度，供渐变着色
        let depth = t - 1;
        for (let L = 0; L < t; L++) {
          if (this.inRounded(x, y, x0 + L, y0 + L, w - 2 * L, h - 2 * L, Math.max(1, rad - L))) { depth = L; break; }
        }
        const c = colorAt(depth / Math.max(1, t - 1));
        this.dot(x, y, c[0], c[1], c[2], a);
      }
    }
  }
  // 任意多边形（扫描线）+ 逐像素回调
  polygon(pts, shader) {
    const ys = pts.map(p => p[1]);
    const y0 = Math.max(0, Math.floor(Math.min(...ys)));
    const y1 = Math.min(this.h - 1, Math.ceil(Math.max(...ys)));
    for (let y = y0; y <= y1; y++) {
      const yy = y + 0.5, hits = [];
      for (let k = 0; k < pts.length; k++) {
        const A = pts[k], B = pts[(k + 1) % pts.length];
        if ((A[1] <= yy && B[1] >= yy) || (B[1] <= yy && A[1] >= yy)) {
          const t = B[1] === A[1] ? 0 : (yy - A[1]) / (B[1] - A[1]);
          hits.push([A[0] + (B[0] - A[0]) * t, k, t]);
        }
      }
      if (hits.length < 2) continue;
      hits.sort((p, q) => p[0] - q[0]);
      for (let h = 0; h + 1 < hits.length; h += 2) {
        const xa = Math.max(0, Math.ceil(hits[h][0])), xb = Math.min(this.w - 1, Math.floor(hits[h + 1][0]));
        for (let x = xa; x <= xb; x++) {
          const c = shader(x, y, (x - hits[h][0]) / Math.max(1, hits[h + 1][0] - hits[h][0]));
          if (c) this.dot(x, y, c[0], c[1], c[2], c[3] === undefined ? 255 : c[3]);
        }
      }
    }
  }
  line(x0, y0, x1, y1, halfW, colorAt) {
    const n = Math.ceil(Math.hypot(x1 - x0, y1 - y0)) * 2;
    for (let s = 0; s <= n; s++) {
      const t = s / n, x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t;
      for (let d = -halfW; d <= halfW; d++) {
        const c = colorAt(d / Math.max(0.001, halfW));
        this.dot(x + d, y, c[0], c[1], c[2], c[3] === undefined ? 255 : c[3]);
      }
    }
  }
  save(file) { fs.writeFileSync(file, encodePNG(this.w, this.h, this.px)); return file; }
}

module.exports = { Canvas, encodePNG };
