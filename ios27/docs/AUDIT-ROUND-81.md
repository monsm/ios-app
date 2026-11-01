# AUDIT-ROUND-81 · 第八十一轮：两处「屏幕常亮」在异常路径上不会复位

> CI：`3479121` 已验证；`e150d03`（安全披露修复）刚推送。本轮本地提交。

## 1. 缺陷

`ScreenCare.keepingAwake(_:)` 的注释写着「离开页面或任务结束**必须复位**」，全仓 3 个调用点：

| 位置 | 形态 |
|---|---|
| `DFUScreen` | `keepingAwake(true)` + 紧跟 `defer { keepingAwake(false) }` |
| `KeyCreateScreen` | `true` … await … **末尾** `false` |
| `KeyDetailScreen` | 同上 |

后两处是「末尾调一次」。而中间那句是 `await app.enrollFingerprint(...)` ——
**它若抛错、或任务被取消，末尾那句就不会执行** ⇒ `isIdleTimerDisabled` 停在 `true`：

- 屏幕一直亮着（耗电）；
- 系统的自动熄屏被永久绕开，直到用户手动锁屏或杀掉 App。

`enrollFingerprint` 确实会失败（用户中途走开、锁掉线、指纹录入超时），所以这不是理论路径。

## 2. 修法

两处都改成与 DFU 相同的 `defer` 形态：

```swift
ScreenCare.keepingAwake(true)
defer { ScreenCare.keepingAwake(false) }
```

并删掉 `KeyDetailScreen` 里那句已冗余的末尾复位（留着会让人以为"复位靠它"）。

## 3. 防复发：`privacy` 第 21 条

`keepingAwake(true)` 之后（同函数 30 行内）必须出现 `defer`。

验证时先踩了两个错，都记下来：

1. 正则里的 `\s\` 被转义成 `\s\/`（**这是我第三次在写闸门正则时踩同一个坑**，
   前两次在 `a11y.js`）—— 已用字符码替换的方式修，避免手写反斜杠；
2. 判据本身第一版把「函数结束」的条件写成了无效正则，导致跨函数误判。

双向验证通过：

```
去掉 defer → privacy: FAIL — 1 处回归
  KeyCreateScreen.swift:234 — keepingAwake(true) 没有 defer 复位
```

## 4. 方法论

**"末尾复位"只覆盖正常路径，而这类 API 的失效恰恰发生在异常路径。**

判据：**凡是 `X(true)/X(false)` 形式的成对调用，先问"中间会不会抛错/被取消"** ——
会，就必须用 `defer`（或 `do/catch` 双写）。

而且这一条应该优先看**同族里已经写对的那处**（本轮是 `DFUScreen` 的 `defer`），
照着它统一 —— 比重新设计可靠。
