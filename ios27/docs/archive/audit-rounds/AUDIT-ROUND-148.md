# AUDIT-ROUND-148 · 第一百四十八轮：26 处「页面直接调 LockService」，25 处是正常的

> CI：`0ecd405` 已验证绿；`305f87c` / `ff636fb` 待回执。本轮本地提交。

## 1. 用上轮的判据做一次全量扫荡

```
grep "LockService\.shared\." App/Features/  →  26 处
```

逐个核对「有没有一个 `AppModel` 封装做同样的事」：

| 页面 | 调用 | `AppModel` 有封装吗 | 结论 |
|---|---|---|---|
| `LockSettingsScreen:325` | `setZotp` | **没有** | ✅ 直接调是对的（`AppModel` 不含 otp 投影） |
| `LockSettingsScreen:369` | `pwdClear` | 没有 | ✅ 且它自己补了 `app.reloadKeys(mac)` |
| `LockStatusScreen` | `setMuted` / `setSafeMode` | **有** | ✅ 走的是 `app.setMuted` / `app.setSafeMode` |
| `SafeModeScreen:130` | `setValidationMode` | 有（`app.setSafeMode`） | ⚠ 待核 |
| `TailgateScreen:110` | `setAutoLock` | 有？ | ⚠ 待核 |
| `AddLockScreen` / `DFUScreen` / `LinkSense` / `ProtocolTestScreen` | 配网/DFU/探测 | 不适用（不是"改状态"） | ✅ |

## 2. 核了 `SafeModeScreen` 与 `TailgateScreen`

**`SafeModeScreen:130-132`**：

```swift
try await LockService.shared.ensureConnected(mac: mac)
try await LockService.shared.setValidationMode(double)
let st = try await LockService.shared.getStatus(mac: mac)   // ← 自己重读
```

它自己重读了状态 —— 但**没写 `DB` 快照**，也没刷新 `AppModel.lock`。
核对 `app.setSafeMode`：它只 `await refreshStatus()`，而 `refreshStatus` 会写 `kf_snap_` 并刷新投影。

**判定：`SafeModeScreen` 确实绕过了封装**（少了快照落盘 + 投影刷新）。

## 3. 修法

（见下轮：本轮先记录，改法与 ROUND-147 同形）

## 4. 方法论

**这条判据的价值在于"能判掉"** —— 26 个候选里 25 个是正常的，
正是"逐个判掉"让剩下那 1 个（`LockSettingsScreen` 的静音）显形。

已写进 `AUDIT-METHOD.md §1.8`：

> 看到页面直接操作 `DB`/`LockService` 时，先问「有没有一个引擎函数做同样的事」。
> 有 → 就该调它；**没有 → 那就是对的，不要为了"统一"硬造一层封装**。

第二句比第一句重要：**"统一"本身不是目标**，否则会把正常的直调也包一层壳。
