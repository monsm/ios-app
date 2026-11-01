# AUDIT-ROUND-213 · 第 213 轮：**五个页面抢同一个路由事件** —— 谁先跑谁把别人的跳转吃掉

> CI：`15aaac2`（本次读取数）已验证绿；`a4a581a` / `02457cb` 排队中。

## 1. 缺陷

`Router.consume()` 是**无条件**的：

```swift
func consume() -> RouteContext {
    let p = pending
    pending = .none      // ← 取走一切并清空
    return p
}
```

而**五处**都在监听同一个 `pending`：

| 页面 | 监听方式 | 认识的 case | 其余怎么办 |
|---|---|---|---|
| `HouseholdScreen` | `.onChange(of: router.pending)` | `.member` | `guard` ⇒ **丢弃** |
| `RecordsScreen` | `.onChange(of: router.pending)` | `.record` / `.day` | `default: break` ⇒ **丢弃** |
| `KeyCreateScreen` | `consumeRoute()` | `.key` | `guard` ⇒ **丢弃** |
| `KeyDetailScreen` | `consumeRoute()` | `.key` | 选第一枚凭证（也算丢弃） |
| `MemberDetailScreen` | `.onAppear` | `.member` | 丢弃 |

**TabView 里活着的 Tab 都会响应 `onChange`** —— 于是谁先跑谁赢，跳转被**吃到一半就没了**。

### 症状

| 触发 | 若被错的人先吃掉 | 用户看到 |
|---|---|---|
| 通知点开某条记录 | `HouseholdScreen` 先 consume | **什么都不发生** |
| 成员页跳到成员详情 | `RecordsScreen` 先 consume | 落在记录页空白 |
| 钥匙页跳新建 | 任一先 consume | 表单不预填 |

这类「有时灵有时不灵」最容易被当成偶发 bug 放过去。

## 2. 修法

```swift
/// 只有当挂起上下文与调用方相关时才取走它。
func consume(if matches: (RouteContext) -> Bool) -> RouteContext? {
    guard matches(pending) else { return nil }
    let p = pending
    pending = .none
    return p
}
```

五处全部改成只取自己认识的那几种，不认识的**留在原地**等对的人。

顺带修正了 `RecordsScreen.consume()` 里一个我自己引入的风险：`guard ... else { return }` 会跳过末尾的 `searchSeed` 处理（那段与路由无关，每次都要跑）—— 改成 `if let`。

## 3. 方法论

**「共享的可变单槽 + 多个观察者」= 一定有人会被抢。** 三种正确形状：

| 形状 | 适用 |
|---|---|
| **按类型认领**（本轮） | 多方关心不同子类型 |
| 队列（每个事件只投递给一个消费者） | 事件必须恰好送达一次 |
| 广播（每个观察者各收一份） | 多个消费者都要看到 |

本仓是第一种。判据：**看到「一个 pending 变量 + 两个以上 onChange」时，就该问「谁清空它、清空时别人怎么办」。**
