# AUDIT-ROUND-247 · 第 247 轮：电量链路全链核对 —— **审过，无缺陷**

> CI：**`4a3b788` build 全绿**（成员计数刷新编译通过）。

## 1. 本轮核对的链路

从「读锁状态」到「低电通知」的每一环：

| 环 | 位置 | 结论 |
|---|---|---|
| 采样埋点 | `LockServiceOps:27` → `BatteryCare.sample` | ✅ 真接了（90 天 / 720 条 / 同分钟去重） |
| 展示取数 | `displayPct`（采样与快照谁新用谁） | ✅ 五处全部走它（Round 236 统一了门页） |
| 展示文案 | `faceText`（`>80%` 粗估档 / `--` 未知） | ✅ |
| 锁电量哨兵 | `LockSummary.battery == -1` | ✅ 消费点全部 `>= 0` 前置 |
| 低电通知滞回 | `evaluateLowBattery` | ✅ `>30%` 重置 / `≤20%` 一档 / `≤10%` 二档 / 只升级不重复 |
| 通知标识 | `c6.batt.<mac>.l<level>` | ✅ 即时通知（`trigger: nil`），送达即消失，不会累积 |
| 阈值来源 | `CareSchedule.battThreshold` | ✅ 全仓**只有一个**（`kf_batt_threshold`，10/15/20 白名单） |
| 夜间免扰 | `quietNight` | ✅ 有 setter、有 UI 开关（`AppearanceScreen:386`）、有消费点（两处 `sound(at:)`） |

## 2. 顺带澄清一个我一开始误判的点

grep `battThreshold` 时同时命中 `BatteryCare.swift:211` 与 `CareSchedule.battThreshold` ——
看起来像「两套阈值」。实际 `CareSchedule` 就定义在 `BatteryCare.swift` 里，**是同一个声明**。

**教训：grep 命中同一行的两种模式，不等于两个实体。** 先看文件再下判断。

## 3. 方法论

**「审过、无缺陷」要写下来 —— 否则下一轮会重新审一遍。**

| 记录 | 价值 |
|---|---|
| 只记缺陷 | 下一轮无法区分「没查」与「查过没问题」 |
| **缺陷 + 无缺陷清单** | 覆盖度可见，重复劳动消失 |

本轮清单同时是一份**接线图**：电量从哪来、经过谁、到哪去。以后改这条链的人可以直接照它核对。
