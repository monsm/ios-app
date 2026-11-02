# AUDIT-ROUND-319 · 第 319 轮：只读试验模式有**两条绕过路径**，还有一句过宽的文案

> CI：`7956de4d` build 全绿（errors=0）。

## 1. 文案承诺 vs 实际拦截

`TrialGuard.warning` 写：「开锁、写凭证、换钥、配网、网关、**固件升级**、导入备份全部被拦下」

而实际的守卫只有两处：

| 强制点 | 覆盖 |
|---|---|
| `LockServiceLink.request` 的 `ZKProtocol.assertReadOnly` | 开锁/写凭证/换钥/配网/网关 ✅ |
| `BackupStudioKit.restore` | 导入备份 ✅ |
| **`HardwareService.send`** | ❌ **没有** |
| **`DFUSession.run`** | ❌ **没有** |

## 2. 两条绕过路径的实际危害

| 路径 | 能做什么 |
|---|---|
| `HardwareService.send` | 硬件页的 cmd41（写 ekey）/ cmd21（设 bkey）等**写命令**照样下发 |
| `DFUSession.run` | **固件升级照样能刷** —— 而「刷一半断链」正是 DFU 页自己最警告的失败态（会把锁停在升级模式、开不了门） |

只读模式的整个意义就是「真机排障时不会把锁改坏」，这两条恰好都能把锁改坏。

## 3. 修法

| 位置 | 改动 |
|---|---|
| `HardwareService.send` | 照抄同一行：`if DB.store.getBool("kf_trial_guard", false) { try ZKProtocol.assertReadOnly(cmdObj.cmd) }` |
| `DFUSession.run` | `guard !TrialGuard.isOn else { throw DFUTransportError.ble(…) }`（唯一执行入口，拦一处即全覆盖） |
| `SecurityScreen:303` | 文案「写入类操作全部停用」→「写入类**命令**全部停用（**本机台账仍可编辑**）」 |

最后那条是因为：本机台账/成员/设置的编辑**本来就没拦**（它们不下发到锁），
而上面那句 note 其实写对了（「写入类**命令**停用」）—— 三处文案按最窄的那条对齐。

## 4. 方法论

**「开关的强制点」要按**发送路径**枚举，不是按「最常走的那条」堵。**

| 查法 | 会漏 |
|---|---|
| 找到一处 `assertReadOnly` 就以为覆盖了 | ❌ 漏掉 `HardwareService` / `DFUSession` 两条独立链路 |
| **grep 所有 `writeValue` / 所有直接发包函数** | ✅ 三条链路都列出来 |

判据：**给「总开关」加拦截时，先把「所有能产生外部副作用的地方」列全 —— 只要有一条绕过，开关就等于没有。**
