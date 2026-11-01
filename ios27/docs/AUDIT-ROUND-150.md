# AUDIT-ROUND-150 · 第一百五十轮：校时成功后，门页仍显示旧锁钟

> CI：`ff636fb` 已验证绿；`83c6e30` / `9a1b52b` 待回执。本轮本地提交。

## 1. 缺陷：`syncTime` 用 `refreshStatus: false`

```swift
func syncTime() async -> Result<(Int, Int), Error> {
    ...
    let r = try await LockService.shared.syncTime()
    await reload(refreshStatus: false)      // ← 不重读 cmd03
    return .success((r.before, r.after))
}
```

而门页的「锁钟」读数取的是**投影里的状态**：

```swift
// DoorScreen:700
let clock = app.lastStatus.map { ProtoTime.localStr($0.status.lockTime) } ?? "未读到"
```

`refreshStatus: false` ⇒ 不重新读 `cmd03` ⇒ `DB.readStatus` 拿到**校时前**的快照
⇒ `app.lastStatus.status.lockTime` 是旧值 ⇒ **校时成功了，门页锁钟还是旧的**。

## 2. 为什么本页看不出问题

`SyncTimeScreen` 自己的读数来自 `syncTime()` 的**返回值**（`pair.1`），
所以那一页显示正确 —— 缺陷只在**别的页面**显形。

这是本段反复出现的一种形状：**"发起动作的页面正确，受害的是另一个页面"**。

| 轮次 | 发起页 | 受害页 |
|---|---|---|
| 147 | 锁设置（静音） | 锁状态（`app.lock.muted`） |
| 149 | 安全模式（A/B） | 锁状态（`app.lock.safeMode`） |
| **150** | **校时** | **门页（`app.lastStatus.status.lockTime`）** |

## 3. 修法

```swift
await reload(refreshStatus: true)
```

## 4. 核对全仓 20+ 处 `refreshStatus: false` —— 只有这一处该改

其余都是**页面进入时重载本地数据**（凭证/成员/记录），不需要重读锁状态
（重读要走 BLE，有成本）。判据：

| 该函数做了什么 | `refreshStatus` |
|---|---|
| **改了锁端状态**（静音/模式/校时/上锁） | **true** |
| 只读了本机台账 | false |

## 5. 方法论

**"改了锁端状态"的函数必须刷新投影 —— 这与"页面本地状态"是两件事。**

本段这条判据的战绩：147（静音）· 149（安全模式）· 150（校时）。
三次都是同一个模式：**写路径改了远端真值，但投影没跟上**。

判据：**看到 `LockService.shared.set*` / `sync*` 之后，检查同一个函数里有没有 `refreshStatus`。**
这条可以机械化（`set*` 后 30 行内无 `refreshStatus`/`reload(refreshStatus: true)` 即候选），
但候选里 `setZotp`/`setAutoLock` 等是**正常**的（它们写的数据不是投影），
所以仍需人工判 —— 暂不做闸门（假红会多）。
