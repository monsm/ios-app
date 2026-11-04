# AUDIT-ROUND-216 · 第 216 轮：自动开锁 rc=3 校时后不重试 + rc=26 不解除武装

> CI：`e834943`（路由事件认领）已验证绿；`edbd3b0` / `1f51b10` 排队中。

## 1. 缺陷 A：rc=3 校完时不重试 —— 用户站在门口什么也没发生

```swift
case 3:
    await selfHealTime(mac: mac)      // ← 校完就结束了
```

`rc=3` = **命令过期**，按协议锁**没有执行**这条开锁（多半是锁钟漂了）。

| 环节 | 原行为 |
|---|---|
| 发现 rc=3 | 自动校时 ✅ |
| 校时成功之后 | **不重试** —— 门没开，用户不知道发生了什么 |

自动开锁的全部意义就是「不用用户动手」。校好了却不补一次，等于把唯一的自动化机会浪费掉。

### 修法

`selfHealTime` 改为返回 `Bool`（是否真的校时成功），成功后补一次开锁：

```swift
case 3:
    if await selfHealTime(mac: mac) {
        let rc2 = (try? await LockService.shared.unlock(mac: mac)) ?? -1
        if rc2 == 0 { armed = false; AutoOpen.audit(mac, "rc=3 校时后重试开锁成功") }
        else { AutoOpen.audit(mac, "rc=3 校时后重试仍失败 rc=\(rc2)") }
    }
```

**安全性**：rc=3 保证锁没执行，所以重试不会双开。

## 2. 缺陷 B：rc=26 防拆后没解除武装

```swift
case 26:
    AutoOpen.setSuspendUntil(mac, …)   // 只挂了 24h 挂起
```

`armed` 仍为 true ⇒ 之后每次靠近都会走到闸门被判「拒开 rc=26 防拆挂起中」并**刷一条审计**。
挂起期本就该静默，刷屏只会把真正的线索淹掉。补 `armed = false`。

## 3. 顺带确认：`AutoOpenKit` 的成功判据是对的

```swift
switch rc {
case 0: AutoOpen.audit(mac, "自动开锁成功")
…
}
```

**只有 rc=0 算成功** —— 这与 ROUND-196 把 `AppModel` 里 `rc == 0 || rc == 22` 改掉的方向一致，
也反向印证了那个修复是对的（同一个动作，引擎层的判据比界面层严格）。

## 4. 本轮审计点全表

| 行 | 断言 | 支配条件 | 判定 |
|---|---|---|---|
| 326 | 拒开 rc=26 防拆挂起中 | `isSuspended` | ✅ |
| 389 | 拒开 … | `AutoOpenGate.reject` | ✅ |
| 427 | 下发前复查放弃 | `guard AutoOpen.on && active` | ✅ |
| **434** | **自动开锁成功** | **`case 0`** | ✅ |
| 438/440/443/445 | 各 rc 分支 | `switch rc` | ✅ |
| 449 | 下发异常 | `catch` | ✅ |
| 455 | 读锁钟失败 | `guard let … else` | ✅ |
| 473/475 | 校时失败 / 已校时 | `if let syncError` | ✅（上轮修） |
| 478 | 偏差超窗 | `else` | ✅ |

**全部有支配条件。** 这条线可以收尾了。

## 5. 方法论

**「自愈只做了一半」比「不自愈」更难察觉。**

| 写法 | 用户感受 |
|---|---|
| 不自愈 | 「自动开锁不工作」—— 明确 |
| **自愈了但不继续** | 「有时灵有时不灵」—— 最难查 |

判据：**任何"修复前置条件"的分支，都要问一句「修好之后，原来那件事要不要再做一次」。**
