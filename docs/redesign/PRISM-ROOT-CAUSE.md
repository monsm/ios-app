# 三棱柱为什么黑屏、不立体、切不动 —— 三个根因

> 2026-10-21。用户真机验收: 「html 的三棱柱很棒很棒 但是 app 的黑屏 不立体 且无法正常切换 1% 的效果都没有」

HTML 原型 `docs/redesign/prism-anim.html` 用 **three.js + PerspectiveCamera(fov 32°)**，
三棱柱是**真正的 3D 物体**。SwiftUI 里我试图用两套 2D 变换去"模拟"它，三处都错了。

---

## 根因 1：`projectionEffect` 把透视项丢了 → 黑屏

原代码：

```swift
private var containerProjection: ProjectionTransform {
    var t = CATransform3DIdentity
    t.m34 = -1.0 / 1200.0                       // ← 透视项
    t = CATransform3DRotate(t, containerAngle * .pi / 180, 0, 1, 0)
    return ProjectionTransform(t)               // ← 只取 3×3
}
...
.projectionEffect(containerProjection)
```

**`CATransform3D` 的 m34 在第 4 列**（4×4 矩阵的 row3/col4），
而 `ProjectionTransform(CATransform3D)` **只取左上 3×3** —— m34 当场被丢掉。

剩下的 3×3 是一个绕 Y 轴的旋转矩阵：

```
cos  0  sin
0    1  0
-sin 0  cos
```

`ProjectionTransform` 把它当成 **2D 投影变换（homography）** 用：
第三列 `(sin, 0, cos)` 变成了分母系数，于是每个像素被除以一个随 x 变化的量 ——
结果整个视图被扭曲、推出屏幕外。**表现就是黑屏。**

> 教训：SwiftUI 没有「父级 3D 变换作用到子视图」这种能力
> （没有 CSS 的 `transform-style: preserve-3d`）。
> `projectionEffect` 只能做 2D 投影，做不了 3D 相机的活。

---

## 根因 2：`perspective: 0` = 正交投影 → 不立体

原代码每个面：

```swift
.rotation3DEffect(.degrees(theta), axis: (x: 0, y: 1, z: 0),
                  anchor: .center,
                  anchorZ: -prismApothem,
                  perspective: 0)          // ← 0 = 没有近大远小
```

`perspective` 是「相对消失点」：**0 表示正交投影**，完全没有近大远小。
位置算得再对，投影出来也只是一堆平面的卡片。

**修法**：原型用 fov 32° 的透视相机，
换算成「以视图尺寸为单位的相机距离」≈ `1/(0.5/tan(16°)) ≈ 0.57`，
所以取 `0.55`。

---

## 根因 3：容器转角没传到面上 → 切不动

原代码 `prismFace` 只用了面自己的角度：

```swift
let theta = FaceAngle.current(f)      // 只有 0/120/240
```

容器转角 `containerAngle`（拖拽 + 翻页的进度）**只通过 `projectionEffect` 施加**。
projectionEffect 一删，转角就彻底没地方去了 —— 面永远不动。

**修法**：把容器转角合并进每个面自己的 `rotation3DEffect`：

```swift
let theta = FaceAngle.current(f) + containerAngle
```

这在几何上等价于 three.js 里 `prism.rotation.y` 作用到子节点 ——
因为 `anchorZ = -A` 的旋转已经同时给出了「朝向」和「位置」：

- 朝向 = θ
- 位置 = (A·sinθ, 0, A·cosθ)

正是三棱柱上该在的地方。

---

## 根因 4（切不动的另一半）：热区自锁

```swift
HStack { edgeZone(...); Spacer(); edgeZone(...) }
    .allowsHitTesting(!dragging)      // ← 自锁
```

`DragGesture.onChanged` 第一帧就把 `dragging = true`，
这一行随即让热区**不再接收触摸** → SwiftUI 取消手势 →
拖到一半就断，`.onEnded` 也不一定来。

热区必须**始终可点**。已删。

---

## 顺带修的

| 项 | 原来 | 现在 |
|---|---|---|
| 内切圆半径来源 | `UIScreen.main.bounds.width`（iOS 26+ 废弃；分屏/多窗口下不对，返回 0 时三面全叠在圆心） | `GeometryReader` 传入的宽度 |
| 拖拽灵敏度 | `/160` → 24pt 热区要拖 80pt 才翻面 | `/120` → 拖 60pt |

---

## 修完后的正确结构

```swift
private func prismBody(width: CGFloat) -> some View {
    ZStack {
        prismFace(.b, width: width)
        prismFace(.d, width: width)
        prismFace(.f, width: width)
    }
    .scaleEffect(breathScale)          // 侧面呼吸（由朝向推导）
    // 没有 projectionEffect
}

private func prismFace(_ f: DoorFace, width: CGFloat) -> some View {
    let theta = FaceAngle.current(f) + containerAngle   // ← 容器转角合并
    return faceView(f)
        .rotation3DEffect(.degrees(theta), axis: (x: 0, y: 1, z: 0),
                          anchor: .center,
                          anchorZ: -prismApothem(width),
                          perspective: prismPerspective)   // 0.55，不是 0
        .opacity(faceVisibility(f))
}
```

## 仍未验证

- **真机观感**：0.55 这个透视强度是否与原型接近，只有真机能定
- 三个面在过渡中的遮挡顺序（`faceVisibility` 的 0.15 阈值）
- `scaleEffect` 与 `rotation3DEffect` 的作用顺序是否与 three.js 的
  `prism.scale` 完全等价（three.js 是 scale 作用在 group，会缩放子节点的位置；
  SwiftUI 的 `scaleEffect` 作用在已渲染结果上 —— x 方向等价，z 方向不等价）
