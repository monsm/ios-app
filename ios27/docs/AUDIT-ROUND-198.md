# AUDIT-ROUND-198 · 第 198 轮：单飞改成 continuation（并纠正上一版的判断）

## 1. 先纠错

我在改这版时的理由是"`Task { [self] }` 会产生并发告警"，**这个判断是错的**。

`b49eebd`（就是 Task 版本）的 CI 回执：

```
build_ok=1  archive_ok=1  errors=0  warnings=0
```

**`warnings=0`** —— 那句 `Task { [self] … }` **没有**产生并发告警。
原因大概是 `LockService` 已经是 `@MainActor`，而 `Task { }` 在 MainActor 上下文里继承隔离，
捕获 self 不构成跨 actor 传递，所以 `strict concurrency: complete` 也不报。

我把"理论上可能报"当成了"一定会报"。**这是推测当证据。**

## 2. 那为什么保留 continuation 版本

既然 Task 版本是绿的，continuation 版本不是"修复"，是**等价但更显式**的写法：

| 维度 | `Task { [self] }` | continuation |
|---|---|---|
| 语义 | 后来者 `await` 同一个 Task | 后来者挂在 `connectWaiters` 上被唤醒 |
| 中断安全 | 靠 MainActor 保证 | 靠 MainActor 保证（同样无 await 间隙） |
| 额外对象 | 每次连接建一个 `Task` | 无 |
| 可读性 | 藏一层 | 显式：谁在等、什么时候唤醒 |

两者都正确。保留 continuation 的理由只是**没有额外对象、边界更清楚**，
而不是"Task 版本有问题"。

## 3. 代码

```swift
if connectingMac == m {
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        connectWaiters.append(c)
    }
    return
}
connectingMac = m
…
private func settleConnecting(_ error: Error?) {
    connectingMac = ""
    let waiters = connectWaiters
    connectWaiters = []
    for w in waiters { if let error { w.resume(throwing: error) } else { w.resume() } }
}
```

`LockService` 是 `@MainActor`，所以「检查 + 登记」与「清标记 + 唤醒」都不会被打断，单飞语义成立。

## 4. 方法论

**「可能」不是「会」—— 而我这次把"可能"写成了"会"。**

| 我说的 | 实际 |
|---|---|
| "`Task { [self] }` 在 strict concurrency 下会报告警" | CI 回执 `warnings=0`，没报 |

正确的做法是：**改之前就说"不确定，等回执"；改之后如果回执证明我错了，把错的那句改掉**
—— 而不是让"听起来很合理的推断"留在文档里变成下一个人的依据。

这条比代码本身重要。
