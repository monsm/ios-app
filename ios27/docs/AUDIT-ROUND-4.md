# AUDIT-ROUND-4 · 第四轮：金标终于真跑起来了

> 执行日期：2026-11-01 04:00 → 05:00（+08:00）
> 起点 `60ec123` → 终点 `9b62e7c`
> 方法：继续修 AUDIT-E/F 未闭环项；同时把"金标从未执行"这个跨三轮的缺口真正关掉。

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| **金标测试** | **真的执行了：Executed 16 tests, with 0 failures**（CI run `41238960936`，`xcode-27` + iOS 27 模拟器） |
| 本轮修复 | 6 项（SEC-24 · SEC-30 残余 · E-13 · 3 条测试自身的错误） |
| 闸门 | 17 / 17 |
| CI | `9b62e7c`：BUILD SUCCEEDED + ARCHIVE SUCCEEDED + errors=0；golden job `test_ok=1` |

---

## 1. 跨三轮的验证缺口：关掉了

**之前的状态**：`GoldenDiffTests` 一直存在，但

- 第 1 轮发现"新工程没有测试目标"；
- 第 2 轮把目标 + 夹具 + 104 条断言接上，但 CI 两个镜像都没有 iOS 27 模拟器 runtime ⇒ `test_executed=no`；
- 第 3 轮尝试把协议层编成 macOS bundle，被 `DiagKit`(UIKit) 依赖闭包挡回，如实回退。

**这一轮找到的办法**：`xcode-27` 镜像**有 iOS 27 SDK**，只是默认没装模拟器 runtime。
让 golden job 先 `xcodebuild -downloadPlatform iOS`，再用 `simctl` 的 **JSON** 取设备名
（BSD `sed` 不支持 `\s`，之前的写法把整行当成设备名，一条断言都没跑）。

结果（`git show origin/ci-test:test.log`）：

```
Test Case testAES passed · testAttribution passed · testCmds passed · testEpoch passed
testFirmwareVersionCompare · testGatewayStatus · testGoldenFixtureLoaded · testHeaderVariants
testInflate · testKeychainStatus · testParseAdv · testParseLogs · testParseStatus
testPidCapabilities · testRcMsg · testZOTP
Executed 16 tests, with 0 failures (0 unexpected) in 13.238 seconds
** TEST SUCCEEDED **
```

这 16 条覆盖：40 条命令帧逐字节 / NIST AES 向量 / 状态解析 / 日志解析 / 三种帧头 /
广播解析 / ZOTP 冻结时钟 / PID 能力矩阵 / 网关 38 与钥匙串 43 应答 / 归属推断 /
时间基准 / rc 文案表 / inflate 往返 / 固件版本比较。

---

## 2. 第一次真跑就抓出 3 个问题（全部在**测试**里，不是产品里）

这正是"跑起来才有价值"的证明 —— 三条都是静态闸门永远看不到的：

| # | 现象 | 判定 |
|---|---|---|
| 1 | 30+ 条命令帧"不一致" | **测试过严**：JS 出小写 hex、Swift 出大写。十六进制大小写不是协议语义。改为按 `lowercased()` 比较 —— 长度/顺序/内容仍逐字符比，截断与错序照样拦得住。 |
| 2 | `testEpoch` 差 28800 秒 | **测试的时区假设**：`epochMs` 按**本地墙钟** 2010-01-01 计算（APK 语义，偏移自己抵消），夹具里那个毫秒值是**东八区**生成的；UTC runner 上必然差 8 小时。改为断言**时区无关的不变量**（epoch 自换算为 0、与夹具基准之差必须是整小时且 ≤14h）。 |
| 3 | `testAttribution` 全 nil | **夹具编号过期**：夹具里 `type: 4/3` 是修正前的旧编号，而本仓权威表是 `openKind = [11:key, 16:temp, 17:pwd, 19:fp]`（按 APK `We` 表勘误）。改为按权威表喂事件，并**断言映射关系**，而不是把勘误退回去迎合夹具。 |

三条都改在测试侧，**没有为了让测试变绿而改产品代码** —— 这一点比结果本身重要。

---

## 3. 本轮的产品修复

### SEC-24 · 深链能静默切换"当前锁"

`kf://device?mac=...` 原来点一下就把当前锁切过去。用户可能在拿 B 的电量/台账去按 A 的门 ——
正是本 App 最怕的"看着对、其实错"。现在改成**确认弹窗**（显示目标锁名，可"保留当前锁"），
确认后才写 `currentMac` 并重载。

顺带收紧 `kf://records?k=`：行 id 形状是 `<mac>#<序号>`，形状不对就不塞进查询
（本页所有查询都以当前锁为作用域，脏输入只会得到"没找到"，但没必要让它进查询）。

### SEC-30 残余 · 选文件时先整份读进内存，之后才查大小

`readBackupFile` 用 `String(contentsOf:)` **整份读入**，而 32MB 闸在 `parsePreview` 里 ——
闸生效时内存已经被吃满了。现在先用 `fileSizeKey` 查大小再读，并与引擎共享同一个常量
`BackupStudio.maxImportBytes`（避免两处各写一个数字）。

### E-13 · 无障碍偏好的 `@State` 镜像会过期

`AccessibilityScreen` 的六个 `@State` 是持久层的镜像，`@State` 初值只在视图首次创建时取一次。
外观页/设置页改了同一个键、或「恢复默认外观」整体重置之后，这一页仍显示旧值 —— 两份真相。
保留 `@State`（点一下要有反馈），增加 `onAppear` 从持久层重新同步。

---

## 4. 验证链

```
$ node Gates/allgates.js
… 17 道闸门全部通过
tests: 1 个测试文件，108 条断言

$ git show origin/ci-log:meta.txt
commit=9b62e7c… run=… errors=0  build_ok=1  archive_ok=1

$ git show origin/ci-test:meta.txt
job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=16
```

---

## 5. 仍未闭环

### P2
- **SEC-01 残余**：口令已进 Keychain，但 Swift `String` 无法可靠清零，进程内仍有一份明文副本（平台限制）。
- **SEC-18 残余**：手机钥匙撤销走 `cmd08`，锁端失败时本机记录如何处置需真机确认。
- **SEC-22**：协议层 AES-128-ECB 无 IV/无认证、静态 ekey 可重放 —— **固件/协议限制**，App 侧无法根治，只能在文档如实写。
- **SEC-26**：`ITSAppUsesNonExemptEncryption: NO` 对自研 AES 的出口合规归类需法律复核。
- **G-08**：`project.yml` 无 `DEVELOPMENT_TEAM`，README 的本地 ⌘R 路线要写明"签名自备"。
- **G-12**：`CBCentralManager` 无 restore identifier ⇒ DFU 抗进程回收做不到，文档应降级为"后台尽力"。

### P3
`ForEach` 下标身份仍有若干处（只读快照，暂不出 bug）、`.toolbar(.hidden, for:)` 软废弃、
`Shell` body 内读库、`UnlockGate` 作为 Dest 无默认动作、Release 资产名用上传时刻无法反查 commit、
`@unchecked Sendable` 三套手写同步协议缺并发单测。

### 真正的验证缺口（已大幅收窄）
金标**协议层**已在 CI 真跑（16/16）。
仍缺的是**界面层与真实硬件**：SwiftUI 渲染、手势、BLE 回执、指纹录入、DFU、WebDAV
—— 这些需要真机/模拟器人工验证，任何 CI 都替代不了。
