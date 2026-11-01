# AUDIT-ROUND-88 · 第八十八轮：把「清理清单」改成一张会显示缺行的表

> CI：`85bd4d2` 已验证；`a90877b` / `fd07a75` 刚推送。本轮本地提交。

## 1. 上一轮的结论：清理清单是人肉枚举

`removeDevice` 要清的 "每锁数据族" 是一长串手写前缀（`kf_ledger_` / `kf_cbin_` / … 20+ 项），
外加一段兜底的 `k.contains(m)` 扫描。而**钥匙串副本**必须在 plist 键之外单独清 ——
这一点已经在**四族**上各踩过一次：

| 族 | 漏清的后果 | 修于 |
|---|---|---|
| 台账口令 | 每条凭证留一份可读口令 | ROUND-27 |
| 回收站 | ≤100 条留副本 | ROUND-47 |
| 版本快照 | ≤10 份整表留副本 | ROUND-47 |
| **手机钥匙** | **pin/ekey 副本留在本机** | **ROUND-87** |

每次都靠"我再去扫一遍"发现，不是机制发现的。

## 2. 本轮：把清单改成表，让"缺一行"看得见

在 `removeDevice` 上方插入一张表：

| 数据族 | plist 键 | Keychain 副本 | 清副本的调用 |
|---|---|---|---|
| 台账口令 | `kf_ledger_<mac>` | `ledger.<mac>.pwd.<alias>` | 循环 `pwdSecretAccount` |
| 台账指纹 | 同上 | —（指纹无副本） | — |
| 回收站 | `kf_cbin_ui_<mac>` | `ledger.<mac>.bin.<id>` | `CredBinStore.purgeSecretsForDevice` |
| 版本快照 | `kf_chist_ui_<mac>` | `ledger.<mac>.snap.<id>.<alias>` | `CredHistoryStore.purgeSecretsForDevice` |
| 手机钥匙 | `kf_mkey_<mac>` | `mkey.<mac>.pin/.ekey.<id>` | `MobileKeyService.purgeSecretsForDevice` |
| 锁母钥/蓝牙钥/PIN | `kf_keychain_<mac>` | `kc.<mac>.skey/.bkey/.ekey/.pins` | `removeKeychain` |
| 未完成配网 | `kf_pending_pair_<mac>` | `kc.<mac>.pending.<字段>` | `clearPendingPair` |
| 通知排程 | `kf_calert_<mac>_*` | —（在系统通知中心） | 循环 `cancelAlerts` |
| 其余每锁键族 | 前缀列表 + 兜底 `k.contains(m)` | — | — |

并写明判据：

> **新加一族时，上表要么加一行，要么在「Keychain 副本」列写 `—` 并说明为什么没有。**

## 3. 为什么表比"记得清理"有效

表是**有限的、可数的**：读者一眼能看出"我加的那个族在不在里面"。
而一长串前缀列表是**无限的、开放的** —— 少一项完全看不出来。

（写表时我又核对了一遍真实键名：`kc.` 前缀而非我第一版凭印象写的 `keychain.` ——
**又是"写文档时凭记忆编标识符"**，这次当场 grep 校验了。）

## 4. 方法论

**"人肉枚举"要变成"有限表格"才有检错能力。**

判据：**凡是一段"每加一类数据就要回来补一笔"的代码或注释，都该整理成表** ——
行列固定之后，"缺一行"才成为可见状态；散文式清单里，缺什么都没人看得出。
