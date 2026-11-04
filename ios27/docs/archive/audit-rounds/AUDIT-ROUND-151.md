# AUDIT-ROUND-151 · 第一百五十一轮：自动校时也不刷新快照（同缺陷的引擎层那一处）

> CI：`83c6e30` 已验证绿；`9a1b52b` / `70cba7a` 待回执。本轮本地提交。

## 1. 把上轮的判据机械化了

```python
# 找 LockService.shared.set*/sync* 之后 30 行内没有 refreshStatus / reload(refreshStatus: true) 的
```

结果 **3 个候选**：

| 位置 | 判定 |
|---|---|
| `TailgateScreen:111`（`setAutoLock`） | ✅ 正常（`AppModel.tailgateInterval` 是每次现读） |
| `ZotpScreen:189`（`setZotp`） | ✅ 正常（`AppModel` 不投影 otp） |
| **`AutoOpenKit:460`（`syncTime`）** | ❌ **真缺陷** |

## 2. 缺陷

```swift
private func selfHealTime(mac: String) async {
    ...
    if AutoOpenKit.dualTimeSync(...) {
        _ = try? await LockService.shared.syncTime()   // ← 校时了
        AutoOpen.audit(mac, "rc=3 → 已自动校时（0E 双确认）")
    }   // ← 没有重读快照
}
```

与上轮 `AppModel.syncTime` 是**同一缺陷的两处**：

| 处 | 层 | 上轮处置 |
|---|---|---|
| `AppModel.syncTime` | 应用层 | 改 `refreshStatus: true` |
| **`AutoOpenKit.selfHealTime`** | **引擎层** | **本轮：直接写快照** |

## 3. 为什么引擎层不能调 `refreshStatus`

`AppModel` 依赖 Engine，Engine 不反向依赖界面层（`EngineHost` 就是为此存在的）。
所以引擎层只能做 `refreshStatus` 里**与快照有关的那一句**：

```swift
if let st = try? await LockService.shared.getStatus(mac: mac) {
    DB.writeStatus(mac, st)
}
```

（`AppModel:107` 的 `refreshStatus` 内部做的也正是这一句。）

## 4. 方法论

**"同一缺陷可能在多层各有一份"** —— 修完一层要问"另一层有没有同样的地方"。

本段这条的战绩：

| 轮次 | 缺陷 | 层 |
|---|---|---|
| 150 | 校时不刷新投影 | 应用层 |
| **151** | **同一处** | **引擎层** |
| 145 | 「永久」判据抄三份 | 引擎 + 界面 |
| 133 | 四态被写成二分支 | 界面（引擎侧是对的） |

判据：**一个"忘了做 X"的缺陷，要 grep 一下 X 的语义在别的层是否也需要。**

## 5. 顺带

`LockService.syncTime` 内部**已经回读锁钟**（`readLockTime`，第 107 行）并做 ±60s 校验，
但**不写快照** —— 写快照是调用方的事。这条分工是对的，所以修在调用方而不是 `LockService`。
