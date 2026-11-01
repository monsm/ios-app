# AUDIT-ROUND-117 · 第一百一十七轮：跨年的组头只显示「月-日」

> CI：`21f2e74` 全绿（`errors=0`、`warnings=0`）。本轮本地提交。

## 1. 缺陷：`dayTitle` 一律 `MM-dd`，跨年时无法分辨

```swift
static func dayTitle(_ dayKey: String) -> String {
    let today = dayKeyFmt.string(from: Date())
    if dayKey == today { return "今天" }
    ...
    if dayKeyFmt.string(from: yesterday) == dayKey { return "昨天" }
    return dayTitleFmt.string(from: d)      // ← 恒为 MM-dd
}
```

而记录页**会列出跨年日志** —— 锁端日志一次能读到几十上百条，跨年是常态。于是：

| 实际日期 | 组头显示 | 用户看到 |
|---|---|---|
| 2026-12-25 | `12-25` | 今年 |
| **2025-12-25** | **`12-25`** | **也像今年** |

两个组头文字完全相同，用户既分不清哪年，也无法比较。

## 2. 影响面：8 处调用

```
RecordsScreen:335 / 567 / 605     记录页组头、只看某天
RecordExportScreen:267 / 278      导出分组与无障碍标签
Ledger.swift:94                    台账行
KeyCalendarScreen:192             到期月历当天卡片标题
```

**导出那一处尤其要紧**：导出的文本里两个 `12-25` 分节，读的人无从判断。

## 3. 修法

```swift
// 与「今天」同一年 → MM-dd；否则 yyyy-MM-dd。
let thisYear = calendar.component(.year, from: Date())
let thatYear = calendar.component(.year, from: d)
return thatYear == thisYear ? dayTitleFmt.string(from: d) : dayKey
```

（`dayKey` 本身就是 `yyyy-MM-dd`，直接复用，不再另建格式器。）

## 4. 回归测试

```swift
func testDayTitleCarriesYearWhenNotCurrentYear() {
    XCTAssertEqual(TimeFormat.dayTitle(todayKey), "今天")
    XCTAssertEqual(TimeFormat.dayTitle(lastYearKey), lastYearKey,
                   "跨年日期必须原样返回 yyyy-MM-dd，不能只给 MM-dd")
    XCTAssertTrue(TimeFormat.dayTitle(lastYearKey).hasPrefix(String(thisYear - 1)),
                  "跨年组头必须以那一年开头")
}
```

## 5. 方法论

**"格式化函数"的缺陷往往不在实现，而在"它假设了什么范围"。**

`MM-dd` 这个格式本身没错 —— 它只是**默认了"所有数据都在今年"**。
而记录类 App 的数据天然跨年。

判据：**凡是格式化时间的地方，问一句"这批数据的时间跨度有多大"**；
如果跨度可能超过一年，就必须把年份纳入格式或做条件分支。

## 6. 本轮同时审了 2 个文件（无缺陷）

| 文件 | 结论 |
|---|---|
| `Reading.swift`（104 行） | 无缺陷。`FieldRow` 的 `minHeight: V.Hit.min - V.S.gapS` 是行距补偿，而它是**纯展示行**（无点击），不涉及命中区 |
| `TimeFormat.swift`（75 行） | 发现本轮缺陷 |

差集从 23 缩到 21。
