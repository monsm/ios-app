# AUDIT-ROUND-199 · 第 199 轮：开关「说谎」—— 写失败不弹回，以及又一次「文案猜颜色」

> CI：`b49eebd` 已验证绿（build_ok=1 warnings=0）；后续排队中。

## 1. 缺陷 A：写失败时开关停在「已开启」

`LockStatusScreen.PolicyToggle` 的同步逻辑：

```swift
@State private var localOn = false
.onChange(of: localOn) { _, new in if new != isOn { write(new) } }
.onChange(of: isOn) { _, new in localOn = new }
.onAppear { localOn = isOn }
```

`write` 失败时：`app.setSafeMode(on)` 返回 `.failure` ⇒ 只设 `outcome` 文案 ⇒
**`isOn`（来自锁端快照）不变** ⇒ `.onChange(of: isOn)` 不触发 ⇒ `localOn` 停在用户拨到的位置。

| 界面 | 锁端 |
|---|---|
| 开关「开 · 双验」+ 绿点 | 还是单验 |

**「操作了但失败」被显示成「操作且成功」，这比报错严重。**

### 修法：写入序列号

失败时 `isOn` 不变 ⇒ 不能靠它触发。给父视图加 `policyRev`，**每次写入结束（成功或失败）都 +1**；
`PolicyToggle` 多收一个 `revision`，变了就 `localOn = isOn` 重新对齐真实值。

## 2. 缺陷 B（同族老朋友）：`pendingLine` 又在猜文案

```swift
VStateDot(tone: outcome.contains("失败") || outcome.contains("错") ? .attention : .ok, word: outcome)
```

失败文案「锁忙，请稍后再试」**一个「失败/错」字都没有** ⇒ 绿点。
（这一族我已经修过两处：`CredentialStudioScreen` 的「已」前缀、`KeyCreateScreen` 的前缀猜测 ——
这是第三处，说明**这个模式在写 UI 的人手里是默认习惯**。）

### 修法：显式 `outcomeOK: Bool`，每个赋值点同步设置。

## 3. 过程：`callsig2` 又立功了

我先把 `revision` 加在 `write` **之后**声明，但调用点写成了 `…, revision:, write:` ——
闸门立刻红：

```
callsig2: FAIL — PolicyToggle 参数 "write:" 出现在已消费的参数之后
（声明顺序：isOn, onWord, offWord, write, revision）
```

（Swift 不强制调用点按声明顺序，但本仓为了 diff 可读性约定按序 —— 这条闸门就是干这个的。）

## 4. 方法论

**「乐观 UI」的完整闭环是：操作 → 乐观更新 → 结果回来 → *无论成败*都把 UI 对齐真实状态。**

| 环节 | 这里的实现 |
|---|---|
| 乐观更新 | ✅ `localOn` 立即变 |
| 成功对齐 | ✅ `.onChange(of: isOn)` |
| **失败对齐** | ❌ **原来没有**（`isOn` 不变，没有触发点） |

「失败对齐」是最容易漏的一环，因为它的触发条件**不是数据的成功路径** ——
必须自己造一个信号（本轮的 `policyRev`）。

**「文案猜颜色」出现第三次 ⇒ 该有一条闸门**：`tone:` 的实参里出现 `.contains(` 就是可疑形状。
（下轮把它写进 `swiftcheck`。）
