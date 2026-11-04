# AUDIT-ROUND-237 · 第 237 轮：**`owner` 字段里同时存着「成员 id」和「成员名」**

> CI：**`dcd2888` build 全绿**（WebDAV test 修复编译通过）；`1d40003` 排队中。

## 1. 缺陷

台账的 `LedgerPwd.owner` / `LedgerFp.owner` 这**一个字段**，历史上被两条路径写进了两种东西：

| 写入路径 | 写进去的是 |
|---|---|
| 成员管理指派 / 成员合并 / 备份恢复 | **成员 id**（`DB.setPwdOwner(mac, alias, memberID)`） |
| **凭证工作室创建**（`KeyCreateScreen` → `addPassword(owner: ownerName)`） | **成员名字**（`owner = member.name`） |

而读侧只有一种口径 —— `CredentialOrg.ownerName(_:)` 里 `guard let m = DB.member(id)`，**只按 id 查**。

### 后果

| 现象 | 说明 |
|---|---|
| 工作室创建的凭证**恒显示「未归属」** | `DB.member("张三")` 查的是 `kf_members["张三"]`，而键是 id |
| 「名下 N 枚凭证」计数漏 | 那处按 `owner == member.name` 比 ⇒ 只数得到名字口径的，漏掉 id 口径的 |

## 2. 修法（读侧 + 写侧一起）

**读侧兼容旧数据**：`DB.member(id) ?? DB.members().first { $0.name == id }`

**写侧统一成 id**（`addPassword`）：已是 id 就保留，是名字就换成对应成员的 id。

**计数两口径都认**（`MemberCard.keyCount` 与两处 `KeysOwnerRow`）：`$0.owner == m.id || $0.owner == m.name`

## 3. 方法论

**一个字段两种含义，是「两套口径」里最难发现的一种 —— 因为两条路径各自都自洽。**

| 单看写入方 | 单看读取方 | 合起来 |
|---|---|---|
| 工作室写名字，合理（UI 里就是按名字选） | 按 id 查，合理（成员主键就是 id） | **永远对不上** |

判据：**凡是有 `owner` / `author` / `assignee` 这类「指向另一个实体」的字段，
就 grep 一遍它的所有写入点，确认它们写的是同一个东西（id 还是名字）。**

本轮就是靠「grep 底层字段 `keyCount`」→ 发现 `owner == m.name` 这个比较 → 反查出写入侧不一致。
