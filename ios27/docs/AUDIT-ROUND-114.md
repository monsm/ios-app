# AUDIT-ROUND-114 · 第一百一十四轮：反证确认（`@escaping` 必须保留）

> CI：`6a0a46a` 判红（**`errors=6`**）—— 这正是"删掉内层 `@escaping`"那版。
> 修复 `526d101` 已推送、待回执。本轮只有一处注释修正（未推）。

## 1. 那 6 条错误是最好的反证

```
App/Engine/CredentialOrgState.swift:50:46: error: escaping closure captures non-escaping parameter 'done'
App/Engine/CredentialOrgState.swift:139:46: error: escaping closure captures non-escaping parameter 'done'
App/Engine/CredentialOrgState.swift:174:46: error: escaping closure captures non-escaping parameter 'done'
App/Engine/CredentialOrgState.swift:178:22: error: escaping closure captures non-escaping parameter 'done'
```

它把问题说得很清楚：**内层 `done` 必须能被异步闭包捕获**，所以它必须标 `@escaping`。
我上一轮"内层 `@escaping` 非法"的判断是错的，删掉它导致 `done` 变成非逃逸。

这与 `32736b9` 的 `converting non-escaping parameter 'job'` 是**同一个根因的两个面**：

| 版本 | 删掉了什么 | 报什么 |
|---|---|---|
| `32736b9` | 泛型实参里的 `@escaping` | `job` 不再逃逸 → 塞进容器失败 |
| `6a0a46a` | 签名里内层的 `@escaping` | `done` 不再逃逸 → 被异步闭包捕获失败 |

## 2. 当前修复（`526d101`）与已验证版本的差异

```diff
- Locked<[(@escaping () -> Void) -> Void]>
+ Locked<[(@escaping @Sendable () -> Void) -> Void]>
- func enqueue(_ job: @escaping (@escaping @Sendable () -> Void) -> Void)
+ func enqueue(_ job: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void)
- let job: ((@escaping () -> Void) -> Void)?
+ let job: ((@escaping @Sendable () -> Void) -> Void)?
```

**三个类型位置只增加 `@Sendable`，`@escaping` 逐字未动。** 与 `86f4617`（CI 证明可编译）一致。

## 3. 本轮只改了一处注释（未推）

我先前在 `notifyQueue` 上方写了段注释说"这里**不能**写 `@escaping`" ——
那是基于我错误的判断。已改成实话：

> `@escaping` 保持原样（`86f4617` 就有、CI 已验证可编译），只补 `@Sendable`。
> 删掉它会得到 `escaping closure captures non-escaping parameter 'done'`（6 处）—— 反证它必须保留。

**为什么没有立刻推**：`526d101` 还没被验证。在上面叠加改动（哪怕是纯注释）会让"到底是哪一版绿的"
变得含糊。等回执后一起推。

## 4. 方法论

**编译器的错误信息本身可以当"反证证据"用。**

这轮我没有再推理语法，而是读那 6 条错误 —— 它们直接说明了"为什么这个属性必须存在"。
这比"我觉得应该这样写"可靠得多。

另一条（上轮已记，这轮再次验证）：**改类型标注前先 `git show` 一个已知绿的版本做基准。**
