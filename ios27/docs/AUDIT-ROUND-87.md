# AUDIT-ROUND-87 · 第八十七轮：删设备漏清「第四族」钥匙串副本（手机钥匙）

> CI：`efc94c8` 已验证；`dc7b29c` / `93416f6` / `85bd4d2` 待回执。本轮本地提交。

## 1. 缺陷

`Store.removeDevice` 已经清了**三族** Keychain 副本（都在注释里逐条写明）：

| 族 | 账户形态 | 规模 |
|---|---|---|
| 台账口令 | `ledger.<mac>.pwd.<alias>` | 每条一个 |
| 回收站 | `ledger.<mac>.bin.<id>` | ≤100 |
| 版本快照 | `ledger.<mac>.snap.<id>.<alias>` | ≤10 份 × 条数 |

**漏了第四族**：手机钥匙的 `mkey.<mac>.pin.<id>` 与 `mkey.<mac>.ekey.<id>`。
删设备会删掉 `kf_mkey_<mac>` 这个 **plist 键**，但钥匙串副本不随键消失 ——
于是"删了这把锁"之后，它签出去的那些手机钥匙 ekey 还留在本机钥匙串里。

而 `MobileKeyService.revoke` 里**早就有**清这两个账户的代码（第 176-177 行）——
也就是说这个知识一直在，只是没被删设备路径复用。

## 2. 修法

`MobileKeyService.purgeSecretsForDevice(_:)` + 在 `removeDevice` 里紧随另三个 purge 调用。

## 3. 新增测试（带跳过条件）

`testMobileKeyPurgeRemovesSecretCopies`：写入 → 确认副本在 → purge → 确认清掉。

**但先加了 `try XCTSkipUnless(keychainAvailable, ...)`** —— 因为未签名测试宿主没有钥匙串权限，
`SecItemAdd` 会失败，硬断言会变成假失败。仓里 `testLedgerPasswordRoundTripsThroughKeychain`
早就建立了这个判据，直接复用它（而不是另写一套"能写就测"的逻辑）。

## 4. 这是"同族里只有一处漏了"的第 N 次

形态表里第一条就是它（ROUND-23/28/29/30/44/48/65/66/81/83/85 …）。
这次的新意在于：**遗漏发生在"清理清单"本身** —— 而那个清单是逐条手写的，
每加一族数据就要记得回来补一笔。

## 5. 方法论

**清理清单是"人肉维护的枚举"，必须有机制提醒它跟上新增的数据族。**

可行的做法（下一轮做）：在 `removeDevice` 的注释里列一张**数据族 ↔ 存储位置**表，
并把"有没有 Keychain 副本"作为必填列 —— 新增一族时，那张表会显得"缺一行"，
比一句"记得清理"更容易被注意到。
