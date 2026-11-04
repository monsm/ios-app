# AUDIT-ROUND-274 · 第 274 轮：合并成员后，凭证仍显示旧归属

> CI：build `fb152c1` ✅ / golden `6c20d1c` ✅；`77b60ca`（签名改动）/ `d287a34` / `cc10e73` 排队中。

## 1. 扫描方法

找所有 `DB.saveLedger(` 的调用点，看它后面 8 行内有没有 `reloadKeys` / `reload(` —— 没有的逐个判定。

18 处命中里，13 处在 `StoreLedger.swift`（DB 层自身，调用方负责刷新 ✅），
2 处已有 `app.reload(...)` ✅，剩 3 处需要人工判定，其中 **2 处是真缺陷**。

## 2. 缺陷 A：成员合并后 `app.keys` 没重建

    let moved = MemberMergeKit.merge(primaryID:secondaryID:)   // 把凭证 owner 改判给主档
    app.reloadMembers()                                        // ← 只重建了成员

`app.keys` 里每条 `KeyItem.owner` 仍是**旧成员**，于是凭证页显示旧名字，
直到别的原因触发一次 `reloadKeys`（切页 / 加凭证 / 重启）。

修法：改调 `app.reloadKeys()` —— 它内部已顺带 `reloadMembers()`（Round 244），一个就够。

## 3. 缺陷 B：撤销新建成员后完全不刷新

    app.members.removeAll { $0.id == id }
    DB.removeMember(id)
    …
    router.request(.tab(.household))      // ← 没有任何 reload

向导第 4 步可能已生成**归这名成员**的临时码；撤销建档后那条凭证成了孤儿归属，
而 `app.keys` 没重建 ⇒ 一直显示旧归属。补 `app.reloadKeys()`。

## 4. 方法论

**「谁改了数据」和「谁负责刷新界面」之间没有编译器约束 —— 只能靠一次系统性 grep。**

| 检查手法 | 效果 |
|---|---|
| 逐个功能手动试 | 漏（要恰好想到合并/撤销这两条路径） |
| **grep 写入口 + 看邻近有没有刷新** | ✅ 一次覆盖全部 18 处 |

判据：**任何 `save*` / `remove*` 的写函数，都要问「它改的那份数据，界面是从哪个投影读的，那个投影谁负责重建」。**
本仓 `app.keys` 是凭证的唯一投影，所以凡是动台账的地方都必须过 `reloadKeys`。
