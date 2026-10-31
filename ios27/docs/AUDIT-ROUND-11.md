# AUDIT-ROUND-11 · 第十一轮：一个"点了没反应"的模态撞车 + 第 19 道闸门

> 执行日期：2026-11-01 07:15 → 08:00（+08:00）
> 起点 `8a3e76b` → 终点 `d6355bc`
> CI：build `errors=0`；golden **50 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **1 个真缺陷**（关闭本机密码时验证框被吞） |
| 新闸门 | **第 19 道** `modal.js` |
| 闸门 | 18 → **19** |
| 测试 | 46 → **50**（+4 模态互斥），6 文件 |
| 静态扫描 | P0 0 · P1 0 · P2 21 · P3 9 |

---

## 1. 真缺陷：点「继续验证」，验证框根本没出来

`SecurityScreen` 的「关闭本机密码」流程是：

1. 点开关 → `confirmationDialog`（"关闭后冷启动不再需要密码……"）
2. 点「继续验证」→ 应该弹出 `VerifyPasscodeSheet` 要求输入当前密码
3. 验证通过 → `DB.setPasscode(nil)`

旧代码第 2 步是**在对话框的按钮闭包里直接置 sheet 布尔**：

```swift
.confirmationDialog("关闭本机密码？", isPresented: $showDisableConfirm, ...) {
    Button("继续验证", role: .destructive) { showVerifyPass = true }   // ← 问题在这
    Button("取消", role: .cancel) {}
}
```

那一刻对话框**还在退场动画中**。HIG `sheets` 明确要求
"Display only one sheet at a time from the main interface" ——
SwiftUI 在已有模态正在消失时收到新的呈现请求，会把它**静默丢弃**。

用户看到的是：点「继续验证」→ 对话框消失 → **没有任何东西弹出** →
密码关不掉，而且没有任何错误提示。他会以为 App 坏了，或者以为自己没点中。

> 这个缺陷和上一轮那两个是同一族：**用户做了动作，界面没有任何回应**。
> 区别在于上一轮是"错误被 try? 吞掉"，这一轮是"呈现被 SwiftUI 吞掉"。

### 修法：排队，而不是抢

```swift
Button("继续验证", role: .destructive) { pendingVerify = .pass }   // 只记意图
...
.onChange(of: showDisableConfirm) { _, open in
    if !open { consumePendingVerify() }   // 对话框真的关掉之后才呈现
}
```

同一个形状也用在「关闭胁迫码」那条路径上（同样的 bug，一并修）。

---

## 2. 第 19 道闸门：`Gates/modal.js`

判据：**`.confirmationDialog` / `.alert` 的按钮闭包里直接置某个 sheet 布尔为 true ⇒ 红**。
另外把"同一视图 ≥4 个 sheet 入口"作为**提示**（不判红）——多入口本身没错，但要人确认互斥。

**当场验证抓得住**：把修复回退成 `showVerifyPass = true`，闸门立刻红：

```
modal: FAIL — 1 处模态呈现会撞车（HIG sheets）
  App/Features/Settings/SecurityScreen.swift:70  对话框里直接置 showVerifyPass = true
  —— 对话框退场会吞掉这次呈现
```

修复版则是绿 + 一条提示（4 个 sheet 入口，已确认互斥）。

---

## 3. 新增测试：`SheetPresentationTests`（4 条）

把"同一时刻最多一个模态"写成可执行断言（纯逻辑 `ModalGate`，不依赖 SwiftUI 运行时）：

| 测试 | 钉住什么 |
|---|---|
| `testSecondModalIsRejected` | 已有模态时第二个请求必须被拒绝，不能覆盖 |
| `testCanPresentAfterDismiss` | 关闭后可再呈现 |
| `testEnqueuedModalPresentsAfterDismiss` | 对话框里请求的 sheet 必须**排队**，退场后才呈现（正是本轮修复的形状） |
| `testPendingIsConsumedOnce` | 排队项只能用一次，重复 dismiss 不能重复呈现 |

---

## 4. 本轮顺带核对的 HIG 页（无需改动）

| HIG 页 | 核对结论 |
|---|---|
| `voiceover` | 全部 `*Screen.swift` 都有 navigationTitle；15 处 `.isHeader`；装饰图标已 `accessibilityHidden`。**转子（rotor）零使用** —— 但本仓列表都是短列表，属可选优化，非缺陷 |
| `gestures` | 门页圆盘有多重路径：`tap` / `double` / `hold` / `上滑` / 围栏拖拽，且都挂 `.accessibilityAction`（"Not the only way" 满足）；`dialHint` 会说明当前手势怎么用 |
| `motion` | 13 处 `.animation` 全部带 `value:`，且门页两处受 `reduceMotion` 控制；`Gates/motion.js` 绿 |
| `loading` | 23 处 `VBusyRow`/`ProgressView` 覆盖长操作 |
| `privacy` | 4 条 purpose string 合格，Face ID 确实在用 |

---

## 5. 验证链

```
$ node Gates/allgates.js
… 19 道闸门全部通过
modal: OK — 对话框不会直接抢 sheet，1 处多入口已提示
feedback: OK — 用户动作里的 try? await 都有错误通道
tests: 6 个测试文件，212 条断言

$ node Tools/static-audit.js
P0=0 P1=0 P2=21 P3=9

$ git show origin/ci-test:meta.txt
commit=d6355bc… job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=50

$ git show origin/ci-log:meta.txt
commit=d6355bc… errors=0  build_ok=1  archive_ok=1
```

---

## 6. 仍未闭环

### P2（6 项，均需设备/外部决定/平台限制）
SEC-01 残余（Swift `String` 无法清零）· SEC-18 残余（需真机）·
SEC-22（固件 AES-ECB 限制）· SEC-26（出口合规需法律复核）·
SEC-01 单测（未签名宿主无钥匙串权限 ⇒ CI skipped）· D-12（竖屏产品决定）。

### P3
D-11 已确认误报（跨文件 extension 需要 internal）。D-14（DesignLab `<img>` 缺 alt）、
`ForEach` 下标身份若干处、`.toolbar(.hidden, for:)` 软废弃、
VoiceOver 转子（可选优化）。

### 工具
`hig-doctor` MCP 仍不可用（第五轮）。HIG 依据 `apple-design` skill 自带的 123 页本地副本
（`references/hig/*.md`，Apple 原文），本轮据此核对了 5 个页面。

### 需要真机/人工的
SwiftUI 真实渲染与浅色主题观感、手势、触觉、BLE 回执、指纹录入、
DFU 真实续传、WebDAV 真实链路。
