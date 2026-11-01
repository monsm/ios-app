# AUDIT-ROUND-198 · 第 198 轮：把单飞改成**零并发告警**的写法

## 1. 为什么要改

`project.yml` 写得很清楚：

```yaml
SWIFT_VERSION: "5.0"
SWIFT_STRICT_CONCURRENCY: complete
SWIFT_TREAT_WARNINGS_AS_ERRORS: NO
```

并发问题在 Swift 5 模式下是**告警**，不会让构建失败 ——
**但 CI 的回执口径是 `warnings=0`**（每一轮 meta.txt 都记着 `warnings=…`）。

而我上一版写的是：

```swift
let task = Task { [self] in try await ensureConnectedInner(mac: m) }
```

`Task` 的闭包是 `@Sendable`，捕获 `LockService`（非 Sendable 类）⇒
`strict concurrency: complete` 下会报「capture of non-Sendable self」。
**构建能过，但会多一条告警** —— 等于把 `warnings=0` 的卫生记录弄脏。

## 2. 改成 continuation

```swift
if connectingMac == m {
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        connectWaiters.append(c)
    }
    return
}
…
private func settleConnecting(_ error: Error?) {
    connectingMac = ""
    let waiters = connectWaiters
    connectWaiters = []
    for w in waiters { if let error { w.resume(throwing: error) } else { w.resume() } }
}
```

| 方案 | 并发告警 | 说明 |
|---|---|---|
| 存 `Task { [self] … }` | **1 条** | 捕获非 Sendable self |
| **continuation** | **0** | 不跨 actor 传递，只是挂起/唤醒 |

## 3. 正确性没变

`LockService` 是 `@MainActor`：

| 步骤 | 是否可被打断 |
|---|---|
| `if connectingMac == m` → `connectWaiters.append(c)` | **否**（中间没有 await） |
| `connectingMac = m` | **否** |
| `settleConnecting` 清标记 + 唤醒全部 | **否** |

所以"检查 + 登记"仍是原子的，单飞的语义与上一版一致。

## 4. 方法论

**"能编译"和"没弄脏卫生线"是两件事。**

`SWIFT_TREAT_WARNINGS_AS_ERRORS: NO` 只保证构建不因告警失败 ——
但它**不保证告警不会增加**。而 `warnings=0` 这个记录本身就是资产：
一旦允许它变成 1，下一个人就会允许它变成 10。

判据：**改代码时，除了"能不能过"，还要问"会不会多一条告警"。**
