# AUDIT-ROUND-110 · 第一百一十轮：我的修复只把告警从 6 降到 1

> CI：`86f4617` **已验证**（`errors=0`、`build_ok=1`、`archive_ok=1`）。
> 本轮本地提交。

## 1. 验证结果：6 → 1，不是 0

上一轮我说"下一轮看告警是否从 6 降到 0"。实际是 **1**：

```
App/Engine/CredentialOrgState.swift:72:22: warning:
  passing non-Sendable parameter 'job' to function expecting a '@Sendable' closure
```

**这条是我自己上一轮引入的。** 我只把内层回调 `done` 标成了 `@Sendable`，
而外层 `job` 也被存进队列、并在 `Task { @MainActor in … }` 里被调用 —— 它同样必须是 `@Sendable`。

## 2. 修法：三个类型要一起改

| 位置 | 原 | 改后 |
|---|---|---|
| `enqueue` 参数 | `@escaping (@escaping () -> Void) -> Void` | `@escaping @Sendable (@escaping @Sendable () -> Void) -> Void` |
| `notifyQueue` 元素类型 | `[(@escaping () -> Void) -> Void]` | 同上（与参数一致） |
| `runNextNotify` 局部 | `((@escaping () -> Void) -> Void)?` | 同上 |

三处必须一致，否则类型不匹配 —— **这是"改一个类型标注要顺着数据流走一遍"的典型**。

## 3. 闭包捕获的安全性核查

三处 `enqueue { done in … }` 捕获了什么？

| 位置 | 捕获 | 是否 Sendable |
|---|---|---|
| `cancelAlerts(id:)` | `id: String` | ✅ |
| `cancelAllForDecoy()` | 无（调静态函数） | ✅ |
| `scheduleAlertsOrdered(id:p:a:mac:)` | `String` / `LedgerPwd` / `CredAlert` / `String` | ✅（三个都是纯值类型：`Int`/`String`/`Bool`） |

`LedgerPwd` 与 `CredAlert` 都是 `Codable` 的纯值 struct，隐式满足 `Sendable`。
所以标 `@Sendable` 是**安全的**，不会引入数据竞争。

## 4. 方法论

**"修掉 N 条告警"要复核到 0，而不是"明显变少了"。**

如果我上轮只看到"6 条变 1 条"就收工，这条新告警会一直留着 —— 而它是我引入的，
且在 Swift 6 下同样是 error。

另一条：**改类型标注要顺着数据流走**。`@Sendable` 不是加在一个参数上就完事 ——
同一个闭包类型出现在参数、容器元素、局部变量三处，三处都要改。
这与 ROUND-89 的 actor 隔离是同一类教训（`nonisolated` 只解决入口，函数体内每个调用都要检查）。
