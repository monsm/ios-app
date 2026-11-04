# AUDIT-ROUND-288 · 第 288 轮：修我自己上一轮的红灯（`[#ActorIsolatedCall]`）

> CI：`d54449f` **build errors=2** —— 是我 Round 282 那个「合并成员时迁手机钥匙」的修复引入的。

## 1. 错误原文

    App/Engine/MemberMergeKit.swift:35:26: error: call to main actor-isolated static method
    'reassignMember(from:to:)' in a synchronous nonisolated context [#ActorIsolatedCall]

## 2. 原因

| 事实 | 说明 |
|---|---|
| `MobileKeyService` 是 `@MainActor` 枚举 | 第 53-54 行 |
| 我新加的 `reassignMember` 因此也是主 actor 隔离 | 自然结果 |
| `MemberMergeKit.merge` 是**非隔离**静态函数 | 存在已久的签名 |

于是「非隔离 → 主 actor」的同步调用被 Swift 6 严格并发拒了。

## 3. 修法：给调用方加 `@MainActor`（而不是硬把被调方改成 nonisolated）

先查调用点：`MemberMergeKit.merge` **唯一调用者**是 `MemberMergeSheet.merge()` —— 一个 View 方法，本来就在主 actor 上。
所以给 `merge` 标 `@MainActor` **不改变任何调用方式** ✅。

反方向（把 `reassignMember` 标 `nonisolated`）做不到：它要调 `rawList` / `save`，
那两个都在 `@MainActor` 枚举里 —— 该枚举里唯一一个 `nonisolated` 的 `purgeSecretsForDevice` 注释里就写明了这条约束
（「不调 `rawList`：它在本 `@MainActor` 枚举里，从 nonisolated 上下文调会编译不过」）。

## 4. 方法论

**跨隔离调用有两个方向，「往哪边加」取决于哪一端的约束更硬 —— 穷举端（枚举/工具类）比调用端硬。**

| 方向 | 何时可行 |
|---|---|
| 给被调方标 `nonisolated` | 它**不碰**任何主 actor 状态（本仓 `purgeLocalArtifacts` / `purgeSecretsForDevice` 就是这种） |
| **给调用方标 `@MainActor`** | **被调方依赖主 actor 状态；且调用链本来就在主线程**（本轮） |

判据：**改隔离前先 grep「谁在调它」——只有一个主线程调用点时，加 `@MainActor` 是零成本；
有多个跨线程调用点时，才值得深入排查被调方能否 nonisolated。**

另记：`allgates` 与 `swiftparse` 都是**文本级**闸门，抓不到 actor 隔离错误 —— 这类只能靠 CI。
