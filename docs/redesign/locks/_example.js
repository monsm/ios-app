import * as THREE from 'three';

// ═══════════════════════════════════════════════════════════════
// 技术示例 —— 只为演示格式，形态本身很平庸，**不要照抄**
// ═══════════════════════════════════════════════════════════════
// 它演示了三件事:
//   1. 怎么在文件内自建材质
//   2. 怎么用 mm 建模、几何体怎么摆
//   3. 怎么导出 highlight（状态着色用）

function metal(color, rough) {
  return new THREE.MeshStandardMaterial({ color: color, metalness: 1.0, roughness: rough });
}

function box(w, h, d, mat, x, y, z) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  m.position.set(x || 0, y || 0, z || 0);
  return m;
}

function cyl(r, h, mat, x, y, z, seg) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, seg || 64), mat);
  m.position.set(x || 0, y || 0, z || 0);
  return m;
}

export const DESIGNS = [
  {
    id: 'example-disc',
    name: '示例圆盘',
    note: '技术示例，不要照抄',
    build: function () {
      const g = new THREE.Group();
      const steel = metal(0x9AA0A8, 0.28);
      const dark = metal(0x1A1C20, 0.5);

      // 主体圆盘 φ64，厚 20mm（圆柱默认竖着，转 90° 让圆面朝 +Z）
      const body = cyl(32, 20, dark, 0, 0, 0, 64);
      body.rotation.x = Math.PI / 2;
      g.add(body);

      // 外环（略大一圈，凸出）
      const ring = cyl(34, 6, steel, 0, 0, 8, 72);
      ring.rotation.x = Math.PI / 2;
      g.add(ring);

      // 中心指纹（凹陷）
      const sensor = cyl(10, 4, metal(0x07090C, 0.05), 0, 0, 11, 48);
      sensor.rotation.x = Math.PI / 2;
      g.add(sensor);

      // 倒角层（用略小的圆柱叠出层次）
      const step = cyl(28, 3, steel, 0, 0, 11, 64);
      step.rotation.x = Math.PI / 2;
      g.add(step);

      return g;
    },
    highlight: {
      accent: null,
      sensor: null,
      mover: null,
    },
  },
];
