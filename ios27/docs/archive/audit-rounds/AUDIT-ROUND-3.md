# AUDIT-ROUND-3 · 第三轮：并发/协议/备份正确性 + 测试基础设施

> 执行日期：2026-11-01 03:00 → 04:00（+08:00）
> 起点 `6cf880e`（17 道闸门 / CI 绿）→ 终点 `16ce2c6`（17 道闸门 / CI 绿）
> 方法：继续啃 AUDIT-E/F 的未闭环清单；每一条都用 CI 真编译验证。

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **8 项**（P2 6 · P3 2） |
| 静态高危扫描 | P0 0 · P1 0 · **P2 23**（从 26 降）· P3 9 |
| 闸门 | **17 / 17** |
| CI | `16ce2c6`：**BUILD SUCCEEDED + ARCHIVE SUCCEEDED + errors=0** |
| 被 CI 抓到的自身错误 | 2 次（都当场修掉，见 §3） |

---

## 1. 本轮修掉的缺陷

### SEC-15 · P2 · BLE 回包被"错的那个服务"消费（真并发正确性）

**问题**：`LockService` 与 `HardwareService` 共用同一条 BLE 连接，各自维护自己的 waiter，
而两个 waiter **只按 `cmd` 号匹配**。同时发同一条命令时（门页 `cmd03` 与硬件页 `cmd03`），
回包会被先挂上的那个拿走 —— 结果是把 A 的目标状态写进 B 的快照，或一方等满超时。

**修法**：给帧订阅加**归属**。

```swift
// BLEService
func onFrame(owner: String, _ cb: @escaping (ParsedFrame) -> Void)
func setFrameOwner(_ owner: String?)      // 发命令前声明这条连接归谁
// emit 只投给归属方；无归属时照旧广播（配网期两边都要看状态帧）
```

关键点：`LockService` / `HardwareService` 在**成功路径与失败路径**都要释放归属 ——
漏一条就会出现"另一个服务的命令永远超时"。

### SEC-32 · P2 · 通知"取消"会删掉刚排好的提醒

`cancelAlerts` 与 `scheduleAlertsOrdered` 原来各起一条 `getPendingNotificationRequests`
异步序列。删凭证时"取消"还在飞，同一时刻的"排新"已把新通知写进 pending，
取消回调再把它们一起删掉 —— 表现是"删了凭证提醒还在 / 改期后一条都不响"。

**修法**：三类动作（删旧 / 排新 / 取消）排进**同一条串行队列**，逐个完成后 `done()` 再取下一个。
任何路径都必须调 `advance()`，否则整条链会卡死。

### SEC-14 · P2 · 校验和不一致只警告，恢复照旧往下走

`ChecksumState.mismatch` 原来只显示在预览卡上。而"包被截断"恰恰是最该拦的情况 ——
拿半截包覆盖真数据比拒绝更糟。现在三条恢复路径（本机备份 / 换机包 / 文件导入）**全部拒绝**。

### SEC-16 残余 · P2 · 协议解析用宽容 hex，脏帧会被读成合法帧

`HexKit.bytes()` 的宽容语义是**为 JS 差分服务的**（复刻 `parseInt(pair,16)`：首字符非 hex → 0）。
协议解析路径用它，等于让含噪声的帧"成功"解析成垃圾 KLV。已把 `parseKLV` / `parseResponse` /
`injectToken` / 帧重组 / 广播解析全部换成 `strictBytes`。

### E-11 / E-12 / E-14 · P3 · SwiftUI 正确性

| # | 问题 | 修法 |
|---|---|---|
| E-11 | 成员列表用 `ForEach(archived.indices, id: \.self)` —— 归档/恢复会重排数组，下标身份让 SwiftUI 复用错行（"点 A 打开 B"） | 改用 `id: \.id`（成员 id） |
| E-12 | `KeysScreen.now` 只在 `onAppear` 刷新 ⇒ 跨零点后"还剩 N 天"的角标与颜色不更新 | 按分钟重算（一次 `Date()`，成本可忽略） |
| E-14 | `ShareToAndroid.deliverable` 是**死代码**：页面文案说"本机还没有可交付的钥匙"，而 `build()` 只看 `currentKeychain` —— 停用/已过期/无 ekey 的手机钥匙照样生成二维码并显示"可以扫码导入" | `build()` 先过 `deliverable` |

---

## 2. 一次被证伪的尝试（记下来，免得下一个人再走一遍）

想把协议层编成 **macOS 原生测试 bundle**（那样 CI 不需要 iOS 模拟器就能真跑金标）。
已经做到"能编译"这一步 —— 但依赖闭包一路拖到 `DiagKit`（UIKit + CoreBluetooth + UserNotifications）、
`Store`（Security）、整个 DB 层。硬抽出来要么改生产代码，要么写一堆假实现 ——
**后者等于测假货，比不测更糟**。已回退，并把原因写进 `project.yml` 与 `docs/AUDIT-ROUND-2.md`。

> 结论：金标要真跑，仍然需要一台带 **iOS 27 模拟器 runtime** 的机器。
> golden job 会如实输出 `test_executed=no`，不会假装通过。

---

## 3. 本轮被 CI 抓到的自身错误（都是新写的代码）

| run | 错误 | 根因 |
|---|---|---|
| 41234127519 | `CredentialOrgState.swift:48` "contextual type for closure argument list expects 1 argument" | `enqueue` 的闭包签名是 `(@escaping () -> Void) -> Void`，调用点却写成零参数 |
| 41233597469 | （上一轮）`StatsKit` ActorIsolatedCall / `State` 构造 | 已在第二轮修复 |

值得记一笔：这次能立刻定位，靠的是**第二轮给 `meta.txt` 加的逐步骤证据** ——
`build_ok=0 / archive_ok=0` 一眼就能看出"编译就红了，不是测试或打包问题"。

---

## 4. 验证链

```
$ node Gates/allgates.js
… 17 道闸门全部通过

$ node Tools/static-audit.js
static-audit: 148 个 Swift 文件
static-audit: P0=0 P1=0 P2=23 P3=9      # 第二轮是 P2=26

$ git show origin/ci-log:meta.txt
commit=16ce2c67a676e28e501e77c2425335e03ae7bc1e
run=41236327726   job=build   errors=0
build_log=yes  archive_log=yes  build_ok=1  archive_ok=1
```

---

## 5. 仍未闭环

### P2（约 8 项）
- **SEC-01 残余风险**：口令已进 Keychain，但 Swift `String` 无法可靠清零；
  进程内仍会有一份明文副本（平台限制，只能靠缩短生命周期）。
- **SEC-18 残余**：手机钥匙撤销已走 `cmd08`，但锁端失败时本机记录如何处置需真机确认。
- **SEC-26**：隐私清单/隐私政策与 WebDAV 上传能力的一致性；`ITSAppUsesNonExemptEncryption`
  对自研 AES 的出口合规归类需法律复核。
- **SEC-22**：协议层 AES-128-ECB 无 IV/无认证、静态 ekey 可重放 —— **固件/协议层限制**，
  App 侧无法根治，只能在文档里如实写。
- **G-08**：`project.yml` 无 `DEVELOPMENT_TEAM`，README 的本地 ⌘R 路线要写明"签名自备"。
- **G-12**：`CBCentralManager` 无 restore identifier ⇒ DFU 抗进程回收做不到，文档应降级为"后台尽力"。
- **SEC-24**：`kf://device?mac=` 深链可切换当前锁，建议加显式确认。
- **SEC-30 残余**：`String(contentsOf:)` 读用户选的文件没有大小上限（备份文本路径已加 32MB 闸，
  但 `readBackupFile` 仍先整份读入内存）。

### P3（约 9 项）
`ForEach` 下标身份仍有若干处（列表为只读快照，暂不出 bug）、`AXSettings` 的 `@State` 镜像（双真相）、
`.toolbar(.hidden, for:)` 软废弃、`Shell` body 内读库、`UnlockGate` 作为 Dest 无默认动作、
Release 资产名用上传时刻无法反查 commit、`@unchecked Sendable` 三套手写同步协议缺并发单测。

### 唯一真正的验证缺口（未变）
**金标测试从未在任何机器上真跑过**。它已接线（目标 + 夹具 + 104 条断言 + 17 道闸门静态证明），
但执行需要 iOS 27 模拟器 runtime。这是"不要再出现 BUG"这条承诺的最后一块拼图。
