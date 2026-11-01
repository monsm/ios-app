# AUDIT-ROUND-27 · 第二十七轮：每删一条凭证，钥匙串里就永久多一份明文

> CI：`db3beda` 已验证（errors=0、build_ok=1）；`af30ed5` 与本轮提交待回执

## 1. 缺陷：`delPwd` 不清钥匙串副本

SEC-01 之后，每条凭证的明文口令在 Keychain 里另存一份：`ledger.<mac>.pwd.<alias>`（`pwdSecretAccount`）。

清理只发生在 `ledgerForPlist` —— 而它只遍历**仍在台账数组里的条目**：

```
for i in safe.pwds.indices {
    guard let pwd = ..., !pwd.isEmpty else {
        SecretStore.remove(pwdSecretAccount(mac, safe.pwds[i].alias))   // 只覆盖「还在数组里」的
        continue
    }
    ...
}
```

条目一旦被 `delPwd` 从数组移除，那份副本就**再没有任何代码碰过它**。
于是：**每删一条凭证，钥匙串里就永久多一份可读的开门口令**。
这既是无界堆积，也是「已删除的凭证材料还留着」的泄露面。

## 2. 修法

`delPwd` 是全仓所有删除路径的唯一落点（其注释已列明：停用 / 彻底删除 / 批量 / 换槽 / 恢复），所以在那里补一行：

```
SecretStore.remove(pwdSecretAccount(mac, alias))
```

## 3. 同类排查（这次没有漏）

| 家族 | 删除时是否清副本 |
|---|---|
| 台账口令 `ledger.<mac>.pwd.<alias>` | **本轮修复** |
| 手机钥匙 `mkey.*` | 是 —— `MobileKeyService.revoke` 清 |
| 回收站 `ledger.<mac>.bin.<id>` | 是 —— `purge` / `clear` / `restore` 都清 |
| 版本历史 `ledger.<mac>.snap.*` | 是 —— 裁到 10 份时清被裁的 |
| 整机删除 `removeDevice` | 是 —— 遍历该锁全部 alias 清 |

## 4. 防复发：privacy 闸门第 15 条

`delPwd` 函数体内必须出现 `pwdSecretAccount`。已验证抓得住：

```
privacy: FAIL — 1 处回归
  Engine/StoreLedger.swift:184 — delPwd 没有清理钥匙串里的口令副本
    → 加 SecretStore.remove(pwdSecretAccount(mac, alias))
```

## 5. 方法论

**「写进去的地方」和「擦掉的地方」往往不是同一处。**

`ledgerForPlist` 看起来是口令生命周期的总闸，但它只在「保存」时运行，
而删除是「先移除条目、再保存」—— 顺序决定了它永远看不到被删的那条。

判据：**凡是把数据搬到另一个存储的动作，都要单独问「删除时谁去清那一份」**，不能指望保存路径顺手清掉。
