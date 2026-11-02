# AUDIT-ROUND-276 · 第 276 轮：工作室批量动作后的陈旧问题 —— **审过，无缺陷**

> CI：`65952dd` build ✅ / `1f84bca` golden ✅（82）；`d287a34`（补 `try`）排队中。

## 1. 怀疑的缺陷

`CredentialStudioScreen` 的批量动作（停用 / 延期 / 前缀备注）收尾只做 `tick += 1`：

    CredentialOrg.batchDisable(studioMac, …)
    studioOutcome = …
    tick += 1          // ← 只重绘工作室自己那张表（它直接读 DB）

而它**从不**调 `app.reloadKeys()`。于是一个很合理的担心是：
批量停用 5 条 → 返回凭证页 → `app.keys` 没重建 → **列表还是停用前的样子**。

## 2. 核对结果：不是缺陷

`KeysScreen` 第 93 行本来就有：

    .task { await app.reload(refreshStatus: false) }

`.task` 随视图出现而运行（与 `onAppear` 同一时机），从 push 出来的工作室返回时**会再跑一次** ⇒
凭证页每次进来都是全量重建（`reloadKeys` + `reloadMembers` + `reloadEntries`）✅。

家页同样有 `.task { await app.reload(...) }` ✅。

所以**两条投影都覆盖到了**，工作室不需要额外通知 —— 少一次通知反而少一处要维护的耦合。

## 3. 一次差点犯的错

我本来准备在 `KeysScreen.onAppear` 里加一行 `app.reloadKeys()`。
读文件时才发现 `.task` 就写在第 93 行 —— **加了就是重复刷新**。

## 4. 方法论

**「某处没通知」的怀疑，要先确认「接收方会不会自己来取」。**

| 刷新模型 | 特征 |
|---|---|
| push 通知 | 写方负责调 `reload*` |
| **pull 刷新（`.task` / `onAppear`）** | **读方每次出现自己取** |

判据：**判断「写完要不要通知」前，先看读方有没有 `onAppear` / `.task` 拉取 —— 有就不要再加推。**
（本轮若直接加，就是给一条已经有 pull 的链路再加 push，纯冗余。）
