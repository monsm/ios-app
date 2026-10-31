# AUDIT-ROUND-8 · 第八轮：一个会"诬告正常开门"的时基 bug + 闸门自身的盲区

> 执行日期：2026-11-01 06:00 → 07:00（+08:00）
> 起点 `94ef79f` → 终点 `6dea426`
> CI：build `errors=0`；golden **41 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **3 项**（1 个真产品缺陷 + 2 个闸门/测试盲区） |
| 测试 | **41 条**（16 金标 + 15 安全 + 5 并发 + 5 时基），4 个文件 / 199 条断言 |
| 闸门 | 17 / 17，`swiftcheck` 覆盖 **148 → 152** 个文件 |
| 静态扫描 | P2 23 → **21** |

---

## 1. 真缺陷：越界窗口把**正常开门诬告成伪造**

`RecordSearch.outOfWindow` 是记录页那个「只看越界窗口的临时码开门」筛选，
界面文案写着「可能是伪造或时钟偏差」。它把两个时间**直接比较**：

```swift
let f = parseStamp(p.from), to = parseStamp(p.to)      // ← UTC 解析
...
let ts = Int64(d.timeIntervalSince1970)                 // ← dateOf 用 DF.stamp（本地）
if !temps.contains(where: { ts >= $0.from && ts <= $0.to }) { /* 判越界 */ }
```

**两边时基不同**：

| 数据 | 写入方 | 时区 |
|---|---|---|
| 临时码 `from`/`to` | `DF.cached("yyyy-MM-dd HH:mm")`（默认 `TimeZone.current`） | **本地** |
| 日志 `timeStr` | `ProtoTime.localStr` → `DF.stamp`（默认本地） | **本地** |
| 解析窗口 | `parseStamp` → `DF.stampUTC` | **UTC** |

东八区下，窗口被整体平移 −8 小时 ⇒ 一条**落在窗口内 8 小时处**的正常开门会被判成越界，
界面告诉用户「可能是伪造或时钟偏差」。**把正常开门诬告成攻击，比不显示更糟** ——
用户会去重置锁、改密码、怀疑家人。

修法：新增 `RecordSearch.parseLocal`（按 `DF.stamp` 解析），窗口侧改用它。
`parseStamp`（UTC 口径）**保留不动** —— 它是 `Attribution.ms` 那条 JS 互操作链的既定语义，
有正当理由，只是**不能**用在这个比较里。

> 这类 bug 不崩、不报错、不影响编译 —— 只会让判定结果错。
> 只有把"哪个字段该用哪个口径"写成可执行断言才防得住。

---

## 2. 闸门自身的盲区（我自己的代码先撞上）

### 2.1 `swiftcheck` 只扫 `App/`，`Tests/` 从未被检查

我在 `TimeBasisTests.swift` 里写了一个少一个右括号的行：
**本地 17 道闸门全绿**，CI 真编译器才报 `Expected ',' separator`。

修法：`swiftcheck` 现在也扫 `Tests/`（148 → **152** 个文件）。
并且**当场验证**过它真的抓得住 —— 把那个 bug 塞回去，闸门立刻红：

```
Tests/TimeBasisTests.swift  文件末尾括号不平衡（depth=1）
swiftcheck: FAIL — 1 处不平衡
```

> 这条比"修好那个括号"重要得多：闸门覆盖不到的地方，等于没闸门。

### 2.2 测试假设了开发机在东八区

`XCTAssertNotEqual(logSec, parseStamp(sample))` —— "本地与 UTC 解析必须不同"。
在 CI 的 **UTC runner** 上，两者本来就相等（偏移为 0），于是**正确实现被判成红**。

修法：改成断言**关系**而不是"不同" —— 差值必须正好等于
`TimeZone.current.secondsFromGMT(...)`。这样在东八区是 28800、在 UTC 是 0，两边都成立。

> 教训：写时间相关断言时，先问"这条断言在 UTC 机器上还成立吗"。

---

## 3. 顺带修的崩溃面

`LockServicePairing` 两处 `pins[0]`：空数组索引是 **crash 不是 throw**。
今天的唯一调用点喂 `KeyGen.genPins(64)`（要么 64 条要么 throw），所以不会触发 ——
但那是**调用点的隐式约定**，不是函数自己的保证。配网是"用户正站在门边"的场景，
崩进程代价极高。改用 `pins.first ?? ""`，空 pins 由成帧收口判失败并给出可读原因。

---

## 4. 验证链

```
$ node Gates/allgates.js
… 17 道闸门全部通过
swiftcheck: OK — 152 个文件括号/字符串/注释全部平衡
tests: 4 个测试文件，199 条断言

$ node Tools/static-audit.js
P0=0 P1=0 P2=21 P3=9      # 上轮 P2=23

$ git show origin/ci-test:meta.txt
commit=6dea426… job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=41

$ git show origin/ci-log:meta.txt
errors=0  build_ok=1  archive_ok=1
```

---

## 5. 仍未闭环

### P2（6 项）
- **SEC-01 残余**：Swift `String` 无法可靠清零，进程内仍有一份明文口令副本（平台限制）。
- **SEC-18 残余**：手机钥匙撤销走 `cmd08`，锁端失败时本机记录如何处置**需真机确认**。
- **SEC-22**：协议层 AES-128-ECB 无 IV/无认证、静态 ekey 可重放 —— **固件限制**。
- **SEC-26**：`ITSAppUsesNonExemptEncryption: NO` 的出口合规归类**需法律复核**。
- **SEC-01 单测**：未签名测试宿主无钥匙串权限 ⇒ CI 上 `skipped`。
- **D-12 竖屏**：产品决定，需在说明里记录。

### P3
D-11 是**误报**（`MemberCreateScreen`/`KeyCreateScreen` 的 `@State` 必须 internal ——
四步视图住在另一个文件的 `extension` 里，`private` 会编译不过；两处都已有注释说明）。
D-14（DesignLab `<img>` 缺 alt）、`ForEach` 下标身份若干处（只读快照）、
`.toolbar(.hidden, for:)` 软废弃。

### 工具状态
`hig_audit` / `hig_audit_file` 本轮仍**超时**（连续第二轮）。HIG 结论以上轮的人工逐条复核为准。

### 需要真机/人工的
SwiftUI 真实渲染与**浅色主题观感**、手势手感、触觉反馈、
BLE 回执、指纹录入、**DFU 真实续传**、WebDAV 真实链路。
