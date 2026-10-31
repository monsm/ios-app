# AUDIT-A · 功能遗漏审计（原 App → ios27）

> 审计对象：D:\aapk\ios-app\App（原 iOS App，**139** 个 Swift）→ D:\aapk\ios-app\ios27（新 App，**143** 个 Swift）。
> 审计日期：2026-10-31。
> 审计立场：默认「有遗漏」；结论只写有文件/行号或实测数字支撑的项。
> 审计口径：**用户能否从 App 根界面点到该功能，并且点下去真的发生该功能描述的结果**。只有引擎存在、没有页面/按钮，或按钮存在但无消费者，一律不算「已覆盖」。
> 审计对象未修改：本报告只写 ios27/docs/AUDIT-A-OMISSION.md。
>
> 修复状态（2026-10-31）：§5 的 34 项与 §7 的 8 项均已修复，并在对应行标注「✅ 已修复 · 文件:行」；完整清单与剩余项见 docs/FIX-REPORT.md。

---

## 0. 结论摘要（先给结论）

1. **PARITY-V7 的「127 / 127 已覆盖、0 降级、0 缺失」不成立。** 本次确认 **遗漏 34 项**（见 §5、§8），另有 **8 项伪实现/错误入口**（见 §7）。
2. 文件规模：原 App 实测 **139** 个 Swift；ios27 实测 **143** 个 Swift。PARITY-V7 第 3 行写的「新 App 124 个 Swift」是过期数字（实际多 19 个）。
3. PARITY-V7 第 223 行「53 个纯逻辑 Engine 文件逐字节一致」经 SHA-256 实测**成立**：同名文件 53 个，哈希全部相同；另有 13 个同名文件内容不同（BatteryCare / CaptureShield / CredentialOrg / LockStats / QuickActions / QuickPool / RecordSearch / TimeFormat / ToastCenter / LockKeeperApp / BackupKit / DefendService / MobileKeyService），73 个原 UI/Core 文件在 ios27 没有同名文件。
4. 最重的三个页面级断点：
   - **锁信息名片 DeviceInfoView 整页无路由**（ios27 全仓 DeviceInfo 仅剩注释）。
   - **30 秒内二次开锁应用锁闸 UnlockGateView 无任何 route/sheet**（ios27 全仓 showGate / UnlockGate 命中 0）。
   - **设备页「模块排序与显隐」moduleOrderSheet 无入口**（DevModuleStore 引擎存在且与原版逐字节一致，但 ios27 Features 中 0 引用）。
5. 最重的行为级断点：ios27 的「开锁圆盘」是普通 Button（DoorScreen.swift:94-107），没有原版的按住确认/上滑/误触围栏/双击直开/失败自动重试/失败排查链；设置页里对应的开关只是写入 kf_* 键，无任何消费者（见 §7）。

---

## 1. 方法与统计

- 用 glob 取全量 Swift：原 App 139、ios27 143。
- 用 grep 做「页面/路由/入口」检索：router.request、.dest(、.sheet、NavigationLink、alert。
- 用 SHA-256 逐文件比对同名文件：**53 个逐字节一致**，13 个同名不同内容，73 个无同名文件。
- 用 grep 对每个新增设置项做「写点 / 读点」对账：只写不读 = 假开关；有引擎无 UI = 引擎空转。
- 边界：本机无 Swift/Xcode，无法 xcodebuild；本报告是静态代码级审计，不把「能编译」当结论。

### 1.1 原 App 模块归类（文件数）

| 模块 | 文件数 | 主要内容 / 关键类型 |
|---|---:|---|
| App/Core | 64 | ZKProtocol/ZKCmdBuilder/StatusParser、AES/KeyGen/ZOTP、Store/StoreModels/StoreKeychain/StoreLedger、LockStats/LockArchive、MemberHub、RecordSearch*、StatsKit、BatteryCare、DesignSystem/DesignTokens、AccessibilityKit、SettingsGroups、DevModules、TrialGuardKit、AutoOpen、LinkSense、Destination |
| App/Services | 17 | BLEService/BLEDelegates/BLETypes、LockService+Link/Pairing/Credentials/Ops、DFUKit、ZipKit、BackupKit/BackupCanonical/BackupStudioKit、HardwareService、MobileKeyService、DefendService、Attribution |
| App/UI | 53 | DeviceHomeView/Blocks/Quick/Support、CredentialsView/Actions/ListRows/Otp/Center/Calendar、PwdStudio/PwdDetailStudio/FpStudio/FpDetailStudio/TempCodeStudio/StudioHome、RecordsView/Chrome/Sheets/Timeline、MemberCenter/Members/MemberWizard/MemberDetail、SettingsView/Sections/SubPages/Appearance、LockSettingsView/DeviceInfoView/LockProfileView/DongleView/GatewayView/DFUView/ProtocolTestView、BackupView、AddDeviceView、DefendView、ShareToAndroidView |
| App/ 根 | 5 | LockKeeperApp（AppState/RootView）、RootTabs、AppStateAppearance、AppColorExtension、UIKitComponents |
| **合计** | **139** | |

### 1.2 ios27 模块（文件数）

| 目录 | 文件数 |
|---|---:|
| App/Engine | 69 |
| App/Features/Door | 15 |
| App/Features/Settings | 14 |
| App/Features/Keys | 13 |
| App/Features/Household | 11 |
| App/Features/Records | 5 |
| App/Features/Shared | 1 |
| App/Design + Design/Components + Design/V7 | 10 |
| App/Shell | 4 |
| App/ 根 | 1 |
| **合计** | **143** |

---

## 2. 原 App 28 个 Destination 与 ios27 路由对照（页面级）

原 App 的 App/Core/Destination.swift:8-38 是自动生成的 28 个页面清单。ios27 的可达页面以 App/Shell/Router.swift:9-121 的 Dest + App/Shell/Destinations.swift:7-57 为准。

| # | 原页面（Destination） | 原文件 | ios27 对应 | 用户能否点到 | 结论 |
|---:|---|---|---|---|---|
| 1 | AddDeviceView | App/UI/AddDeviceView.swift:5 | Features/Door/AddLockScreen.swift:9（Dest .addLock） | 是（Door 空态/入口，Settings 空态） | 已覆盖（4 步 UI，真实配网链） |
| 2 | BackupView | App/UI/BackupView.swift:8 | Features/Settings/BackupScreen.swift:10（Dest .backup） | 是（设置→备份与恢复） | 部分覆盖：**文件选择器/导出到文件缺失**（见遗漏 #22） |
| 3 | CredentialCalendarView | App/UI/CredentialCalendarView.swift:14 | Features/Keys/KeyCalendarScreen.swift:10（Dest .keyCalendar） | 是（Keys→到期月历） | 已覆盖 |
| 4 | CredentialsView | App/UI/CredentialsView.swift:16 | Features/Keys/KeysScreen.swift:9 | 是（底部「凭证」） | 降级：**搜索/按成员分组缺失**（#13/#14） |
| 5 | CredExtendView | App/UI/CredentialCenterView.swift:16 | Features/Keys/CredentialStudioScreen.swift:13（批量延期） | 是（Keys→凭证工作室） | 已覆盖（批量形式；无独立 sheet） |
| 6 | DefendView | App/UI/DefendView.swift:12 | Features/Door/DefendScreen.swift:9（Dest .defend） | 是（Door/Settings→布防） | 已覆盖 |
| 7 | DeviceHomeView | App/UI/DeviceHomeView.swift:7 | Features/Door/DoorScreen.swift:9 | 是（底部「设备」） | **降级严重**：多个模块/流程缺失（#5-#11） |
| 8 | **DeviceInfoView** | App/UI/DeviceInfoView.swift:6（Destination.swift:16） | **无 Dest / 无页面** | **否** | **缺失**（#1） |
| 9 | DFUView | App/UI/DFUView.swift:11 | Features/Door/DFUScreen.swift:9（Dest .dfu） | 是（设置→固件升级，锁设置→固件） | 已覆盖（版本比对/本地导入/降级闸/进度） |
| 10 | DongleView | App/UI/DongleView.swift:14 | Features/Settings/HardwareScreen.swift:10（Dest .hardware） | 是（设置→钥匙串/硬件） | **降级**：写钥/扫钥有；查看已写入/假钥匙/解绑无（#19-#21），手动读状态也未单列 |
| 11 | GatewayView | App/UI/GatewayView.swift:5 | Features/Door/GatewayScreen.swift:9（Dest .gateway） | 是（设置/Door） | 已覆盖 |
| 12 | LockProfileView | App/UI/LockProfileView.swift:5 | Features/Door/LockProfileScreen.swift:10（Dest .lockProfile） | 是（锁设置→锁档案） | 基本覆盖，但启动默认锁/PIN 选择是假开关（§7-B4） |
| 13 | LockSettingsView | App/UI/LockSettingsView.swift:17 | Features/Door/LockSettingsScreen.swift:11（Dest .lockSettings） | 是（Door/设置→锁设置） | 已覆盖（含清空密码、静音、临时码、安全模式入口） |
| 14 | MemberArchivedView | App/UI/MemberWizard.swift:305 | Features/Household/MemberArchiveScreen.swift:9（Dest .memberArchive） | 是（家→归档成员） | 已覆盖 |
| 15 | MemberCenterView | App/UI/MemberCenterView.swift:14 | Features/Household/HouseholdScreen.swift:22（Dest .household） | 是（Door→成员；非底部 Tab） | 已覆盖（含分组筛选/排序/归档/家庭场景） |
| 16 | MemberDetail360View | App/UI/MemberDetail.swift:7 | Features/Household/MemberDetailScreen.swift:8（Dest .memberDetail） | 是（家→点成员） | 已覆盖（角色/权限/档案/凭证/摘录/归档） |
| 17 | MembersView | App/UI/MembersView.swift:5 | Features/Household/HouseholdScreen.swift:22 + MemberCreateScreen.swift:10 | 是 | 降级：**电话字段/一键呼叫缺失**（#24） |
| 18 | MemberWizardView | App/UI/MemberWizard.swift:7 | Features/Household/MemberCreateScreen.swift:10（Dest .memberCreate） | 是（家→新建成员） | 基本覆盖；**初始临时码只写内存**（§7-B3） |
| 19 | MergeMembersView | App/UI/MemberWizard.swift:207 | Features/Household/MemberMergeSheet.swift:6（MemberDetail 内 sheet） | 是（成员 360→重复合并） | 已覆盖 |
| 20 | MobileKeyView | App/UI/MobileKeyView.swift:10 | Features/Keys/MobileKeyScreen.swift:10（Dest .mobileKey） | 是（Keys→手机钥匙） | 已覆盖 |
| 21 | ProtocolTestView | App/UI/ProtocolTestView.swift:15 | Features/Settings/ProtocolTestScreen.swift:7（Dest .protocolTest） | 是（设置→协议测试） | 已覆盖 |
| 22 | RecordsView | App/UI/RecordsView.swift:20 | Features/Records/RecordsScreen.swift:9 | 是（底部「记录」） | 降级：**跨锁范围/换锁缺失**（#23）；告警类型筛选缺失（#4） |
| 23 | SafemodeIntroView | App/UI/SettingsSubPages.swift:92 | Features/Door/SafeModeScreen.swift:9（Dest .safeMode；LockSettings sheet） | 是（锁设置→安全模式） | 已覆盖 |
| 24 | SettingsView | App/UI/SettingsView.swift:7 | Features/Settings/SettingsScreen.swift:9 | 是（底部「设置」） | 降级：**设置页内搜索/分组筛选缺失**（#26）；通知权限行缺失（#27） |
| 25 | ShareToAndroidView | App/UI/ShareToAndroidView.swift:8 | Features/Keys/ShareToAndroidScreen.swift:12（Dest .shareToAndroid） | 是（Keys→分享给安卓） | 已覆盖 |
| 26 | SyncTimeView | App/UI/DeviceHomeSupport.swift:5 | Features/Door/SyncTimeScreen.swift:9（Dest .syncTime） | 是（Door/设置/锁设置） | 已覆盖（cmd03/cmd0E + 回读） |
| 27 | TailgateView | App/UI/SettingsSubPages.swift:29 | Features/Door/TailgateScreen.swift:9（Dest .tailgate） | 是（锁设置→防尾随） | 已覆盖（2–6 秒档 + PidMap 门禁） |
| 28 | **UnlockGateView** | App/UI/DeviceHomeSupport.swift:122 | **无 Dest / 无 sheet** | **否** | **缺失**（#2） |

**结论：28 个 Destination 中 2 个整页无路由（DeviceInfoView、UnlockGateView）；另有 8 个页面存在但关键子功能缺失（Backup/Dongle/MemberWizard/Members/Records/Settings/DeviceHome/LockProfile）。**

### 2.1 原 App 里有页面/流程、ios27 没有对应路由的 Sheet / Alert / Empty / Error 清单

| 原 App 流程 | 原文件:行 | 原实现形态 | ios27 是否有点击入口 | 结论 |
|---|---|---|---|---:|
| 设备页「模块排序与显隐」 | App/UI/DeviceHomeView.swift:77,354-460 | moduleOrderSheet：3 槽排序 + 每模块显隐 + 快捷格勾选 + 恢复默认 | **无**（DevModuleStore 仅 Engine 定义） | 缺失 |
| 设备页空态「从备份恢复」第二出口 | App/UI/DeviceHomeView.swift:178-194 | 空态按钮 → 设置→备份与恢复 | **无**（DoorScreen.swift:384-401 只有「添加门锁」） | 缺失 |
| 设备页失败排查清单 / 再试一次 | App/UI/DeviceHomeBlocks.swift:403-427,495-519 | 三连败清单、失败终态重试 | **无**（DoorScreen.swift:109-124 只有错误文案） | 缺失 |
| 设备页自动上锁倒计时 | App/UI/DeviceHomeBlocks.swift:377-385,480-493 | 开锁成功后的秒级倒计时 | **无** | 缺失 |
| 30 秒内二次开锁应用锁闸 | App/UI/DeviceHomeSupport.swift:122-219；App/LockKeeperApp.swift:380-384 | showGate sheet + 本机密码 + 冷却 | **无**（showGate 0 命中） | 缺失 |
| 记录页告警类型多选 | App/UI/RecordsSheets.swift:9-62 | AlarmKindsSheet 真实类型多选 | **无**（AlarmKinds 0 命中；RecordsStudioScreen.swift:174 仅布尔「只看告警」） | 缺失 |
| 记录页「范围：当前锁/全部锁 + 换锁」 | App/UI/RecordsFilters.swift:105-140 | 跨锁记录 + app.select 换锁 | **无**（ios27 Records 只有 LedgerScope：全部/开锁/告警/失败） | 缺失 |
| 凭证搜索 / 最近搜索 / 空结果兜底 | App/UI/CredentialActions.swift:123-204 | 搜索框 + 搜索历史 + 搜索兜底 | **无**（Keys 目录 search 0 命中） | 缺失 |
| 凭证按成员分组视图 | App/UI/CredentialActions.swift:349-408；App/UI/CredentialsView.swift:34 | 按 owner 分 Section | **无**（CredentialStudioScreen.swift:58-60 仅排序，不分组） | 缺失 |
| 指纹重录替换 | App/UI/FpDetailStudio.swift:12,65-72 | FpStudio(prefillReplace:) sheet | **无**（ios27 relink/重录 0 命中） | 缺失 |
| 临时码提前失效滑杆 | App/UI/PwdDetailStudio.swift:163-196 | 0–120 分钟本机提示滑杆 | **无**（earlyExpireMin 仅 Engine） | 缺失 |
| OTP 防窥挡片 | App/UI/CredentialOtp.swift:86-108 | 长按揭开、双击切字号 | **无**（ZotpScreen.swift 无 shield） | 缺失 |
| 蓝牙钥匙串「查看已写入的钥匙」 | App/UI/DongleView.swift:156-167,286-298 | HardwareService.dongleKeys | **无**（ios27 dongleKeys 仅 Engine 定义） | 缺失 |
| 蓝牙钥匙串「写入未知/假钥匙」 | App/UI/DongleView.swift:229-240,315-330 | writeFaultDongleKey | **无**（writeFaultDongleKey 仅 Engine） | 缺失 |
| 蓝牙钥匙串「从本机解绑」 | App/UI/DongleView.swift:254-267 | DB.removeDongle | **无**（removeDongle 仅 Engine） | 缺失 |
| 备份「存到 iCloud 云盘 / 本机」+「从文件选择」 | App/UI/BackupView.swift:55-82,173-180,218-224 | fileExporter / fileImporter | **无**（ios27 fileExporter 0 命中；fileImporter 仅 DFU） | 缺失 |
| 设置页内搜索 + 五组筛选 | App/UI/SettingsView.swift:17,65,226-269；App/Core/SettingsGroups.swift:18-78 | 搜索命中直跳 / 分组 chip | **无**（Settings 目录 搜索/SettingsGroup 0 命中） | 缺失 |
| 外观 13 个控件 | App/UI/SettingsAppearance.swift:10-241 | 品牌色/自定义色/圆角/行高/时间线/数字字体/指标位/条数/开场策略/长按时长/双击防抖/夜间免扰/纯黑/活泼档 | **部分**（ios27 AppearanceScreen.swift 只有主题/密度/动效/时间/快捷格/恢复默认） | 缺失（逐项见 §5） |
| 应用锁「更改/关闭本机密码、更改/清除胁迫码」前验证原密码 | App/UI/SettingsView.swift:372-466 | promptOldPasscode 先验旧码 | **无**（SecurityScreen.swift:88-96,152-161 直接开 PasscodeSheet；SettingsParts.swift:283-296 不验旧码） | 缺失 |
| 锁档案「设为启动默认锁」「选择开锁 PIN」 | App/UI/LockProfileView.swift:81-102,177-186；App/LockKeeperApp.swift:410-416 | 默认锁影响冷启动；PIN 影响 cmd04 | **有入口但无效果**（ios27 写 kf_default_mac/kf_chosen_pin_，全仓无读点；见 §7-B4） | 伪入口 |

---

## 3. 功能点对账表（按模块，含已覆盖项与缺口）

> 「可点」列的含义：从 App 根页面能否点到；「结论」列区分「已覆盖 / 降级 / 缺失 / 伪入口」。

### A. BLE / ZK / 安全引擎（原 App/Core + App/Services）

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| 0x87 帧组装 / 0x88 EKey 包络 / KLV | App/Core/ZKProtocol.swift:15-332、ZKCmdBuilder.swift:12 | Engine/ZKProtocol.swift、Engine/ZKCmdBuilder.swift | 引擎（页面间接） | 已覆盖：SHA-256 逐字节一致 |
| 命令 03/04/05/08/0A/0B/0E/12/13/14/15/16/18/19/20/21/22/23/24/25 | App/Services/LockService*.swift、App/Core/DefendKit.swift | Engine/LockService*.swift、DefendKit.swift | 大多有页面入口（见下） | 命令引擎已覆盖；交互层见设备/凭证页缺口 |
| DFU / 固件包校验 / 降级闸 | App/Services/DFUKit.swift:89-414、ZipKit.swift:27-180 | Engine/DFUKit.swift、Engine/ZipKit.swift + Features/Door/DFUScreen.swift:9 | 是（设置/锁设置→固件升级） | 已覆盖 |
| 蓝牙扫描 / 20B 分片 / 断链自愈 | App/Services/BLEService.swift:21、BLEDelegates.swift:6 | Engine/BLEService.swift、BLEDelegates.swift + Features/Door/LinkSense.swift:13 | 是（Door 顶部连接感知） | 已覆盖 |
| 连接感知：预热/重连阶梯/RSSI 历史/蓝牙横幅 | App/Core/LinkSenseKit.swift、LinkSenseReconnect.swift | Features/Door/LinkSense.swift:13-293 + DoorScreen:19 | 是（Door 顶部） | 已覆盖 |
| 应用锁冷启动门禁 / 生物识别 / 胁迫码 | App/Core/AppLock.swift:20、App/UI/LockScreen.swift:14 | Engine/AppLock.swift + LockKeeperApp.swift:127-254 | 是（冷启动 LockGateScreen） | 已覆盖（但更改/关闭密码流程缺旧码验证，见 #34） |

### B. 设备页 / 开锁（原 App/UI/DeviceHome*、UnlockDial*）

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| 设备页 Hero 卡（身份/三态胶囊/信号/RSSI/4 指标/钥匙有效期） | DeviceHomeBlocks.swift:48-195 | DoorScreen.swift:141-196（仅名称/状态文本/预计可用） | 是（但信息被删） | 降级 |
| 异常提醒卡（密钥未绑定/超30天未校时/低电/2h 到期） | DeviceHomeBlocks.swift:196-247 | 无 | 否 | 缺失 #5 |
| 最近开门模块（最近 N 条/成员归属/点按筛选/查看全部） | DeviceHomeQuick.swift:231-292 | DoorScreen.swift:199-226 仅今日面积图 | 否 | 缺失 #6 |
| 下拉重扫 | DeviceHomeView.swift:57-59,271-289 | 无 .refreshable | 否 | 缺失 #7 |
| 开锁圆盘（按住确认/上滑/围栏/双击/自动重试） | UnlockDial.swift:32-38,203-370 | DoorScreen.swift:94-107 普通 Button；Dial.swift 组件未被使用（Dial( 0 命中） | 只能轻点 | 缺失 #12 |
| 开锁进度三段/取消等待/退避重试/失败清单/再试一次 | DeviceHomeBlocks.swift:351-465,495-519；LockKeeperApp.swift:419-479 | DoorScreen.swift:109-124 只有失败文案 | 否 | 缺失 #11 |
| 自动上锁倒计时 | DeviceHomeBlocks.swift:377-385,480-493 | 无 | 否 | 缺失 #10 |
| 30 秒二次开锁应用锁闸 | DeviceHomeSupport.swift:120-219 | 无 | 否 | 缺失 #2 |
| 快捷操作网格（3 列/大格 2 列/待添加指纹/长按编辑） | DeviceHomeQuick.swift:6-92 | DoorScreen.swift:252-280 纵向列表；QuickPoolEditSheet.swift:6-83 仅勾选 | 部分（编辑链接） | 缺失 #9 |
| 设备页模块排序与显隐 | DeviceHomeView.swift:77,354-460 | 无；Engine/DevModules.swift 有引擎无 UI | 否 | 缺失 #3 |
| 设备页空态「从备份恢复」 | DeviceHomeView.swift:178-194 | DoorScreen.swift:384-401 只有添加 | 否 | 缺失 #8 |
| 锁信息名片（进页自动校时/连接环境/电量采样图/固件服役/链路验证/容量） | DeviceInfoView.swift:6-307 | 无页面；LockSettingsScreen.swift:96-136 只保留部分只读字段 | 否 | 缺失 #1 |

### C. 凭证（原 App/UI/Credentials*、Pwd*、Fp*、Credential*）

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| 凭证台账 CRUD / 类型分段 / 到期状态 | CredentialsView.swift:16-130、CredentialActions.swift:51-120 | Features/Keys/KeysScreen.swift:9-494 | 是（底部「凭证」） | 已覆盖（简化） |
| 凭证搜索 / 最近搜索 / 空结果 | CredentialActions.swift:123-204 | 无（Keys 0 命中） | 否 | 缺失 #13 |
| 按成员分组视图 | CredentialActions.swift:349-408 | 无；Studio 仅排序 | 否 | 缺失 #14 |
| 新增密码/指纹/临时码（四步向导） | PwdStudio.swift:7、PwdStudioSteps.swift:6-442、FpStudio.swift:62、TempCodeStudio.swift:7 | Features/Keys/KeyCreateScreen.swift:9-270 + KeyCreateParts.swift | 是（Keys→新增凭证） | 已覆盖（指纹录入 cmd13/14 真实） |
| 密码随机生成 / 密码强度 / 重复检测 | PwdStudioSteps.swift:125-199 | KeyCreateParts.swift:134-207 | 是 | 已覆盖 |
| 密码详情：打码/分段复制/语音播报 | PwdDetailStudio.swift:49-101 | KeyDetailScreen.swift:96-156（打码/分段复制；无语音播报） | 部分 | 降级（语音播报缺） |
| 到期预警五档 | PwdDetailStudio.swift:103-162 | CredentialStudioParts.swift:9-74（仅工作室入口，不在详情页） | 是（需先到工作室） | 降级（详情页入口缺失） |
| 提前失效滑杆 | PwdDetailStudio.swift:163-196 | 无 UI（Engine only） | 否 | 缺失 #17 |
| 指纹详情/重录替换/冗余提示 | FpDetailStudio.swift:12,36-94 | KeyDetailScreen.swift:96-205（无重录） | 否 | 缺失 #16 |
| OTP 防窥挡片/大字双击 | CredentialOtp.swift:65-120 | ZotpScreen.swift:83-135（大字有，挡片无） | 部分 | 缺失 #18 |
| 单条凭证改归属（行菜单） | CredentialListRows.swift:154-220 | 无单条；仅工作室批量移交 | 部分（批量） | 降级（仅批量；单条菜单缺失，未计入 N） |
| 凭证 Tab 近 7 日到期角标 | RootTabs.swift:19-20；CredentialOrgState.swift:94-101 | VFloatingTabBar 无 badge；expiringSoonCount 0 调用 | 否 | 缺失 #15 |
| 凭证包导出（AES 信封 + 口令单列） | CredentialsView.swift:373-391、CredentialOrgBatch.swift:86 | CredentialStudioScreen.swift:340-360（导出包/口令） | 是 | 已覆盖 |
| 版本历史/回收站/星标/批量延期/停用/前缀/移交 | CredentialCenterView.swift:16-89、CredentialOrg*.swift | CredentialStudioScreen.swift:13-499 + CredentialStudioParts.swift | 是（Keys→凭证工作室） | 已覆盖（批量） |

### D. 记录（原 App/UI/Records*）

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| 记录时间线 / 日分组 / 搜索筛选 | RecordsView.swift:20、RecordsTimeline.swift:14、RecordsFilters.swift:105-140 | Features/Records/RecordsScreen.swift:9-702 | 是（底部「记录」） | 已覆盖（单锁范围） |
| 自然语言/加减号检索/统计 | RecordSearch.swift:274-541、StatsKit.swift:8 | RecordsStudioScreen.swift:15-311 | 是（记录→工作室） | 已覆盖 |
| 告警类型多选筛选 | RecordsSheets.swift:9-62 | 无（仅布尔「只看告警」） | 否 | 缺失 #4 |
| 记录详情 / 同日上下文 / 备注标旗处置 | RecordsTimeline.swift:14-500、RecordSearch.swift:24-110 | RecordDetailScreen.swift:8-367 | 是（点记录行） | 已覆盖（无上下条翻页，降级） |
| 跨锁范围（当前锁/全部锁）与换锁 | RecordsFilters.swift:105-140 | 无 | 否 | 缺失 #23 |
| CSV/成员名册/单条分享卡/上周小结 | ExportShares.swift:13-100、RecordsView.swift:216-400 | RecordExportScreen.swift:80-453 | 是（记录→导出） | 已覆盖 |
| 原始帧 hex 导出 | RecordsRows.swift:6、FrameRedact.swift:11 | RecordsStudioScreen.swift:253-278 | 是 | 已覆盖 |

### E. 成员 / 家庭（原 App/UI/Member*）

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| 成员增删改查/建档向导 | MembersView.swift:5、MemberWizard.swift:7-204 | HouseholdScreen.swift:22、MemberCreateScreen.swift:10-312 | 是（Door→成员→新建） | 已覆盖（初始码伪实现见 §7-B3） |
| 成员 360（角色/权限矩阵/档案/凭证/摘录） | MemberDetail.swift:7-350 | MemberDetailScreen.swift:8-394 | 是 | 已覆盖 |
| 成员归档/恢复 | MemberWizard.swift:305 | MemberArchiveScreen.swift:9 | 是 | 已覆盖 |
| 同名合并 | MemberWizard.swift:207 | MemberMergeSheet.swift:6、MemberMergeKit.swift | 是 | 已覆盖 |
| 移交/借用/家政窗/轮值/关怀/欢迎语 | MemberHub.swift:70-370 | MemberOpsScreen.swift:10-414 | 是（家→成员流转） | 已覆盖 |
| 访客虚拟分组 | MemberCenterView.swift:280-312 | HouseholdScreen.swift:198-204（点击只到 records，无 visitor filter） | 部分 | 缺失 #25 |
| 成员一键呼叫（电话） | MembersView.swift:69-103,125-135 | 无 tel://（0 命中）；无电话字段 | 否 | 缺失 #24 |
| 成员常用锁字段 | MemberDetail.swift:294-308 | 无（commonLocks 仅 Engine） | 否 | 缺失（低优先级） |

### F. 设置 / 外观 / 系统

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| 设置主页分组 | SettingsView.swift:7-99 | SettingsScreen.swift:9-365 | 是（底部「设置」） | 已覆盖（分组名称不同） |
| 设置页内搜索 + 五组筛选 | SettingsView.swift:17,65,226-269、SettingsGroups.swift:18-78 | 无 | 否 | 缺失 #26 |
| 通知权限状态/去系统设置 | SettingsSections.swift:182-198 | 无（NotifyAuth 仅 Engine） | 否 | 缺失 #27 |
| 时间制式/显示秒/两行日期 | SettingsSections.swift:8-28 | AppearanceScreen.swift:110-168、TimeDisplay.swift:8 | 是 | 已覆盖 |
| 开锁偏好（按住确认/误触围栏/手势/双击直开/失败重试/圆盘尺寸） | SettingsSections.swift:34-74、UnlockDialState.swift:6-7 | SecurityScreen.swift:214-237、AccessibilityScreen.swift:81-118 | 有开关但**无消费者** | **伪入口（§7-B1）** |
| 外观主题（四档含纯黑） | SettingsAppearance.swift:10-18 | SettingsModel.swift:14-27 仅三档 | 部分 | 缺失 #33（纯黑） |
| 品牌色六套 + 自定义强调色 | SettingsAppearance.swift:20-37,118-134 | 无 | 否 | 缺失 #28 |
| 圆角档位 | SettingsAppearance.swift:39-46 | 无 | 否 | 缺失 #29 |
| 凭证行高 / 时间线行距 / 最近开门条数 | SettingsAppearance.swift:71-86,108-115 | 无 | 否 | 缺失 #30 |
| 主控读数数字字体 / 指标位显隐 / 记录页开场过滤 | SettingsAppearance.swift:90-105,138-148 | 无（HeroStats 0 命中） | 否 | 缺失 #31 |
| 长按确认时长 / 双击防抖 / 夜间免扰 | SettingsAppearance.swift:196-208,222-241 | 无（kf_ax_hold/kf_dbltap_guard/kf_quiet_night 0 UI） | 否 | 缺失 #32 |
| 动效强度「活泼」档 | SettingsAppearance.swift:51-58 | SettingsModel.swift:48-60 仅两档 | 部分 | 缺失 #33 |
| 应用锁设置/更改/关闭、胁迫码 | SettingsView.swift:372-466 | SecurityScreen.swift:10-260、SettingsParts.swift:220-297 | 是 | 部分：**缺旧密码验证**（#34） |
| 只读试验模式 | SettingsSections.swift:199-221 | SettingsScreen.swift:229-233 + TrialGuard.swift | 是 | 已覆盖 |
| 关于（累计开锁/构建/版本彩蛋） | SettingsSections.swift:256-319 | AboutScreen.swift:9-145 | 是 | 已覆盖 |
| 锁档案（昵称/符号/色标/分组/备注/电池/默认锁/PIN） | LockProfileView.swift:5-238 | LockProfileScreen.swift:10-290 | 是（锁设置→锁档案） | 部分：**默认锁/PIN 假开关**（§7-B4） |

### G. 备份 / 硬件 / DFU

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| 全量备份生成（CryptoBox/canonical） | BackupView.swift:87-184 | BackupScreen.swift:74-155 | 是（设置→备份与恢复） | 已覆盖（文本生成） |
| 备份文件导出到 iCloud/本机、从文件导入 | BackupView.swift:55-82,173-180,218-224 | 无（fileExporter 0） | 否 | 缺失 #22 |
| 备份工作室（WebDAV/多份/迁移/自检） | BackupStudioKit.swift:17-400 | BackupStudioScreen.swift:16-481 | 是（设置→备份工作室） | 已覆盖 |
| 蓝牙钥匙串写钥/撤销 | DongleView.swift:203-251,300-344 | HardwareScreen.swift:197-224 | 是（设置→钥匙串/硬件） | 已覆盖（写/撤销） |
| 钥匙串看已写入/假钥匙/解绑/手动读状态 | DongleView.swift:156-167,229-240,254-284 | 无 | 否 | 缺失 #19-#21 |
| DFU / 固件包导入/进度/禁止退出 | DFUView.swift:11、DFUKit.swift:89 | DFUScreen.swift:9-270 | 是 | 已覆盖 |

### H. 跨系统 / 通知 / 深链

| 功能点 | 原文件:行 | 新文件/页面 | 用户能否点到 | 结论 |
|---|---|---|---:|---|
| kf:// device/credentials/records/settings 深链 | Route.swift:24、LockKeeperApp.swift:115-134 | LockKeeperApp.swift:54-78 | 系统入口（外链） | 已覆盖（基础四 host） |
| 通知授权 + 点通知定位凭证 | QuickActions.swift:11-64 | Engine/QuickActions.swift:11-67 + LockKeeperApp | 系统入口 | 已覆盖 |
| 凭证 Tab 到期角标 | RootTabs.swift:19-20 | VFloatingTabBar 无 badge | 否 | 缺失 #15 |
| 快速操作池（编辑/智能排序/再开一次） | QuickPool.swift:26-160、DeviceHomeQuick.swift:6-166 | DoorScreen.swift:252-308 + QuickPoolEditSheet.swift:6-83 | 是（但 3 个快捷动作指向错误页，§7-B6） | 部分 |

---

## 4. 重点：原 App 有页面/流程、ios27 没有对应路由的清单（汇总）

### 4.1 整页缺失（无 Dest、无 NavigationStack）

| 原页面 | 原文件:行 | ios27 路由检索结果 | 影响 |
|---|---|---|---|
| DeviceInfoView | App/UI/DeviceInfoView.swift:6（28 个 Destination 之一，见 Destination.swift:16） | grep DeviceInfo ios27 = 6，全部是注释/Engine，无 Dest、无 View | 锁信息名片整页；进页自动校时、连接环境、电量采样图、固件服役、链路验证、容量读数均无入口 |
| UnlockGateView | App/UI/DeviceHomeSupport.swift:122（Destination.swift:36） | grep showGate/UnlockGate ios27 = 0 | 30 秒内第二次开锁需本机密码的应用锁闸整页；当前 ios27 可连续点圆盘无限开锁 |
| moduleOrderSheet（非 Destination，设备页 sheet） | App/UI/DeviceHomeView.swift:77,354-460 | grep showModuleOrder/devOrder ios27 = 0；DevModuleStore 无引用 | 设备页模块排序/显隐/快捷格勾选/恢复默认整张面板 |
| AlarmKindsSheet（记录页 sheet） | App/UI/RecordsSheets.swift:9-62 | grep AlarmKinds ios27 = 0；RecordsStudioScreen.swift:174 只有布尔 | 告警类型多选筛选 |

### 4.2 有页面但关键子页面/子流程缺失

| 原页面 | 缺失的子流程（原文件:行） | ios27 对应文件 | 点不到的证据 |
|---|---|---|---|
| BackupView | 文件导出/导入选文件（BackupView.swift:55-82,173-180,218-224） | BackupScreen.swift | fileExporter 0；fileImporter 只在 DFU |
| DongleView | 查看已写入钥匙/假钥匙/解绑/手动读状态（DongleView.swift:156-167,229-240,254-284） | HardwareScreen.swift | dongleKeys/writeFaultDongleKey/removeDongle 均仅 Engine 定义 |
| MembersView | 电话字段/一键呼叫（MembersView.swift:69-103,125-135） | HouseholdScreen.swift / MemberDetailScreen.swift | tel:// 0；无 phone 字段 |
| MemberCenterView | 访客卡按访客过滤（MemberCenterView.swift:280-312） | HouseholdScreen.swift:198-204 | action 只 router.request(.dest(.records)) |
| SettingsView | 设置内搜索/分组（SettingsView.swift:17,65,226-269） | SettingsScreen.swift | 搜索 0，SettingsGroup 0 |
| DeviceHomeView | 模块排序 / 最近开门 / 异常卡 / 空态备份 / 倒计时（见 §3-B） | DoorScreen.swift | 无对应 View/VStack 分支 |
| CredentialsView | 搜索 / 按成员分组（见 §3-C） | KeysScreen.swift | search 0；无 member section |
| RecordsView | 跨锁范围/换锁（RecordsFilters.swift:105-140） | RecordsScreen.swift | 换锁 0、全部锁 0；LedgerScope 不是锁范围 |
| LockProfileView | 启动默认锁/PIN 选择（LockProfileView.swift:81-102,177-186） | LockProfileScreen.swift:247-288 | 仅写 kf_default_mac/kf_chosen_pin_，无读点（defaultMac 只在 LockStats.orderedDevices，而该方法无 UI 调用） |
| FpDetailStudio | 重录替换（FpDetailStudio.swift:12,65-72） | KeyDetailScreen.swift | relink/重录 0 |
| PwdDetailStudio | 提前失效滑杆（PwdDetailStudio.swift:163-196） | KeyDetailScreen.swift | earlyExpireMin 仅 Engine |
| CredentialOtp | 防窥挡片（CredentialOtp.swift:86-108） | ZotpScreen.swift | 无 shield 状态 |

### 4.3 Alert / Sheet / 空态 / 错误态对照

| 类型 | 原 App | ios27 | 结论 |
|---|---|---|---|
| Alert | 删除设备「键入锁名」（SettingsView.swift:350-370） | SettingsScreen.swift:369-435 有同形 sheet | 有，但**删除动作只 app.lock = nil**（§7-B2） |
| Alert | 清空全部密码（LockSettingsView.swift:168-185） | LockSettingsScreen.swift:50-57,251-270 有 | 已覆盖 |
| Alert | 应用锁原密码验证（SettingsView.swift:397-409） | 无（PasscodeSheet 直接保存） | 缺失 #34 |
| Sheet | 告警类型多选（RecordsSheets.swift:9） | 无 | 缺失 #4 |
| Sheet | 模块排序（DeviceHomeView.swift:77） | 无 | 缺失 #3 |
| Sheet | 锁信息名片（LockSettingsView.swift:75 NavigationLink） | 无 | 缺失 #1 |
| Empty | 设备页无锁「从备份恢复」（DeviceHomeView.swift:178-194） | 只有添加（DoorScreen.swift:384-401） | 缺失 #8 |
| Empty | 记录/凭证空态给下一步（CredentialsView.swift:53-58、RecordsView.swift:45-50） | 有（KeysScreen.swift:389-425、RecordsScreen.swift:560-580） | 已覆盖 |
| Error | 开锁失败可反复重试/排查清单（DeviceHomeBlocks.swift:403-427） | 只有静态错误文案 | 缺失 #11 |
| Error | 网关配网失败回显（GatewayView.swift:88-94） | GatewayScreen.swift:243-247 | 已覆盖 |
| Error | DFU 校验失败/降级闸（DFUView.swift:229） | DFUScreen.swift:202-219 | 已覆盖 |

---

## 5. 确认遗漏 34 项（逐项 + 修复建议）

> 编号即 §8 的 N 项编号。证据全部来自上表的原文件:行与 ios27 检索结果。

| # | 遗漏功能点 | 原实现（文件:行） | ios27 现状（缺什么/证据） | 修复建议 |
|---:|---|---|---|---|
| 1 | 锁信息名片页 | App/UI/DeviceInfoView.swift:6-307；Destination.swift:16 | 无 Dest/无 View；DeviceInfo 只在注释出现 | 新增 Dest.deviceInfo + DeviceInfoScreen：接 LockStatus 的 Boot/键盘/容量/锁钟，BatteryCare.samples 采样图，LockArchive.meta.verifiedAt，进页 syncTime() 自动校时；从 LockSettingsScreen overview 底部进入  **✅ 已修复** · `App/Features/Door/DeviceInfoScreen.swift:9` |
| 2 | 30 秒内二次开锁应用锁闸 | App/UI/DeviceHomeSupport.swift:122-219；App/LockKeeperApp.swift:380-384 | showGate/UnlockGate 0 命中；AppModel.runUnlockChain 无 30 秒判定 | 在 AppModel 记录 lastUnlockSuccessAt；DoorScreen 点击圆盘前若 DB.hasPasscode 且 <30s 则弹出 UnlockGateScreen（密码+冷却），验证后调用 runUnlockChain  **✅ 已修复** · `App/Features/Door/UnlockGateScreen.swift:8` |
| 3 | 设备页模块排序与显隐面板 | App/UI/DeviceHomeView.swift:77,354-460 | DevModuleStore 仅 Engine；showModuleOrder/devOrder 0 命中 | 新增 Dest.moduleOrder 或 DoorScreen sheet：读 DevModule.allCases/DevModuleStore.hidden，三槽排序写 kf_dev_order；把快捷格勾选/恢复默认一并搬回  **✅ 已修复** · `App/Features/Door/ModuleOrderSheet.swift:8` |
| 4 | 记录告警类型多选筛选 | App/UI/RecordsSheets.swift:9-62 | AlarmKinds 0；只有 alarmOnly bool | 在 RecordsStudioScreen 增加 Set<Int> alarmKinds 多选 sheet，读 StatsKit.alarmTypes，写回 LedgerFilter  **✅ 已修复** · `App/Features/Records/AlarmKindsSheet.swift:8` |
| 5 | 设备页异常提醒卡 | App/UI/DeviceHomeBlocks.swift:196-247 | DoorScreen.swift 无 attention 分支 | 在 DoorScreen gauge 前插入提醒卡：密钥未绑定、staleSync、低电阈值、CredentialOrg.dueSoonPwds 四类  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:152` |
| 6 | 设备页最近开门模块 | App/UI/DeviceHomeQuick.swift:231-292 | DoorScreen.swift:199-226 仅今日面积图 | 增加「最近开门」列表：app.entries 最近 N 条（kf_recent_count），行支持按 whoId 跳记录筛选，标题右侧「查看全部」→ records  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:817` |
| 7 | 设备页下拉重扫 | App/UI/DeviceHomeView.swift:57-59,271-289 | DoorScreen 无 .refreshable | 给 DoorScreen ScrollView 加 .refreshable { await link.preheat(); await app.refreshStatus() }，失败时按原版三档 toast（蓝牙未开/超时/信号值）  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:76` |
| 8 | 设备页空态「从备份恢复」 | App/UI/DeviceHomeView.swift:178-194 | DoorScreen.swift:384-401 只有添加门锁 | 在 noLockBlock 增加第二按钮→router.request(.dest(.backup))  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:966` |
| 9 | 快捷操作网格（含待添加指纹格/大格/长按编辑） | App/UI/DeviceHomeQuick.swift:6-92 | DoorScreen.swift:252-280 纵向列表；无待添加指纹格；kf_bigtile 无消费 | 改回 LazyVGrid(columns: bigTile ? 2 : 3)；DB.listFps().isEmpty 时追加虚线「待添加指纹」格→keyCreate；长按任一格打开 QuickPoolEditSheet  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:709` |
| 10 | 自动上锁倒计时 | App/UI/DeviceHomeBlocks.swift:377-385,480-493 | 无任何倒计时状态 | AppModel 开锁成功后按 DB.tailgate(mac)?.interval ?? 6 起 Task，DoorScreen 显示「约 N 秒后自动上锁」  **✅ 已修复** · `App/Shell/AppModel.swift:312` |
| 11 | 开锁失败处理链（进度/取消/退避/清单/再试） | App/UI/DeviceHomeBlocks.swift:351-465,495-519；LockKeeperApp.swift:419-479 | DoorScreen.swift:109-124 仅失败文案 | 将 runUnlockChain 扩展为 3 次自动重试（2s/5s，超时不重试）、failStreak、phase 0..3 进度条、失败后显示三项自查清单与「再试一次」；Dial 组件已具备 phase 显示，可复用  **✅ 已修复** · `App/Shell/AppModel.swift:231` |
| 12 | 开锁手势确认（按住/上滑/围栏/双击/自动重试） | App/UI/UnlockDial.swift:32-38,203-370；UnlockDialState.swift:6-7 | DoorScreen 普通 Button；Dial( 0 使用；kf_fence/kf_tap_direct 0 命中 | 用 Dial/UnlockDial 替换 VGauge 按钮；实现 DragGesture(minimumDistance:0) 的 hold/fence/swipe；kf_hold_confirm/kf_fence/kf_tap_direct/kf_auto_retry 均要有读点  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:390` |
| 13 | 凭证搜索 / 最近搜索 / 空结果兜底 | App/UI/CredentialActions.swift:123-204 | grep search ios27 Features/Keys = 0 | 在 KeysScreen 顶部加 TextField 与 CredentialOrg.searchHistory()，按名称/备注/别名/归属过滤，空结果显示「没有找到」+按成员重搜  **✅ 已修复** · `App/Features/Keys/KeysScreen.swift:17` |
| 14 | 按成员分组视图 | App/UI/CredentialActions.swift:349-408；CredentialsView.swift:34 | KeysScreen 无 member section；groupMode 只影响工作室排序 | 把 CredentialOrg.groupMode == .owner 作为 KeysScreen 分支：按 DB.members() 分 Section，未归属单独一组；CredentialStudioScreen 保留排序  **✅ 已修复** · `App/Features/Keys/KeysScreen.swift:33` |
| 15 | 凭证 Tab 近 7 日到期角标 | RootTabs.swift:19-20；CredentialOrgState.swift:94-101 | VFloatingTabBar 无 badge API；expiringSoonCount 0 调用 | VTabItem 加 badge: Int?，在 Shell 用 CredentialOrg.expiringSoonCount(macs: DB.keychains().map(\.mac)) 驱动；或至少在 Keys 图标右上角画红点  **✅ 已修复** · `App/Design/V7/V7Components.swift:626` |
| 16 | 指纹重录替换 | App/UI/FpDetailStudio.swift:12,65-72 | KeyDetailScreen 无重录；relink 0 | KeyDetail 指纹分支增加「重录一枚替换它」→ 打开 KeyCreateScreen 的指纹模式并预填 owner/replaceBatch；成功后 deleteFingerprint 旧批次  **✅ 已修复** · `App/Features/Keys/KeyDetailScreen.swift:406` |
| 17 | 临时码提前失效滑杆 | App/UI/PwdDetailStudio.swift:163-196 | earlyExpireMin 仅 Engine | KeyDetail 临时码分支加 Slider 0–120 分钟，读写 CredentialOrg.earlyExpireMin/setEarlyExpireMin，并显示「只在本页提示，不改锁端」  **✅ 已修复** · `App/Features/Keys/KeyDetailScreen.swift:336` |
| 18 | OTP 防窥挡片 | App/UI/CredentialOtp.swift:86-108 | ZotpScreen 无 shield 状态 | ZotpScreen 加 @State otpShieldOn + otpReveal，长按揭开/松手复位，contextMenu 开关；默认关  **✅ 已修复** · `App/Features/Keys/ZotpScreen.swift:152` |
| 19 | 蓝牙钥匙串「查看已写入的钥匙」+「读取状态」 | App/UI/DongleView.swift:156-167,272-298 | HardwareService.dongleKeys 与 readDongleState 均无手动 UI（readDongleState 只在写钥后自动调用） | HardwareScreen 每台钥匙串增加「读取状态」与「查看已写入的钥匙」两个按钮，分别调 readDongleState/dongleKeys，显示电量/钥匙数与 MAC+锁名  **✅ 已修复** · `App/Features/Settings/HardwareScreen.swift:284` |
| 20 | 蓝牙钥匙串「写入未知/假钥匙」 | App/UI/DongleView.swift:229-240,315-330 | writeFaultDongleKey 0 UI | 每台钥匙串提供「写入一把未知钥匙（随机 PIN，永久）」按钮，调 HardwareService.writeFaultDongleKey，文案说明开不了锁  **✅ 已修复** · `App/Features/Settings/HardwareScreen.swift:316` |
| 21 | 蓝牙钥匙串「从本机解绑」 | App/UI/DongleView.swift:254-267 | DB.removeDongle 0 UI | 钥匙串详情底部加 destructive「从本机解绑」；只删本机记录，提示实体钥匙仍有效  **✅ 已修复** · `App/Features/Settings/HardwareScreen.swift:332` |
| 22 | 备份文件导出/导入 | App/UI/BackupView.swift:55-82,173-180,218-224 | fileExporter 0；fileImporter 仅 DFU | BackupScreen 生成后加「存到文件」fileExporter；导入区加「从文件选择」fileImporter，复用 BackupDoc/parsePreview  **✅ 已修复** · `App/Features/Settings/BackupScreen.swift:47` |
| 23 | 记录跨锁范围与换锁 | App/UI/RecordsFilters.swift:105-140 | 换锁/全部锁 0；LedgerScope 不是锁范围 | RecordsScreen 顶部加范围 segmented（当前锁/全部锁）+ Menu 换锁（DB.currentMac），全部锁时 RecordsSource.load 合并各锁缓存  **✅ 已修复** · `App/Features/Records/RecordsScreen.swift:773` |
| 24 | 成员一键呼叫/电话字段 | App/UI/MembersView.swift:69-103,125-135 | tel:// 0；MemberDetail 无 phone 字段 | Member 增加 phone 编辑（DB.setMemberInfo），成员行 contextMenu 加「呼叫」→ tel://（清洗非数字，<3 位不给）  **✅ 已修复** · `App/Features/Household/MemberDetailScreen.swift:364` |
| 25 | 访客卡按访客过滤记录 | App/UI/MemberCenterView.swift:280-312 | HouseholdScreen.swift:198-204 只跳 records | 增加 RecordsRoute 的 visitor 过滤上下文（owner == nil && event.contains("临时")），点击后 records 按该条件过滤并显示清除  **✅ 已修复** · `App/Features/Records/RecordsScreen.swift:787` |
| 26 | 设置页内搜索 + 五组筛选 | App/UI/SettingsView.swift:17,65,226-269；SettingsGroups.swift:18-78 | Settings 目录 搜索/SettingsGroup 0 | SettingsScreen 顶部加搜索框，命中滚动到节/打开子页；加 5 组 chip（daily/keys/data/look/help），节 filter 与搜索并用  **✅ 已修复** · `App/Features/Settings/SettingsScreen.swift:122` |
| 27 | 通知权限状态行 | App/UI/SettingsSections.swift:182-198 | NotifyAuth 仅 Engine；设置页无行 | SettingsScreen 工具区加条件行：NotifyAuth.isOffFor(status) 时显示「通知权限 · 到期提醒不会送达」，点击 UIApplication.openSettingsURLString  **✅ 已修复** · `App/Features/Settings/SettingsScreen.swift:420` |
| 28 | 品牌色六套 + 自定义强调色 | App/UI/SettingsAppearance.swift:20-37,118-134 | ios27 kf_accent 仅备份字段；无 picker/ColorPicker | SettingsStore 加 accent/customAccent，AppearanceScreen 加六色 chip + ColorPicker；T/V.C 用 accent 解析  **✅ 已修复** · `App/Features/Settings/AppearanceScreen.swift:86` |
| 29 | 圆角档位 | App/UI/SettingsAppearance.swift:39-46 | 无 kf_radius UI | SettingsStore.radius + AppearanceScreen 三档 chip；V.R 从 store 读  **✅ 已修复** · `App/Features/Settings/AppearanceScreen.swift:157` |
| 30 | 凭证行高 / 时间线行距 / 最近开门条数 | App/UI/SettingsAppearance.swift:71-86,108-115 | 无 kf_row_h/kf_tl_gap/kf_recent_count UI | 三项 Picker 加进 AppearanceScreen；Keys row / Records 时间线 / Door recent 模块消费  **✅ 已修复** · `App/Features/Settings/AppearanceScreen.swift:194` |
| 31 | 主控读数数字字体 / 指标位显隐 / 记录页开场过滤 | App/UI/SettingsAppearance.swift:90-105,138-148 | HeroStats 0；kf_digit_font 无 UI；无 QueryFilters.policy UI | AppearanceScreen 加字体/指标位 Picker；Records 使用 QueryFilters.policy 开页过滤  **✅ 已修复** · `App/Features/Settings/AppearanceScreen.swift:254` |
| 32 | 长按确认时长 / 双击防抖 / 夜间免扰 | App/UI/SettingsAppearance.swift:196-208,222-241 | kf_ax_hold/kf_dbltap_guard/kf_quiet_night 0 UI/消费 | AppearanceScreen 加 hold 时长 Picker（0.4/0.6/0.9/1.2/1.6）；双击防抖接入 PressableButtonStyle；夜间免扰加 Toggle，CareSchedule.quietOn  **✅ 已修复** · `App/Features/Settings/AppearanceScreen.swift:271` |
| 33 | 纯黑主题 / 动效「活泼」档 | SettingsAppearance.swift:10-18,51-58 | AppearanceTheme 3 档无 black；MotionTier 2 档无 lively | 加 case black（RootView.colorScheme 映射 .dark + 纯黑 surface token）；MotionTier 加 lively  **✅ 已修复** · `App/Features/Settings/SettingsModel.swift:20` |
| 34 | 应用锁更改/关闭前验证原密码（含胁迫码） | SettingsView.swift:372-466（promptOldPasscode） | SecurityScreen.swift:88-96,152-161 直接打开 PasscodeSheet；SettingsParts.swift:283-296 只校验新码 | PasscodeSheet 增加 oldCode 输入，DB.verifyPasscode 通过后才允许 setPasscode/setDuressCode；关闭密码/胁迫码同样先验证  **✅ 已修复** · `App/Features/Settings/SettingsParts.swift:298` |

---

## 6. 被 PARITY-V7 误判为「已覆盖」的条目

| PARITY-V7 行 | 原文结论 | 实测反证 | 判定 |
|---|---|---|---|
| L3 | 「新 App，124 个 Swift 文件」 | 实测 143 个（glob） | 数字过期 |
| L50 | 「钥匙串 41 / 43 / 44 ... 已覆盖」 | HardwareScreen.swift:197-224 只有扫描/写钥/撤销；dongleKeys（44 查询）、writeFaultDongleKey、removeDongle、readDongleState 手动入口均为 0 | **降级（4 个动作缺失）** |
| L82 | 「备份页生成 / 导入 UI 已覆盖（本次接真 CryptoBox + canonical + BackupStudio.restore）」 | 文本粘贴/复制有（BackupScreen.swift:157-253），但 fileExporter 0、fileImporter 0（DFU 除外） | **降级（文件 I/O 缺失）** |
| L111 | 「凭证搜索 / 筛选 已覆盖（简化）」 | Keys 目录 search 0 命中；只有 KeysFilter 类型分段。不是「简化」，是 **搜索整个没有** | **缺失** |
| L175 | 「设备首页：开锁盘 / 状态 / 最近记录 已覆盖」 | DoorScreen.swift:94-107 无手势、无进度；DoorScreen.swift:199-226 无最近记录列表；DeviceHomeQuick.swift:231-292 原模块未迁移 | **降级（关键交互/模块缺失）** |
| L184 | 「外观 / 主题 / 时间制式 / 快捷格偏好 已覆盖（本次接线）」 | AppearanceScreen.swift 只有主题(3档)/密度/动效(2档)/时间/快捷格/恢复；原 SettingsAppearance.swift 至少 13 个控件无 UI（品牌色/自定义色/圆角/行高/时间线/数字字体/指标位/条数/开场策略/长按时长/双击防抖/夜间免扰/纯黑） | **降级严重（13 控件缺失）** |
| L166 | 「只读试验模式 已覆盖（本次补持久化与真实绑定）」 | TrialGuard.set 与 trialGuardBinding 有；SettingsScreen.swift:229-233 与 SecurityScreen.swift:240-255 两处开关是真实绑定；这项成立 | 已覆盖（保留） |
| L155 | 「应用锁：本机密码 / 失败冷却 已覆盖（本次接 DB 摘要与真实校验）」 | 冷启动/生物识别/胁迫码有；**更改/关闭密码不验旧码**（SettingsParts.swift:283-296） | **部分降级（安全流程缺失）** |
| L173 | 「本地深链 kf://（device / records / credentials / settings） 已覆盖（基础四 host）」 | LockKeeperApp.swift:54-78 四 host 有；成立 | 已覆盖 |
| L185 | 「无障碍与操作辅助（AXPrefs / AuthKit） 已覆盖（本次接线）」 | 大字/大格 UI 有；dialSize/gestureMode/holdConfirm 无消费（§7-B1） | **伪入口** |
| L180 | 「安全模式说明页（A/B 模式） 已覆盖（本次接线）」 | SafeModeScreen.swift:9-160 有；成立 | 已覆盖 |
| L42 | 「命令 19 临时码开关 已覆盖（本次接线）」 | LockSettingsScreen.swift:157-177 有 toggle + Zotp 入口；成立 | 已覆盖 |
| L47 | 「命令 24 自动上锁 / 防尾随档 已覆盖（本次接线）」 | TailgateScreen.swift:9-150 有 2–6 秒 Picker + cmd24；成立 | 已覆盖 |
| L61 | 「连接感知 ... 已覆盖（本次接线）」 | LinkSense.swift:13-293 有预热/重连/RSSI 历史/蓝牙横幅；成立 | 已覆盖 |
| L108 | 「安卓配对二维码 已覆盖（本次接 AndroidPair.payload）」 | ShareToAndroidScreen.swift:12-212 有；成立 | 已覆盖 |
| L160 | 「里程碑：开锁 / 整理 / 备份计数 已覆盖（本次接开锁/备份计数）」 | Milestones.swift + AboutScreen.swift:39-66；recordOrganize 有调用；成立 | 已覆盖 |

---

## 7. 额外发现：伪入口 / 假开关 / 误实现（有入口但功能不成立）

> 这些不是「没有页面」，而是「页面上有按钮/开关，用户点了却没有对应功能」。按对抗审计标准，它们不能被算作「已覆盖」。

| 编号 | 问题 | 证据 |
|---|---|---|
| B1 | **开锁偏好开关全部是假开关**：holdConfirm/autoRetry 在 SecurityScreen.swift:214-237 写入 kf_*，但 DoorScreen 的 runUnlockChain 不读；dialSize/gestureMode 在 AccessibilityScreen.swift:81-118 写入，但 Dial.swift 未被使用（Dial( 0 命中），DoorScreen 固定 VGauge；kf_fence/kf_tap_direct 全仓 0 命中；kf_auto_retry 只在 SettingsModel.swift:197-200 有 getter/setter，无解锁链读点 | grep kf_hold_confirm 命中只在 Settings/Backup；grep kf_fence/kf_tap_direct = 0；grep Dial( = 0；DoorScreen.swift:94-107 普通 Button  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:448` |
| B2 | **删除设备不删数据**：DeleteDeviceSheet 的「删除本机数据」只执行 app.lock = nil，没有调用 DB.removeDevice（Engine 已有 StoreKeychain.swift:194）；删除后 keychain/台账/日志全部留在本机，页面即刻显示为「已删除」 | SettingsScreen.swift:417-420；StoreKeychain.swift:194-236；ios27 全仓 removeDevice 仅 Engine 定义  **✅ 已修复** · `App/Features/Settings/SettingsScreen.swift:590` |
| B3 | **成员向导初始临时码只写内存**：MemberCreateScreen.finish 只 app.keys.append(KeyItem(...))，id 以 "k-" + expires 生成；没有 DB.saveLedger、没有 app.addPassword、没有 cmd0A 下发。退出/刷新后 reloadKeys 从 DB.ledger 重建，向导码消失 | MemberCreateScreen.swift:279-301；AppModel.swift:115-154  **✅ 已修复** · `App/Features/Household/MemberCreateScreen.swift:280` |
| B4 | **锁档案的「启动默认锁」「开锁 PIN」是假设置**：LockProfileScreen.save 写 kf_default_mac/kf_chosen_pin_<mac>；但 AppModel.currentMac 只读 lock?.id ?? DB.preferredMac()（AppModel.swift:53），DB.preferredMac 读 kf_current_mac 不是 default；AppModel.runUnlockChain 调用 LockService.unlock(mac:) 未传 pinDec，chosenPin 0 命中 | LockProfileScreen.swift:260-288；AppModel.swift:53,198-230；StoreKeychain.swift:241-244；grep chosenPin = 0  **✅ 已修复** · `App/Shell/AppModel.swift:304` |
| B5 | **HardwareScreen「手机钥匙」错误跳到家页**：scopePanel 的「手机钥匙（发给成员）」行 action 为 router.request(.dest(.household))，但 Household 全仓无 mobileKey 入口（0 命中）。正确落点为 .mobileKey | HardwareScreen.swift:161-169；grep mobileKey Features/Household = 0  **✅ 已修复** · `App/Features/Settings/HardwareScreen.swift:222` |
| B6 | **快捷操作 3 个图标指向错误页面**：DoorScreen.runQuick 把 otp→.keyCreate（应为 .zotp），tailgate→.lockStatus（应为 .tailgate），safemode→.lockStatus（应为 .safeMode）；QuickPool 原版 quickDestination 对应 TempCodeStudio/TailgateView/SafemodeIntroView | DoorScreen.swift:282-308；QuickPool.swift:167-186（原）  **✅ 已修复** · `App/Features/Door/DoorScreen.swift:787` |
| B7 | **设置页 DFU「版本」值恒空**：SettingsScreen.pkgVersion 直接返回 ""，固件升级行右侧永远空白；原版 DFUView 显示包版本/锁内版本 | SettingsScreen.swift:316  **✅ 已修复** · `App/Features/Settings/SettingsScreen.swift:523` |
| B8 | **凭证「停用/恢复使用」实际是删除**：KeyDetailScreen 的 toggleDisabled 对密码调用 app.deletePassword、对指纹调用 app.deleteFingerprint（KeyDetailScreen.swift:309-319），不是把 disabled 置位；用户点「停用这枚凭证」后该凭证直接从锁端和本机台账消失 | KeyDetailScreen.swift:186-201,309-319；AppModel.swift:296-345  **✅ 已修复** · `App/Features/Keys/KeyDetailScreen.swift:327` |

---

## 8. 确认遗漏 N 项与修复优先级

### 8.1 数量

- **确认遗漏：34 项**（§5 表 1–34）。
- 按一级模块分布：设备/开锁 11 项（#1–#3、#5–#12）、凭证 6 项（#13–#18）、硬件/备份 4 项（#19–#22）、记录/成员 4 项（#4、#23–#25）、设置/外观 9 项（#26–#34）。
- 另有 **8 项伪入口/误实现**（§7-B1–B8），不计入 34，但按用户可见结果同样属于「功能不成立」。

### 8.2 修复顺序建议（按用户影响 / 风险）

1. **先修 4 个伪实现安全/数据问题**：B2 删除设备（数据不删 = 用户以为已清空但密钥还在本机）、B1 开锁偏好假开关（尤其「按住确认」失效 = 误触即开门）、B3 成员向导临时码（用户以为已发码但锁端没有）、B8 凭证「停用」实际是删除（误操作不可逆）。
2. **再补 4 个整页**：DeviceInfo（#1）、UnlockGate（#2）、moduleOrder（#3）、AlarmKinds（#4）。这四项在 PARITY-V7 中被直接跳过或误记为已覆盖，且都是「原 App 独立入口」。
3. **补设备页 8 个主模块**：#5 attention / #6 recent / #7 rescan / #8 backup empty / #9 quick grid / #10 countdown / #11 failure chain / #12 gestures；其中 #12 与 B1 共用一套 UnlockDial 接线，一次改完。
4. **补凭证页 6 项**：#13 search / #14 member group / #15 tab badge / #16 fp relink / #17 early expire / #18 OTP shield；其中 #13/#14 是日常高频入口。
5. **补硬件/备份 4 项**：#19 dongle 查看已写入的钥匙 / #20 写入未知钥匙 / #21 本机解绑 / #22 备份文件导出导入。
6. **补设置/外观 9 项**：#26 settings search / #27 notification / #28-#33 appearance（6 组，含 13 个控件子项） / #34 old passcode；建议先做 #34（安全）再做 #28-#33（纯偏好）。

### 8.3 验收口径（避免再次「127/127」）

- 每一项必须有：① 原文件:行；② ios27 的 Dest/sheet 入口或 grep 0 证据；③ 一个真实用户动作路径（如「设置 Tab → 备份与恢复 → 生成备份 → 存到文件」）；④ 动作后的可观察结果（写库键/锁端命令/页面跳转）。
- 「引擎同名文件存在」「按钮存在」「设置项能拨动」都不算覆盖；必须验证**写入有消费者、点击有结果**。本报告 §7 的 8 项就是典型反例。

---

## 9. 边界与未验证项

- 本机无 Swift/Xcode，无法编译或运行 ios27；本审计为静态代码/路径级，不替代真机/CI。
- BLE/DFU/网关/指纹的真实回执未验证；本报告只判断「入口/调用链是否存在」。
- 原 App 中有些注释标注的功能本身是死代码（例如 DeviceHomeView.swift:22-30 的 pageIndex/pageOrder 无渲染消费；SettingsAppearance.swift:47-49 的 Hero 纹理 Picker 体缺失）。本报告没有把这些原 App 自身未实现的东西算成 ios27 的遗漏，避免虚增项。
