# AUDIT-ROUND-123 · 第一百二十三轮：`DefendService` 审完无缺陷（三处单位/枚举核对）

> CI：`91a7f06` 全绿；`44d8807` / `359b773` 待回执。本轮无代码改动。

## 1. 为什么这轮不动代码

读完 `DefendService.swift`（50 行）与它依赖的 `DefendKit` / `AutoOpenKit.defendActive`，
逐个核对三处容易错的地方 —— **都对**。

## 2. 核对的三处（都是"差一位就出错"的地方）

**（a）落盘单位 vs 读盘单位**

```swift
// 写（DefendService:40-43）
DB.saveDefend(kc.mac, DefendCfg(control: control,
                                startSec: startProto,   // ← 协议**半秒**
                                endSec: endProto,
                                at: ...))
```

```swift
// 读（AutoOpenKit:109）
let secOfDay = ((h * 3600 + m * 60 + s) / 2)   // ← 当天秒数也除以 2
```

**两边都是"半秒"**，单位一致 ✅。若读侧忘了 `/2`，时段布防会整体偏移一倍（12 小时），
表现为"该布防的时候不布防"。

**（b）枚举 rawValue 与协议 control 的对应**

```swift
enum DefendMode: Int { case off = 0; case once = 1; case period = 2 }
```

与协议注释（`DefendKit.swift:4`）"0 = 撤防 / 1 = 不定期布防 / 2 = 时段布防"逐值对齐 ✅。
`rawValue` 直接就是 control，不做第二层映射 —— 这正是避免"映射表写错一格"的正确做法。

**（c）失败不写本地**

```swift
try await host.lockLink.setDefence(...)   // 抛错就直接退出
DB.saveDefend(...)                        // 只有成功才落盘
```

注释里写了理由（"宁可让用户重试，也不要造出一个本机以为布防了的假状态 ——
因为 F4 否决门读的就是本地配置，写早了会让自动开锁被误否决"）✅ 实现与理由一致。

## 3. 另一处已记录的设计取舍（不是缺陷）

`once` 模式下发 `startProto = 0, endProto = 0`，而 APK 发的是绝对时间（到点自动撤防）。
代码注释（27-32 行）写明了原因：**UI 没有起止时间选择器**，本机无从得知"到几点撤防"，
且 `DefendView:179` 已如实告知用户"直到你手动撤防"。

这是"能力差异被诚实呈现"的正确姿态，不是缺陷。

## 4. 方法论

**审"协议层"代码时，最高产的检查是"跨文件的单位一致性"。**

本段已用这条抓到过：

| 轮次 | 缺陷 |
|---|---|
| 44 | `parseStamp`（UTC）vs `parseLocal`（本地墙钟）混用 → 越界页诬告正常开门 |
| 119 | `Rec.lockTime`（协议秒）vs `timeStr`（本地串） |
| **123** | 核对通过（半秒 ↔ 半秒） |

判据：**凡是"A 写、B 读"的数值，去两边各看一眼单位/口径**。这类缺陷不会崩、不会报错，
只会让行为静默偏移。

## 5. 差集进度

「从未在报告里出现」的文件：26 → 18（本轮审完 `DefendService`，上一轮 `PidMap`）。
其中 4 个本轮之前审过并记录（`RecordSearchQuery` / `StatusParser` / `Attribution` / `Reading`）。
