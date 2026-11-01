# AUDIT-ROUND-77 · 第七十七轮：把「时间戳可信」做成唯一判据，并用在第二处

> CI：`1452c0d` 已验证；`9ffbc1a` / `d252700` 刚推送。本轮本地提交。

## 1. 按上轮末的判据扫全部「现在 − 持久化时间戳」判断点

扫出 6 处，逐一判方向：

| 位置 | 表达式 | 未来时间戳的后果 | 处置 |
|---|---|---|---|
| `AutoOpenKit.coolReady` | `now - last > 6` | 冷却**永久生效** ⇒ 自动开锁无声失效 | 上轮已修 |
| **`LockStats.touchConnection`** | `now - last < 300` | **恒真 ⇒ 该字段再也不更新** | **本轮修** |
| `LockStats.isSleeping` | `now - t > 30d` | 恒假 ⇒ 视为最近活跃（偏保守，无害） | 不动 |
| `QuickPool.reached30d` | `now - since >= 30d` | 恒假 ⇒ 视为"还没满 30 天" | 不动 |
| `AutoOpenKit.audit` | `now - t < 10` | 只是内存态节流，重启即失效 | 不动 |
| `CredentialOrg.recentUseCount` | `t >= now - N*86400` | 未来值会让它被计入（统计偏大） | 保留未接函数，不动 |

**`touchConnection` 是第二个真问题**：它写的是"最近连接时间"，而这个字段喂给
`isSleeping`（30 天未连 → 沉睡）。一旦被未来值钉死，用户会看到一把锁**永远显示为"最近活跃"**，
而它其实早就没连过了 —— 判断依据静默失效。

## 2. 修法：做成唯一判据，两处复用

新增 `TimeFormat.timestampIsPlausible(_:now:tolerance:)`：

```swift
static func timestampIsPlausible(_ t: Double, now: Double = ..., tolerance: Double = 60) -> Bool {
    t <= 0 || t <= now + tolerance
}
```

- 容忍 60 秒：小幅时钟漂移不算超前（否则正常使用会被误伤）；
- `t <= 0` 视为可信：那是"没有记录"，由各调用点自己的 `guard > 0` 处理；
- 两处调用点直接用它替换各自手写的不等式。

## 3. 新增测试

`TimestampPlausibilityTests`：0 / −10s / +30s（容忍）/ +1h（拒）/ +30d（拒），
以及 `coolReady` 对未来值返回 true。

## 4. 方法论

**同一个判据出现第二次时，就该提出来做成唯一出口。**

上轮我在 `coolReady` 里手写了一个 `lastDispatch > now + cooldownSeconds` 的内联检查。
本轮在 `touchConnection` 遇到同一形状 —— 如果再手写一遍，就是**第三处将要出现不一致的地方**
（本仓已经反复在这种"同一规则多处实现"上栽跟头）。

所以提到 `TimeFormat`（本仓"时间口径的唯一出口"，定位一致）。
判据：**同类判断第二次出现时立刻提取共用，第三次就是债。**
