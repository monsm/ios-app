# AUDIT-ROUND-315 · 第 315 轮：SEC-03 写了三个页面，只做了两个

> CI：`79a4d49f` build 全绿（errors=0）。

## 1. 本仓自己写的判据

`AppModel.swift:153-154` 的注释（SEC-03）：

> 「凭证工作室 / **备份工作室** / 记录工作室 这些直接读 DB 的页面必须据此返回空集，
>  否则胁迫者能在空壳里看到并导出真实凭证。」

## 2. 落实情况

| 页面 | 有没有做 |
|---|---|
| 凭证工作室 | ✅ `CredentialStudioStores.all` / `stored` 都有 `if DB.isDecoy { return [] }` |
| 记录工作室 | ✅ `RecordSearch` 三处 `if DB.isDecoy` |
| **备份工作室** | ❌ **没有** |

## 3. 缺陷 A：空壳下列出全部备份文件

`BackupStudioScreen.reloadFiles()` 用 `FileManager.contentsOfDirectory` **直读 Documents 目录** ——
绕过了所有 `DB` 访问器，所以那句「直接读 DB 的页面要返回空集」在这里**根本没有生效的机会**。

| 后果 |
|---|
| 被胁迫者说「我这 App 里没东西」，界面上却列着十几份备份（名字带日期）—— 伪装当场穿帮 |
| 可以点「恢复」，用旧备份覆盖真实台账 |

**修**：`reloadFiles()` 开头加 `if DB.isDecoy { files = []; filesError = nil; keepCount = 0; return }`。

## 4. 缺陷 B：空壳下可以导入备份（覆盖真实数据）

`BackupStudioKit.restore` 是三条导入路径（旧备份页 / 工作室文本 / 换机迁移）的**唯一入口**，
它已有 `TrialGuard.isOn` 的写拦截，但**没有 decoy 拦截**。

判据与 TrialGuard 那条完全同源：**导入是整表改写，属于「写」**；而空壳模式的设计是「只读、只隐藏、不破坏」。

（这正是 `AUDIT-F` 里 N-01 的同类：「空壳点还原 → 用空台账覆盖真实台账」，当时只修了 `saveLedger` 一层。）

**修**：`guard !DB.isDecoy else { throw … }`，紧挨 TrialGuard 那道。

## 5. 顺带核实

`BackupKit.restoreAll` 已**只剩注释**（无定义）⇒ 恢复入口确实只有一条，拦一处即全覆盖 ✅。

## 6. 方法论

**仓库里最危险的不是「没写的规则」，而是「写了但只落实一半的规则」—— 它会让人以为已经覆盖了。**

| 状态 | 风险 |
|---|---|
| 没有 SEC-03 | 有人会去补 |
| **SEC-03 写了、三个页面只做了两个** | **第三个永远不会被想起来**（看起来「已处理」） |

判据：**每当遇到一条「A / B / C 都必须…」的注释，就把 A、B、C 逐个 grep 一遍 —— 这类清单的完成度几乎从来不是 100%。**
