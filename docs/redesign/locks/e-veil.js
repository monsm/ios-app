import * as THREE from 'three';

/**
 * e-veil — 帷
 * φ70 圆形锁体。正面压一层 φ66 的深色半透明玻璃，玻璃下沉 0.85mm，
 * 里面藏着齿环与拉丝盘；玻璃四周由一圈 φ68.8 的抛光金属环托住，
 * 只让 1.5mm 的高光边露在外面。
 *
 * 全部使用 Box / Cylinder / Sphere / Cone 与手搓 BufferGeometry，
 * 单位毫米，+Z 朝观察者，圆柱段数 <= 64。
 */

const SEG = 64;

/** 手搓的薄环形板（外壁 / 正面 / 内壁 / 背面），替代 Torus / Lathe / Extrude。 */
function ringGeometry(rOuter, rInner, thickness, segments) {
  const geo = new THREE.BufferGeometry();
  const pos = [];
  const idx = [];
  const z0 = 0;
  const z1 = thickness;

  for (let i = 0; i <= segments; i++) {
    const a = (i / segments) * Math.PI * 2;
    const c = Math.cos(a);
    const s = Math.sin(a);
    pos.push(rOuter * c, rOuter * s, z0);
    pos.push(rOuter * c, rOuter * s, z1);
    pos.push(rInner * c, rInner * s, z1);
    pos.push(rInner * c, rInner * s, z0);
  }

  for (let i = 0; i < segments; i++) {
    const a = i * 4;
    const b = (i + 1) * 4;
    // 外壁
    idx.push(a, b, b + 1, a, b + 1, a + 1);
    // 正面
    idx.push(a + 1, b + 1, b + 2, a + 1, b + 2, a + 2);
    // 内壁
    idx.push(a + 2, b + 2, b + 3, a + 2, b + 3, a + 3);
    // 背面
    idx.push(a + 3, b + 3, b, a + 3, b, a);
  }

  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

/** 手搓的方齿环：玻璃底下那层金属织理，带顶面与底面的实体薄环。 */
function gearRingGeometry(teeth, rInner, rRoot, rTip, thickness, stepsPerTooth) {
  const geo = new THREE.BufferGeometry();
  const total = teeth * stepsPerTooth;
  const pos = [];
  const idx = [];
  const radii = [];

  for (let i = 0; i < total; i++) {
    const phase = (i % stepsPerTooth) / stepsPerTooth;
    radii.push(phase < 0.5 ? rTip : rRoot);
  }

  for (let i = 0; i <= total; i++) {
    const a = (i / total) * Math.PI * 2;
    const c = Math.cos(a);
    const s = Math.sin(a);
    const r = radii[i % total];
    // 外壁 z0 / 外壁 z1 / 内壁 z1 / 内壁 z0
    pos.push(r * c, r * s, 0);
    pos.push(r * c, r * s, thickness);
    pos.push(rInner * c, rInner * s, thickness);
    pos.push(rInner * c, rInner * s, 0);
  }

  for (let i = 0; i < total; i++) {
    const a = i * 4;
    const b = ((i + 1) % total) * 4;
    // 外壁
    idx.push(a, b, b + 1, a, b + 1, a + 1);
    // 顶面（齿顶的台面）
    idx.push(a + 1, b + 1, b + 2, a + 1, b + 2, a + 2);
    // 内壁
    idx.push(a + 2, b + 2, b + 3, a + 2, b + 3, a + 3);
    // 底面
    idx.push(a + 3, b + 3, b, a + 3, b, a);
  }

  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

function makeMaterials() {
  return {
    // 1. 拉丝抛光的浅色金属
    metal: new THREE.MeshStandardMaterial({
      color: 0xbcb7ab,
      metalness: 1.0,
      roughness: 0.32,
      envMapIntensity: 1.05
    }),
    // 2. 枪灰暗金属，藏在玻璃底下
    metalDark: new THREE.MeshStandardMaterial({
      color: 0x4b4943,
      metalness: 1.0,
      roughness: 0.48,
      envMapIntensity: 0.85,
      side: THREE.DoubleSide
    }),
    // 3. 哑光黑，用来做缝隙、沉台、密封圈
    black: new THREE.MeshStandardMaterial({
      color: 0x0a0a0b,
      metalness: 0.25,
      roughness: 0.78
    }),
    // 4. 唯一的半透明：深色烟熏玻璃
    glass: new THREE.MeshPhysicalMaterial({
      color: 0x0b0f12,
      metalness: 0.0,
      roughness: 0.05,
      transmission: 0.58,
      thickness: 2.0,
      ior: 1.52,
      clearcoat: 1.0,
      clearcoatRoughness: 0.03,
      transparent: true,
      opacity: 0.94,
      envMapIntensity: 1.25,
      side: THREE.FrontSide
    })
  };
}

export const DESIGNS = [
  {
    id: 'e-veil',
    name: '帷',
    note: '光在玻璃下面沉成一层薄雾，金属只肯露出一小圈齿纹。',
    build: function () {
      const g = new THREE.Group();
      g.name = 'e-veil';

      const mats = makeMaterials();
      const metal = mats.metal;
      const dark = mats.metalDark;
      const black = mats.black;
      const glassMat = mats.glass;

      // ---- 01 后壳底盘 φ70：比正面短 1mm，形成一圈背缝 ----
      const backPlate = new THREE.Mesh(
        new THREE.CylinderGeometry(35, 35, 6.0, SEG, 1),
        black
      );
      backPlate.rotation.x = Math.PI / 2;
      backPlate.position.z = -3.0;
      g.add(backPlate);

      // ---- 02 金属主体 φ70，正面到 z = 9.0 ----
      const body = new THREE.Mesh(
        new THREE.CylinderGeometry(34.9, 35, 9.0, SEG, 1),
        metal
      );
      body.rotation.x = Math.PI / 2;
      body.position.z = 4.5;
      g.add(body);

      // ---- 03 侧壁分模缝：外凸 0.04 的黑色细带，摸得到 ----
      const seamBand = new THREE.Mesh(
        new THREE.CylinderGeometry(35.04, 35.04, 0.28, SEG, 1),
        black
      );
      seamBand.rotation.x = Math.PI / 2;
      seamBand.position.z = 3.8;
      g.add(seamBand);

      // ---- 04 外缘倒角：φ70 -> φ68.8，1.2mm 的斜边 ----
      const chamfer = new THREE.Mesh(
        new THREE.CylinderGeometry(34.4, 35, 1.2, SEG, 1),
        metal
      );
      chamfer.rotation.x = Math.PI / 2;
      chamfer.position.z = 9.6;
      g.add(chamfer);

      // ---- 05 玻璃井底的暗环：r 29.5 -> 33.4，压出 0.25mm 的落座面 ----
      const seatRing = new THREE.Mesh(ringGeometry(33.4, 29.5, 0.25, SEG), black);
      seatRing.position.z = 9.0;
      g.add(seatRing);

      // ---- 06 玻璃下的金属底盘 φ59：托住齿环与中央拉丝盘 ----
      const underPlate = new THREE.Mesh(
        new THREE.CylinderGeometry(29.5, 29.5, 0.25, SEG, 1),
        dark
      );
      underPlate.rotation.x = Math.PI / 2;
      underPlate.position.z = 9.375;
      g.add(underPlate);

      // ---- 07 齿环：48 齿，φ52.6，只透过玻璃隐约可见 ----
      const gear = new THREE.Mesh(gearRingGeometry(48, 22.5, 24.4, 26.3, 0.5, 4), dark);
      gear.position.z = 9.5;
      g.add(gear);

      // ---- 08 中央拉丝圆盘 φ42，比齿环低 0.1mm ----
      const centerDisc = new THREE.Mesh(
        new THREE.CylinderGeometry(21, 21, 0.4, SEG, 1),
        metal
      );
      centerDisc.rotation.x = Math.PI / 2;
      centerDisc.position.z = 9.7;
      g.add(centerDisc);

      // ---- 09 玻璃下的锥形指示点 φ4：正对中央，尖顶朝观察者 ----
      const sensor = new THREE.Mesh(
        new THREE.ConeGeometry(2.0, 1.0, 32, 1),
        dark
      );
      sensor.rotation.x = Math.PI / 2;
      sensor.position.z = 10.1;
      g.add(sensor);

      // ---- 10 玻璃下的一圈极细黑色密封线 φ65.6 ----
      const gasket = new THREE.Mesh(ringGeometry(32.8, 32.3, 0.18, SEG), black);
      gasket.position.z = 10.42;
      g.add(gasket);

      // ---- 11 半透明深色玻璃圆片 φ66，厚 2.0，比金属主体小 φ4 ----
      const glassDisc = new THREE.Mesh(
        new THREE.CylinderGeometry(33, 33, 2.0, SEG, 1),
        glassMat
      );
      glassDisc.rotation.x = Math.PI / 2;
      glassDisc.position.z = 11.6;
      glassDisc.renderOrder = 2;
      g.add(glassDisc);

      // ---- 12 玻璃顶面内缩的一圈 0.35mm 台阶，指腹能定位中心 ----
      const glassStep = new THREE.Mesh(
        new THREE.CylinderGeometry(26.2, 27.0, 0.4, SEG, 1),
        glassMat
      );
      glassStep.rotation.x = Math.PI / 2;
      glassStep.position.z = 12.8;
      glassStep.renderOrder = 3;
      g.add(glassStep);

      // ---- 13 抛光金属护环 φ68.8：只露出 1.5mm 的高光边 ----
      const guardRing = new THREE.Mesh(ringGeometry(34.4, 32.9, 2.75, SEG), metal);
      guardRing.position.z = 9.85;
      g.add(guardRing);

      // ---- 14 护环内侧的倒角：0.6mm 斜面，让高光边更薄 ----
      const ringBevel = new THREE.Mesh(
        new THREE.CylinderGeometry(34.0, 34.4, 0.6, SEG, 1, true),
        metal
      );
      ringBevel.rotation.x = Math.PI / 2;
      ringBevel.position.z = 12.9;
      g.add(ringBevel);

      // ---- 15 底部拾音微孔 φ1.6，落在抛光护环面上 ----
      const micHole = new THREE.Mesh(
        new THREE.CylinderGeometry(0.8, 0.8, 0.45, 24, 1),
        black
      );
      micHole.rotation.x = Math.PI / 2;
      micHole.position.set(0, -33.55, 12.32);
      g.add(micHole);

      // ---- 16 背面安装沉台 φ58，凹进 0.8mm ----
      const backRecess = new THREE.Mesh(
        new THREE.CylinderGeometry(29, 29, 0.8, SEG, 1),
        black
      );
      backRecess.rotation.x = Math.PI / 2;
      backRecess.position.z = -5.85;
      g.add(backRecess);

      // ---- 17 背面定位方台：一颗 12x12x1.2 的暗色凸台 ----
      const boss = new THREE.Mesh(
        new THREE.BoxGeometry(12, 12, 1.2),
        black
      );
      boss.position.z = -6.4;
      boss.rotation.z = Math.PI / 8;
      g.add(boss);

      g.userData.designId = 'e-veil';
      g.userData.unit = 'mm';
      g.userData.frontZ = 13.2;
      g.userData.backZ = -7.0;
      g.userData.parts = 17;
      g.userData.materials = 4;

      return g;
    },
    highlight: { accent: null, sensor: null, mover: null }
  }
];