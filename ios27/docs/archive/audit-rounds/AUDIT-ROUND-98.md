# AUDIT-ROUND-98 · 第九十八轮：按修正后的判据复核剩余 9 条，并再判掉一条

> CI：`e5c4c04` 已验证（errors=0、build_ok=1）；`efdc4b2` 刚推送。本轮本地提交。

## 1. 用「真 grep 验证命中性质」复核剩余 9 条

上一轮我改的判据是：**标记只是线索，必须逐个看命中处是定义、注释还是真调用**。
按此复核：

| 符号 | 命中性质 | 结论 |
|---|---|---|
| `markDisabled` | 定义 + 1 处注释提及 | 真零调用 ✅ |
| `disableMark` / `disableMarkText` | 定义 + 注释（其余是 `DisableMark` 结构体本身） | 真零调用 ✅ |
| `monthDeadlines` / `dayDeadlines` | 定义 + 注释 | 真零调用 ✅ |
| `TimeWord.word` | 仅 enum 定义 | 真零调用 ✅ |
| `sameTypeCount` | 仅定义 | 真零调用 ✅ |
| `context(mac:aroundKey:…)` | 仅定义（其余 20+ 命中是 `CGContext` / `RouteContext` / `.contextMenu` 等**同名异物**） | 真零调用 ✅ |
| `recentUseCount` / `overlapWindows` | 仅定义 | 真零调用 ✅ |

**清单现在干净了。**

（顺带说明：`context` 这个名字的 grep 结果里 20+ 条几乎全是同名异物 ——
这也是为什么"看命中性质"比"数命中数"可靠：**数命中数会把同名异物算进去**。）

## 2. 再判掉一条：`sameTypeCount` 从「低」改「中」

上一轮我把它标成「**低**（加一行，与行数据同粒度）」。这轮真去接时发现：

```swift
static func sameTypeCount(mac: String, type: Int, exceptKey: String) -> SameCount
```

它需要 `exceptKey`（锁端日志的 `idxRaw`），而记录详情页拿到的 `LedgerEntry` **只有 `rawType`、没有 `idxRaw`**。

也就是说接线前要先给 `LedgerEntry` 加一个字段、并在构建处填进去 —— 与上一轮 `pwdAgeDays` 同类的结构改动。

**判定改为「中」，本轮不接。**

## 3. 方法论

**「低成本」的评估必须在"看过接线点的数据结构"之后才能定。**

我上一轮标「低」时只看了"接线点在记录详情"这件事，没看**那个函数要什么参数、页面有没有**。
两轮下来连续两条（`pwdAgeDays`、`sameTypeCount`）都因此低估 —— 说明这不是偶发。

所以成本评估的正确顺序是：

1. 看接线点（在哪一页）；
2. **看函数签名要什么参数**；
3. **看那一页手里有没有这些参数**；
4. 都没有才是"低"。
