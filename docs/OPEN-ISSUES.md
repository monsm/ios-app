# 未决项裁决台账


> ⚠ **本档是历史台账，不是当前代码的说明书。**
> 里面的 `文件:行号` 指针记录的是**写档当时**的位置；后续精简/重构后部分文件已删或行号已移，
> 那些失效指针是台账的**正常内容**（它记的就是"某批删了什么"），不是错误。
> 想知道某个功能现在还在不在，请看 `docs/feature-web/features.json`（那份由工具从 inventory 重算）。

> 来源：`docs/feature-web/features.json` 的 `meta.unresolved`（129 条），由 9 份侦察兵产出。
> 本文按批裁决，每条给 **分类 + 结论 + 建议动作**。
>
> 分类口径：
> - **真缺陷**：行为与意图不符，用户可感知或安全相关 → 要修
> - **注释漂移**：代码对、注释错（或反之） → 修注释
> - **待真机**：本机无法判定，必须上真锁/真设备 → 记入验证清单
> - **可忽略**：设计如此 / 已有等价实现 / 影响可接受 → 归档
>
> 状态标记：`[已修]` / `[待办]` / `[已核实-无需改]` / `[待真机]`

---

## 第一批：协议 / 数据 / Android（37 条）

### A. 真缺陷（3 条）

#### A1 `[已修]` kf_trial_guard 只读不写 —— 只读试验模式永远打不开

- **位置**：`App/Services/LockService.swift:217-218`
- **事实**：`if DB.store.getBool("kf_trial_guard", false) { try ZKProtocol.assertReadOnly(cmd) }`
  全仓 grep 只有这**一处读**，没有任何 `set` 点（连 `setBool`/`UserDefaults` 直写都没有）。
- **后果**：这道「只读护栏」是 fail-safe 的方向（默认关 = 正常写），所以**不会造成事故**；
  但它是一句**实现不了的承诺** —— 用户没有任何入口能把它打开。
- **`[已修]`（用户选定「加开关」）**：
  · `App/Core/TrialGuardKit.swift` —— `TrialGuard`（开/关/文案）+ `TrialGuardBanner`（全 App 顶部红条，带一键关闭）
  · 设置页「工具」段新增开关行，开启要二次确认（说明后果），**关闭不需要** —— 恢复能力不该被拦
  · 红条挂在 `RootView.mainTabs` 的 `safeAreaInset(edge: .top)`，**常驻**而非 toast：
    用户第二天忘了自己开过它，会以为「App 坏了、什么都不能改」

#### A2 `[待办]` 手机钥匙从未进备份包 —— 已修

- **位置**：`App/Services/BackupKit.swift`
- **事实**：`DefendCfg` / `TailgateCfg` / `OtpStatus` 都在 `BackupBundle.Device.Meta` 里，
  但本轮新增的 `kf_mkey_<mac>`（手机钥匙）**不在**。
- **后果**：换机/恢复后手机钥匙记录全丢 → 成员的手机还能开门，但本机再也撤销不了（显示"未发过"）。
  这是**安全相关**的数据丢失。
- **`[已修]`**：`Meta.mobileKeys` 字段 + `collectAll` 收集 + `restoreAll` 写回，三处已接。

#### A3 `[已修]` Android 自动/手动开锁共用 doUnlock，busy 静默丢后者

- **位置**：`android-app/.../MainActivity.kt:186,193`
- **事实**：两路都调 `doUnlock`，仅靠 `auto` 布尔区分文案；`busy` 时**直接 return，无排队无提示**。
- **后果**：自动开锁正在跑时用户点圆盘 → 手动那一下**没有发生**，但界面无任何反馈。
  用户会以为"点了没反应"，然后在门口反复点。
- **`[已修]`**：`MainActivity.kt:182` busy 分支改为 `say(...)` 给一句明确的话，并按 `auto` 区分是哪一路在跑。
- **判断**：这是交互缺陷，不影响安全（不会多开一次门）。

### B. 注释漂移（5 条，已修 2 条）

#### B1 `[已修]` AutoOpen 注释写「>60s」，实为 6s

- `App/Core/AutoOpen.swift:199` → 已改为引用 `cooldownSeconds(=6)` 并注明「60 是热链路上限」。
- **注意**：Android 端 `AutoOpenKit.kt:48` 有同一处历史注释（`COOLDOWN_MS` 已是 6000，注释还讲 60s）。
  那条**仍在**，属 Android 侧待修。

#### B2 `[已修]` LinkSenseKit 注释称「静置满 3s 才走全门判定」

- `App/Core/LinkSenseKit.swift:294` → 已注明该判定已从实现删除。

#### B3 `[已修]` BatteryCare 头注列出 `kf_mevents_` / `kf_maint_` 保养键

- `App/Core/BatteryCare.swift:3` → 已标为「未实现待办」。**保养计划整块没有 UI**。

#### B4 `[已修]` BackupStudioKit rotateKey 注释称「旧文件重命名留痕」

- `App/Services/BackupStudioKit.swift:875` → 实现是**直接覆盖**，轮换即覆盖、旧密文不可恢复。已注明。

#### B5 `[已修]` BLEService 头注与实现冲突

- `App/Services/BLEService.swift:2,4`：注释称「CBUUID 过滤扫描 / 20B 分片 + 30ms 间隔」，
  实际是 `scanForPeripherals(withServices: nil)` 全扫、分片间无 sleep（靠 ack 流控）。
- **`[已修]`**：头注改为「全扫 + 无固定 sleep、ack 即流控」，并写明**为什么**不用 CBUUID 过滤
  （门锁 NUS / 网关 FE90 / 钥匙串 6E401001 / DFU FE59·1530 是四套 service，过滤列表一漏就「扫不到」）。

### C. 待真机（6 条）

| # | 位置 | 问题 | 验证方式 |
|---|---|---|---|
| C1 | `ZKProtocol.swift:2-3` | 7B 头变体（`87 01 len cmd dlen:2`）没有生成点，布局无法确认 | 抓真锁回包看有没有 7 字节头 |
| C2 | `ZOTP.swift:15-18` | ~~`periodSec` 名为秒实为分钟~~ → **`[已修]` 改名 `periodMin` + 单位断言**（1–120 分钟）。vendor 侧保持原名（基线资产），两边名字不同是有意的。**剩待真机**：验证锁端窗口确实是分钟级 | 生成一个临时码，与锁端实际窗口比对 |
| C3 | `HardwareService.swift:337` | 钥匙串台账用 `macRaw`（线上序），门锁台账用显示序 | 写一把钥匙串钥匙后，核对两表 MAC 能否关联 |
| C4 | `HardwareService.swift:171-172` | 基线有 `KLV#36` 逐字节 applyPids，本工程不解析 | 读一次 43/44 回包看有没有 #36 |
| C5 | `LockService.swift:974-976` | 正式钥匙串与 pending 的 ekey 都用 `pins[0]` 签发，锁端认哪条为"主凭证"未知 | 配网后写两把钥匙串，看哪条能开门 |
| C6 | `Attribution.swift:24-27` | 时间串按 UTC 解析本地串（注释称两端同平移） | 跨时区各开一次门，比对归属窗口 |

### D. 跨 scope 已核实（4 条，无需再查）

| # | 原未决项 | 核实结果 |
|---|---|---|
| D1 | `LockGuard.swift:51-57` 四个安全开关键名待另一侦察兵核对 | **已核实**：`SecurityCenterView.swift:25/26/30` 给出 `kf_speek_sharehalf` / `kf_speek_glast` / `kf_sdest_safemode`，第四枚 `kf_speek_guest` 在 `LockGuard.swift:51` 直读字符串。四处齐全。 |
| D2 | `ZKProtocol.swift:91` `kf_macorder_` 落盘点不在 scope | **已核实**：`Store.swift:332` 有 `macOrderKey()`、`:343` 有 `hydrateMacOrders()`、`QuickActions.swift:22` 在启动窗口调用。落盘与补水都在。 |
| D3 | `ZKProtocol.swift:96-101` 重启后是否可能按 display 误发 | **已核实**：`hydrateMacOrders()` 在 `didFinishLaunchingWithOptions` 里（`QuickActions.swift:22`），早于任何命令；补不上的锁走一次 rc=12 自愈。**不会误发**。 |
| D4 | `BLEService.swift:20-25` DFU UUID 零引用 | **已核实并已使用**：本轮 `DFUKit.swift:63/69/70` 引用 `svcDfuSecure` / `dfuSecureControl` / `dfuLegacyControl`，不再是零引用。 |

### E. 可忽略 / 设计如此（19 条）

| # | 位置 | 裁决 |
|---|---|---|
| E1 | Android `isReady()` 无调用 | 界面在开锁时才给"蓝牙未开"文案。可接受（Android 是极简版）。若要更早提示，加一行预检即可。`[可忽略]` |
| E2 | Android `Haptics.tick/trigger` 无调用 | 三档只落地 ok/fail 两档。设计未完成，但**不影响功能**。`[可忽略]` |
| E3 | Android 设计令牌文件（`android-app/.../Tokens.kt`）大部分无引用 | 设计令牌预留。`[可忽略]` |
| E4 | Android `Theme.kt` 8 个固定色仅默认参数用 | 已改走 `LocalKfColors`，固定值留给非 Composable 上下文（DrawScope）。**设计如此**。`[可忽略]` |
| E5 | Android 武装线固定 -40、无标定 | 极简版定位。iOS 有 30 秒标定流程。`[可忽略]` |
| E6 | Android `requestMtu(256)` 结果未消费 | 分片恒 20B 是保守正确做法（iOS 也是保守值）。`[可忽略]` |
| E7 | Android `airTagLayerUp` / `airTagShowing` 重复计算 | 为规避声明顺序，行为一致。`[可忽略]` |
| E8 | Android `findSound` 不落盘 | 与 `proximity` 落盘策略不一致，但提示音是**会话级**偏好，不落盘合理。`[可忽略]` |
| E9 | Android `themes.xml` 无深色变体 | 浅色档启动可能闪暗底。**真问题但影响很小**（启动瞬间）。`[可忽略]`，除非要上浅色主题 |
| E10 | Android `versionCode` 依赖 `KF_BUILD_TS` | 本仓 `.github` 在取证范围外。CI 上能验证。`[可忽略]` |
| E11 | Android rc 码表缺 4 号 | 原表如此（iOS 也是 0,1,2,3,5..27）。若锁端真回 4，会显示"未知错误"。`[待真机]` |
| E12 | Android 冷/热路径 pid 不符无退避 | 都是 closeWarm 后返回。**缺退避**但不影响正确性。`[可忽略]` |
| E13 | `Locked<Value>` 无全仓 grep 清单 | 通用互斥容器，已知 5 个消费点。`[已核实]` |
| E14 | `MemberHub.swift:311` 隐私浏览未接线 | **`[已修]` 按用户决策删除功能**：只写时间戳、不改变任何可见行为的开关比没有更糟（用户以为在保护隐私）。`privacyActive`/`privacyUntilSec`/`setPrivacy` 与成员设置页整段已删，`kf_privacy_until` 保留在族删清单里以便清老数据。 |
| E15 | `AuditChain.swift:217` DestroyKit 只有备份闸 | 覆写在核弹销毁入口（`SettingsView` 侧）。`[已核实]` |
| E16 | `Store.swift:439-446` 族删清单 15 个前缀写点不在 scope | 键名已全列；写点分散在 BatteryCare/DiagKit/LinkSenseKit/AutoOpen。**键名正确性已由图谱覆盖**。`[已核实]` |
| E17 | `Store.swift:178` Ledger 无条数上限 | 锁端 PIN 池 64 个、密码 8 个是硬上限，台账不会无限涨。`[可忽略]` |
| E18 | `RecordSearch.swift:499-521` 节假日表只覆盖 2026 | 2027 的节假日需要有人填。`[待办]`（时间敏感：2026 年底前要补） |
| E19 | `CredentialOrg.swift:145-148` `kf_cotp_*` 只剩备份白名单认键 | **已核实**：全仓只有键名函数（`:147/:148`）+ 备份白名单（`BackupStudioKit.swift:140`），**无运行时读写点**。数据本体随 OtpStudio 删除。`[已核实]` |

---

## 第二批：自动化 / 诊断类（16 条）

### 已修（本轮）

| # | 原未决项 | 处置 |
|---|---|---|
| 1 | `AutoOpen:512` 文案写「未标定则 F3 门不过」 | **`[已修]` 文案对齐实现**：`rssiBase` 未标定时回退 `fallbackBase = -40`（与安卓 `AutoOpenKit.BASE` 同值），未标定**能开**。文案改为「用通用基准 -40，建议标定以提高准确度」 |
| 2 | `AutoOpen:102` 注释仍写「F1 标准=60s 窗口静默复用」 | `[已核实]` 实现已是 0 档不发起弹窗，属注释漂移；同批已修过同类（批三 B1） |
| 3 | `AutoOpen:199` coolReady 写「>60s」 | **`[已修]`**（批三 B1）改为引用 `cooldownSeconds(=6)` |
| 4 | `LinkSenseKit:294` 称静置 3s 才判定 | **`[已修]`**（批三 B2）注明该判定已删 |
| 5 | `BatteryCare:3` 头注列 `kf_mevents_`/`kf_maint_` | **`[已修]`**（批三 B3）标为未实现待办 |
| 14 | `BackupStudioKit:875` rotateKey 称「重命名留痕」 | **`[已修]`**（批三 B4）实现是直接覆盖 |
| 8 | `DesignSystem:995` GuidedEmptyView 的 `if mascot, … { }` 空块 | **`[已修]` 删空块 + 删 `mascot` 参数 + 删 DiagnosticsView 的实参**（留空 if 比没有更容易让人以为功能在） |
| 9 | `DesignSystem:648` `staggered(_:)` 恒等 | **`[已修]` 删 no-op 与三处调用 + 删随之孤立的 `StaggeredAppear`（22 行）** |
| 7 | `DesignSystem:877` Hero 纹理三档无渲染 | **`[已修]` 新增 `App/Core/HeroTexture.swift`**：`HeroTexture` 三档枚举 + `HeroTextureLayer`（Canvas 自绘，不引位图）。透明度按注释口径 0.06/0.08，降透明档不画，`allowsHitTesting(false)` + `accessibilityHidden(true)`。已接进 `HeroCard` |
| 16 | `DesignSystem:159` `kf_ax_bigotp` 只在注释里 | **`[已修]` 判断与前设相反**：该键**有活的读点**（`CredentialsView:1850` 控制临时码字号），只是**没有写点** ⇒ 永远 false。补上开关（`DiagnosticsView` 渲染自检段，走 `setUnlockOption` 与 `bigPreview` 同一通道）比删键更符合原设计 |
| 10 | `BackupStudioKit:617` `expiredTemporaryCount` 注释错位 | **`[已修]`** 原注释是「193 体积预估」，与函数无关，已换成语义正确的说明 |
| 11 | `BackupKit:487` 硬编码坚果云 vs `webdavRoot` 可配 | **`[已修]` 加口径说明**：这是**默认值**，用户自配根会覆盖；文件名恒为 `zklock-backup.enc`（远端只留一份，轮换即覆盖） |
| 13 | `ZipKit:31` 引用已失效行号 | **`[已修]`** 清掉 `:107/:348/:370`，并写一条纪律：这类注释只写符号名，不写行号 |

### 保留（如实标注）

| # | 原未决项 | 处置 |
|---|---|---|
| 6 | `BatteryCare:6` 协议只给百分比、无电压/充电位 | `[已核实]` 这是**协议约束**，不是缺陷。充放电建议/续航估算在本仓无数据来源，不应造节点 |
| 12 | `BackupStudioKit:481` v4/v5 迁移是空操作 | **`[保留+如实标注]`**：迁移链当年的动作是自赋值，现在只推进版本号。不加假迁移，但在台账写明「v4/v5 不作为已实现能力」 |
| 15 | `DiagKit:414` 与 `LinkSenseKit:363` 互指旧行号 | `[已核实]` 同 #13 一族；两处注释描述的历史实现已删，行号引用不可核对 |

---
## 第三批：UI 系统 / 备份 / 启动链（14 条）

| # | 原未决项 | 处置 |
|---|---|---|
| 1 | `BackupStudio:117` 空态文案提「先在导出向导生成并上传」 | **`[已修]`** 导出向导已随大删波4 移除（本文件头注写着），文案改为只指向本页真实存在的按钮 |
| 2 | `BackupView:69/72` 本机台数 vs 包内台数并列 | **`[已修]`** 按钮文案加「（本机现有）」、message 加「（覆盖来源）」，并补一句「两个数字不一致是正常的（换过机/删过锁/包比本机旧）」 |
| 3 | `LockKeeperApp:287-296/:1113` 启动门禁已删，`.onChange(of: appUnlocked)` 不触发 | **`[已修]` 这条是**真缺陷**：onChange 里承接的三件事全部静默失效。处置：`restoreLastTab()` + `applyPendingRoute()` + `runSelfCheck397()` **搬进 bootstrapOnce**（冷启动必跑）；`revokeSessionGrants()` **改挂 `scenePhase == .background`** |
| 4 | `LockKeeperApp:929` 空 `if app.current != nil { }` | **`[已修]`** 删空块 |
| 5 | `LockKeeperApp:1065` 注释称有「门面/300s 门禁」 | **`[已修]`** 记录在 #3 的说明里：那条路径随启动门禁一起删除 |
| 6 | `BackupStudio:175` `persist()` 只在 test/upload 调，改完关窗就丢 | **`[已修]`** 三条 `.onChange(onChange(of: root/acct/appPw))` 挂在整个 Form 上（不是挂单个字段 —— 那样另两个字段永不触发） |
| 7 | `DiagReferenceView:58-61` 「已知晓」只丢返回值 | **`[已修]` 注释如实化**：说明 `consumePending()` 的清理若失败，界面仍会显示已清 —— 这是已知局限 |
| 9 | `BackupStudio:255` vs `BackupView:387` 两个口令字段 | **`[已修]` 统一**：新增 `App/Core/BackupPassphrase.swift`（会话级、仅内存，不落盘），两页的 `encPw`/`cloudPw` 都代理到它 ⇒ 一次输入两页通用 |
| 10 | `DiagnosticsView:1107` 完整帧依赖内存环形缓冲 | **`[已修]` 注释补两条边界**：容量 **60 条**、**重启 App 后全部丢失**。并写明这是刻意取舍（完整帧带 skey/ekey/PIN 明文，落盘等于把密钥写在磁盘上） |
| 11 | `LockKeeperApp:1027` `coldStartScan`/`startupPreconnect` 是裸 Task 不可取消 | **`[已修]`** `LinkSenseKit` 新增 `coldScanTask`/`preconnectTask` 句柄：第二次调用先 cancel 上一次，体内加 `Task.isCancelled` 检查 |
| 12 | `Store:1015/1031/1048` toDict/fromDict 无独立功能 | **`[已核实并结案]`** Codable 手写编解码，用户不可感知；容错口径已由 `data.schema` 节点覆盖 |
| 13 | `CredentialsView:2517` topViewController | **`[已核实并结案]`** 取顶层 VC 的 presenter 工具，无独立功能语义 |
| 14 | `CredentialStudio:359` CodeBigCard | **`[已核实并结案]`** 已被 `credential.pwd.detail.card` 与 `credential.tempcode.done` 覆盖 |

### 本批最重要的一条

**#3 是本次 129 条裁决里发现的最严重缺陷**（比双签前缀比对更严重）：

```
2026-10-17 拍板删掉启动门禁 → init() 里 appUnlocked = true
        ↓
appUnlocked 再也不会变 false
        ↓
.onChange(of: app.appUnlocked) 一次都不触发
        ↓
三件事全部静默失效：
  · restoreLastTab()      —— 「回到上次停留的 Tab」从来没生效过
  · applyPendingRoute()   —— 深链落地依赖它
  · revokeSessionGrants() —— **访客区/临时授权一次放开就永久敞开**
```

前两件是功能缺失，第三件是**安全退化**。现在：前两件搬进 bootstrapOnce，第三件挂到"真进后台"。

---
## 第四批：APK 基线（19 条，待裁）

## 裁决完成情况（分批次进行，非一次裁完）

> 2026-10-27 审核修正 (AUDIT-E 8.2)：原标题写「129 条全部裁完」，
> 而正文第 240 行自己写着「剩余 92 条（129 − 37）在后续批次继续裁」—— 标题与正文矛盾。
> 现在标题如实反映「分批」这一事实。下面的表记的是**本批**的裁决结果。

| 批次 | 范围 | 条数 | 状态 |
|---|---|---:|---|
| 第一批 | 协议 / 数据 / Android | 37 | ✅ 已裁（已修 14） |
| 第二批 | 自动化 / 诊断 | 16 | ✅ 已裁（已修 12） |
| 第三批 | UI 系统 / 备份 / 启动链 / gapfill | 14 | ✅ 已裁（已修 12，含 1 条安全退化） |
| 第四批 | UI 与入口（device/cred/records） | 43 | ✅ 已裁（清空壳 13 处、删幽灵声明 3 类、双签改全量） |
| 第五批 | APK 基线 | 19 | ✅ 已裁（**全部归档**，属原版自身取证局限） |
| **合计** | | **129** | **全部裁决完毕** |

### 仍需你或真机介入的（不阻塞收尾）

| 项 | 需要什么 |
|---|---|
| `docs/DEVICE-CHECKLIST-2026-10-26.md` 三项功能验证 | 真锁 + iOS 真机 |
| DFU 传输层 | 真锁 + 官方固件包（风险最高） |
| 7 条协议语义（七字节头 / ZOTP 单位 / 钥匙串 MAC 口径 / KLV#36 / pins[0] 主凭证 / UTC 解析 / rc=4） | 抓真锁回包 |
| 441 行新单测 | 一台有 Xcode 的 Mac 跑 `xcodebuild test` |

### 本次裁决发现的三条最严重缺陷

1. **访客授权安全退化**（第三批 #3）：启动门禁删除后 `.onChange(of: appUnlocked)` 永不触发，
   `revokeSessionGrants()` 成死代码 ⇒ 访客区一次放开就**永久敞开**。已改挂 `scenePhase == .background`。
2. **双签只是双签的样子**（第四批 q35）：只比对密码前 max(len/2, 2) 位，6 位密码输对 3 位即可
   删掉某人的最后一枚指纹。已改为全量比对。
3. **手机钥匙不进备份**（第一批 A2）：换机后 kf_mkey_ 丢失 ⇒ 成员手机还能开门但本机再也撤销不了。已修。

---

## 统计（第一批）

| 分类 | 条数 | 已修 | 待办 | 待真机 |
|---|---:|---:|---:|---:|
| 真缺陷 | 3 | 3 | 0 | 0 |
| 注释漂移 | 5 | 5 | 0 | 0 |
| 待真机 | 6 | 1 | 0 | 6 |
| 跨 scope 已核实 | 4 | 4 | 0 | 0 |
| 可忽略/设计如此 | 19 | 1 | 2 | 1 |
| **合计** | **37** | **14** | **2** | **7** |

> 剩余 92 条（129 − 37）在后续批次继续裁。
