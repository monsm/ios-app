# AUDIT-ROUND-5 · 第五轮：给本轮所有安全修复装上可执行回归保护

> 执行日期：2026-11-01 04:45 → 05:30（+08:00）
> 起点 `046e823` → 终点 `f271eb9`
> CI 实测：**Executed 31 tests, with 1 test skipped and 0 failures**（run `41242556012`）

---

## 0. 为什么这一轮不修产品代码，而是修"验证"

前四轮累计修掉 40+ 个缺陷。但其中相当一部分属于
**"改回去也没人会发现"** 的那一类 —— 剪贴板直写、备份明文、空壳模式可读、
帧脱敏只处理第一个 `hex=`、KLV 超长静默截断、CSV 注入、备份 schema 丢字段、口令摘要降级……

`Gates/privacy.js`（第 16 道）盯的是**代码形状**，它回答不了"行为对不对"。
而金标测试虽然在第 4 轮终于跑起来了，覆盖的却是**协议层**（命令帧/AES/解析），
本轮修的安全行为**一条断言都没有**。

所以这一轮做一件事：给它们补 `SecurityRegressionTests.swift` —— **15 条可执行断言**。

---

## 1. 新增覆盖（每条都对应本轮或前几轮的一个真实缺陷）

| 测试 | 钉住的缺陷 |
|---|---|
| `testKLVRejectsOversizedPayload` | SEC-31 超长 KLV 静默截断（半截 WiFi 密码"看着成功"） |
| `testFrameRedactHandlesEveryHexSegment` | SEC-23 帧脱敏只处理第一个 `hex=`，第二个原样落盘 |
| `testFrameRedactKeepsShortHexHidden` | 短 hex（4 字节 PIN）也必须遮，不能因"不够帧头"放行 |
| `testCSVFieldBlocksFormulaInjection` | SEC-12 CSV 公式注入（`=HYPERLINK` / `+cmd|…`） |
| `testCSVFieldQuotesCommasAndQuotes` | 逗号/引号转义 + 回车不得伪造额外行 |
| `testVCardEscapesCarriageReturn` | SEC-12 vCard 行注入（未转义 `\r` 可伪造 TEL/EMAIL 字段） |
| `testMergedPasscodeRecordNeverDowngrades` | SEC-06 备份口令摘要不得从 PBKDF2 降级成 32 位 FNV |
| `testAppearanceCodableRoundTripKeepsAllFields` | 外观段 `CodingKeys` 漏列字段（曾导致 10 个偏好**从来没进过备份**） |
| `testChecksumMismatchIsDetected` | SEC-14 校验和不一致必须**判得出来**（恢复路径据此拒绝） |
| `testFrameOwnerRoutingIsolatesSubscribers` | SEC-15 帧归属路由（两个服务共用一条 BLE 连接、只按 cmd 匹配） |
| `testStrictHexRejectsNoise` | SEC-16 协议解析必须拒绝脏 hex，而不是解成垃圾帧 |
| `testLedgerPasswordRoundTripsThroughKeychain` | SEC-01 台账口令进出 Keychain + plist 副本不留明文 |
| `testDecoyModeHidesAndBlocksWrites` | SEC-03/N-01 空壳模式读为空**且写被拒绝**（防空表覆盖真台账） |
| `testBackupImportRejectsForeignAndOversizedPayloads` | SEC-30 类型/规模闸 |
| `testPasscodeFailStreakIsPersistent` | SEC-28 失败计数与冷却必须落盘（关掉 sheet 不清零） |

**闸门也升级**：`Gates/tests.js` 现在逐条要求这 13 类安全断言存在，
缺任何一条就红 —— 防止有人把测试文件删了还留着 `tests: OK`。判据 15 → **28 条**。

---

## 2. 新测试第一次跑就抓到 3 个问题（都在**测试自身**）

这恰好证明"跑起来"的价值 —— 三条都是静态审查看不到的：

| 现象 | 判定与处置 |
|---|---|
| CSV 断言 `hasPrefix("'")` 失败 | **测试写错了**：含 `"` 的值会被再包一层 CSV 引号，所以原始 field 以 `"` 开头。改为断言**单元格实际内容**（去外层引号 + 反转义）—— 那才是 Excel 看到的东西。产品行为本来就对。 |
| 校验和篡改测试判 `.ok` | **测试前提错了**：往 JSON 里插空格不改变 canonical（它重新序列化）。改为**改数据**（设备 MAC）。 |
| 夹具包里没有 MAC | **测试依赖了宿主状态**：测试宿主没有锁，`collectAll()` 是空包。改为**显式构造**一个含单把锁的包 —— 不依赖宿主存储，测试才可重复。 |
| Keychain 断言失败 | **环境限制**：未签名的单元测试宿主没有 Keychain 权限（`errSecMissingEntitlement`）。改为 `XCTSkipUnless` **显式跳过**并打印原因 —— 既不假通过，也不用无差别红掩盖真问题。 |

---

## 3. 验证链

```
$ node Gates/allgates.js
… 17 道闸门全部通过
tests: 2 个测试文件，176 条断言

$ git show origin/ci-test:meta.txt
commit=f271eb9… run=41242556012 job=golden
test_executed=yes  test_ok=1  test_failed=0  tests_executed=30

$ git show origin/ci-test:test.log
Executed 16 tests, with 0 failures        # GoldenDiffTests（协议层）
Executed 15 tests, with 1 test skipped and 0 failures   # SecurityRegressionTests
Executed 31 tests, with 1 test skipped and 0 failures

$ git show origin/ci-log:meta.txt
errors=0  build_ok=1  archive_ok=1
```

---

## 4. 仍未闭环

### 有断言但**在 CI 上被跳过**的一条
`testLedgerPasswordRoundTripsThroughKeychain`（SEC-01 的核心行为）。
未签名测试宿主拿不到 Keychain 权限 ⇒ 它只在**签了名的真机/本地 Mac**上会真的跑。
这是当前测试覆盖的唯一空洞，且是**平台性**的，不是偷懒。

### P2
- **SEC-01 残余**：Swift `String` 无法可靠清零，进程内仍有一份明文口令副本（平台限制）。
- **SEC-18 残余**：手机钥匙撤销走 `cmd08`，锁端失败时本机记录如何处置需真机确认。
- **SEC-22**：协议层 AES-128-ECB 无 IV/无认证、静态 ekey 可重放 —— 固件限制，App 侧无法根治。
- **SEC-26**：`ITSAppUsesNonExemptEncryption` 对自研 AES 的出口合规归类需法律复核。
- **G-08 / G-12**：无 `DEVELOPMENT_TEAM`；`CBCentralManager` 无 restore identifier ⇒ DFU 抗进程回收做不到。

### P3
`ForEach` 下标身份若干处（只读快照，暂不出 bug）、`.toolbar(.hidden, for:)` 软废弃、
`Shell` body 内读库、`UnlockGate` 作为 Dest 无默认动作、Release 资产名用上传时刻无法反查 commit、
`@unchecked Sendable` 三套手写同步协议仍缺并发单测。

### 需要真机/人工的（CI 替代不了）
SwiftUI 真实渲染与浅色主题观感、手势手感、进度弧节奏、触觉反馈、
BLE 回执、指纹录入、DFU、WebDAV 真实链路。
