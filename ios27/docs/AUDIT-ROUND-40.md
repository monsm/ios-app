# AUDIT-ROUND-40 · 第四十轮：自查上一轮的上限，发现它丢错了东西

> CI：仍在排队（`2d75c19` 是最后一条有回执的提交）。本轮**只本地提交、不推送**，
> 按用户「不做没必要的推送」的要求改为攒批。

## 1. 缺陷：回收站上限丢的是「最新」，不是「最旧」

第 23 轮我给回收站加了 100 条上限，实现是：

```
let dropped = list.suffix(from: maxItems)
list = Array(list.prefix(maxItems))
```

而 `list` 是**插入顺序**（旧 → 新）：`addPwds` 把新条目 `append` 在末尾。
所以 `suffix(from: maxItems)` 丢掉的正是**最新**的那些 ——

> 刚删掉的凭证被立刻丢弃，远古条目反而留着。
> 回收站彻底失去意义：用户想找回"刚才删错的那条"，它已经被裁掉了。

**这是我自己在第 23 轮引入的回归**，且当时没有测试覆盖顺序语义。

## 2. 修法

改成丢前缀：

```
let excess = list.count - maxItems
for item in list.prefix(excess) { SecretStore.remove(...) }
list = Array(list.suffix(maxItems))
```

并补 `testBinCapKeepsNewest`：写满 `maxItems + 1` 条后断言
**最旧的被裁、最新的还在**。

## 3. 方法论

**"有上限"只说了容量，没说淘汰策略。** 而淘汰策略错了，上限就从"保护"变成"加速丢失"。

可复用判据：**任何 `prefix`/`suffix`/`dropLast`/`removeFirst` 的裁剪，都要先确认数组的排列语义**
（插入顺序 / 时间顺序 / 排序后顺序），再决定裁哪一端；并且必须有一条测试锁住这个方向。

这也是我第二次栽在"数组语义"上（上一次是"最近一条"其实按别名排序，见 ROUND-31）。
