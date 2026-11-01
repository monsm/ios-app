# AUDIT-ROUND-101 · 第一百零一轮：把过期的「保留未接」标记全部清掉

> CI：`efdc4b2` 已验证；`9abe249` / `92a4d3f` / `0cac4ce` 待回执。本轮本地提交。

## 1. 为什么必须清标记

`【保留未接】` 标记是**给人看的线索**。接线之后不删，它就变成假信息 ——
而**我上一轮正是被它误导的**（4 条误判 + 本轮 2 条，全都因为"标记还在，但功能已经接上了"）。

所以处置不能只改 `RESERVED.md`：**源码里的标记同样要清**，否则下一个人还会被骗。

## 2. 本轮清掉的 6 处过期标记

| 文件 | 函数 | 实际接线点 |
|---|---|---|
| `HexKit:11` | `strictBytes` | `ZKProtocol` 7 处帧解析 |
| `CredentialOrgBatch:33` | `batchPrefixNote` | `CredentialStudioScreen.applyPrefix()` |
| `MemberHub:274` | `recentExcerpts` | `MemberOpsScreen.activityCard` |
| `RecordSearch:169` | `CommuteLabel.tag` | `RecordsScreen` 行级标签 |
| `CredentialOrg:303` | `removeSearchHistory` | `KeysScreen` 长按删除 |
| `AutoOpenKit:90` | `clearAutocal` | `AutoOpenScreen` 清除标定 + 失败分支 |
| `CredentialOrgState:245` | `weakReason` | `KeyCreateParts.duplicateNote` |

每条都改成「**已接线**：<具体调用点>（原标记已过期并删掉，见 AUDIT-ROUND-XX）」。

## 3. 顺带修了一处悬空交叉引用

`CredentialOrg.swift:241` 原句拿 `monthDeadlines` 作"保留未接"的例子，
而那个函数本轮已被删除（功能由 `KeyCalendarScreen` 更完整地实现）——
已改成不依赖具体例子的表述，并注明原类比失效的原因。

## 4. 结果：标记与清单终于一致

剩余 6 处 `【保留未接】` 标记，与 `RESERVED.md` 里的 6 条**逐一对应**：

```
CredentialOrg:312   recentUseCount
CredentialOrg:414   overlapWindows
CredentialOrgState:224  停用原因回显（markDisabled/disableMark）
RecordSearch:187    TimeWord
RecordSearchBuild:90     sameTypeCount
RecordSearchBuild:98     context
```

**这是一条可以定期复核的不变式**：`grep 【保留未接】` 的条数 == `RESERVED.md` 的行数。
不一致就说明有标记过期了，或有条目漏登记。

## 5. 方法论

**清理"标记"与清理"清单"是两件事，必须同时做。**

我前几轮只改文档，源码标记一直留着 —— 于是源码仍在向读者传递过期信息。
这两者的关系应当是：**源码标记是事实来源，文档清单是索引**；事实变了，两者都要改。
