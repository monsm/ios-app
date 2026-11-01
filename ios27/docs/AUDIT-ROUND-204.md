# AUDIT-ROUND-204 · 第 204 轮：接上 `keyboardFreeze` —— 别再把整池 PIN 刷进冻结的锁

> 承接第 203 轮：cmd03 的 KLV#06/#07（freeze / errCount）**解析了但零消费**。

## 1. 为什么这条必须接

上一版「凭证回落 = 逐枚 PIN 试」没有上限 —— 用户日志显示一次点击连发 **42+ 条 cmd04 全部 rc=2**。
而锁端有键盘冻结机制：**每一条失败的 PIN 都在加深锁端计数**，冻结后键盘开锁也不可用。
本机当时完全看不到这一切 —— 因为 freeze/errCount 没有任何消费者。

## 2. 修法

```swift
var maxPinRetries = kc.pins.count
if let st = try? await getStatus(), st.keyboardFreeze > 0 {
    throw BLEErrorX.msg("锁端键盘已冻结（试错过多），约 \(st.keyboardFreeze) 秒后再试")
} else if let st = try? await getStatus(), st.keyboardErrCount > 0 {
    maxPinRetries = min(maxPinRetries, 3)   // 已有试错记录 ⇒ 收窄额度
}
```

两条：冻结 ⇒ **一条都不发**（发了必败，还会让冻结更久）；有试错记录 ⇒ 额度收到 3。

顺带：调用点加了 `idx < maxPinRetries` 上限。

## 3. 过程：`callsig2` 拦了我两次

第一次我调了不存在的 `readStatus()`（那是 `StoreState` 的**本地缓存**读取，不是真链路）——
闸门立刻红：「readStatus 缺参数 _」。
换成真正的 `getStatus()`（cmd03 真链路）后通过。

**本地缓存 ≠ 真实状态**：冻结计数必须问锁本身，不能问本机 30 秒前的快照。
这个错如果过了本地闸门，会表现为"永远读到的都是旧计数" —— 又一个难查的静默错。

## 4. 方法论

**「有采集无消费」的补法有两种：接到 UI，或接到决策。** 这里接的是决策（要不要发、发多少）。

| 接法 | 价值 |
|---|---|
| 接到 UI（显示冻结秒数） | 用户知情 |
| **接到决策（不发/少发）** | **直接改变行为，防止伤害** |

本轮两者都做了：不发冻结锁 + 收窄额度；UI 的暴露（锁档案页显示试错计数）留给下一轮。
