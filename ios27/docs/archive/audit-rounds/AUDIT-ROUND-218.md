# AUDIT-ROUND-218 · 第 218 轮：手机钥匙的两处缺口（PIN 池泄漏 + 安全提示从没显示）

> CI：`df32217` 已验证绿；`9aee6fa` 排队中。

## 1. 缺陷 A：过期钥匙永久占用 PIN ⇒ 64 枚发完就再也发不出

```swift
static func availablePin(_ kc: Keychain, used: [MobileKey]) -> String? {
    let taken = Set(used.map { $0.pin })      // ← 含早已过期的
    for p in kc.pins where !p.isEmpty && !taken.contains(p) { return p }
    return nil
}
```

| 场景 | 原行为 |
|---|---|
| 签发 64 把（多数早已过期、但没手动撤销） | **「PIN 池已用尽」—— 永远发不出新的** |

而一把过期钥匙的 ekey 已过 `validTo`，锁端根本不会再认 —— 那枚 PIN 完全可以回收。

### 修法

优先未占用的；**池子用尽时**才回收「已过期」那批里最早到期的一枚：

```swift
let reusable = used.filter { !$0.pin.isEmpty }
    .filter { (ZKCmdBuilder.protoSecOrNil($0.validTo) ?? Int64.max) < now }
    .sorted { $0.validTo < $1.validTo }
return reusable.first?.pin
```

安全性：永久档 `validTo` 是 2118（解析出来远大于 now）⇒ 不会被回收；解析不出的按「未过期」处理。

## 2. 缺陷 B：foreignKeyHint 写好了却**从没被调用过**

它算的是：

> 「锁端显示已绑定 N 个 PIN，本机只记录了 M 个 —— 差额可能是**别人发的手机钥匙**，删除前请先确认归属。」

全仓 grep：**只有定义处，零调用**。而这条提示是**删除钥匙前最该看到的一句话** —— 删错别人的钥匙 = 让别人进不了门。

### 修法

接到手机钥匙页顶部（拿不到锁状态时返回 nil，不给无依据的断言）：

```swift
private var foreignHint: String? {
    guard let kc = app.currentKeychain else { return nil }
    return MobileKeyService.foreignKeyHint(pinInfoBinding: app.lastStatus?.status.pinInfoBinding ?? 0, kc: kc)
}
```

顺带纠正我上一轮的一个说法：`pinInfoBinding` 并非「解析了完全没用」—— 它有一个消费者 `foreignKeyHint`，只是**那个消费者自己没被接线**。链路断在最后一环，而不是第一环。

## 3. 方法论

**「零调用」有两种，危害完全不同：**

| 形态 | 危害 |
|---|---|
| 工具函数零调用 | 只是死代码 |
| **安全提示零调用** | **该看到的警告永远看不到** —— 用户在最需要它的时刻（删钥匙）毫无提示 |

判据：**排查零调用时，先看它「产出的是一句话还是一个值」。产出一句话的，几乎都该接上。**
