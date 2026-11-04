# AUDIT-ROUND-266 · 第 266 轮：同一张卡上的两个数字来自两个人群

> CI：**`d8fc80d` build 全绿**；`ef58e21` / `2d02f3c` 排队中。

## 1. 缺陷

`RecordExportScreen` 的「成员名册」卡片里并排两格：

| 格 | 算法 | 含归档？ |
|---|---|---|
| 成员 N 位 | `app.members.filter { !$0.archived }.count` | ❌ 不含 |
| **凭证 N 枚** | **`app.members.reduce(0) { $0 + $1.keyCount }`** | **✅ 含** |

而它旁边导出的 vCard 名册（`MemberVCard.build`）是 `for member in members where !member.archived` ——
**只含在册成员**。

于是这个「凭证 N 枚」**描述的不是它旁边那份导出内容**：归档成员名下的凭证被算进来了，
用户导出后对不上。

这也与 `HouseholdScreen` 的 `HHStats.ownedKeys(activeMembers)`（在册）口径不一致 ——
**全仓只有这一处对全部成员求和**。

## 2. 修法

改为 `app.members.filter { !$0.archived }.reduce(0) { $0 + $1.keyCount }`，与「成员 N 位」同一人群。

## 3. 本轮另外 2 项核对

| 检查 | 结论 |
|---|---|
| CSV 导出的行数 | ✅ 用 `RecordCSV.rowCount(csv)` 数**实际行数**，不是选中数 |
| `LockSettingsScreen` 六个开关的反馈 | ✅ 成功/失败都有 outcome + 成功有 toast |

## 4. 方法论

**并排显示的两个数字，必须是同一个「人群/范围」，否则读者会默认它们可比。**

| 检查手法 | 效果 |
|---|---|
| 单独看每个数字 | 各自都对 |
| **看同一张卡上的数字是否同一 population** | 一眼看出分母不同 |

判据：**一张卡片/一个区块内的所有计数，先问「它们统计的是同一批东西吗」——不是就先统一，再谈显示。**
