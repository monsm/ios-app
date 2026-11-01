# AUDIT-ROUND-149 · 第一百四十九轮：`SafeModeScreen` 绕过了投影刷新（第 2 处）

> CI：`305f87c` 已验证绿；`ff636fb` / `83c6e30` 待回执。本轮本地提交。

## 1. 修正上一轮的判断

上轮我说 `SafeModeScreen` "**没写 `DB` 快照**"。这轮读到第 134 行才发现它**有**：

```swift
DB.writeStatus(mac, st)   // ← 我上轮漏看了
```

所以它做对了"落盘"这一步，**只差投影刷新**。

## 2. 缺陷（第 2 处同类）

```swift
try await LockService.shared.setValidationMode(double)
let st = try await LockService.shared.getStatus(mac: mac)
status = st
DB.writeStatus(mac, st)          // 落盘 ✅
// ← 没有 app.refreshStatus()，AppModel.lock.safeMode 仍是旧值
```

而 `LockStatusScreen` 读的是 `lock.safeMode`（**投影**）：

```swift
// AppModel:124
safeMode: (snap?.verifyMode ?? 0) != 0
```

后果：在「安全模式」页切了 A/B，**「锁状态」页仍显示旧模式**。

## 3. 修法（保留本页更严格的回读校验）

`SafeModeScreen` 比 `AppModel.setSafeMode` 多做了两件事：

| 本页有 | `setSafeMode` 有 |
|---|---|
| 回读后**比对** `verifyMode` / `broadcastMode` 并给出"命令已下发但未生效"的诚实提示 | ❌ 只 `refreshStatus` |

所以**不能**简单换成 `app.setSafeMode`（会丢掉那个诚实提示）。
最小改法：保留原逻辑，末尾补 `await app.refreshStatus()`。

## 4. 核对 `TailgateScreen` —— 不是缺陷

```swift
DB.saveTailgate(mac, TailgateCfg(...))
```

而 `AppModel` 的自动上锁倒计时是**计算属性**：

```swift
// AppModel:316-320
/// 自动上锁倒计时：档位取 cmd24 的本机记忆（kf_tailgate_），没设过按厂商默认 6 秒。
let interval = DB.tailgate(currentMac)?.interval ?? 6
```

**每次现读 DB**，不是投影缓存 ⇒ 写完立刻正确，不需要刷新。

## 5. 方法论

**"绕过封装"这条判据要问的第二层：数据是"投影缓存"还是"每次现读"。**

| 数据形态 | 写完要不要刷新 |
|---|---|
| 投影缓存（`AppModel.lock`） | **要**（否则别的页面看旧值） |
| 每次现读（`AppModel.tailgateInterval`） | 不要 |

所以判据要改成两步：

1. 有没有一个引擎函数做同样的事？有 → 调它；
2. **没有的话，看它写的数据是不是投影缓存** —— 是就该补刷新，不是就不必。

第 2 步是我上轮漏掉的 —— 我上轮把 `TailgateScreen` 也标成"待核"，正是因为没先看数据形态。
