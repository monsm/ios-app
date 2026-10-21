import * as THREE from 'three';

const SEG = 64;

/* 四种材质：拉丝钛、哑光黑、香槟金、烟色玻璃 */
const MAT_STEEL = new THREE.MeshStandardMaterial({
  color: 0x9298a1,
  metalness: 0.96,
  roughness: 0.27
});

const MAT_DARK = new THREE.MeshStandardMaterial({
  color: 0x0e1013,
  metalness: 0.45,
  roughness: 0.68
});

const MAT_BRASS = new THREE.MeshStandardMaterial({
  color: 0xc9a25f,
  metalness: 1.0,
  roughness: 0.22
});

const MAT_GLASS = new THREE.MeshPhysicalMaterial({
  color: 0x0a1220,
  metalness: 0.15,
  roughness: 0.05,
  transparent: true,
  opacity: 0.72,
  clearcoat: 1.0,
  clearcoatRoughness: 0.03,
  envMapIntensity: 1.4
});

/* 圆盘：主柱 + 上下 45° 倒角，全部由圆柱段拼出 */
function puck(radius, height, z0, material, bevel) {
  const c = Math.min(bevel === undefined ? 0.7 : bevel, height * 0.3, radius * 0.1);
  const bodyH = height - c * 2;
  const group = new THREE.Group();

  const body = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, bodyH, SEG), material);
  body.rotation.x = Math.PI / 2;
  body.position.z = z0 + c + bodyH / 2;
  group.add(body);

  const bottom = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius - c, c, SEG), material);
  bottom.rotation.x = Math.PI / 2;
  bottom.position.z = z0 + c / 2;
  group.add(bottom);

  const top = new THREE.Mesh(new THREE.CylinderGeometry(radius - c, radius, c, SEG), material);
  top.rotation.x = Math.PI / 2;
  top.position.z = z0 + height - c / 2;
  group.add(top);

  return group;
}

/* 1.5mm 影缝：内缩的暗色柱，把上下两层托住 */
function shadowGap(radius, height, z0) {
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, height, SEG), MAT_DARK);
  mesh.rotation.x = Math.PI / 2;
  mesh.position.z = z0 + height / 2;
  return mesh;
}

/* 平顶薄盘：顶面车纹与传感器底座 */
function slab(radius, height, z0, material) {
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, height, SEG), material);
  mesh.rotation.x = Math.PI / 2;
  mesh.position.z = z0 + height / 2;
  return mesh;
}

export const DESIGNS = [
  {
    id: 'c-stack',
    name: '叠',
    note: '四层钛盘在 1.5mm 的影缝里逐级收束，像一枚被轻轻旋开的机芯。',
    build: function () {
      const g = new THREE.Group();
      g.name = 'c-stack';

      // L1 基座 φ68：下段 7mm、车削腰槽 3mm、上段 4.5mm
      g.add(puck(34, 7, 0, MAT_STEEL, 0.9));
      g.add(slab(32.2, 3, 7, MAT_DARK));
      g.add(puck(34, 4.5, 10, MAT_STEEL, 0.8));

      // 基座台肩上的金色对准刻线
      const index = new THREE.Mesh(new THREE.BoxGeometry(4.4, 0.9, 0.45), MAT_BRASS);
      index.position.set(31.1, 0, 14.72);
      g.add(index);

      // 影缝 1（14.5 → 16.0）
      g.add(shadowGap(25.0, 1.5, 14.5));

      // L2 φ58
      g.add(puck(29, 10, 16, MAT_STEEL, 0.9));

      // 影缝 2（26.0 → 27.5）
      g.add(shadowGap(21.0, 1.5, 26));

      // L3 φ49
      g.add(puck(24.5, 8.5, 27.5, MAT_STEEL, 0.8));

      // 影缝 3（36.0 → 37.5）
      g.add(shadowGap(17.5, 1.5, 36));

      // L4 顶盘 φ40
      g.add(puck(20, 8, 37.5, MAT_STEEL, 0.8));

      // 顶面同心车纹：两级台阶 + 一圈金线
      g.add(slab(16.5, 0.5, 45.5, MAT_STEEL));
      g.add(slab(13.6, 0.4, 46, MAT_STEEL));
      g.add(slab(12.1, 0.22, 46.4, MAT_BRASS));

      // 传感器：暗盘 + 烟色玻璃穹顶
      g.add(slab(11.2, 0.5, 46.62, MAT_DARK));
      const dome = new THREE.Mesh(
        new THREE.SphereGeometry(10, SEG, 32, 0, Math.PI * 2, 0, Math.PI / 2),
        MAT_GLASS
      );
      dome.rotation.x = Math.PI / 2;
      dome.scale.set(1, 0.32, 1);
      dome.position.z = 47.12;
      g.add(dome);

      g.traverse(function (o) {
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
        }
      });

      return g;
    },
    highlight: { accent: null, sensor: null, mover: null }
  }
];
