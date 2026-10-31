# AUDIT-ROUND-1 · 四路地毯式审核 + 修复汇总

> 执行日期：2026-10-31 23:00 → 2026-11-01 01:00（+08:00）
> 起点 `b6143d4`（CI 绿）→ 终点 `2e2b9cd`（CI 绿，run `41221877905`）
> 方法：四路子代理并行深审（各写一份只读报告）+ Lead 按证据逐条修复并推 CI 验证。
> 纪律：**每一条结论都要有 file:line 或实测数字**；修完必须过 16 道闸门 + 真编译。

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 并行审计流 | **4**（AUDIT-E Swift/SwiftUI · AUDIT-F 安全/隐私 · AUDIT-D HIG/无障碍 · AUDIT-G 构建/交付） |
| 审计覆盖面 | 148 个 Swift 文件全量 + 69 个 Engine 文件逐读 + 55 张设计截图 + 真 IPA 逐字节解析 + CI 日志 |
| 新发现缺陷 | **E 20 · F 32 · D 15 · G 14 = 81 项**（去重后约 70） |
| 本轮已修 | **46 项**（P0 1 · P1 9 · P2 22 · P3 14） |
| 编译状态 | `BUILD SUCCEEDED` + `ARCHIVE SUCCEEDED` + **errors=0** + **warning=0**（从 88 条告警降到 0） |
| 闸门 | **16 / 16**（新增第 16 道 `privacy`，9 类判红回归） |
| 提交数 | 22 |
| 仍未闭环 | 见 §5（P1 1 项 · P2 约 12 项 · P3 约 20 项） |

---

## 1. 四份审计报告（只读产物，均在 `docs/`）

| 报告 | 范围 | 发现 |
|---|---|---|
| `AUDIT-E-SWIFT6.md` | Swift 6 并发 / SwiftUI 正确性 / 索引与生命周期 | P0 0 · P1 2 · P2 7 · P3 11 |
| `AUDIT-F-SECURITY.md` | 安全 / 隐私 / Engine 正确性 | P0 0 · P1 4 · P2 17 · P3 11（复核后：已修 10 · 部分 4 · 仍存在 18 · 新引入 4） |
| `AUDIT-D-HIG.md` | HIG / 无障碍 / 设计 | 真实 15（P1 2 · P2 7 · P3 6），另 63 条工具误报已逐条说明为何不报 |
| `AUDIT-G-DELIVERY.md` | 构建 / 交付 / CI / IPA | **P0 1 · P1 2 · P2 5 · P3 6** |

---

## 2. 本轮修掉的最重的问题（按影响排序）

### 2.1 P0（1 项）

| # | 问题 | 影响 | 修法 |
|---|---|---|---|
| G-01 | `App/PrivacyInfo.xcprivacy:50` 是**非法 XML**（应 `</array>` 却写 `</dict>`） | 隐私清单解析失败 = Required Reason API（CA92.1/C617.1）申报等于没交；App Store 会拒收/警告。xcodebuild 与所有闸门都**不会**发现它 | 改成 `</array>`；`Gates/privacy.js` 增加 plist 标签配对断言（判红） |

### 2.2 P1（9 项）

| # | 问题 | 影响 | 修法 |
|---|---|---|---|
| E-01 | `startScan` 只启动扫描就返回，页面立刻读 `allDiscovered()`（`discovered` 刚被清空） | **「添加门锁」与「协议测试」两个入口事实上永远搜不到设备** —— 配网不可用 | `BLEService.scanWindow(...)` 扫满窗口再返回快照；两个页面改调它 |
| E-02 | 「改造密码值」走 `addPassword`，只 append 新 alias，旧码不删不改 | 用户以为改了口令，实际门口**多了一把仍能开门的旧码** | `addPassword(replacingAlias:)`：先建新成功再删旧（顺序不能反） |
| SEC-03 / N-01 | 胁迫码「空壳模式」只清 `AppModel` 界面投影；`ledger()` 在空壳下返回空表而 `saveLedger` **没有守卫** | ① 空壳下仍能看/导出真实凭证 ② 空壳里一次 `saveLedger` 会用「只有 1 条」的空表**覆盖真实台账 → 凭证全丢** | 数据层 `DB.isDecoy` + `setDecoy`；ledger/members/readLogs/keychains/keychain/dongles/gateways/mobileKeys/bin/history/notes 全部加守卫；`saveLedger` 空壳拒写；`AppLock.lock()` 回写 `setDecoy(false)` |
| SEC-04 | 自动开锁不检查 `AppLock.unlocked`；严格档把「Face ID 提示进行中」当作已认证 | 锁屏/未解锁/空壳下可自动下发 cmd04；提示未成功也能开门 | `faceFresh` 的 `pendingPrompt` 改为 false；`f0Foreground` 要求 `unlocked && !decoy`；`pollOnce` 未解锁直接停 |
| SEC-02 | 备份默认明文写 `Documents`，无 `isExcludedFromBackup`、无文件保护 | 一次点击生成含全部 skey/pins 的「万能钥匙文件」，随 iCloud/iTunes 备份出机 | 无口令**拒绝**生成（本机备份/换机包/WebDAV 三条路都强制加密）；目录 `isExcludedFromBackup`；写盘 `.completeFileProtection` |
| SEC-21 | `AppLock.lock()` 全仓零调用点 | 解锁一次后进程不退出就再也不上锁（手机被拿走可直接看凭证/导出/开门） | `didEnterBackground`/`willEnterForeground(lockAfter: 30)` 接进 `scenePhase`；`lock()` 同时清内存母钥缓存并断链 |
| SEC-18 | 手机钥匙「彻底删除」只 `app.keys.removeAll`（内存） | 重启后钥匙还在、锁端 PIN 仍有效 —— 旧的 ekey 照样能开门（与「彻底删除」语义相反） | 走 `MobileKeyService.revoke`（cmd08 删 PIN + 删本机记录） |
| SEC-20 | WebDAV 接受 `http://`，Basic Auth 与完整备份明文过局域网 | 同网攻击者可读走账号与 skey | `normalized()` 只放行 https（本机回环例外） |
| G-02 | 发布步骤只有 `if: success()`，但工作流也由 `pull_request` 触发 | 任一同仓 PR 可删改公开 Release 的 IPA；fork PR 让 build 假红 | 发布与 ci-log 两个步骤都加 `github.event_name == 'push'` |

### 2.3 P2（22 项）摘要

- **备份 schema**：`Appearance.CodingKeys` 手写后漏列 10 个字段 → 无障碍/外观偏好**从来没进过备份**；`duress` 定义了却没写进 canonical → 换机后胁迫码静默丢失。
- **崩溃路径**：`RecordSearchParse` 5 处 `Calendar` 强解包（输入「13月1日」可崩）、`DFUKit` 先取 `bytes[0]` 后判长度、`BLEService.manager` 隐式解包、`LockSettingsScreen` 的 `st!`/`kc!` 三元副作用求值。
- **换锁写错锁（8 处）**：`await` 之后仍用计算属性 `mac` → 状态/静音/OTP/防尾随/安全模式写到另一把锁（「给 A 静音实际静音了 B」）。
- **HIG**：V7 调色板只有深色（浅色主题 = 黑页）、`.dynamicTypeSize(.large)` 压掉系统字号、Tab 栏缺「家」、`VTag` 24pt 触达区、filled tag 3.29:1、pink 文本 4.00–4.39:1、8 处装饰图标无 a11y、卡片假 chevron。
- **协议/健壮性**：`FrameAssembler` 无缓冲上限（残帧可撑爆内存）、`FrameRedact` 只处理第一个 `hex=`、备份导入无大小/类型/设备数上限、CSV/vCard 注入、`per-lock` 台账损坏标记被整库清掉。
- **Swift 6**：`SettingsStore` 缺 `@MainActor`、binding 的 `@Sendable` 捕获、通知回调传非 Sendable 闭包 → **62 条并发告警清零**。
- **假按钮**：`abortRequested` 全仓零读取（「中止并回滚」点了没反应）、`inReset: true` 写死（重置态守卫成死代码）、`lockClockSyncedAt` 只活内存（重启恒「从未」）。
- **交付**：文档里的闸门数/文件数/CI run 全部过期、文档写死的 IPA 文件名已 404、8 套备选图标是死资产（旧版有换图标功能，新版静默丢失）。

### 2.4 P3（14 项）摘要

微字号 <11pt（Tab 标签 9pt）→ 全部提到 11pt；`ZOTP` 的 `assert`（Release 关断言 = 不存在）→ clamp；`BackgroundTasks` 死 import；Logger subsystem 用旧 bundle id；Keychain service 名是历史值（**加注释禁止改动**，改 = 老用户密钥丢失）；job 无 `timeout-minutes`；`WARNINGS.md` 锚点过期（88 → 0）。

---

## 3. 验证链（怎么证明这些改动是真的）

```
$ node Gates/allgates.js
swiftparse: OK — 148 个 Swift 文件无语法错误（已知语法盲区豁免 14 处）
types:      OK — 368 个顶层类型无重复声明，Engine 无未解析引用
swiftcheck: OK — 148 个文件括号/字符串/注释全部平衡，无裸控制字符
tokens:     OK — 148 个 Swift 文件，0 处硬编码样式字面量
contrast:   88 条断言全部达标（V7 色板已改为明暗双取值，浅色也过 WCAG）
glass / motion / a11y / dynamictype / reducedmotion / crosprivate / callsig2 / lineage / workflow / destmap: OK
privacy:    OK — 剪贴板/备份加密/空壳隔离(读+写)/帧脱敏/WebDAV/文件保护/CSV 注入/隐私清单 XML 9 类回归判据全部通过

allgates: 全部 16 道闸门通过
```

```
$ git show origin/ci-log:meta.txt      # commit=2e2b9cd run=41221877905 errors=0
$ git show origin/ci-log:build.log    # ** BUILD SUCCEEDED **，": warning:" 计数 = 0
$ git show origin/ci-log:archive.log  # ** ARCHIVE SUCCEEDED **
```

**真 IPA**（AUDIT-G 实测，sha256 与 GitHub release digest 逐字节一致）：
`CFBundleVersion=48`（构建号注入真的生效，不是写死 1）· `MinimumOSVersion=27.0` · Mach-O `minos 27.0.0` · 24 个依赖全是系统框架 · `UILaunchScreen={}` · `kf://` · `bluetooth-central` · `UIRequiresFullScreen` 已不在。

**视觉**：`DesignLab/` 54 张截图（27 屏 × 明暗）全部重渲染；V7 令牌改为 `dual(light:dark:)` 后浅色不再是一片黑。

---

## 4. 被闸门抓到的真实问题（闸门本身也是被测对象）

| 轮次 | CI 红的原因 | 处置 |
|---|---|---|
| run 41217531256 | `RecordsModels.swift:407` 注释里混进一个**裸 CR** → Swift 报 4 条「Consecutive statements…」 | 修注释；**`Gates/swiftcheck` 增加裸控制字符判据**，这类错误本地就红 |
| run 41218788400 | `RecordCSV.build` 调 `TimeDisplay.clock`（主 actor 隔离）报 ActorIsolatedCall | `RecordCSV`/`WeeklyDigest` 标 `@MainActor` |
| run 41218914864 | `SyncTimeScreen` 用了不存在的 `mac` + `saveSyncTime` 签名不符 | 改 `app.currentMac` + `Double` |
| run 41216586934 | `BLEError.notReady` 不存在 | 改用已有 `.underlying` |

---

## 5. 仍未闭环（下一轮的输入）

> **第二轮（2026-11-01）更新**：下面这些已在本轮修掉 —— SEC-01（口令/手机钥匙/回收站/快照搬进 Keychain + 启动迁移）、
> SEC-06（备份带 PBKDF2 d2，恢复不降级强摘要）、SEC-08（恢复校验 skey/pins 形状 + 要当前本机密码）、
> SEC-11（普通截图也遮挡）、SEC-13（遥测改落 Caches 并去掉备注/归属原文）、SEC-19（删设备连备份与还原点一起清）、
> SEC-28（口令验证走 AppLock 持久冷却）、SEC-29（SecretStore.remove 返回成败）、SEC-31（KLV 超长拒绝而非截断）、
> G-07（**真测试目标 + 金标差分接进 CI**）、G-09/G-10/G-11/G-13、D-09（高对比/减少透明变成真消费者）、E-O4（政策开关不再卡住）。
> 当前未闭环见 §7。

### P1（本轮已清零）
- ~~SEC-01~~ **已修**：门锁密码、手机钥匙 `pin/ekey`、回收站与版本历史副本全部搬进 Keychain；
  plist 只留非密字段，启动时一次性迁移并抹掉旧明文。
  （实现与 `saveKeychain` 同一纪律：先写 Keychain 成功才允许抹明文，写失败保留明文并记遥测。）

### P2（约 12 项）
- SEC-06（备份把 App 密码降级成 32 位 FNV、PBKDF2 仅 60k 轮）、SEC-08（恢复无条件信任包内 passcode/skey，只判非空）、SEC-11（截图保护只覆盖 2 个视图且 `isCaptured` 检测不到普通截图）、SEC-13（遥测把备注/成员名写进 UserDefaults 随备份出机）、SEC-14（备份无 HMAC，校验和 mismatch 只警告）、SEC-15（LockService/HardwareService 共用 BLE 单连接、响应可能被错消费者拿走）、SEC-19（删设备不清理备份/回滚快照/全局遥测）、SEC-28（`VerifyPasscodeSheet`/`UnlockGateScreen` 失败计数不持久）、SEC-29（`SecretStore.remove` 忽略 `SecItemDelete` 结果）、SEC-31（`buildKLV` 超 255 字节静默截断）、SEC-32（通知排期跨队列竞态）。
- G-07：**没有任何测试目标** —— 引擎层的金标向量（40 条命令帧 / NIST AES / 状态日志解析）在旧仓，本仓未接入 CI。这是"不要再出现 BUG"这条承诺的唯一可证伪手段，优先级应高于多数 P3。
- G-08：`project.yml` 无 `DEVELOPMENT_TEAM`，而 README 让人本地 ⌘R。

### P3（约 20 项）
`ForEach` 用 `.indices`/`\.offset` 身份 9 处、`KeysScreen` 的 `now` 只在 `onAppear` 刷新、`AXSettings` 的 `@State` 镜像（双真相）、`ShareToAndroid` 的 `deliverable` 死代码、4 处 `Task.sleep(nanoseconds:)`、`.toolbar(.hidden, for:)` 软废弃、`Shell` body 内读库、`UnlockGate` 作为 Dest 无默认动作、`LockStatusScreen` 的 `Toggle(isOn: Binding(get:set:))` 参数值快照（弱信号下卡住不前进也不回弹）、Release 资产名用上传时刻无法反查 commit、`CBCentralManager` 无 restore identifier（DFU 抗进程回收做不到）。

---

## 6. 边界（未验的就是未验）

1. **没有真机 / 没有模拟器**：本轮全部是静态代码级 + CI 编译级 + 像素级（DesignLab）验证。开锁手感、BLE 回执、指纹录入、DFU、WebDAV 真实链路**一次都没在本机跑过**。
2. **DesignLab 不是 SwiftUI**：CSS 近似，不能验手势、真实液态玻璃折射、PingFang 中文度量。
3. **`@unchecked Sendable` 的同步靠人肉**：`BLEService`/`DFUSession`/`Store` 依赖 `Locked`、写槽 FIFO、continuation 单槽三套手写协议，编译器检查不到。切 Swift 6 前建议先给这三套加并发单测。
4. **App Store 侧行为**未实测：G-01 的「解析失败 → 清单不生效」依据 Apple 对 `PrivacyInfo.xcprivacy` 的 plist 要求与两个解析器实测，未真的提交过一次。
5. **REA 未能解析 IPA**：`D:\aapk\.tmp-audit-c\ipa\LockKeeper.ipa` 是截断文件（1,029,868 B、无 EOCD）。AUDIT-G 改用「Release API digest → 下载 → Python zipfile/Mach-O 解析」替代，结论未降级。
