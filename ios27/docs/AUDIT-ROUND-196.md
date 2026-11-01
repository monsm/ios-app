# AUDIT-ROUND-196 · 第 196 轮：`rc=22` 被当成「开锁成功」—— 而 vendor 文案是「不能重复验证」

> CI：`6b46374` 已验证绿；`940f4fa` / `43397b1` 待回执。

## 1. 缺陷

```swift
// AppModel.runUnlockChain（旧）
if rc == 0 || rc == 22 {
    dialPhase = .opened            // ← 显示「已开锁」
    lastUnlockSuccessAt = now      // ← 记成功
    Milestones.recordUnlockSuccess()
    startAutoLockCountdown()       // ← 开始自动上锁倒计时
    return
}
```

而 `StatusParser.rcMsg` 里：

```swift
22: "不能重复验证",
```

那张表的注释是：

> rc → 人话。**这张表要与 vendor `status.js` 逐字一致**（`tools/parseshadow.js` 会对拍），
> 改文案会让闸门红 —— 想补提示请用 `rcHint(rc:)`。

也就是说：**vendor 自己的定义是「不能重复验证」**，Android 侧也是把它当错误文案弹给用户的。
代码里 `// 0 成功; 22 双验继续` 这个说法**没有任何出处**。

## 2. 后果

若 22 实际含义是「还需要第二种验证方式」（B 模式双验）或「本次验证被拒」：

| 界面 | 真实情况 |
|---|---|
| 圆盘显示**已开锁** | 门没开 |
| 记 `lastUnlockSuccessAt` | 后续 30 秒免密窗被错误打开 |
| 起**自动上锁倒计时** | 对一扇没开的门开始计时 |
| 记里程碑 / 清 `failStreak` | 失败被记成成功 |

**"把失败显示成成功"比"显示失败"严重得多** —— 用户会以为门开了。

## 3. 修法

```swift
if rc == 0 { …真正的成功路径… }
if rc == 22 {
    nonRetryable = true
    throw BLEErrorX.msg("门锁要求第二种验证方式（B 模式双验）—— 请再用指纹或密码验证一次")
}
```

`LockServiceOps.unlock` 的早退也同步收窄成 `if r.rc == 0`，注释写明 22 的口径来源。

**不记成功、不起倒计时、如实提示。**

## 4. 这条需要真机再确认一次

B 模式（双验）是**可选档**（`SafeModeScreen` 里切换），默认是 A 单验。
所以绝大多数用户不会遇到 22。

但如果真机确认 22 确实是"门已开、只是要求补一次验证"，那这条要改回去 ——
**现在的改法是"不把不确定当成功"**，方向上比原来安全。

## 5. 顺带核对：`pinToLEOrNil` 与 `cmd08` 的 PIN 编码一致

| 环节 | 编码 |
|---|---|
| `KeyGen.genPin()` | 8 位 hex（4 字节，生成时已按 LE 反序） |
| `cmd08SyncPinsBatch` | `addPins.joined()` —— **原样写字面 hex** |
| `pinToLEOrNil`（ekey 用） | 8 位且全 hex ⇒ **原样返回** |

三处逐字节一致 ✅ —— 所以「写入的 PIN」与「ekey 里的 PIN」不会因编码不同而不匹配。
这排除了"编码不一致导致 rc=2"这个可能，把 `rc=2` 的嫌疑集中到"锁里确实没有这枚 PIN"。

## 6. 方法论

**"我们自己的注释"不是证据 —— 要追到 vendor 的定义。**

`// 0 成功; 22 双验继续` 这条注释看着很确定，但它**没有任何出处**；
而同一仓的 `rcMsg` 表为了与 vendor 对拍，把 22 定义成「不能重复验证」。

| 证据强度 | 例子 |
|---|---|
| 最强 | 与 vendor 逐字对拍的表（`rcMsg`）、金标字节 |
| 中 | 注释里写了出处的说明 |
| **最弱** | **没有出处的注释**（本轮这条） |

判据：**当一个"特判"（`|| rc == 22`）找不到出处时，它就是可疑的。**
