# AUDIT-ROUND-136 · 第一百三十六轮：低电缓存从不作废

> CI：`350341c` 已验证绿；`ddad1bc` / `d694a4d` 待回执。本轮本地提交。

## 1. 缺陷：`appLowBattery` 的缓存没有失效路径

```swift
private static let lowCacheLock = Locked((mac: "", low: false))

static var appLowBattery: Bool {
    let mac = DB.preferredMac()
    let cached = lowCacheLock.withLock { $0 }
    if cached.mac == mac { return cached.low }   // ← 命中就直接返回
    ...
    lowCacheLock.withLock { $0 = (mac, low) }    // ← 只有这里写
}
```

这个值驱动 **全 App 的动效档位**（≤20% 时把动效压到 `calm`）。
而缓存的**唯一写入点是这个函数自己** —— `sample()` 记了新电量之后**不作废它**。

于是：

| 时刻 | 电量 | 缓存 | `appLowBattery` |
|---|---|---|---|
| T1 | 15% | `(mac, true)` | `true`（动效降级） |
| T2（充上电后） | **80%** | 仍是 `(mac, true)` | **仍是 `true`** |
| T3（换锁再换回） | 80% | 缓存 miss | 才恢复 `false` |

用户看到的是：**电量早就上来了，界面还是一副"低电"的克制样子**，
直到某个不相关的原因让缓存 miss。

## 2. 修法

`sample()` 记完新点就作废缓存：

```swift
lowCacheLock.withLock { $0 = ("", false) }
```

（用 `mac == ""` 表示"无缓存"，与该结构体原有的空值约定一致 —— 注释里写着
"空值由 `mac == ""` 表示"。）

## 3. 为什么这类缺陷难发现

**它不违反任何"形状"规则**：缓存读写都在一个函数里、类型正确、并发安全（`Locked`）。
缺陷在于**生命周期**：一个派生值缓存了，而它的**输入**变了却没通知它。

闸门与编译器都看不到这个层次。

## 4. 方法论

**凡是"缓存一个派生值"，都要同时写下"什么时候作废"。**

| 缓存形态 | 失效方式 |
|---|---|
| 按 key 缓存（`mac` / `id`） | key 变了自然 miss —— **但只要 key 不变就永远不失效** |
| 按时间缓存 | TTL |
| **本轮这种** | **没有失效路径 ⇒ 缺陷** |

判据：**看到一个 `if cached.x == x { return cached.y }`，就问"x 不变时 y 会变吗"**。
会变，就必须有作废点。

## 5. 顺带核对（都正确）

| 检查点 | 结论 |
|---|---|
| `tier(_:)` 的 `case ..<0` 分支是否可达 | **可达** —— `displayPct` 在采样与快照都缺时返回 `-1` |
| 五档区间是否连续无洞 | ✅ `..<0` / `0...10` / `11...20` / `21...35` / `36...60` / `61...80` / `default` |
| `sample()` 的 720 条上限 | ✅ ROUND-85 已修（保留最新） |
| 头注的 `kf_mevents_` / `kf_maint_` | ✅ 头注已自我更正为"未实现"（不是既有能力） |
