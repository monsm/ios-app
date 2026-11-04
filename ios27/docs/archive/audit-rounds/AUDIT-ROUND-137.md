# AUDIT-ROUND-137 · 第一百三十七轮：同族里又两处缺「未来时间戳」保护

> CI：`350341c` 已验证绿；`ddad1bc` / `d694a4d` / `216c46c` 待回执。本轮本地提交。

## 1. 起点：`LockStats` 里同族两个函数，只有一个有保护

```swift
// touchConnected —— 有保护
if TimeFormat.timestampIsPlausible(m.lastConnectedAt, now: now), now - m.lastConnectedAt < 300 { return }

// isSleeping —— 没有
return Date().timeIntervalSince1970 - t > 30 * 86400
```

若 `lastConnectedAt` 落在**未来**（用户调过系统时间 / 换机带来别的设备的时钟），
`now - t` 为负 ⇒ **永不沉睡**。

方向是 fail-open（只是少标一次「沉睡」，不涉及安全），**但同族两处口径不一致本身就是缺陷** ——
下一处改动很容易把这条当成"已处理"而跳过（这正是本段反复踩的坑）。

## 2. 顺着这条线又找到一处：`QuickPool.reached30d`

```swift
static var reached30d: Bool {
    guard let since = DB.store.get(Double.self, sinceKey) else { return false }
    return Date().timeIntervalSince1970 - since >= 30 * 86400    // ← 同形态
}
```

`since` 在未来 ⇒ `now - since` 为负 ⇒ **恒 false** ⇒「智能排序」永远攒不够 30 天、永不启用。

## 3. 修法（两处都加同一个守卫）

```swift
guard TimeFormat.timestampIsPlausible(t, now: now) else { return false }
```

即"不可信的未来值 ⇒ 按刚发生处理"。这与 `touchConnected` 的取舍一致。

## 4. 逐个判掉的三处（不改）

| 位置 | 为什么不用改 |
|---|---|
| `AutoOpenKit.audit:62` | 内存节流表（进程重启即清），未来值只让节流多生效 10 秒，无害 |
| `SyncTimeScreen.drift:73` | **负值是合法信息**（锁钟比手机慢），显示侧已用 `abs(drift)` 正确处理 |
| `AppLock:165` | `backgroundedAt` 是进程内记录的，不来自 UserDefaults |

## 5. 方法论

**「同族里只有一处漏了」是本段最高产的线索** —— 这已经是第 N 次：

| 轮次 | 同族 | 漏的那一处 |
|---|---|---|
| 30 | 三个单条读取器 | `member(id)` 缺过滤 |
| 47 | 三族钥匙串副本 | 删设备漏清 |
| 76/77 | 两处 `now - t` | `coolReady` / `touchConnection` |
| 81 | 三处 `keepingAwake` | `KeyDetailScreen` |
| **137** | **两处 30 天窗口** | **`isSleeping` / `reached30d`** |

判据：**找到一个"有保护"的实现后，立刻 grep 它的同族（同一个常量、同一种比较），逐个看有没有保护**。

`TimeFormat.timestampIsPlausible` 的文档注释里其实已经列了两个调用点（`coolReady` / `touchConnection`）——
但那只是"已知用过的地方"，不是"所有该用的地方"。**注释不会自己更新**。
