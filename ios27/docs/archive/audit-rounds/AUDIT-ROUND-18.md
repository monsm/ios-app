# AUDIT-ROUND-18 · 第十八轮：第 3 轮那个"串行化"其实从未生效

> CI：build 已验证到 `d70cf14`（errors=0）；本轮提交待回执

## 1. 真缺陷：通知排程是分离异步，串行队列形同虚设

第 3 轮我修 SEC-32 时加了「删旧 / 排新 / 取消」的串行队列，理由是
*两条独立异步序列看不到对方中间态*。本轮复核发现：

```swift
// CredentialOrg.addCalendar（旧）
static func addCalendar(id: String, date: Date, title: String, body: String) {
    ...
    Task {                                   // ← 分离异步，不等待
        try await UNUserNotificationCenter.current().add(req)
    }
}
```

而队列的完成信号在 `scheduleAlertsNow` **返回后**立刻发出：

```swift
Task { @MainActor in
    scheduleAlertsNow(...)   // 6 次 addCalendar，每次只 spawn 一个 Task
    done()                   // ← add 还在飞，队列已放行下一个动作
}
```

结果是第 3 轮想修的竞态**根本没被修掉**：下一个动作（取消 / 重排）的删除，
可能落在这些 `add` 之前或之后，两种顺序都是错的：

- 删除落在 add 之后 → 刚排好的提醒被删掉（"改了期一条都不响"）；
- add 落在删除之后 → 凭证已删而提醒还活着（"删了还在响"）。

### 修法：让排程可 await

`addCalendar` 改成 `async`（内部直接 `await add`，不再套 `Task`），
`scheduleAlertsNow` 改成 `async` 并逐条 `await`，队列里的 `done()` 移到 `await` 之后。
这样"删旧→排新"的顺序才真正成立。

## 2. 闸门第 12 条判据：排程必须可 await

`privacy.js` 新增：`addCalendar` 必须带 `async`。已验证抓得住 ——
把它改回同步，闸门立刻红：

```
privacy: FAIL — 1 处回归
  Engine/CredentialOrg.swift:164 — addCalendar 不是 async：
    通知排程会回到分离异步，串行队列失效 → 改成 async 并由调用方 await
```

## 3. 方法论

**"我加了一个队列"不等于"顺序被保证了"。** 要问的是：
队列里的每个动作，`done()` 是否真的在**副作用落地之后**才被调用？
只要动作内部还有 `Task { ... }`，答案就是否 —— 队列只串行了"发起"，没串行"完成"。

这和上一轮的教训是同一族：**修完之后要回去证明它真的成立**，
而不是"代码看起来按我想的顺序写了"。
