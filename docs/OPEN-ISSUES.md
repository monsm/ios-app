# 未决项裁决台账

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

#### A1 `[待办]` kf_trial_guard 只读不写 —— 只读试验模式永远打不开

- **位置**：`App/Services/LockService.swift:217-218`
- **事实**：`if DB.store.getBool("kf_trial_guard", false) { try ZKProtocol.assertReadOnly(cmd) }`
  全仓 grep 只有这**一处读**，没有任何 `set` 点（连 `setBool`/`UserDefaults` 直写都没有）。
- **后果**：这道「只读护栏」是 fail-safe 的方向（默认关 = 正常写），所以**不会造成事故**；
  但它是一句**实现不了的承诺** —— 用户没有任何入口能把它打开。
- **建议**：二选一
  1. 在「实验室」页加一个开关（写 `kf_trial_guard`），并在开启时把写命令全部拦死 + 顶部常驻横幅；
  2. 或者删掉这段只读分支，承认离线版不提供试验模式（JS 那边是给真机调试用的）。
- **我不擅自决定**：这取决于你是否还需要「只读试验」这个能力。

#### A2 `[待办]` 手机钥匙从未进备份包 —— 已修

- **位置**：`App/Services/BackupKit.swift`
- **事实**：`DefendCfg` / `TailgateCfg` / `OtpStatus` 都在 `BackupBundle.Device.Meta` 里，
  但本轮新增的 `kf_mkey_<mac>`（手机钥匙）**不在**。
- **后果**：换机/恢复后手机钥匙记录全丢 → 成员的手机还能开门，但本机再也撤销不了（显示"未发过"）。
  这是**安全相关**的数据丢失。
- **`[已修]`**：`Meta.mobileKeys` 字段 + `collectAll` 收集 + `restoreAll` 写回，三处已接。

#### A3 `[待办]` Android 自动/手动开锁共用 doUnlock，busy 静默丢后者

- **位置**：`android-app/.../MainActivity.kt:186,193`
- **事实**：两路都调 `doUnlock`，仅靠 `auto` 布尔区分文案；`busy` 时**直接 return，无排队无提示**。
- **后果**：自动开锁正在跑时用户点圆盘 → 手动那一下**没有发生**，但界面无任何反馈。
  用户会以为"点了没反应"，然后在门口反复点。
- **建议**：busy 时至少给一句 toast「正在自动开锁，请稍候」；或把手动请求排队一次。
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

#### B5 `[待办]` BLEService 头注与实现冲突

- `App/Services/BLEService.swift:2,4`：注释称「CBUUID 过滤扫描 / 20B 分片 + 30ms 间隔」，
  实际是 `scanForPeripherals(withServices: nil)` 全扫、分片间无 sleep（靠 ack 流控）。
- **建议**：改注释。**不要改代码** —— 全扫是有意的（网关/钥匙串用不同 service，过滤会漏）。

### C. 待真机（6 条）

| # | 位置 | 问题 | 验证方式 |
|---|---|---|---|
| C1 | `ZKProtocol.swift:2-3` | 7B 头变体（`87 01 len cmd dlen:2`）没有生成点，布局无法确认 | 抓真锁回包看有没有 7 字节头 |
| C2 | `ZOTP.swift:15-18` | `periodSec` 名为秒实为**分钟**；若锁端真是 30 秒，生成码会系统性错窗 | 生成一个临时码，与锁端实际窗口比对 |
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
| E14 | `MemberHub.swift:311` 隐私浏览未接线 | **真缺口**：只有 `kf_privacy_until` 时间戳，没隐藏数据也没水印。已由图谱标 partial。`[待办]`（低优先） |
| E15 | `AuditChain.swift:217` DestroyKit 只有备份闸 | 覆写在核弹销毁入口（`SettingsView` 侧）。`[已核实]` |
| E16 | `Store.swift:439-446` 族删清单 15 个前缀写点不在 scope | 键名已全列；写点分散在 BatteryCare/DiagKit/LinkSenseKit/AutoOpen。**键名正确性已由图谱覆盖**。`[已核实]` |
| E17 | `Store.swift:178` Ledger 无条数上限 | 锁端 PIN 池 64 个、密码 8 个是硬上限，台账不会无限涨。`[可忽略]` |
| E18 | `RecordSearch.swift:499-521` 节假日表只覆盖 2026 | 2027 的节假日需要有人填。`[待办]`（时间敏感：2026 年底前要补） |
| E19 | `CredentialOrg.swift:145-148` `kf_cotp_*` 只剩备份白名单认键 | **已核实**：全仓只有键名函数（`:147/:148`）+ 备份白名单（`BackupStudioKit.swift:140`），**无运行时读写点**。数据本体随 OtpStudio 删除。`[已核实]` |

---

## 第二批及之后

- **UI 与入口类**（ios-ui-device 17 + ios-ui-records 17 + ios-ui-cred 9 = 43 条）：待裁
- **自动化与诊断类**（ios-core-auto 16 条）：待裁
- **APK 基线类**（apk-baseline 19 条）：待裁
- **UI 系统类**（ios-ui-system 11 条）：待裁
- **其他**（lead-gapfill 3 条）：待裁

---

## 统计（第一批）

| 分类 | 条数 | 已修 | 待办 | 待真机 |
|---|---:|---:|---:|---:|
| 真缺陷 | 3 | 1 | 2 | 0 |
| 注释漂移 | 5 | 4 | 1 | 0 |
| 待真机 | 6 | 0 | 0 | 6 |
| 跨 scope 已核实 | 4 | 4 | 0 | 0 |
| 可忽略/设计如此 | 19 | 0 | 3 | 1 |
| **合计** | **37** | **9** | **6** | **7** |

> 剩余 92 条（129 − 37）在后续批次继续裁。
