# AUDIT-ROUND-21 · 第二十一轮：清掉通知之后，没有把它装回来

> CI：`ffb0407` 已验证（build errors=0、build_ok=1）；本轮提交待回执

## 1. 自查上一轮的改动，发现我造成了新的静默丢失

上一轮加了「进空壳就清掉整族通知」（`cancelAllForDecoy`）。
本轮先问了一个问题：**退出空壳之后，这些提醒会回来吗？**

答案是**不会**。全仓搜 `rescheduleAll` / `rebuildAlerts` / 任何全量重排入口 —— 零命中；
`scheduleAlerts` 的调用点只有一个：凭证编辑页在用户改提醒开关时调它。

也就是说我上一轮的修复会造成：

> 用户用胁迫码进空壳 → 通知被清 → 退回正常模式 →
> **所有凭证的到期提醒永久消失**，直到他逐条重新保存提醒开关。
> 而界面照旧显示"已排程"，实际一条都不会响。

这和我这段时间一直在修的缺陷是同一类：**静默的功能丢失**。

## 2. 修法

新增 `CredentialOrg.rescheduleAllAlerts()`：遍历所有锁的凭证，
只对**用户确实开过档位**（`a.day || a.d3 || a.d1 || a.h24 || a.h2`）的条目重新排程，
避开永久有效的 2118 档。逐条走 `scheduleAlerts`，因此同样经串行队列。

调用点：`AppModel.reload` 里用 `wasDecoy` 记住进入前的状态，
**只在真的从空壳退出来的那一次**重建（`reload` 会被频繁调用，不能每次都全量重排）。

## 3. 防复发：privacy 闸门第 13 条

「清了通知就必须有重建路径」—— 检查有 `cancelAllForDecoy` 的文件里是否也有
`rescheduleAllAlerts`。已验证抓得住：

```
privacy: FAIL — 1 处回归
  Shell/AppModel.swift:1 — 清空通知后没有重建路径
    → 退出空壳时调用 CredentialOrg.rescheduleAllAlerts()
```

## 4. 方法论（本轮唯一值得记的）

**每次"清掉某样东西"的修复，都要立刻问一句：它该什么时候回来？**

- 清通知 → 何时重建？（本轮）
- 清 waite/cache（`dropKeychainCache`）→ 何时重新填充？（已由下次读取自然恢复）
- 清明文（`ledgerForPlist` 抹 pwd）→ 何时回填？（`ledgerWithSecrets` 读时回填）

前两个是我自己写的，第三个是更早轮次写的。**只有第一个漏了"回来"那一半。**
所以这条要作为固定检查项：清理动作必须配一个恢复动作，或明确写出"不需要恢复"的理由。
