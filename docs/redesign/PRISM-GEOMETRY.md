# 三棱柱几何 —— 显式推导（最终版）

> 2026-10-21。彻底弃用 SwiftUI 的 `projectionEffect` / `anchorZ` / `perspective`，
> 改成**自己算每个量**。这样每个数字都可验算。

## 为什么弃用 SwiftUI 的 3D 参数

| 参数 | 问题 |
|---|---|
| `projectionEffect` | `ProjectionTransform(CATransform3D)` **只取 3×3**，`m34`（透视）在第 4 列被丢弃 → 视图被当 2D 投影扭曲 → **黑屏** |
| `perspective` | 「相对消失点」的**确切公式没有文档**（m34 = −p/S 里的 S 是什么），只能靠反算猜 |
| `anchorZ` | 旋转轴 z 位置。方向对但**无法在同一变换里再做 z 平移**，规格的 `z=−0.35·narrow` 做不到 |

## 最终公式

设：
- `W` = 容器宽度（pt）
- `A = W / (2√3) = 0.2887·W` —— 正三棱柱内切圆半径
- `D = 10.4·A` —— 相机距离（由原型 5.2/0.5 反算）
- `θ` = 面在棱柱上的角度 + 容器转角

每个面：

```swift
let rad = θ * .pi / 180
let zShift = -A * 0.7 * breathNarrow        // 规格的 z = -0.35·narrow（R=2A）
let z = A * cos(rad) + zShift
let x = A * sin(rad)
let depthScale = D / (D - z)

faceView(f)
    .rotation3DEffect(.degrees(θ), axis: (x:0,y:1,z:0), anchor: .center)  // ① 朝向
    .scaleEffect(depthScale)                                             // ② 近大远小
    .offset(x: x)                                                        // ③ 位置
    .opacity(faceVisibility(f))                                          // ④ 遮挡
```

**关键**：`rotation3DEffect` 的旋转轴**过视图中心**，所以它只产生 `cos(θ)` 的前缩，
不引入任何透视畸变 —— 透视完全由 ②③ 显式控制。

## 验算

### 1. 深度比与原型一致

| | 正面 / 120°面 大小比 |
|---|---|
| three.js 原型（相机 5.2，内切圆 0.5）| 0.8624 |
| 本实现（D = 10.4A）| **0.8624** |

### 2. 面交界（θ=60° 时棱柱的角）

| A 的取法 | 结果 |
|---|---|
| `0.9·0.2887·W`（原代码）| **空隙 17.4pt** ✗ |
| `0.2887·W`（现在）| **重叠 7.6pt** ✓ |

面宽就是 `W`，正三棱柱边长 = 面宽 ⇒ 内切圆必须严格 `W/(2√3)`。
原来多乘的 0.9 让棱柱小了 10%，转到中间时两面之间留缝。

### 3. 转场曲线与规格逐点吻合

| t | 转过角 | narrow | scale | zShift |
|---|---|---|---|---|
| 0.00 | 0.0° | 0.000 | **1.000** | 0.0 |
| 0.25 | 17.6° | 0.476 | 0.905 | −33.7 |
| **0.50** | **60.0°** | **1.000** | **0.800** | **−70.7** |
| 0.75 | 102.4° | 0.476 | 0.905 | −33.7 |
| 1.00 | 120.0° | 0.000 | **1.000** | 0.0 |

`scale = 1 − 0.20·narrow` ✓
`z = −0.35·R·narrow` ✓

## 竖棱（体积感）

原型 `buildPrism` 除了三个面，还放了 3 根圆柱当「骨」：

```js
const radius = R_PRISM * Math.sin(Math.PI/3);   // 0.866 R
const a = FACE_ANGLE[i] + Math.PI/3;            // 面法线 + 60° = 角上
```

换算：角点半径 = 0.866·R = 1.732·A。

Swift 侧同样用显式几何：

```swift
let R = A * 1.732
let z = R * cos(rad)
let x = R * sin(rad)
Capsule().frame(width: 5).scaleEffect(D/(D-z)).offset(x: x)
```

可见性：`cos(rad) > 0` 才画（前侧两根可见，背面那根隐藏）。

## 构图（为什么需要留边）

原型里棱柱只占视口 **67%×70%**（相机 5.2 / 半径 1.0 / fov 32°），四周是背景。
Swift 版原来每面铺满全屏 —— **没有轮廓可看，3D 就白做**。

现在留 **水平 4% / 垂直 3%**（比原型 16% 保守，因为面是真实页面，底部导航要贴边）。

## reduceMotion

规格要求「三棱柱不动，保持原样」：

| 量 | reduceMotion 时 |
|---|---|
| `containerAngle` | 返回 `base`（不随拖拽/翻页转）|
| `breathNarrow` | 返回 0 |
| `breathScale` | 返回 1.0 |
| `step()` | 直接跳面，不做旋转过渡 |

结果：**三棱柱照常渲染（当前面正面朝向），只是不动** —— 不是降级成淡入淡出。

## 仍未验证（只有真机能定）

- SwiftUI 的 `rotation3DEffect` + `scaleEffect` + `offset` 组合出来的**实际像素效果**
- `.compositingGroup()` 之后投影的表现
- 5 根棱/3 个面叠在一起时的渲染性能
