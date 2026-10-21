# BDF 三棱柱重构 —— 交付交接

> 2026-10-21。HEAD `85a7888`。

## 交付状态

| 项 | 状态 | 证据 |
|---|---|---|
| CI 编译 | ✅ 多次连续 SUCCESS（见 `node tools/cistat.js`）| 最近验证: `39595179104` |
| 本地 23 道闸门 | ✅ 全绿 | `tools/*.js` |
| 52 页深度适配 | ✅ 34 页改动 + 18 页核验，0 未处理 | `PAGE-ADAPT-LEDGER.md` |
| 三域架构 | ✅ | `ManagerFace`(B) / `XGateDoor`(D) / `DashboardFace`(F) |
| 旧代码删除 | ✅ | `DoorStage.swift` / `DoorBack.swift` 不存在 |
| **真机观感确认** | ❌ **未完成** | 只有用户能做 |

## 目标 8 项的落地证据

1. **B/D/F 三域** — `ManagerFace` / `XGateDoor` / `DashboardFace`，容器 `DoorPrism`
2. **D 域真实比例** — `GateMetrics`: 门 1050×2300×88、锁 60×300（1:5）、锁宽占门宽 5.71%、把手离地 1080mm、40 根竖条
3. **三棱柱 C** — 四个数学项全部落地并验算（见下表）
4. **B 域** — `.axGlassCapsule()` + 5 组（ledger/devices/members/security/backupLook）
5. **F 域** — `.axGlassCapsule()` + `Lens(.lock/.people)`；`StatsKit` 静态 9 处、`StatModel` 实例方法 8 处（6 个指定方法全在）
6. **52 页** — 见台账
7. **reduceMotion** — 3 个 guard；三棱柱照常渲染，无 `transition(.opacity)`
8. **旧代码删除** — ✅

## 三棱柱四个数学项（逐项验算）

| 规格 | 实现位置 | 验算 |
|---|---|---|
| `easeInOutSine` | `.easeInOut(duration: 0.42)` | ✅ |
| `narrow = (\|cos(relToEdge)\|−0.5)/0.5` | `breathNarrow` | t=0→0 / t=0.5→1 / t=1→0 ✅ |
| `scale = 1−0.20·narrow` | `breathScale` | 1.000 / 0.800 / 1.000 ✅ |
| `z = −0.35·narrow` | `zShift = −0.7A·narrow` | 0 / −70.7 / 0 ✅ |

## 三棱柱修过的 11 个问题

| # | 问题 | 后果 | 发现方式 |
|---|---|---|---|
| 1 | `ProjectionTransform` 只取 3×3，`m34` 在第 4 列被丢 | 黑屏 | 矩阵分析 |
| 2 | `perspective: 0` = 正交 | 不立体 | 文档 |
| 3 | 容器转角没传给面 | 切不动 | 代码追踪 |
| 4 | 热区 `.allowsHitTesting(!dragging)` 自锁取消手势 | 切不动 | 代码追踪 |
| 5 | 面铺满全屏，无棱柱轮廓 | 看不出棱柱 | 对比原型相机/视口 |
| 6 | 缺 3 根竖棱 | 静止无体积 | 逐行读 `buildPrism` |
| 7 | `UIScreen.main` 废弃，可能返 0 | 三面叠圆心 | API 检查 |
| 8 | 内切圆多乘 0.9 | θ=60° 空隙 17pt | **ASCII 模拟** |
| 9 | 内切圆按容器宽而非面宽 | A 大 8.7% | **完整模拟** |
| 10 | 竖棱 5pt 太细 | 看不见 | 按原型比例换算 |
| 11 | **width=0 → `depthScale = 0/0 = NaN`** | **视图被丢弃（黑屏）** | **边界分析** |

### 最终几何（全部显式，不依赖未文档化的 SwiftUI 3D 参数）

```swift
let A = max(width, 1) * 0.2887          // 内切圆 = 面宽/(2√3)
let D = A * 10.4                        // 相机距离（由原型 5.2/0.5 反算）
let theta = FaceAngle.current(f) + containerAngle
let rad = theta * .pi / 180
let zShift = -A * 0.7 * breathNarrow    // 规格的 z = -0.35·narrow
let z = A * cos(rad) + zShift
let x = A * sin(rad)
let denom = D - z
let depthScale: CGFloat = (denom.isFinite && denom > 0.001) ? D / denom : 1

faceView(f)
    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    .rotation3DEffect(.degrees(theta), axis: (x:0,y:1,z:0), anchor: .center)  // 只做朝向
    .scaleEffect(depthScale)                                                 // 近大远小
    .offset(x: x)                                                            // 摆位置
    .opacity(faceVisibility(f))                                              // 遮挡
```

竖棱同理，半径 `1.732A`（= 面半宽，精确等于棱柱角点）。

### 三组验算结果

| 项 | 本实现 | 原型/规格 |
|---|---|---|
| 正面/120°面 大小比 | **0.8624** | 0.8624（three.js）|
| θ=60° 面交界 | 重叠 **7.6pt** | 应为接上（原来空隙 17.4pt）|
| 转场 narrow/scale | 0→1→0 / 1→0.8→1 | 规格 |

## 未完成的唯一一项

**用户真机确认观感。** 这是目标明列的第三条验收标准，只有用户能做。

我这边已排除的：
- ✅ 挂载链（`RootView → rootChrome → rootCore → rootGroup → mainTabsChrome → DoorRoot` 无条件）
- ✅ 三个面都有真实内容（不是空视图）
- ✅ `SecurityWatermark` 是 `opacity 0.05` 的 Canvas，不遮挡
- ✅ `depthScale` 的 NaN/Inf 兜底
- ✅ 所有颜色令牌存在

**如果真机上仍然异常，最可能还没查的是：**
1. `rotation3DEffect` + `scaleEffect` + `offset` 三者的**实际作用顺序**是否与我的假设一致
2. 全屏页面（内含 `ScrollView`）在 3D 变换下是否正常渲染
3. `.compositingGroup()` 之后的投影是否影响可见性

## 相关文档

- [PRISM-GEOMETRY.md](PRISM-GEOMETRY.md) —— 几何推导与验算
- [PRISM-ROOT-CAUSE.md](PRISM-ROOT-CAUSE.md) —— 三个根因分析
- [CI-VS-GATES.md](CI-VS-GATES.md) —— 本地闸门 ≠ 能编译
- [PAGE-ADAPT-LEDGER.md](PAGE-ADAPT-LEDGER.md) —— 52 页台账
- [SECTION-MIGRATION-LESSON.md](SECTION-MIGRATION-LESSON.md) —— Section 迁移三坑
