# AUDIT-ROUND-289 · 第 289 轮：等 CI 追平 + 两项核对（沉睡判定 / 30 天阈值单位）

> CI：仍停在 `c70d0d3`（`errors=2`，已知根因 = 我 Round 282 的跨隔离调用）。
> 修复 `a2e8766`（给 `MemberMergeKit.merge` 加 `@MainActor`）**已推送，排在队列里**。

## 1. 为什么 `@MainActor` 那处修复是安全的（静态论证）

`MemberMergeSheet` 是 `struct … : View`。SwiftUI 的 `View` 协议在现行 SDK 上是
`@MainActor @preconcurrency` ⇒ **conforming 类型整体获得主 actor 隔离**，
所以它的 `private func merge()` 本身就在主 actor 上，调用 `@MainActor` 的 `MemberMergeKit.merge` 合法 ✅。

（唯一调用点 `MemberMergeSheet:91`，别处只用 `candidates`（非隔离）—— 不受影响。）

## 2. 核对 A：沉睡判定

`LockStats.isSleeping`：

| 检查 | 结论 |
|---|---|
| 从未连接过的锁 | ✅ `t > 0` 守卫 ⇒ 不判沉睡（新绑定/只导入） |
| 未来时间戳 | ✅ `timestampIsPlausible` 挡掉，按「刚连过」处理 |
| 阈值 | ✅ 30 天 |
| 与 `touchConnected` 的口径 | ✅ 两处都做了未来值保护（注释记录了「同族两处口径不一致本身就是缺陷」） |

**无缺陷。**

## 3. 核对 B：各处「30 天」的单位

| 位置 | 单位 | 与谁比较 | 结论 |
|---|---|---|---|
| `DoorScreen`（未校时提醒） | 毫秒 | `DB.syncTime`（毫秒） | ✅ |
| `HouseholdRoster` / `HouseholdScreen` | 毫秒 | `entry.at`（毫秒） | ✅ |
| `QuickPool` / `MemberHub` / `RecordSearchQuery` | 秒 | `protoSecondsToUnix`（秒） | ✅ |

**各自内部一致**（毫秒比毫秒、秒比秒）✅。

## 4. 方法论

**同一个常量（30 天）出现在 8 处、两种单位里 —— 判它有没有 bug，看的是**每处内部是否自洽**，不是看它们是否统一。**

| 检查方式 | 结论 |
|---|---|
| 「全都应该是毫秒」 | ❌ 错误前提 —— 秒制数据源天然用秒 |
| **「这一处的两端单位一致吗」** | ✅ 正确判据 |

判据：**跨单位的一致性要求应加在「同一字段的两端」，不是加在「同一数值的所有使用者」上。**
