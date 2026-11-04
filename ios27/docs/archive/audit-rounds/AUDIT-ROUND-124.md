# AUDIT-ROUND-124 · 第一百二十四轮：审 2 个文件，无缺陷（记录核对过程）

> CI：`44d8807` 已验证绿（`errors=0`、`warnings=0`）；`359b773` / `0fd7c63` 待回执。本轮无代码改动。

## 1. `BackgroundGuard.swift`（35 行）

这个文件本身是 **2026-10-27 的修复产物**（"全仓 0 处 `beginBackgroundTask`"→ 配网/录指纹/DFU
中途切后台会被挂起，门锁留在半完成态）。实现核对：

| 检查点 | 结论 |
|---|---|
| `expirationHandler` 的线程 | Apple 文档：在 **main thread** 调用；而本函数已 `@MainActor` ⇒ **无数据竞争** |
| `taskId` 在闭包里捕获 | Swift 闭包按**引用**捕获 `var`，过期时读到的是最新值 ✅ |
| `beginBackgroundTask` 返回 `.invalid` | `defer` 有 `if taskId != .invalid` 守卫 ⇒ 不会误调 `endBackgroundTask(.invalid)` ✅ |
| 抛错路径 | `defer` 保证 `endBackgroundTask` 一定执行（忘了 end 会被系统强杀）✅ |

3 处调用点（`DFUScreen:251` 固件刷写 / `LockServicePairing:135` 配网尾链 / 另一处配网）
都是"已经在做的长操作"，符合该文件注释里"把已经在做的事做完，而不是开新的后台任务"的定位。

## 2. `AuditChain.swift`（43 行）

头注里有一段**自我修正**值得记：

> ⚠ 2026-10-30 核实（第 99 轮）：**本文件与全仓都没有 DestroyKit**。
> 原头注列的「等价覆写 + 销毁前备份闸 + 残留全文检查」三项**从未实现**。
> 本文件也没有第 242 行 —— 整个文件只有 60 余行（3 个哈希函数）。

也就是说：**这个文件曾经在文档里"声称"有三件事，实际只有两件**。已被前一轮审计更正。
（这正是本段反复出现的"注释里的承诺没有实现"形态，但这里**已经修好了**。）

哈希实现核对：

| 检查点 | 结论 |
|---|---|
| CryptoKit 分支 | `SHA256.hash` → 小写 hex ✅ |
| 无 CryptoKit 的降级 | FNV-1a32 双轮拼接；注释诚实写明"不要求密码学强度"（离线 App 无中心校验方）✅ |
| `fingerprint` 只取前 4 位 hex | 用于**审计留痕的口令 diff**（`StoreLedger:150`），只判"前后是否变化" ⇒ 16 bit 足够 ✅ |

## 3. 方法论

**"这个文件曾经撒谎、现在修好了"值得单独记一笔。**

审计报告容易只记"我发现的新缺陷"，而**已经被前轮修好的缺陷**如果不再提，
下一个读者就不知道"这里曾经有坑、现在没了" —— 他可能重新引入。

`AuditChain` 头注里那段自我修正（写明"从未实现"、写明"没有第 242 行"）
正是**正确的处置方式**：把撤下的承诺留在原地并说明，而不是悄悄删掉。

## 4. 差集进度

26 → 17（本轮 `BackgroundGuard` + `AuditChain`）。
剩余：`DateFormats` 84 / `HouseholdParts` / `HouseholdRoster` / `KeysBits` / `KeysParts` /
`LockGuard` 29 / `RecordModels` 30 / `ToastCenter` 已审 / `HeroStats` 19 等。
