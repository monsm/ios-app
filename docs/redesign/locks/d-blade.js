import * as THREE from 'three';

/* ------------------------------------------------------------------
 * 刃 / d-blade
 * 60 × 300 mm 的非对称锁体。
 * 左缘一根直线，右缘一段 R500 的外凸弧 —— 整块体的形，只有这一道弧。
 * 剩下的都收进 22 mm 的厚度里：一圈压边、一道竖向分缝、一处指腹的凹陷。
 * 单位 mm；X 向右，Y 向上，Z 指向观察者；正面基准面 z = 0。
 * ------------------------------------------------------------------ */

const W = 60;
const H = 300;
const R = 500;
const HH = H / 2;
const LEFT = -W / 2;
const ARC_CX = W / 2 - R;   // 弧心 (-470, 0)：让弧在 y = 0 处正好落在 x = +30
const DEPTH = 22;
const ARC_SEG = 56;

const DECK_INSET = 3;       // 压边自外轮廓内缩 3 mm
const SEAM_X = -12;         // 品牌压线所在的竖向分缝
const SEAM_HALF = 0.35;

/* ------------------------------ 2D 工具 ------------------------------ */

function lineIntersect(a, b, c, d) {
  const rx = b[0] - a[0], ry = b[1] - a[1];
  const sx = d[0] - c[0], sy = d[1] - c[1];
  const den = rx * sy - ry * sx;
  if (Math.abs(den) < 1e-9) return null;
  const t = ((c[0] - a[0]) * sy - (c[1] - a[1]) * sx) / den;
  return [a[0] + rx * t, a[1] + ry * t];
}

// 逆时针多边形向内偏移 d（斜接）
function insetPolygon(poly, d) {
  if (!d) return poly.map(function (p) { return [p[0], p[1]]; });
  const n = poly.length;
  const nrm = [];
  for (let i = 0; i < n; i++) {
    const a = poly[i], b = poly[(i + 1) % n];
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const L = Math.hypot(dx, dy) || 1;
    nrm.push([-dy / L, dx / L]);        // 逆时针 → 左手法线即向内
  }
  const out = [];
  for (let i = 0; i < n; i++) {
    const p = (i - 1 + n) % n;
    const A = poly[p], B = poly[i], C = poly[(i + 1) % n];
    const n1 = nrm[p], n2 = nrm[i];
    const e1a = [A[0] + n1[0] * d, A[1] + n1[1] * d];
    const e1b = [B[0] + n1[0] * d, B[1] + n1[1] * d];
    const e2a = [B[0] + n2[0] * d, B[1] + n2[1] * d];
    const e2b = [C[0] + n2[0] * d, C[1] + n2[1] * d];
    const ip = lineIntersect(e1a, e1b, e2a, e2b);
    if (ip && Math.hypot(ip[0] - B[0], ip[1] - B[1]) < d * 8) out.push(ip);
    else out.push([(e1b[0] + e2a[0]) / 2, (e1b[1] + e2a[1]) / 2]);
  }
  return out;
}

/* ------------------------------ 轮廓 ------------------------------ */

// 整块锁体轮廓（内缩 inset）：左直线 + 上下短边 + 右侧 R500 弧
function bladeOutline(inset) {
  const xL = LEFT + inset;
  const yT = HH - inset;
  const r = R - inset;
  const tMax = Math.asin(yT / r);
  const pts = [[xL, -yT]];
  for (let i = 0; i <= ARC_SEG; i++) {
    const th = -tMax + (2 * tMax * i) / ARC_SEG;
    pts.push([ARC_CX + r * Math.cos(th), r * Math.sin(th)]);
  }
  pts.push([xL, yT]);
  return pts;
}

const DECK_Y = HH - DECK_INSET;      // 147
const DECK_XL = LEFT + DECK_INSET;   // -27
const SEAM_L = SEAM_X - SEAM_HALF;
const SEAM_R = SEAM_X + SEAM_HALF;

// 压边被竖向分缝切成两块：左边窄条守住直线边，右边带弧的大面跟着 R500 走
const POLY_DECK_L = [
  [DECK_XL, -DECK_Y],
  [SEAM_L, -DECK_Y],
  [SEAM_L, DECK_Y],
  [DECK_XL, DECK_Y]
];

function deckRightOutline() {
  const yT = DECK_Y;
  const r = R - DECK_INSET;
  const tMax = Math.asin(yT / r);
  const pts = [[SEAM_R, -yT]];
  for (let i = 0; i <= ARC_SEG; i++) {
    const th = -tMax + (2 * tMax * i) / ARC_SEG;
    pts.push([ARC_CX + r * Math.cos(th), r * Math.sin(th)]);
  }
  pts.push([SEAM_R, yT]);
  return pts;
}

/* --------------------------- 几何构造 --------------------------- */

function capFan(pts, flip, out) {
  let cx = 0, cy = 0;
  for (let i = 0; i < pts.length; i++) { cx += pts[i][0]; cy += pts[i][1]; }
  cx /= pts.length; cy /= pts.length;
  const cz = pts[0][2];
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i], b = pts[(i + 1) % pts.length];
    if (flip) out.push(cx, cy, cz, b[0], b[1], b[2], a[0], a[1], a[2]);
    else out.push(cx, cy, cz, a[0], a[1], a[2], b[0], b[1], b[2]);
  }
}

// 带前后倒角的平板：zBack → zFront，四道环（倒角环 / 直壁 / 直壁 / 倒角环）
function buildSlab(poly, zBack, zFront, chBack, chFront) {
  const rings = [{ d: chBack, z: zBack }];
  if (chBack > 0) rings.push({ d: 0, z: zBack + chBack });
  if (chFront > 0) rings.push({ d: 0, z: zFront - chFront });
  rings.push({ d: chFront, z: zFront });

  const rp = rings.map(function (r) {
    return insetPolygon(poly, r.d).map(function (p) { return [p[0], p[1], r.z]; });
  });

  const pos = [];
  for (let k = 0; k < rp.length - 1; k++) {
    const A = rp[k], B = rp[k + 1], n = A.length;
    for (let i = 0; i < n; i++) {
      const j = (i + 1) % n;
      pos.push(A[i][0], A[i][1], A[i][2], A[j][0], A[j][1], A[j][2], B[j][0], B[j][1], B[j][2]);
      pos.push(A[i][0], A[i][1], A[i][2], B[j][0], B[j][1], B[j][2], B[i][0], B[i][1], B[i][2]);
    }
  }
  capFan(rp[0], true, pos);                  // 背面朝 -Z
  capFan(rp[rp.length - 1], false, pos);     // 正面朝 +Z

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.computeVertexNormals();
  return geo;
}

// 超椭圆环：指纹槽不是正圆，指腹的形状更接近这个
function superRing(a, b, n, t, seg) {
  const p = 2 / n;
  const out = [];
  for (let i = 0; i < seg; i++) {
    const th = (i / seg) * Math.PI * 2;
    const c = Math.cos(th), s = Math.sin(th);
    out.push([
      a * t * Math.sign(c) * Math.pow(Math.abs(c), p),
      b * t * Math.sign(s) * Math.pow(Math.abs(s), p)
    ]);
  }
  return out;
}

// 沿一组环（外高 → 内低）铺曲面；最后可收口到中心点
function buildFunnel(rings, centerZ) {
  const seg = rings[0].pts.length;
  const rp = rings.map(function (r) {
    return r.pts.map(function (p) { return [p[0], p[1], r.z]; });
  });
  const pos = [];
  for (let k = 0; k < rp.length - 1; k++) {
    const A = rp[k], B = rp[k + 1];
    for (let i = 0; i < seg; i++) {
      const j = (i + 1) % seg;
      pos.push(A[i][0], A[i][1], A[i][2], A[j][0], A[j][1], A[j][2], B[j][0], B[j][1], B[j][2]);
      pos.push(A[i][0], A[i][1], A[i][2], B[j][0], B[j][1], B[j][2], B[i][0], B[i][1], B[i][2]);
    }
  }
  if (centerZ !== null && centerZ !== undefined) {
    const last = rp[rp.length - 1];
    for (let i = 0; i < seg; i++) {
      const j = (i + 1) % seg;
      pos.push(last[i][0], last[i][1], last[i][2], last[j][0], last[j][1], last[j][2], 0, 0, centerZ);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.computeVertexNormals();
  return geo;
}

/* --------------------------- 指纹槽剖面 --------------------------- */
/* 压边面 z = 1.0，槽口沿抬到 2.05，槽底 1.13 —— 一个浅碟，不是深坑 */

const POD = { x: 3, y: 56, a: 11, b: 26, n: 2.8, seg: 64 };
const POD_Y = 56;

const RIM_RINGS = [
  [1.000, 0.78],   // 埋进压边
  [1.000, 1.95],   // 外壁，高出压边 0.95
  [0.995, 2.02],
  [0.985, 2.05],   // 槽口外沿
  [0.900, 2.05],   // 1.9 mm 宽的顶面
  [0.870, 1.98],   // 内倒角，压回碟里
  [0.870, 1.92]
];

const WELL_RINGS = [
  [0.870, 1.92],
  [0.830, 1.62],
  [0.770, 1.40],
  [0.660, 1.24],
  [0.560, 1.155],
  [0.520, 1.140]
];

const WELL_FLOOR_Z = 1.13;

/* ------------------------------ 装配 ------------------------------ */

const DESIGNS_HL = { accent: null, sensor: null, mover: null };

export const DESIGNS = [
  {
    id: 'd-blade',
    name: '刃',
    note: '左边交给尺规，右边交给手掌；正面只剩指腹的一处浅碟，和一道橙色在缝里呼吸。',
    build: function () {
      const g = new THREE.Group();
      g.name = 'd-blade';

      // 4 种材质：阳极铝 / 哑黑内衬 / 抛光钢 / 品牌橙
      const bodyMat = new THREE.MeshStandardMaterial({ color: 0x34383e, metalness: 0.86, roughness: 0.36 });
      const darkMat = new THREE.MeshStandardMaterial({ color: 0x0c0e11, metalness: 0.30, roughness: 0.82 });
      const steelMat = new THREE.MeshStandardMaterial({ color: 0xc9ced4, metalness: 1.0, roughness: 0.16 });
      const accentMat = new THREE.MeshStandardMaterial({
        color: 0xe8642c, metalness: 0.40, roughness: 0.34,
        emissive: 0xe8642c, emissiveIntensity: 0.40
      });

      // 1 主锁体：60 × 300，右缘 R500，前后各一道倒角
      const body = new THREE.Mesh(buildSlab(bladeOutline(0), -DEPTH, 0, 1.1, 1.7), bodyMat);
      g.add(body);

      // 2 背面胶垫：内缩 6 mm，边缘留 1.4 mm 的落影
      const backPad = new THREE.Mesh(buildSlab(bladeOutline(6), -DEPTH - 2.6, -DEPTH + 1.4, 0.8, 0), darkMat);
      g.add(backPad);

      // 3 压边左条：守住直线边的那一条窄面
      const deckL = new THREE.Mesh(buildSlab(POLY_DECK_L, -1.0, 1.0, 0.3, 0.45), bodyMat);
      g.add(deckL);

      // 4 压边右板：跟着 R500 一路走的大面，与左条之间留 0.7 mm 分缝
      const deckR = new THREE.Mesh(buildSlab(deckRightOutline(), -1.0, 1.0, 0.3, 0.45), bodyMat);
      g.add(deckR);

      // 5 品牌压线：0.34 mm 宽，沉在缝底，比压边面低 0.3
      const accent = new THREE.Mesh(new THREE.BoxGeometry(0.34, 252, 0.52), accentMat);
      accent.position.set(SEAM_X, 0, 0.44);
      g.add(accent);

      // 6 指纹槽槽口：一圈 0.95 mm 高的边，顶面倒角压进碟里
      const podRim = new THREE.Mesh(buildFunnel(
        RIM_RINGS.map(function (r) {
          return { pts: superRing(POD.a, POD.b, POD.n, r[0], POD.seg), z: r[1] };
        }), null
      ), bodyMat);
      podRim.position.set(POD.x, POD_Y, 0);
      g.add(podRim);

      // 7 指腹浅碟：哑黑内衬，一路收进 1.13 深的碟底
      const podWell = new THREE.Mesh(buildFunnel(
        WELL_RINGS.map(function (r) {
          return { pts: superRing(POD.a, POD.b, POD.n, r[0], POD.seg), z: r[1] };
        }), WELL_FLOOR_Z
      ), darkMat);
      podWell.position.set(POD.x, POD_Y, 0);
      g.add(podWell);

      // 8 传感器钢托：椭圆，压在碟底，只露出一圈 0.9 mm 的边
      const sensorBase = new THREE.Mesh(new THREE.CylinderGeometry(4.5, 4.62, 0.36, 48), steelMat);
      sensorBase.rotation.x = Math.PI / 2;
      sensorBase.scale.set(1, 1, 1.30);
      sensorBase.position.set(POD.x, POD_Y, 1.28);
      g.add(sensorBase);

      // 9 传感器镜片：比钢托小 0.95，沉下去，一圈暗缝
      const lens = new THREE.Mesh(new THREE.CylinderGeometry(3.55, 3.55, 0.20, 48), darkMat);
      lens.rotation.x = Math.PI / 2;
      lens.scale.set(1, 1, 1.34);
      lens.position.set(POD.x, POD_Y, 1.55);
      g.add(lens);

      g.traverse(function (o) {
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
        }
      });

      DESIGNS_HL.accent = accent;
      DESIGNS_HL.sensor = lens;
      DESIGNS_HL.mover = null;

      return g;
    },
    highlight: DESIGNS_HL
  }
];
