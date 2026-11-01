# AUDIT-ROUND-219 · 第 219 轮：**「全新恢复后成员和凭证不关联」**（用户报告）

> CI：`df32217` 已验证绿；`9aee6fa` / `71e370d` 排队中。

## 1. 链路逐段核查

| 环节 | 结论 |
|---|---|
| 导出 `collectAll` → `members` / `ledger.pwds[].owner` | ✅ 都在 |
| `BackupCanonical.ledgerValue` | ✅ 写 `owner`（nil 写 null） |
| `LedgerPwd.CodingKeys` / `init(from:)` | ✅ 解 `owner` |
| `parsePreview` → `JSONDecoder` → `upgradeChain` | ✅ 不丢字段 |
| `restore`：`importMembers` 建 `remap`（旧 id → 新 id） | ✅ 按名字匹配/新建 |

**链路本身是通的** —— 所以问题出在"映射**建不起来**"的那几种情况。

## 2. 缺陷

原来的归属重写只有两条路：

```swift
if let o = p.owner { p.owner = remap[o] ?? (DB.member(o) != nil ? o : nil) }
```

| 情况 | 结果 |
|---|---|
| 本机新建过该成员（remap 命中） | ✅ 关联 |
| 旧值恰好是本机已存在的成员 id | ✅ 关联 |
| **旧包把 owner 存的是成员名字** | ❌ `remap[name]` 落空 + `DB.member(name)` 查的是 id ⇒ **置 nil，关联不可逆丢失** |
| 成员没恢复成功（同名无法新建等） | ❌ 同上 |

**第三条是关键**：`owner` 字段历史上存过**名字**，而重写逻辑只认 **id**。

### 修法：加一条按名字回退

```swift
if let o = p.owner {
    if let newID = remap[o] { p.owner = newID }
    else if DB.member(o) != nil { p.owner = o }
    else if let byName = DB.members().first(where: { $0.name == o }) { p.owner = byName.id }   // ← 新增
    else { unlinkedOwners += 1; p.owner = nil }
}
```

密码与指纹两条都改了。

## 3. 让"丢了几个"变成用户看得见的数字

`restore` 的返回值新增 `unlinkedOwners`，两个恢复页都会显示：

> 「已恢复：新增 12 项，合并 0 项；**3 项凭证的归属在本机找不到（已置为未归属，可在凭证页重新指派）**」

颜色也随之转警告。这样下次再出现同类问题，**用户能直接告诉我是几条**，而不是"不关联了"。

## 4. 方法论

**「关联丢失」类 bug 的可怕之处：数据一条没少，只是关系断了。**

| 检查 | 能不能发现它 |
|---|---|
| 条数对账（新增 N 项） | ❌ 全对 |
| 字段非空检查 | ❌ owner 允许为 nil |
| **关系完整性（每条 owner 都能解析到成员）** | ✅ 只有这个能查出 |

判据：**恢复/迁移后不要只报"恢复了多少条"，还要报"其中多少条的关系断了"。**
