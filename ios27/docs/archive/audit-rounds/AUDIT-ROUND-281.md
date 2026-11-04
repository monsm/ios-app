# AUDIT-ROUND-281 · 第 281 轮：删掉锁之后，记录页仍死盯着那把不存在的锁

> CI：`60869f8` build 全绿；`b320efa` / `68c0bf7` 排队中。

## 1. 组合场景（这轮换的角度：按操作序列找跨功能缺陷）

| 步骤 | 状态 |
|---|---|
| 记录页用锁选择器选了 A | `selectedMac = A` |
| 去设置页删掉 A | `kf_keychains` 里没有 A 了 |
| 回记录页 | `mac` 仍解析成 **A** |

## 2. 后果

| 位置 | 表现 |
|---|---|
| `reload()` | `DB.keychains().filter { $0.mac == A }` ⇒ 空 ⇒ **记录页恒空** |
| `readLogs()` | `if selectedMac != app.lock?.id` ⇒ **每次读取都把 `DB.currentMac` 指回已删的 A** |

第二条尤其糟：全局当前锁被反复拨到一把不存在的锁上，再靠 `preferredMac()` 兜回来 ——
看起来「没坏」，但每次读日志都要先绕一圈错误状态。

## 3. 修法

`reload()` 入口加回落：

    if !selectedMac.isEmpty, DB.keychain(selectedMac) == nil { selectedMac = "" }

`selectedMac` 为空即「跟随当前锁」（`mac` 的实现本来就是这个语义），删锁后记录页自动跟到剩下的那把 ✅。

## 4. 方法论

**「实体 A 被删」时，所有**持有 A 的 id** 的地方都要能回落 —— 而这类引用不会出现在「删 A」的代码里。**

| 查法 | 能发现什么 |
|---|---|
| 看 `removeDevice` 做了什么 | 只能看到它自己清的数据 |
| **grep「谁存了锁的 id」** | **发现 `selectedMac` / `overrideMac` 这类会话态引用** |

判据：**删实体的流程写完，要 grep 一遍「这个实体的 id 还被谁记着」，逐个确认能回落。**
（`overrideMac` 已被 `currentMac` 的 `DB.keychain(overrideMac) != nil` 守卫覆盖 ✅；`selectedMac` 本轮补上。）
