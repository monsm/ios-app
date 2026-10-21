# 锁体设计 · 写作约定

## 唯一目标
一把**高雅、精致、有气质**的 3D 入户门锁锁体。看起来像艺术品，不像硬件玩具。

## 技术硬约束
1. **只用 Box / Cylinder / Sphere / Cone / Plane 或 BufferGeometry 手搓顶点**
   ❌ 禁用 TorusGeometry / ExtrudeGeometry / LatheGeometry / TubeGeometry（iOS 做不出来）
2. **单位 mm**：面板宽 55-80、高 250-400；圆盘直径 50-75。Z 轴朝观察者。
3. 圆柱段数 ≤ 64
4. 不要 DOM 操作（canvas 做贴图可以）

## 文件格式
`docs/redesign/locks/<名字>.js`：

```js
import * as THREE from 'three';
export const DESIGNS = [
  { id:'x', name:'中文名', note:'一句气质说明',
    build: function(){ const g=new THREE.Group(); /* mm 建模 */ return g; },
    highlight: { accent:null, sensor:null, mover:null } }
];
```

## 检查
`node --check docs/redesign/locks/<名字>.js` 必须通过。

## 形态要想清楚
看不见渲染结果。先想正视图，再想侧视图，再决定放哪些几何体。
宁可少而准，不要多而乱。
