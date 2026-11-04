# AUDIT-ROUND-163 · 第 163 轮：提示条也用原生玻璃；以及 toast 文案被截断

> CI：**`8a1135f` 已验证绿** —— `onGeometryChange` 编译通过（意味着 `AnyLayout` 那笔也过了）。
> 至此四个新 API 全部验证：`glassEffect` / `Picker(.segmented)` / `LabeledContent` / `AnyLayout` / `onGeometryChange`。

## 1. 提示条改用原生液态玻璃

`ToastHost` 原来只是一层半透明色：

```swift
.background(V.C.tabGlass, in: .rect(cornerRadius: V.R.action, style: .continuous))
```

提示条是**浮在内容之上的临时层**，正是 Liquid Glass 的设计场景。改用同一入口 `VGlassSurface`：

```swift
.background {
    VGlassSurface(solid: systemReduceTransparency || SettingsStore.shared.reduceTransparency,
                  cornerRadius: V.R.action, tint: V.C.tabGlass, stroke: V.C.tabEdge) { Color.clear }
}
```

关键点：**「减少透明度」的判据与 Tab 栏用的是同一条**（系统设置 or App 内开关），不另写一套 ——
两处各写一套的话，迟早有一处漏掉「App 内开关」。

玻璃闸门仍然报「自定义玻璃面 **1** 处」：因为 `.glassEffect(` 这个字面量只在 `GlassSurface.swift` 里。
这正是上一轮把它收成唯一入口的收益 —— **加玻璃面不影响闸门计数，也不破坏"玻璃只在功能层"。**

## 2. 缺陷：toast 文案在无障碍字号下被截断

```swift
Text(message).font(V.F.footnote).lineLimit(2)
```

实测最长的一条 toast 是 **45 字**（「已归档 · 历史留在记录页，可随时恢复 TA」这类）。

| 字号档 | 估算行数 | 2 行够不够 |
|---|---|---|
| 默认（13pt） | 约 1.8 行 | 刚好 |
| AX 档（~30pt） | 约 4 行 | **不够** |

而 toast **会自己消失** —— 被截掉的部分用户**永远读不到**（不像列表可以再点进去看）。
所以这条不能靠"截断"兜底：改 `lineLimit(4)`。

## 3. 方法论

**"会消失的界面"和"可以再看的界面"，截断的代价不一样。**

| 类型 | 截断后还能补救吗 | 策略 |
|---|---|---|
| 列表行 / 卡片 | 能（点进详情） | `lineLimit(1)` 可以接受 |
| **toast / 提示 / 一次性文案** | **不能** | **宁可多占两行** |

判据：**给一个 `Text` 加 `lineLimit` 前，先问"这个界面会不会消失"。**
