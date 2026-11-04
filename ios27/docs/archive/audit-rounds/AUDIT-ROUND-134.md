# AUDIT-ROUND-134 · 第一百三十四轮：差集指标失真，补一张事实来源表

> CI：`78d2e0d` 已验证绿；`8335306` / `350341c` 待回执。本轮本地提交。

## 1. 我发现自己的覆盖指标在失真

ROUND-122 建立的指标是：**文件 × 报告正文的差集 = 从未被专门审过的文件**。
这轮重算，从 26 缩到 13 —— 但看那 13 个，**好几个我明明审过**：

| 文件 | 我审过吗 | 为什么差集还列它 |
|---|---|---|
| `HouseholdParts.swift` | ✅ ROUND-133 审的，还发现了缺陷 | 报告里只写了 `HHMemberRow`，没写文件名 |
| `KeysBits.swift` | ✅ ROUND-131/132 | 同上 |
| `ToastCenter.swift` | ✅ ROUND-118 | 报告里写的是 `ToastHost` |
| `HeroStats.swift` | ✅ ROUND-128 | 报告里写的是 `setVisible` |

**根因**：我在报告里习惯写**符号名**（`HHMemberRow` / `ToastHost`），而不是文件名。
于是"文件名 vs 报告正文"这个机械判据**测不到**这些审计。

## 2. 处置：不修指标，而是补一张事实来源表

指标（差集）的价值是"帮我找到还没看的文件"，它不需要精确到"已审清单"。
真正需要的是**一张人能读、且可被逐行核对的表**。

所以 `AUDIT-COVERAGE.md` 新增 §2.5：

| 分组 | 内容 |
|---|---|
| 已审且**无缺陷** | 10 个文件（`RecordSearchQuery` / `StatusParser` / `Attribution` / `Reading` / `DefendService` / `BackgroundGuard` / `AuditChain` / `HeroStats` / `RecordModels` / `LockGuard`） |
| 已审且**发现缺陷** | 7 个文件（`HouseholdParts` / `KeysBits` / `ToastCenter` / `PidMap` / `TimeFormat` / `DateFormats` / `WeekCal`） |
| **尚未专门审** | 8 个（`AndroidPair` / `BLETypes` / `BatteryCare` / `DoorLayout` / `EngineHost` / `HouseholdRoster` / `LockStats` / `RecordSearchBuild`） |

并写明一条注记：

> 机械差集仍会列出上表里的某些文件，因为它们的**文件名**只出现在这一节 ——
> 这正是"报告里没写文件名"导致指标失真的例子。**上表是本轮之后的事实来源。**

## 3. 方法论

**"指标"与"台账"是两件东西，不要用前者替代后者。**

| | 差集指标 | 逐文件台账 |
|---|---|---|
| 用途 | 找"还没看的" | 回答"哪些看过了" |
| 精度要求 | 宁可多列（假阳性可容忍） | **必须准确** |
| 维护方式 | 可重算 | 每轮手动追加 |

我一开始想"把指标修准"，但那需要报告里统一写文件名 —— 而报告的价值在于讲清符号级的问题，
不该为了指标而改写作方式。**补一张台账，比修一个指标划算。**

## 4. 顺带确认

`AndroidPair` / `BLETypes` / `BatteryCare` / `DoorLayout` / `EngineHost` / `HouseholdRoster` /
`LockStats` / `RecordSearchBuild` 这 8 个确实还没专门审（其中 `BatteryCare` / `LockStats` /
`RecordSearchBuild` / `DoorLayout` 我改过，但那是"顺带改"而不是"专门审"）。
