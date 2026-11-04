# AUDIT-ROUND-166 · 第 166 轮：设置行的读数在无障碍字号下换行；`swiftui-pro` 布局规则全面核对

> CI：`ad34f48`（toolbarVisibility）已验证绿；`6743235`（reorderable）待回执。

## 1. 缺陷：`VListRow` 五个元素挤一行

```
[图标 30pt] [标题 / 说明] [Spacer] [读数] [chevron]
```

默认字号下刚好。但 `V.F.rowTitle`（16pt，随 `.body`）与 `V.F.rowDetail`（13pt）在 AX 档会放大 2–3 倍，
五个元素挤一行 ⇒ 读数被挤到换行或截断，而**读数恰恰是设置页最关键的信息**（「已备份 / 从未」）。

改法（与系统行为一致）：无障碍字号下把读数移到标题下方 ——
`Form` 里的 `LabeledContent` 在大字号下正是这么排的。

```swift
if typeSize.isAccessibilitySize { valueText }     // 放进标题 VStack 内
...
if !typeSize.isAccessibilitySize { valueText }    // 右侧原位
```

`valueText` 抽成一个 `@ViewBuilder`，**样式只写一份** —— 两处各写一份的话，
字号/颜色/等宽数字迟早会漂。

## 2. `swiftui-pro` 的布局规则逐条核对

`references/design.md` + `references/resizability.md` 里可机械核对的几条：

| 规则 | 本仓 | 判定 |
|---|---|---|
| **Never rely on `UIScreen.main`**（iOS 26 起废弃；iPhone Duo 有两块屏） | 扫描命中 1 处 | **假红** —— 那处在**注释**里（"不再使用已废弃的 `UIScreen.main`"），实际用的是 `UIScreen.capturedDidChangeNotification` |
| 空态优先 `ContentUnavailableView` | 已用 2 处 | ✅ |
| `ContentUnavailableView.search` 用于搜索空态 | 0 | 本仓搜索是页内卡片（非 `.searchable`），不适用 |
| 图标 + 文字优先 `Label` | 已用 11 处；`HStack { Image; Text }` 候选 **0** | ✅ |
| 用 `bold()` 而非 `fontWeight(.bold)` | `bold()` 2 处 | ✅ |
| 最小点击区 44×44 | `a11y` 闸门在守 | ✅ |
| `ConcentricRectangle`（iOS 26+，贴边形状） | 未使用 | 本仓的卡片都内缩 `pageGutter`，属"远离边界"，按规则可用 `.rect`。**不改** |
| 基于 `horizontalSizeClass` 而非设备型号 | **0 处使用** | 见 §3 |

## 3. 一个**明确的能力缺口**：本仓没有尺寸类适配

```
horizontalSizeClass   0
verticalSizeClass     0
ViewThatFits          0
```

`resizability.md` 明确说：iPhone Duo 合上/展开时**不重启 App、不改 `scenePhase`**，
只改可用空间；外屏"宽而矮"，内屏有中央折痕。

**本仓目前是所有页面都按"高窄 iPhone"设计的**（`ScrollView` + 固定列数）。
在 iPad 分屏或 iPhone Duo 内屏下，内容会拉得很宽但列数不变。

**本轮不做**，理由：

| 理由 | 说明 |
|---|---|
| 没有真机可验证 | 本机无 iOS 27 环境，改了也无法确认观感 |
| 影响面大 | 涉及 52 个 `ScrollView` 页面 |
| 不是"原生控件"问题 | 是**响应式布局**的独立课题 |

已记录为**已知缺口**，而不是假装没有。

## 4. 方法论

**"扫描命中"和"缺陷"之间还差一步：读那一行。**

本轮 `UIScreen.main` 扫出 1 处，看起来是"违反 iOS 26 废弃规则"的真缺陷 ——
打开一看，那句话是注释里的**历史说明**："不再使用已废弃的 `UIScreen.main`"。
代码实际早改对了。

如果只信扫描结果就去"修"，我会把一句正确的注释改掉，或者在已经正确的代码上再包一层。
