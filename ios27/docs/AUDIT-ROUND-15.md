# AUDIT-ROUND-15 · 第十五轮：同一个盲区的另一半（字号令牌）

> 执行日期：2026-11-01 08:40 → 09:10（+08:00）
> 起点 `06461de` → 终点 `01631d2`
> CI：build `errors=0`；golden **54 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **3 个死字号令牌** + 闸门覆盖到 `V.F` |
| 闸门 | 20 / 20 |

---

## 1. 上一轮只补了盲区的一半

第十四轮发现 `V7Tokens.swift` 因为"是字面量的家"被 `tokens.js` 整体豁免，
于是**没人检查令牌是否被使用** —— 修掉了 `C.blueCursor`，并给闸门加了颜色令牌判据。

本轮检查同一个文件的**另一个豁免**：

`Gates/dynamictype.js` 的豁免名单里同样有 `V7Tokens.swift`（理由：`V.F.sans(数字)` 只在那里定义）。
于是**字号令牌**也从没被检查过使用情况。

按同样的表格法把 `V.F` 的 **82 个**字号令牌逐个查消费点，发现 3 个零消费：

| 令牌 | 定义 | 消费点 |
|---|---|---|
| `title20` | `sans(20, weight: .bold, relativeTo: .title3)` | **0** |
| `cardBodyStrong` | `sans(16, weight: .semibold, relativeTo: .body)` | **0** |
| `icon22Medium` | `sans(22, weight: .medium, relativeTo: .title2)` | **0** |

三个都是"看起来完全合理"的字号档 —— 而正因为合理，后来的人会以为它们是设计系统的一部分、
不敢删、甚至照着它们挑新字号。字号表越堆越密，反而让人选错。

**处置：删除，原位留一行说明。** 三条注释都写明"removed 2026-11-01: zero consumers"，
`git blame` 到那里能直接读到理由。

---

## 2. 闸门覆盖到 `V.F`

`tokens.js` 的死令牌检查现在同时覆盖两个枚举：

| 枚举 | 检查对象 | 排除的"非令牌" |
|---|---|---|
| `V.C` | 颜色令牌 | `rgb` / `dual` / `dimmed` / `trackOf` / `highContrastOn` |
| `V.F` | 字号令牌 | `sans` / `serif` / `mono` / `gaugeNumber` / `gaugeNumberPlain` |

**当场验证抓得住**：临时塞一个 `zzDeadFont` 进 `V.F`，闸门立刻红：

```
tokens: FAIL - 1 token(s) with zero consumers
  F.zzDeadFont
```

（第一版输出写死了 `C.` 前缀，会打成 `C.F.zzDeadFont` —— 已修成按前缀区分。
输出错了会误导排查方向，所以这个也值得修。）

---

## 3. 方法复盘：为什么"豁免"总会漏掉一半

这两个闸门（`tokens` / `dynamictype`）的豁免都**有正当理由**：
令牌文件里必须允许出现字面量，否则每条定义都会红。

但"允许出现字面量"被实现成了"整文件跳过"，
副作用就是**这个文件里的一切都不再被任何规则检查** —— 包括"有没有被用"。

正确的豁免粒度应该是**按规则**而不是**按文件**：
- "不许写字面量"这条规则 → 令牌文件豁免 ✅
- "令牌必须有消费点"这条规则 → 令牌文件**不该**豁免 ❌（原实现把它一起豁免了）

本轮与上一轮修的正是后者。

---

## 4. 验证链

```
$ node Gates/allgates.js
… 20 道闸门全部通过
tokens: OK — 148 个 Swift 文件，0 处硬编码样式字面量（含 V7 字号/色板）

$ git show origin/ci-log:meta.txt
commit=01631d2… errors=0  build_ok=1  archive_ok=1

$ git show origin/ci-test:meta.txt
commit=01631d2… job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=54
```

---

## 5. 仍未闭环

### P2（6 项，均需设备/外部决定/平台限制）
SEC-01 残余（Swift `String` 无法清零）· SEC-18 残余（需真机）·
SEC-22（固件 AES-ECB 限制）· SEC-26（出口合规需法律复核）·
SEC-01 单测（未签名宿主 skipped）· D-12（竖屏产品决定）。

### P3
D-11 误报已确认。D-14（DesignLab `<img>` 缺 alt）、`ForEach` 下标身份若干处、
`.toolbar(.hidden, for:)` 软废弃、VoiceOver 转子（可选优化）。

### 需要真机/人工的
SwiftUI 真实渲染与浅色主题观感、手势、触觉、BLE 回执、指纹录入、
DFU 真实续传、WebDAV 真实链路、密度三档观感。
