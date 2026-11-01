# AUDIT-ROUND-139 · 第一百三十九轮：跨锁时间线静默吞掉「没读到时钟」的行

> CI：`d694a4d` 已验证绿；`216c46c` / `76a01b7` / `338ce0d` 待回执。本轮本地提交。

## 1. 缺陷：`buildRecs` 没过滤 `lockTime == 0` 的行

`StatusParser:151` 明确：

```swift
lockTimeStr: lockTime != 0 ? ProtoTime.localStr(lockTime) : ""
```

即 **`lockTime == 0`（锁端没读到时钟）⇒ `timeStr` 是空串**。

而单锁路径 `RecordsModels:265` 早就处理了：

```swift
guard log.lockTime > 0 else { untimed += 1; continue }
```

**但跨锁路径 `buildRecs` 没做** —— 于是这些行带着空 `timeStr` 进了结果集，造成两个可见后果：

| 后果 | 机制 |
|---|---|
| 排到列表最底 | `out.sort { $0.timeStr > $1.timeStr }`（降序），空串最小 ⇒ 全部沉底 |
| **时段筛选静默丢弃** | `RecordsStudioScreen.inSegment` 用 `DF.stamp.date(from: "")` ⇒ `nil` ⇒ 返回 `false` |

第二条最要紧：用户选「上午」时段，这些行**全部消失**，而界面不提示 ——
用户会以为"这个时段真的没有记录"。

## 2. 修法（两步）

**（a）`buildRecs` 跳过这些行**（与单锁路径同口径）：

```swift
guard e.lockTime != 0 else { continue }
```

**（b）补一个计数口 + 界面提示**（因为单锁路径不只是跳过，还会**告知**）：

```swift
static func untimedCount(macs: [String]) -> Int {
    macs.reduce(0) { n, mac in n + DB.readLogs(mac).filter { $0.lockTime == 0 }.count }
}
```

界面（`RecordsStudioScreen`）在列表上方：

> 「另有 N 条日志锁端没回时刻，未进时间线（不是丢失，是锁钟未读到）。」

## 3. 为什么只改一半是错的

我第一版只加了 `guard ... else { continue }` —— 那确实修了"静默丢弃"，
但**比单锁路径少了一半信息**：单锁路径会告诉用户「有 N 条没读到时刻」。

如果我只跳过不告知，用户看到的就是"记录变少了，但不知道为什么" ——
**从"静默丢弃"变成了"静默消失"**，并没有更好。

## 4. 方法论

**修一个"路径 A 缺少路径 B 已有的处理"时，要抄完整，不是抄一半。**

| 抄一半的后果 | 例 |
|---|---|
| 修了行为，丢了信息 | 本轮：跳过但不说 |
| 修了信息，丢了行为 | 只提示但仍显示错误数据 |

判据：**对照两条路径的"行为 + 信息"两个面**，逐面确认。

本段同类：ROUND-47 删设备漏清钥匙串副本（清了 plist 键但没清副本）—— 也是"抄一半"。
