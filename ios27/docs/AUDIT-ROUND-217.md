# AUDIT-ROUND-217 · 第 217 轮：`DefendService` 注释承诺「回读」，实现里没有

> CI：`edbd3b0` 已验证绿；`1f51b10` / `0c87d80` 排队中。

## 1. 缺陷（文档过度承诺）

`DefendService.swift` 文件头：

> 把「下发 + 落盘 + **回读**」三件事收在一处，才能保证不会出现
> 「锁端在布防、本机 F4 还在放行自动开锁」这种两边不一致。

`apply` 的文档注释也写着同样的三件事。而实现只有**两步**：

```swift
try await host.lockLink.setDefence(control: control, startSec: startProto, endSec: endProto)
DB.saveDefend(kc.mac, DefendCfg(...))      // ← 到此结束，没有回读
```

### 为什么没有回读（不是漏写，是做不到）

布防状态**不在 cmd03 的状态 KLV 里** —— 要 `op=getDeviceSetting`（`SecurityScreen:237` 的 TODO 记着这件事）。
所以本机只能确认「锁回了 rc=0」，不能确认「锁真的布防了」。

### 修法

把两处注释改成事实：**下发 + 落盘**，并写明「没有回读校验」是**已知未闭环**、
以及 rc=0 但固件未生效时本机与锁端会分叉。

## 2. 顺带核对：用户侧措辞是诚实的

`DefendScreen:413`：

```swift
outcome = mode == .off ? "已撤防（锁端回执成功）" : "已布防（锁端回执成功）"
```

写的是「**锁端回执成功**」而不是「已生效」—— 措辞与能力一致 ✅。
**注释过度承诺、界面却诚实**，说明写注释的人比写界面的人更乐观。

## 3. 本轮另外 3 项「审过、正确」

| 检查 | 结果 |
|---|---|
| `defendActive` 的 `secOfDay / 2` | ✅ 协议是**半秒**刻度：`DefendKit.protoSec` 做 `sec/2`、`secFromProto` 做 `proto*2`，三处一致 |
| `DefendKit.validate` 的 `startSec >= daySeconds` 与 `endSec > daySeconds` 不对称 | ✅ **有意**：允许「到 24:00」（结束），不允许「从 24:00 开始」 |
| `AutoOpenGate.rejectReason` 的 AND 链 | ✅ 8 道门逐条 fail-closed，`faceFresh` 在非严格档直接 `return true`，不会把非严格档卡死 |

## 4. 方法论

**注释比代码更乐观 —— 因为注释没有编译器。**

| 位置 | 谁在核对 |
|---|---|
| 代码 | 编译器 + 闸门 + CI |
| **注释** | **没有人** |

所以注释里的**动词表**（"下发 + 落盘 + 回读"）要格外小心：它读起来像清单，
而清单最容易多写一项。判据：**注释里每列一个动作，就去实现里找出对应那一行；找不到就删掉这个词。**
