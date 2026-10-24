# iOS Core / Services 层 · 最小功能点清单

> 范围：`D:\aapk\ios-app` 下 `App/Core` 47 个 .swift、`App/Services` 8 个 .swift、`App/LockKeeperApp.swift` = **56 个文件 21,601 行**。委托单写 55 个文件，实测 Core 为 47 + Services 8 + 入口 1。`Core/SpeechKit.swift` 与 `Core/DevModules.swift` 只有注释与 import，**零声明**。
>
> 方法：剥离全部注释后建立全仓符号引用索引（`App/**` 106 + `Tests/**` 4 = 110 个 .swift），对每个声明统计「本文件内引用 / 跨文件引用 / 仅测试引用」，零跨文件引用且零测试引用 → 冗余「高」。局限：本机无 Swift 工具链，`#selector`/`@objc`/SwiftUI 隐式使用按源码字面统计，同名短函数（`run`/`sample`/`tier`/`body`）已人工复核。

## 图例

| 列 | 含义 |
|---|---|
| ID | `core-*` = App/Core，`app-*` = LockKeeperApp.swift |
| 类型 | 计算 / 存储 / 协议 / 密码学 / 解析 / 状态 / 编排 / 通知 / 令牌 / 组件 / 配置 / 统计 |
| 被谁用 | 引用该符号的**其它文件**（去 `.swift`，`×N` 为次数）；`—` = 全仓无引用 |
| 冗余嫌疑 | **高** = 零调用 / 仅注释 / 空壳；中 = 仅本文件内自用、重复实现、写侧缺失；低 = 活链路 |

## 总览

| # | 文件 | 行数 | 类型 | 函数 | 零调用声明 | 外部类型引用 | 嫌疑 |
|---|---|---|---|---|---|---|---|
| 1 | Core/AccessibilityKit | 336 | 6 | 15 | 5 函数 + 1 类型 | 11 | 中 |
| 2 | Core/AESKit | 42 | 1 | 2 | 0 | 9 | 低 |
| 3 | Core/AlertTone | 87 | 2 | 4 | 0 | 13 | 低 |
| 4 | Core/AndroidPair | 44 | 1 | 3 | 0 | 2 | 低 |
| 5 | Core/AuditChain | 495 | 10 | 28 | 0（4 个内部件） | 51 | 低 |
| 6 | Core/AutoOpen | 812 | 10 | 39 | 1 函数 | 68 | 中 |
| 7 | Core/BatteryCare | 517 | 10 | 29 | 2 函数 | 75 | 中 |
| 8 | Core/ClipboardCare | 114 | 4 | 5 | 0 | 17 | 低 |
| 9 | Core/Components | 2744 | 44 | 23 | 1 函数 + 3 类型 | 641 | 中 |
| 10 | Core/CredentialOrg | 1539 | 20 | 134 | **43 函数** | 120 | **高** |
| 11 | Core/Destination | 34 | 1 | 0 | 0 | 4 | 低 |
| 12 | Core/DevModules | 18 | 0 | 0 | **整文件** | **0** | **高** |
| 13 | Core/DiagKit | 696 | 28 | 40 | 2 函数 + 5 类型 | 106 | 中 |
| 14 | Core/ErrorText | 60 | 1 | 1 | 0 | 20 | 低 |
| 15 | Core/FirmwareHistory | 40 | 1 | 4 | 2 函数 | 1 | 中 |
| 16 | Core/HexKit | 97 | 1 | 13 | 0 | 135 | 低 |
| 17 | Core/HintOnce | 13 | 1 | 2 | 0 | 4 | 低 |
| 18 | Core/HolidayFeed | 162 | 5 | 9 | 2 函数 | 3 | 中 |
| 19 | Core/KeyGen | 86 | 1 | 8 | 0 | 14 | 低 |
| 20 | Core/LinkSenseKit | 959 | 7 | 35 | 3 函数 | 24 | 中 |
| 21 | Core/LockCommand | 125 | 1 | 1 | 0 | 3 | 低 |
| 22 | Core/Locked | 37 | 1 | 1 | 0 | 17 | 低 |
| 23 | Core/LockGuard | 175 | 4 | 10 | 0（2 个内部件） | 51 | 低 |
| 24 | Core/LockKeySpace | 72 | 1 | 2 | 0 | 1 | 低 |
| 25 | Core/LockStats | 438 | 9 | 31 | **7 函数** | 102 | 中 |
| 26 | Core/MemberHub | 333 | 6 | 26 | 3 函数 | 96 | 中 |
| 27 | Core/Milestones | 617 | 10 | 37 | **9 函数 + 1 类型** | 102 | **高** |
| 28 | Core/NoticeBudget | 51 | 2 | 1 | 0 | 5 | 低 |
| 29 | Core/PidMap | 56 | 1 | 10 | 1 函数 | 18 | 中 |
| 30 | Core/QuickPool | 172 | 2 | 7 | **6 函数** | 3 | **高** |
| 31 | Core/RecordSearch | 1018 | 16 | 78 | **18 函数 + 1 类型** | 101 | **高** |
| 32 | Core/Route | 98 | 1 | 1 | 0 | 7 | 低 |
| 33 | Core/ScreenCare | 89 | 2 | 6 | 1 函数 | 1 | 中 |
| 34 | Core/SeasonIcon | 69 | 1 | 4 | 0 | 1 | 中 |
| 35 | Core/SecretStore | 61 | 1 | 5 | 0 | 20 | 低 |
| 36 | Core/SettingsGroups | 53 | 1 | 1 | **1 函数 + 1 类型** | **0** | **高** |
| 37 | Core/SpeechKit | 9 | 0 | 0 | **整文件** | **0** | **高** |
| 38 | Core/StatsKit | 1088 | 19 | 39 | **13 函数** | 59 | **高** |
| 39 | Core/StatusCheckNotice | 73 | 1 | 4 | 0 | 2 | 低 |
| 40 | Core/StatusParser | 196 | 3 | 10 | 0（2 个内部件） | 66 | 低 |
| 41 | Core/Store | 1040 | 19 | 101 | 4 函数 | 1419 | 低 |
| 42 | Core/Theme | 970 | 14 | 18 | 0（2 个内部件） | 3388 | 低 |
| 43 | Core/TimeFormat | 125 | 1 | 7 | 0 | 27 | 低 |
| 44 | Core/WeekCal | 82 | 1 | 2 | 0 | 102 | 低 |
| 45 | Core/ZKCmdBuilder | 286 | 2 | 40 | 0（5 个内部件） | 87 | 低 |
| 46 | Core/ZKProtocol | 299 | 7 | 23 | 0（3 个内部件） | 213 | 低 |
| 47 | Core/ZOTP | 55 | 1 | 4 | 1 函数 | 4 | 中 |
| 48 | Services/Attribution | 81 | 2 | 2 | 0 | 29 | 低 |
| 49 | Services/BackupCanonical | 294 | 2 | 14 | 0（9 个内部件） | 12 | 低 |
| 50 | Services/BackupKit | 490 | 12 | 19 | 0（9 个内部件） | 44 | 低 |
| 51 | Services/BackupStudioKit | 1434 | 23 | 77 | **10 函数 + 2 类型** | 112 | **高** |
| 52 | Services/BLEService | 583 | 6 | 23 | 1 函数 | 108 | 中 |
| 53 | Services/DFUKit | 727 | 11 | 31 | 1 函数 | 35 | 中 |
| 54 | Services/HardwareService | 382 | 3 | 25 | 0（10 个内部件） | 16 | 低 |
| 55 | Services/LockService | 1028 | 7 | 48 | 5 函数 | 17 | 中 |
| 56 | App/LockKeeperApp | 1698 | 14 | 61 | **13 函数** | 84 | **高** |

**全层合计**：1,524 个具名声明（类型 468 / 函数 1,056）；跨文件零引用 **155 函数 + 15 类型**；仅本文件内自用 305 个；活函数 703 个。下表按"最小功能点"归并，逐条标冗余。

## 1. Core/AccessibilityKit.swift（336 行）

无障碍与操作辅助核心：系统旗标 + App 偏好的唯一读点，降级判据集中在此。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-ax-01 | 系统辅助五旗标：增强对比 862 / 智能反转 863 / 加粗 861 / 减弱动效 899 / 降低透明度 226 | 状态 | Theme×3, LockKeeperApp×4 | 低 |
| core-ax-02 | 非隔离快照 `reduceMotionSnapshot`/`typeSizeSnapshot`（供 ButtonStyle 等非主 actor 求值；值本身进 `Locked`，不是 unsafe） | 状态 | LockKeeperApp.refreshSnapshots | 低 |
| core-ax-03 | 858 生效字号 `typeSize()`：App 档 × 系统相对倍率取最近 DynamicTypeSize（866 极限字号自检同出口） | 计算 | HomeConsole×3, Components×2, LockProfilePage×2 | 低 |
| core-ax-04 | 859 AX 降级布局 `axStackLayout`（字号 ≥1.5 圆盘缩至 128pt）+ 879 灰度预览 | 计算 | 视图层 | 中 |
| core-ax-05 | `AXPrefs` 九枚冻结偏好（防连点/按住 0.9s/眼动 2.0s/字幕条/双震/单手下沉/左手/大格/贴底表单） | 配置 | LockKeeperApp×1 | 中 |
| core-ax-06 | `CalcToken` —— 与 `AXPrefs` **逐行相同的整份副本** | 配置 | — | **高** |
| core-ax-07 | 852 播报 `announce`（在用）+ 855 焦点序列 `liveFocusSequence/visit` + 876 双震 `newEntryHaptic` + `announceConnectFail` | 组件 | LockKeeperApp×2（后四件零调用） | **高** |
| core-ax-08 | 生物识别 `AuthKit.biometricAvailable`/`verifyBiometricAsync`（945 供 Intent await）+ 392 面容失败原因 `reasonText`（LAError→中文，取消/锁停分开）+ 玻璃降级三形状 `axGlass`/`axGlassCapsule`/`axGlassCircle` + 862 增强对比全树补丁 `axIncreaseContrast`/`AXContrastModifier` | 服务/组件 | SecurityCenterView, CredentialStudio×2, LockKeeperApp, BackupStudio | **高**（`reasonText` 与 `axGlassCircle` 零调用） |

## 2. Core/AESKit.swift（42 行）

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-aes-01 | AES-128-ECB + ZeroPadding 加密 `encryptHex`（CommonCrypto，与 JS utils/crypto.js 字节级一致） | 密码学 | ZKCmdBuilder×2, ZKProtocol, ZOTP, Tests×4 | 低 |
| core-aes-02 | 解密 `decryptHex`（仅 GoldenDiffTests 使用，App 侧无调用） | 密码学 | Tests | 中 |
| core-aes-03 | ZeroPadding 补齐规则（明文长度 %16 时补零；差分基准 NIST 向量 + 回环） | 密码学 | 本文件 | 低 |

## 3. Core/AlertTone.swift（87 行）

App 内提示音唯一出口，全部走系统 SystemSound（铃声静音时由系统本身出无声）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-tone-01 | 76/848 开锁成功音 `unlockSuccess`（开关 `kf_unlock_sound`） | 通知 | LockKeeperApp | 低 |
| core-tone-02 | 自动开锁音 `autoUnlockSuccess`（独立开关、默认开：手机可能在口袋里，声音是唯一的到场信号） | 通知 | AutoOpen | 低 |
| core-tone-03 | 848 终态失败音 `unlockFailure`（中间静默重试不响，否则一次失败连响三声）；733 告警分级 `Tier.alert`（胁迫三音 / 低电单音，级别只影响**节奏**）+ 四条独立开关与四个私有 SystemSoundID | 通知 | LockKeeperApp, BatteryCare×9 | 低 |

## 4. Core/AndroidPair.swift（44 行）

给安卓端的「扫码即用」载荷（刻意**不带 skey**：ekey 丢了可换 PIN 重签，skey 丢了是整把锁的母钥）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-pair-01 | 开锁凭证 `ekey`：优先配网签好的，缺失则按 skey+PIN 现签（与 unlock() 同一算式、同一组默认有效期 ⇒ 与配网那次逐字节一致） | 计算 | Store, LockService, HardwareService | 低 |
| core-pair-02 | 二维码正文 `payload`（`KFA1:{v,n,m,p,e}`，字段压到 1 字母让二维码更稀疏，暗光/斜角更好认） | 序列化 | DFUKit, ExportCenter, ShareToAndroidView | 低 |
| core-pair-03 | 显示名 `displayName` + 前缀 `KFA1:`（只用于扫错码时立刻判掉，**不是安全边界** —— 边界是 ekey 本身） | 格式化 | ExportCenter, LocksPage, BackupStudioKit | 低 |

## 5. Core/AuditChain.swift（495 行）

包7 安全·隐私·审计纯逻辑层（无 SwiftUI 依赖，便于单测与 golden 差分）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-audit-01 | `HashKit`：SHA-256→hex（CryptoKit 不可用时退化 FNV-1a32 双轮）+ 口令指纹（只留前 4 位）+ 8 位救援码 | 密码学 | Store, BackupStudioKit, ExportCenter, SecurityCenterView | 低 |
| core-audit-02 | 386 哈希链 `seal`：本条 hash 覆盖前序 hash + 全字段 | 密码学 | BackupStudio, CareViews | 低 |
| core-audit-03 | 双流水 `AuditLog.append/load`（封顶 500，NSLock 串行化）+ 开门/管理分流 `doorEvents/adminEvents` | 存储 | 全仓 48 处调用 | 低 |
| core-audit-04 | 386 防篡改 `verifyChain`：逐链重算 + **id 单调性**（堵"截掉前 N 条重封 GENESIS"的重放） | 计算 | DiagKit, SecurityCenterView×2, SecurityPage | 低 |
| core-audit-05 | 385 保留期 `purgeExpired`（0/3/6/12 月，到期物理删并留一条清理记录） | 存储 | LockKeeperApp, SecurityCenterView | 低 |
| core-audit-06 | 382 脱敏导出 `exportJSON`（密码类字段默认换成指纹前 4 位；勾选含明文需调用方二次确认） | 序列化 | SecurityCenterView | 低 |
| core-audit-07 | 388/953 敏感台账 `SensitiveLedger`（`record/recent/intentItems/memberItems/stamp`；意图族单独分区，避免把"最近 5 条"挤成快捷指令日志） | 存储 | SecurityCenterView, MemberCenterView, ClipboardCare, ExportCenter | 低 |
| core-audit-08 | 402 成员离职 `Offboard.markDeparted`（名下凭证入回收站 —— 旧归档族没有取回入口，等于进黑洞） | 编排 | SecurityCenterView | 低 |
| core-audit-09 | 383 销毁 `DestroyKit.destroyAll`：随机字节覆写 N 轮 + 销毁前采样残留；`sudoRequired` 无券则**什么都不动**并返 nil | 编排 | SecurityCenterView | 低 |
| core-audit-10 | 406 残留复核 `residueSelfCheck`（两条硬不变量，不依赖调用方传值）+ 400 备份闸 `lastBackupAt/backupGatePass`（毫秒→秒口径已修正）+ 旧版内部件 `hashInput`/`destroyLocalFiles`/`checkResidue`/`remainingSecretFileTexts`（能力已被 406/383 取代）+ 口令重复检测 `PwReuse.reuseWarnings` | 计算 | SecurityCenterView, 仅本文件内 | 中 |

## 6. Core/AutoOpen.swift（812 行）

靠近自动开锁门控链 F0/F1/F2'/F3/F4/F5/F6，全绿才经既有 `LockService.unlock` 下发 cmd04；默认全关、fail-closed。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-auto-01 | 主开关 `on` + 面容档位 `faceTier`（0 免额外验证 / 非 0 严格；**未知值一律按严格**，配置漂移只能往严的一侧靠） | 配置 | MePage | 低 |
| core-auto-02 | rc=26 防拆挂起 `suspendUntil/setSuspendUntil/isSuspended`（到点前一律 fail-closed 拒） | 状态 | 仅本文件内 | **高** |
| core-auto-03 | F0 前台门 `defendActive`（跨午夜时段；**起==止按全天布防**，把空集读成"不布防"等于一次配错就关掉门） | 计算 | Tests×14 | 低 |
| core-auto-04 | F1 面容门 `faceFresh` 两档 + `noteFaceSuccess/lastFace`（0 档不发起任何弹窗 —— iOS 没有静默生物识别） | 计算 | Tests×11 | 低 |
| core-auto-05 | F2' 信号门 `rssiSample` 回差滤波（武装/解除线**在线性功率域**换算；直接对 dBm 乘系数会把方向搞反） | 计算 | Tests×10 | 低 |
| core-auto-06 | F3 标定 `p95/armThreshold/disarmThreshold/fallbackBase`（未标定退回 -40；旧写法返回 nil 会让自动开锁对未标定用户**永不触发**） | 计算 | Tests×3 | 低 |
| core-auto-07 | F3 标定存储 `AutoCal` + `autocal/saveAutocal/removeAutocal` | 存储 | 仅本文件内 | 中 |
| core-auto-08 | F5 一次性冷却 `coolReady` + 校时自愈 `dualTimeSync`（防"把错手机时间写进锁 → 全钥匙时间窗集体错乱"的自伤 DoS） | 计算 | Tests×11 | 低 |
| core-auto-09 | 拒因链 `Reject.rejectReason`（顺序即门序）+ 人话 `rejectText` + 审计 `AuditEntry/audit/audits/lastReject`（只记哪道门拒、哪把锁、何时，永不记密钥） | 状态 | `rejectText`/`lastReject` 零调用 | **高** |
| core-auto-10 | 面容服务抽象 `FaceService` + `SystemFaceService`（严格档弹窗 / 标准档 60s 静默复用窗口） | 服务 | 本文件默认注入 | 低 |
| core-auto-11 | 控制器 `AutoOpenController` 六个入口（`onForeground/onBackground/feedRssi/rssiArmed/tickDwell/attempt`）+ 四个私有件 `makeContext/dispatch/selfHealTime/doorName` + 距离标定页 `AutoCalView`（实时 RSSI 波形 + §3.4 **强制**风险披露） | 编排/组件 | LockKeeperApp×3, LinkSenseKit×2, Destination, MePage | **高**（四个私有件零调用：0E 自愈校时写了但没接） |

## 7. Core/BatteryCare.swift（517 行）

包4 电量·维护·固件关怀 —— 本地采样与提醒引擎（纯数据层，无 UI）。协议只给百分比，不虚构电压/充电态/续航。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-batt-01 | 电量采样表 `BattSample` + `samples/latest/sample`（读 03 追加点，90 天截断） | 存储 | StatsKit, BackupStudioKit, DevicePage | 低 |
| core-batt-02 | 统一展示读数 `displayPct`（采样与快照取较新，都缺则 -1 未知；调用方另标采样时间） | 计算 | CareViews | 低 |
| core-batt-03 | 电量→档位/图标**唯一映射** `tier`/`icon`（曾有三套：p=5 时两屏分别显示 0%/25%，同一格电量两个样子） | 计算 | Theme×11, ExportCenter, Milestones, SecurityCenterView | 低 |
| core-batt-04 | 1004 低电判定 `isLow`(≤20%，与 287 可调横幅阈值独立) + 全 App 动效压到 calm 的 `appLowBattery` | 计算 | CareViews | 低 |
| core-batt-05 | 界面电量写法 `facePct`/`faceText`（"--" 未读到 / ">80%" 粗估档不假装精确） | 格式化 | — | **高** |
| core-batt-06 | 1040 单日掉电 `bigDropDays`（只相减真实采样点，不拟合不外推） | 计算 | DevicePage | 低 |
| core-batt-07 | 118 换电复位 `recordBatterySwap`（强制落基线点 + 重置低电武装位 + 写 1014 事件；采样表**不清空**，跳升本身是有效样本） | 编排 | CareViews | 低 |
| core-batt-08 | 1022 保养周期 `carePeriodDays`（近 30 天开门 ≥60 次则 90→60 天；此前三份实现，第三份把 90 写死在字面量里） | 计算 | CareViews, CarePage | 低 |
| core-batt-09 | 保养状态 `CareState` + `care/saveCare/markCareToday/careStreakMonths`（自定义 decodeIfPresent：加字段不能让旧 JSON 解码失败而静默清档） | 存储 | CareViews×30, CarePage×28 | 低 |
| core-batt-10 | 维护事件 `MaintEvent` + `events/addEvent`（1014 更换电池 / 1028 专属过滤） | 存储 | CarePage×4, SecurityCenterView×3 | 低 |
| core-batt-11 | 固件族 `FWLibItem/addFWLib`、`DFURecord/addDFURecord`、`FwSince/fwSince`；1019/1026 低温季 `isColdSeason`+`coldCityTable`；`CareSchedule` 免扰/阈值/启动巡检/日历提醒；即时通知 `notifyNow`（五类，免扰静默丢弃、`dayDeliver` 顺延 08:00） | 存储/编排 | FirmwarePage×3, DevicePage, LinkSenseKit×2, BackupStudioKit, StatusCheckNotice, LockKeeperApp | 中（`notifyNow` 仅本文件内 7 处调用，无外部触发点） |

## 8. Core/ClipboardCare.swift（114 行）

405/238 敏感内容剪贴板自清 —— 全仓唯一出口（choke point）；"90 秒"这个延时数只在本文件写一次。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-clip-01 | 延时自清 `copySecret`（`ttl` 默认 60s，0=关，钳制 0…600s；`via` 只进提示文本供人肉排查） | 编排 | CredentialStudio×3 | 低 |
| core-clip-02 | 代数守卫 + changeCount 校验：**只在剪贴板仍是当时那串时才清**，用户中途复制别的绝不替他删 | 状态 | 本文件 | 低 |
| core-clip-03 | 517 一键清除 `clearNow`（不等 ttl，复用同一代守卫）+ 清空时长设置 `setTTL`；344 粘贴建议条 `Suggestion`（recopy 重新起算窗口 / dismissSuggestion 就地收起，不挂成常驻广告）+ 状态机 `PasteStage` 与内部快照 `Pending` | 编排 | LockKeeperApp, SecurityCenterView, LockKeeperApp×2 | 低 |


## 9. Core/Components.swift（2,744 行）

组件库 · 第二块基石：每个组件只做一件事，没有"可选参数矩阵"，所有视觉取自 Theme 令牌。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-comp-01 | `XPanel` 全 App **唯一**卡片（实色 surface / 圆角 24 / 零投影 / hero 34；旧实现有四处违反规范） | 组件 | MemberCenterView×27, SecurityCenterView×27, ExportCenter×17 | 低 |
| core-comp-02 | `XHairline` 卡内分隔线（全宽不内缩，上下各 14pt 节奏）+ `XScreen`/`XNavTitle` 页面骨架（标题到首卡 74pt）+ `XRow` 标准行 | 组件 | MePage×14, DiagnosticsPage×8, MemberCenterView×6, CarePage×3 | 低 |
| core-comp-03 | `XStatCard`/`XStatSection` 分段统计卡（段间自动插 0.5pt 全宽线）+ `XEmptyState` 统一空态 | 组件 | HomeConsole, DevicePage, ExportCenter, CredentialBinView, AlarmsPage | 低 |
| core-comp-04 | `XToneColor` 五档语义色调 + `XStatusPill` 状态胶囊（语义色+文字，不单靠颜色区分） | 令牌 | LockKeeperApp, DevicePage, DonglesPage, MemberCenterView×3 | 低 |
| core-comp-05 | `XStatChip` 顶部胶囊行（高 56 / r18，**标签在上灰、值在下白** —— 最容易做反的一个组件）+ `XMetricTile` | 组件 | ManagerFace×12, HomeConsole×6, KeysPage×5, StatsPage | 低 |
| core-comp-06 | `XHeroNumber`/`XValueUnit` 主角数字与单位（单位=数值 70%、同色、同字重、基线对齐）+ `XDataRow` 彩色数据行（点与数字同色） | 组件 | MemberCenterView×5, CarePage×3, KeysPage×5, SecurityCenterView×4 | 低 |
| core-comp-07 | 按钮族 `XPrimary`/`XSecondary`/`XDestructive`/`XBusy` + `AnyButtonStyle` 擦除（SwiftUI 要求 ButtonStyle 是具体类型） | 组件 | BackupStudio×3, BackupPage×2, ExportCenter×12 | 低 |
| core-comp-08 | `xFont` / `xFontExact` 排版**唯一入口**（字阶全线下修一档；exact 是为图表轴/量规开的逃生门，两重载会歧义故改名） | 格式化 | xFont 全仓 953 处、xFontExact 53 处 | 低 |
| core-comp-09 | §7.18 数字溢出降档 `xFontScaled`（按位数分档，不用 minimumScaleFactor —— 那会逐条缩出不同比例） | 格式化 | — | **高** |
| core-comp-10 | `xPlate`/`xCallout`/`XPlateShape` 底衬与提示块（capsule/tile/control/iconBadge） | 组件 | HomeConsole×5, CredentialStudio×4, LockKeeperApp×3 | 低 |
| core-comp-11 | `destined`/`XDestinedModifier` 目的地台账标记（**零视觉作用**，供 tools/destmap.js 与 uicoverage 扫描） | 台账 | MemberCenterView×6, BackupStudio×3, CareViews×2 | 低 |
| core-comp-12 | `XCodeRing` 时效码大环（6/7/8 位自适应字号，末 5 秒转橙，录制中遮码）+ `XCycleRing` 粗三环 + `startPulse` 超期脉冲 | 组件 | — | **高**（两个环型零引用：OTP 大卡与周期环都没上屏） |
| core-comp-13 | `XHeroCard` 旧 HeroCard 别名 | 组件 | — | **高**（注释自承"一直是个空壳"） |
| core-comp-14 | `XDayClock`/`XBatteryGauge`/`XSkewBar`/`XStepBar` 仪表四件（`XBatteryGauge.animateTo` 零调用） | 组件 | StatsPage, DevicePage, DeviceHomeView, BackupStudio | 中 |
| core-comp-15 | `xScrollLift` 卡片进出边缘连续形变 + `xScaledWidth` 固定列宽随字号缩放（AX3 下 10 处写死列宽会一起垮） | 组件 | SecurityCenterView×19, ExportCenter×11, StatsPage×5 | 低 |
| core-comp-16 | `XSegmented` 全仓唯一分段控件（胶囊式，此前三种混用）+ `XInlineError` 行内错误条（图标+一句话+重试）+ `XGlassSurface`/`xGlass` 功能层玻璃 + `XSkeleton` 占位 | 组件 | BackupStudio×2, ExportCenter×2, AddKeyPage, AddFingerPage, GatewayPage, AccessibilityKit×3, EventsPage, AlarmsPage, StatsPage | 低 |

## 10. Core/CredentialOrg.swift（1,539 行）★ 冗余重灾区

包6 凭证列表·批量·流转。**43 个业务函数全仓零调用** —— 本层最大的死代码聚集地（明细见文末专题 A）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-cred-01 | 487 版本快照 `CredSnapshot` + `snapshot`（每凭证 N 版、495 星标豁免、488 auto 版不计配额且置顶标记） | 存储 | BatteryCare, LockKeeperApp×3, FirmwarePage | 低 |
| core-cred-02 | 496 恢复即新版本 `restore`（不覆盖、按基线复制、留"恢复自 v(s)"快照）+ 494 `snapshotBeforeDelete`（历史+回收站双通道找回） | 编排 | CredentialBinView, BackupStudioKit, BackupStudio | 低 |
| core-cred-03 | 字段级 diff `Diff/diff`（值/时段/备注逐字段，口令只比指纹）+ 380 审计联动 | 计算 | AuditChain, ExportCenter, SecurityCenterView | 低 |
| core-cred-04 | 497-506 回收站 `CredBinEntry/CredBinSource` + `bin/saveBin/addToBin` + 保留期 `reclaimDays`（498 来源：手动/批量/过期/重录/孤儿） | 存储 | CredentialBinView×3, SecurityCenterView, DFUKit | 低 |
| core-cred-05 | 506 撤销 `undoRemove` —— 收回未发出的锁端删除 + 清 361 停用便签的**完整**语义（只做 `undoBin` 会留下"队列还排着删除刚恢复的那条"） | 编排 | CredentialBinView | 低 |
| core-cred-06 | 删除执行内部件 `purgeBin`(502 裸执行口)/`purgeNow`/`sweepReclaim`(497)/`reclaim`/`cancelPendingDelete`/`clearDisabled`/`undoBin` | 编排 | 仅本文件内 | 中 |
| core-cred-07 | 501 级联入回收站 `cascadeBinMember` + 删除成员预告 `memberCredentialPreview`（跨锁合计，锁名走 `LockArchive.displayName`） | 编排 | MemberCenterView×3 | 低 |
| core-cred-08 | 365 下发队列 `CredQueueItem/CredQueueState`：`enqueue/markQueue/pendingCount/pendingQueue/sendQueued/launchTick`（`sendQueued` 是队列项**唯一**下发实现） | 编排 | MemberCenterView, LinkSenseKit, LockKeeperApp | 低 |
| core-cred-09 | 353 批量停用 `batchDisable`（本地移除+入回收站+锁端删除入队）+ 348 批量延期 `batchExtend` + 349 批量移交 `batchTransfer` | 编排 | KeysPage×3 | **高**（后两件零调用） |
| core-cred-10 | 526/921 星标 `stars/toggleStar/starSuggestion` + 批量置顶 `setStar`/`isStarred` + 354 归档 `setArchived/isArchived` | 存储 | KeysPage, QuickPool, SecurityCenterView, Milestones | **高**（`setArchived` 注释自承"15 处过滤全是空操作"） |
| core-cred-11 | 359 三档预警 `CredAlert` + `alert/saveAlert/scheduleAlerts/dayTier/addCalendar` + 930 角标 `expiringSoonCount` + 2 小时档 `dueSoonPwds` | 编排 | Alerts, SecurityCenterView, MemberCenterView, HomeConsole, KeysPage | 中（组内两件写侧零调用） |
| core-cred-12 | 建议 `Advice/advice` + 355/914 分组与四维排序 `CredSortKey/CredGroupMode` + 527 智能列表 `CredSmartList` + 350 `smartSet` | 配置 | DiagKit（其余仅本文件内） | 中 |
| core-cred-13 | 304/314 同值与前缀混淆 `duplicatePwdValues/duplicatePwdLockNames/prefixConflict/overlapWindows` | 计算 | CredentialStudio, AddKeyPage | 低 |
| core-cred-14 | 9 安全审计 `PwdRisk/passwordRisks`（同值/超期/弱口令三类**写死**判据，不编"强度评分"）+ 七件判据内部件 | 计算 | SecurityPage | 低 |
| core-cred-15 | 311/316/320/326/335 用量族 `openCountInWindow/inferredLastUseMap/openTimes/lastUse/fpUseCount30d/fpAlarmLogCount/usageCount`（锁端无逐凭证计数，全部按时间窗推断并标"约"） | 计算 | — | **高**（九件零调用：同码引用与指纹档案整族未上屏） |
| core-cred-16 | 331 本机提前失效四件 + 333 首用回执 `firstUse`（上界必须一起滤）+ 343/345 TOTP/静态码存储 + 界面读法 `ownerName/displayPwd/pwdState/expiryLabel` | 计算/格式化 | CredentialStudio, BackupKit, BackupStudioKit, KeysPage×9, MemberCenterView, QuickPool | **高**（`isEarlyExpired`/`earlyExpiryNote`/`setEarlyExpireMin` 写侧零调用） |

## 11. Core/Destination.swift（34 行，生成文件）

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-dest-01 | `Destination` 22 个界面站点枚举（呈现通道 20 + 仅被 `.destined()` 引用的 2 —— 后一半删掉会直接编译失败） | 台账 | Components, SecurityPage | 低 |
| core-dest-02 | rawValue = View 类型名，供 `tools/uicoverage.js` 与本台账对账；漏一条就是某套界面缺一页而没人发现 | 台账 | 工具链 | 低 |
| core-dest-03 | 生成纪律：`node tools/destmap.js --emit` 生成，**不要手改** | 台账 | 工具链 | 低 |

## 12. Core/DevModules.swift（18 行）★

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-dev-01 | 设备页模块显隐（乱源治理第 3 批）：文件只有设计说明与 `import Foundation`，**零声明 → 整批功能未实现** | 配置 | — | **高** |
| core-dev-02 | 设计口径：**默认一块都不隐** —— 这一批改的是"能不能关"这个能力，不是观感默认值 | 设计约束 | — | 中 |
| core-dev-03 | 必留五块刻意不进面板：设备切换器 / 176pt 开锁圆盘 / 三个可排序槽 / 异常卡 / 换机迁移向导（藏了就等于把 App 变成台账浏览器，或让用户自己把警告闭嘴）；存储约定：单键 CSV + 白名单过滤 + 去重，认不出的 id 一律丢掉（与 `QuickPool` 同口径，改名不会打空用户设置） | 设计约束 | — | 中 |

## 13. Core/DiagKit.swift（696 行）

包11 诊断·性能·运维数据层（无 UI，全部本地；本仓"数据库"是 UserDefaults 语义封装，故 VACUUM/索引类创意按等价落地）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-diag-01 | 时间戳族 `DiagTime.hhmmss/mmddHHmm/full`（locale 无关，台账可比对） | 格式化 | LockService, AutoOpen, LinkSenseKit, Store | 低 |
| core-diag-02 | 诊断操作流水 `DiagOp` + `DiagOps.isOn/record/list` | 存储 | LinkSenseKit, DiagnosticsPage, SecurityCenterView | 低 |
| core-diag-03 | 启动分段计时 `StartupTrace.mark/ms` + 预热门控 `Prewarm.run` | 计算 | LockKeeperApp×4, DiagnosticsPage×2 | 低 |
| core-diag-04 | 热点缓存 `HotCache`（日志惰性加载 + `invalidate` 作废，比"写完立刻重读"少一次解码） | 缓存 | Store, ExportCenter, EventsPage, HomeConsole | 低 |
| core-diag-05 | 748 扫描统计 `ScanStats.record/recent` + 省电建议 `advice`（按近 7 天**真实**日均扫描秒数，不是档位科普） | 统计 | LinkSenseKit | 中（`advice` 零调用） |
| core-diag-06 | 分级日志 `DiagLogs.all/today/append/applyRetentionNow` + 本地日 key（**不能用 `.iso8601`**：UTC+8 在 00:00–08:00 会拿到"昨天"） | 存储 | ExportCenter×25, MemberHub, CredentialOrg | 低 |
| core-diag-07 | 154/543 实体识别 `EntityRef` + `Kind`（日志里可深链的凭证/指纹批次/成员名/MAC） | 解析 | — | **高**（两个类型零引用：深链实体卡从未渲染） |
| core-diag-08 | BLE 遥测 `BleTelemetry.recordEvent/recordAttempt` + `BleEvent/ConnAttempt` 落盘 | 存储 | LinkSenseKit×26, DiagnosticsPage | 低 |
| core-diag-09 | 748/756 按日成功率 `DayRate` / 失败归类 `FailClass`（本地词表给"重试建议"） | 统计 | — | **高**（两个类型零引用：数据建好没人读） |
| core-diag-10 | 127 静默排查 `DiagFlags.silent`（暂停冷启动扫描/自动预热/到场补发/自动重连/会话巡检/自动连接 6 处自动动作） | 配置 | LinkSenseKit×7, LockKeeperApp | 低 |
| core-diag-11 | 崩溃护栏 `CrashGuard`：最后界面 / 异常退出 / 干净退出 / 会话时长 / 档案列表（真机闪退时唯一线索） | 状态 | LockKeeperApp×8, DiagnosticsPage, Components | 低 |
| core-diag-12 | 数据健康 `DataHealth.integrity/gapDays/archiveOldLogs/human`（JSON 回环 + 台账计数核对 + 451 空洞日 + 223 归档） | 计算 | DiagnosticsPage×3, LockKeeperApp, SecurityPage | 低 |
| core-diag-13 | 546/152 存储构成 `Family` / `Slice`（各 kf_ 键族体积估算 / 三段构成条） | 统计 | — | **高** |
| core-diag-14 | 页面打开耗时 `PageTrace`（tab 变更到 onAppear 的墙钟，属下界型参考值）+ 387 维护回执 `MaintenanceLog.record` + 387 上一会话 `lastSessionLine/markSeen` + 397 自检 `SelfCheck.run/summary` | 统计/计算 | LockKeeperApp, DiagnosticsPage, LinkSenseKit, Store, BackupStudioKit, ManagerFace | 中（`lastSessionLine`/`markSeen` 零调用） |

## 14. Core/ErrorText.swift（60 行）

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-err-01 | `ErrorText.human` 错误翻译（"write failed"/"rc=5" 翻成用户读得懂的话） | 格式化 | DonglesPage×5, BackupPage×3, GatewayPage×3 | 低 |
| core-err-02 | 认不出就**原样返回** —— 备份模块的错误本来就是说人话的（"口令错误或内容被篡改"），硬套模板反而把好文案改坏 | 设计约束 | 同上（全仓 20 处） | 低 |
| core-err-03 | `Error`/`String` 双重载入口 | 格式化 | 同上 | 低 |

## 15. Core/FirmwareHistory.swift（40 行）

755 固件版本随行标注（刻意不叫"固件历史"：观测点只在读状态时产生，中间升过几次本机无从得知）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-fwh-01 | 记录一次观测 `record`（每次成功读 03#31 顺带记"哪天看到哪个固件"，fw 为空则不记） | 存储 | LockService | 低 |
| core-fwh-02 | 按日查询 `observed`（"该日或更早"最近一次，找不到返 nil —— **不用当前版本冒充历史版本**） | 计算 | — | **高** |
| core-fwh-03 | 观测点列表 `observations`（详情页用，最新在前） | 计算 | — | **高** |

## 16. Core/HexKit.swift（97 行）

十六进制/字节工具，与 JS utils/crypto.js、kernel/protocol.js 逐项对齐（golden.json 差分）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-hex-01 | `bytes`/`hex` 字节↔十六进制（**尽力解**，非校验：奇数长/非 hex 会静默产出偏短结果，不能当判据用） | 解析 | DFUKit×17, ExportCenter×17, BackupKit×12 | 低 |
| core-hex-02 | `u16leHex/u32leHex/readU16LE/readU32LE` 小端整数读写 | 解析 | ZKCmdBuilder×19, DFUKit×5, ZKProtocol×3 | 低 |
| core-hex-03 | `hexPair/fillZeroLeft/reversePairs` 成对、补位与字节对反转；`asciiHex/utf8Hex/hexToAscii` 文本编码互转 | 解析 | ZKCmdBuilder×19, ZKProtocol×12, HardwareService×3, ZKCmdBuilder×3, HardwareService×4 | 低 |

## 17. Core/HintOnce.swift（13 行）

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-hint-01 | 42 首用提示打点 `shown`/`mark`（每条一个键 `kf_hint_<id>`） | 配置 | LockKeeperApp×4 | 低 |
| core-hint-02 | 刻意不做"看过引导"总开关（会让"看过这一条"变成"永远看不到别条"），也刻意不自动计时消失（气泡自己飘走 = 用户没读就被判定已看过） | 设计约束 | — | 低 |
| core-hint-03 | 刻意不提供 `clear`：抹掉看过记录 = 重置教程，不该免销毁权限就能碰；`kf_hint_*` 前缀让核弹销毁天然覆盖 | 设计约束 | — | 低 |

## 18. Core/HolidayFeed.swift（162 行）

671 在线假日表（内置表兜底 + 选源 + 手动拉 + 可开关自动）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-hol-01 | 拉取校验链 `fetch`：只走 https；**整份校验通过才替换缓存**；返回的 year 必须等于请求年（防 CDN 递错年）；任一步失败保留上次好数据 | 编排 | 仅本文件内 | 中 |
| core-hol-02 | 年份载荷 `HolidayYearDTO/HolidayDayDTO` + `accept`（`isOffDay=false` 的**调休补班日必须保留** —— 任何"只看真假日"的简化都是丢信息） | 解析 | 仅本文件内 | 中 |
| core-hol-03 | 缓存 `cached/cacheKey` + 合并 `MergedCache/buildRows` | 缓存 | RecordSearch×2, BatteryCare, ExportCenter | 低 |
| core-hol-04 | 自动档 `autoRefreshIfNeeded`（本会话只发一次，且只在用户明确开过开关后 —— 离线锁管家静默联网要用户点头） | 编排 | LockKeeperApp | 低 |
| core-hol-05 | 开关 `setAuto` + 来源说明 `coverageText`（哪几年在线、最近一次何时拉）；选源 `setSource` / 清缓存 `clearCache`（公告改期或源不可信时回到只信内置表） | 配置 | SeasonIcon（同名不同义） | **高** |

## 19. Core/KeyGen.swift（86 行）

配网密钥族生成器（系统 CSPRNG：SecRandomCopyBytes；JS utils/keys.js 移植）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-keygen-01 | `randomBytes` 字节源 + `isAllZeroHex` 全零闸（全零 = 随机源故障的特征值） | 密码学 | AuditChain, BackupKit, SecurityCenterView, LockService | 低 |
| core-keygen-02 | `genSkey` 16B 母钥（32 hex） | 密码学 | LockService | 低 |
| core-keygen-03 | `genPins` PIN 池（n×4B LE、顶字节 &0x7F 使值 <2^31、池内互不重复）；`genBkey`（16B + 相邻字节约束变换）/ `genTrackId`(<2^31) / `randomDigits`(351 合包导出口令) / 单枚 `genPin` | 密码学 | LockService, CredentialStudio | 中（`genPin` 仅内部，池化版已覆盖） |

## 20. Core/LinkSenseKit.swift（959 行）

包2 连接感知与离线同步 —— **只预热不执行**（绝不自动开锁、绝不自动下发凭证）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-link-01 | `LinkSense` 单例 + 链路三态 `LinkState`(ready/connecting/down) + 信号围栏唯一读点 `rssiFence`（默认 -70 只写一处，改默认值的人不必再想起另外两处） | 状态 | LockKeeperApp×12, AutoOpen×3, DevicePage×2 | 低 |
| core-link-02 | 95/135 静默预热 `refresh` + 冷启动 `startupPreconnect/coldStartScan` + 回连 `startReconnectLoop` + 死链看门狗 `startDeadWatch` | 编排 | LockKeeperApp×3, KeysPage, ScreenCare, DiagnosticsPage | 低 |
| core-link-03 | 135 scenePhase 消费 `setSceneActive`（.active 预热+补发；非 active 暂停回连）+ 98 用户路径标记 `noteUserConnect`（解释快慢差异） | 编排 | LockKeeperApp×2 | 低 |
| core-link-04 | 537 下拉重扫 `scan` `scan` + 信号落档 `saveRssi` | 编排 | AddLockPage×10, DonglesPage×3, AutoOpen | 低 |
| core-link-05 | 128 环境拥挤度 `envCount/envFirstSeenMs` + 272 连接保持 `holdMinutes` + 270/129 弱信号提示 `weakSignalHint`（骤降优先，否则走绝对值门槛） | 统计 | 本文件 | 中 |
| core-link-06 | 69 跟随蓝牙开关 `syncBtOn` / 去系统设置引导 `openBluetoothSettings`（无 App 级深链 API，只能引导） | 编排 | LockKeeperApp | 中 |
| core-link-07 | 93/95 预握手 `preconnect/preconnectOthers/warmLocks`（一条扫描收多锁广播 —— 开两条只会互抢射频） | 编排 | DevicePage（其余仅内部） | 中 |
| core-link-08 | 96 补发 `onPreconnectDone/resync/autoReconnectTick` + 重连阶梯 `nextLadderInterval` + 统一 RSSI 入口 `updateRssi/markReady/deadbeatCheck` | 编排 | 仅本文件内 | 中 |
| core-link-09 | 队列项下发 `applyQueueItem`（**第四份副本**，实现已收进 `CredentialOrg.sendQueued`，此份弃用） | 编排 | 仅本文件内 | **高** |
| core-link-10 | 124/539 失败细则 `FailKind/classifyFailure/occupationHint/successRateText/bestHourHint`（口径与 DiagKit 同源，不假装是滚动 7 天） | 计算 | 仅本文件内 | 中 |
| core-link-11 | 537 重扫回传 `noteScannedRssi/rssiFor`（**只动"最近见到的信号"，不动连接态** —— 扫到广播 ≠ 已连接） | 状态 | — | **高** |
| core-link-12 | 三态切换记录 `StateHop/history` + 95 进页预热 `enterPage` + 70/97/100/539 连接偏好页 `LinkPrefsView` 与围栏档位 + 136 `BLEStrip`/69 `BLEOffBanner` 两条横幅 | 存储/组件 | Destination, MePage, LockKeeperApp×2 | **高**（`noteStateHop` 与 `enterPage` 零调用） |

## 21. Core/LockCommand.swift（125 行）

协议命令的**唯一安全分类表** —— 每条会上链的 cmd 必须登记一次，否则发包前被拒（fail-closed）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-cmd-01 | 30 条命令的读写分类（01/03/12/16/30/38/43/44 只读；其余 21 条写类需过 SecurityPolicy） | 协议 | LockService, HardwareService | 低 |
| core-cmd-02 | `policy`（nil = 只读，不触发任何安全闸）+ `label` 人话名（不复用 ZKCmd.name，未成帧时拿不到） | 协议 | 本文件 | 低 |
| core-cmd-03 | 296 上链前唯一判据 `requireAllowed`：新增命令若不在本表，会在发包前被拒，而不是悄悄绕过只读模式 | 协议 | LockService, HardwareService | 低 |

## 22. Core/Locked.swift（37 行）

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-locked-01 | 原生互斥容器 `Locked<T>`：让值由锁持有（`static var` 本身仍是全局可变存储，编译器照样看得见），`withLock` 是唯一访问路径 | 并发 | AccessibilityKit, DiagKit, HolidayFeed, Store, ClipboardCare×8 | 低 |
| core-locked-02 | 选型：NSLock 而非 OSAllocatedLock（后者在 CI 的 Xcode 27.2 上 `cannot find in scope`） | 设计约束 | — | 低 |
| core-locked-03 | `@unchecked Sendable` 是**有依据的** unchecked：所有读写必须经 `withLock`，`value` 没有第二条访问路径 | 并发 | — | 低 |

## 23. Core/LockGuard.swift（175 行）

应用锁安全族消费者（389–395/398）—— 这些键位此前只在设置页写与显示，验证路径一个都不读。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-guard-01 | 392 失败累加 `registerFailure`（30s·2^n 上取冷却封顶 10 分钟 + 留痕；关冷却时仍累计连败供 877 用） | 状态 | SecurityCenterView | 低 |
| core-guard-02 | 393/394 退后台锁定 `onBackground`（"" 或未知档位 = 退后台即锁，最严；m1/m5/next 记到期时刻） | 编排 | LockKeeperApp×3, AutoOpen | 低 |
| core-guard-03 | `LockAction` 七族危险动作 + `blockedInReadOnly`（296 全族停，但**设置页开关本身不在族内** —— 一把全锁死就不是应急位而是自锁） | 协议 | LockCommand | 低 |
| core-guard-04 | 383 `SudoTicket` 入场券（init fileprivate ⇒ 外部造不出，只能由 SecurityPolicy 当场验口令后发） | 安全 | AuditChain, LockKeeperApp, SecurityCenterView | 低 |
| core-guard-05 | 五枚开关唯一判据口 `SecurityPolicy`：377 访客 / 377 筛敏感 / 383 sudo / 296 只读 / 376 遮半（刻意不加 @MainActor，否则每个调用点都得绕路再写回 DB） | 配置 | SecurityCenterView×30, LockKeeperApp×5, DFUKit×4 | 低 |
| core-guard-06 | `allows`/`denialMessage` 放行与拒因（点名是哪枚开关拦的，不写含糊的"操作失败"） | 协议 | SecurityCenterView, LockKeeperApp, DFUKit | 低 |
| core-guard-07 | 376 遮码 `masked`（前一半原样、后一半逐位糊；**两位以下原样返回** —— 一位码遮完等于把口令吞了却不给提示）+ `halfMasked`；`sudoTicket`/`sudoTicketBiometric` 验过才发券（2026-10-17 拍板 A：生物复核走同一张券，界面仍造不出无凭据的券） | 格式化 | Components, CredentialStudio, SecurityCenterView×13, LockKeeperApp×2 | 低 |

## 24. Core/LockKeySpace.swift（72 行）

每锁数据族的**唯一所有权表**（UserDefaults 里 300+ 个 `kf_*` 键没有命名空间机制）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-kspace-01 | 三档键族表：`suffixPrefixes`(前缀+mac) / `segmentedPrefixes`(前缀+mac+尾段) / 兜底"键含 MAC" | 配置 | 本文件 | 低 |
| core-kspace-02 | `owns` 归属判定（大小写不敏感，兼容 DemoKit 大写 demoMac；旧实现两套判据写在同一函数里） | 计算 | MemberHub×3, MemberCenterView×3 | 低 |
| core-kspace-03 | `purge` 清掉一把锁的全部逐锁键（调用方负责钥匙串/未完成配网记录/全局指针） | 存储 | Store | 低 |


## 25. Core/LockStats.swift（438 行）

包3 设备档案与多锁总览（纯本地只读现有表，不新增采集，不碰协议）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-lstats-01 | 单锁档案 `LockMeta`（106 备注 / 105 符号色标 / 774 场所副标题 / 290 电池档案 / 258 首连验证 / 292 沉睡基准 / 104 分组） | 存储 | CareViews | 低 |
| core-lstats-02 | 档案读写 `LockArchive.meta/save`（独立键 `kf_lockmeta_<mac>`，不动 Keychain ⇒ 备份 schema 与小程序互通不受影响） | 存储 | BackupStudioKit×15, BackupKit×12, LockProfilePage×3 | 低 |
| core-lstats-03 | 292 连接刷新 `touchConnected` + 258 链路已验证 `markVerified`（首开成功 = BLE→会话→04→日志 全链跑通） | 状态 | LockKeeperApp×3 | 低 |
| core-lstats-04 | 108 手动隐藏 `isHidden/setHidden`（与"沉睡"自动判据**刻意分开**：凑成一个开关就会出现"我没藏它，它自己不见了"） | 存储 | LocksPage×3, BackupKit, LockProfilePage | 低 |
| core-lstats-05 | 271 启动默认锁 `defaultMac/setDefaultMac`（与 766 只留一个真相）+ 292 沉睡 `isSleeping` | 存储 | 仅本文件内 | 中 |
| core-lstats-06 | 104/767 分组 `group/normalizedGroup`（去空白 + 12 字上限，两处写同一字段）+ `setGroup` + `groupPresets` | 存储 | MemberCenterView×27, SecurityCenterView×26, BackupKit | 低 |
| core-lstats-07 | 现存组 `grouped`+`LockGroup`（按组内首锁在总顺序里的先后，"未分组"固定垫底） | 计算 | Theme, EventsPage, BackupKit | 低 |
| core-lstats-08 | 766 手工顺序 `setOrder/orderedDevices/clearManualOrder` + 组内拖动回写 `reordered` + 置顶 `pinToFront` | 存储 | 仅本文件内 | **高**（后两件零调用：766/104 的拖动与置顶动作没有入口） |
| core-lstats-09 | 105 色标盘 `Swatch/swatches/swatchColor` + 符号盘 `SymbolOption/symbols` | 组件 | LockProfilePage×3 | 中（`symbolName` 零调用） |
| core-lstats-10 | 769 显示名 `displayName` + 774 副标题 `subtitle`（场所优先、缺省回退型号） | 格式化 | ExportCenter×11, LocksPage×6, SecurityCenterView×25, LockKeeperApp×10 | 低 |
| core-lstats-11 | 769 绑定时间小字 `boundLabel`（未记录就不虚构日期） | 格式化 | — | **高** |
| core-lstats-12 | 776/778 全锁聚合 `LockUsage`+`usage`（30 天窗口；`logged` 区分"0 次"与"从未同步"；`alarmRate` = 告警/(告警+开门)） | 统计 | BatteryCare×2, DevicePage | 低 |
| core-lstats-13 | 291 快照采样时刻 `snapAt/statusTime`（断连展示"数据截至 14:32 · 缓存"） | 计算 | BatteryCare, DevicePage | 低 |
| core-lstats-14 | 768 待维护清单 `MaintenanceItem/maintenance` + 787 对比结论 `summary` + 784 固件对照 `fwLag/fwCmp` + 764 近 N 天告警锁集合 `recentAlarmMacs` | 统计 | Destination, CareViews, DiagKit×4, DiagnosticsPage, ManagerFace, DevicePage | **高**（`recentAlarmMacs` 零调用） |

## 26. Core/MemberHub.swift（333 行）

包13 成员·家庭协作数据层（纯本地，不动协议层与备份包 schema）。活跃度一律台账+归属推断，展示层强制带"约"。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-mem-01 | 成员档案扩展 `MemberExt`+`ext/saveExt`（挂在成员 id 上，不动 Member 结构体 ⇒ 备份互通不受影响） | 存储 | MemberCenterView×28, ExportCenter×19 | 低 |
| core-mem-02 | 归档与活跃 `archivedIDs/isActive`（归档成员不参与常规名册） | 存储 | MembersPage×3, ManagerFace, MemberCenterView | 低 |
| core-mem-03 | 470 权限矩阵 `permRows/permAllows/permCan/permCannot`（查不到的项一律按不允许走，不做"默认放行"；且**真按它亮灭**两枚开关，不再只是说明文字） | 协议 | MemberCenterView | 低 |
| core-mem-04 | 成员展示 `roleLabel`/`display`（称呼+备注+色标）+ 666 编号兜底 `unnamedLabel`（多位未命名时同名分不出人） | 格式化 | Theme, MemberCenterView×9, MembersPage×6 | 中 |
| core-mem-05 | 919 时间线别名 `aliasName`（relation 非空才替换显示；匹配与凭证深链仍走裸名，不被别名污染）+ 461 双层文本 `doubleLine` | 格式化 | LockKeeperApp | 中（`doubleLine` 零调用） |
| core-mem-06 | 793 访客虚拟行 `isVisitorRow`（临时码类且无可证明归属，与家人独立分组） | 计算 | — | **高** |
| core-mem-07 | 262/799 活跃度 `Activity/activity`（30 天无可证明归属 → 置灰）+ 周小结 `weekSentence` + 摘录 `Excerpt/recentExcerpts` | 统计 | MemberCenterView×5, MembersPage | 低 |
| core-mem-08 | 462 认领 `claims/claim/reassignClaims`（合并只迁凭证不迁认领 → 记录挂已不存在的 id 显示"无法归属"） | 存储 | Store×6, MemberCenterView×2 | 低 |
| core-mem-09 | 468 代管名单 `proxyNames`（三处读点共用一份判据：成员页行 / 482 会议摘要 / 凭证页停用便签） | 配置 | Store×6 | 低 |
| core-mem-10 | 关系图谱 `Edge/peerName/graphCap`（取**最后一条**「移交 → X」快照画边，上限 24 条） | 计算 | 仅本文件内 | 中（`appendEdge` 零调用 → 图谱画不出边） |
| core-mem-11 | 794 隐私浏览 `setPrivacy` + 479 长辈模式 `elderMode/setElderMode`（改的是钥匙页那一族：分段只留三类 + 隐藏批量导出）；关怀到期 `CareDue/careDue` + 归属来源计数 `sourceCounts` | 配置 | MemberCenterView, CareViews×4, MemberCenterView×2 | 低 |

## 27. Core/Milestones.swift（617 行）★ 冗余重灾区

包18 游戏化·情感化·纪念统计与成就引擎（纯数据层；一次结算 O(日志≤300/锁)，UI 只读结果，全离线）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-mile-01 | 徽章定义 `Badge` / 979 稀有度 `BadgeRarity` / 977 四类 `BadgeCat`（管家·守护·整理·探索）+ 978 隐藏 | 配置 | MemberCenterView×3 | 低 |
| core-mile-02 | 徽章结算 `evaluate`（写 `kf_ach_done`，返回增量供 UI 播庆祝/通知） | 编排 | LockKeeperApp | 低 |
| core-mile-03 | 徽章陈列 `badge/unlockedMap/latestUnlocked`（988 最近点亮 n 枚）+ 998 周年回忆 `badgeAnniversaryToday`（恰好满一年同月日） | 统计 | MemberCenterView×10, LockKeeperApp×4, ManagerFace×3 | 中 |
| core-mile-04 | 统计快照 `MStats` + `loadStats/satisfies`（995 join1 真判据：建过档 ∧ 名下有归属凭证） | 统计 | 仅本文件内 | 中 |
| core-mile-05 | 日/月 key `dayKey/monthKey/mdKey` + 同月日 `isSameMonthDay`（日 key 唯一口径是 `StatsKit.dayKey`，此处曾自建 DateFormatter） | 格式化 | StatsKit×17, ExportCenter×16, RecordSearch×10 | 低 |
| core-mile-06 | 一次性成就 `onceDone/markOnce` + 1046 素颜模式 `plainMode`（时刻卡保留内容、不播粒子）+ 996 收集音 + 986 成就通知 | 配置 | LockKeeperApp×7 | 低 |
| core-mile-07 | 898 启动一句话 `launchPhrase`（按**当天**取一条 —— 用随机数会让 Hero 卡每重算一次就换句话，像在自言自语） | 格式化 | — | **高** |
| core-mile-08 | 结缘日 `bondDay` + `bootstrap` 首次初始化 | 状态 | LockKeeperApp, BLEService, HardwareService | 低 |
| core-mile-09 | 打卡族 `Streak/streak` + `markRecordsViewed` + `nightMarks` + `checkInTonight` + `canNightCheckIn`（22 点后；协议无上锁状态位，纯手动确认） | 存储 | 仅最后一件与配额件被读，写侧全空 | **高** |
| core-mile-10 | 24/992/1005 开锁里程碑 `UnlockCrossing/recordUnlockSuccess`（首开/100/1000）+ 千次心跳触感 `heartbeatHaptic` | 编排 | LockKeeperApp×2 | 低 |
| core-mile-11 | 980 备份里程碑 `recordBackup/lastBackupAt/backupStreakMonths` + 822「还没有备份」判据（读的就是同一本历史，不另开键） | 编排 | BackupStudioKit×3, BackupPage×2, BackupStudio | 低 |
| core-mile-12 | 本周整理 `weekDone`（读侧，周起点跟随 912）+ `recordOrganize`（写侧零调用 → 恒 0） | 统计 | 读侧仅本文件内 | **高** |
| core-mile-13 | 成员徽章 `memberBadges/setMemberBadge` + 生日 `memberBirthdays/setMemberBirthday/birthdayCelebrantToday`（991 今天的寿星） | 存储 | MemberCenterView, CareRemindersView×4 | 中（两个写侧零调用） |
| core-mile-14 | 成就胶囊 `Capsule/capsule/capsuleIsOpen/markVoiceOver` + 1011 陪伴天数三件 + 节气 `solarTermToday/solarTermHint` + `QuarterSummary` + 关怀通知 `CareReminders` | 组件/计算 | Components×7, AutoOpen×2, LockKeeperApp×3, CareRemindersView×4, BatteryCare | **高**（陪伴天数与节气整条链零调用） |

## 28. Core/NoticeBudget.swift（51 行）

乱源治理第 2 批：同屏"闲时提醒"唯一席位（任意时刻只挂一条，被压住的不丢）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-notice-01 | 四类候选 `Ambient`（本机自检异常 / 剪贴板建议 / 首用胶囊 / 逐格揭幕）+ `rank` 排位（数据完整性 > 限时隐私 > 首用教学 > 可等的逐格） | 配置 | LockKeeperApp×4 | 低 |
| core-notice-02 | `ranked` 纯函数（第 0 条上台，其余折进汇总胶囊；点开逐条给**它原本就有的动作**，不新造做不到的动作） | 计算 | LockKeeperApp | 低 |
| core-notice-03 | 不参赛四类：演示横幅 / 蓝牙关横幅 / toast 与 508 回执 / 377 访客入口（让位就等于撒谎或放开受限区） | 设计约束 | — | 低 |

## 29. Core/PidMap.swift（56 行）

产品矩阵与能力开关（JS utils/pidmap.js 移植，golden.pidTable / golden.capabilities 差分）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-pid-01 | 型号/产品名 `modelName/productName` | 解析 | StatusParser, LockStats×2, AddLockPage, FeedPage | 低 |
| core-pid-02 | 能力位 `canDefend/canTailgate/canDeviceUpgrade`（zn.can* 对应，决定哪些设置项该出现） | 协议 | Tests×6 | 低 |
| core-pid-03 | 品类判定 `isKnown/isGW` + 固件比较 `cmpFw` + `canClearPwd` | 解析 | 仅本文件内（`isLock` 零调用） | 中 |

## 30. Core/QuickPool.swift（172 行）★ 冗余重灾区

905 快捷格"十选六"池 + 1047 常用动作排前 + 921「再开一次」格。**池子每一项都对应真视图，没有为凑十格新造假入口。**

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-quick-01 | 候选池 `QuickPool.all`（11 项）+ 默认六格 `defaultIds`（= 旧版观感，不改变任何人现在看到的界面） | 配置 | LockKeeperApp | 低 |
| core-quick-02 | 读池 `selected`（白名单过滤 + 去重 + 保用户序；全不认识则回退默认六格，不打空设置） | 配置 | LockKeeperApp×2 | 低 |
| core-quick-03 | 写池 `setSelected` / 智能首格 `setSmartFirst` | 配置 | — | **高**（"长按编辑"的写侧完全没接） |
| core-quick-04 | 1047 学习机制 `recordingOn`（从未动过 = 静默学习，手动关 = 硬退出并清计数）+ `reached30d` + 频次表 `counts` | 配置 | 本文件 | 低 |
| core-quick-05 | 频次写入 `recordTap` / 清空 `clearCounts` | 存储 | — | **高**（无点击埋点 ⇒ `counts` 恒空 ⇒ 排序恒等于原序，1047 静默失效） |
| core-quick-06 | 三档排序 `ordered`（开关开=次数降序；关但满 30 天=只提最常用一格；其余=原序；**稳定排序，不做预测**） | 计算 | BackupStudioKit, LockKeeperApp | 低 |
| core-quick-07 | 921「再开一次」目标 `repeatTarget`（星标密码 > 星标指纹 > 高频推断；已归档的不作为直达目标）；池项→视图 `quickDestination` + 十一项 ID 即存储值（只能加不能改，改名会把用户设置打空） | 计算 | — | **高** |

## 31. Core/RecordSearch.swift（1,018 行）★ 冗余重灾区

包9 记录检索与告警核心（纯本地，只读既有台账）。纪律：告警类型只用 CAPABILITY §3 真实存在的 5 种，归属推断一律标"约"。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-rec-01 | 本机覆盖层 `RecordOverlay`：186 备注 `note/setNote`（空文本=删键不留空壳，否则完整性自查会数出无意义条目）+ 188 标旗 `flags/isFlagged/toggleFlag`，按 `mac#idxRaw` 存 | 存储 | AlarmsPage×3, EventsPage×3, CredentialOrg×34, SecurityCenterView×4 | 低 |
| core-rec-02 | 跨锁聚合行 `Rec` + 655 动词化文案 `RecordVerbs.line`（"张三 用 指纹 开了门"） | 格式化 | EventsPage×17, AlarmsPage×7, ExportCenter×70, MemberCenterView×4 | 低 |
| core-rec-03 | 724 四级告警 `AlarmMeta/isAlarm/level/levelName`（只对真实 5 种告警定级，协议无胁迫类**不虚构**） | 协议 | ExportCenter×24, LinkSenseKit×11, Components×6, BatteryCare×5 | 低 |
| core-rec-04 | 596 损坏类集合 `damageTypes`（7 防撬 / 10 试错锁定 / 224 键盘锁定）+ 告警措辞 `AlarmWords/phrase` | 格式化 | 仅 `damageTypes` 内部使用 | 中 |
| core-rec-05 | 告警行标题 `alarmTitle` / 同类预览 `sameCountPreview` | 格式化 | — | **高**（注释自承"此前无声明、编译期未解析符号" —— 告警页调用的是不存在的成员） |
| core-rec-06 | 564/566/567/568 查询过滤 `QueryFilters/key/load/save`（成员**跟着这一份一起存**，分开存会得到"过滤记住了、成员没记住"的半截行为） | 存储 | EventsPage×3 | 低 |
| core-rec-07 | 908 开场策略 `policyKey/setPolicy`（记住上次 / 每次空白 / 每次只看告警；非默认策略下照常保存是有意的） | 配置 | `setPolicy` 零调用 | 中 |
| core-rec-08 | 560 命名过滤视图 `NamedView/namedViews/saveNamedView/deleteNamedView` | 存储 | EventsPage×11 | 低 |
| core-rec-09 | 551 全局搜索 `search` + 554 中文时间短语 `Query.parse`（含 `monthDayComps` 防"13月1日"强解包崩溃） | 计算 | EventsPage×17, KeysPage×8, DFUKit, ExportCenter | 低 |
| core-rec-10 | 553 搜索历史 `history/pushHistory/removeHistory/clearHistory/historyCap`（存最新在前、读同序；此前从尾部截 5 条，第 6 条之后永不出现） | 存储 | EventsPage×4 | 低 |
| core-rec-11 | 671 节假日 `Holiday/holidayName/isMakeupWorkday`（**调休补班日必须与放假日分开**）+ 覆盖年上限（UI 才敢说"次年公告未发布前不显示"） | 解析 | HolidayFeed×4, StatsKit×3 | 低 |
| core-rec-12 | 569 越界开门 `OutWin/outOfWindow`（临时码时间窗外仍产生开门，本地检测标"约"）+ 737 今日试错 `trialRowsToday/trialCountToday/TrialEvent/trialEventsToday` | 计算 | — | **高**（两族零调用） |
| core-rec-13 | 649/676 深夜段 `nightFrom/nightTo/nightWindowDegenerate/isLateNight`（起==止为空集要**如实提示**）+ 672 假日顺延 | 计算 | StatsKit×2 | 中（三个写侧零调用） |
| core-rec-14 | 745 处置留痕 `Disposition/dispositions/disposition/testMarkedKeys`（结论+时刻；"测试"标记复用同一份不另造状态） | 存储 | ExportCenter×3, AlarmCenterView | 低 |
| core-rec-15 | 739 处置写入 `markDisposition` / 回退 `undoDisposition` / 727 清单 `checkState/setCheck` / 729 误报折叠 `misfireFold` | 存储 | — | **高**（写侧全空 ⇒ 734/735 的"未处置"恒等于全部） |
| core-rec-16 | 735/581 未处置告警 `unhandledAlarmDays/unhandledAlarmCount`（角标数据源）+ 596 `damageDays` + 741 同类告警 + 736 上下文 + 747 前后对比 + 723/765 跨锁流 + 处置排序 `rank` | 统计 | HomeConsole, MePage×5, DevicePage, ExportCenter×5, DataScannerView×3, AutoOpen×4, NoticeBudget×3 | **高**（`damageDays`/`alarmStream`/`mergedRecentOpens`/`aroundDays` 零调用） |

## 32. Core/Route.swift（98 行）

2026-10-16：目的地身份取代"裸整数 Tab 号"（旧实现里 sheet 端出的页面会去切一个不存在的 Tab，而 sheet 还盖在上面）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-route-01 | `Route` 四目的地枚举（device/credentials/records/settings）+ 顺序唯一声明 `byHost`（深链 host 表与 legacy 序号都从它推） | 协议 | LockKeeperApp×5, HomeConsole×2 | 低 |
| core-route-02 | `tabIndex`/`legacyHostIndex`（越界返 -1 不崩溃，调用方靠"拿不到就不记账"兜脏值） | 计算 | 本文件 | 低 |
| core-route-03 | 377 访客受限 `guestBlocked/guestBlockedTabs`（由前者派生，不再手写 `[1,3]` 这份**同一个量的双实现**）+ 294 `deepLinkHosts` | 协议 | 本文件 | 低 |

## 33. Core/ScreenCare.swift（89 行）

374 录屏遮罩 + 336 截图警示。边界写清：只能知道"系统正在采集"，不知道被谁采集、采集到哪；越狱/私有钩子不可防。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-screen-01 | 录屏遮罩 `ScreenCaptureWatch.start/refresh`（`UIScreen.isCaptured` + 采集变更通知；取"正在采集的那块屏"走 key window 所在 scene，**不猜 main 也不猜数组顺序**） | 状态 | LockKeeperApp | 低 |
| core-screen-02 | 336 截图话术 `notice`（"可能已进那张图片"而非"已拍到" —— 只知道发生过一次截图，不知道拍的是不是这屏） | 格式化 | 本文件 | 低 |
| core-screen-03 | 长任务常亮 `ScreenAwakeWhile`（条件为真置常亮，页面消失即恢复；刻意不留全局开关）+ `keepingScreenAwake` 修饰入口 | 组件 | 本文件 body | **高**（修饰入口零调用：注释点名的 FirmwareView / StartAddFpView 都没接） |

## 34. Core/SeasonIcon.swift（69 行）

897 四季图标：按图标自己的底色对到四季，可选"回前台时对齐当季"。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-season-01 | 月份→图标 `name`（气象季 3-5 春 / 6-8 夏 / 9-11 秋 / 12-2 冬；不用节气 —— 这里要的只是"三个月换一次"这种可预期的东西） | 计算 | Store, RecordSearch, ExportCenter | 低 |
| core-season-02 | 自动档 `setAuto`（**默认关**：桌面图标是用户首屏，后台悄悄换属越界；关掉后行为与旧版一致）+ `seasonName` | 配置 | HolidayFeed（同名不同义） | 低 |
| core-season-03 | 回前台对齐 `syncIfNeeded`（只认原有四款；用户选了新增五款 → 尊重选择只记号不动手，也不给新五款再造"春季标准色"） | 编排 | LockKeeperApp | 低 |

## 35. Core/SecretStore.swift（61 行）

2026-10-14 对抗式查漏：密钥材料此前与普通偏好一起明文落盘 —— 越狱或一份 iTunes 备份就能把整库门锁密钥读走（REVERSE_REPORT §8：skey 泄露 = 可离线构造任意开锁帧）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-secret-01 | Keychain 最小封装 `set/get/remove/removeAll`（按账户存一个字符串，不动 Keychain 模型与所有 `kc.skey` 调用点，对上层完全透明） | 存储 | Store×19, SecurityCenterView×23, AuditChain | 低 |
| core-secret-02 | 访问级别 AfterFirstUnlockThisDeviceOnly（覆盖锁屏后台任务 428 充电备份；不随 iCloud/iTunes 迁出 —— 跨机迁移走 App 自己的加密备份） | 安全 | 本文件 | 低 |
| core-secret-03 | 核弹销毁 `removeAll`（UserDefaults 的 keys() 全表清**碰不到**系统 Keychain，这是必须单独做一处的原因） | 存储 | RecordSearch×5, Store×5, AuditChain×3 | 低 |

## 36. Core/SettingsGroups.swift（53 行）★

乱源治理第 4 批：设置页 17 个 Section / 约 37 个一级入口平铺在一屏，找一个开关要划过整页。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-setgrp-01 | 设置页五组分区 `SettingsGroup`（开门日常 / 凭证与成员 / 数据与安全 / 外观与辅助 / 帮助与关于）+ 节显隐 `settingsSectionShown` | 配置 | — | **高**（整文件外部零引用：筛选片只做了"能不能关"，没接线） |
| core-setgrp-02 | 归属判据按"用户此刻想干的事"而非代码实现归属（安全/工具/固件/备份统一归"数据与安全"） | 设计约束 | — | 低 |
| core-setgrp-03 | 硬约束：不改任何 section 内部、不挪任何入口、不新建页面；`nil` 档必须与加这一批之前逐字一致，且与页内搜索互不影响 | 设计约束 | — | 低 |

## 37. Core/SpeechKit.swift（9 行）★

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-speech-01 | 全站唯一本地朗读出口（810 逐卡朗读 / 309 密码逐位 / Siri 读最近记录）—— 文件只有 `import AVFoundation`，**`Speech.digits` 类型并不存在**，而 `CredentialStudio:13-14` 还引用着它 | 组件 | — | **高** |
| core-speech-02 | 设计要求："停掉上一句"必须只有一个实例才做得到 —— 两份各自 new 的 synthesizer 会同时说话，各做一半就是两份真相源 | 设计约束 | — | 低 |
| core-speech-03 | 离线口径：全程走系统本地语音，不联网、不采集、不录音 | 设计约束 | — | 低 |


## 38. Core/StatsKit.swift（1,088 行）★ 冗余重灾区

包10 统计与图表 —— 纯本地聚合层（Swift Charts 数据源）。只读既有台账，不新增采集，推不出的不猜。明细见文末专题 D。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-stats-01 | 时间基元 `dateOf`（`lockTime==0` 是"无时钟"占位，必须绕开 —— 否则换算后落在 2010 纪元，其小时必然 <6，会凭空点亮夜猫子徽章）/ `dayKey` / `startOfDay` | 计算 | RecordSearch×15, ExportCenter×16, Milestones×10 | 低 |
| core-stats-02 | 时间轴辅助 `weekdayIndex/isWorkday/secondsOfDay/earliestDate/coverageDays` + 窗口切片 `logsInWindow`（本文件 16 处复用，唯一窗口口径） | 计算 | 仅本文件内 | 中 |
| core-stats-03 | 646 小时桶折叠 `hourBuckets`+`HourBucket`（窗口 ≥90 天才折；保留该桶**最近一条真日志** ⇒ 点按跳转不因折叠而丢） | 统计 | StatsPage | 低 |
| core-stats-04 | 图表数据点八型：`DailyPoint/MovingPoint/GapBand/AlarmScatterPoint/WeekdayStat/FirstOpenSample/MonthPair/AlertStat` | 统计 | StatsPage（经 StatModel） | 低 |
| core-stats-05 | 凭证维度四型：`TempGantt`（含 `ticks` 真实开门时刻 + 629 核销率）/ `OtpPoint` / `PwdUse`（`approxUses` 必须带"约"）/ `MemberBubble` | 统计 | 本文件 | 低 |
| core-stats-06 | `StatModel` 统计模型（各分区只读计算属性；总量只从 `logsInWindow` 出，视图不许再 `reduce` 第二个定义） | 统计 | StatsPage×11 | 低 |
| core-stats-07 | 窗口常量唯一读点 `weekWindowDays/memberBarDays/longWindowDays/recentBarDays/alarmScatterDays`（"近 N 天"文案与查询参数同一个出处） | 配置 | 本文件 | 低 |
| core-stats-08 | 622 降级护栏 `isDegraded`（覆盖 <7 天或开门 <5 条不渲染空坐标轴，显示"积累 X 天后可用"）+ 646 `isHourFolded` | 计算 | 本文件 | 低 |
| core-stats-09 | 617/618 逐日条 `rangeRows` + 首次开门区间 `firstOpenHourSpread`（`minHour` = 当日最早开门小时，**不是"离家时刻"**） | 统计 | 本文件 | 低 |
| core-stats-10 | 602 作息四轴 `dayparts`（边界必须显示出来，否则同一张图两人读成两种）+ 假日段 `HolidayDay/HolidayHour/holidayTailDays` | 统计 | 本文件 | 低 |
| core-stats-11 | 780 工作日首开 `workdayFirstOpens/workdayFirstOpenMedian`（**中位数而非平均值**：23:50 与 01:00 的算术平均是 12:40，那一刻根本没人开过门） | 统计 | 本文件 | 低 |
| core-stats-12 | 615 帕累托 `pareto/paretoCover`（折 4 **类**凭证而非逐条；"前几类"= 累计首次够到 80% 的那一类算进去）+ 601 `monthPair` / 641 `weekDelta` / 613 `alertStats` / 605 `alarmScatter` | 统计 | 本文件 | 低 |
| core-stats-13 | 799 成员周小结 `weekSummary` + 698 上周小结 `lastWeekDigest`（自然周 CSV + 三句话摘要；两者差别是"滚动 N 天"vs"上一个完整自然周"） | 统计 | — | **高** |
| core-stats-14 | 624/604/955 成员族 `memberBubbles/memberDaily/memberTodayCount`（y = 距最近开门天数要扫**全量缓存**，否则闲置三个月的人会被算成窗口内活跃） | 统计 | — | **高** |
| core-stats-15 | 612/625 归属计数 `memberCounts/todayMemberCounts`（一次归因给出全部人，避免逐人重跑 Attribution）+ `kindOwnerBreakdown` | 统计 | HomeConsole | 中 |
| core-stats-16 | 800 在家时长代理四件（协议无门磁/上锁态，只能以开门事件包围近似）+ 1020 黄金时段 + 626 `pwdUses` + 628 `outOfRangeTotal` + 格式化四件与词表 | 统计/格式化 | Components, MembersPage×7, FpOwnerPicker×2, FeedPage×3 | **高**（在家时长四件零调用） |

## 39. Core/StatusCheckNotice.swift（73 行）

963 每晚状态确认提醒（本地通知，全离线）。与 1031 夜间免扰的冲突是**结构性的**，不假装相容。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-scn-01 | 夜间提醒 `sync`（时点只认三档，别的值回落 22:00 —— 键被老版本或导入写成垃圾时不能排出一条怪时间的通知） | 通知 | LockKeeperApp, BackupStudioKit | 低 |
| core-scn-02 | 1031 免扰裁决 `insideQuiet`（开着免扰且时点落在免扰段内 → **根本不排**这条，而不是排了再静默） | 计算 | 仅本文件内 | 中 |
| core-scn-03 | 正文 `bodyText`（只用台账数得出的数：锁数 + 今天真正连上过几把；写明"读数是本机缓存" —— 这条通知不联网不连锁）；授权 `requestAuthAndSync`（沿用 CareSchedule 那一份，同一个系统弹窗不该请求两次） | 格式化 | 仅本文件内, LockKeeperApp | 中 |

## 40. Core/StatusParser.swift（196 行）

03 状态 / 16 日志解析（JS utils/status.js 移植，golden.parse.* 差分）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-sp-01 | 03 状态解析 `parseStatus` → `LockStatus`（KLV 01 密钥态 / 03 rc / 04 锁钟 / 05 周期 / 06 键盘冻结 / 07 试错计数 / 08 安全级 / 11 电量 / 14 音量 / 21..29 容量族 / 31..35 版本族） | 解析 | LockService×2, Tests | 低 |
| core-sp-02 | 16 日志解析 `parseLogs`/`parseLogEntry` → `[LogEntry]`（KLV#05 = type/len/idxRaw/lockTime） | 解析 | LockService, Tests | 低 |
| core-sp-03 | 强校验 `truncatedLogCount`（声明长度与实际不符的条数，对齐 vendor status.js 的 `invalid`） | 校验 | LockService | 低 |
| core-sp-04 | rc 文案 `rcMessage`(12 处)/`rcFriendly`/`rcHint` + rc→锁态 `lockStateText`（**唯一实现**：此前两页逐字重复 9 行 switch） | 格式化 | LockService×12, HardwareService×4, LockProfilePage×4, LocksPage×4 | 低 |
| core-sp-05 | `intHex`/`leHexToU32` 数值解析件 | 解析 | HardwareService×4, LockService×2 | 低 |

## 41. Core/Store.swift（1,040 行）

本地存储与数据模型（JS utils/store.js + services/{ledger,snapshot,keychain,gateway,members}.js 移植）；键与小程序完全一致（`kf_*`）便于全量备份跨端互换。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-store-01 | 泛型读写 `get/getDict/getString/getBool/getInt/set/setCodable`（两种参数序并存以兼容 87 处既有写法） | 存储 | 全仓 1,419 处引用 | 低 |
| core-store-02 | 原字节与键族 `remove/has/keys/rawText/rawData/setRawData/matchingKeys`（421 回滚快照要**字节不变** —— 重新编码会改写键序与可选字段） | 存储 | LockKeeperApp×16, BackupStudioKit, AuditChain | 低 |
| core-store-03 | 失败台账 `recordFailure/failureLines`（只存"键←原因"不存值；**刻意不提供清空口** —— 否则就是"抹掉证据但不告诉用户"） | 存储 | 仅本文件内 | 中 |
| core-store-04 | 密钥台账 `Keychain` 结构（skey/bkey/ekey/pins/trackId…）+ `keychains/keychain/normalizeMac` | 存储 | LockStats×12, LocksPage×8, BackupStudioKit×15, MePage×10 | 低 |
| core-store-05 | 凭证台账 `LedgerPwd/LedgerFp/Ledger` + `batchU32` 符号与上界护栏（导入链不校验符号，`UInt32(-1)` 在 Swift 会直接 trap） | 存储 | CredentialOrg×37, CredentialStudio×5, Attribution×2 | 低 |
| core-store-06 | 成员/摇一摇/网关/快照/缓存模型 `Member`、`Dongle(Stat)`、`Gateway`、`StatusSnapshot(Data)`、`LogCache/CachedLog`、`DefendCfg/TailgateCfg/OtpStatus/OtpIdx` | 存储 | MemberCenterView×18, DonglesPage×9, GatewayPage×6, BackupKit | 低 |
| core-store-07 | `DB` 命名空间（65 个外部文件、1,419 处引用 —— 本层最大扇入点） | 存储 | 全仓 | 低 |
| core-store-08 | MAC 字节序注册表 `macOrder/setMacOrder/hydrateMacOrders`（协议层不读库；补不上时进程重启后首帧回 rc=12，由 exec 顺序自愈再学一次，代价是多一个来回而不会写错锁） | 状态 | LockService×4, ZKProtocol×2, LockKeeperApp | 低 |
| core-store-09 | 密钥落盘 `saveKeychain/removeKeychain/removeDevice` + 一次性迁移 `migrateSecretsToKeychain`（幂等，把旧明文抹掉） | 存储 | BackupStudioKit, LockService, LocksPage, LockKeeperApp | 低 |
| core-store-10 | 软砖后路 `savePendingPair/pendingPair/clearPendingPair`（05 换钥后本机没落盘 = 最接近变砖的状态；`removeKeychain` **刻意不动**这份记录） | 存储 | LockService | 低 |
| core-store-11 | 子页默认锁 `preferredMac`（此前各处 `keychains().first` 会让子页默认绑到最旧那把锁）+ 台账损坏标记内件（防"解不出→空表写回"清空数据） | 计算 | BatteryCare, MemberCenterView | 中 |
| core-store-12 | 台账读写 `ledger/saveLedger` + `listPwds/listFps/addPwd/delPwd/setPwdPeriod/setPwdNote/setPwdOwner/addFp/delFp/renameFp/setFpNote/setFpOwner/getPwd/getFp` | 存储 | CredentialOrg×22, StatsKit×9, MemberCenterView×8, KeysPage | 低 |
| core-store-13 | 四个无调用读写口 `rePwd`(改值) / `setFpAlarm` / `getPwdList` / `getFpList` | 存储 | — | **高** |
| core-store-14 | 379/380 台账 diff `ledgerDiff`（口令只记指纹前 4 位，明文不落审计链）+ `fromDict/toDict` 备份互通转换 | 计算 | AuditChain | 中 |
| core-store-15 | 状态与日志缓存 `writeStatus/readStatus/statusTime/writeLogs/readLogs/replaceLogs`（`writeLogs` 是"新+旧按 idxRaw 去重合并"，`replaceLogs` 才是归档用的替换语义）+ 写入闸 `cacheWritable` | 存储 | LockService, StatsKit×8, CredentialOrg×8, DiagKit | 低 |
| core-store-16 | 锁端运行参数读写、成员增删改+`memberPalette` 六色板、摇一摇/网关增删改、应用锁口令（PBKDF2 60,000 轮 + 双摘要兼容旧包）、92 开锁失败标记 `FailEvent` | 存储/安全 | BackupKit×4, BackupCanonical×2, BackupStudioKit×22, LockCommand×3, ManagerFace×25, MembersPage×12, MemberCenterView×19, DonglesPage×6, GatewayPage×8, HardwareService×7, MePage×3, LockKeeperApp×5, LockGuard, BackupStudio, RecordSearch, EventsPage | 低 |

## 42. Core/Theme.swift（970 行）

Black Canvas / Glass Instrument 令牌层 —— 唯一色/空/圆角/动效事实来源（**全仓扇入最高：3,388 处**）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-theme-01 | `XPalette` 语义色板：canvas 纯黑（**黑色是画布，不是背景色**）/ surface #1C1C1E / hairline 白 8% / text / specular / qrQuietZone（唯一不跟随主题的白，ISO 18004 要求静区） | 令牌 | MemberCenterView×132, BackupStudio×126, Components×123, SecurityCenterView×117 | 低 |
| core-theme-02 | 强调与状态色 `accent/accentText`（文字档要过 4.5:1，填充只要 3.0）/ `onAccent` / `ok/warn/danger`（暖色只取参考图实测的 4 个值） | 令牌 | 视图层 | 低 |
| core-theme-03 | 凭证类色 `kindFp` 青 / `kindTemp` 金 / `kindOtp` 紫（不借 warn 的橙：同一个颜色两个含义是 HIG 点名要避免的） | 令牌 | 视图层 | 低 |
| core-theme-04 | `XSpace` 间距（页边距 gutter 22 / 卡内 16 / 行距 8 / 区块 28 / 标题到首卡 74 / **对齐线 29**）+ `xsm` 6 | 令牌 | SecurityCenterView×63, BackupStudio×62, MemberCenterView×60 | 低 |
| core-theme-05 | `XRadius` 圆角（卡片 26 / 主视觉 34 / 控件 12 / 瓦片 14 / 胶囊 18 / 设备 44）+ `XHit.min` 44pt 触达 | 令牌 | Components×21, AddLockPage×5, ExportCenter×26 | 低 |
| core-theme-06 | `DSRing` 环几何（线宽=直径 12% 且**不低于 30pt** / 内盘深海军蓝不是纯黑 / 游标 18pt / 分段竖条色） | 令牌 | HomeConsole×7, FirmwarePage×2 | 低 |
| core-theme-07 | `XIcon` 七档（12/13/17/20/22/28/34）+ `XOpacity` 七档（wash/badge/glow/edge/track/glassFill 0.08/glassEdge 0.12） | 令牌 | SecurityCenterView×17, Components×19, AddLockPage×3 | 低 |
| core-theme-08 | `XMetric` 度量：`dataText`（数据文字随 AX 放大）/ `digitCount` / `overflowScale` / `grouped` 千分位 / `display`（>11 位缩写）/ `decorIcon` | 计算 | Components×21, AddLockPage×5, MePage×3, MemberCenterView×9 | 低 |
| core-theme-09 | `XMotion` 三档（calm/standard/lively，**单调曲线零过冲** —— 过冲在 3D 翻转里会露出镜像背面）+ 十条曲线 + 卡入场逐卡 40ms 延迟 | 动画 | Components×12, LockKeeperApp×12, HomeConsole×11, SecurityCenterView×7 | 低 |
| core-theme-10 | `XHaptics` success/warning/failure（`prepare` 零调用）+ `XGradient` hero/dial/dialOK/chip + `glow`(0.35) 与 `ambient`(0.12–0.20) 两个**不同的量** | 组件 | LocksPage×9, EventsPage×8, HomeConsole×7, Components×4 | 中 |
| core-theme-11 | `XAppearance` 外观三件（高对比并联 / `memberSwatch` 色串解析 / `adaptive`）+ `XText` 12 档字阶与 `unitStyle` + `DSFont` + `abbreviate` 万级缩写 | 令牌 | AccessibilityKit, Components×8, CredentialStudio, DeviceHomeView, FirmwarePage, FpOwnerPicker, MembersPage×7 | 中（`abbreviate` 仅本文件内） |

## 43. Core/TimeFormat.swift（125 行）

647/651 时间显示的两个口径 + 一条真边界：**页面不许自己拼 DateFormatter**（否则同一条记录在时间线、详情卡、导出 CSV 里显示成三个样子）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-tf-01 | 651 `shortClock`：把源串里**已存在**的 HH:mm(:ss) 段按设置改写；识别不出原样返回，且**不做时区换算**（源串是与锁端键盘对得上的墙上时钟） | 格式化 | AlarmsPage, EventsPage, KeysPage | 低 |
| core-tf-02 | `clock` 时钟口径（环形/卡片共用） | 格式化 | MemberCenterView×3, QuickPool×2, CareViews×2 | 低 |
| core-tf-03 | 665 区间精简 `range`（同年省年份、同月省月份、跨年才补全；**按数字比较**而非找"月"字，否则补零写法一变就悄悄失效） | 格式化 | ExportCenter×60, RecordSearch×14, ZKProtocol×4 | 低 |
| core-tf-04 | `daysSince` 天数差 + `dayEnd` 今晚 23:59（**唯一出口**：此前两个表单各抄一份且都写错）；三枚设置键 `styleKey`(跟随/24/12) / `secsKey`(到秒；**没有秒位的行不补零**，补了就是谎称精确到秒) / `twoLineKey`(双行日期默认关：行内多一行是整页密度的变化) + `hour24` | 计算 | CareViews×5, BackupStudioKit×3, CredentialStudio, 本文件 | 低 |

## 44. Core/WeekCal.swift（82 行）

912 周起始日偏好 —— 一个共享的"按偏好配好的 Calendar"（此前周界算法散在四处，会出现"月历从周一排、'本周'却按周日起算"）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-week-01 | 公历化日历 `gregorian`（只钉 identifier=公历，时区/Locale/周首日/年初最小天数全照抄系统 —— 否则 iOS 选佛历会取回 2569 年，而本仓所有日期串都是公历的） | 计算 | StatsKit×18, Milestones×11, DiagKit×8, RecordSearch×8 | 低 |
| core-week-02 | 周偏好 `key`/`calendar`（三档 mon/sun/sat，并把 `minimumDaysInFirstWeek` 一并钉死为 4，否则跨年那一周周号错位） | 计算 | 同上 | 低 |
| core-week-03 | `shifted` 加减**日历日**的唯一出口（`±86400` 在夏令时地区会落到前天 23:00；真算"时长"的调用点不该用这里）；中文名 `name` / `effectiveName`（"" 档下把"跟随系统"翻译成看得见的哪天；直接按 firstWeekday 取，避免屏幕上出现"跟随系统（当前为 跟随系统）"） | 计算 | DiagKit×3, RecordSearch×2, CredentialOrg, Store, RecordSearch, ExportCenter | 低 |

## 45. Core/ZKCmdBuilder.swift（286 行）

ZK 命令构造器 —— JS utils/kernel/cmds.js 逐行移植。密文面统一模式 `body → EKey(cmd,mac) → AES-ECB(skey) → KLV#xx`，40 个命令有完整帧 hex 的 golden 差分。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-cmdb-01 | 命令结构 `ZKCmd` + 无符号协议秒收口 `protoSecU32`（早于 2010 的输入不许回绕成未来时间） | 协议 | LockService×31, HardwareService×11 | 低 |
| core-cmdb-02 | 会话与探测：`cmd01Session` / `cmd23ExKeyWay` / `cmd12Echo` / `cmd03StatusPlain` / `cmd03StatusWrap` | 协议 | LockService×5 | 低 |
| core-cmdb-03 | 换钥与开锁：`cmd05Exchange`（`order` 只有配网期字节序只读探针会显式传）/ `cmd04Open` / `buildEkeyOpen` / `buildEkeyShare` | 协议 | LockService×5, AndroidPair, HardwareService×2 | 低 |
| core-cmdb-04 | 密钥族：`cmd08SyncPinsBatch` / `cmd21SetBkey` / `cmd41WriteEkey` / `cmd44GetEkeyInfo` / `cmd43KeychainStatus` | 协议 | LockService, HardwareService×3 | 低 |
| core-cmdb-05 | 密码族 `cmd0ASyncPwd`(4 处) / `cmd0BSyncPwdExpire`(2 处) + 指纹族 `cmd13AddFp`/`cmd14FpConfirm`/`cmd15DeleteFp` | 协议 | LockService×9 | 低 |
| core-cmdb-06 | 运行参数：`cmd0ESyncTime` / `cmd18Volume` / `cmd19OpenZotp` / `cmd20ValidationMode` / `cmd24AutoLock` / `cmd25Defence` | 协议 | LockService×6 | 低 |
| core-cmdb-07 | 日志与升级：`cmd16GetLog` / `cmd22EnableDfu` | 协议 | LockService | 低 |
| core-cmdb-08 | 网关族 `cmd38GWStatus`/`cmd31GWSetWifi`/`cmd32GWSetIot`/`cmd35GWReboot`/`cmd30GWDeviceName` + 协议秒解析 `protoSecOrNil/protoSecRawOrNil/protoSec` + PIN 转换 `pinToLEOrNil` + 载荷告警 `suppliedButUnparsed`（传了却没解析，静默忽略等于撒谎） | 协议/解析 | HardwareService, 仅本文件内 | 中 |

## 46. Core/ZKProtocol.swift（299 行）

ZK 0x87 帧协议层 —— JS utils/kernel/protocol.js 逐行移植（**全仓 213 处引用，BLE 链地基**）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-proto-01 | 协议时间换算 `protoSecondsFromMs/protoSecondsToMs/protoSecondsToUnix/nowProtoSeconds`（epoch 2010-01-01；`protoSecondsToUnix` 是 Swift 侧便利出口，JS 那边就地写） | 计算 | ZKCmdBuilder×9, LockService×3, Attribution, CredentialOrg×7 | 低 |
| core-proto-02 | KLV 构造 `buildKLV`（22 处）+ 解析 `parseKLV` | 协议 | ZKCmdBuilder | 低 |
| core-proto-03 | 帧构造 `buildFrame`（8B/10B/7B 三种头）+ 成帧收口 `wrapFrame`（skey 非 16B 时**整帧返回空串**；旧写法会包出"含空值 KLV 的完整帧"，于是 `hex.isEmpty` 永不成立） | 协议 | ZKCmdBuilder×30 | 低 |
| core-proto-04 | MAC 字节序 `MacOrder` + `setMacOrder/macOrder/flipped/targetMac`（显示序 vs 线上序**逐字节相反**；内存注册表由 `DB.hydrateMacOrders` 在启动窗口补） | 协议 | LockService×8, Store×3, ZKCmdBuilder×4 | 低 |
| core-proto-05 | 0x88 EKey 包络 `buildEkey` + 只读断言 `assertReadOnly` + 会话令牌注入 `injectToken`（KLV#0xEE） | 协议 | ZKCmdBuilder×3, LockService×2 | 低 |
| core-proto-06 | 响应解析 `ParsedFrame.parseResponse` + `ZKLV` 结构 | 解析 | LockService×14, HardwareService×6, BLEService×3 | 低 |
| core-proto-07 | 粘包重组 `FrameAssembler.push`（与 JS makeAssembler 逐行一致） | 协议 | BLEService | 低 |
| core-proto-08 | 广播解析 `AdvData/parseAdv/lockMac`（厂商段是线上序，`lockMac` 逐字节翻成显示序；错误解读就是 2026-10-17 那次 rc=12 + 幽灵台账）+ `ProtoTime.localStr` 协议时刻本地化 | 解析 | LinkSenseKit×3, HardwareService×3, AddLockPage×2, RecordSearch×3, StatusParser, DeviceHomeView | 低 |

## 47. Core/ZOTP.swift（55 行）

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-zotp-01 | ZOTP 生成 `generate`：AES-ECB(skey,ZeroPadding)(时间计数器 + MAC反序 + idx + "00000000") → 取前 24hex，每 4hex 块 `(b1^b2)%10` 拼 6 位 | 密码学 | RealityAPIProbe×2, BladeMesh, Tests | 低 |
| core-zotp-02 | 窗口计数（`periodSec` 沿用 JS 命名，真实单位是**分钟**：t=30 ⇒ 30 分钟窗口；前提是锁钟已同步 0E） | 计算 | 本文件 | 低 |
| core-zotp-03 | `reversePairHex/le2be2` 字节序辅助 + `nextWindow` 下一窗口预告（零调用） | 解析 | 仅内部 | 中 |

## 48. Services/Attribution.swift（81 行）

归属推断（JS services/attribution.js 移植）—— 「谁开的门」只在可证明时给出，绝不猜测。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-attr-01 | R1 一次性密码窗口：事件时刻落在某条给成员发的临时码 [from,to] 内且**唯一命中** → 归属 | 计算 | StatsKit×11, MemberHub×4, RecordSearch, ExportCenter×2 | 低 |
| core-attr-02 | R2 锁内唯一凭证 + 实时背书：本次会话 03 显示该型凭证只剩 1 个且事件够新（≤3 天） | 计算 | 同上 | 低 |
| core-attr-03 | 结果行 `Row`（推不出的不出行；推断值一律由调用方标"约"） | 状态 | MemberCenterView×4, StatsKit | 低 |

## 49. Services/BackupCanonical.swift（294 行）

备份包规范化序列化 —— 与 JS storage.js canonicalBundle/checksum **逐字节**互通。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-canon-01 | `JValue` 有序 JSON 值树 + `escape`（控制符 \uXXXX、非 ASCII 原样 —— 复刻 JSON.stringify 紧凑语义） | 序列化 | 本文件 27 处 | 低 |
| core-canon-02 | `canonical` 固定键序：devices 按 mac 排序、members 按 id 排序、globals 键排序并剔 null | 序列化 | BackupStudio×2, BackupStudioKit | 低 |
| core-canon-03 | `fnv1a32Hex` 校验和（**必须复现** JS 侧按 UTF-16 码元喂 `charCodeAt(i) & 0xff` 的非教科书实现 —— 中文/emoji 与 UTF-8 字节流不同） | 密码学 | BackupStudioKit×4 | 低 |
| core-canon-04 | 旧语义 `fnv1a32HexLegacy`（只留给导入侧认旧包；直接换掉会把用户已有备份判成篡改）；`exportText` 导出文本 + 各区取值 `kcValue/ledgerValue/metaValue/dongleValue/gatewayValue/memberValue` + `put/putB/stringify` | 密码学 | BackupStudioKit, BackupPage×8, BackupStudioKit×7（后六件仅内部） | 低 |

## 50. Services/BackupKit.swift（490 行）

备份加密信封 + WebDAV 同步（JS utils/cloudcrypto.js + services/cloudsync.js 移植；与小程序端信封完全互通）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-bkit-01 | `CryptoBox` 信封：PBKDF2-HMAC-SHA256(60000) → AES-128-CBC + HMAC-SHA256（encrypt-then-MAC） | 密码学 | BackupStudioKit×6, CredentialOrg, Store, ExportCenter | 低 |
| core-bkit-02 | kdf 参数钳制 `iterMin`（iter 来自**不可信信封**且在校验之前就用于派生密钥，超大值等于远端可触发的 DoS） | 安全 | 本文件 | 低 |
| core-bkit-03 | 加密 `encryptText` / `encryptBytes`（691 二进制信封与文本**同一套 KDF/AES/HMAC 与同一信封结构** —— 不新造第二套算法） | 密码学 | BackupStudioKit×5, CredentialOrg, ExportCenter | 低 |
| core-bkit-04 | 解密 `decryptEnvelope` + 内部件 `hmacSha256/deriveKey/aesCbcEncrypt/aesCbcDecrypt/concat/isHex`（严格十六进制校验） | 密码学 | BackupStudioKit（其余仅内部） | 低 |
| core-bkit-05 | 包结构 `BackupBundle`（`currentSchema=5`，导入时**拒绝更高版本**，防字段被误读且无告警） | 序列化 | BackupStudioKit×17, BackupCanonical×3, BackupPage×3 | 低 |
| core-bkit-06 | 包内分区 `Device/Meta/Globals`：otpKeys 必须走**白名单核验**（否则恶意包体能借它写任意偏好键）+ typed `Appearance/DeviceOrg/PasscodeRec/TraceRec`（用自由字典就等于把"任意键写入"重新开放给可伪造 JSON） | 序列化 | BackupStudioKit, BackupCanonical | 低 |
| core-bkit-07 | 收集 `collectAll` + `collectAppearance/enumVal/collectDeviceOrg`（只收枚举过的档位值，读到没见过的就当没这项，免得把脏数据搬过去） | 编排 | BackupStudioKit×2, BackupPage | 低 |
| core-bkit-08 | 894/D-36 落地 `applyGlobalsAppearanceAndOrg`（overwrite/merge 唯一实现；每字段独立判定，不合格就跳过，**绝不整包接受**）+ `applyAppearance`；全量恢复 `restoreAll` | 编排 | BackupStudioKit×2, LockKeeperApp×10, BackupStudioKit, BackupPage | 低 |


## 51. Services/BackupStudioKit.swift（1,434 行）★ 冗余重灾区

包8 备份工作室服务层 —— 备份·恢复·换机迁移（覆盖 idea 181/193/197/198/237/407-413/417-450/453/507-512/1018/1048）。纪律：备份文件只去用户自配 WebDAV，**口令不出本机内存**。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-bs-01 | 工作室命名空间 `BackupStudio`（备份/恢复全链；7 个外部文件、112 处外部引用） | 编排 | BackupStudio×81, BackupPage×6, LockKeeperApp×5 | 低 |
| core-bs-02 | 421 回滚目录 `rollbackDir`（放 Application Support 而非 Documents —— 后者会让整库 skey 明文进 iTunes/iCloud 备份） | 安全 | 本文件 | 低 |
| core-bs-03 | 409 自描述文件名 `fileName`（锁管家_主锁名_日期时分_全量.enc；194 自动命名，410 分卷尾部加 _卷N，用户不用自己起名） | 格式化 | ExportCenter×28, DFUKit×3 | 低 |
| core-bs-04 | 198 备份节奏 `cadence` + 排期提醒 `scheduleCadenceReminder/scheduleMonthlyBackup`（落地为本地通知，**不做后台静默写**） | 通知 | LockKeeperApp, BackupStudio | 低 |
| core-bs-05 | 429/509 新鲜度 `lastExportMs/daysSinceLastExport/daysSinceLastImport/markImported` + 「上次备份」**唯一文案** `lastBackupText`（此前备份页与工作室两份措辞与数据源都不同） | 计算 | BackupStudio×8 | 低 |
| core-bs-06 | 421/445 回滚快照 `RollbackBundle` + `makeRollbackPoint/undoLastRestore/restoreRollbackSnapshot/pruneRollback` + `rollbackFamilies`（这些键族按 mac+alias 或成员 id 挂钩，覆盖恢复会绕过它们） | 编排 | BackupPage, BackupStudio×2 | 中 |
| core-bs-07 | 428 充电备份 `rescheduleChargeBackup/chargeBackupNote`（排期失败要记维护回执，不能 `try?` 吞掉却称"已交给系统"）+ 407 导出前体检 `HealthCheck/preExportHealth/expiredTemporaryCount/cleanExpired` | 编排 | BackupStudio | 低 |
| core-bs-08 | 407/181/427 组包 `zoneCounts/otpIncluded/bundleFor/prune`（未勾分区在包内置空，恢复端按 nil 语义跳过）+ 410 分卷 `Volume/volumes`（**按文件数取舍会把一套卷切成半套** —— 基础卷没了，剩下的记录卷恢复不出任何东西） | 序列化 | BackupStudio×3 | 低 |
| core-bs-09 | 408/409/411 导出 `exportText/writeLocal/qrImage/credentialQRPayload`（后者旧实现返回**明文 canonical 含 skey/ekey**，同屏文案却写"口令另行线下交接" —— 已修） | 序列化 | BackupPage×8, ExportCenter×3, ShareToAndroidView×2 | 低 |
| core-bs-10 | 419 冲突裁决 `MergeStrategy/Conflict/conflicts` + `DiffRow/compare/tally` + 425/440 逐锁对账 `LockDiff/lockDiffRows` + 193 体积 `estimateBytes/sizeText` | 编排 | BackupStudio×16, FirmwarePage×2 | 低 |
| core-bs-11 | 453 校验状态 `ChecksumState/checksumState`（**absent 与 mismatch 必须分开**）+ 422/423 `verifyChecksum` + 434 `shortHash` | 校验 | 仅本文件内 | **高**（校验两件零调用：预演走的是 `parsePreview` 里的另一份判据） |
| core-bs-12 | 195/417/449/450 恢复预演 `Preview/preview/parsePreview`（魔数先行 → 口令层 PBKDF2 只跑一遍 → schema 升级 → 抽 5 条；哈希层在**写库之前**就拦下） | 编排 | BackupStudio×9, ExportCenter×7, MemberCenterView×5 | 低 |
| core-bs-13 | 424 升级链 `UpgradeStep/upgradeSteps/upgradeChain`（v1→v5 逐级、每级幂等）+ 1048 `stripCommentHeader/needsPassword`（"这份备份要不要口令"的唯一入口）+ 420/453 解密兜底 `looksEncrypted/decryptAny` | 编排 | BackupStudio, BackupPage | 中 |
| core-bs-14 | 恢复 `restore`（策略 + 冲突采纳）+ 438 三通道 `Channel`（备份文件 / 扫码 / WebDAV） | 编排 | CredentialOrg×5, CredentialBinView×2, BackupStudio | 低 |
| core-bs-15 | 445 中断续迁：会话 `MigSession/loadMigSession/clearMigSession/pendingMigration` + **真事务表** `MigTxn/loadMigTxn/saveMigTxn/noteMigTxnDone/pendingMigrationTxn`（中断判定认事务表不认百分比；快照被清掉的事务表不可回滚） | 编排 | LockKeeperApp（其余仅内部） | 中 |
| core-bs-16 | 442 首验清单 + 446 退役横幅 + 448/397 库体指纹（只比不改）+ 397 启动自检 + 507 备份角标 + 备份事件 + 430 本机文件族 + 440 增量补传 + 1219 `algoNote` + 433 密码提示 + 通知代理 `UNDelegate`/`onMonthlyTap` | 校验/编排 | BackupStudio×3, DiagKit, Milestones, LockKeeperApp, LinkSenseKit×16 | **高**（`CompletionOnce`/`Handover` 两类型零引用） |

## 52. Services/BLEService.swift（583 行）

BLE 服务 —— CoreBluetooth 实现（JS services/ble.js 的 iOS 等价）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-ble-01 | UUID 常量 `BLEUUID`（NUS 6E400001 / 网关 FE90）+ 错误码 `BLEError`（1001/1006/1007/2003/5001/6001/6004/6005）+ `BLEErrorX` 包装 | 协议 | DFUKit×10, LockService×42, HardwareService×17 | 低 |
| core-ble-02 | 123 扫描三档 `ScanProfile`（**只作用于发现型扫描**，不改连接与 AUTOOPEN 时序 —— 免得一个"省电"档把靠近判定的窗口一起收窄；只有极速档开重复广播） | 配置 | DiagKit, LinkSenseKit | 低 |
| core-ble-03 | 扫描 `startScan/stopScan/allDiscovered`（10s 自动停扫；已发现设备快照供 MAC 解析） | 编排 | LinkSenseKit×5, HardwareService×3, DFUKit | 低 |
| core-ble-04 | 连接 `connect/disconnect`（20s 超时；发现服务→特征→开 notify；MTU 由系统协商） | 编排 | LockService×6, DFUKit×3, HardwareService×3 | 低 |
| core-ble-05 | `readLinkRSSI`（门锁**一旦连上就停止广播** ⇒ 发现侧再也不产生样本，靠近自动开锁的武装位只能从连接上取） | 编排 | LinkSenseKit | 低 |
| core-ble-06 | `writeFrameHex`（20B 分片 + 30ms 间隔，对齐 JS writeFrame）+ `onFrame` 帧回调 | 协议 | LockService×3, HardwareService | 低 |
| core-ble-07 | 写槽 FIFO `writeSlot/acquireWriteSlot/releaseWriteSlot/waitWriteReady/writeChunk`（with-response 必须串行，否则 `writeAckCont` 单槽被后者覆盖 ⇒ 前者 continuation 永不完成、挂死） | 并发 | 仅本文件内 | 中 |
| core-ble-08 | 就绪与状态 `waitReady/readyMessage`（首装权限弹窗未答复期间 state 恒 `.unknown`，直接判"未开启"会误导）+ `powerState` + `publishOnMain/emit/finishConnect/stopScanInternal` | 状态 | 仅本文件内 | 中 |
| core-ble-09 | 无响应写流控回调 `peripheralIsReady`（队列满时系统不报错也不抛；旧的 20ms 盲 sleep 分不清"对端慢"与"队列满"，分片写 cmd08 就会残帧）；广播设备 `BLEAdvDevice` + 测距回调 `rssiCompletion/rssiGeneration`（单槽 + 代次，防"等的不是我那一次"） | 并发 | AddLockPage×5, LinkSenseKit×2 | **高**（拍板 #1 的正解，回调体零引用） |

## 53. Services/DFUKit.swift（727 行）

DFU 固件升级套件 —— JS utils/dfu/{zip,nordic}.js + services/dfu.js 的 Swift 移植。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-dfu-01 | CRC32（IEEE 802.3，与 zlib 一致） | 校验 | Tests | 低 |
| core-dfu-02 | ZIP 解析 `ZipKit.parse/ZipEntry`（CRC 校验 + 原生 inflate = RFC1951 raw deflate）+ 只做方法 0 的 `write`（CSV/PDF 本已紧，要点是"打包+加密"不是压缩率） | 解析 | ExportCenter×4（`inflate` 仅内部） | 低 |
| core-dfu-03 | 固件包 `FirmwarePackage` + `FirmwareKit.parse` + 版本比较 `versionLt/nextMac` | 解析 | FirmwarePage×8, BatteryCare | 低 |
| core-dfu-04 | 降级闸 `downgradeBlocked`（烧旧固件本身不是漏洞，但配合"无签名"就是攻击者最省事的一条）+ `versionFromFileName` | 校验 | 仅本文件内 | 中 |
| core-dfu-05 | 错误 `DFUError`（zip / msg） | 协议 | BackupKit×8, BackupStudioKit×4, HomeConsole | 低 |
| core-dfu-06 | 会话 `DFUBleSession` + `Mode`（Secure FE59 / Legacy 1530；操作码取自 APK 内嵌 Nordic 12.x 库） | 编排 | 本文件内 | 中 |
| core-dfu-07 | 通道 `op/resp/rdU32/writeControl/writePacket/writeRaw/waitResponse/abort/stream` | 协议 | Store×3, AuditChain, LockService×6 | 中 |
| core-dfu-08 | 上传 `uploadSecure/uploadLegacy`（onProgress 标 `@Sendable` 才过 Swift 6 sending 检查）+ 扫描 `scanDfuDevice`（MAC+1 / ZkDFU 启发式） | 编排 | 仅本文件内 | 中 |
| core-dfu-09 | 进度 `DFUProgress`（0 连接 / 1 起始 / 2 切 DFU / 3 上传% / 4 校验 / 6 完成 / 7 中止） | 状态 | FirmwarePage×3 | 低 |
| core-dfu-10 | 单锁升级 `DFURunner.runUpgrade` + 144 批量排队 `QueueOutcome.runUpgradeQueue`（逐把**串行**：DFU 期间手机与锁都是独占态，并行既抢 BLE 又抢 bootloader；一把失败不中断队列）；中止活动会话 `cancelActive`（2026-10-14：离开升级页此前只 dismiss，传输实际继续，用户误以为已停） | 编排 | FirmwarePage×2 | **高** |

## 54. Services/HardwareService.swift（382 行）

蓝牙钥匙串（ZKBBV1 pid=16289）与智能网关（FE90）—— 两者共用 BLE 单连接，切目标时自动断旧连。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-hw-01 | 服务主体 `HardwareService` + `Waiter` 单连接通道 + 分级日志 `log` | 编排 | DonglesPage×5, GatewayPage×3, LockKeeperApp, LockService×60 | 低 |
| core-hw-02 | 钥匙串命令 `readDongleState/parseKCStatus`（11/24/25 直读，12/31/34/35 反转）、`writeDongleKey`（cmd41，空串 = 删除该锁钥匙）、`deleteDongleKey`、`dongleKeys/parseEkeyMacs`（cmd44，每 6B 一台） | 协议 | DonglesPage | 低 |
| core-hw-03 | 网关命令 `readGatewayState/parseGWStatus`（cmd38，01/04/05 双重反转 → ASCII）、`provisionGateway` 全链（扫描 → 38 → 31 写 WiFi → 35 重启）、`rebootGateway` | 编排 | GatewayPage | 低 |
| core-hw-04 | 型号族扫描 `scanForDongle/scanForPIDs/scanForPID/pidFor`（网关有 GW / GW_commercial / GW2_commercial **三个 pid**，只认 12193 会让另两种网关永远搜不到） | 编排 | DonglesPage（后三件仅内部） | 中 |
| core-hw-05 | 字节序解析 `direct/dotted3/dotted/v`（`dotted3` 对不是 3B 的输入回空串 —— **不是整 3 字节就回空**，对齐基线 keychain.js） | 解析 | `v` 27 处外部引用 | 低 |
| core-hw-06 | 记录绑定与内部件 `dongleRecord/gatewayRecord/connectTarget/send/errCodeOf/rcOf`；`GatewayState` 结构 | 编排 | 仅本文件内（`rcOf` 被 LockService 用）, 本文件 | 中 |

## 55. Services/LockService.swift（1,028 行）

离线管理端核心：会话令牌生命周期 / 命令执行 / rc 守卫 / 配网编排（JS services/lock.js 同构：**无条件刷新令牌** V81 语义 · rc=3 自愈重试 · G1~G8 守卫）。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| core-ls-01 | 服务主体 `LockService` + `ensureConnected`（切锁/进页/固件页共用一条连接） | 编排 | LinkSenseKit×6, LockKeeperApp×2, FirmwarePage×2 | 低 |
| core-ls-02 | 请求/等待 `Waiter/request` + `exec/execOk`（`ExecResult`）—— rc=3 自愈重试与 G1~G8 守卫都在这一层 | 协议 | BackupStudioKit×5, MemberCenterView | 中 |
| core-ls-03 | 0x88 带 MAC 命令集 `macBearingCmds`（rc=12 的顺序自愈只对它们有意义；网关/明面命令的 MAC 在别处） | 配置 | 本文件 | 低 |
| core-ls-04 | 回包形状 `klvShape`（只报键与长度，**一个值都不带** —— "#02=0B 锁压根没回密钥"这种事实比猜测有用，而值里可能含 skey/ekey/PIN） | 诊断 | 仅本文件内 | 中 |
| core-ls-05 | 配网提示 `pairWarning/pairHint`（判据是"本机有没有留存这份密钥"而非"换钥有没有发生"；**刻意不复用 rcHint** —— 配网期本机还没有钥匙串，0E 校时根本发不出去） | 格式化 | 仅本文件内 | 中 |
| core-ls-06 | 状态与锁钟 `getStatus/readLockTime` | 协议 | AutoOpen, LinkSenseKit, LockKeeperApp | 低 |
| core-ls-07 | **04 开锁唯一出口** `unlock` | 编排 | LockKeeperApp×5, LockCommand×4, AuditChain×3 | 低 |
| core-ls-08 | 校时 `syncTime` + 静音 `setSilent` + 验证模式 `setValidationMode`（**只允许 A→B 变严**，且必须回读 verifyMode 才能报成功 —— rc=0 只证明命令被接收） | 协议 | LockCommand×3, QuickPool×3, ManagerFace×3, SettingsView | 低 |
| core-ls-09 | 布防 `setDefence` / 自动上锁 `setAutoLock` / 临时码开关 `setZotp` | 协议 | — | **高**（三件零调用：设置页三个开关没有下发侧） |
| core-ls-10 | 密码族 `pwdAdd/pwdDelete/pwdExpire` + `pwdModify/pwdClear/aliasFrom` + 指纹族 `fpStart/fpConfirm/fpDelete` + `FpPress` 进度 | 协议 | CredentialOrg, AddKeyPage, CredentialStudio, AddFingerPage×3 | 中 |
| core-ls-11 | 按压判据 `press/isPress/pressesCount/collectionDone`（干净按压 = rc 正常且 KLV#04 序号 > 0；**模糊帧不计数**，否则屏上写 4/8 而锁里只有 3 次有效特征） | 计算 | 仅本文件内 | 中 |
| core-ls-12 | 日志抓取 `getLogs` + `LogPage`（surplus + 分页）+ 升级模式 `enableDfu` | 协议 | EventsPage, LockCommand×3, DFUKit | 低 |
| core-ls-13 | 配网 `pair` + 尾链 `finishPairing`（完整配网与续配共用同一条尾链 —— 分开写迟早只改一条，而续配漏一步就是软砖）+ 幽灵台账清理 `cleanWrongOrderTwin` + 免令牌回声 `EchoProbe/probeEcho/sendEcho` + 扫描 `scanForMAC` + 帧脱敏 `Redact.frameHex` | 编排/安全 | FirmwarePage×5, AddLockPage×3, CredentialStudio×2, BackupKit, HardwareService | 中 |

## 56. App/LockKeeperApp.swift（1,698 行）★ 冗余重灾区

离线锁管家 for iOS —— App 入口与全局状态（SwiftUI 全原生）。61 个函数里 13 个零调用、30 个仅本文件内自用。

| ID | 功能点 | 类型 | 被谁用 | 冗余嫌疑 |
|---|---|---|---|---|
| app-01 | `@main` 入口 `LockKeeperApp`（WindowGroup + `environmentObject` + `tint(XPalette.accent)`）+ 旧主题枚举 `Theme`（三枚转发到 XPalette；isLight/scheme 已按规范整组删除） | 入口 | 系统 / —（`Theme` 零引用） | **高**（`Theme` 枚举零引用） |
| app-02 | `AppState` 全局状态对象（设备/当前锁/状态快照/开锁态/应用锁位；42 个外部文件引用） | 状态 | SecurityCenterView×8, LinkSenseKit×7, BackupStudioKit×6, MemberCenterView×6 | 低 |
| app-03 | 377 访客通道：`guestAreaUnlocked`（**内存态** —— 落盘就等于"退出不用再输密码"）/ `guestGateTarget` / `needGuestGatePrompt` / `guestGateGroup` / `guestAreaLocked` | 状态 | 本文件 + HomeConsole | 低 |
| app-04 | `showGuestGate` 标志（注释自承"不再驱动任何界面"）+ `presentGuestGate/openGuestGate/presentGuestGateFromView`（复核现由 UIAlertController 直接 present） | 状态 | 仅本文件内 | **高** |
| app-05 | 383 sudo 券会话持有 + 换页**唯一漏斗** `requestRoute`（深链/粘贴条/自检黄条都汇到这里，377 访客闸只在此生效）+ 兼容适配器 `requestTab` + 377/383 会话授权收回 `revokeSessionGrants` | 编排 | BackupStudioKit×3, CredentialOrg, AddLockPage, SecurityCenterView | **高**（`requestTab` 零调用） |
| app-06 | 底部导航 `tabSelection` 五 Tab 语义（0 门厅 / 1 钥匙 / 2 设备 / 3 成员 / 4 系统）+ 序号常量族 + 由 Route 派生的深链与访客受限集 | 状态 | 全仓视图 | 低 |
| app-07 | 外观通道 `appearanceSeed/prefSeed/applyAppearance/reloadAppearance`（主题变更 +1 重建全树；恢复备份后必须显式调，否则"包里是深色、屏幕还是浅色"） | 状态 | BackupKit×2, BackupPage, BackupStudio | 低 |
| app-08 | 外观设置组 `setTheme/setHighContrast/setWeekStart/setHeroStats/setRecentCount/resetAppearance/bumpAppearanceForLayout` | 配置 | 仅 `setHighContrast`/`setWeekStart` 有外调 | **高**（五件零调用） |
| app-09 | 开锁偏好 `setUnlockOption` + `behaviorKeys`（区分"重建全树"与"只发轻量信号" —— 后者不换身份所以滚动位保住） | 配置 | — | **高** |
| app-10 | 54/372 摇一摇双语义 `handleShake` + `shakePanel/shakeReturnTab`（按当前 Tab 定死优先级，不做"两个都试试"；回位票是内存态，落盘会跨启动诈尸）+ 826 解锁落地 `commitUnlock/confirmGatePassed/cancelGate/rememberTab/restoreLastTab` | 编排 | 仅本文件内 | 中 |
| app-11 | 开锁动作链 `requestUnlock/startUnlock/runUnlock/cancelUnlock/finishDwell/unlockReturnedHint` + PIN 选择 `chosenPinIndex/setChosenPinIndex/chosenPin`（存下标不存 PIN，口令留钥匙串）+ `UnlockState` | 编排 | — | **高**（六个动作与三个 PIN 口全零调用，已被 AutoOpen/LockService 路径取代） |
| app-12 | Toast `showToast` + `ToastTone` 语义触感档（§11.4：触感由**语义**决定而非颜色；此前 141 处调用只有一处配了触感） | 组件 | MemberCenterView×16, SecurityCenterView×15, BackupPage×11 | 低 |
| app-13 | 508 写入回执 `flashReceipt`（2 秒浮出对勾，替代云同步反馈，纯本地不碰网络） | 组件 | — | **高** |
| app-14 | 344 粘贴建议条刷新 `refreshPasteSuggestion` + 827 快捷格提示态 `ambientTipUsed/ambientTipOff/showAmbientList/quickTipTile` | 状态 | 仅本文件内 | 中 |
| app-15 | 42/268 首用气泡 + 同屏提醒排位 `ambientRanked` + 397 库体自检 + 深链落地暂存四件 + 设备台账与静默刷新 | 计算/状态 | 本文件 + 视图, AddLockPage×2, BackupStudio×2, LocksPage×2, HomeConsole×2 | 中 |

## 跨文件专题

### A. 零调用清单（冗余「高」的全量索引）

> 判据：声明存在，但全仓（`App/**` 106 + `Tests/**` 4 个 .swift）**无任何调用点**。合计 **155 函数 + 15 类型 + 2 个只有注释的空文件**。下表按"这一条承诺了什么"归并，共 28 组。

| # | 位置 | 零调用符号 | 承诺的事 / 为什么值得注意 |
|---|---|---|---|
| 1 | Core/SpeechKit.swift | 整文件（0 声明） | 注释承诺 `Speech.digits`，**类型不存在**；`CredentialStudio:13-14` 还引用着它 |
| 2 | Core/DevModules.swift | 整文件（0 声明） | 设备页模块显隐整批未实现 |
| 3 | Core/SettingsGroups.swift | `SettingsGroup` + `settingsSectionShown` | 设置页五组筛选片（外部零引用） |
| 4 | Core/AccessibilityKit.swift | `CalcToken` / `reasonText` / `axGlassCircle` / `announceConnectFail` / `newEntryHaptic` / `liveFocusSequence` | 与 `AXPrefs` 逐行相同的副本；392 留痕、圆形玻璃、852 播报示例、876 双震、855 焦点序列 |
| 5 | Core/AutoOpen.swift | `suspendUntil/setSuspendUntil/isSuspended` + `lastReject` + `makeContext/dispatch/selfHealTime/doorName` | rc=26 防拆自动关闭 24h；0E 双确认自愈校时 |
| 6 | Core/BatteryCare.swift | `facePct` / `faceText` | 电量界面写法（"--" / ">80%"）；`CareSchedule.notifyNow` 亦只在本文件内自洽，**没有任何外部触发点** |
| 7 | Core/Components.swift | `XCodeRing` / `XCycleRing` / `XHeroCard` / `xFontScaled` / `shows` / `animateTo` / `startPulse` / `block` | 时效码大环、周期环、空壳 HeroCard、§7.18 数字降档 |
| 8 | Core/CredentialOrg.swift | `batchExtend` / `batchTransfer` / `exportPackage` / `monthDeadlines` / `dayDeadlines` / `recentUseCount` / `typeCounts` / `namingTemplate` / `listCountdown` / `addTotp` / `removeTotp` / `addStaticCode` / `removeStaticCode` / `totpParams` / 用量九件 / 风险判据五件 / 预警写侧四件 / 队列四件 / 回收站执行七件 | **43 个零调用函数集中于此**（详见第 10 节） |
| 9 | Core/DiagKit.swift | `EntityRef`/`Kind`/`DayRate`/`FailClass`/`Family`/`Slice` + `lastSessionLine`/`markSeen` | 154/543 深链实体、748 成功率、546/152 体积构成、387 上一会话 —— **数据类型建好却无渲染方** |
| 10 | Core/FirmwareHistory.swift | `observed` / `observations` | 755 固件随行标注**只有写侧**，读侧没人读 |
| 11 | Core/HolidayFeed.swift | `setSource` / `clearCache` | 671 的"选源"与"清缓存"两个用户动作 |
| 12 | Core/LinkSenseKit.swift | `noteScannedRssi` / `rssiFor` / `enterPage` | 537 下拉重扫回传、95 进页预热 |
| 13 | Core/LockStats.swift | `reordered` / `pinToFront` / `clearManualOrder` / `symbolName` / `boundLabel` / `recentAlarmMacs` / `sampleTimeText` | 766 组内拖动改序、置顶、符号名、769 绑定时间小字、764 告警锁集合 |
| 14 | Core/MemberHub.swift | `isVisitorRow` / `doubleLine` / `appendEdge` | 793 访客分组、461 双层文本、关系图谱（图谱因此画不出边） |
| 15 | Core/Milestones.swift | 打卡四件 + 三个写侧（`recordOrganize`/`setMemberBadge`/`setMemberBirthday`）+ `companionDays/companionFullYear/companionText`/`solarTermToday`/`solarTermHint`/`launchPhrase` + `QuarterSummary` | 写侧缺失使 `weekDone` 恒 0、`memberBadges` 恒空 |
| 16 | Core/QuickPool.swift | `setSelected` / `setSmartFirst` / `recordTap` / `clearCounts` / `repeatTarget` / `quickDestination` | **写侧全空** ⇒ `counts` 恒空 ⇒ 1047 排序恒等于原序 |
| 17 | Core/RecordSearch.swift | `alarmTitle`/`sameCountPreview`（自承"编译期未解析符号"）/ `markDisposition`/`undoDisposition`/`misfireFold`/`setCheck` / `outOfWindow` / `trialEventsToday`/`trialCountToday` / `alarmStream`/`mergedRecentOpens`/`damageDays` / `setPolicy`/`setNightFrom`/`setNightTo`/`setHolidayExtend` | 18 个零调用：处置无写入方 ⇒ 734/735 的"未处置"恒等于全部 |
| 18 | Core/ScreenCare.swift | `keepingScreenAwake` | 注释点名 FirmwareView / StartAddFpView 两个调用点，实际都没有 |
| 19 | Core/Store.swift | `rePwd` / `setFpAlarm` / `getPwdList` / `getFpList` | 台账改值与列表读取口 |
| 20 | Core/ZOTP.swift | `nextWindow` | 下一窗口预告 |
| 21 | Services/BackupStudioKit.swift | `verifyChecksum`/`shortHash` / `noteMigTxnDone`/`pendingMigrationTxn`/`clearMigSession`/`firstChecks` / `duePins`/`markPinSeen`/`pinLabel`/`pinDayText` + `CompletionOnce`/`Handover` | 422/423/434 校验链、445 迁移事务断点、442 首验清单、433 密码提示 |
| 22 | Services/BLEService.swift | `peripheralIsReady` | 无响应写流控回调（拍板 #1 的正解） |
| 23 | Services/DFUKit.swift | `cancelActive` | 注释自承"此前离开升级页只 dismiss，传输实际继续" |
| 24 | Services/LockService.swift | `setDefence` / `setAutoLock` / `setZotp` / `pwdClear` / `probeEcho` | **布防 / 自动上锁 / 临时码三个设置项没有下发侧** |
| 25 | App/LockKeeperApp.swift | `requestTab` / `openGuestGate` / `presentGuestGate`(系列) / `flashReceipt` / `bleStatusStrip` / `requestUnlock`/`startUnlock`/`cancelUnlock` / `chosenPinIndex`/`setChosenPinIndex`/`chosenPin` / `setTheme`/`setHeroStats`/`setRecentCount`/`setUnlockOption`/`bumpAppearanceForLayout`/`resetAppearance` / `motionEnded`/`onDeviceShake` + `Theme` 枚举 | 入口层 13 个零调用成员，多为旧四 Tab / 旧开锁链 / 旧外观设置的残骸 |
| 26 | Core/StatsKit.swift | `weekSummary`/`lastWeekDigest` / `memberBubbles`/`memberDaily`/`memberTodayCount` / `homeProxyHours`/`homeDurationProxy` / `kindWords`/`kindOrder`/`naturalSentence` / `isIdleLock`/`springFestiveRange` | 13 个零调用：799/698/624/604/955/800/673 七族统计无消费者 |
| 27 | Core/LockGuard.swift / LockCommand.swift / AuditChain.swift / StatusParser.swift | 无零调用（仅本文件内 2~4 个内部件） | 安全与协议族全员在用，是全层质量最好的一批 |
| 28 | Core/AESKit.swift / Core/ZKProtocol.swift / Core/ZKCmdBuilder.swift | `decryptHex`（仅测试）/`parseKLV`/`normMac`/`wrapEnc` | 内部件已收口，无孤儿 |

### B. 重复实现（同一件事写了两遍以上）

| # | 主题 | 重复点 | 风险 |
|---|---|---|---|
| 1 | AX 偏好九件套 | `AXPrefs`（AccessibilityKit:99）× `CalcToken`（:186）**逐行相同** | 改一处必漏另一处 |
| 2 | 电量→图标映射 | 曾三套：`BatteryCare.icon` 已收，DonglesPage / LocksPage 曾各一套 | p=5 时三处分别给 `battery.0`/`battery.25`/`battery.0percent`：同一格电量两个屏显示不同图标 |
| 3 | 锁态文案 | `StatusParser.lockStateText` 已收；LocksPage / LockProfilePage 曾逐字重复 9 行 switch | 已修，页面层需防回潮 |
| 4 | 日 key | `StatsKit.dayKey` / `Milestones.dayKey` / `RecordSearch.dayKeyOf` / `DiagLogs.localDay` 四处同算法 | §10.30 记录过 UTC 偏差事故（UTC+8 在 00:00–08:00 拿到"昨天"） |
| 5 | 队列项下发 | `CredentialOrg.sendQueued`（唯一实现）vs `LinkSenseKit.applyQueueItem`（第四份副本，自承弃用）vs 另两处视图内 switch | 缺载荷时静默中止的语义各不相同，且自动补发那条路**没人盯着** |
| 6 | 告警类型集合 | `LockStats.openTypes = StatsKit.openTypes`（已收） | 加一类告警只改一处就会静默漂移 |
| 7 | 备份时间读法 | `DestroyKit.lastBackupAt` / `Milestones.lastBackupAt` / `BackupStudio.lastExportMs` 三处（毫秒 vs 秒口径曾不一致） | 7 天闸与页面日期曾一起失真 |
| 8 | 成员色回落 | `XAppearance.memberSwatch` 已收（此前 FpOwnerPicker / MembersPage / SecurityCenterView 三处各写一套，**回落值三处不同**） | 已修 |
| 9 | 时长/日终出口 | `TimeFormat.dayEnd` 已收（此前两个表单各抄一份且都写错） | 已修 |
| 10 | 关系文案 | `MemberHub.doubleLine` 与 MembersPage 页内拼接 | 两处文案分叉 |
| 11 | 提示音出口 | `AlertTone` 已收；`Milestones.playCollectSound` 仍走裸 `AudioServicesPlaySystemSound` | 静音开关覆盖不到 |
| 12 | 周界算法 | `WeekCal.shifted` 是唯一出口，但 `+86400` 的写法仍在若干页面 | 夏令时地区差一格 |

### C. 协议层与密码学（冗余低，核心资产）

| 模块 | 结论 |
|---|---|
| `ZKProtocol`（299 行） | 8B/10B/7B 三种帧头 + 0x88 包络 + KLV#0xEE 令牌注入 + 粘包重组 + 广播解析。**21 个文件、213 处引用**，BLE 链地基。活函数 23/23，仅 3 个内部件。**冗余低。** |
| `ZKCmdBuilder`（286 行） | 40 个命令构造器全部有完整帧 hex 的 golden 差分；活函数 40/40。**冗余低。** |
| `AESKit` / `ZOTP` / `KeyGen` / `BackupKit.CryptoBox` / `BackupCanonical` | 与 JS 侧**字节级互通**的密码学资产（AES-128-ECB / ZOTP / CSPRNG / PBKDF2+AES-CBC+HMAC / FNV-1a32 复刻）。冗余低；注意 `AESKit.decryptHex` 只有测试调用、`ZOTP.nextWindow` 零调用。 |
| `LockCommand`（125 行） | 30 条命令的读写分类表，296 只读模式的唯一判据口（fail-closed）。**安全关键，冗余低。** |
| `LockGuard` / `SudoTicket` / `SecurityPolicy` | 377/383/296/376 四枚开关的唯一判据口；`SudoTicket.init` 是 fileprivate ⇒ 外部造不出无凭据的券。**安全关键，零死代码。** |
| `SecretStore` | 密钥材料进系统 Keychain（AfterFirstUnlockThisDeviceOnly）。**安全关键，冗余低。** |

### D. 统计聚合类专项（任务书点名"常有大量没人看的指标"）

| 文件 | 行数 | 声明 | 零调用 | 判读 |
|---|---|---|---|---|
| `StatsKit` | 1,088 | 19 数据点类型 + 39 函数 | **13 函数**（33%） | `StatModel` 的 25 个只读属性里约 2/3 被 StatsPage/HomeConsole 消费（日柱/月对比/作息四轴/帕累托/告警构成）；**剩下 1/3（成员族 799/624/604/955、在家时长 800、上周小结 698）没有任何页面渲染**。典型形态：数据层先建好，视图层没跟上。 |
| `LockStats` | 438 | 9 类型 31 函数 | 7 函数 | 776/778/784/787 在用；**766 手工排序的写侧（reordered/pinToFront）与 764 告警锁集合无人调**。 |
| `DiagKit` | 696 | 28 类型 40 函数 | 2 函数 + **6 类型** | 零调用函数少，但 `EntityRef`/`Kind`/`DayRate`/`FailClass`/`Family`/`Slice` 六个**数据类型建好却没有渲染方**（154/543/748/756/546/152）。 |
| `Milestones` | 617 | 10 类型 37 函数 | **9 函数 + 1 类型** | 打卡族与三个写侧全空 ⇒ `weekDone` 恒 0、`memberBadges` 恒空。 |
| `RecordSearch` | 1,018 | 16 类型 78 函数 | **18 函数 + 1 类型** | 处置写侧缺失（markDisposition）使 734/735 未处置队列失去意义；737 今日试错、729 误报折叠、723 跨锁告警流三族整条未接。 |

**结论**：统计聚合层的问题不是"多写了函数"，而是**读侧齐全、写侧/渲染侧成片缺失**，导致部分指标恒为 0 或恒为全量。优先补 5 个写侧缺口（`QuickPool.recordTap`、`RecordSearch.markDisposition`、`Milestones.recordOrganize`、`CredentialOrg.setArchived`、`BackupStudioKit.markPinSeen`）比删函数划算得多 —— 删掉读侧会永久失去已经设计好的能力。

### E. 全层结论

1. **主要问题不是"死代码多"，而是"写侧少、读侧多"**：155 个零调用函数里约六成是读侧/展示侧（统计属性、格式化、查询），删掉会永久失去已设计好的能力；真正该删的是**重复副本**与**已被替代的旧实现**：`CalcToken`、`LinkSenseKit.applyQueueItem`、`requestTab`、`Theme` 枚举、`XHeroCard`、`XCycleRing`、`XCodeRing`、`CompletionOnce`、`Handover`、`DevModules` 注释壳。
2. **两个空文件最该先处理**：`SpeechKit.swift` 与 `DevModules.swift` 让 UI 侧注释（`CredentialStudio:13-14`、设备页面板注释）变成了假承诺。
3. **协议 / 密码 / 安全五族（ZKProtocol、ZKCmdBuilder、AESKit+ZOTP、LockCommand、LockGuard）零问题**，是全仓质量最高的部分，也是 96/296/377/383 这些安全承诺的唯一实现。
4. **入口文件是第二大冗余源**：61 个函数里 13 个零调用、30 个仅本文件内自用；四组残骸（旧四 Tab 语义、旧外观设置、旧开锁动作链、旧 HeroStats/回执）都是被新架构取代后未清理的。
5. **"命名即承诺"型缺陷值得单列一类**：`alarmTitle`/`sameCountPreview`（注释自承编译期未解析符号）、`setArchived`（自承"15 处过滤全是空操作"）、`keepingScreenAwake`（点名两个不存在的调用点）、`cancelActive`（自承此前只 dismiss）—— 本仓注释质量很高，反而让这类"注释已经写清是假的"条目格外好定位。

---

*口径说明：引用计数由 110 个 .swift 剥注释后逐符号正则匹配得出；同名短符号（`record`/`sample`/`tier`/`icon`/`body`/`save`/`load`）可能带来 ±1 误差，涉及"高"判定的条目均已人工复核。行数以物理行计（含注释与空行）。*
