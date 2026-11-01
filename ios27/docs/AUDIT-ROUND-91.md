# AUDIT-ROUND-91 · 第九十一轮：等 CI 的同时做两件零风险的事

> CI：`64a3c47` 的回执未到（当前 `ci-log` 仍指向 `fd07a75` 的旧红）。本轮本地提交。

## 1. 静态核对隔离修复是否完整

`removeDevice` 一共调用 6 个外部函数，逐个确认隔离：

| 函数 | 所属 | `@MainActor`？ |
|---|---|---|
| `removeKeychain` / `clearPendingPair` / `ledger` | `Store` / `StoreKeychain` | 否 |
| `CredentialOrg.cancelAlerts` | `enum CredentialOrg`（无标） | 否 |
| `CredBinStore.purgeSecretsForDevice` | 普通 enum | 否 |
| `CredHistoryStore.purgeSecretsForDevice` | 普通 enum | 否 |
| `MobileKeyService.purgeSecretsForDevice` | **`@MainActor` 枚举** | **是 —— 已加 `nonisolated`** |

结论：**只有一个需要修，且已修**。这也解释了 CI 为什么只报了一条错（编译器会在第一条报错处停下，
但类型检查不会"漏报" —— 若另五个也有问题，静态核对这一步就会暴露）。

## 2. 找到第 7 处「保留未接」

`CredentialOrg.overlapWindows`（327 租期重叠检测）零调用。按 RESERVED 的三特征判定：

| 特征 | 有？ |
|---|---|
| 注释里有需求编号（327） | ✅ |
| 实现完整（同归属人过滤 + 半开区间判定） | ✅ |
| 能指出接线点（凭证创建页时间段字段下方） | ✅ |

⇒ **保留未接**，不是死代码。已加 `【保留未接】` 标记并登记进 `RESERVED.md` 第 17 行。

## 3. 为什么不删

它与前面清掉的 6 处死声明（`quota` / `DiagFlags.silent` / `Advice` / `DiagOp` / `selfCheckWarning` / `Diff`）
的关键区别是：**那 6 处都说不出"接在哪"**。说得出接线点的，删掉就等于删掉一个已设计好的功能。

## 4. 方法论

**"零调用"是事实，"死代码"是判断** —— 两者之间隔着"有没有接线点"这个证据。

本仓的处置规则现在很清楚：

| 证据 | 处置 |
|---|---|
| 零调用 + 无需求编号 + 无接线点 | **删**（6 处已删） |
| 零调用 + 有需求编号 + 有接线点 | **标记 + 登记 RESERVED**（现 17 处） |
| 零调用但在封闭簇内互相调用 | **追可达性后删**（1 簇已删） |
