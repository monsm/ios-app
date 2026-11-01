# AUDIT-ROUND-207 · 第 207 轮：**日志翻页方向反了**（三方对比第二个真 bug）

> CI：`ce73de4`（PIN 池对照）已验证绿。

## 1. vendor 的真实做法（`main.js` 的 `getLog`）

```js
this.logIdxNow = 4294967295;              // 起点 = 0xFFFFFFFF
this.getLog(0, this.logIdxNow);           // orderType=0
// 回调里：i = 页内**最后一条**的 idx
e.getSurplusLogs() > 0 && t.logCount < 100 && (
    t.logIdxNow = i - 1,                  // ← **递减**
    t.getLog(0, t.logIdxNow)
);
```

**从最新往回读，`startIdx = 末条 idx − 1`。**

## 2. 本仓原来怎么写

```swift
var startIdx: UInt32 = 0
…
if let last = page.logs.last { startIdx = last.idxRaw &+ 1 }   // ← **递增**
```

`orderType = 0` 的语义是"从 startIdx **往回**"，所以从 `0` 开始：

| 页 | startIdx | 锁返回 | 结果 |
|---|---|---|---|
| 1 | 0 | idx ≤ 0 的那一条 | 收到 1 条 |
| 2 | 0 + 1 = 1 | idx ≤ 1（含刚读过的那条） | **原地打转** |
| … | | | 20 页读完，全是前几条的重复 |

**表现：界面说"读取成功"，但记录页几乎空白。** 又一个"不报错、不崩、只是没有数据"的缺陷。

## 3. 证据链（三条独立证据都指向同一方向）

| # | 证据 |
|---|---|
| 1 | vendor `main.js`：起点 `0xFFFFFFFF`，逐页 `i - 1` |
| 2 | 本仓自己的金标 `GoldenDiffTests:87`：`startIdx: 0xFFFFFFFF` |
| 3 | `StatusParser.parseLogs` **保序**（不排序）⇒ 页内最后一条就是最小 idx，`−1` 才有意义 |

## 4. 修法

```swift
var startIdx: UInt32 = 0xFFFF_FFFF
…
// vendor 同款：surplus > 0 才继续（=0 表示到底）
if let s = page.surplus, s <= 0 { break }
if page.logs.count < 5 { break }
guard let last = page.logs.last, last.idxRaw > 0 else { break }   // 防 0 下溢
startIdx = last.idxRaw - 1
```

`remaining`（第 183 轮那个"锁端还有 N 条"）语义不变：只有**读满 20 页**才可能是被截断。

## 5. 方法论

**三方对比的价值在第二次兑现**：第 203 轮排除了"协议写错"，本轮却靠 vendor 的**循环语句**
找到了一个纯逻辑错误 —— 它不在帧字节里，而在**翻页的方向**上。

| 对比层 | 能发现 |
|---|---|
| 字节层（信封/AES/成帧） | 编码错 |
| **控制流层（循环、方向、终止条件）** | **翻页方向、终止条件、重试策略** |

字节对比做完了不等于对比做完了 —— **控制流才是"逻辑"两个字的本体**。
