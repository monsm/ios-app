# AUDIT-ROUND-184 · 第 184 轮：**校时后显示「回读偏差 531260264 秒」**（用户实测报告）

> 用户反馈：写锁同步时间后，偏差显示 **531260264 秒**。
> 这个数字是决定性的线索 —— 531260264 秒 ≈ **16.8 年**，
> 而 2010-01-01 到 2026-11-01 正好是 **1,262,304,000 秒** 量级。

## 1. 根因：把「偏差」当成了「绝对时间戳」

`AppModel.syncTime()` 返回的是 `(before, after)`，两者都是**偏差（秒）**：

```swift
// LockServiceOps.syncTime
var before = 0
if let lockSec = try? await readLockTime() {
    before = Int(lockSec - now)                    // ← 差值
}
...
if let lockSec = try? await readLockTime() {
    after = Int(lockSec - ZKProtocol.nowProtoSeconds())   // ← 差值，同步成功时 ≈ 0
}
```

而 `SyncTimeScreen.sync()` 把 `pair.1`（= after）**当成协议秒**去换算：

```swift
// 旧（错）
lockAt = Int64((ZKProtocol.protoSecondsToUnix(Int64(pair.1)) * 1000).rounded())
```

`protoSecondsToUnix(sec) = sec + 1_262_304_000`（2010-01-01 基准）。于是：

| 步骤 | 值 |
|---|---|
| 同步成功，`after ≈ 0` | `0` |
| 被当成协议秒换算 | `protoSecondsToUnix(0)` = **1_262_304_000** |
| 转成毫秒当"锁内时间" | `1_262_304_000_000` ms（= 2010-01-01） |
| `residual = (现在 − lockAt)/1000` | `(1.793e12 − 1.2623e12)/1000` ≈ **5.31 亿** |

**与用户报的 531260264 完全对上**（差额来自锁钟当时真实的几千秒偏差）。

## 2. 修法

```swift
// 新
let drift = pair.1                       // 锁 − 手机（秒），≈0 表示对准了
lockAt = now + Int64(drift) * 1000        // 锁内时间 ≈ 手机现在 + 偏差
...
let residual = -drift                     // 页面「偏差」面板算的是「手机 − 锁」，取反与它同号
result = SyncOutcome(ok: abs(residual) <= Self.driftThreshold,
                     text: "同步完成 · 回读偏差 \(residual) 秒")
```

## 3. 为什么 `read()` 那处是对的、只有 `sync()` 错

同一个文件里两处都在用 `protoSecondsToUnix`，但语义不同：

| 位置 | 数据来源 | 是不是绝对时间戳 | 用法 |
|---|---|---|---|
| `read()`（214 行） | `app.lastStatus?.status.lockTime`（cmd03 的 KLV#04） | ✅ **是**（锁钟绝对协议秒） | ✅ 正确 |
| `sync()`（242 行，旧） | `pair.1`（cmd0E 的回读**差值**） | ❌ **不是** | ❌ 错 |

**同一个换算函数，喂进两种语义的数据，只有一种是合法的。**

## 4. 符号也顺手对齐了

页面「偏差」读数算的是 `(now − lockAt)` = **手机 − 锁**（正 = 手机快）；
而 `pair.1` 是 **锁 − 手机**。若直接用它显示，同一页会出现「偏差 +5」与「回读偏差 −5」。
所以取反后再显示。

## 5. 方法论

**"数字大得离谱"时，先算它等于什么 —— 异常值本身就是最精确的线索。**

`531260264` 秒不是一个随机的大数：除以 86400 得 6148 天 ≈ 16.8 年，
而本仓的协议秒基准正好是 2010-01-01 —— 于是"基准 epoch 被当成差值"这个假设直接命中。

| 症状 | 最可能的根因 |
|---|---|
| 差 **几十年** | epoch 基准混用（2010 vs 1970） |
| 差 **1000 倍** | 秒/毫秒混用 |
| 差 **8 小时** | UTC / 本地时区 |
| **恰好是某个常数** | **把常量当成了变量** |

另一条：**同名函数喂不同语义的数据**是这类 bug 的温床。
`protoSecondsToUnix` 只接受"绝对协议秒"，但签名上看不出来 ——
如果类型能区分（例如 `ProtoInstant` vs `ProtoDelta`），这个 bug 在编译期就没了。
