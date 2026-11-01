# 设计符合性报告（iOS 27 · 原生控件 / 液态玻璃 / 文字占用 / 布局）

> 这份文件回答：**按 iOS 27 的 skill 逐条核对，本仓现在站在哪里、还差什么。**
>
> 依据（都在本机 skill 库里，可复现）：
> - `swiftui-pro` → `references/api.md`（软废弃清单）、`accessibility.md`、`design.md`、`views.md`、`navigation.md`、`resizability.md`
> - `swiftui-expert-skill` → `references/liquid-glass.md`、`list-patterns.md`
> - `apple-design` → `references/code-audit.md`、`references/hig/liquid-glass.md`
>
> **一条规则只有在引用到具体页面/条目时才算"核对过"**；凭印象写的不算。

## 1. 原生控件

| 规则（出处） | 本仓状态 | 证据 |
|---|---|---|
| 有系统控件就用系统控件（`apple-design` `code-audit.md`） | **已改** | 见下表 |
| `TextEditor` 优先换 `TextField(axis: .vertical)`（`views.md`） | ✅ 未使用 `TextEditor` | `grep TextEditor` = 0 |
| `NavigationView` 已废弃（`navigation.md`） | ✅ | 0 处 |
| 旧的 `NavigationLink(destination:)`（`navigation.md`） | ✅ | 0 处 |
| `navigationDestination(for:)` 每栈注册一次（同上） | ✅ | `Shell.swift:96` 唯一一处 |
| `Label` 优先于 `HStack{Image;Text}`（`design.md`） | ✅ | `Label(` 11 处；`HStack{Image(systemName:);Text}` 候选 **0** |
| 空态用 `ContentUnavailableView`（`design.md`） | ✅ | 4 处 |
| 触觉用 `sensoryFeedback` 而非 UIKit generator（`api.md`） | ✅ | `sensoryFeedback` 6 处；UIKit generator **0** |
| 分享用 `ShareLink`（系统控件） | ✅ | 4 处 |

### 本轮 objective 期间完成的原生控件替换

| 自定义件 | 换成 | 覆盖调用点 |
|---|---|---|
| 档位 chip 行 | `Picker(.segmented)` | 10 |
| 读数行 `HStack` | `LabeledContent` | 55 |
| 手绘拖拽/上下移 | **`reorderable()` + `reorderContainer(for:)`（iOS 27）** | 1 面板（按钮保留） |
| 半透明材质 Tab 栏 | 原生 `.glassEffect` | 1 |
| 半透明提示条 | 原生 `.glassEffect` | 1 |

### 保留的自定义件（**不是**"重造系统控件"）

| 件 | 为什么保留 |
|---|---|
| `VMiniBars` / `VAreaChart` | 24 格 × 1.8pt 柱 + 5pt 辉光的**密集波形**，`BarMark` 无对应形态 |
| `VSegmentedRing` / `VRingStack` | **多段**环；原生 `Gauge` 是单值 |
| `VGauge` | 带刻度与游标的仪表盘，`Gauge` 无对应形态 |
| `VChipRow`（家页分组等） | 档位多到放不下，分段控件会被压扁 |

## 2. 液态玻璃

按 `hig/liquid-glass.md › Review checklist` 七条逐项核对：

| # | 条目 | 本仓 | 证据 |
|---|---|---|---|
| 1 | **层次纪律**：玻璃只在浮动控件与导航上 | ✅ | 仅 2 处：浮动 Tab 栏、顶部提示条。内容卡片/列表行 **0** |
| 2 | **克制**：自定义玻璃面数量 | ✅ | 全 App **2** 处，同屏最多 2（提示条是瞬时的） |
| 3 | **变体适配**：文字多的面用 regular，别用 clear | ✅ | 只用 `.regular`；`.clear` **0** 处 |
| 4 | **颜色预算**：每屏最多 1–2 个染色主操作 | ✅ | 染色只在两块**面**上，玻璃**按钮** 0 个 |
| 5 | **无障碍状态**：Reduce Transparency → 不透明；**Increase Contrast → 更强的填充与描边**；Reduce Motion → 去掉形变 | **本轮补齐** | 见 §2.1 |
| 6 | **滚动边缘**：内容与栏交界处淡出，不铺不透明底 | ✅ | 页面用 `.scrollEdgeEffectStyle`；玻璃下面没有实色底 |
| 7 | **点击区**：玻璃不缩小点击区（44×44） | ✅ | `a11y` 闸门在守 |

### 2.1 本轮修掉的缺口：Increase Contrast 没处理

`VGlassSurface` 原来只判 `accessibilityReduceTransparency`。开了「增强对比度」的用户看到的仍是半透明玻璃，
而 checklist 第 5 条明确要求这一档给 **stronger fills and borders**。

```swift
@Environment(\.colorSchemeContrast) private var contrast
private var opaque: Bool { solid || contrast == .increased }
// 描边：contrast == .increased 时 lineWidth × 2
```

### 2.2 逐条排除的误用

| 误用形态（`code-audit.md`） | 本仓 |
|---|---|
| 列表行 / 单元格 / 卡片 / 背景上用 `glassEffect` | **0** |
| 玻璃嵌玻璃且不在 `GlassEffectContainer` 里 | 无嵌套。两块玻璃一在屏幕底部、一在顶部，**不相邻**（参考原文限定 "nearby"） |
| `.clear` 玻璃压在文字上 | **0** |
| 工具栏/标签栏下面铺实色底 | **0** |
| 缺少 `accessibilityReduceTransparency` 分支 | 有（且本轮补了 Increase Contrast） |
| `UIDesignRequiresCompatibility = YES` | **不存在**（App 不在旧设计兼容模式） |

## 3. 控件大小考虑实际文字占用

| 规则（出处） | 本仓 |
|---|---|
| 不要写死字号，用 Dynamic Type（`accessibility.md`） | ✅ `VFont` 全部经 `@ScaledMetric` 渲染，`relativeTo` 默认 `.body` |
| 用 `dynamicTypeSize` 而非已废弃的 `sizeCategory`（同上） | ✅ `dynamicTypeSize` 7 处；`sizeCategory` **0** |
| 用 `isAccessibilitySize` 选布局（同上） | ✅ 5 处 |
| 布局要放得下更大的字号（`design.md`） | ✅ 见下表 |

### 本轮 objective 期间修掉的「文字被挤/被裁」

| 位置 | 旧 | 后果 |
|---|---|---|
| 浮动 Tab 栏标签行 | `frame(height: 57)` | 字号放大后文字被裁 |
| Tab 选中胶囊 | `.frame(width: 60, height: 49)` | 胶囊盖不住放大后的文字 |
| `VActionButton` / `VOutlineButton` | `frame(height: 50)` | 17pt 标题在 AX 档可到 53pt，被裁 |
| 记录页时间列 | `frame(width: 48)` | 「23:59」大字号下超宽被裁 |
| `VListRow.detail` | `lineLimit(1)` | 15–20 字说明**默认字号下就已截断** |
| `ToastHost` 文案 | `lineLimit(2)` | 最长 45 字，AX 档需 4 行；而 toast 会消失，截断即永远读不到 |
| `ReadingGrid`（18 处调用） | 固定 2–3 列 | AX 档每列过窄，读数被压 |
| `VStatPair`（12 处调用） | 固定横排 | AX 档两列互相挤 |
| `VListRow` 读数 | 固定右侧 | AX 档五元素挤一行 |

### 固化成闸门的两条

| 判据 | 位置 |
|---|---|
| `V.Action.height` / `V.Tab.height` 不许当固定高度 | `Gates/a11y.js` |
| 点击区 ≥ 44pt | `Gates/a11y.js` |

## 4. 布局

| 规则（出处） | 本仓 |
|---|---|
| **Never rely on `UIScreen.main`**（`design.md`；iPhone Duo 有两块屏） | ✅ 真实使用 **0**（唯一命中是注释里的历史说明） |
| 不按设备型号/idiom 选布局（`resizability.md`） | ✅ `userInterfaceIdiom` / `UIDevice.current` **0** |
| 底部留白不要自己估（`resizability.md`：不要用固定间距假装安全区） | ✅ 本轮改为 `onGeometryChange` **实测**栏高 |
| 优先 `safeAreaInset()` 等系统机制 | ✅ `Shell` 用 `safeAreaInset(edge:.bottom)` |
| `confirmationDialog` 挂在触发控件上（`navigation.md`，液态玻璃从正确位置展开） | ✅ 改了 2 处；其余 6 处逐条写明为何保留 |
| 最小点击区 44×44（`design.md`） | ✅ 闸门在守 |

## 5. 已知偏差（**明确记录，不假装没有**）

| # | 偏差 | 出处/严重度 | 为什么不改 |
|---|---|---|---|
| 1 | **手写的浮动 Tab 栏**（`HStack` 固定在底部），而非 `TabView` | `code-audit.md` 把它列为 **High**：会错过系统材质、系统适配，以及 **iPhone Duo 的侧边栏位置** | 它是本 App 的骨架（268pt 居中胶囊 + Router），换 `TabView` 等于重做导航层；且无 iOS 27 真机可验证观感。**这是本报告里最大的一处偏差。** |
| 2 | **没有任何尺寸类适配**：`horizontalSizeClass` / `verticalSizeClass` / `ViewThatFits` 全为 0 | `resizability.md`：iPhone Duo 合上/展开只改可用空间 | 影响 52 个 `ScrollView` 页面，且无真机可验证。属独立课题 |
| 3 | `ConcentricRectangle` 未使用 | `design.md`：贴边形状用它，远离边界的可继续用 `.rect` | 本仓卡片都内缩 `pageGutter`，属"远离边界"，规则允许 `.rect` |
| 4 | `RoundedRectangle` 到处显式写 `style: .continuous` | `design.md`：那是默认值，不必写 | 纯冗余，非缺陷；批量改会制造无意义的 diff |

## 6. 怎么复核这份报告

```bash
node Gates/allgates.js        # 22 道闸门
node Gates/glass.js           # 玻璃纪律（含"Material 只许出现在唯一入口"）
node Gates/a11y.js            # 点击区 / 固定高度 / 图标 label
```

数字口径：本报告里的「N 处」都是**当前源码的实际计数**，
复核脚本在 `_review/` 之外不保留 —— 需要时按表里的图案重新 `grep` 即可。
