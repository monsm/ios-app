#!/usr/bin/env node
// ============================================================================
// measure-locks.js — 实跑每个锁体设计的 build()，量出真数据
// ============================================================================
//
// 为什么需要这个:
//   node --check 只查语法。有设计语法完全正确，但 build() 里用了
//   g.userData / mesh.clone() / Vector3.subVectors() 之类只在运行时才报错的调用。
//   我第一版桩件缺这几个 API，导致 3 个设计被误判成"坏"。
//
//   这个工具用一套 three 桩件把 build() 真的跑一遍，能查出:
//     · build() 抛异常
//     · 返回的不是 Group
//     · highlight 有没有提供（iOS 状态着色需要）
//     · 网格数与三角面数（性能预算）
//     · 圆柱最大段数（>64 就超预算）
//
// 用法: node tools/measure-locks.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DIR = path.join(ROOT, 'docs', 'redesign', 'locks');


const THREE = {
  Group: class { constructor(){ this.children=[]; this.userData={}; this.position={set(){},x:0,y:0,z:0}; this.rotation={set(){},x:0,y:0,z:0}; this.scale={set(){},setScalar(){},x:1,y:1,z:1}; }
    add(o){ if(o) this.children.push(o); return this; }
    traverse(fn){ fn(this); this.children.forEach(c=>c.traverse?c.traverse(fn):fn(c)); }
    clone(){ const g=new this.constructor(); g.userData=Object.assign({},this.userData); return g; }
    remove(){ return this; } },
  Mesh: class { constructor(geo,mat){ this.geometry=geo; this.material=mat; this.userData={};
      this.position={set(){},copy(){return this;},x:0,y:0,z:0};
      this.rotation={set(){},x:0,y:0,z:0};
      this.scale={set(){},setScalar(){},copy(){return this;},x:1,y:1,z:1}; }
    traverse(fn){ fn(this); }
    clone(){ const m=new this.constructor(this.geometry, this.material);
      m.userData=Object.assign({},this.userData); return m; }
    add(){ return this; } },
  BoxGeometry: class { constructor(w,h,d){ this.w=w; this.h=h; this.d=d; this.type='Box'; }
    translate(){return this;} dispose(){} },
  CylinderGeometry: class { constructor(rt,rb,h,seg){ this.rt=rt; this.rb=rb; this.h=h; this.seg=seg||32; this.type='Cyl'; }
    translate(){return this;} dispose(){} },
  SphereGeometry: class { constructor(r,w,h){ this.r=r; this.type='Sph'; } translate(){return this;} dispose(){} },
  ConeGeometry: class { constructor(r,h,seg){ this.r=r; this.type='Cone'; } translate(){return this;} dispose(){} },
  PlaneGeometry: class { constructor(w,h){ this.w=w; this.type='Plane'; } translate(){return this;} dispose(){} },
  BufferGeometry: class { constructor(){ this.attrs={}; this.type='Buf'; }
    setAttribute(n,a){ this.attrs[n]=a; return this; }
    setIndex(i){ this.idx=i; return this; }
    computeVertexNormals(){ return this; }
    translate(){ return this; } dispose(){} },
  Float32BufferAttribute: class { constructor(arr,n){ this.array=arr; this.itemSize=n; this.count=arr.length/n; } },
  Shape: class { constructor(){ this.pts=[]; } moveTo(){} lineTo(){} absarc(){} closePath(){} },
  Path: class { constructor(){ } absarc(){} },
  Vector3: class { constructor(x,y,z){ this.x=x||0; this.y=y||0; this.z=z||0; }
    set(x,y,z){ this.x=x;this.y=y;this.z=z; return this; }
    copy(v){ this.x=v.x;this.y=v.y;this.z=v.z; return this; }
    clone(){ return new this.constructor(this.x,this.y,this.z); }
    add(v){ this.x+=v.x;this.y+=v.y;this.z+=v.z; return this; }
    sub(v){ this.x-=v.x;this.y-=v.y;this.z-=v.z; return this; }
    addVectors(a,b){ this.x=a.x+b.x;this.y=a.y+b.y;this.z=a.z+b.z; return this; }
    subVectors(a,b){ this.x=a.x-b.x;this.y=a.y-b.y;this.z=a.z-b.z; return this; }
    multiplyScalar(s){ this.x*=s;this.y*=s;this.z*=s; return this; }
    dot(v){ return this.x*v.x+this.y*v.y+this.z*v.z; }
    cross(v){ return new this.constructor(this.y*v.z-this.z*v.y, this.z*v.x-this.x*v.z, this.x*v.y-this.y*v.x); }
    crossVectors(a,b){ return this.cross(b); }
    length(){ return Math.sqrt(this.x*this.x+this.y*this.y+this.z*this.z); }
    normalize(){ const l=this.length()||1; return this.multiplyScalar(1/l); }
    divideScalar(s){ return this.multiplyScalar(1/(s||1)); }
    applyQuaternion(){ return this; }
    setFromMatrixPosition(){ return this; }
    negate(){ this.x=-this.x;this.y=-this.y;this.z=-this.z; return this; }
    distanceTo(v){ return Math.hypot(this.x-v.x,this.y-v.y,this.z-v.z); }
  },
  Vector2: class { constructor(x,y){ this.x=x||0; this.y=y||0; }
    set(x,y){this.x=x;this.y=y;return this;} copy(v){this.x=v.x;this.y=v.y;return this;}
    clone(){return new this.constructor(this.x,this.y);}
    add(v){this.x+=v.x;this.y+=v.y;return this;} sub(v){this.x-=v.x;this.y-=v.y;return this;}
    subVectors(a,b){this.x=a.x-b.x;this.y=a.y-b.y;return this;}
    multiplyScalar(s){this.x*=s;this.y*=s;return this;} length(){return Math.hypot(this.x,this.y);}
    normalize(){const l=this.length()||1;return this.multiplyScalar(1/l);} distanceTo(v){return Math.hypot(this.x-v.x,this.y-v.y);}
  },
  MeshStandardMaterial: class { constructor(o){ Object.assign(this,o||{}); } },
  MeshPhysicalMaterial: class { constructor(o){ Object.assign(this,o||{}); } },
  MeshBasicMaterial: class { constructor(o){ Object.assign(this,o||{}); } },
  Color: class { constructor(c){ this.c=c; } },
  CanvasTexture: class { constructor(cv){ this.cv=cv; } },
  RepeatWrapping: 1000,
  SRGBColorSpace: 'srgb',
  DoubleSide: 2,
  FrontSide: 0,
  BackSide: 1,
  Math: Math,
};

// DOM 桩件（材质贴图用 canvas）
globalThis.document = {
  createElement: function(){ return {
    width:0, height:0,
    getContext: function(){ return {
      fillStyle:'', strokeStyle:'', globalAlpha:1, lineWidth:1,
      fillRect(){}, beginPath(){}, moveTo(){}, lineTo(){}, stroke(){}, fill(){},
      arc(){}, ellipse(){}, closePath(){}, putImageData(){},
      getImageData: function(){ return { data: new Uint8ClampedArray(4*256*256) }; },
    }; }
  }; }
};


const files = fs.readdirSync(DIR).filter((f) => f.endsWith('.js') && !f.startsWith('_')).sort();
if (!files.length) { console.error('没有设计文件'); process.exit(1); }

let ok = 0, fail = 0;
const rows = [];

for (const f of files) {
  let src = fs.readFileSync(path.join(DIR, f), 'utf8');
  src = src.replace(/^\s*import\s+[^;]+;?\s*$/gm, '');
  src = src.replace(/export\s+const\s+DESIGNS\s*=/, 'const DESIGNS =');
  let DESIGNS;
  try {
    DESIGNS = new Function('THREE', 'document', src + '\nreturn DESIGNS;')(THREE, globalThis.document);
  } catch (e) {
    console.log('  ✗ ' + f + '  加载失败: ' + e.message);
    fail++;
    continue;
  }
  if (!Array.isArray(DESIGNS)) { console.log('  ✗ ' + f + '  DESIGNS 不是数组'); fail++; continue; }

  for (const d of DESIGNS) {
    try {
      const obj = d.build();
      if (!obj || !obj.children) { console.log('  ✗ ' + f + ' / ' + d.id + '  build() 返回的不是 Group'); fail++; continue; }
      let meshes = 0, maxSeg = 0, tris = 0;
      const visit = function (o) {
        if (!o) return;
        if (o.geometry) {
          meshes++;
          const g = o.geometry;
          const seg = g.seg || 0;
          if (seg > maxSeg) maxSeg = seg;
          if (g.type === 'Cyl') tris += (g.seg || 32) * 4;
          else if (g.type === 'Box') tris += 12;
          else if (g.type === 'Sph') tris += 200;
          else if (g.type === 'Buf') { const p = g.attrs.position; tris += p ? Math.floor(p.count / 3) : 0; }
          else tris += 50;
        }
        if (o.children) o.children.forEach(visit);
      };
      visit(obj);
      // highlight 必须在 build() **之后**读 ——
      // 有的设计把 highlight 对象声明在模块顶层，build() 运行时才把网格挂上去。
      // 在 build() 之前读，永远读到 null，会把好东西误判成"缺失"。
      const hl = d.highlight ? Object.keys(d.highlight).filter((k) => d.highlight[k]) : [];
      rows.push({ file: f, name: d.name || d.id, meshes: meshes, tris: tris, maxSeg: maxSeg, hl: hl });
      ok++;
    } catch (e) {
      console.log('  ✗ ' + f + ' / ' + d.id + '  build() 抛异常: ' + e.message);
      fail++;
    }
  }
}

console.log('');
console.log('设计'.padEnd(10) + '文件'.padEnd(16) + '网格'.padStart(5) + '三角面'.padStart(8) + '段数'.padStart(6) + '  highlight');
console.log('-'.repeat(66));
for (const r of rows) {
  console.log(
    String(r.name).padEnd(10) +
    r.file.padEnd(16) +
    String(r.meshes).padStart(5) +
    String(r.tris).padStart(8) +
    String(r.maxSeg).padStart(6) +
    '  ' + (r.hl.length ? r.hl.join('/') : '-')
  );
}

console.log('');
console.log('成功 ' + ok + ' / 失败 ' + fail);

// 硬性检查
let warn = 0;
for (const r of rows) {
  if (r.maxSeg > 64) { console.error('⚠ ' + r.name + ' 圆柱段数 ' + r.maxSeg + ' > 64（超预算）'); warn++; }
  if (r.tris > 30000) { console.error('⚠ ' + r.name + ' 三角面 ' + r.tris + ' > 30000（超预算）'); warn++; }
  if (!r.hl.length) { console.error('⚠ ' + r.name + ' 没有 highlight —— iOS 状态切换时无法变色'); warn++; }
}
if (fail > 0) process.exit(1);
