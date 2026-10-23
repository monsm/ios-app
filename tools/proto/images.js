'use strict';
// tools/proto/images.js —— §6.4 图像与材质
//
// 规范三条铁律：
//   I1 禁止用 CSS 渐变/纯色块冒充图像素材（"一眼假，且无法通过后续美化挽救"）
//   I2 设备样机必须是真实渲染图，不是 CSS 画的边框
//   I3 没有素材时用**单色占位**，不用假渐变（"单色显得未完成，假渐变显得廉价，前者诚实"）
//
// §6.4.4 占位优先级：SF Symbols 单色图标（textTertiary）+ 无底 > surfaceRaised 色块 r14
const fs = require('fs'), path = require('path');
const D = __dirname;
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));

// textTertiary
const T3 = '#6A6A6E';
const T2 = '#8D8D93';

let n = 0;
for (const p of reg) {
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  const before = s;

  // ① 彩色圆头像 → 单色：把 background 为半透明彩色的圆形改成透明底 + 单色描边
  //    典型形态：<div style="...border-radius:50%;background:#XXXXXX22;...color:#XXXXXX">
  s = s.replace(
    /(border-radius:50%;)([^"]*?)background:(#[0-9A-Fa-f]{6})22;([^"]*?)color:(#[0-9A-Fa-f]{6})/g,
    function(m, r, a, bg, b, c) {
      // 保留形状，背景改为透明，文字/描边用 textTertiary
      return r + a + 'background:transparent;border:1px solid ' + T3 + ';' + b + 'color:' + T2;
    });

  // ② 渐变冒充的图像块 → 单色 surfaceRaised
  s = s.replace(
    /(border-radius:(?:50%|d+px);[^"]*?)background:linear-gradient([^)]*)/g,
    function(m, pre) { return pre + 'background:#24242A'; });

  // ③ 彩色图标徽章 → 统一 textTertiary 单色（§6.4.4「SF Symbols 单色 + 无底」）
  //    形态：background:<color>22 的 34/38/44px 方块
  s = s.replace(
    /(width:d+px;height:d+px;border-radius:d+px;)([^"]*?)background:(#[0-9A-Fa-f]{6})22;([^"]*?)color:(#[0-9A-Fa-f]{6})/g,
    function(m, dim, a, bg, b, c) {
      return dim + a + 'background:#24242A;' + b + 'color:' + T2;
    });

  if (s !== before) { fs.writeFileSync(fp, s, 'utf8'); n++; }
}
console.log('✓ §6.4 占位规范化 ' + n + ' 页');
