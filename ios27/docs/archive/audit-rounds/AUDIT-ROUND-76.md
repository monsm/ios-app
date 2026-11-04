# AUDIT-ROUND-76 · 第七十六轮：一个未来时间戳能让自动开锁永久失效

> CI：`2dae705` 已验证；`cdb0615` / `1452c0d` 待回执。本轮本地提交。

## 1. 缺陷

```swift
static let cooldownSeconds: Double = 6
static func coolReady(lastDispatch: Double, now: Double) -> Bool {
    lastDispatch == 0 || now - lastDispatch > cooldownSeconds
}
```

`lastDispatch` 被持久化（`kf_autoopen_lastdispatch_<mac>`）。若它的值**在未来**：

- `now - lastDispatch` 为负 ⇒ 永远不大于 6 ⇒ `coolReady` **恒 false**；
- 后果：这把锁的自动开锁**永久失效**，而界面上没有任何解释 ——
  用户只会觉得"自动开门坏了"，不会想到是冷却时间戳。

时间戳怎么会跑到未来？用户调过系统时间、或换机后从另一台设备带过来的值。

## 2. 修法

```swift
guard lastDispatch > 0 else { return true }
if lastDispatch > now + cooldownSeconds { return true }   // 明显超前 → 当它无效
return now - lastDispatch > cooldownSeconds
```

关键判断：**6 秒冷却只是节流，不是一个能长期生效的封禁**。
真正的"封禁"是 `isSuspended`（rc=26 防拆事件 → 24h fail-closed），那条有独立语义，不动它。

## 3. 同类：`isSuspended` 的方向相反（记入报告，不改）

```swift
static func isSuspended(mac: String, now: Double = ...) -> Bool {
    let t = suspendUntil(mac)
    return t > 0 && Double(t) / 1000.0 > now
}
```

它依赖**写入时算好的绝对时刻**（`now + 24h`）。若用户在挂起期内把系统时间调快，
封禁会**提前结束**（fail-open）—— 安全方向是错的。

但这需要产品决策（是否改用单调时钟 / 是否记录"已挂起"布尔），不是审计能顺手改的。
**已记入报告**，未动代码。

## 4. 新增测试（放在 ConcurrencyTests，因为它们是纯逻辑、毫秒级、锁住行为）

`testCooldownIgnoresFutureTimestamps`：0 / −3s / −7s / **+3600s** 四种输入。

## 5. 方法论

**"差值判断"在时间戳上是不安全的。** `now - t > k` 隐含假设 `t ≤ now`，
而这个假设在"持久化时间戳 + 用户可调时钟"的场景里不成立。

判据：**凡是用"当前时间 − 持久化时间戳"做判断的地方，都要单独处理 `t > now`**。
本仓还有几处时间戳比较（`kf_autocal_`、`kf_lock_cool`、`kf_care_notify_`），下一轮逐个查。
