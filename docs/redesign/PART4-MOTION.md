# PART 4 · 动效总谱

前置：`DECISIONS.md` 的 **D3 / D5 / D11**、`PART1-LOCKFACE.md` §4 状态机。

> **本文是两端共用的数值唯一来源。** iOS 与 Android 用同一组时长与曲线；
> Android **不做门面**（D11），所以 A 段对它是「不适用」，**B 段必须照做**。

---

## 0. 三条纪律

1. **820ms 的门转必须作为新令牌进 `DS.Motion`**（如 `doorSwing`），并让它也在 `calm` 档降级。
   不许在视图里直接写 `withAnimation(.timingCurve(...))` —— 那等于把降级规则实现第二遍
   （`DesignSystem.swift:294-298` 的注释专门批过这件事）。
2. **触觉只允许三档**：`DS.Haptics.tick`（light，过程）、`DS.Haptics.trigger`（medium，动作）、
   结果档 `UINotificationFeedbackGenerator` 的 success/warning/error（`DesignSystem.swift:248-258`）。
3. **22:00–06:00 降装饰层峰值**（`DS.isNightDim`，`:259-264`）：门面的 sheen / 中缝光 / 锁体辉光都要接。

---

## 1. A 段 · 门面专属时间轴（**iOS only**，Android 列写「不适用（D11）」）

t = 0 定义为**开锁成功回包到达那一刻**（不是手指抬起那一刻）。

| t (ms) | 事件 | 时长 | 曲线 | 驱动量 | calm 档降级 |
|---|---|---|---|---|---|
| 按下 | 锁体按压 | 100ms | `quick` | `scale 1 → 0.972` | 同（瞬时） |
| 按下 | 充能开始 | 连续 | 无（跟手） | `p: 0 → 1` 驱动环 trim / 光晕 / 刻度 | **不逐帧**：直接到终态 |
| 按下期间 | 触觉节拍 | 每 10% | — | `tick`（light） | 同 |
| p = 1 | 充能完成 | — | — | `trigger`（medium）→ 发指令 | 同 |
| 0 | 锁体字形换态 | 260ms | `.easeOut` | 闭环 → 开环，`scale .9 → 1` | 交叉淡入 120ms |
| 0 | **中缝透光** | 420ms | `.easeOut` | `LightLeak.opacity 0 → 1` | 直接显示（不渐入） |
| +340 | **门转开** | 820ms | `.timingCurve(0.22, 0.76, 0.03, 1)` | `rotateY 0 → ±106°` | **不转**：整层 200ms 交叉淡出 |
| +340 | 门板压暗 | 700ms | `.easeOut` | 黑 0 → 32% | 同 |
| +340 | 标题/提示淡出 | 260 / 300ms | `.easeOut` | `opacity → 0` | 120ms |
| +340 | 锁体淡出 + 缩 | 300 / 560ms | `.easeOut` | `opacity → 0`, `scale → .955` | 120ms |
| +480 | App 层入（opacity） | 460ms | `.easeOut` | `opacity 0 → 1` | 200ms |
| +480 | App 层入（scale） | 700ms | `.timingCurve(0.22, 0.76, 0.03, 1)` | `scale .986 → 1` | 无（直接 1） |
| +760 | 门转结束，相位 → `open` | — | — | 门层 `accessibilityHidden(true)` | 同 |
| +1180 | 中缝光淡出（门开完后延迟 420ms） | 420ms | `.easeOut` | `opacity 1 → 0` | 同 |
| 失败 | 锁体抖动 3 次 | 3 × 90ms | `.easeInOut` | `shakeX ±6pt` | 只抖一次 |
| 失败 | 门**完全不动** | — | — | 逐帧像素差必须为 0 | 同 |
| 松手 p<1 | 充能回零 | 180ms | `.easeOut` | `p → 0` | 瞬时 |
| 关门 | 门转回 | 820ms | 同开门曲线 | `rotateY ±106° → 0` | 交叉淡入 |
| 关门 | App 层淡出 | 400ms | `.easeOut` | `opacity 1 → 0` | 200ms |
| +780 | 回到 `locked`，恢复标题/提示 | — | — | — | 同 |

**验收**：录屏逐帧比对，中缝光出现在门转动**之前** ≥ 300ms；**淡出开始那一帧**每扇门残留宽度 5–16pt（推导见 PART1 §10 第 3 条）。

---

## 2. B 段 · 共用组件动效（**两端同值**）

| 事件 | 时长 | 曲线 | iOS | Android |
|---|---|---|---|---|
| Tab 切换 | 系统持有 | — | **不自己包 `withAnimation`**（`DesignSystem.swift:276-278` 明说 TabView 动画由系统持有） | 系统持有 |
| 列表行按压 | 100ms | `quick` | `PressableButtonStyle`（缩放 0.97 + 降透明） | `Modifier.scale` + `animateFloatAsState` |
| 行/卡出现 | 250ms | `soft` | `DS.Motion.soft` | `CubicBezierEasing(0.42, 0, 0.58, 1)` |
| 展开/折叠 | 220ms | `soft` | v10 `.sub` 展开 | 同上 |
| 开关切换 | 150ms | `quick` | `VariantToggleStyle` | 同上 |
| sheet 进出 | 系统持有 | — | 用系统 `.sheet` | 用系统 `ModalBottomSheet` |
| 状态变化（在线→离线） | 250ms | `soft` | 颜色/图标交叉淡入 | 同上 |
| 加载→内容 | 250ms | `soft` | `BusyButton` 退场 | 同上 |
| 空态出现 | 300ms | `soft` | `ContentUnavailableView` | 同上 |
| 破坏性确认 | 系统持有 | — | `.confirmationDialog` / `.alert` | 系统 AlertDialog |

**「共用」的含义**：数值（时长/曲线控制点）**逐字相同**；实现 API 各自平台原生。
两端的验收方式：同一操作录屏，逐帧取关键帧时刻，误差 ≤ 1 帧（16.7ms）。

---

## 3. 曲线词典

| 名称 | cubic-bezier | 用途 | SwiftUI | Compose |
|---|---|---|---|---|
| 门转 | `(0.22, 0.76, 0.03, 1)` | 106° 大角度旋转、App 层 scale | `.timingCurve(0.22, 0.76, 0.03, 1, duration: 0.82)` | `CubicBezierEasing(0.22f, 0.76f, 0.03f, 1f)` |
| 标准软 | `(0.42, 0, 0.58, 1)` | `DS.Motion.soft`（easeInOut） | `.easeInOut(duration: 0.25)` | `CubicBezierEasing(0.42f,0f,0.58f,1f)` |
| 出场 | `(0, 0, 0.58, 1)` | `DS.Motion.exit`（easeOut） | `.easeOut(duration: 0.15)` | `CubicBezierEasing(0f,0f,0.58f,1f)` |
| 入场 | `(0.42, 0, 1, 1)` | `DS.Motion.calm` 的 easeInOut 档 | `.easeInOut(duration: 0.16)` | 同上 |

**为什么 106° 用 timingCurve 而不是 spring**：SwiftUI 的 `spring(response:dampingFraction:)` 即使
`dampingFraction = 1.0` 也可能因 `response` 与初始速度产生**过冲**；
在 106° 这种大角度下，过冲意味着门会**转过头再弹回来**——超过 90° 时背面会露出来（见 PART1 §11 坑 1），
视觉上是「门穿帮了」。timingCurve 保证单调，不会越过终点。
**例外**：跟手手势的释放仍用 `DS.Motion.fling`（那是真的带动量）。

---

## 4. 充能进度 `p` 驱动的属性（**1:1，单一来源**）

| 属性 | 从 → 到 | 是否 1:1 |
|---|---|---|
| 环 `trim(from:to:)` | `0 → 1` | 是 |
| 光晕 `opacity` | `0 → 0.55` | 是（线性映射） |
| 盘体 `scaleEffect` | `0.972 → 1.0` | 是 |
| 刻度点亮数 | `0 → 12` | 否（量化到整数） |
| 触觉节拍 | 每 10% 一次 | 否（阈值触发） |
| 中缝光 `opacity` | **不由 p 驱动** | — |

**红线**：`p` 只由按压时长/位移算出，**不许**用 `Timer` 分段推进状态；
`p` 变化时**只**改上述属性，不许在回调里改相位以外的状态（v10 就是因为回调里混了 `classList` 操作而崩溃，`v10.html:449`）。

---

## 5. 降级矩阵

| 开关 | 门面（iOS） | 组件（两端） |
|---|---|---|
| **降低动态效果** `AXFlags.reduceMotionSnapshot` | 门不转（200ms 交叉淡入）；中缝光直接显示；充能不逐帧，直接终态；高光不跟随指针 | 走 `DS.Motion` 各令牌内部的 `tier` switch（不是 `DS.Motion.calm`，那个成员不存在）；Android 读 `Settings.Global.ANIMATOR_DURATION_SCALE == 0` |
| **低电量** `BatteryCare.appLowBattery` | 同 calm | 同 calm（`DS.Motion.tier` 已实现） |
| **降低透明度** `AXFlags.reduceTransparency` | 门面去噪声；玻璃走 `axGlass` 的实底回落；锁体保留描边 | 玻璃全部走 `axGlass` |
| **增强对比** `AXFlags.highContrast` / `kf_hc` | 门上提示文案用主文本色；中缝亮线 2pt | 沿用既有高对比三组（`DesignSystem.swift:361-365`） |
| **夜间** `DS.isNightDim` | 装饰层峰值下调（sheen/中缝光/辉光） | 装饰层同降 |

---

## 6. 触觉总谱

| 时机 | 档位 | 与动画的对齐 |
|---|---|---|
| 充能过程 | `tick`（light） | 每 10% 一次，与刻度点亮同帧 |
| 充能完成 | `trigger`（medium） | 与字形换态同帧（t=0） |
| 开锁成功 | success | 与中缝光亮起同帧 |
| 开锁失败 | error | 与抖动第一次同帧 |
| 推门而入 | `tick` | 手势跨过 72pt 阈值时一次 |
| 关门 | `tick` | 手势跨过 96pt 阈值时一次 |
| 列表行选择 | `tick` | 按压开始时 |

**禁止** `UIImpactFeedbackGenerator(style: .heavy)`（本仓触感只有三档）。
Android 对应：`HapticFeedbackConstants.CLOCK_TICK`（tick）/ `CONFIRM`（trigger）/ `REJECT`（error）。

---

## 7. 性能守则

1. **只动 transform 与 opacity**：`rotation3DEffect` / `scaleEffect` / `opacity` 走 GPU；
   **禁止**逐帧改 `frame` / `padding` / 布局尺寸。
2. **噪声 `Canvas` 只光栅化一次**：外层 `.drawingGroup()`；点数按面积放大但**固定种子**
   （照抄 `DS.HeroTexture` 的 LCG，`DesignSystem.swift:214-230`），否则每帧重绘会闪。
3. **门面层整体 `.compositingGroup()`**，避免多层渐变各自合成。
4. **不在 `body` 里做计算**：直径、角度等一次性算好存 `let`。
5. Android：`Modifier.graphicsLayer { rotationY = ...; cameraDistance = ... }`；
   噪声用 `Modifier.drawWithCache`（缓存一次）。

---

## 8. 验收

1. 录屏逐帧：中缝光早于门转 ≥ 300ms。
2. **淡出开始那一帧**每扇门残留宽度 5–16pt（= `(屏宽÷2)×cos 88°` 附近；393pt 基准约 7pt）。
3. 无镜像背面闪现（88°–106° 透明度斜坡生效）。
4. 失败时门板像素差 = 0。
5. iPhone SE(3rd) 开门 ≥ 55fps。
6. 开启「降低动态效果」后门不转。
7. B 段任取 3 个事件，两端关键帧时刻误差 ≤ 1 帧。