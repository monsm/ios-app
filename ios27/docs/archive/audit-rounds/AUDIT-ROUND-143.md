# AUDIT-ROUND-143 · 第一百四十三轮：同族三处缓存，只有一处正确回填

> CI：`485ee7b` 已验证绿；`fdaa7f7` / `3fa85c1` 待回执。本轮本地提交。

## 1. 缺陷：`DiagKit` 三个缓存，两个读路径不回填

```swift
// entryCache —— 正确（先回填再返回）
private static func loadIntoCache() -> [DiagLogEntry] {
    if let c = entryCache.withLock({ $0 }) { return c }
    let loaded = DiagLogStore.load()
    entryCache.withLock { $0 = loaded }      // ← 回填
    return loaded
}

// eventCache / attemptCache —— 不回填
static var events: [BleEvent] { eventCache.withLock { $0 } ?? loadEvents() }
static var attempts: [ConnAttempt] { attemptCache.withLock { $0 } ?? loadAttempts() }
```

两个后果：

| 后果 | 说明 |
|---|---|
| **性能** | 缓存为 nil 时**每次读都重新解析 JSON 文件**（这几处正是"诊断日志防抖"想避免的） |
| **一致性** | 写路径是"读缓存→改→写回"，读路径永远看磁盘 ⇒ 两者会短暂不一致 |

第二条更隐蔽：`recordEvent` 与 `events` 在同一个进程里可能看到不同的列表。

## 2. 修法

照 `entryCache` 的形状改：

```swift
static var events: [BleEvent] {
    if let c = eventCache.withLock({ $0 }) { return c }
    let loaded = loadEvents()
    eventCache.withLock { $0 = loaded }
    return loaded
}
```

`attempts` 同。

## 3. 这是方法论 §1.1 的又一实例

**"同族里只有一处做对了"** —— `entryCache` 写对了，`eventCache` / `attemptCache` 没写对。
如果只看后两个，会觉得"这个模式本来就这样"；
正是**先看到 `loadIntoCache` 这个正确实现**，才能判断另外两个是漏的。

本段这条判据的战绩（`AUDIT-METHOD.md §1.1`）：

| 轮次 | 同族 | 漏的那一处 |
|---|---|---|
| 30 / 47 / 76 / 77 / 81 / 118 / 126 / 137 | … | … |
| **143** | **三个诊断缓存** | **`events` / `attempts`** |

## 4. 方法论补充

**扫描"同族"时，不要只搜名字相同的符号，要搜"同一种模式"。**

我这轮的入口是 `grep "Locked("`（模式），而不是 `grep "Cache"`（名字）——
因为 `eventCache` 与 `entryCache` 名字不同，但模式相同。

| 搜什么 | 能找到 |
|---|---|
| 符号名 | 同名的实现 |
| **模式（`Locked(...)` / `if let c = ... { return c }`）** | **同模式的实现** |

## 5. 顺带核对（无缺陷）

其余 9 个 `Locked` 静态量（`registeredLock` / `ledgerWriteLock` / `keychainWriteLock` /
`ledgerLock` / `macOrdersLock` / `mergedLock` / `lowCacheLock`（已在上轮修））都不是"缓存派生值"，
而是锁/标记/写序号，不存在失效问题。
