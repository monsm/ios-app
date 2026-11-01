# AUDIT-ROUND-125 · 第一百二十五轮：`DF` 没钉公历，与 `TimeFormat` 会显示不同年份

> CI：`359b773` 已验证绿（`errors=0`、`warnings=0`）；`0fd7c63` / `8368291` 待回执。本轮本地提交。

## 1. 缺陷：两个日期工厂，只有一个钉了公历

```swift
// TimeFormat.machine（早就对了）
f.calendar = calendar                       // ← 钉公历

// DF.cached（缺这一行）
let f = DateFormatter()
f.locale = Locale(identifier: locale)
f.dateFormat = format
f.timeZone = tz
// ← 没有 f.calendar
```

`DateFormatter` 不设 `calendar` 时用的是 `Calendar.current`。于是用户把系统历法切成
佛历 / 民国历 / 农历后：

| 工厂 | 输出年份（同一时刻） |
|---|---|
| `TimeFormat.dayKey` | **2026**（公历） |
| `DF.cached("yyyy-MM-dd")` | **2569**（佛历） |

**同一个时刻在两个地方显示不同年份。** 而这正是 `DateFormats.swift` 头注里说的
"语义与原来逐处新建完全一致"—— 逐处新建时**也**跟着系统历法，所以"一致"是成立的，
但**两边都错**（相对本仓"日期串一律公历"的规范）。

## 2. 为什么测试一直是绿的

`FormatterConsistencyTests` 里那三条（`testClockFormatAgrees` / `testDayKeyFormatAgrees` /
`testDayShortFormatAgrees`）都是在**当前历法**下比对两个工厂：

```swift
let viaTimeFormat = TimeFormat.dayKey(ms)
let viaDF = DF.cached("yyyy-MM-dd").string(from: ...)
XCTAssertEqual(viaTimeFormat, viaDF)
```

CI 机器是公历 ⇒ 两边都输出公历 ⇒ **永远相等**。
这个测试**结构上无法发现"两个工厂都不钉公历"**这种情况。

## 3. 修法

```swift
f.calendar = Calendar(identifier: .gregorian)
```

## 4. 补一条不依赖环境的测试

```swift
func testBothFormattersPinGregorian() {
    XCTAssertEqual(TimeFormat.calendar.identifier, .gregorian)
    XCTAssertEqual(DF.cached("yyyy-MM-dd").calendar.identifier, .gregorian,
                   "DF 也必须钉公历，否则用户切佛历后它输出 2569 而 TimeFormat 输出 2026")
    XCTAssertEqual(DF.stamp.calendar.identifier, .gregorian)
    // 证明"历法真的会影响输出"，而不是形式主义：
    let thai = Calendar(identifier: .buddhist)
    let yThai = thai.component(.year, from: ...)
    let yGreg = TimeFormat.calendar.component(.year, from: ...)
    XCTAssertNotEqual(yThai, yGreg, "佛历与公历的年份本就该不同")
}
```

**关键差别**：这条查的是 formatter **自身的 `calendar` 属性**，而不是"两个工厂的输出是否相等" ——
所以它在任何环境下都成立，不依赖 CI 机器恰好是公历。

## 5. 方法论

**"两个实现比对"型测试有一个结构性盲区：当两边都错得一样时，它永远通过。**

| 测试写法 | 能发现 |
|---|---|
| `assertEqual(A 的输出, B 的输出)` | A 与 B **不一致** |
| `assertEqual(A 的属性, 期望值)` | A **本身错了**（无论 B 如何） |

正确做法是**两者都要**：比对测试抓"漂移"，属性测试抓"共同的错"。
本轮补的正是后者 —— 而它立刻抓到了这个从 ROUND-1 起就存在的缺陷。
