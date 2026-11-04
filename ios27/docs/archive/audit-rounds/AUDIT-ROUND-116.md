# AUDIT-ROUND-116 · 第一百一十六轮：审了 3 个「从未被专门审过」的文件，未发现缺陷

> CI：`6633fb7` 全绿（`errors=0`、`warnings=0`）；`21f2e74` / `0bd09d4` 待回执。

## 1. 本轮做了什么

沿用上轮建好的指标（**文件 × 报告正文的差集**），继续审那 26 个"从未被任何报告提到"的文件。
先确认了一件事：

```
闸门文本里被点名的: 0 / 26
```

也就是说这 26 个文件**只被通用形状规则覆盖**（闸门是按目录扫，不按名单），
从未被针对性检查过。

本轮逐个读完了 3 个：

| 文件 | 行数 | 结论 |
|---|---|---|
| `RecordSearchQuery.swift` | 74 | 无缺陷（下面记了 3 处核对） |
| `StatusParser.swift` | 217 | 无缺陷（偏移与时基均正确） |
| `Attribution.swift` | 80 | 与 `StatsKit.openTypes` 一致 |

## 2. 三处"看起来可疑、核对后正确"的地方

**（a）`dateOf` 用字符串解析而不是 `lockTime` 整数**

```swift
static func dateOf(_ r: Rec) -> Date? {
    if !r.timeStr.isEmpty { return DF.stamp.date(from: r.timeStr) }
    return nil
}
```

`Rec` 里其实有 `lockTime: Int64`，看起来"用整数更可靠"。但：

| 字段 | 单位 | 需要转换 |
|---|---|---|
| `Rec.lockTime` | **协议秒** | 要 `ZKProtocol.protoSecondsToUnix` |
| `Rec.timeStr` | 已格式化的**本地墙钟串** | 不需要 |

而 `parseLocal` 也钉在 `DF.stamp`（本地墙钟）—— 两边时基**一致**。所以用字符串是对的。

**（b）`leHexToU32` 里 `stride(from: b.count - 1, through: 0, by: -1)` 在空数组时**

`b.count == 0` ⇒ `from: -1, through: 0, by: -1`。Swift 的 `stride` 在 `from < through` 且 `step < 0` 时
返回**空序列**，循环体不执行 ⇒ 不会越界。安全。

**（c）`parseLogEntry` 的字节偏移**

格式注释写的是 `[type 1B][len 1B][idx 4B LE][lockTime 4B LE]`，代码：

| 字段 | 代码 | hex 字符位 | 对不对 |
|---|---|---|---|
| type | `b[0]` | 0–1 | ✅ |
| （len 跳过） | — | 2–3 | ✅ 有意跳过 |
| idx | `dropFirst(4).prefix(8)` | 4–11 | ✅ |
| lockTime | `dropFirst(12).prefix(8)` | 12–19 | ✅ |
| body | `dropFirst(20)` | 20– | ✅ |

`guard hex.count >= 20` 也正好是最小长度（10 字节）。全部正确。

## 3. 本轮没有改动任何代码

这是**刻意的**。objective 里写着「无可分析的时候不要强行硬分析」——
我读完这 3 个文件，确实没有找到缺陷。把"核对后确认正确"的推理过程写下来，
比编一个改动有价值。

## 4. 方法论

**"审过但没发现问题"是一种结果，应该如实记录。**

否则有两种坏结局：

| 做法 | 后果 |
|---|---|
| 为了"有产出"硬改一处 | 引入回归（本段已发生多次） |
| 不记录"审过" | 下一个人又要重读一遍，且不知道已经读过 |

所以本轮的价值是：**这 3 个文件从此可以标"已审、无缺陷"**，差集从 26 缩到 23。

## 5. 下一步

剩余 23 个文件（`Reading` 104 行 / `DateFormats` 84 / `TimeFormat` 75 / `ToastCenter` 71 /
`DoorLayout` 68 / `WeekCal` 66 / `PidMap` 55 / `DefendService` 50 / `AuditChain` 43 /
`BackgroundGuard` 35 / `RecordModels` 30 / `LockGuard` 29 / `HeroStats` 19 / 若干 Parts 文件）。
下一轮继续，同样标准：**找到就改，找不到就如实记录。**
