# AUDIT-ROUND-158 · 第 158 轮：原生液态玻璃从 0 到 1，并修三处「固定尺寸裁字」

> 新 objective：用符合 iOS 27 的 skill 审核——原生控件优先、液态玻璃原生化、控件尺寸考虑文字占用、合理布局。
> 起点核对：`hig-doctor` MCP **已恢复可用**（本轮跑通了全项目审计）。

## 1. 起点数据：全 App **零**原生液态玻璃

```
glassEffect            0  (0 files)
GlassEffectContainer   0  (0 files)
buttonStyle(.glass)    0  (0 files)
.ultraThinMaterial     1  (V7Components 的浮动 Tab 栏)
```

也就是说：**"液态玻璃"此前只是"超薄材质 + 一层半透明色"** —— 那是模糊，不是玻璃。
原生 `.glassEffect()` 会采样背后的内容做折射与高光，这才是 iOS 26/27 的液态玻璃。

## 2. 建「玻璃的唯一入口」

新建 `App/Design/Components/GlassSurface.swift`：

```swift
struct VGlassSurface<Content: View>: View {
    var solid: Bool = false          // true = 「减少透明度」退化为不透明卡片
    var cornerRadius: CGFloat
    var tint: Color? = nil
    var stroke: Color? = nil
    @ViewBuilder var content: Content
}
```

为什么必须收在一处（三条都可核对）：

| 理由 | 说明 |
|---|---|
| `glass` 闸门要求"玻璃只在功能层" | 字面量收在一处，审计才能一眼看全"全 App 有几块玻璃" |
| 「减少透明度」必须退化 | 这个判断也只该有一份，否则总有某块忘了退化 |
| 两种观感不能混 | 一半原生玻璃 + 一半 Material 搓的玻璃，同屏会明显不一致 |

部署目标是 **iOS 27**，所以 `glassEffect` 无条件可用 —— **不加 `#available`**
（加了会被判"多余的可用性检查"，反而让 CI 告警不为 0）。

## 3. 浮动 Tab 栏：Material → 原生玻璃

```swift
// 旧：模糊 + 自家染色
.background {
    RoundedRectangle(...).fill(solidTabBar ? V.C.card : .ultraThinMaterial)
        .overlay { RoundedRectangle(...).fill(V.C.tabGlass) }
}
// 新：原生液态玻璃（染色与描边仍在，但底子是真玻璃）
.background {
    VGlassSurface(solid: solidTabBar, cornerRadius: V.R.tab,
                  tint: solidTabBar ? nil : V.C.tabGlass, stroke: V.C.tabEdge) {
        Color.clear
    }
}
```

## 4. 三处「固定尺寸裁字」

判据来自 objective 的「控件大小考虑实际文字的占用」。本仓字号**确实随 Dynamic Type 缩放**
（`VFont.relativeTo` 默认 `.body`，经 `@ScaledMetric` 渲染），所以固定尺寸在大字号下必然裁字。

| 位置 | 旧 | 新 | 后果（旧） |
|---|---|---|---|
| `VFloatingTabBar` 标签行 | `frame(height: 57)` | `frame(minHeight: 57)` | 57pt 要装 20pt 图标 + 2 + 标签，字号放大后**"门"字下半截被切** |
| `VFloatingTabBar` 选中胶囊 | `.frame(width: 60, height: 49)` | 按内容自适应（四周内边距） | 60×49 的前提是"2 个 11pt 汉字"；放大后**胶囊盖不住文字**，看起来像选中态破了 |
| `VActionButton` / `VOutlineButton` | `frame(height: 50)` | `padding(.vertical, gapS)` + `frame(minHeight: 50)` | `V.F.bodyStrong` 是 17pt 随 `.body` 缩放，AX 档可到 53pt ⇒ **按钮标题被裁** |
| `RecordsScreen` 时间列 | `frame(width: 48)` | `frame(minWidth: 48)` | 13pt 随 `.footnote` 缩放，「23:59」大字号下超过 48pt ⇒ **时间被裁** |

另外给 Tab 标签补了 `.lineLimit(1)` + `.minimumScaleFactor(0.75)`：
**宁可轻微缩字，也不要裁掉半个字**（裁掉会让人读不出是什么）。

## 5. 收紧闸门：Material 只允许出现在唯一入口

```js
// 旧：只禁止「内容层」用 Material（Shell/ 里随便用）
if (!rel.startsWith('Shell/')) { ... }
// 新：只允许 Components/GlassSurface.swift
if (!rel.includes('Components/GlassSurface.swift')) { ... }
```

双向验证：往 `V7Extras` 注入 `.background(.ultraThinMaterial)` → 判红；删掉 → 22/22 全绿。

## 6. 方法论

**「原生控件」这条要先去数"到底用没用"，而不是凭印象改。**

本轮第一步做的是**统计**（`glassEffect` 0 处、`Toggle` 7 处、`ProgressView` 11 处、
`ContentUnavailableView` 2 处…），而不是直接动手。结论是：

| 类别 | 状态 |
|---|---|
| 开关 / 进度 / 空态 / 弹窗 / 导航 | **已经是原生**（`Toggle` / `ProgressView` / `ContentUnavailableView` / `alert` / `NavigationStack`） |
| **液态玻璃** | **完全没有** ← 本轮补上 |
| 图表 / 仪表盘 | 全部手绘（`VMiniBars` / `VAreaChart` / `VGauge`） |
| 分段控件 / 搜索 | 自定义 |

**先数再改**，才不会把"本来就是原生的"也重写一遍。
