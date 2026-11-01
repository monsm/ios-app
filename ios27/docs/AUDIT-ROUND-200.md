# AUDIT-ROUND-200 · 第 200 轮：「文案猜颜色」变成闸门（第三次踩坑之后）

> CI：`c3a0257` 已验证绿；`0387282` / `2be3a0d` / `a3d86d3` 排队中。

## 1. 这个模式的三次案底

| 轮次 | 位置 | 文案判据 | 后果 |
|---|---|---|---|
| 182 | `CredentialStudioScreen` | `msg.hasPrefix("已")` | 「已延期…下发到锁失败 M 条」**涂绿** |
| 197 附近 | `KeyCreateScreen` | 同族前缀猜测 | 部分失败显示成功 |
| 199 | `LockStatusScreen.pendingLine` | `outcome.contains("失败") || .contains("错")` | 「锁忙，请稍后再试」**绿点**（一个关键字都没有） |

三次都是同一个形状：**状态色（`tone:` / `tint:`）的实参来自消息文本的内容判断**。

为什么这个形状总出错：

| 原因 | 说明 |
|---|---|
| 写消息的人和写颜色的人是同一段代码的两处 | 消息改了、判据没跟上 |
| 失败消息**没有义务**包含"失败"二字 | 「锁忙」「已被占用」「请稍后再试」都合法 |
| 成功路径测试永远过 | 测试用例的成功文案总是匹配的 |

## 2. 规则

`swiftcheck` 新增：

```js
if (/\b(tone|tint)\s*:[^,)]*\.contains\(/.test(code)) → FAIL
```

「颜色必须来自**显式的成败标志**，不来自消息文本。」

当前全仓命中 **0 处**（前三处都已修成显式标志：`studioOutcomeBad` / `outcomeOK`）。

## 3. 双向验证

把 `outcomeOK ? .ok : .attention` 临时改回 `outcome.contains("失败") ? …`：

```
swiftcheck: FAIL
  App/Features/Door/LockStatusScreen.swift  tone/tint 实参里用了 .contains(...)
  —— 文案猜颜色（失败文案不一定含关键字）
```

恢复后 22/22 全绿。

## 4. 方法论

**同一类 bug 出现第三次，就不再是"改一处"的事 —— 是写法本身该被禁。**

| 第 1 次 | 改掉它 |
|---|---|
| 第 2 次 | 改掉它 + 全仓扫一遍 |
| **第 3 次** | **写成闸门** —— 因为"全仓扫一遍"会过期，闸门不会 |

这也是本仓 22 道闸门的来路：**每一条背后都是一个真实踩过的坑**
（workflow.js 的闸门数对账、memberfill 的内容特征、callsig2 的实参顺序、
lineage 的设计系统残留……以及今天的 tone/tint）。
