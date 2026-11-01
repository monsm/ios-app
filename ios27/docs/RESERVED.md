# 待接功能清单（RESERVED）

> 本仓有一批「**有意保留、尚未接线**」的函数：实现完整可用，但**没有任何调用点**。
> 它们不是死代码（不是遗忘），而是「用户当时没选，先留着」—— 删掉会删掉将来要接的东西。
>
> 问题是这些标记散在 8 个文件的注释里，**没有任何地方汇总**。下一个人（或下一个我）看到零调用，
> 只会误判成两种：当死代码删掉，或以为已经接上了。
>
> 判据：注释里带 `【保留未接】`。快照 2026-11-01。
>
> **编表时我按记忆写符号名，两个写错了**（`weakPasswordHint` / `strictHex` —— 真名是
> `weakReason` / `strictBytes`）。所以本表以**符号名**为准（能被 grep 验证），行号只作参考。
>
> 接线后请从本表删掉该行，并去掉代码里的标记。

| # | 符号 | 文件 | 功能 | 接线点（注释里写的） |
|---|---|---|---|---|
| 1 | `markDisabled(_:kind:keys:label:via:)` | `CredentialOrg` | 停用原因**写入** | 停用时采集原因（与 #2 成对） |
| 2 | `disableMark(_:kind:key:)` / `disableMarkText(_:kind:key:)` | `CredentialOrgState` | 停用原因**读取与回显** | 凭证详情页的停用行 |
| 3 | `monthDeadlines(_:year:month:)` | `CredentialOrgState` | 月历到期角标 | 凭证页月历视图 |
| 4 | `dayDeadlines(_:_:)` | `CredentialOrgState` | 某天到期凭证列表（#3 的配套读侧） | 同上，一起接 |
| 5 | `weakReason(_:)` | `CredentialOrgState` | 弱口令判据（少于 6 位 / 全同位 / 连续） | 新密码输入时即时提示 |
| 6 | `batchPrefixNote(_:pwdAliases:fpBatches:prefix:)` | `CredentialOrgBatch` | 批量加同一前缀备注 | 凭证页多选菜单 |
| 7 | `strictBytes(_:)` | `HexKit` | 严格十六进制解析（坏输入显式失败） | 协议解析路径（现用宽容版 `bytes()`） |
| 8 | `recentExcerpts(_:_:)` | `MemberHub` | 成员详情「最近记录摘录」 | 成员页空档补位 |
| 9 | `CommuteLabel.tag(date:hour:)` | `RecordSearch` | 通勤时段标签（工作日 7-9 / 17-19） | 记录页时段分组 |
| 10 | `TimeWord.word(_:)` | `RecordSearch` | 自然时段词（清晨 / 上午 / 午间…） | 记录组头与行级小字 |
| 11 | `sameTypeCount(mac:type:exceptKey:)` | `RecordSearchBuild` | 同类型记录计数（「本周第 3 次撬锁」） | 记录详情 |
| 12 | `context(mac:aroundKey:minutes:n:)` | `RecordSearchBuild` | 告警前后 10 分钟同锁记录（前 3 / 后 3） | 记录详情「前后事件」区 |

| 14 | `recentUseCount(_:pwdAlias:days:)` | `CredentialOrg` | 近 N 天使用次数（529 组尾统计） | 凭证详情/列表行尾（文案带"约"） |
| 16 | `clearAutocal(_:)` | `AutoOpenKit` | 清掉某把锁的自动校准值 | 自动开门设置页的「重新校准」 |
| 17 | `overlapWindows(_:from:to:owner:excluding:)` | `CredentialOrg` | 租期重叠检测（327） | 凭证创建页时间段字段下方 |

> 第 13 条（`removeSearchHistory`）已于 2026-11-01 **接线**：搜索历史标签支持长按删除（`KeysScreen`）。
> 第 14–16 条是 2026-11-01 用"可达性"扫描（而非引用计数）找出来的：它们对外零引用，
> 但实现完整、有需求编号，属**保留未接**，已在源码处加 `【保留未接】` 标记。

> 同批被**删除**的（真死，不是保留）：`MemberHub.aliasName`（被 `CredentialOrg.ownerName` 取代）、
> `MemberHub.display`+`unnamedLabel`+`doubleLine`（封闭死簇）、`BatteryCare.facePct`
> （三个界面都直接用 `displayPct`）。
## 怎么判定「保留未接」而不是「死代码」

| 特征 | 保留未接 | 死代码 |
|---|---|---|
| 注释里写了**接线点**（"接到哪一页的哪一块"） | 有 | 没有 |
| 有 `【保留未接】` 标记与日期 | 有 | 没有 |
| 实现完整（有边界处理、有注释解释为什么这么算） | 有 | 常常只有个壳 |

按这三条，上面 12 条全部成立；已清理的 6 处（`quota` / `DiagFlags.silent` / `Advice` /
`DiagOp`+`DiagOps` / `selfCheckWarning` / `Diff`）**一条都不符合**。

## 一条纪律

**新增「保留未接」函数时，必须同时把接线点写进注释，并在本表加一行。**
否则过几个月，它和一个真正的死声明没有任何区别 —— 而"有没有接线点"是唯一能事后区分两者的线索。
