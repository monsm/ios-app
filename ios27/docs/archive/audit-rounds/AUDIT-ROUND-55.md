# AUDIT-ROUND-55 · 第五十五轮：把「下限当上限」做成闸门，它立刻抓到一处我漏的

> CI：`3864e54`（实参顺序修复）已推送，回执未到。本轮本地提交。

## 1. 上一轮我改完 8 处就收手了，但规则能抓出第 9 处

上一轮把 8 处 `.frame(height: V.H.action)` 改成 `minHeight`。本轮按计划加闸门判据：

> `a11y` 第 ⑥ 条：`.frame(height: V.H.*)` / `.frame(width: V.H.*)` 一律判红。

写完后跑一遍 —— 立刻红了一处我**没找到**的：

```
App/Design/Components/Primitives.swift:92
  下限令牌被当作固定尺寸（大字号会裁字）：改用 minHeight/minWidth
```

那是 `ChipRow` 的 chip：`.frame(height: V.H.chip)`。已改 `minHeight`。

## 2. 双向验证

- 现状（`minHeight`）→ 绿；
- 改回 `.frame(height: V.H.chip)` → 红。

## 3. 方法论

**"我手动改了一遍"和"有规则守着"是两个不同的完成度。**
我上一轮改完 8 处时以为已经穷尽（我 grep 过 `V.H.action`），
但 `V.H.chip` 是**另一个令牌**，grep 那个词根本不会命中它。

这正是闸门的价值：它按**模式**（`V.H.*` 被用作固定尺寸）判，而不是按我记得的某个具体名字判。

判据：**手动修完一类问题时，写规则的收益往往大于继续手动找下一处** ——
因为规则覆盖的是"这一类"，而我脑子里只有"我想到的那几个"。
