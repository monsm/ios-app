# AUDIT-ROUND-162 · 第 162 轮：设置行的说明被截成一行；以及 hig-doctor 的分数不能当指标

> CI：**`18f63cd` 已验证绿**（`build_ok=1`、`errors=0`、`warnings=0`）——
> `Picker(.segmented)` 与 `LabeledContent` 两处原生改造都编译通过。
> `e3c2cd3` / `8a1135f` 待回执。

## 1. 缺陷：`VListRow.detail` 只给一行

```swift
Text(detail)
    .font(V.F.rowDetail)
    .lineLimit(1)      // ← 只有一行
```

而 `detail` 是 15–20 字的中文说明，例如：

```swift
VListRow(title: "电池档案", detail: "电量采样 / 五档 / 电池型号与换电日期", ...)
VListRow(title: "锁信息名片", detail: "固件 / 容量 / 电量采样 / 链路验证", ...)
```

在 393pt 宽的屏上，这一行减去 30pt 图标 + 间距 + 右侧读数后**只剩约 250pt**，
13pt 中文 20 字 ≈ 260pt ⇒ **默认字号下就已经被截**；无障碍字号下更糟。

改 `lineLimit(2)`：短说明的观感不变，长说明能读完。

（`VToggleRow` 的 `detail` 本来就没有 `lineLimit`，已经会换行 —— 同族里这一处是漏的。）

## 2. 一个重要结论：hig-doctor 的聚合分数**不能当进度指标**

本轮重跑全项目审计，结果是：

```
severities: {"critical":27, "serious":0, "moderate":55}
files: {"code":186, "style":0, "config":1}
```

**与本轮改造前完全一致**（尽管这四轮改了玻璃、两个原生控件、四处布局）。
于是逐个文件抽查它的规则来源：

| 文件 | 聚合里的"concern"数 | 逐文件审计的真实结果 |
|---|---|---|
| `KeyCreateScreen.swift` | 13 | 13 条全是 `swift/non-private-state`（moderate） |
| `Shell.swift` | 14 | **只有 2 条** moderate（`ignores-safe-area`），其余是 HTML 误匹配 |
| `V7Tokens.swift` | 2 | 2 条 `swift/hardcoded-rgbcolor`（令牌层本就是字面量的家） |
| `SettingsScreen.swift` | 2 | 2 条 `ignores-safe-area`（背景铺满，正常） |

逐文件全部是 **moderate**，没有一条 critical。也就是说 **聚合的 "27 critical" 无法从逐文件结果复现**。

### 逐条判定这三个高频规则

| 规则 | 本仓是否成立 |
|---|---|
| `swift/non-private-state` | **不成立** —— `*Parts.swift` 拆分要求 `@State` 必须 internal（`KeyCreateScreen` 头注写明） |
| `swift/ignores-safe-area` | **不成立** —— 背景铺满是正确用法（`V.C.bg.ignoresSafeArea()`） |
| `swift/hardcoded-rgbcolor` | **不成立** —— 令牌层的职责就是把 RGB 收在一处 |

**结论：这个 MCP 的规则集是通用正则，对本仓的设计系统架构不适用。**
以后不要拿它的 critical/moderate 数当"改进了多少"的证据 —— 它测不到本轮做的任何一件事。

（它的价值在**逐文件审计时的具体 ruleId + 行号**，可以当"去那条规则看一眼"的线索，
而不是分数。）

## 3. 方法论

**一个指标如果"改了很多但它一动不动"，先验证它测的是不是你在改的东西。**

我本可以用"审计分数没变差"来证明"没引入回归" —— 但那也是假的：它连"变好"都测不到，
自然也测不到"变坏"。**一个对变化不敏感的指标，对两个方向都不敏感。**

判据：**引入一个外部工具当指标前，先用一次已知的改动验证它会动。**
