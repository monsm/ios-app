# AUDIT-ROUND-120 · 第一百二十轮：一个"有实现、有备份白名单、但没有 UI"的偏好

> CI：`f563712` 已验证绿（`errors=0`、`warnings=0`）；`ca5b563` / `9da0da6` 待回执。本轮本地提交。

## 1. `WeekCal.swift` 本身写得很严谨

这个文件注释里已经处理了三个经典坑，我逐个核对都正确：

| 坑 | 处理 |
|---|---|
| 用户历法切佛历/农历 | 钉 `Calendar(identifier: .gregorian)`，其余旋钮照抄 |
| 夏令时 ±24 小时 | `shifted(_:days:)` 用 `date(byAdding: .day)` 而非 `addingTimeInterval` |
| `firstWeekday` 改了但 `minimumDaysInFirstWeek` 没改 | 显式档位钉死为 4（ISO 口径） |

## 2. 但发现：`kf_week_start` 这个偏好**根本没有 UI 写入点**

搜索全仓 `kf_week_start`：

| 出现处 | 用途 |
|---|---|
| `WeekCal.key` | 读 |
| `BackupBundle.weekStart` | 备份结构体字段 |
| `BackupKit` 白名单 `["", "mon", "sun", "sat"]` | 导出时枚举校验 |
| `BackupKit` / `BackupStudioKit` | 导入导出 |
| **设置页** | **零** |

也就是说：

```
现网恒为 "" ⇒ weekdayMap 分支永不执行 ⇒ WeekCal.calendar 恒等于 gregorian
```

**备份里却白名单着 `mon`/`sun`/`sat` 三个值** —— 也就是说"从别的设备/旧版本导入一份带
`kf_week_start: "mon"` 的备份"，这个偏好会**生效**，但用户在本机永远看不到、也改不了它。

## 3. 判定：保留未接（不是死代码）

按三特征：

| 特征 | 有？ |
|---|---|
| 需求编号（912） | ✅ |
| 实现完整 | ✅（映射表 + 注释里三处坑都处理了） |
| 能指出接线点 | ✅ 外观页「记录页」分区 |

⇒ **保留未接**。已加 `【保留未接】` 标记，并登记进 `RESERVED.md` 新开的一节
「**存储键级**的保留未接」（因为它不是函数，`reserved.js` 闸门按 `func <name>` 查找，
登记在函数表里会误报）。

## 4. 顺带记下一个接线时必须处理的副作用

```swift
// HouseholdRoster.weekKey / MemberHub 的轮值键
String(c.component(.yearForWeekOfYear, from: date)) + "-W" + String(c.component(.weekOfYear, from: date))
```

**周号依赖 `firstWeekday`**。如果用户在某周中途把档位从"跟随系统"切成"周一"，
`weekOfYear` 会变，于是"本周轮值"看起来**丢了一周**（旧键的数据还在，但读不到了）。

所以这个偏好的接线成本是 **高**，不是"加个选择器"那么简单 —— 必须先定好
"切档位时已有的 `duty` 表怎么迁移"。已写进 RESERVED 的成本列。

## 5. 方法论

**"备份里有、界面上没有"是一个可机械发现的不一致。**

这次发现路径是：读 `WeekCal` → 看到 `weekdayMap` → 问"谁写这个键" → 搜全仓 → 只有读和备份。

可推广的判据：**凡是"读某个键"的地方，都搜一遍"谁写它"**；
若只有备份在写，就说明"这个偏好的 UI 还没接"或"接了一半"。

本仓另一个同形态的例子：`HintOnce.swift`（0 字节空文件，上轮已删）。
