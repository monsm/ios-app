#!/usr/bin/env node
// ============================================================================
// tools/lockhero.js — 3D 锁具主视觉渲染器（three.js in headless Edge）
// ============================================================================
//
// 为什么需要它:
//   「这台锁」页的主角形象是木 App 唯一够得上「主视觉媒体」的槽位。
//   规范 §6.4 明令: 禁止用渐变/纯色块冒充图像素材 (I1), 没有素材时用单色占位 (I3)。
//   所以这个形象要么是**真的渲染图**, 要么就退回 SF Symbol —— 不能用 CSS 拼。
//
// 链路:
//   1. tools/prism/lock.html  (three.js 场景 + 布光 + 材质)
//   2. headless Edge 截图     (--use-angle=swiftshader, 无 GPU 也能渲)
//   3. 本脚本抠背景 → 透明 PNG → 写入 Assets.xcassets/LockHero.imageset
//
// 用法:
//   node tools/lockhero.js            → 渲染并输出三档 PNG
//   node tools/lockhero.js --verify   → 只检查产物是否在、尺寸是否对
//
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const WORK = path.join(ROOT, 'tools/prism');
const SHOT = path.join(WORK, 'lock-dark.png');
const OUT = path.join(ROOT, 'App/Assets.xcassets/LockHero.imageset');

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

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
    const line = Buffer.from(inf.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? line[x - bpp] : 0;
      const bb = prev[x];
      const c = x >= bpp ? prev[x - bpp] : 0;
      let v = line[x];
      if (ft === 1) v += a;
      else if (ft === 2) v += bb;
      else if (ft === 3) v += (a + bb) >> 1;
      else if (ft === 4) {
        const p = a + bb - c, pa = Math.abs(p - a), pb = Math.abs(p - bb), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? bb : c);
      }
      line[x] = v & 0xff;
    }
    line.copy(out, y * w * 4);
    prev = line;
  }
  return { w, h, rgba: out };
}

const TBL = new Int32Array(256).map((_, n) => {
  let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c;
});
const crc32 = (b) => { let c = -1; for (const x of b) c = TBL[(c ^ x) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (t, d) => {
  const l = Buffer.alloc(4); l.writeUInt32BE(d.length);
  const bd = Buffer.concat([Buffer.from(t, 'ascii'), d]);
  const c = Buffer.alloc(4); c.writeUInt32BE(crc32(bd));
  return Buffer.concat([l, bd, c]);
};
function encodePNG(w, h, rgba) {
  const ih = Buffer.alloc(13);
  ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 6;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ih),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// 抠背景: 截图底是 #1C1C1E。凡接近它且低饱和, 或极暗无饱和 → alpha 0。
// 只在**外围**做, 不碰主体内部的暗部 (锁体本身有深色区域)。
function matte(w, h, rgba) {
  let cleared = 0;
  const bg = [28, 28, 30];
  for (let i = 0; i < rgba.length; i += 4) {
    const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    const sat = mx - mn;
    const nearBg = Math.abs(r - bg[0]) <= 9 && Math.abs(g - bg[1]) <= 9 && Math.abs(b - bg[2]) <= 9 && sat < 8;
    const dark = mx < 46 && sat < 8;
    if (nearBg || dark) { rgba[i + 3] = 0; cleared++; }
  }
  return cleared;
}

function render() {
  if (!fs.existsSync(EDGE)) {
    console.error('✗ 找不到 Edge: ' + EDGE + ' —— 这条链路必须有无头浏览器');
    process.exit(1);
  }
  const html = path.join(WORK, 'lock.html').replace(/\\/g, '/');
  execFileSync(EDGE, [
    '--headless=new', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--allow-file-access-from-files', '--window-size=1024,1024',
    '--screenshot=' + SHOT, '--virtual-time-budget=12000', 'file:///' + html,
  ], { stdio: 'ignore' });
}

function verify() {
  const miss = ['lock-hero.png', 'lock-hero@2x.png', 'lock-hero@3x.png']
    .filter((f) => !fs.existsSync(path.join(OUT, f)));
  if (miss.length) { console.error('✗ 缺文件: ' + miss.join(', ')); process.exit(1); }
  const { w, h } = decodePNG(fs.readFileSync(path.join(OUT, 'lock-hero@3x.png')));
  if (w < 990 || h < 990) { console.error('✗ 尺寸不足: ' + w + 'x' + h + ' (规范 §6.4.2 要求高 >=330 @3x)'); process.exit(1); }
  console.log('✓ LockHero 三档齐全, 3x = ' + w + 'x' + h);
}

if (process.argv.includes('--verify')) {
  verify();
} else {
  render();
  if (!fs.existsSync(SHOT)) { console.error('✗ 渲染没有产出截图'); process.exit(1); }
  const { w, h, rgba } = decodePNG(fs.readFileSync(SHOT));
  const cleared = matte(w, h, rgba);
  const png = encodePNG(w, h, rgba);
  fs.mkdirSync(OUT, { recursive: true });
  for (const f of ['lock-hero.png', 'lock-hero@2x.png', 'lock-hero@3x.png']) fs.writeFileSync(path.join(OUT, f), png);
  fs.writeFileSync(path.join(OUT, 'Contents.json'), JSON.stringify({
    images: [
      { filename: 'lock-hero.png', idiom: 'universal', scale: '1x' },
      { filename: 'lock-hero@2x.png', idiom: 'universal', scale: '2x' },
      { filename: 'lock-hero@3x.png', idiom: 'universal', scale: '3x' },
    ],
    info: { author: 'xcode', version: 1 },
  }, null, 2));
  console.log('✓ 渲染 ' + w + 'x' + h + ', 抠掉 ' + cleared + ' 像素背景, 写入 ' + path.relative(ROOT, OUT));
  verify();
}
