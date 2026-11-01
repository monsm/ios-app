# AUDIT-ROUND-100 · 第一百轮：第 2 问真的用起来，又删掉两个重复实现

> CI：`efdc4b2` 已验证；`9abe249` / `92a4d3f` 刚推送。本轮本地提交。

## 1. 按新判据的第 2 问复查，抓到两处

第 2 问是：**"它注释说的接线上，有没有等价实现？"**

| 条目 | 接线页 | 第 2 问结果 |
|---|---|---|
| `markDisabled` / `disableMark`（停用原因回显） | 凭证详情/工作室 | 该页**没有**停用原因回显 → 保留 |
| **`monthDeadlines` / `dayDeadlines`（月历到期）** | 凭证页月历 | **`KeyCalendarScreen` 已实现** → 删 |
| `TimeWord`（时段词） | 记录页 | 无等价实现（但粒度不匹配）→ 保留 |
| `sameTypeCount`（同类计数） | 记录详情 | 无 → 保留 |
| `recentUseCount`（使用次数） | 凭证详情 | 无 → 保留 |
| `overlapWindows`（租期重叠） | 凭证创建 | 无 → 保留 |

## 2. `monthDeadlines` / `dayDeadlines` 判为重复实现的依据

`KeyCalendarScreen` 里有完整的等价（且**更全**）实现：

| 能力 | 日历页（活的） | `monthDeadlines`/`dayDeadlines`（死的） |
|---|---|---|
| 每格到期条数 | `deadlines`（按 dayKey 分桶） | `monthDeadlines` |
| 当天清单 | `pickedItems` | `dayDeadlines` |
| 页头总计 | `monthTotal` | — |
| **数据源** | **`app.keys`（含指纹、手机钥匙）** | 仅 `DB.listPwds`（只有密码/临时码） |

**界面那版覆盖面更广**，Engine 那版是"数据源更窄的旧实现"。已删除，并在原处留说明
（"月历逻辑在 `KeyCalendarScreen`，不在 Engine"）。

## 3. 我差点判错一次（记录）

第一眼看到"日历页已有 `deadlines`"时，我准备直接删。但多看了一眼数据源：

- 日历页：`for key in app.keys`；
- Engine 版：`for p in DB.listPwds(mac)`。

若两者语义等价，删是对的；若不等价（比如界面漏了某类凭证），删就等于删功能。
实际核对后：**界面更全**，所以删是对的 —— 但这个"多看一眼"不能省。

## 4. 方法论

**"有等价实现"要做一次覆盖面对比，不能只看名字像。**

| 对比项 | 问题 |
|---|---|
| 数据源 | 两边都遍历了什么？ |
| 聚合方式 | 分桶键一致吗？ |
| 边界 | 永久有效 / 已停用 / 已归档怎么处理？ |

三个都一致才算"重复实现"。本轮第 3 项恰好是决定性的（`app.keys` vs `listPwds`）。
