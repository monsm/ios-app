# AUDIT-ROUND-140 · 第一百四十轮：冷启动点通知，动作被静默丢弃

> CI：`76a01b7` 已验证绿；`338ce0d` / `5695cc9` 待回执。本轮本地提交。

## 1. 缺陷：宿主未就绪时，点通知的动作丢了

```swift
if let action = CredentialOrg.handleNotificationAction(id) {
    Task { @MainActor in
        guard let host = EngineHostRegistry.host else { return }   // ← 静默丢弃
        CredentialOrg.applyNotification(action, host: host)
    }
}
```

`EngineHostRegistry.current` 是 `weak var`，只在 `RootView.onAppear` 里注册。
而**冷启动点通知**的时序是：

```
系统启动 App → didReceive 回调（host == nil）→ … → RootView.onAppear（host 才注册）
```

于是用户点了「密码临期」通知：**App 打开了，但没跳到那条凭证**，且没有任何提示。

## 2. 修法：排一个 pending 队列

```swift
private static var pending: [@MainActor (any EngineHost) -> Void] = []

static func register(_ host: any EngineHost) {
    current = host
    let queued = pending; pending = []
    for run in queued { run(host) }     // 注册时立刻消费
}

static func whenReady(_ run: @escaping @MainActor (any EngineHost) -> Void) {
    if let host = current { run(host) } else { pending.append(run) }
}
```

`QuickActions` 改用 `whenReady`。

## 3. 为什么 `weak var` 本身不是缺陷

我一开始怀疑 `weak` 会让宿主被释放后静默失效。核对后：

| 检查点 | 结论 |
|---|---|
| 宿主是谁 | `AppModel`，由 `RootView` 的 `@State` 持有 |
| 注册时机 | `.onAppear`（与 RootView 生命周期一致） |
| 会不会被释放 | 不会（只要 RootView 在） |

`weak` 是**正确选择**（避免注册表持有宿主形成循环）。真正的缺陷是"注册**之前**就来的动作没人接"。

## 4. 逐个判掉的两处（不改，并注明理由）

| 位置 | 为什么不用 `whenReady` |
|---|---|
| `AutoOpenKit:311`（轮询读 RSSI） | 要的是"**此刻**"的锁与连接；排队后执行会用一个过期的宿主 |
| `AutoOpenKit:378`（开门尝试） | 同上 —— 自动开锁是实时决策，延迟执行比不执行更危险 |

这两处 `guard ... else { return }` 是**正确的**：过期动作不该执行。

## 5. 方法论

**"宿主未就绪"这个窗口，要区分"可以延后"与"必须此刻"。**

| 动作类型 | 未就绪时该怎么办 |
|---|---|
| 用户明确的意图（点通知、深链） | **排队**（用户已经表达了意图，延后执行是对的） |
| 实时状态决策（自动开锁） | **丢弃**（延后执行会基于过期状态做判断） |

判据：**问一句"这个动作延后 2 秒执行，结果还对吗"** —— 对就排队，不对就丢弃。

## 6. 顺带核对（无缺陷）

`EngineHost` 协议本身（35 行）很干净：只声明引擎真正用到的 4 个能力，
注释里写明"上一版把 40KB 的 AppState 传进 Engine，导致引擎离不开界面层" ——
这是本仓分层纪律的由来。
