# AUDIT-ROUND-172 · 第 172 轮：把标签栏换成**官方 `TabView`**（真正的液态玻璃控件）

> 用户反馈：**"该液态玻璃的控件还是没有用官方的控件呈现液态玻璃啊"**
>
> 这条批评是对的。上一段我做的是「自己画一条 HStack 胶囊，再在它背后铺一层 `.glassEffect`」——
> 那是**给自定义控件painted 了一层玻璃**，不是用官方控件呈现液态玻璃。

## 1. 判据在哪

`apple-design` 的 `code-audit.md`（本轮之前我把它记为"已知偏差"而不是"待修"）：

> **A hand-built tab bar or toolbar** (an `HStack` pinned to the bottom, a custom `UIView` bar)
> where `TabView`, `UITabBarController`, `.toolbar`, or `UIToolbar` would do
> → Misses the system material, its adaptations, and the iPhone Duo side placement

`swiftui-expert-skill` 的 `liquid-glass.md` 也说：玻璃的**官方形态**来自系统控件本身，
而不是把 `.glassEffect` 贴到任意自绘形状上。

## 2. 改法：`TabView` + `Tab`（iOS 18+ API）

```swift
TabView(selection: $router.tab) {
    Tab(TabSlot.door.title, systemImage: TabSlot.door.symbol, value: TabSlot.door) {
        NavigationStack(path: router.path(for: .door)) { DoorScreen().withDestinations() }
    }
    Tab(TabSlot.keys.title, systemImage: TabSlot.keys.symbol, value: TabSlot.keys) { ... }
        .badge(keysBadge)          // 原生角标，不再自己画红点
    ...
}
```

现在标签栏由**系统渲染**，自带：Liquid Glass 材质、选中态形变、滚动收起、
iPhone Duo 展开后的侧边位置、VoiceOver 的「第 N 个标签，共 M 个」语义。

### 代价（如实写进代码注释）

v7 参考图是「268pt 居中浮动胶囊」，官方标签栏是**全宽**的。
这是"用官方控件"必然带来的视觉变化 —— 但换来的是真正的系统材质与系统适配。

### `household` 为什么也在栏里

`router.tab = .household` 有 **5 处调用**（成员建档/详情/归档/操作页返回时切回）。
它必须是真标签，否则那 5 条路径会把 `selection` 置成一个 TabView 里不存在的值。
所以原生栏是 **5 项**（此前自定义栏只画 4 项、`家` 靠深链进）。

## 3. 连带清理（这些都是换控件后必须做的）

| 项 | 处置 |
|---|---|
| `VFloatingTabBar` + `VTabItem`（119 行） | **删除** —— 只剩自己的 Preview 引用，是死代码 |
| `VFloatingTabBarPreviewHost` + 它的 `#Preview` | **删除** |
| `C.tabPill` / `C.tabPillEdge` / `F.tabIcon` | **删除**（`tokens` 闸门报"零消费者"，处置就是"要么用起来要么删掉"） |
| `enum Tab`（width/height/bottom/selectedW/selectedH/iconSize/labelGap/contentInset） | **删除** |
| `R.tab` / `R.tabSelected`（28.5 / 24.5） | **删除** |
| **13 个页面的 `.padding(.bottom, V.Tab.contentInset)`** | **删除** —— 这是关键：原生 `TabView` 自己会用 safe area 预留空间，再补 92pt 就是**多出一大块空白**。**这是换控件如果不连带清理就会引入的回归。** |

## 4. 为什么**没有**把 `VActionButton` / `VOutlineButton` 也换成 `.buttonStyle(.glass)`

`liquid-glass.md › Review checklist` 第 1 条（层次纪律）：

> Glass appears only on **floating controls and navigation**.
> Glass on app backgrounds, **cards**, list rows, or content containers is a **defect**.

这两个按钮都用在**内容卡片里**（卡片内的主操作/次操作）。把它们做成玻璃按钮，
不是"更原生化"，而是**违反层次纪律** —— 玻璃会与卡片背景叠在一起，层级反而糊掉。

该玻璃的只有浮动层：标签栏（本轮已换成官方 `TabView`）、提示条（`VGlassSurface`）。

## 5. 方法论

**「贴了玻璃效果」≠「用了玻璃控件」。**

| 做法 | 得到什么 |
|---|---|
| `.glassEffect` 贴到自绘形状上 | 一层会折射的材质，但控件仍是自绘：无系统形变、无系统适配、无系统语义 |
| **换成系统控件（`TabView`）** | 材质 + 形变 + 适配 + 语义，**全部由系统负责** |

判据：**先问"这个东西系统有没有现成控件"，有就换控件；只有在系统没有对应控件时，才考虑给它加材质。**

另一条：**换控件必须连带清理"为旧控件服务的布局假设"**。
本轮 13 个页面的 92pt 底部留白就是这种假设 —— 不删就是一大块空白，
而且它是**静默的**（不报错、不告警，只是看起来"底部怎么空了"）。
