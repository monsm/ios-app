# AUDIT-ROUND-111 · 第一百一十一轮：CI 判红 —— `@escaping` 用错了位置

> CI：`063ee8f` **判红**（`errors=2`、`build_ok=0`）：
>
> ```
> App/Engine/CredentialOrgState.swift:64:47: error:
>   '@escaping' may only be used in function parameter position
> ```

## 1. 我错在哪

上一轮我把队列元素类型改成：

```swift
Locked<[(@escaping @Sendable (@escaping @Sendable () -> Void) -> Void)]>([])
```

**`@escaping` 只能出现在函数参数位置**，放进泛型实参是编译错误。
我把它当成了"标注这个闭包会逃逸"的通用修饰词 —— 不是。

存进容器之后它本来就逃逸了，`@Sendable` 足以表达"可跨并发域传递"这个约束。

## 2. 修法

| 位置 | 前 | 后 |
|---|---|---|
| `notifyQueue` 元素类型 | `(@escaping @Sendable (@escaping @Sendable () -> Void) -> Void)` | `(@Sendable (@Sendable () -> Void) -> Void)` |
| `runNextNotify` 局部 | 同上 | 同上 |

**参数位置保留 `@escaping`**（`enqueue(_ job: @escaping @Sendable (...) -> Void)`）—— 那里是对的。

## 3. 穷尽核对

搜全仓"函数类型出现在泛型实参 / 类型标注"的位置，确认只有这一处：

```
AutoOpenKit.swift:57      Locked<[String: Double]>        （非函数类型）
CredentialOrgState.swift:67  Locked<[(@Sendable (...) -> Void)]>   ← 已修
DiagKit.swift:108/209/210  Locked<[...]?>                 （非函数类型）
StoreKeychain.swift:8     Locked<[String: Keychain]>      （非函数类型）
```

## 4. 这一轮的形状很典型

**"我以为我在修类型标注，其实我在引入一个语法错误。"**

`@escaping` 与 `@Sendable` 两个属性看起来都属于"闭包修饰"，但作用域完全不同：

| 属性 | 允许位置 |
|---|---|
| `@escaping` | **仅函数参数** |
| `@Sendable` | 函数类型（任何位置） |

## 5. 方法论

**又一次印证：本地 21 道闸门全绿 ≠ 能编译。**

这已是本段第 5 次（actor 隔离、参数顺序、死代码、Sendable 遗漏、本轮 `@escaping`），
其中 3 次是我"修上一个告警时引入的新问题"。

所以**修告警之后必须再看一次 CI 的 `errors=` 与 `warnings=`** ——
不能假设"我这次改的是类型标注，应该不会引入新错误"。
