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
>
> 接线后请从本表删掉该行，并去掉代码里的标记。

| # | 符号 | 文件 | 功能 | 接线点（注释里写的） | 接线成本 |
|---|---|---|---|---|---|
| 1 | `markDisabled(_:kind:keys:label:via:)` | `CredentialOrg` | 停用原因**写入** | 停用时采集原因（与 #2 成对） | 中（要与 #2 成对） |
| 2 | `disableMark` / `disableMarkText` | `CredentialOrgState` | 停用原因**读取与回显** | 凭证详情页的停用行 | 中（同 #1） |
| 3 | `monthDeadlines(_:year:month:)` | `CredentialOrgState` | 月历到期角标 | 凭证页月历视图 | 高（要建月历视图） |
| 4 | `dayDeadlines(_:_:)` | `CredentialOrgState` | 某天到期凭证列表（#3 配套读侧） | 同上，一起接 | 高（同 #3） |
| 10 | `TimeWord.word(_:)` | `RecordSearch` | 自然时段词（清晨 / 上午 / 午间…） | 记录组头与行级小字 | **高**（按小时 vs 按天分组，粒度不匹配） |
| 11 | `sameTypeCount(mac:type:exceptKey:)` | `RecordSearchBuild` | 同类型记录计数（「本周第 N 次」） | 记录详情 | 中（需先给 `LedgerEntry` 加 `idxRaw`，当前结构拿不到 exceptKey） |
| 12 | `context(mac:aroundKey:minutes:n:)` | `RecordSearchBuild` | 告警前后 10 分钟同锁记录（前 3 / 后 3） | 记录详情「前后事件」区 | 中（要加一个区块） |
| 14 | `recentUseCount(_:pwdAlias:days:)` | `CredentialOrg` | 近 N 天使用次数（529 组尾统计） | 凭证详情/列表行尾（文案带"约"） | 中（要扫日志，且文案要带"约"） |
| 17 | `overlapWindows(_:from:to:owner:excluding:)` | `CredentialOrg` | 租期重叠检测（327） | 凭证创建页时间段字段下方 | 中（要加时间窗校验与提示） |

> 第 13 条（`removeSearchHistory`）已于 2026-11-01 **接线**：搜索历史标签支持长按删除（`KeysScreen`）。
> 第 14–16 条是 2026-11-01 用"可达性"扫描（而非引用计数）找出来的：它们对外零引用，
> 但实现完整、有需求编号，属**保留未接**，已在源码处加 `【保留未接】` 标记。

> 同批被**删除**的（真死，不是保留）：`MemberHub.aliasName`（被 `CredentialOrg.ownerName` 取代）、
> `MemberHub.display`+`unnamedLabel`+`doubleLine`（封闭死簇）、`BatteryCare.facePct`
> （三个界面都直接用 `displayPct`）。

## ⚠ 2026-11-01 的四次误判（必须记住）

这份清单初版有 **4 条是错的** —— 它们标着 `【保留未接】`，但**界面已经在用**：

| 符号 | 实际调用点 |
|---|---|
| `weakReason(_:)` | `KeyCreateParts.swift:192`（新密码弱口令提示） |
| `strictBytes(_:)` | `ZKProtocol.swift` **7 处**（协议帧解析）+ 5 条测试 |
| `batchPrefixNote(...)` | `CredentialStudioScreen.swift:491`（批量前缀备注） |
| `recentExcerpts(_:_:)` | `MemberOpsScreen.swift:282`（成员活跃度摘录） |

**根因**：我是按"注释里写了 `【保留未接】`"就采信的，没有逐个验证调用点。
而标记本身会**过期** —— 接线的人忘了去掉标记，标记就成了假信息。

### 判据修正（这条最重要）

> **`【保留未接】` 标记只是一个"线索"，不是证据。**
> 判定一个函数是否真的零调用，**必须 grep 它的名字并逐个看命中处是定义、注释还是真调用**。

这条判据同样适用于别处：本仓所有"注释声称"的东西都要这样验（这正是本段前几十轮在做的事，
只是这次我自己在文档里犯了同一个错）。
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
