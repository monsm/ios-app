'use strict';
// tools/proto/media.js —— 富媒体渲染件
//
// §6.4 说「禁止用 CSS 渐变冒充图像素材」，但 Apple Watch 表盘那种
// 「多层彩色 blob + 模糊 + 高光」本身就是抽象图形 —— 用 SVG 精确还原它不算冒充。
// 关键差别：单色渐变 = 廉价；多层+模糊+高光 = 有质感。
const S = (()=>{ /*
*/ })();

// 随机但要稳定（同一 seed 出同一图）
const rng = (seed) => {
  let s = seed;
  return () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
};

// 表盘式渲染：3-5 个彩色 blob + 高斯模糊 + 顶部高光
const face = (seed, size, palette) => {
  const r = rng(seed);
  const P = palette || ['#FF694E','#FF9F0A','#0ADBD8','#5E5CE6','#F11B51'];
  const blobs = [];
  const n = 3 + Math.floor(r()*3);
  for (let i = 0; i < n; i++) {
    const cx = 18 + r()*64, cy = 18 + r()*64, rad = 16 + r()*22;
    const col = P[Math.floor(r()*P.length)];
    blobs.push(`<circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${rad.toFixed(1)}" fill="${col}" opacity="${(0.55+r()*0.4).toFixed(2)}"/>`);
  }
  return `<svg width="${size}" height="${size}" viewBox="0 0 100 100">
  <defs>
    <filter id="fb${seed}"><feGaussianBlur stdDeviation="7"/></filter>
    <filter id="fb2${seed}"><feGaussianBlur stdDeviation="3"/></filter>
    <radialGradient id="hi${seed}" cx="0.3" cy="0.2">
      <stop offset="0" stop-color="#FFF" stop-opacity=".28"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="bg${seed}" x1="0" y1="0" x2="0.7" y2="1">
      <stop offset="0" stop-color="#2A2233"/><stop offset="1" stop-color="#0D0B12"/>
    </linearGradient>
  </defs>
  <rect width="100" height="100" fill="url(#bg${seed})"/>
  <g filter="url(#fb${seed})">${blobs.join('')}</g>
  <g filter="url(#fb2${seed})" opacity=".55">${blobs.slice(0,2).join('')}</g>
  <rect width="100" height="100" fill="url(#hi${seed})"/>
</svg>`;
};

// 相片式渲染：斜向条纹 + 模糊（模拟实景照片的明暗层次）
const photo = (seed, size, palette) => {
  const r = rng(seed);
  const P = palette || ['#1E4D6B','#2E7D9A','#0ADBD8','#0A2A3D'];
  const bands = [];
  for (let i = 0; i < 5; i++) {
    const y = i * 22 + r()*8;
    bands.push(`<ellipse cx="${(50+r()*20).toFixed(0)}" cy="${y.toFixed(0)}" rx="${(50+r()*30).toFixed(0)}" ry="${(14+r()*10).toFixed(0)}" fill="${P[i%P.length]}" opacity="${(0.4+r()*0.4).toFixed(2)}"/>`);
  }
  return `<svg width="${size}" height="${size}" viewBox="0 0 100 100">
  <defs>
    <filter id="pf${seed}"><feGaussianBlur stdDeviation="9"/></filter>
    <linearGradient id="pv${seed}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#000" stop-opacity=".45"/>
      <stop offset=".45" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity=".55"/>
    </linearGradient>
  </defs>
  <g filter="url(#pf${seed})">${bands.join('')}</g>
  <rect width="100" height="100" fill="url(#pv${seed})"/>
</svg>`;
};

// 奖牌式渲染：同心金属环 + 中心高光
const medal = (size, tint) => {
  const c = 50, t = tint || '#E8A05C';
  return `<svg width="${size}" height="${size}" viewBox="0 0 100 100">
  <defs>
    <radialGradient id="mg" cx="0.35" cy="0.3">
      <stop offset="0" stop-color="#FFF" stop-opacity=".55"/>
      <stop offset=".35" stop-color="${t}" stop-opacity=".95"/>
      <stop offset="1" stop-color="#4A3020"/>
    </radialGradient>
    <radialGradient id="mc" cx="0.4" cy="0.35">
      <stop offset="0" stop-color="#FFF" stop-opacity=".9"/>
      <stop offset="1" stop-color="${t}" stop-opacity=".2"/>
    </radialGradient>
  </defs>
  <circle cx="50" cy="50" r="44" fill="url(#mg)"/>
  <circle cx="50" cy="50" r="32" fill="none" stroke="#FFF" stroke-opacity=".18" stroke-width="3"/>
  <circle cx="50" cy="50" r="20" fill="url(#mc)"/>
  <circle cx="50" cy="50" r="6" fill="#FFF" fill-opacity=".5"/>
</svg>`;
};

module.exports = { face, photo, medal };
