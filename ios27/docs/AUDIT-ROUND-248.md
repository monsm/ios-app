# AUDIT-ROUND-248 · 第 248 轮：一条**不可达的路由**（同一功能两份实现）

> CI：**`ccfb2d5` build 全绿** —— 锁钟哨兵修复（Round 245）编译通过。

## 1. 怎么发现的

枚举 `Router.Dest` 的 44 个 case，统计每个 case 在 `.dest(.X)` 里被跳转的次数：

| case | 跳转次数 | 判定 |
|---|---|---|
| `door` / `settings` | 0 | ✅ tab 根，不经 `.dest` |
| `unlockGate` | 0 | ✅ 门禁页，由根视图直接呈现 |
| **`alarmKinds`** | **0** | ❌ **死路由** |

## 2. 缺陷

「告警类型多选」实现了**两份**：

| 实现 | 入口 | 可达？ |
| --- | --- | --- |
| `AlarmKindsSheet` | `RecordsScreen` 的 `.sheet { … }`（按钮在筛选行） | ✅ |
| `AlarmKindsScreen` + `Dest.alarmKinds` | 无 | ❌ |

两者共用同一个 `AlarmKindsCard` 与同一份 `RecordsRoute.alarmKinds`，所以**行为完全一致** ——
这正是危险之处：以后有人改「告警筛选」，grep 到两处，很可能改错那处不可达的。

## 3. 修法

删除不可达的那份：`Dest.alarmKinds`（含标题映射与 tab 归属映射）、`Destinations` 的分支、`AlarmKindsScreen`。
`AlarmKindsCard` 保留（sheet 在用）。原地留注记说明为什么删。

## 4. 方法论

**「同一功能两份实现」的危害不是占空间，而是让后来者改错地方。**

| 情况 | 后果 |
|---|---|
| 一份实现 | 没有选择，不会改错 |
| 两份且都可达 | 改一处漏一处（本仓已抓到多次） |
| **两份且一份不可达** | **改了没效果，且不容易发现** |

判据：**枚举「路由/入口」清单，统计每个入口的实际跳转次数 —— 0 次的要么是根视图，要么是死代码。**
本轮 44 个 case 里只有 1 个属于后者。
