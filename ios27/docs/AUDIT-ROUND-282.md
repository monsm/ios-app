# AUDIT-ROUND-282 · 第 282 轮：合并同名成员，会把副档的手机钥匙**静默删掉**

> CI：`9be5d11` build 全绿；`b320efa` / `68c0bf7` / `402f8e6` 排队中。

## 1. 缺陷

`MemberMergeKit.merge` 把副档并入主档时，迁了三样：

| 数据 | 迁了吗 |
|---|---|
| 密码归属 | ✅ `DB.setPwdOwner` |
| 指纹归属 | ✅ `DB.setFpOwner` |
| 记录认领 `kf_mclaim_` | ✅ `MemberHub.reassignClaims` |
| **手机钥匙 `kf_mkey_`** | ❌ **没迁** |

而 merge 的最后一步是 `DB.removeMember(secondaryID)`，它会执行（Round 230 加的那段）：

    把 memberID 指向该成员的手机钥匙**整条删掉**，
    连钥匙串里的 pin / ekey 副本一起 `SecretStore.remove`。

**于是：合并两个同名成员 = 副档签出去的那些手机钥匙在本机被静默抹掉。**
而锁端那把钥匙**仍然有效** —— 用户从此看不到它、也吊销不了。

## 2. 为什么 removeMember 那样写是对的，而 merge 用它就错

`removeMember` 的注释写的是「删了成员，他名下签出去的手机钥匙仍在列表里（且 pin/ekey 副本也在），
显示成一个归属不存在的孤儿」—— 对**删除**而言，清掉是对的。

但**合并**不是删除：主档还在，只是换了个人名。密码/指纹都是「改判」，手机钥匙凭什么被删？

## 3. 修法

新增 `MobileKeyService.reassignMember(from:to:)`：遍历所有 `kf_mkey_` 表，把 `memberID == 副档` 的条目改判给主档；
`merge` 在 `removeMember` **之前**调用它。

（`rawList` 会从钥匙串回填 pin/ekey，`save` 会写回 —— 复用既有读写，不碰副本本身。）

## 4. 方法论

**「删除流程」被复用到「合并流程」时，删除侧为「清孤儿」做的清理会变成数据丢失。**

| 流程 | 对副档名下数据 |
|---|---|
| 删除成员 | 清掉（无人可归属） ✅ |
| **合并成员** | **改判给主档**（人还在，只是换了档） ❌ 原来被清掉 |

判据：**凡是「复用 removeX 收尾」的 merge 流程，都要逐个列出 removeX 会清掉的数据族，
确认每一族在合并语义下该「改判」而不是「删除」。**
