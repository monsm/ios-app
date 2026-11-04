# AUDIT-ROUND-312 · 第 312 轮：周报与「本周」会错开一天 —— 而且这条路**已经通了**

> CI：`a8b24bea` build 全绿（errors=0）。

## 1. 背景：两把尺

| accessor | 是否应用 `kf_week_start` | 谁在用 |
|---|---|---|
| `WeekCal.calendar` | ✅ 应用 | `MemberHub.weekKey`、`HouseholdRoster`、`RecordSearchParse` 的「本周/上周」 |
| `WeekCal.gregorian` | ❌ 忽略 | **`StatsKit.lastWeekDigest`（周报周界）** |

代码注释把它登记为「今天两者等价（偏好无人写入），所以不是缺陷」。

## 2. 但那条「没人写」的假设是错的

| 写入路径 | 证据 |
|---|---|
| **备份恢复会写 `kf_week_start`** | `BackupKit.swift:356` `set("kf_week_start", a.weekStart)` |
| 备份里也可能带这个字段 | `BackupKit.swift:271` `weekStart: enumVal("kf_week_start")` |

⇒ 只要某份备份带 `weekStart: "mon"`，恢复后：

| 功能 | 周界 |
|---|---|
| 「本周」搜索（`WeekCal.calendar`） | 周一为界 |
| **周报 `lastWeekDigest`（`WeekCal.gregorian`）** | **仍按系统默认（可能周日）** |

两边差一天，而用户看到的会是「本周记录」与「上周周报」对不上。

## 3. 修法：一行 + 把注记改成约束

`StatsKit.lastWeekDigest` 的 `let cal = WeekCal.gregorian` → **`WeekCal.calendar`**。

**为什么现在改是零风险**：偏好为空时 `calendar` 直接返回 `gregorian`（`WeekCal:67-69` 的 `guard` 分支）⇒ 行为完全不变 ✅。

同时把 `WeekCal` 的注记从「接线时要做」改成「**已统一**」，并加一条反向约束：

> 不要再往这块加 `WeekCal.gregorian` 的**周区间**计算 —— 周相关一律用 `calendar`；
> `gregorian` 只用于「取年月日时分」这类与周起始无关的场合。

## 4. 方法论

**「今天两者等价」不等于「不是缺陷」—— 要看**有没有一条写入路径能把它们分开**。**

| 判断 | 结论 |
|---|---|
| 只问「现在会不会出问题」 | 不会（偏好为空） |
| **问「有没有路径能让它出问题」** | **有（备份恢复）** ⇒ 是缺陷 ✅ |

判据：**两个口径并存时，判据不是「当前值是否相同」，而是「是否存在使它们分叉的写入路径」—— 有路径就要按分叉后的语义写代码。**
