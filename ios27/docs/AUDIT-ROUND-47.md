# AUDIT-ROUND-47 · 第四十七轮：删设备时，回收站与版本快照的口令副本没清

> CI：`9d6f645` 已验证；`7f87aef` / `2971b60` 待回执。本轮本地提交，不推送。

## 1. 缺陷：删了锁，它的口令还留在钥匙串里

`Store.removeDevice` 做得已经很细：取消通知、清台账口令的 Keychain 账户、按前缀删几十个键族、
兜底按 MAC 子串扫、连本机备份文件都清。**但漏了两族"整份副本"：**

| 族 | 规模 | 清了吗 |
|---|---|---|
| 台账口令 `ledger.<mac>.pwd.<alias>` | 每条一个 | ✅ 清了 |
| **回收站** `ledger.<mac>.bin.<id>` | 最多 100 条 | ❌ **没清** |
| **版本快照** `ledger.<mac>.snap.<id>.<alias>` | 最多 10 份 × 每条凭证 | ❌ **没清** |

`removeDevice` 会删掉 `kf_cbin_<mac>` / `kf_chist_<mac>_*` 这些 **plist 键**，
但钥匙串（Keychain）里的副本不会随键消失 —— 于是「删除这把锁」之后，
它的开门口令仍然以最多 110 份的形式留在本机钥匙串里。

这和 AUDIT-ROUND-27 修的是同一族问题（`delPwd` 不清 `pwdSecretAccount`），
只是当时只覆盖了台账那一条路径。

## 2. 修法

- `CredBinStore.purgeSecretsForDevice(_ mac:)`
- `CredHistoryStore.purgeSecretsForDevice(_ mac:)`
- `removeDevice` 在**删键之前**调用这两个（删了键就读不到条目了）

## 3. 方法论

**"删除"要按存储层逐层清，而不是按键名清。** 一个实体（凭证）的明文可能同时存在于：
台账 plist、回收站 plist、10 份快照 plist、以及它们各自的钥匙串账户 ——
**四层里删掉一层，就等于没删。**

判据：任何 `remove*` 函数，都要列出"这个实体的副本都住在哪"，逐层清并写在注释里。
本轮的注释就按这个格式写的（列表格）。
