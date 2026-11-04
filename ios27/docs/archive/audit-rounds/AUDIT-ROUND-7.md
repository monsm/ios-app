# AUDIT-ROUND-7 · 第七轮：HIG 复核 + 并发地基测试 + 交付可追溯

> 执行日期：2026-11-01 05:40 → 06:20（+08:00）
> 起点 `398608d` → 终点 `f70dfb3`
> CI：build `errors=0`；golden **35 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **2 项**（G-14 · D-04）+ **1 项新测试体系**（并发 5 条） |
| 测试 | **35 条**（16 金标 + 15 安全回归 + 5 并发），3 个文件 / 185 条断言 |
| 闸门 | 17 / 17（`tests` 判据 28 → **31**） |
| 静态扫描 | P0 0 · P1 0 · P2 23 · P3 9 |

> 说明：本轮 `hig_audit` MCP **两次超时**（项目级 + 逐文件级都 timeout）。
> 于是改为**逐条人工复核**第一轮 HIG 报告（`docs/AUDIT-D-HIG.md`）里的 15 条真实问题，
> 结论写在 §1 —— 这比"工具没跑就不了了之"更可靠，因为每条都对着当前代码验过。

---

## 1. 第一轮 15 条 HIG 问题的现状（逐条复核当前代码）

| ID | 结论 | 证据 |
|---|---|---|
| D-01 浅色主题不生效 | **已修** | `V7Tokens` 已有 `Color.dual(light:dark:)`，47 个令牌全部双值 |
| D-02 Dynamic Type 被钉死 | **已修** | `LockKeeperApp` 改用 `AXTextSizeModifier`，不覆盖系统字号 |
| D-03 chip 固定高 + `lineLimit(1)` | **已修** | `V7Components.swift:206/211` 已 `lineLimit(2)` + `fixedSize`，`:219` 用 `minHeight` |
| D-04 `VTag` 命中区 26pt | **本轮修复** | 见 §2 |
| D-05 白字压 #3F8EF4 仅 3.29:1 | **已修** | `onBlue = dual(0xFFFFFF, 0x06201A)` |
| D-06 pink 文字 4.07:1 | **已修** | `pink = dual(0xC81E4A, 0xFF6A7A)`（深色提亮到 4.5:1） |
| D-07 8 处装饰图标未隐藏 | **已修** | `LockProfileScreen:129/148` 有 `accessibilityHidden` + `isSelected`；`CredentialStudioScreen:255/272` 星标 label 随状态变 |
| D-08 标签栏缺「家」 | **已修** | `VTabItem.all` 已含 `household`（5 项） |
| D-09 三个死开关 | **已修** | `VFloatingTabBar` 读 `accessibilityReduceTransparency` + App 内同档开关 |
| D-10 字号 < 11pt | **已修** | `V.F.tab` 等已提到 ≥11pt |
| D-11 26 个 `@State` 缺 `private` | 待核 | P3 代码规范，不影响用户 |
| D-12 仅竖屏 | 待核 | P3；门锁场景竖屏是产品决定，需在设计说明里记录 |
| D-13 假 chevron | **已修** | `VCardHeader.showsChevron` 默认已改 `false` |
| D-14 DesignLab `<img>` 缺 alt | 待核 | 非 app 产物（内部总览页） |
| D-15 App 内外观设置 | **保留** | 产品决定；D-01 修好后每个选项都真实生效 |

**15 条里 11 条已闭环，4 条为 P3 或产品决定。**

---

## 2. D-04 · `VTag` 命中区（本轮真修）

`VTag` 视觉上是 26pt 高的小胶囊，但它被**直接当作 Button 的 label** 用
（`AccessibilityScreen:105` 圆盘尺寸、`TailgateScreen:33` 模式选择、
`RecordsStudioScreen:151` 成员筛选、`LockPortfolioScreen` 等）——
那些地方的点击区域只有 26pt，远低于 HIG 的 44×44pt（最低 28pt）。

修法：**视觉尺寸不动**（设计稿要求小胶囊），用 `minHeight` + `contentShape` 把命中区撑到 44pt：

```swift
.frame(minHeight: V.Hit.min)
.contentShape(.rect)
```

外观一点没变，手指够得着了。这是"设计稿与可达性冲突"时的正确解法 ——
不是把胶囊画大（破坏设计），而是让**命中区**大于**绘制区**。

---

## 3. G-14 · 构建产物无法反查 commit

IPA 文件名原来只有时间戳 `LockKeeper-20261101.003442-unsigned.ipa`。
拿到一个包装错版本时，**没有任何线索**能反查它是哪次构建。

现在：

```
LockKeeper-<时刻>-r<运行号>-<短SHA>-unsigned.ipa
LockKeeper-20261101.060212-r41245258609-f70dfb3-unsigned.ipa
```

Release 说明也带上完整 `github.sha`、run 号与产物名。
这条改动很小，但它决定"我明明推了修复却没生效"这类问题要查 5 分钟还是 5 秒。

---

## 4. 新增：并发地基测试（5 条）

全仓 `@unchecked Sendable`（`BLEService` / `DFUSession` / `Store` / `QuickActions`）
**都建立在 `Locked` 真的互斥这个前提上**。而 `@unchecked` 的含义正是
"编译器你别管，我保证过" —— 前提一旦破了，编译器不会报错，
表现是**偶发丢计数 / 偶发丢日志 / 偶发界面数字对不上**，最难查的那类 bug。

| 测试 | 钉住什么 |
|---|---|
| `testLockedIncrementIsAtomic` | 8 线程 × 2000 次自增，结果必须正好 16000（lost update 会明显偏小） |
| `testLockedReadModifyWriteIsIndivisible` | 读-判-写在同一次 `withLock` 里（`Store.addUnique` 那类形状） |
| `testLockedUnlocksOnThrownError` | 闭包抛错后 `defer unlock` 真的解锁 —— 漏了会死锁（CI 上表现为超时红） |
| `testLockedReturnsBodyResult` | 返回值语义 |
| `testLockedWithReferenceValue` | 包住引用类型时的共享计数 |

`Gates/tests.js` 同步要求这 3 类断言存在（判据 28 → **31**）。

**实测**：`Executed 35 tests, with 0 failures` —— 并发测试全过，`Locked` 的互斥是真的。

---

## 5. 验证链

```
$ node Gates/allgates.js
… 17 道闸门全部通过
tests: 3 个测试文件，185 条断言

$ git show origin/ci-test:meta.txt
commit=f70dfb3… job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=35

$ git show origin/ci-log:meta.txt
commit=f70dfb3… errors=0  build_ok=1  archive_ok=1
```

---

## 6. 仍未闭环

### P2（6 项，全部需要设备 / 外部决定 / 平台限制）
- **SEC-01 残余**：Swift `String` 无法可靠清零，进程内仍有一份明文口令副本（平台限制）。
- **SEC-18 残余**：手机钥匙撤销走 `cmd08`，锁端失败时本机记录如何处置**需真机确认**。
- **SEC-22**：协议层 AES-128-ECB 无 IV/无认证、静态 ekey 可重放 —— **固件限制**。
- **SEC-26**：`ITSAppUsesNonExemptEncryption: NO` 的出口合规归类**需法律复核**。
- **SEC-01 单测**：未签名测试宿主无钥匙串权限 ⇒ CI 上 `skipped`。
- **D-12 竖屏**：产品决定，需在说明里记录。

### P3
D-11（26 个 `@State` 缺 `private`）、D-14（DesignLab `<img>` 缺 alt）、
`ForEach` 下标身份若干处（只读快照）、`.toolbar(.hidden, for:)` 软废弃。

### 需要真机/人工的
SwiftUI 真实渲染与**浅色主题观感**、手势手感、进度弧节奏、触觉反馈、
BLE 回执、指纹录入、**DFU 真实续传（G-12 改完正好要真机验）**、WebDAV 真实链路。

### 工具状态
`hig_audit` / `hig_audit_file` MCP 本轮**超时两次**（项目级与文件级）。
改用逐条人工复核，结论如上表 —— 但下一轮若工具恢复，应重跑一次以捕获新增规则。
