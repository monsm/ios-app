# AUDIT-ROUND-65 · 第六十五轮：星标也不进备份，以及 `callsig2` 这次真的抓到了我

> CI：`b00ad23` 已验证；`2d6a02d` / `f5c5238` 待回执。本轮本地提交。

## 1. 缺陷：用户标出来的「最常用的那几条」换机就没了

星标存在 `kf_cstar_ui_<mac>`（`CredStarStore`，元素形如 `p:<alias>` / `f:<batch>`）。
查备份链路：**一次都没有**（与上一轮修的 `kf_calert_` 同族）。

后果不像"丢凭证"那么严重，但性质一样：**用户手动标记的信息静默消失**。
凭证还在，可"哪几条最重要"这个判断没了，而用户只能靠自己回忆重建。

## 2. 修法：一个字段要改**四处**才真的生效

这是本仓备份的固定套路（ROUND-52 吃过一次亏：只改结构体等于没做）：

| # | 位置 | 动作 |
|---|---|---|
| 1 | `BackupBundle.Device.Meta` | 加 `var stars: [String]?` |
| 2 | `BackupCanonical.metaValue` | emit `stars`（否则导出文本里没有它） |
| 3 | `BackupKit.collectAll` | 从 `CredStarStore.all(mac)` 取值 |
| 4 | `BackupStudioKit.restore` | 写回 |

## 3. `callsig2` 这次真的抓到了我

第 4 步我写了 `CredStarStore.set(mac, Set(st))` —— 而 `CredStarStore` **只有 `toggle`，没有 `set`**。

`callsig2` 立刻判红：

```
Engine/BackupStudioKit.swift:459  CredStarStore.set —— CredStarStore 没有成员 set
```

这值得记，因为我在 ROUND-37 说过它的盲区（**跳过所有 `类型.方法(...)` 调用**）。
但这次它抓到了 —— 说明它的**静态成员表**检查（"类型 X 有没有成员 Y"）与"调用实参比对"
是两条不同的路径：前者能覆盖点号调用，后者不能。

我之前把"点号调用全跳过"当成了"callsig2 对点号调用完全无效"，这个概括过于粗糙。
准确说法：**它不校点号调用的实参，但会校点号调用的成员是否存在。**

## 4. 补的方法

给 `CredStarStore` 加 `set(_:_:)`（整表写入），语义与 `RecordOverlay.setNotes` 一致：
备份恢复用整表，不用逐条 toggle。

## 5. 方法论

**同一轮里既发现缺陷、又被自己的工具拦下一次 —— 这是最好的组合。**
如果 `callsig2` 没拦住，这处会一直绿到 CI，然后让我再花一轮去查"为什么星标没恢复"。
