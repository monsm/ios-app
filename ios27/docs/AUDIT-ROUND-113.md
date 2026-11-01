# AUDIT-ROUND-113 · 第一百一十三轮：用「已编译通过的版本」做基准，才找到真因

> CI：`32736b9` 判红（`errors=2`：`converting non-escaping parameter 'job'`）。
> 修复 `526d101` 已推送、待回执。

## 1. 我连着错了两次，都是同一个原因

| 轮次 | 我的判断 | CI 的结果 |
|---|---|---|
| 111 | "`@escaping` 只能出现在函数参数位置，泛型实参里非法" → 删掉 | ❌ `may only be used in function parameter position` |
| 113 | "内层 `@escaping` 非法" → 删掉 | ❌ `converting non-escaping parameter 'job' to generic parameter 'Element' may allow it to escape` |

两次都是"**我认为某个写法非法，于是删掉它**" —— 而删掉之后反而错得更远。

## 2. 真正有效的方法：拿一个"CI 已验证可编译"的版本做基准

```
git show 86f4617:ios27/App/Engine/CredentialOrgState.swift
```

`86f4617` 是**CI 明确验证过 `build_ok=1` 的提交**（告警 6→1 那次）。看它原始的写法：

```swift
private static let notifyQueue = Locked<[(@escaping () -> Void) -> Void]>([])
static func enqueue(_ job: @escaping (@escaping @Sendable () -> Void) -> Void) {
let job: ((@escaping () -> Void) -> Void)? = ...
```

**`@escaping` 在泛型实参里、在嵌套层级里 —— 原始代码本来就有，而且编译通过。**
我的两次"纠正"全是在把一个正确的写法改错。

## 3. 现在的改动：只加 `@Sendable`

```diff
-  Locked<[(@escaping () -> Void) -> Void]>
+  Locked<[(@escaping @Sendable () -> Void) -> Void]>
-  func enqueue(_ job: @escaping (@escaping @Sendable () -> Void) -> Void)
+  func enqueue(_ job: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void)
-  let job: ((@escaping () -> Void) -> Void)?
+  let job: ((@escaping @Sendable () -> Void) -> Void)?
```

**三处只增加 `@Sendable`，`@escaping` 位置与已验证版本逐字一致。** 这是最小改动。

## 4. 方法论（这是本轮最有价值的一条）

**"改一个我不完全理解的类型标注"之前，先看它现在的样子能不能编译。**

| 做法 | 结果 |
|---|---|
| 凭语法规则推断（我前两次） | ❌ 两次都改错 |
| **找 `git show <已知绿的提交>:<文件>` 对比** | ✅ 立刻看出"原始写法是对的" |

这条能推广：**任何"我以为这是错的"改动，都先问"它现在能编译吗"** ——
能编译，就说明我的语法推断至少不完整；这时改动应当**只做最小增量**，而不是"纠正"。

## 5. 代价

这一处类型标注，我花了 **3 轮 CI**（`063ee8f` 红 → `32736b9` 红 → `526d101` 待验）。
若第一次就先看 `86f4617` 的原始写法，一轮就够了。

**教训：在无法本地编译的环境里，"读一个已验证版本"比"推理语法"可靠得多。**
