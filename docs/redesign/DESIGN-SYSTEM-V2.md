# 设计系统 v2 — 视觉能力清单

> 这份文档记录 2026-10-21 这一轮"全新 UIUX"落地了什么。
> 目的不是罗列代码，而是让下一个人知道**每个视觉手法为什么在这里**。

## 一、四条设计原则（贯穿全部页面）

### 1. 视觉必须承载信息，不做纯装饰

每一个动效/图形都在回答一个真实问题：

| 组件 | 回答的问题 | 视觉手法 |
|---|---|---|
| `XCodeRing` | 这个 OTP 码还能用多久？ | 环的收缩 = 倒计时本身；末 5 秒转橙 |
| `XDayClock` | 我一天里什么时候在用门？ | 极坐标辐条 = 24 小时分布；夜间 65% 透明 |
| `XBatteryGauge` | 门锁电量还剩多少？ | 270° 弧 = 余量；三档变色 |
| `XCycleRing` | 距离该保养还有多久？ | 弧越满越紧迫；超期脉冲 |
| `XStepBar` | 我在第几步？ | 序号 + 标题 + 连接线；已过步打勾 |
| `XScrollLift` | （无信息，纯可读性） | 边缘卡片微缩，视线自然带向中部 |

反面样本（刻意不做）：
- 给设置页加动效 —— HIG motion.md: "Don’t add motion for the sake of adding motion"
- 给 LazyVGrid 网格项加 scrollTransition —— 同行卡片不同缩放会错位

### 2. 无障碍不是补丁，是设计的一部分

- **Canvas 画的图形 VoiceOver 读不到** → 每个 Canvas 组件都有 `accessibilityElement(children: .ignore)` + 一个完整的朗读串
- **无限循环动画是晕动症主要诱因** → 13 处 `accessibilityReduceMotion` 守卫，无一缺失
- **颜色不能是唯一通道** → 告警行同时用色条 + 图标 + 文字；状态灯同时用色 + "正常/需处理" 文字
- **对比度** → `Color.adaptive` 双档，浅色/深色分别达标（见 `XPalette.kindFp` 的修正）

### 3. 组件化的价值在于"改一处，全 App 受益"

这一轮有三次这样的情况：

| 改动 | 影响面 |
|---|---|
| `XRow` 加图标徽章 | 十几处页面的所有设置行 |
| `XStatusPill` 加 symbolEffect | 13+ 处状态切换 |
| `XPrimaryButtonStyle` 加顶部高光 | 30+ 个主按钮 |

所以样式必须收在 `Components.swift`，页面只负责组合。

### 4. 静态闸门查不出几何问题

21 道静态闸门查语法/令牌/对比度/括号，但查不出：
- 码值压到环线上
- 刻度被容器裁掉
- 整屏 40% 是空白

`tools/preview.py` 就是补这个盲区的（见下）。

## 二、组件清单（24 个）

### 基础
- `XPanel` — 卡片容器（hero/group/flat 三式）
- `XHairline` — 分隔线
- `XStatusPill` — 状态胶囊
- `XMetricTile` — 指标磁贴
- `XEmptyState` / `XGuidedEmptyView` — 空态
- `XBusyButton` / `XPrimaryButtonStyle` / `XSecondaryButtonStyle` / `XDestructiveButtonStyle` — 按钮四式
- `XRow` — 设置行（图标徽章 + 标题 + 副标题 + 值 + chevron）
- `XHeroCard` — 首屏大卡
- `XToggle` — 开关三态重载

### 数据可视化（Canvas 自绘）
- `XCodeRing` — 时效码大卡
- `XDayClock` — 24 小时极坐标
- `XBatteryGauge` — 电量仪表环
- `XCycleRing` — 周期进度环

### 布局与动效
- `XStepBar` — 多步向导指示器
- `XScrollLift` — 卡片滚动连续形变
- `XStaggeredAppear` — 交错入场
- `XDestinedModifier` — 路由目的地绑定
- `XPlateShape` — 形状集合
- `XContainerKind` / `XToneColor` / `XHeroStats` — 枚举

## 三、令牌（App/Core/Theme.swift）

| 枚举 | 作用 |
|---|---|
| `XPalette` | 12 档中性灰阶 + 语义色 + 六套可选强调色 + specular + kindFp/kindOtp |
| `XSpace` | 8pt 栅格（xxs 2 → xxl 32 + gutter/card/control/tile/lockFace） |
| `XRadius` | card 16 / control 12 / tile 14 / min 8 |
| `XHit` | 最小触达 44 |
| `XIcon` | 图标尺寸 xs13/sm16/md20/lg26/xl44/lock72 |
| `XMetric` | 锁面尺寸 / 行高 / 装饰图标缩放 / 夜间暗化 |
| `XMotion` | 四档（quick/standard/soft/exit）+ 门面专用（doorSwing/lightLeak/doorReveal） |
| `XGradient` | 门面底色 / 门缝透光 / 锁面金属环 |
| `XHaptics` | tick/trigger/soft/rigid + success/warning/failure |
| `XAppearance` | isAMOLED / highContrast |

标 `nonisolated` 的：`xFont` / `xList` / `xScreen` / `xPlate` / `xCallout` / `staggered` / `xScrollLift`。
理由：`extension View` 默认 `@MainActor`，而 Swift 6 严格并发下这些纯样式函数会在非隔离上下文被调用。

## 四、工具

### `tools/preview.py` — 渲染验证（602 行 / 11 个渲染器）

按 SwiftUI 的 VStack/HStack 规则手工推算布局，用 Pillow 画成 PNG。

**它抓到过 7 个静态闸门查不出的缺陷：**
1. XCodeRing 56pt 码值压环线（8 位时直接穿过）
2. DoorFront `Spacer` + `maxHeight` 导致布局退化，整屏 40% 空白
3. AlarmCenter 柱状图容器 56 < 内容 58，刻度被裁
4. DoorFront 锁体直径 52% 在 402pt 屏上偏小
5. XDayClock 圆心数字被辐条压住
6. XDayClock clock 168 + maxWidth 让右侧读数被挤
7. 告警柱状图刻度与底部提示重叠

**局限（写在文件头）：** 近似渲染，不是真机截图。字体用 Noto Sans SC 代替 SF Pro，
渐变/blur/blendMode 都是近似。用途是查构图与几何，不是校验像素级还原。

用法：`python tools/preview.py <组件名>` / `--list`
输出：`docs/redesign/preview/<名>.png`

### `tools/apisig.js` — 第 36 道闸门

把「组件签名能静态判定的部分」提前到本地：
- `xFont` 只收 `(Font, weight:)`，传 `design:`/`size:` 直接判失败
- 6 个组件的参数名与真实声明对账

判据**从 Components.swift 现读**，不手抄第二份。
带 4 条自检（2 正控 / 2 反控）—— 写这道闸门时自检抓出了我自己的两个 bug。

## 五、这一轮修复的真实缺陷

| 缺陷 | 性质 |
|---|---|
| `CareViews.historySection` 的 `all` 变量从未定义 | 历史遗留，藏在 Form 里一直没被编译到 |
| `StudioPage` teal 浅色模式 2.96:1 | 低于 WCAG 非文字 3:1，改为 adaptive 后 5.01:1 |
| `DoorFront` 的 `repeatForever` 无 reduceMotion 守卫 | HIG motion.md 违规 |
| `FeedPage` 的 `xFont` 传 design 参数 | Xcode 才报，已固化成 apisig 闸门 |
| `DeviceHomeView` 残留 `.xList()`/`.xScreen()` | 旧 List 形态修饰符，在 ScrollView 上无作用 |
