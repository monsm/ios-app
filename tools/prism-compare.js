#!/usr/bin/env node
// tools/prism-compare.js — 并排输出「App 会画成什么」vs「three.js 原型画成什么」
'use strict';
const fs = require('fs');
const path = require('path');
const { Canvas } = require('./prism-render.js');

const ROOT = path.resolve(__dirname, '..');
const SRC = fs.readFileSync(path.join(ROOT, 'App/UI/DoorPrism.swift'), 'utf8');

// ── 从 Swift 源码读参数，保证渲染与代码同步 ──
function grab(re, dflt) { const m = SRC.match(re); return m ? parseFloat(m[1]) : dflt; }
const INNER_F  = grab(/let inner = width \* ([0-9.]+)/, 0.80);
const CAM_DIST = grab(/prismCameraDistance: CGFloat \{ ([0-9.]+) \}/, 10.4);
const EDGE_F   = grab(/let R = A \* ([0-9.]+)/, 1.732);
const EDGE_W   = grab(/\.frame\(width: ([0-9.]+)\)\s*\n\s*\.scaleEffect\(depthScale\)\s*\n\s*\.offset\(x: x\)/, 8);
function lastGrab(re, dflt) { const all = [...SRC.matchAll(re)]; return all.length ? parseFloat(all[all.length-1][1]) : dflt; }
const FRAME_W  = lastGrab(/lineWidth: ([0-9.]+)/g, 5);
console.log('读到参数:', JSON.stringify({ INNER_F, CAM_DIST, EDGE_F, EDGE_W, FRAME_W }));

const W = 390, H = 844, SS = 2;
const CW = W * SS, CH = H * SS;
const BG = [13, 14, 16];

const FACES = [
  { id: 'b', angle: 0,   tint: [217, 139, 69] },
  { id: 'd', angle: 120, tint: [61, 214, 140] },
  { id: 'f', angle: 240, tint: [142, 123, 212] },
];
const easeInOutSine = t => -(Math.cos(Math.PI * t) - 1) / 2;

// ── App 内容（示意：标题 + 三卡 + 底部玻璃导航）──
function appContent(cv, x0, y0, w, h, tint, alpha) {
  if (w < 4 || h < 4) return;
  cv.fillRounded(x0, y0, w, h, 26 * SS, [23, 24, 28], alpha);
  cv.fillRounded(x0 + w * 0.07, y0 + h * 0.055, w * 0.44, h * 0.028, 7 * SS, [226, 226, 231], alpha);
  cv.fillRounded(x0 + w * 0.07, y0 + h * 0.095, w * 0.26, h * 0.013, 5 * SS, [114, 114, 122], alpha);
  for (let i = 0; i < 3; i++) {
    const cy = y0 + h * (0.16 + i * 0.115);
    cv.fillRounded(x0 + w * 0.07, cy, w * 0.86, h * 0.085, 14 * SS, [35, 37, 42], alpha);
    cv.fillRounded(x0 + w * 0.10, cy + h * 0.012, w * 0.22, h * 0.010, 4 * SS, [152, 152, 160], alpha);
  }
  cv.fillRounded(x0 + w * 0.07, y0 + h * 0.87, w * 0.86, h * 0.065, 16 * SS, [34, 36, 41], alpha);
  cv.fillRounded(x0 + w * 0.07, y0 + h * 0.87, w * 0.22, h * 0.065, 16 * SS,
    tint.map(v => Math.round(v * 0.30)), alpha);
  cv.fillRounded(x0 + w * 0.08, y0 + h * 0.95, w * 0.84, h * 0.034, 14 * SS, [52, 54, 60], alpha);
  for (let i = 0; i < 5; i++)
    cv.fillRounded(x0 + w * 0.08 + w * 0.84 * (0.07 + i * 0.187), y0 + h * 0.95 + h * 0.010,
      w * 0.065, h * 0.013, 3 * SS, tint, alpha);
}
const METAL = [[205,209,217],[186,190,198],[160,164,172],[132,136,144],[106,110,118]];

// ── App 侧渲染（严格按 SwiftUI 的 scale/offset/opacity）──
function renderApp(turn, turnSign, faceId) {
  const cv = new Canvas(CW, CH);
  cv.clear(...BG);
  const inner = W * INNER_F;
  const A = Math.max(inner, 1) * 0.2887;
  const D = A * CAM_DIST;
  const faceH = H * 0.96;
  const base = FACES.find(f => f.id === faceId).angle;
  const cont = -base + turn * turnSign * 120;
  const prog = 1 - turn;
  const narrow = Math.max(0, Math.min(1, (Math.abs(Math.cos(((prog * 120) - 60) * Math.PI / 180)) - 0.5) / 0.5));
  const bScale = 1 - 0.20 * narrow;
  const zShift = -A * 0.7 * narrow;

  const items = FACES.map(f => {
    const rad = (f.angle + cont) * Math.PI / 180;
    const z = A * Math.cos(rad) + zShift;
    const ds = D / (D - z);
    const c = Math.cos(rad);
    const op = c > 0.15 ? 1 : (c < -0.15 ? 0 : (c + 0.15) / 0.30);
    return { ...f, rad, z, ds, op, sx: Math.max(0.001, Math.abs(c) * ds * bScale), sy: ds * bScale,
             x: A * Math.sin(rad) * bScale };
  }).filter(i => i.op > 0.02).sort((p, q) => p.z - q.z);

  const frameT = FRAME_W * SS;
  for (const it of items) {
    const w = inner * it.sx * SS, h = faceH * it.sy * SS;
    const x0 = CW / 2 + it.x * SS - w / 2, y0 = CH / 2 - h / 2;
    const al = Math.round(255 * it.op);
    appContent(cv, x0 + frameT, y0 + frameT, w - 2 * frameT, h - 2 * frameT, it.tint, al);
    cv.strokeRounded(x0, y0, w, h, 30 * SS * Math.min(1, it.sx), frameT,
      t => METAL[Math.min(4, Math.floor(t * 5))], al);
  }
  // 竖棱
  for (const base2 of [60, 180, 300]) {
    const rad = (base2 + cont) * Math.PI / 180;
    if (Math.cos(rad) <= 0) continue;
    const Rc = A * EDGE_F;
    const ez = Rc * Math.cos(rad), eds = D / (D - ez);
    const ex = CW / 2 + Rc * Math.sin(rad) * bScale * SS;
    const eh = faceH * eds * bScale * SS;
    const ew = EDGE_W / 2 * SS;
    cv.line(ex, CH / 2 - eh / 2, ex, CH / 2 + eh / 2, ew,
      t => { const k = Math.round(200 - 40 * Math.abs(t)); return [k, k + 3, k + 9]; });
  }
  return cv;
}

// ── three.js 原型渲染 ──
function renderHTML(turn) {
  const cv = new Canvas(CW, CH);
  cv.clear(...BG);
  const fov = 32, tanF = Math.tan(fov / 2 * Math.PI / 180);
  const FW = 1.42, FH = 2.1, APO = 0.5;
  const dCam = (FW / INNER_F) / (2 * tanF * (W / H));
  const proj = (x, y, z) => { const d = dCam - z, k = H / (2 * d * tanF); return [W / 2 + x * k, H / 2 - y * k, k]; };
  const base = FACES[1].angle;   // 停在 D 面
  const cont = -base + turn * 120;
  const list = FACES.map(f => {
    const a = (f.angle + cont) * Math.PI / 180;
    return { ...f, a, cz: Math.cos(a) * APO };
  }).filter(f => Math.cos(f.a) > 0).sort((p, q) => p.cz - q.cz);
  for (const f of list) {
    const cx = Math.sin(f.a) * APO, cz = Math.cos(f.a) * APO;
    const tx = Math.cos(f.a), tz = -Math.sin(f.a);
    const pts = [[-FW/2,-FH/2],[FW/2,-FH/2],[FW/2,FH/2],[-FW/2,FH/2]].map(([u,v]) => {
      const p = proj(cx + tx*u, v, cz + tz*u); return [p[0]*SS, p[1]*SS];
    });
    cv.polygon(pts, (x, y, t) => {
      const slat = Math.floor(t * 14);
      const sh = (slat % 2 === 0) ? 1.0 : 0.80;
      return [Math.round(19*sh + f.tint[0]*0.05), Math.round(20*sh + f.tint[1]*0.05), Math.round(23*sh + f.tint[2]*0.05), 255];
    });
    // 金属框
    for (let k = 0; k < 4; k++) {
      const A2 = pts[k], B2 = pts[(k+1)%4];
      cv.line(A2[0], A2[1], B2[0], B2[1], 3.5*SS,
        t => { const v = Math.round(200 - 30*Math.abs(t)); return [v, v+2, v+6]; });
    }
  }
  for (const b of [0, 120, 240]) {
    const a = (b + Math.PI/3*180/Math.PI + cont) * Math.PI/180;
    const rad = Math.sin(Math.PI/3);
    const cz = Math.cos(a) * rad;
    if (cz <= 0) continue;
    const cx = Math.sin(a) * rad;
    const top = proj(cx, FH/2, cz), bot = proj(cx, -FH/2, cz);
    cv.line(top[0]*SS, top[1]*SS, bot[0]*SS, bot[1]*SS, 2.5*SS,
      t => { const v = Math.round(190 - 30*Math.abs(t)); return [v, v+2, v+6]; });
  }
  return cv;
}


// 在四角梯形内按参数 (u,v) 双线性插值
function proj2(c, u, v) {
  const top = [c[0][0] + (c[1][0] - c[0][0]) * u, c[0][1] + (c[1][1] - c[0][1]) * u];
  const bot = [c[3][0] + (c[2][0] - c[3][0]) * u, c[3][1] + (c[2][1] - c[3][1]) * u];
  return [top[0] + (bot[0] - top[0]) * v, top[1] + (bot[1] - top[1]) * v];
}

// ── 模拟 SwiftUI rotation3DEffect(theta, y, anchor:.center, anchorZ:-A, perspective:P) ──
// 变换链: translate(0,0,+A) → rotateY(θ) → translate(0,0,-A) → 透视除 (m34 = -P/H)
function project3DEffect(px, py, theta, A, P, H, W) {
  const sgn = parseFloat(process.env.ROTSIGN || '1');
  const th = theta * Math.PI / 180 * sgn;
  // 视图坐标: 原点在面中心
  let x = px, y = py, z = 0;
  z += A;                                   // 撤销 anchor
  const x1 =  x * Math.cos(th) + z * Math.sin(th);
  const z1 = -x * Math.sin(th) + z * Math.cos(th);
  x = x1; z = z1;
  z -= A;                                   // 回到视图空间
  const m34 = -P / H;
  const w = 1 + m34 * z;
  return [W / 2 + x / w, H / 2 + y / w, w];
}

// ── App 侧渲染（3D 版）──
function renderApp3D(turn, turnSign, faceId, perspective) {
  const cv = new Canvas(CW, CH);
  cv.clear(...BG);
  const inner = W * INNER_F;
  const A = Math.max(inner, 1) * 0.2887;
  const faceH = H * parseFloat(process.env.FACEH || '0.96');
  const base = FACES.find(f => f.id === faceId).angle;
  const cont = -base + turn * turnSign * 120;
  const prog = 1 - turn;
  const narrow = Math.max(0, Math.min(1, (Math.abs(Math.cos(((prog * 120) - 60) * Math.PI / 180)) - 0.5) / 0.5));
  const bScale = 1 - 0.20 * narrow;

  const out = FACES.map(f => {
    const theta = f.angle + cont;
    const rad = theta * Math.PI / 180;
    const c = Math.cos(rad);
    const op = c > 0.15 ? 1 : (c < -0.15 ? 0 : (c + 0.15) / 0.30);
    return { ...f, theta, z: A * Math.cos(rad), op };
  }).filter(i => i.op > 0.02).sort((p, q) => p.z - q.z);

  const frameT = FRAME_W;
  for (const it of out) {
    const hw = inner / 2, hh = faceH / 2;
    const proj = (px, py) => {
      const [sx, sy, w] = project3DEffect(px, py, it.theta, A, perspective, H, W);
      // 容器 breathScale 作用在已渲染结果上
      return [(sx - W / 2) * bScale + W / 2, (sy - H / 2) * bScale + H / 2];
    };
    // 四角（先内缩 frameT，作为内容区）
    const corners = [[-hw + frameT, -hh + frameT], [hw - frameT, -hh + frameT],
                     [hw - frameT, hh - frameT], [-hw + frameT, hh - frameT]].map(([a, b]) => proj(a, b));
    const outer = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]].map(([a, b]) => proj(a, b));
    const al = Math.round(255 * it.op);
    // 面：梯形填充 + 内部横向"卡片条"（也用梯形裁剪，避免轴对齐包围盒盖住形状）
    cv.polygon(corners.map(p => [p[0] * SS, p[1] * SS]), (x, y) => [24, 25, 29, al]);
    // 三条横向卡片条：在梯形内按参数 u∈[0,1] 线性插值
    for (let row = 0; row < 3; row++) {
      const v0 = 0.14 + row * 0.16, v1 = v0 + 0.10;
      const quad = [
        proj2(corners, 0.10, v0), proj2(corners, 0.90, v0),
        proj2(corners, 0.90, v1), proj2(corners, 0.10, v1),
      ];
      cv.polygon(quad.map(p => [p[0] * SS, p[1] * SS]), () => [35, 37, 42, al]);
    }
    // 金属框（沿外轮廓）
    for (let k = 0; k < 4; k++) {
      const P1 = outer[k], P2 = outer[(k + 1) % 4];
      cv.line(P1[0] * SS, P1[1] * SS, P2[0] * SS, P2[1] * SS, frameT / 2 * SS,
        t => { const v = Math.round(205 - 60 * Math.abs(t)); return [v, v + 3, v + 9, al]; });
    }
  }
  return cv;
}

// ── 并排合成 ──
function compose(a, b, label) {
  const gap = 12 * SS, cv = new Canvas(CW*2 + gap, CH);
  cv.clear(8, 8, 10);
  for (let y = 0; y < CH; y++) for (let x = 0; x < CW; x++) {
    const i1 = (y*CW + x)*4, i2 = (y*(CW*2+gap) + x)*4, i3 = (y*(CW*2+gap) + x + CW + gap)*4;
    cv.px[i2] = a.px[i1]; cv.px[i2+1] = a.px[i1+1]; cv.px[i2+2] = a.px[i1+2]; cv.px[i2+3] = 255;
    cv.px[i3] = b.px[i1]; cv.px[i3+1] = b.px[i1+1]; cv.px[i3+2] = b.px[i1+2]; cv.px[i3+3] = 255;
  }
  return cv;
}

// ── 胶片条：一次转场的 5 帧，上下两排（上 App / 下 原型）──
function filmstrip() {
  const turns = [1, 0.75, 0.5, 0.25, 0];
  const cols = turns.length, gap = 8 * SS, pad = 10 * SS;
  const sw = Math.round(CW * 0.42), sh = Math.round(CH * 0.42);
  const out = new Canvas(cols * (sw + gap) + gap, 2 * (sh + gap) + gap);
  out.clear(8, 8, 10);
  for (let c = 0; c < cols; c++) {
    const app = renderApp(turns[c], 1, 'd');
    const html = renderHTML(turns[c]);
    // 最近邻缩放
    for (let y = 0; y < sh; y++) for (let x = 0; x < sw; x++) {
      const sx = Math.floor(x / sw * CW), sy = Math.floor(y / sh * CH);
      const si = (sy * CW + sx) * 4;
      const dx = gap + c * (sw + gap) + x, dy = gap + y;
      let di = (dy * out.w + dx) * 4;
      out.px[di] = app.px[si]; out.px[di+1] = app.px[si+1]; out.px[di+2] = app.px[si+2]; out.px[di+3] = 255;
      const dy2 = gap + sh + gap + y;
      di = (dy2 * out.w + dx) * 4;
      out.px[di] = html.px[si]; out.px[di+1] = html.px[si+1]; out.px[di+2] = html.px[si+2]; out.px[di+3] = 255;
    }
  }
  out.save(path.join(outDir, 'filmstrip.png'));
  console.log('已输出 filmstrip.png （上排=App，下排=原型，左→右 = turn 1→0）');
}

const turn = process.argv[2] !== undefined ? parseFloat(process.argv[2]) : 0;
const outDir = path.join(ROOT, 'docs/redesign/prism-preview');
fs.mkdirSync(outDir, { recursive: true });
const P = parseFloat(process.env.PERSP || '0.90');
const app = process.env.MODE3D ? renderApp3D(turn, 1, 'd', P) : renderApp(turn, 1, 'd');
const html = renderHTML(turn);
app.save(path.join(outDir, 'app-turn' + turn + '.png'));
html.save(path.join(outDir, 'html-turn' + turn + '.png'));
const side = compose(app, html);
side.save(path.join(outDir, 'compare-turn' + turn + '.png'));
console.log('已输出 compare-turn' + turn + '.png  (左=App, 右=原型)');
if (process.argv[2] === 'strip') filmstrip();
