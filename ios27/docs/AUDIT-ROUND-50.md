# AUDIT-ROUND-50 · 第五十轮：所谓「彻底删除要问生物识别」不存在

> CI：`7f87aef` 已验证；`2971b60` 待回执。本轮本地提交，不推送。

## 1. 第七处「注释比代码更用力」

`CredentialOrg.swift` 头部写着：

> 502 彻底删除的统一门槛口 (`guardedPurge`) 要问生物识别，所以本文件也吃这一套系统框架

实测：**全仓没有 `guardedPurge` 这个函数**，它只在注释里出现过。
回收站的「彻底删除」就是直接删（`CredBinStore.purge`），没有任何生物识别门槛。

连带还有一条：本文件从未用到 `LocalAuthentication` —— `LAContext` 只出现在
`AutoOpenKit` / `SecurityScreen` / `LockKeeperApp` 三处。那条 `import LocalAuthentication`
也是凭空来的，已删。

## 2. 要不要补上这道门槛？

**不要。** 彻底删除的是"已经删掉的凭证的本机副本"—— 它已经不参与任何开锁，
留着只是占空间。给它加生物识别不会提升安全性，只会让用户在清理回收站时多做一次无意义验证。

所以正确处置是**把注释改对**，不是加功能。

## 3. 计数

这已是第七处。前六处：`quota()`、`DiagFlags.silent`、`struct Advice`、`DiagOp/DiagOps`、
`selfCheckWarning`、文件头存储键清单（`kf_cqueue_` / `kf_cbin_reclaim_days` / `kf_clists_`）。

## 4. 方法论

**注释里出现"统一门槛口 / 统一入口 / 单一落点"这类词时，一定要去找那个函数。**
这类词描述的是"架构承诺"，而架构承诺最容易被写在注释里、从未写进代码。

反过来：**代码里真正的统一落点，应该在注释里给出函数名 + 行号，并且能被 grep 到。**
`DB.delPwd` 那条注释就是这么写的（"这里是全仓所有 `DB.delPwd` 的唯一落点"），所以它可信。
