# AUDIT-ROUND-108 · 第一百零八轮：CI 告警里藏着两个真缺陷

> CI：`b811b08` 全绿（build + golden）。本轮本地提交。

## 0. 起点：`WARNINGS.md` 说「0 条告警」，实际是 6 条

我上一轮核对文档数字时，`WARNINGS.md` 声称「当前构建 `: warning:` **0 条**」。
实际数当前 CI 的 `build.log`：

```
当前 CI build.log 源码告警数: 6
```

所以那句话是**过期**的。而这 6 条里有两条是真缺陷 —— **21 道闸门全绿，编译器一抓就准**。

## 1. 真缺陷一：`return true` 之后有 4 行死代码（`AppLock.swift:125`）

```swift
guard !DB.hasDuressCode() else { return false }
unlocked = true
decoy = false
return true          // ← 到这里就返回了
failStreak = 0       // ← 以下四行永远不执行
cooldownUntil = 0
DB.store.setInt(failStreakKey, 0)
DB.store.setDouble(cooldownKey, 0)
```

**后果**：刷脸解锁成功**从不清失败计数与冷却**。于是：

| 用户操作 | 期望 | 实际 |
|---|---|---|
| 密码输错几次 → 进冷却 | 冷却生效 | ✅ |
| 改用刷脸，成功解锁 | 冷却应清除 | ❌ **冷却仍在** |
| 立刻再刷脸 | 应可解锁 | ❌ 被冷却拒绝 |

用户看到的是「刚才明明刷脸成功了，现在又要等」。

**这是我自己的回归** —— 2026-11-01 加胁迫码 guard 时，我把清理代码留在了 `return` 之后。

修法：把四行清理移到 `return true` 之前。

## 2. 试过给它做闸门 —— 失败，已回退

写了 `Gates/deadcode.js`（判"`return` 之后还有可执行语句"）。跑出来 **130 处假红**：

```
App\Design\Components\Ledger.swift:31 — `return` 之后还有可执行语句
```

真实代码是：

```swift
return [
    LedgerEntry(id: "s1", ...),    // ← 多行数组字面量的第二行
    ...
]
```

**根因**：`return` 的表达式可以跨行（数组/字典/多行字符串/链式调用）。
要判准必须解析表达式边界 —— 那是语法树的工作，不是行扫描能做的。

按本段已定的原则（**假红多的闸门不做**，见 ROUND-70/96 的回退），**已删除该闸门**。

## 3. 真缺陷二：4 条 Sendable 捕获告警

```
CredentialOrgState.swift:53: capture of 'done' with non-Sendable type '() -> Void' in a '@Sendable' closure
CredentialOrgState.swift:128 / :166 同上
CredentialOrgState.swift:166: sending 'done' risks causing data races; this is an error in the Swift 6 language mode
```

`enqueue` 的回调参数类型是 `@escaping () -> Void`，而它会被 `UNUserNotificationCenter`
的 `@Sendable` 闭包捕获。修法是把参数类型标成 `@escaping @Sendable () -> Void` ——
**纯类型标注，不改行为**（该回调只被异步 API 调用，不碰任何隔离状态）。

## 4. 方法论

**编译告警是闸门覆盖不到的那一层，而它里面确实会藏真缺陷。**

| 层 | 谁能发现 | 本段战绩 |
|---|---|---|
| 形状 / 命名 / 计数 | 21 道闸门 | 大量 |
| **类型 / 可达性 / 并发** | **编译器** | **actor 隔离（ROUND-89）、参数顺序（ROUND-54）、本轮死代码 + Sendable** |

所以「本地全绿」永远不等于「没问题」—— 这条我已经验证过 4 次。

**每次 CI 回执都该读 `build.log` 里的 `: warning:`，而不只是 `errors=` 与 `build_ok`。**
我这几轮一直只读那两行，直到这轮才去看告警 —— 这是我的流程漏洞。
