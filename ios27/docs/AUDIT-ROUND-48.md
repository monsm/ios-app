# AUDIT-ROUND-48 · 第四十八轮：到期提醒档位不进备份

> CI：`9d6f645` 已验证；`7f87aef` / `2971b60` 待回执。本轮本地提交，不推送。

## 1. 缺陷：换机后所有提醒档位归零

每条凭证的提醒档位存在 `kf_calert_<mac>_pwd_<alias>`（`CredAlert`：day / d3 / d1 / h24 / h2）。
全仓搜索 `calert`：只出现在 `CredentialOrg`（读写）、`StoreKeychain`（删设备时删键）、
以及 `CredentialModels` 的注释里 —— **备份链路里一次都没有**。

后果：

> 换机迁移 / 从备份恢复后，凭证台账和成员都回来了，
> 但每条凭证的提醒档位**静默归零** —— 用户再也不会收到到期提醒，界面也不提示。

这是本轮之前 `memberExt` 那一条的同族问题：**旁挂表没有进备份**。

## 2. 修法（与 memberExt 同一套写法）

1. `CredAlert` 加 `Equatable`（导出时把"全关"的条目省略，不写等价空表）；
2. `BackupBundle.Device.Meta` 新增 `var alerts: [String: CredAlert]?`；
3. 导出：`CredentialOrg.alertTable(mac)` 过滤掉全关项；
4. 恢复：按 `pwd:<alias>` 解析出别名，写回 `alertKey(mac, "pwd", alias)`；
   缺字段 = 没带 = 不动本机。

## 3. 待验证

只过了形状闸门。`Equatable` 合成、`Meta` 成员构造、`DB.setCodable(a, key)` 的参数顺序
都要等 CI 编译确认 —— **回执前不声称通过**。

## 4. 方法论（第二次踩同一个坑，所以把它写成清单）

本仓的"旁挂表"至少这些，**每加一张都要问四件事**：

| 旁挂表 | 进备份？ | 恢复 remap？ | 删设备清？ | 删条目清？ |
|---|---|---|---|---|
| `kf_member_ext` | ✅ 本轮之前 ❌ | ✅ 本轮 | ✅ | — |
| `kf_calert_` | ✅ 本轮之前 ❌ | 按 alias（稳定） | ✅ | ✅ `delPwd` 取消 |
| `kf_rnote_/rflag_/rdisp_` | ✅ | — | ✅ | — |
| `kf_cbin_` / `kf_chist_` | ❌（设计如此） | — | ✅ 本轮补密钥 | ✅ |

清单本身不重要，**"每加一张表就填这四格"这个动作**才重要。
