# AUDIT-ROUND-105 · 第一百零五轮：覆盖图自己也在过期

> CI：`4ea2c9f` 已验证（build + gates 全绿）；`530fcfa` 待回执。

## 1. 缺陷：`AUDIT-COVERAGE.md` 里有 4 处过期数字

本轮做的是"核对现状"而不是"找新缺陷"，结果发现：

| 位置 | 写的 | 实际 |
|---|---|---|
| §1 交付与 CI 行 | 20 道闸门 | 21 |
| §2 自动化保证 | `-> 20 道闸门全部通过` | 21 |
| §2 测试规模 | 315 条断言 | 317 |
| §4 怎么用这份图 | `§5 的 20 道判据` | 21 |

**根因**：`Gates/workflow.js` 的闸门数对账只覆盖 **4 个文件**（README / CI 工作流 /
ARCHITECTURE / COMPLETION），**AUDIT-COVERAGE 不在其中**。

这份覆盖图是我这段审计最重要的产出之一（"哪些查过、哪些没查"），而它的数字没人盯 ——
所以它从"权威索引"退化成"过期快照"。

## 2. 修法

**（a）** 改掉 4 处数字；
**（b）** 把 `AUDIT-COVERAGE.md` 加进 `workflow.js` 的对账目标（第 5 个文件）：

```js
[path.join(ROOT, 'docs', 'AUDIT-COVERAGE.md'), /-> ([一-鿿0-9]+)\s*道闸门全部通过/],
```

已验证：把覆盖图改成「20 道」立刻判红 ——

```
workflow: FAIL — 1 处
  docs\AUDIT-COVERAGE.md 声称 20 道，实际 21 道（与 allgates.js 的 GATES 不一致）
```

## 3. 这是同一个教训的第 N 次

本段已经修过 README（12→20）、ARCHITECTURE（9→20）、COMPLETION（11→20），
每次都说"这次闭环了"，而每次都有**下一个文件**不在对账名单里。

| 轮次 | 修的文件 | 之后新增对账 |
|---|---|---|
| 19 | README | +README |
| 24 | ARCHITECTURE | +ARCHITECTURE |
| 25 | COMPLETION | +COMPLETION |
| **105** | **AUDIT-COVERAGE** | **+AUDIT-COVERAGE（第 5 个）** |

## 4. 方法论

**"文档里的数字"要一次性全找出来，而不是每次修一个。**

正确做法（这轮才真正做了）：**先 `grep` 出所有"声称了闸门数/断言数"的文件，
再一次性全部纳入对账** —— 而不是"我记得改过哪几个"。

现在的对账名单是 5 个文件。下一次如果还有第 6 个，说明我这次仍然没有"全找一遍"。
