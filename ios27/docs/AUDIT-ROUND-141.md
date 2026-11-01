# AUDIT-ROUND-141 · 第一百四十一轮：`move(by:)` 只对 ±1 正确，而我一度用断言表达它

> CI：`338ce0d` 已验证绿；`5695cc9` / `485ee7b` 待回执。本轮本地提交。

## 1. 缺陷：`swapAt` 实现只对 `delta == ±1` 成立

```swift
static func move(_ slot: DevSlot, by delta: Int) {
    ...
    let j = i + delta
    list.swapAt(i, j)          // ← 交换，不是移动
}
```

| 输入 | 期望 | `swapAt` 实际 |
|---|---|---|
| `delta = +1` | 与下一位交换 | ✅ 一致 |
| `delta = +2` | `[A,B,C]` 把 A 上移两位 → `[B,C,A]` | ❌ 得 `[C,B,A]` |

当前唯一调用方（`ModuleOrderSheet` 的上移/下移按钮）**只传 ±1**，所以现网无 bug。
但签名 `by delta: Int` 允许任意值 —— 未来加「移到顶部」就会静默用错。

## 2. 修法：把约束写进实现

```swift
guard delta == -1 || delta == 1 else { return }
```

## 3. 我第一版用了 `assertionFailure` —— 违反本仓约定

本仓**明确不用断言**，两处既有记录：

| 位置 | 处置 |
|---|---|
| `ZKProtocol:60` | 超长时**显式截断 + 遥测**，注释写着"不用 assertionFailure" |
| `ZOTP:23` | 原 `assert(periodMin <= 120)` **已移除** |

理由：**Release 版断言被编译掉 ⇒ 静默继续；Debug 版崩 ⇒ 用户看到闪退。两种都不可取。**

改为防御式 `guard ... else { return }`。

## 4. 顺带把它做成闸门判据

`swiftcheck.js` 新增：

```js
if (/\bassertionFailure\(|\bassert\(|\bprecondition\(/.test(code)) {
  console.log(`  ${rel}  用了断言（assert / assertionFailure / precondition）—— 本仓一律用防御式 guard`);
  bad++;
}
```

双向验证：往 `PidMap.modelName` 注入 `assert(pid >= 0)` → 判红；删掉 → 全绿。

## 5. 方法论

**「当前调用方恰好只传合法值」不能替代「实现自身表达约束」。**

| 做法 | 未来误用时 |
|---|---|
| 只靠调用方自律 | **静默算错**（无任何提示） |
| 实现里写 `guard` | 静默不做（行为可预期） |
| 实现里写 `assert` | Debug 崩、Release 静默（**最糟**） |

判据：**函数签名允许的取值范围，必须与实现实际支持的取值范围一致**；
不一致时，要么收窄签名，要么在实现里守。

## 6. 顺带核对（无缺陷）

`DoorLayout` 其余部分（`order` getter 的白名单+补末尾、`reset` 的三件事）都正确；
`move` 的两处边界（`firstIndex` 找不到 / `j` 越界）都有 guard。
