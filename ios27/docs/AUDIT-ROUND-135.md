# AUDIT-ROUND-135 · 第一百三十五轮：「23–24 点」—— 一个不存在的小时

> CI：`78d2e0d` 已验证绿；`8335306` / `350341c` / `ddad1bc` 待回执。本轮本地提交。

## 1. 缺陷：`peak + 1` 在 23 点时会输出「24 点」

```swift
return "\(name) 近 7 天开门约 \(mine.count) 次，工作日 \(peak)–\(peak + 1) 点最活跃。"
```

若某成员开门最集中在 **23 点**，这句话会写成：

> 「…工作日 **23–24 点**最活跃。」

**24 点不存在** —— 一天只有 0–23 点。用户看到会以为 App 算错了，
或以为「24 点」是某种特殊时段。

## 2. 同一个缺陷在两处（Engine 与界面域各一份）

| 位置 | 域 |
|---|---|
| `HouseholdRoster.weekSentence`（`HHStats`） | 界面域 |
| `MemberHub.weekSentence` | Engine 域 |

两处注释都写着"同口径"，而**两处都错了同一个地方**。

## 3. 修法

界面域加一个共用函数：

```swift
static func hourSpan(_ hour: Int) -> String {
    let next = (hour + 1) % 24
    return next == 0 ? "\(hour)–次日 0 点" : "\(hour)–\(next) 点"
}
```

Engine 域（`MemberHub`）内联同逻辑，并注明**为什么不复用**：

> 与 `HHStats.hourSpan` 同口径（那一个是界面域的，Engine 不反向依赖界面域，故内联）。

（这是本仓的分层纪律：Engine 不依赖 Features。）

## 4. 方法论

**"差一"型缺陷在时间与区间上最密集，而它们的共同特征是"边界值不存在"。**

本段已修过的同类：

| 轮次 | 缺陷 | 边界 |
|---|---|---|
| 40 | 回收站上限丢错端 | `suffix(from: n)` 越界即崩 |
| 117 | 跨年组头只显示月日 | 年份边界 |
| **135** | **「23–24 点」** | **小时上界** |

判据：**凡是"X 到 X+1"的显示，问一句"X 取最大值时，X+1 还合法吗"**。
小时的最大值是 23，它的 +1 是 24 —— 不合法。

## 5. 顺带

`HHMemberStatus` 的四分支派生 `HHStats.status` 核对正确（`archived` → `.archived`；
无 `lastActiveAt` → `.never`；超 30 天 → `.stale`；否则 `.active`），与上轮修的显示侧一致。
