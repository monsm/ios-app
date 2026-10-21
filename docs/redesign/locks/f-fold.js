import * as THREE from 'three';

// ---------------------------------------------------------------------------
// f-fold / 折
// A 66 x 290 mm square-ish lock body whose face is split by one 45° crease.
// Left facet leans -8°, right facet leans +8°. The crease is a real folded
// geometry (hand-built BufferGeometry, 8° half-planes meeting on a spine),
// not a texture. Everything else is quiet: a hairline perimeter gap, a soft
// chamfer, a shallow finger channel and a recessed sensor window.
//
// Units: millimetres. Z faces the viewer. No Extrude/Lathe/Tube/Torus.
// ---------------------------------------------------------------------------

const DEG = Math.PI / 180;
const W = 66;          // overall width  (X)
const H = 290;         // overall height (Y)
const D = 26;          // body depth     (Z, negative = into the door)
const TILT = 8 * DEG;  // facet tilt away from the front plane

// Materials: exactly four.
const MAT = {
  face: new THREE.MeshStandardMaterial({
    color: 0xd8d5cf,
    roughness: 0.36,
    metalness: 0.82
  }),
  flank: new THREE.MeshStandardMaterial({
    color: 0xa9a6a0,
    roughness: 0.52,
    metalness: 0.9
  }),
  gap: new THREE.MeshStandardMaterial({
    color: 0x14161a,
    roughness: 0.95,
    metalness: 0.2
  }),
  lens: new THREE.MeshStandardMaterial({
    color: 0x1b2a2c,
    roughness: 0.18,
    metalness: 0.35,
    emissive: 0x0a1516,
    emissiveIntensity: 0.55
  })
};

// Small helpers -------------------------------------------------------------

function box(w, h, d, mat) {
  return new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
}

function cyl(rTop, rBot, h, seg, mat) {
  return new THREE.Mesh(new THREE.CylinderGeometry(rTop, rBot, h, seg), mat);
}

// Flat face panel lying in XY, extruded along +Z by 'thick' from z = 0.
function panel(w, h, thick, mat) {
  const g = new THREE.BoxGeometry(w, h, thick);
  g.translate(0, 0, thick * 0.5);
  return new THREE.Mesh(g, mat);
}

// Rounded-rect ring made from 4 boxes + 4 corner cylinders (a "slot" outline).
// Used for the seam shadow and the finger channel. No ExtrudeGeometry.
function slotRing(w, h, r, bar, mat) {
  const grp = new THREE.Group();
  const innerW = w - 2 * r;
  const innerH = h - 2 * r;

  const top = box(innerW, bar, bar, mat);
  top.position.set(0, h * 0.5 - bar * 0.5, 0);
  const bot = top.clone();
  bot.position.y = -top.position.y;

  const left = box(bar, innerH, bar, mat);
  left.position.set(-w * 0.5 + bar * 0.5, 0, 0);
  const right = left.clone();
  right.position.x = -left.position.x;

  grp.add(top, bot, left, right);

  const cR = r + bar * 0.5;
  const cH = Math.max(innerH, 0.001);
  const corners = [
    [-w * 0.5 + cR, h * 0.5 - cR],
    [w * 0.5 - cR, h * 0.5 - cR],
    [-w * 0.5 + cR, -h * 0.5 + cR],
    [w * 0.5 - cR, -h * 0.5 + cR]
  ];
  for (let i = 0; i < corners.length; i++) {
    const c = cyl(bar * 0.5, bar * 0.5, cH, 18, mat);
    c.rotation.z = Math.PI * 0.5; // lay along Y
    c.rotation.y = Math.PI * 0.5; // align axis with Y after lay-down
    // simpler: cylinder axis is Y by default; we want it along Y -> keep it flat
    c.rotation.set(0, 0, 0);
    c.geometry.dispose();
    c.geometry = new THREE.CylinderGeometry(bar * 0.5, bar * 0.5, innerH, 18, 1);
    c.position.set(c[0], c[1], 0);
    // The cylinder axis must run vertically only at the ring's straight sides;
    // at the corners we want a quarter-round in plan view. Use a thin disc
    // instead: a cylinder with axis = Z, height = bar.
    c.geometry.dispose();
    c.geometry = new THREE.CylinderGeometry(r, r, bar, 18, 1);
    c.rotation.x = Math.PI * 0.5;
    grp.add(c);
  }

  return grp;
}

// Folding face --------------------------------------------------------------
//
// The face is two planar quads. In plan view (looking down -Y), each facet is
// a straight line: left runs from x=-33 at z=zL to x=0 at z=0, right mirrors
// it. "8° tilt" means each facet's plane is rotated 8° about Y relative to the
// front plane. We build the quads from explicit vertices so the crease is
// genuinely a ridge with a sharp angle between the two planes.

function foldFaceGeometry() {
  const zL = W * 0.5 * Math.tan(TILT); // 66/2 * tan8° ≈ 4.64 mm
  const zR = -zL;
  const zSpine = 0;

  // Front-most z of each side (outer edge) and spine depth.
  const zOuterL = zL;   // left outer edge is furthest forward
  const zOuterR = zR;

  const positions = [];
  const normals = [];
  const uvs = [];

  function addQuad(a, b, c, d) {
    // a,b,c,d counter-clockwise seen from +Z
    const tri = [a, b, c, a, c, d];
    const n = new THREE.Vector3()
      .subVectors(b, a)
      .cross(new THREE.Vector3().subVectors(c, a))
      .normalize();
    for (const v of tri) {
      positions.push(v.x, v.y, v.z);
      normals.push(n.x, n.y, n.z);
      uvs.push((v.x + W * 0.5) / W, (v.y + H * 0.5) / H);
    }
  }

  const spineTop = new THREE.Vector3(0, H * 0.5, zSpine);
  const spineBot = new THREE.Vector3(0, -H * 0.5, zSpine);
  const leftTop = new THREE.Vector3(-W * 0.5, H * 0.5, zOuterL);
  const leftBot = new THREE.Vector3(-W * 0.5, -H * 0.5, zOuterL);

  // Left facet: outer edge -> spine
  addQuad(leftBot, leftTop, spineTop, spineBot);

  const rightTop = new THREE.Vector3(W * 0.5, H * 0.5, zOuterR);
  const rightBot = new THREE.Vector3(W * 0.5, -H * 0.5, zOuterR);
  addQuad(spineBot, spineTop, rightTop, rightBot);

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(normals, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.computeVertexNormals();
  return { geo, zL };
}

// Body back shell -----------------------------------------------------------
// A slightly inset chassis behind the face, so the folded face reads as a lid
// sitting on a milled body, with a visible 0.6 mm shadow gap all round.

function buildBody() {
  const grp = new THREE.Group();
  const inset = 0.6;

  // Chassis: sits behind the fold, slightly narrower than the face.
  const chassis = box(W - inset * 2, H - inset * 2, D - 8, MAT.flank);
  chassis.position.set(0, 0, -8 - (D - 8) * 0.5);
  grp.add(chassis);

  // Deep shadow gap between face and chassis: four thin bars.
  const gap = 1.4;
  grp.add(
    (() => { const m = box(W - gap * 2, gap, gap, MAT.gap); m.position.set(0, H * 0.5 - inset - gap * 0.5, -0.7); return m; })(),
    (() => { const m = box(W - gap * 2, gap, gap, MAT.gap); m.position.set(0, -H * 0.5 + inset + gap * 0.5, -0.7); return m; })(),
    (() => { const m = box(gap, H - gap * 2, gap, MAT.gap); m.position.set(-W * 0.5 + inset + gap * 0.5, 0, -0.7); return m; })(),
    (() => { const m = box(gap, H - gap * 2, gap, MAT.gap); m.position.set(W * 0.5 - inset - gap * 0.5, 0, -0.7); return m; })()
  );

  return grp;
}

// Knurled thumb-turn: a knurled disc built from a low-seg cylinder plus a ring
// of small boxes. Kept subordinate to the fold.

function buildThumbTurn() {
  const grp = new THREE.Group();
  const base = cyl(9.5, 9.5, 1.2, 48, MAT.flank);
  base.rotation.x = Math.PI * 0.5;
  grp.add(base);

  const drum = cyl(8.2, 8.2, 4.4, 48, MAT.face);
  drum.rotation.x = Math.PI * 0.5;
  drum.position.z = 2.8;
  grp.add(drum);

  // chamfer at the finger edge
  const chamfer = cyl(8.6, 9.5, 1.1, 48, MAT.face);
  chamfer.rotation.x = Math.PI * 0.5;
  chamfer.position.z = 0.9;
  grp.add(chamfer);

  // fine knurl: 24 low bars, deliberately subtle
  const knurls = 24;
  for (let i = 0; i < knurls; i++) {
    const a = (i / knurls) * Math.PI * 2;
    const k = box(0.55, 0.55, 3.2, MAT.flank);
    k.position.set(Math.cos(a) * 7.9, Math.sin(a) * 7.9, 3.1);
    k.rotation.z = a;
    k.rotation.x = Math.PI * 0.5;
    grp.add(k);
  }

  return grp;
}

// Recessed sensor window, sitting in the right facet.

function buildSensor() {
  const grp = new THREE.Group();

  // milled pocket walls: a shallow dark well
  const pocket = box(13.2, 34, 1.8, MAT.gap);
  pocket.position.z = 0.5;
  grp.add(pocket);

  // lens: a rounded slab approximated by a box + two cylinders
  const lens = box(10.4, 30.0, 1.0, MAT.lens);
  lens.position.z = 1.45;
  grp.add(lens);

  const capT = cyl(5.2, 5.2, 1.0, 40, MAT.lens);
  capT.rotation.x = Math.PI * 0.5;
  capT.position.set(0, 15.0 - 5.2, 1.45);
  grp.add(capT);
  const capB = capT.clone();
  capB.position.y = -(15.0 - 5.2);
  grp.add(capB);

  // the tiny indicator slit under the lens
  const slit = box(6.4, 0.9, 0.8, MAT.lens);
  slit.position.set(0, -18.4, 1.5);
  grp.add(slit);

  // the well's chamfered lip catches the fold light
  const lip = box(14.0, 34.8, 0.7, MAT.flank);
  lip.position.z = 0.15;
  grp.add(lip);

  return grp;
}

// Finger channel: a shallow slanted void near the lower edge.

function buildFingerChannel() {
  const grp = new THREE.Group();

  // Dark void, slightly rotated so it follows the right facet's slope.
  const voidBar = box(20, 3.4, 1.4, MAT.gap);
  voidBar.position.set(0, 0, 0.3);
  grp.add(voidBar);

  // Two bright lips; asymmetric depth makes it read as a milled groove.
  const lipA = box(21.2, 1.1, 1.2, MAT.face);
  lipA.position.set(0, 2.3, 0.9);
  grp.add(lipA);

  const lipB = box(21.2, 1.9, 2.0, MAT.face);
  lipB.position.set(0, -2.3, 1.5);
  grp.add(lipB);

  // The 45° crease line continuation entering the channel.
  const tick = box(0.8, 5.6, 0.9, MAT.gap);
  tick.position.set(0, 0, 1.1);
  grp.add(tick);

  return grp;
}

// Build ---------------------------------------------------------------------

function build() {
  const g = new THREE.Group();
  g.name = 'f-fold';

  const { geo: faceGeo, zL } = foldFaceGeometry();

  // The folded lid, slightly proud of the chassis.
  const face = new THREE.Mesh(faceGeo, MAT.face);
  face.name = 'fold-face';
  g.add(face);

  // Back of the lid: same footprint, flush, closes the shell.
  const lidBack = box(W, H, 2.2, MAT.flank);
  lidBack.position.set(0, 0, -1.1);
  g.add(lidBack);

  // Main body.
  const body = buildBody();
  g.add(body);

  // Perimeter seam: a hairline 45° chamfer band around the lid edge.
  // Four thin bars follow the silhouette; built from boxes only.
  const cham = 0.45;
  const edgeFront = Math.max(zL, -zL, 0);
  const bandY1 = box(W, cham, cham, MAT.flank);
  bandY1.position.set(0, H * 0.5, edgeFront - cham * 0.5);
  const bandY2 = bandY1.clone();
  bandY2.position.y = -H * 0.5;
  const bandX1 = box(cham, H, cham, MAT.flank);
  bandX1.position.set(-W * 0.5, 0, edgeFront - cham * 0.5);
  const bandX2 = bandX1.clone();
  bandX2.position.x = W * 0.5;
  g.add(bandY1, bandY2, bandX1, bandX2);

  // Crease: a sharp spine cap. One long thin bar tucked into the ridge so the
  // two facets do not z-fight and the highlight reads as a crisp line.
  const spine = box(0.9, H, zL * 2 + 0.4, MAT.face);
  spine.position.set(0, 0, 0);
  g.add(spine);

  // Spine end caps: tiny blocks that terminate the ridge top and bottom.
  const capTop = box(1.6, 1.6, 2.0, MAT.flank);
  capTop.position.set(0, H * 0.5 - 0.8, 0);
  const capBot = capTop.clone();
  capBot.position.y = -(H * 0.5 - 0.8);
  g.add(capTop, capBot);

  // Thumb-turn on the left facet, low, clear of the crease.
  const turn = buildThumbTurn();
  turn.position.set(-19.5, -96, 2.2);
  turn.rotation.y = -TILT; // sits on the tilted facet
  g.add(turn);

  // Sensor window on the right facet, higher up.
  const sensor = buildSensor();
  sensor.position.set(19.0, 34, 1.9);
  sensor.rotation.y = TILT;
  g.add(sensor);

  // Finger channel on the right facet near the lower end.
  const channel = buildFingerChannel();
  channel.position.set(18.6, -150, 1.6);
  channel.rotation.y = TILT;
  channel.rotation.z = -Math.PI * 0.25; // 45° slot, echoing the fold
  g.add(channel);

  // A single hairline status slit at the top, on the spine axis.
  const status = box(4.2, 0.7, 0.6, MAT.lens);
  status.position.set(0, H * 0.5 - 14, 0.55);
  g.add(status);

  // Mounting flange hidden behind: gives the silhouette a real shadow line.
  const flange = box(W - 6, H - 6, 4, MAT.flank);
  flange.position.set(0, 0, -D + 2);
  g.add(flange);

  return g;
}

export const DESIGNS = [
  {
    id: 'f-fold',
    name: '折',
    note: '一道 45° 折脊把正脸压成两个面，光自己完成分色，其余只剩必要的缝与孔。',
    build,
    highlight: { accent: null, sensor: null, mover: null }
  }
];
