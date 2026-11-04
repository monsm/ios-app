# AUDIT-ROUND-233 · 第 233 轮：一个恒返回空串、且没人读的属性

> CI：**`2222064` build 全绿**（借用登记清理编译通过）。

## 1. 缺陷

`RecordsModels.swift` 的 `Rec` 上有：

```swift
/// TODO(engine) 协议帧 hex：缓存层存了才原样带出，否则留空。
var hex: String { "" }
```

核实结果：

| 检查 | 结果 |
|---|---|
| 有没有人读 `Rec.hex` | **0**（Records 目录内 `.hex` 零读取） |
| `RecordCSV` 用的是这个类型吗 | ❌ 用的是 `RecordExportRow` |
| `CachedLog` 里有协议帧 hex 吗 | ❌ 没有 |
| `【保留未接】` 标记 | ❌ 没有 |

**一个永远返回空串、又没人读的属性**，还挂着一条 TODO 暗示"将来会带出数据"。

## 2. 修法

删除，原地留注记说明**为什么删**（与 `quota` / `organizeTotal` / `DiagFlags.silent` 同处置）。

并写明：真要做「导出协议帧」是一个独立功能（要先让 `CachedLog` 存 hex、再定导出格式），
**不是补一个空 getter**。

## 3. 这轮顺带纠正我自己一个错误假设

我先怀疑「成员电话采集了但从不显示」——`MemberCard` 确实没有 `phone` 字段。

但 grep 之后发现：

```swift
HouseholdScreen.swift:280   if let phone = DB.member(member.id)?.phone, !phone.isEmpty { … }
MemberDetailScreen.swift:338   phone = DB.member(m.id)?.phone ?? ""
```

**两处都直接读 `DB.member(…)?.phone`，绕过 `MemberCard`。** 所以电话是显示的 ✅，我的假设不成立。

## 4. 方法论

**「结构体里没有这个字段」不等于「界面上看不到」—— 界面可能绕过投影直接读存储。**

| 判断路径 | 结论 |
|---|---|
| `MemberCard` 没有 `phone` | 只是"投影里没有" |
| **grep `.phone` 全仓** | **才能知道有没有显示** |

判据：**怀疑"采集了没显示"时，grep 值本身，不要 grep 你以为是唯一出口的那个结构体。**
