# AUDIT-ROUND-160 · 第 160 轮：无障碍字号下的自适应布局（30 处调用），以及一个「决定不改」

> CI：**`95a036a`（液态玻璃）已验证绿** —— `build_ok=1`、`errors=0`、`warnings=0`。
> 这意味着 `VGlassSurface` 里 `.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: ...)`
> 的写法编译通过，本轮最大的风险点已清除。`18f63cd` 待回执。

## 1. 缺陷：无障碍字号下「多列/横排」把读数挤成一团

两条布局都在**默认字号下正确、无障碍字号下崩**：

| 组件 | 调用点 | 默认档 | 无障碍档（AX） |
|---|---|---|---|
| `ReadingGrid` | **18 处** | 2–3 列等宽读数 | 每列只剩一半宽度，22pt 读数放大到 ~68pt ⇒ 被压成"两个字一行"甚至截断 |
| `VStatPair` | **12 处** | 横排两列 | 每列一半宽 ⇒ 「近 30 天 / 12 次」变成四行 |

**读数类内容必须读准**（电量 82% 与 8% 只差一位），所以这里不能靠"缩字"或"截断"糊过去。

## 2. 修法：用原生 `DynamicTypeSize` 切换布局

**（a）`ReadingGrid` → 单列**

```swift
@Environment(\.dynamicTypeSize) private var typeSize
private var effectiveColumns: Int { typeSize.isAccessibilitySize ? 1 : max(columns, 1) }
```

`DynamicTypeSize.isAccessibilitySize` 是**原生属性**，不用自己算缩放比。

**（b）`VStatPair` → 竖排**

```swift
let layout = typeSize.isAccessibilitySize
    ? AnyLayout(VStackLayout(alignment: .leading, spacing: V.S.statGap))
    : AnyLayout(HStackLayout(alignment: .top, spacing: V.S.statGap))
layout { ForEach(...) { ... } }
```

用原生 `AnyLayout` 切换，**内容只写一遍** —— 不用复制两份视图树（复制的话两边的样式迟早会漂）。

## 3. 一个「决定不改」：`VMiniBars` / `VAreaChart` 保留手绘

按 objective 的「尽可能有原生控件就用原生控件」，图表本该换成 Swift Charts。**但这里是"尽可能"该停的地方**：

```swift
// V.Mini 的度量
static let gridCount: Int = 24
static let gridW: CGFloat = 1        // 网格线 1pt
static let barW: CGFloat = 1.8       // 柱子 1.8pt
static let glowRadius: CGFloat = 5   // 5pt 辉光
```

这不是"柱状图"，是**密集波形**（24 格 × 1.8pt 柱 + 辉光）。Swift Charts 的 `BarMark` 没有对应形态，
强行换会得到一个观感完全不同的东西 —— 那不是"原生化"，是"换掉设计"。

**判据**：**「原生控件」只在"这个自定义件是在重造系统已有控件"时成立**；
如果它是**为特定数据形态专门设计的可视化**，系统没有对等物，就不该换。

（判据的来源：`VMiniBars` 的 3 处调用都是"24 小时电池/记录密度"这种高密度低精度数据，
不是需要读具体数值的图表。）

## 4. 本轮的调用点覆盖

| 改动 | 覆盖调用点 |
|---|---|
| `ReadingGrid` 单列 | 18 |
| `VStatPair` 竖排 | 12 |
| 合计 | **30** |

加上上一轮的 `SettingChips`（10）与 `VFieldRow`（55），本轮 objective 启动以来已覆盖 **95 处调用点**。

## 5. 方法论

**"自适应布局"要用系统给的信号，不要自己算缩放比。**

| 做法 | 问题 |
|---|---|
| 自己读 `@ScaledMetric` 算倍数 | 只能猜阈值，且不同 `TextStyle` 的曲线不同 |
| **`DynamicTypeSize.isAccessibilitySize`（原生）** | 系统定义的档位边界，与设置里的"更大字体"完全一致 |

同理，切换布局用 **`AnyLayout`** 而不是复制两份视图树 —— 复制会让样式漂移。
