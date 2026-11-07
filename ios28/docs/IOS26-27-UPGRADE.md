# iOS 26 / iOS 27 能力接入报告

> 日期：2026-11-07
> 对照来源（Apple 官方）：
> - [What's New in iOS 26（WWDC25）](https://developer.apple.com/wwdc25/guides/swiftui)
> - [What's New in SwiftUI（WWDC26 session 269）](https://developer.apple.com/wwdc26/guides/swiftui)
> - [SwiftUI updates（Apple 文档变更日志）](https://developer.apple.com/documentation/updates/swiftui)
> - [Apple Developer Documentation · SwiftUI](https://developer.apple.com/documentation/swiftui)
>
> **口径**：本报告只记**代码里真正用到的**能力。没接进去的，一律写明原因 ——
> 不写「以后再说」这种没有信息量的话。

---

## 0. 部署目标与总体策略

| 项 | 之前 | 现在 | 理由 |
|---|---|---|---|
| `deploymentTarget.iOS` | 27.0 | **25.0** | 材质体系（Liquid Glass）是 iOS 26 的能力。把目标降到 25，iOS 26 与 iOS 27 的新 API 才**真的需要** availability 分支，也才有「旧系统不崩溃」这句话可兑现。 |
| `TARGETED_DEVICE_FAMILY` | 1,2 | 1,2 | 宽屏（iPad）走系统的侧边栏形态。 |
| 新增闸门 | — | `Gates/l10n.js` | 文案 key 完整性（与本轮无关，是上一轮的产物，一并保留）。 |

**为什么不是 25 以下**：DAYLIGHT 的整套材质语言就是 iOS 26 的 Liquid Glass。
再往下的降级不是「换个材质」，而是**另做一个 App**（没有折射、没有高光、没有变形），
与设计文档冲突。因此 iOS 25 是**材质等价降级**的下界：
iOS 25 上 `.ultraThinMaterial` 顶替玻璃，层级、命中区、功能完全一致。

---

## 1. 已接入的能力（逐项）

### 1.1 iOS 26 —— Liquid Glass

| 能力 | 落点 | 新系统上的表现 | 降级路径 |
|---|---|---|---|
| `glassEffect(_:in:)` | `App/Design/LiquidGlass.swift`（唯一入口） | 真玻璃：折射背后内容、顶缘高光、交互反馈 | iOS 25 → `.ultraThinMaterial`；「减少透明度 / 增强对比度」→ 不透明面板 + 加倍描边 |
| `GlassEffectContainer(spacing:)` | `App/Design/Modern.swift` 的 `GlassGroup`；`GateScreen` 的键盘、`LensGlass26` | 同一组玻璃合成**一次**渲染，采样一致、可互相变形 | iOS 25 → 不加容器（各自独立，仍可用） |
| `glassEffectID(_:in:)` | `App/Design/LensGlass.swift`（`LensGlass26`） | 镜片玻璃在「镜头 → 光圈」之间**真的变形** | iOS 25 → `LensGlassLegacy`（静态玻璃 + 描边环） |
| `glassEffectTransition(_:)` | 同上（`.matchedGeometry`） | 变形走几何匹配，不是淡入淡出 | iOS 25 → 无变形（静态） |
| `Glass.regular / .clear / .identity`、`.tint(_:)`、`.interactive()` | `LiquidGlass.swift` | 黄铜染色 + 可交互玻璃 | iOS 25 → 材质 + 同样的染色 |
| `.buttonStyle(.glass)` / `.glassProminent` / `.glass(_:)` | `App/Design/Controls.swift`（`ChoiceChip`） | 选项胶囊用**系统**玻璃按钮：自带按压反馈、焦点环、无障碍选中态 | iOS 25 → 自绘表面（选中 = 黄铜实底） |

### 1.2 iOS 26 —— 滚动与背景

| 能力 | 落点 | 表现 | 降级 |
|---|---|---|---|
| `scrollEdgeEffectStyle(_:for:)` | `App/Design/Modern.swift` 的 `softScrollEdge` → `App/Design/Controls.swift` 的 `ScreenScroll` | 浮岛 Tab 栏形态下，内容从栏下滑过时底边**柔化** | iOS 25 → 无柔化（内容直接穿过） |
| `backgroundExtensionEffect()` | `App/Design/Modern.swift` 的 `extendBackground` → `App/Design/Atmosphere.swift`（日光场） | iPad 分屏 / 侧边栏时，日光背景在安全区外**延展**，不被裁断 | iOS 25 → 背景只铺到安全区内 |

### 1.3 iOS 26 —— 导航过渡

| 能力 | 落点 | 表现 | 降级 |
|---|---|---|---|
| `navigationTransitionSource(id:namespace:)` / `navigationTransitionDestination(id:namespace:)` | `App/Design/Modern.swift`（`zoomTransitionSource/Destination`）→ `MobileKeysScreen` 的交付弹层 | 交付弹层从「交给安卓」那一行**长**出来 | iOS 25 → 弹层照旧淡入 |

### 1.4 iOS 26 —— 标签栏与侧边栏

| 能力 | 落点 | 表现 | 降级 |
|---|---|---|---|
| `TabView` + `Tab(_:systemImage:value:)` | `App/ThresholdApp.swift` | 已是 iOS 18+ 的新 Tab API | — |
| `.tabViewStyle(.sidebarAdaptable)` | 同上 | **iPad 上自动变成侧边栏**（iPhone 仍是标签栏） | iOS 18+ 即可用，本 App 最低 25 ✓ |
| `.tabViewSidebarHeader(content:)` | 同上（`SidebarHeader`） | 宽屏侧边栏顶部显示「家名 + 当前锁」 | iOS 18+ 即可用 ✓ |
| `.tabBarMinimizeBehavior(.onScrollDown)` | 同上（`minimizeTabBarOnScrollDown`） | 向下滚动收起标签栏 | iOS 25 → 标签栏常驻 |

### 1.5 iOS 27 —— 容器里的轻扫操作

| 能力 | 落点 | 表现 | 降级 |
|---|---|---|---|
| `swipeActionsContainer()` | `App/Design/Modern.swift`（`iOS27SwipeContainer`）→ `App/Design/Controls.swift` 的 `ScreenScroll` | 自绘容器（ScrollView / LazyVStack）里的行**也能左滑**了；容器负责「一次只展开一行 / 滚动即收起 / 点外面即收起」 | iOS 26 → 无轻扫；**长按菜单**照旧（功能不缺，只是手势不同） |
| `swipeActions(edge:allowsFullSwipe:content:onPresentationChanged:)` | `App/Design/Modern.swift`（`swipeActionsCompat`）→ `LogScreen`（认领 / 备注 / 待查）、`AccessScreen`（复制 / 停用） | 记录时间线与凭证列表支持左滑处置；展开的那一行会被**压暗** | iOS 26 → 旧重载（只有按钮，没有回调） |
| `accessibilityActions(_:)` | 与轻扫同源命令 | 读屏用户能用同一组命令处置记录 | iOS 16+ 即可用 ✓ |

### 1.6 iOS 27 —— 基于数据的弹窗

| 能力 | 落点 | 表现 | 降级 |
|---|---|---|---|
| `alert(_:item:actions:message:)` | `App/Design/Modern.swift`（`itemAlert`）→ `LogScreen` 的备注弹窗 | 一个可选值就是全部状态；关闭时系统自动清空，**不再有「弹了但没有内容」的状态** | iOS 26 → `isPresented` + `presenting` 的等价写法（Bool 由 item 推导） |
| `confirmationDialog(_:item:titleVisibility:actions:message:)` | `App/Design/Modern.swift`（`itemConfirmationDialog`）→ **全 App 15 处确认框** | 同上：删凭证 / 删成员 / 认领归属 / 恢复校验和 / 关闭双验 / 清空密码 / 删本机数据 / 吊销钥匙 / 重写 PIN 池 / 复制帧骨架 / 关本机密码 / 硬件操作 / 命令台发送 | iOS 26 → 等价写法 |

### 1.7 iOS 27 —— 工具栏

| 能力 | 落点 | 表现 | 降级 |
|---|---|---|---|
| `toolbarOverflowMenu(content:)` | `App/Design/Modern.swift`（`toolbarOverflowCompat`）→ `QuickPoolEditSheet` | 次要动作**永远**待在溢出菜单里，不与主行动抢位置 | iOS 26 → 工具栏末尾的等价下拉菜单 |
| `.topBarPinnedTrailing` | `App/Design/Modern.swift`（`thresholdPinnedTrailing`）→ `QuickPoolEditSheet` | 「保存」钉在后缘，空间再紧也留在原处 | iOS 26 → 普通 `.topBarTrailing` |
| `visibilityPriority(_:)` | 同上 | 空间不足时，主行动**最后**被移进溢出菜单 | iOS 26 → 无优先级概念（系统默认） |

### 1.8 顺带用上的既有能力

| 能力 | 落点 | 说明 |
|---|---|---|
| `symbolEffect(.replace, value:)` | `App/Design/Controls.swift`（镜头的图标） | 锁 → 对勾 → 叉 是**形变**切换，不是硬切 |
| `contentTransition(.numericText(value:))` | `App/Design/Primitives.swift`（读数） | 数字滚动（iOS 17+），「减少动态效果」下自动退化为直接替换 |
| `accessibilityRole(.tab)` + `accessibilityAddTraits(.isSelected)` | `App/Design/Primitives.swift`（分段控件） | 读屏用户听到的是「今日，标签，已选中」，而不是三个孤零零的按钮 |

---

## 2. 明确**没有**接入的能力（以及原因）

| 能力 | 原因 |
|---|---|
| `reorderable()` + `reorderContainer(for:isEnabled:move:)`（iOS 27 拖拽重排） | **缺口在数据，不在 API**：`ReorderDifference` 只公开了 `sources`（被移动项的 id）与 `destination`（落点），而 `destination` 的**取值方式**在可核对的公开资料里没有确定答案（它是 `Destination` 结构体，公开成员未列明）。用猜的 API 实现「拖到哪」只会把顺序排错 —— **拖错比不能拖更糟**。快捷池编辑器现在仍是「上移 / 下移」按钮（对读屏与键盘同样可用）。等 SDK 文档给出 `destination` 的读取方式即可接上，改动面只有 `QuickPoolEditSheet` 一处。 |
| `ArrangementView` / `.arrangementViewStyle(.split/.overlay)`（iOS 27.1） | 这批 API 属于 **iOS 27.1**（iPhone Duo 折叠屏一代），而 CI 用的 SDK 版本未确认包含它们 —— 引用不存在的符号会**直接编译失败**，整个 App 停在红上。等 CI 换到 Xcode 27.1+ 再接；本 App 的两栏版式已经用 `AdaptiveLayout`（`twoColumns`）实现了，宽窄两种形态都可用。 |
| `reservedRegions(kind:options:layoutDirectionBehavior:)`（iOS 27.1） | 同上（27.1）。而且本 App 的内容都在系统容器（ScrollView / NavigationStack）里，系统已经为折叠与摄像头留好了边 —— Apple 明确说「标准容器已经适配，手动避让反而会让过渡不自然」。 |
| `onHingeChange(isEnabled:_:)`（iOS 27.1） | 同上（27.1），且需要 iPhone Duo 硬件才能验证；本 App 没有需要随折叠角变化的画面。 |
| `toolbarVerticalEdge` / `axisBehavior(_:)` / `toolbarVerticalBehavior(_:)`（iOS 27.1） | 同上（27.1），且这些是给**竖向工具栏**用的（折叠屏 / iPad 侧边栏）。本 App 隐藏了系统导航栏，用的是自绘的 NavRow + 浮岛 Tab 栏，没有竖向栏可适配。 |
| `Document` 协议族（`ReadableDocument` / `WritableDocument` / `DocumentCreationSource` / `NewDocumentButton`）（iOS 27） | **没有文档型界面**。备份是**加密后的不透明文件**（用户不该编辑它），诊断包是纯文本快照 —— 都不是「用户编辑并保存的文档」。硬套 Document API 只会多一层无用的抽象。 |
| `AsyncImage` 缓存 / `asyncImageURLSession(_:)`（iOS 27） | 本 App **不加载任何远程图片**（全部矢量自绘，零位图）—— 没有可缓存的对象。 |
| `contentTransition` 之外的 `@State` 宏（Xcode 27） | 这是**编译器侧**的行为（用 Xcode 27 编译即生效），不是代码里能写的东西。本 App 的 `@State` 已经是「每视图生命周期只初始化一次」的用法（`AppModel` / `Router` 都放在 `App` 层的 `@State`），语义与新宏一致。 |
| `ContentBuilder`（`ViewBuilder` 的新名字） | 是**别名**，不改变行为；本仓不需要改写现有 `@ViewBuilder`。 |
| `controlSize(.extraLarge)`、`.clipShape(.rect(cornerRadius:style:))` 的同心圆角、`Slider` 刻度、`TextEditor` 富文本、`searchToolbarBehavior(.minimizable)`（均为 iOS 26） | 逐条核对过**视觉收益**：本 App 的主行动按钮是固定 52pt 的品牌实底（系统尺寸不改变它）；分段控件是自绘的（不是 Slider）；备注是一行文字（富文本是杀鸡用牛刀）；搜索是页面内的固定输入框（挪到导航栏会破坏版式）。**没有为了用而用的调用。** |
| `sensoryFeedback(_:trigger:)`（iOS 17+） | 本 App 刻意**不用**它：早期版本把触感挂在相位上，连上/下发/等回执会连震四五下；现在触感只在**结果**上给（`Haptics.cue(_:)`，见 `App/Core/Haptics.swift`）。这是有意的设计决定，不是漏接。 |

---

## 3. 这次改造动到的共享组件

| 组件 | 变化 |
|---|---|
| `App/Design/Modern.swift`（**新增**） | 全 App 新能力的**唯一入口**：每个新 API 只在这里出现一次，页面里不写 availability 判断 |
| `App/Design/LiquidGlass.swift` | 玻璃材质加上 iOS 26 分支与 iOS 25 材质降级；玻璃参数就地构造（`Glass` 是 26+ 的类型，不能出现在签名里） |
| `App/Design/LensGlass.swift`（**新增**） | 镜头的可变形玻璃层 + iOS 25 降级 |
| `App/Design/Controls.swift` | `ChoiceChip` 走系统玻璃按钮；`ScreenScroll` 挂轻扫容器与滚动边缘柔化；镜头图标加 `symbolEffect` |
| `App/Design/Primitives.swift` | 分段控件补「标签页」语音语义 |
| `App/Design/Atmosphere.swift` | 日光场背景延展 |
| `App/ThresholdApp.swift` | 宽屏侧边栏形态 + 侧边栏头 + 标签栏收起（带分支） |
| 15 处确认框 / 1 处提醒 | 全部改成**基于数据**的弹窗（iOS 27），旧系统走等价降级 |
| `App/Features/Log/LogScreen.swift`、`AccessScreen.swift` | 行级轻扫操作（iOS 27）+ 展开行压暗 |
| `App/Features/Settings/QuickPoolEditSheet.swift` | 溢出菜单 + 钉住的主行动（iOS 27） |
| `App/Features/Access/MobileKeysScreen.swift` | 弹层从源按钮「长」出来（iOS 26） |

---

## 4. 没被破坏的东西（逐条核对）

| 流程 | 核对结果 |
|---|---|
| 解锁 | 镜头的玻璃层换成 `LensGlass26`（iOS 26+）/ `LensGlassLegacy`（iOS 25）；相位、环进度、触感、回执卡逻辑未动 |
| 凭证 | 列表与详情未改结构；只多了左滑操作与基于数据的确认框 |
| 配对 | 未改流程；进度条与失败分支仍是 AppModel 驱动的 |
| 记录 | 时间线仍是自绘 ScrollView（版式未变）；轻扫是**新增**手势，长按菜单仍在 |
| 恢复 | 「我锁在门外了」流程未改 |
| 设置 | 段落编号连续（01/02/03/04）；空壳里的隐藏规则未变 |
| 诊断 | 健康检查、诊断包、命令时间线未改；确认框改成基于数据的版本 |

---

## 5. 仍需真机验证的点

| 点 | 为什么静态闸门验不了 |
|---|---|
| 玻璃的折射与顶缘高光 | 只有真机有真实背景可采样；DesignLab 是 HTML 镜像 |
| 镜片变形的中间帧 | 形变动画的观感要人眼判断 |
| 轻扫操作的手感 | 跟手的程度、压暗的时机 |
| 侧边栏形态的排版 | iPad 上真实宽度下的换行与留白 |
| 滚动边缘柔化 | 内容穿过浮岛栏时的过渡观感 |
| iOS 25 的材质降级 | 需要一台 iOS 25 设备（或模拟器） |
