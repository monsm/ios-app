# AUDIT-ROUND-71 · 第七十一轮：已删成员的指纹行，留了个悬空分隔符

> CI：`d62c9c8` 已验证（errors=0、build_ok=1）；`2cf4700` / `6801fa3` 刚推送。本轮本地提交。

## 1. 缺陷

`CredentialStudioScreen` 的指纹行：

```swift
Text("#\(fp.batch) · \(CredentialOrg.ownerName(fp.owner))")
```

`ownerName` 对**已删除的成员**返回空串（`guard let m = DB.member(id) else { return "" }`）——
而 `DB.removeMember` 会把名下凭证的 `owner` 清空、但**指纹的 `owner` 未必同步**（跨锁场景）。

于是这一行会显示成 `"#1 · "` —— 一个**悬空的分隔符**。用户看不出是"没有归属"还是"渲染出错"。

## 2. 同类排查：只有这一处漏了兜底

全仓 `ownerName(...)` 共 5 个调用点：

| 调用点 | 是否兜底 |
|---|---|
| `namingTemplate`（918 命名模板） | `if who.isEmpty { who = "未归属" }` |
| `fpNameSuggestion`（指纹名建议） | `who.isEmpty ? "指纹·" + base : ...` |
| `displayPwd`（凭证显示名） | `if !o.isEmpty { return ... }` |
| 排序比较（`ordered.sorted`） | 空串参与比较是安全的（只是排在最前） |
| **指纹行 `Text(...)`** | **无兜底 ← 本轮修复** |

## 3. 修法

```swift
let who = CredentialOrg.ownerName(fp.owner)
return who.isEmpty ? "指纹 #\(fp.batch)" : "#\(fp.batch) · \(who)"
```

## 4. 方法论

**"返回空串"的辅助函数，每个调用点都要自己决定空串怎么显示。**
这靠"记得检查"是不可靠的 —— 本轮就是靠 `grep ownerName(` 列全 5 处才发现的。

可复用判据：**一个会返回空串的函数，它的调用点清单应当被当成"待检查清单"**，
逐个确认空值分支；而不是假设"大家都处理了"。

（顺带：这也解释了我为什么连续几轮都在用 `grep 标识符` 这个动作 —— 它比"记得"有效得多。）
