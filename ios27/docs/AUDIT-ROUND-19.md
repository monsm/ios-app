# AUDIT-ROUND-19 · 第十九轮：文档里的数字已经和现实脱节

> CI：`232ed77` 已验证（build errors=0、金标 test_ok=1）；本轮提交待回执

## 1. 发现：README 的闸门表只列了 12 道，实际 20 道

README 里那节叫「十六道机器闸门」，表格只列 12 行 ——
缺了 `dynamictype` / `reducedmotion` / `crosprivate` / `workflow` /
`tests` / `feedback` / `modal` / `settings` 共 8 道，其中 4 道是最近几轮才加的。

也就是说：**读者拿这张表当闸门地图，会以为只有一半的检查在跑。**
新增的 `feedback`（命令失败必须说原因）与 `modal`（对话框不许抢 sheet）
恰恰是这轮审核里最有价值的两条，却在文档里不存在。

## 2. 还有三处陈旧数字

| 位置 | 写的 | 实际 |
|---|---|---|
| README 快速开始 | 「跑 9 道静态闸门」 | 20 道 |
| README 表示例输出 | 12 行、`contrast: 88 条断言`、`callsig2: 2082 处` | 20 行、`76` 条、`2091` 处 |
| README + COMPLETION「诚实的边界」 | 引 run `41219938500`（`a8416aa`，16 道）当"当前 CI 已通过" | 早已不是当前 HEAD |

最后一条正是 AUDIT-G 里 G-05 的那类问题：**钉死 run 号必然过期**，
过期后读者会把"某个旧提交是绿的"当成"现在是绿的"。

## 3. 修法

- 表补齐到 20 道（含每道判什么的简述）；标题改为「二十道机器闸门」；
- 示例输出换成**实跑结果**（不再手写）；
- `contrast` 那条不再钉死断言条数（色板一变就过期），改为描述"明暗各一套、数量现场解析"；
- 「诚实的边界」里**删掉钉死的 run 号**，改为给出自查命令：
  `git fetch origin && git show origin/ci-log:meta.txt`，并提醒看
  `build_ok / archive_ok / test_executed / test_ok`，**不要只看 errors=0**。

## 4. 防复发：workflow 闸门第 ④ 条判据

README 与 CI 工作流里声称的闸门数，必须等于 `allgates.js` 里 `GATES` 的真实数量。
已验证抓得住：把 README 标题改回「十六道」，闸门立刻红 ——

```
workflow: FAIL — 1 处
  README.md 声称 十六 道，实际 20 道（与 allgates.js 的 GATES 不一致）
```

## 5. 方法论

**文档里的每个数字都是一个会过期的断言。** 这轮修的不是"写错了一个数"，
而是"没有任何机制阻止它继续错"。所以除了改数字，还加了那条对账判据 ——
数字与来源不一致时本地就红，不必等读者发现。
