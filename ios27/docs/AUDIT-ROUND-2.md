# AUDIT-ROUND-2 · 第二轮：安全 P1 清零 + 引擎回归接回 CI

> 执行日期：2026-11-01 01:00 → 03:00（+08:00）
> 起点 `cad4503`（16 道闸门 / CI 绿）→ 终点 `da83990`（**17 道闸门** / build job 绿）
> 方法：承接第一轮四份审计报告（E / F / D / G）的未闭环清单，逐条修复并用 CI 验证。
> 纪律：每条改动都要过闸门 + 真编译；**CI 跑不了的东西必须如实标注"未执行"，不许假装通过**。

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **16 项**（含第一轮唯一未闭环的 P1） |
| P1 未闭环 | **0**（SEC-01 已修） |
| 闸门 | 16 → **17**（新增 `tests`：测试目标/夹具接线/覆盖面的静态证明） |
| 提交 | 14 |
| CI | `da83990`：**BUILD SUCCEEDED + ARCHIVE SUCCEEDED + errors=0**（build job 绿） |
| 金标测试 | 目标 + 夹具 + 104 条断言已接线；**CI 镜像无 iOS 27 模拟器 runtime ⇒ 本轮未执行**（`test_executed=no`，不是通过） |

---

## 1. 安全：最后一条 P1 清零

### SEC-01 · 门锁密码 / 手机钥匙 / 回收站 / 版本历史 的明文不再进 plist

旧状态：`Keychain` 迁移只覆盖 `skey/bkey/ekey/pins`，而
**门锁密码明文（`LedgerPwd.pwd`）、手机钥匙 `pin/ekey`、回收站与版本历史副本** 仍随
`Store.set → JSONSerialization → UserDefaults` 明文落盘 —— 一份 iTunes/iCloud 备份即可读走全部开门口令。

修法（沿用本仓 `saveKeychain` 已验证的同一套纪律）：

| 结构 | Keychain 账户 | 写侧 | 读侧 |
|---|---|---|---|
| 台账密码 | `ledger.<mac>.pwd.<alias>` | `saveLedger` → `ledgerForPlist`（先写 Keychain，成功才抹明文） | `ledger()` → `ledgerWithSecrets` 回填 |
| 手机钥匙 | `mkey.<mac>.pin.<id>` / `.ekey.<id>` | `MobileKeyService.save` | `MobileKeyService.list` |
| 回收站 | `ledger.<mac>.bin.<itemID>` | `CredBinStore.safeForPlist` | `CredBinStore.all` |
| 版本历史 | `ledger.<mac>.snap.<snapID>.<alias>` | `CredHistoryStore.capture`（裁掉的快照连 Keychain 一起清） | `CredHistoryStore.all` |

配套：
- **启动迁移** `DB.migrateLedgerSecrets()` + `MobileKeyService.migrateSecrets()`（幂等，把旧 plist 明文搬进 Keychain 后抹掉）；
- **删除即清**：`removeDevice` 清该锁全部口令账户；撤销手机钥匙清它的 pin/ekey；清空回收站/还原条目清副本；
- **写失败不丢数据**：Keychain 写失败就保留明文并记遥测 —— 宁可有明文，也不能丢口令。

### 本轮同时修掉的安全项

| # | 问题 | 修法 |
|---|---|---|
| SEC-06 | 备份只带 32 位 FNV 摘要 `d`，把 App 密码降级成可秒破 | 备份带 PBKDF2 `d2`；恢复时**绝不把强摘要降级成弱摘要**（`mergedPasscodeRecord`） |
| SEC-08 | 恢复无条件信任包内 `skey`（只判非空）→ 可用错钥覆盖真钥（软砖）；且能装一个攻击者已知的 App 密码 | 校验 `skey` 必须 32 位 hex、`pins` 必须 8 位 hex；恢复前**要求当前本机密码** |
| SEC-11 | 截图保护只覆盖 2 个视图，且 `isCaptured` 检测不到普通截图 | 监听 `userDidTakeScreenshot` 遮 3 秒；OTP 码值与备份文本也挂上；文案不再承诺"防截图" |
| SEC-13 | 遥测把备注/成员名写进 UserDefaults，随系统备份出机 | 遥测改落 `Caches`（排除备份）文件；审计 diff 只记"变了没变"，不记原文 |
| SEC-19 | 删设备不清备份文件与还原点（它们含该锁 skey） | `purgeLocalArtifacts(mac:)` 删掉含该 MAC 的备份与回滚快照 |
| SEC-28 | 口令验证失败计数在 sheet 的 `@State`，关掉就清零 | 统一走 `AppLock.verify`（持久 fail-streak + 冷却）；胁迫码不得授权这类操作 |
| SEC-29 | `SecretStore.remove` 丢弃 `SecItemDelete` 结果 | 返回 Bool 并记遥测 |
| SEC-31 | `buildKLV` 对 >255 字节**静默截断**（超长 WiFi 密码变成半截口令） | 返回空串让成帧收口判失败，用户看到原因而不是假成功 |
| SEC-12 残余 | 周报 CSV 用另一套转义，且表头是全角逗号（列错位） | 复用 `RecordCSV.field`（标 `nonisolated` 供 Engine 用），表头改半角 |

---

## 2. G-07：引擎金标回归真正接回工程

旧状态：`ios-app/Tests/GoldenDiffTests.swift` 一直存在，但新工程**没有任何测试目标** ——
README 写着"40 条命令帧 / NIST AES 已验证"，实际**一条都没跑**。

本轮做了四件事：

1. **新建 `LockKeeperTests` 目标**（`bundle.unit-test`）+ scheme 的 test 段引用它；
2. **移植金标差分套件**（`ios27/Tests/GoldenDiffTests.swift`，**104 条断言**）：
   AES/NIST 向量 · 40 条命令帧逐字节 · 状态解析 · 日志解析 · 三种帧头 · 广播解析 ·
   ZOTP 冻结时钟 · PID 能力矩阵 · 网关 38 / 钥匙串 43 应答 · 归属推断 · 时间基准 · rc 文案 · inflate；
3. **夹具接线**：`fixtures/golden.json` 作为资源打进测试 bundle，并保留
   `testGoldenFixtureLoaded` —— 资源没打进去时**先红**，而不是让所有断言在空集合上静默通过；
4. **第 17 道闸门 `Gates/tests.js`**：本地（不需要 Mac）静态证明「目标存在 + scheme 引用 + 夹具接线 + 覆盖 9 个协议面 + 断言 ≥40」。

### 诚实边界：CI 上**没有执行**

两个可用镜像都没有 iOS 27 模拟器 runtime：

| 镜像 | 实际 runtime | 结果 |
|---|---|---|
| `xcode-27` | 只有 macOS / tvOS / visionOS / watchOS | `Unable to find a destination` |
| `macos-latest`（Xcode 26.6） | 最高 iOS 26.x | 同上（部署目标是 27.0） |

所以 golden job 现在做三件正确的事：尝试 `xcodebuild -downloadPlatform iOS`；**用 simctl JSON 取真实设备名**
（BSD `sed` 不支持 `\s`，上一版因此把整行当成设备名）；runtime 低于 27 时**明确输出
`test_executed=no` + warning**，而不是假绿或假红。本机读 `origin/ci-test:meta.txt` 就能分辨
"跑过且通过" / "跑过且失败" / "根本没跑"。

> 真跑需要一台带 iOS 27 模拟器的机器：
> `xcodebuild test -project LockKeeper.xcodeproj -scheme LockKeeper -destination "platform=iOS Simulator,name=<设备>"`

---

## 3. CI 自身也被修了三处（这是本轮最有价值的发现）

| 问题 | 为什么危险 | 修法 |
|---|---|---|
| **`errors=0` 不等于 job 绿** | 测试步骤失败时 archive 根本不跑（`archive.log` 不存在），而 `errors` 仍是 0 —— 本机会把红读成绿 | `meta.txt` 增加 `build_log/archive_log/build_ok/archive_ok` 逐步骤证据 |
| **测试日志只 tee stdout** | destination 解析失败时日志只剩 6 行调用头，完全看不出为什么红 | 加 `2>&1`；并在 `errors.txt` 里收录 `Testing failed:` |
| **两个 job 抢同一个孤儿分支** | golden 与 build 并发 force-push `ci-log` 会互相覆盖 | golden 改用独立的 `ci-test` 分支 |

---

## 4. 其余修复

| 类别 | 项 |
|---|---|
| HIG / 设计 | D-09：**高对比 / 减少透明**从"死开关"变成真消费者（描边强度、标签栏玻璃退化）；E-O4：政策开关改由子视图持有 `@State`（`Binding(get: isOn)` 的值快照会让 Toggle 弱信号下卡住不动） |
| SwiftUI | 5 处 `Task.sleep(nanoseconds:)` → `Task.sleep(for:)` |
| 交付文档 | README / COMPLETION 的计数（148 文件 / 16 道闸门 / CI run）与 IPA 链接改为"只指 Release 页"（写死文件名必 404）；`WARNINGS.md` 标注为历史快照（当前 0 warning）；`SecretStore` 的 Keychain service 名加"禁止改动"注释；Logger subsystem 修正；job 加 `timeout-minutes`；删掉死 `import BackgroundTasks` |
| 功能 | G-06：8 套备选 App 图标接线（`CFBundleAlternateIcons` + 外观页换图标入口）—— 旧版有这个功能，新版曾静默丢失 |

---

## 5. 被 CI 抓到的真实错误（都是本轮新写的代码）

| run | 错误 | 根因 |
|---|---|---|
| 41225887928 | `StatsKit.swift:69` ActorIsolatedCall；`LockStatusScreen.swift:163` `'State' cannot be constructed` | `RecordCSV.field` 在主 actor 枚举里却被 Engine 调用；在 struct init 里构造 `State` |
| 41228798601 | 10 条 destination 错误 | `xcode-27` 镜像没有 iOS 模拟器 runtime |
| 41229781300 | 设备名是整行文本 | BSD `sed` 不支持 `\s` |

---

## 6. 验证链

```
$ node Gates/allgates.js
swiftparse / types / swiftcheck / tokens / contrast / glass / motion / a11y /
dynamictype / reducedmotion / crosprivate / callsig2 / lineage / workflow /
destmap / privacy / tests — 全部 OK

allgates: 全部 17 道闸门通过
tests: 1 个测试文件，104 条断言，15 条判据全部通过
```

```
$ git show origin/ci-log:meta.txt
commit=da8399012bf8f9dda74238e48858da82e388e212
run=41231274543   job=build   errors=0
build_log=yes  archive_log=yes  build_ok=1  archive_ok=1

$ git show origin/ci-test:meta.txt
commit=da8399012bf8f9dda74238e48858da82e388e212
job=golden  test_executed=no      # ← 镜像无 iOS 27 runtime，如实标注
```

---

## 7. 仍未闭环（下一轮的输入）

### P2
- **SEC-14**：备份校验和仍是 32 位 FNV（无密钥），mismatch 只警告 —— 明文包可被任意重算。
- **SEC-15**：`LockService` 与 `HardwareService` 共用 `BLEService` 单连接、各自一套 waiter，响应可能被错消费者拿走。
- **SEC-16 残余**：解析路径仍用宽容的 `HexKit.bytes`（`strictBytes` 已存在但没接上）。
- **SEC-18 残余**：手机钥匙「彻底删除」已改走 revoke，但锁端 `cmd08` 失败时本机记录的处置仍需真机确认。
- **SEC-32**：凭证到期通知「删旧 + 排新」跨队列竞态。
- **SEC-26**：隐私清单/隐私政策与 WebDAV 上传能力的一致性，`ITSAppUsesNonExemptEncryption` 需出口合规复核。
- **G-08**：`project.yml` 无 `DEVELOPMENT_TEAM`，README 的本地 ⌘R 路线需写明"签名自备"。
- **G-12**：`CBCentralManager` 无 restore identifier ⇒ DFU 抗进程回收做不到，文档应降级为"后台尽力"。

### P3
`ForEach` 用 `.indices`/`\.offset` 身份 9 处、`KeysScreen` 的 `now` 只在 `onAppear` 刷新、
`AXSettings` 的 `@State` 镜像（双真相）、`ShareToAndroid` 的 `deliverable` 死代码、
`.toolbar(.hidden, for:)` 软废弃、`Shell` body 内读库、`UnlockGate` 作为 Dest 无默认动作、
Release 资产名用上传时刻无法反查 commit。

### 唯一真正的验证缺口
**金标测试从未在 CI 上真跑过**（镜像无 iOS 27 runtime）。这是"不要再出现 BUG"这条承诺的
最后一块拼图 —— 需要一个带 iOS 27 模拟器的 runner，或把部署目标临时降到镜像支持的版本跑一次。
