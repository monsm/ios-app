# AUDIT-ROUND-188 · 第 188 轮：密码闸承诺「输对一次后 30 秒内不再问」—— 但从来没实现

> CI：`f08d7db` 已验证绿；`c0b755a` / `c76a802` 待回执。

## 1. 缺陷

`UnlockGateScreen` 的说明卡片原文：

> 为什么再要一次密码：手机刚开过门，30 秒内被人拿走时，这一道闸让 TA 不能直接再开。
> **输对一次后 30 秒内不再重复询问。**

而 `DoorScreen.needsGate` 是：

```swift
guard DB.hasPasscode(), let last = app.lastUnlockSuccessAt else { return false }
return Date().timeIntervalSince1970 * 1000 - Double(last) < 30_000
```

**只**看 `lastUnlockSuccessAt`，而它在**每次成功开锁后都会刷新**（`runUnlockChain` 里 `lastUnlockSuccessAt = now`）。

于是：

| 时刻 | `lastUnlockSuccessAt` | `needsGate` |
|---|---|---|
| 输对密码、开锁成功 | 刚刷新 | **true**（又落回 30 秒窗口） |
| 5 秒后再开 | 还是刚才 | **true** |
| 再输对、再开 | 又刷新 | **true** |

**连续开门会一直弹密码** —— 而说明文案承诺的"宽限"一个字都没实现。

## 2. 修法

新增「刚通过闸门」的时刻，给一个真正的宽限窗：

```swift
// AppModel
var gatePassedAt: Int64?

// UnlockGateScreen.verify() 成功分支
app.gatePassedAt = Int64(Date().timeIntervalSince1970 * 1000)

// DoorScreen.needsGate
if let passed = app.gatePassedAt, now - Double(passed) < 30_000 { return false }
return now - Double(last) < 30_000
```

这样两个语义才分得开：

| 场景 | 行为 |
|---|---|
| 开门后 30 秒内、**没输过密码** | 要密码（防手机被捡走） |
| **输对一次密码后**的 30 秒内 | **免问**（兑现说明） |

## 3. 本轮另外 5 项「审过、判定正确」

| 疑点 | 结论 |
|---|---|
| `firedThisTouch` 失败后不复位 ⇒ 第二次点没反应 | ✅ 新按下时 `firedThisTouch = false`，`resetGesture()` 复位 `pressing` —— 闩锁正确 |
| `Dest` 每项是否有视图 | ✅ 穷尽 `switch`（编译器 + `destmap.js` 闸门双保险） |
| `LockGuard.masked` 的 `count: n - keep` 会不会为负 | ✅ `n >= 3` 且 `keep = (n+1)/2 ≤ n` 恒成立 |
| `KeyGen.randomBytes(_:)` 的 `count: n` | ✅ `guard n > 0` 在前 |
| `* 100 / total` 类百分比除零 | **0 处**（除零候选全有 `max(..., 1)` 或 `guard`） |

## 4. 方法论

**"界面承诺"和"代码判据"要对得上 —— 而这类不一致只会在**连续使用**时暴露。**

单次使用永远看不出这个 bug：开门 → 弹密码 → 输对 → 开门，一路正常。
只有**连开两次**才会发现"怎么又要密码"。

判据：**凡是文案里写了"X 之后 Y 秒内不再…""每 N 次…""最多 M 天…"，
就去把那个数字在代码里找出来，确认它判的是同一件事。**
本轮这个数字（30 秒）在代码里存在，但**判的对象错了**（判的是"上次开锁"，不是"上次通过闸门"）。
