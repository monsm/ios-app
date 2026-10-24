# iOS UI 层最小功能点清单

> 范围：`ios-app/App/UI` 下全部 **51 个 .swift**（26,411 行）
> 方式：只读源码逐个文件清点；不改任何 .swift
> 用途：判断「哪些功能点可以删 / 可以合并」

## 0. 口径说明

### 0.1 什么算「一个最小功能点」

拆的是**用户能感知到的功能**，不是代码行：

- 一个可点击 / 可滑动 / 可切换的交互（按钮、开关、行点击、左滑、长按菜单、分段器）
- 一个独立展示区块（一张卡、一个环、一行读数、一张图）
- 一个独立数据动作（导出、导入、同步、校验、清空、恢复）

**不拆**：同一个区块里的多个 `Text`、纯样式修饰（hairline / padding / 动画曲线）、
只是同一动作的不同文案分支。所以「一张卡里的 3 行读数」记 1 条，
「一张卡里的 3 个可点动作」记 3 条。

### 0.2 三列判断口径

| 列 | 取值 | 判断依据 |
|---|---|---|
| **是否可达** | 能 / 不能 / 需 X 条件 | 「能」= 从底部 5 个 Tab 出发，沿 NavigationLink / sheet / push 能点到。**快捷格（QuickPool）不算入口** —— 见 §0.4 |
| **是否重复** | 否 / 是 / 说明 | 与另一个页面的某个功能点做同一件事，且用户能分别到达 |
| **冗余嫌疑** | 高 / 中 / 低 | 高 = 零入口的死代码 / 与别处完全重叠；中 = 功能小众或藏在 3 层以下；低 = 核心路径 |

### 0.3 底部导航（唯一的入口树）

`ManagerFace` 是根，原生 `TabView` 五个 Tab（`ManagerFace.swift:72-122`）：

| # | Tab | 首屏 | 组内入口（`rowsFor`，`ManagerFace.swift:251-292`） |
|---|---|---|---|
| 0 | 门厅 | `HomeConsole` | （无组内入口） |
| 1 | 钥匙 | 组页胶囊 | 钥匙管理 / 指纹 / 临时密码 |
| 2 | 设备 | 组页胶囊 | 我的门锁 / 固件升级 / 网关配网 / 钥匙串 / 校准时间 |
| 3 | 成员 | 组页胶囊 | 成员 / 添加成员 / 已归档 |
| 4 | 系统 | 组页胶囊 | 隐私看板 / 安全审计 / 销毁数据 / 安全模式 / 备份恢复 / 导出中心 / 外观工作室 / 本机设置 / 诊断与自检 |

其余页面全部靠 **`MePage`（本机设置）里的 15 条 NavigationLink**、
**`SecurityPage`、`CarePage`、`MembersPage`、`EventsPage` 工具栏**、
以及 **`HomeConsole` 的 sheet** 二次进入 —— 这是本清单里大量「需 X 条件」的来源。

### 0.4 重要前提：快捷格没有接线

`App/Core/QuickPool.swift:143` 定义了 `quickDestination(_:)`（十个快捷格落点），
但**全仓零调用**（`grep -r quickDestination` 只命中定义行）。
因此「门厅/设备页的快捷格」这块 UI 在当前代码里**没有任何入口**，
本清单不把快捷格当作任何页面的可达路径。

### 0.5 文件索引

| # | 文件 | 行数 | 功能点数 | 域 |
|---|---|---|---|---|
| 1 | HomeConsole.swift | 1697 | 21 | 门厅 |
| 2 | ManagerFace.swift | 515 | 10 | 门厅 |
| 3 | KeysPage.swift | 876 | 22 | 钥匙 |
| 4 | CredentialStudio.swift | 1074 | 27 | 钥匙 |
| 5 | AddKeyPage.swift | 491 | 12 | 钥匙 |
| 6 | AddFingerPage.swift | 474 | 7 | 钥匙 |
| 7 | FpOwnerPicker.swift | 116 | 3 | 钥匙 |
| 8 | CredentialBinView.swift | 321 | 7 | 钥匙 |
| 9 | LocksPage.swift | 365 | 10 | 设备 |
| 10 | AddLockPage.swift | 606 | 9 | 设备 |
| 11 | DevicePage.swift | 554 | 10 | 设备 |
| 12 | LockProfilePage.swift | 557 | 13 | 设备 |
| 13 | DeviceHomeView.swift | 304 | 7 | 设备 |
| 14 | DonglesPage.swift | 428 | 11 | 设备 |
| 15 | GatewayPage.swift | 508 | 13 | 设备 |
| 16 | FirmwarePage.swift | 808 | 11 | 设备 |
| 17 | ShareToAndroidView.swift | 153 | 8 | 设备 |
| 18 | MembersPage.swift | 455 | 10 | 成员 |
| 19 | MemberCenterView.swift | 1832 | 47 | 成员 |
| 20 | MePage.swift | 480 | 17 | 系统 |
| 21 | SecurityPage.swift | 364 | 8 | 系统 |
| 22 | SecurityCenterView.swift | 1880 | 43 | 系统 |
| 23 | AppLockSetupView.swift | 275 | 9 | 系统 |
| 24 | EventsPage.swift | 904 | 22 | 记录 |
| 25 | AlarmsPage.swift | 466 | 6 | 记录 |
| 26 | StatsPage.swift | 467 | 9 | 记录 |
| 27 | FeedPage.swift | 382 | 6 | 记录 |
| 28 | BackupPage.swift | 697 | 13 | 数据 |
| 29 | BackupStudio.swift | 1419 | 29 | 数据 |
| 30 | ExportCenter.swift | 2687 | 38 | 数据 |
| 31 | CarePage.swift | 437 | 6 | 关怀 |
| 32 | CareViews.swift | 702 | 16 | 关怀 |
| 33 | CareRemindersView.swift | 331 | 6 | 关怀 |
| 34 | AppearancePage.swift | 112 | 2 | 外观/设置 |
| 35 | IconPicker.swift | 208 | 3 | 外观/设置 |
| 36 | DiagnosticsPage.swift | 537 | 10 | 外观/设置 |
| 37 | SettingsView.swift | 285 | 8 | 外观/设置 |
| 38 | Alerts.swift | 141 | 5 | 支撑 |
| 39 | Celebration.swift | 95 | 2 | 支撑 |
| 40 | MomentLayer.swift | 23 | 1 | 支撑 |
| 41 | DataScannerView.swift | 69 | 2 | 支撑 |
| 42 | ReportVerifyView.swift | 47 | 2 | 支撑 |
| 43 | CJKSpacing.swift | 49 | 1 | 支撑 |
| 44 | XLockBlade.swift | 233 | 1 | 3D/死代码 |
| 45 | BladeGeometry.swift | 296 | 1 | 3D/死代码 |
| 46 | BladeMesh.swift | 109 | 1 | 3D/死代码 |
| 47 | RealityAPIProbe.swift | 260 | 1 | 3D/死代码 |
| 48 | DeviceStripCard.swift | 12 | 1 | 死代码 |
| 49 | LockOverviewView.swift | 6 | 1 | 死代码 |
| 50 | AlarmCenterView.swift | 46 | 2 | 死代码 |
| 51 | FindArrowLayer.swift | 39 | 1 | 死代码 |

---

## 1. HomeConsole.swift（门厅 · 1697 行）

App 唯一主界面 = 底部 Tab 0。三块：页眉芯片 + 大环开锁 + 今日数据 + 成员。合并了旧 D/F/B 三个域。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-home-01 | 顶部四枚状态芯片（连接/电量/今日/待处理） | 横向滚动 | app.status、今日日志、RecordSearch.unhandledAlarmCount | XStatChip，4×120pt 必然溢出故走横滚 | 能 | 否 | 低 |
| ui-home-02 | 实时时钟（30s 刷新） | 自动 | TimelineView | 芯片行下方 caption | 能 | 是 —— MePage/EventsPage 也显示时间但非同一读数 | 低 |
| ui-home-03 | 空状态：还没有门锁 → 去配对门锁 | 点按钮 | DB.keychains() 为空 | 打开 AddLockPage sheet | 能（无锁时） | 否 | 低 |
| ui-home-04 | 锁名大标题 + 一句摘要（今天 N 人开过 N 次） | 自动展示 | StatsKit.build、归因引擎 | LargeTitle 30/Bold | 能 | 否 | 低 |
| ui-home-05 | 关键提示条（告警/低电/7 天内到期，三选一） | 点整条 | alarmCount、powerLevel、expiringSoonCount | 点击跳对应管理组 | 能 | 是 —— 与 MePage 待处理告警、AlarmsPage 顶部重复 | 中 |
| ui-home-06 | 按住 1.05s 开锁大环（340pt） | 长按环 | app.lock.unlock(mac:) | 蓄力弧 + 游标 + 成功/失败态 + 触觉 | 能 | 否 | 低 |
| ui-home-07 | 环右上角 ⓘ「这个环是什么」口径说明 | 点 20pt 图标 | 无 | alert 解释环的统计口径 | 能 | 否 | 低 |
| ui-home-08 | 开锁失败原因 + 「去「X」处理」跳转 | 点胶囊 | UnlockFailure.group | 失败态唯一出路 | 能 | 否 | 低 |
| ui-home-09 | 环下脚注行（电量 · 上次开门 · 锁态） | 自动展示 | app.status、HotCache | 失败时被替换 | 能 | 是 —— 与 ui-home-01 芯片读数重叠 | 中 |
| ui-home-10 | 今日三读数卡（44px 大数字 + 成员数 + 最早开门） | 自动展示 | hourCounts、memberStats | 图 2 双栏形态 | 能 | 否 | 低 |
| ui-home-11 | 细三环（开门/指纹/自动比例） | 自动展示 | tripleOpen/Fp/Auto | ⚠ 硬编码 0.62/0.28/0.10（`HomeConsole.swift:951-953`），非真实数据 | 能 | 否 | 中 |
| ui-home-12 | 「本周」三环卡（开门/成员/电量） | 自动展示 | weekOpenCount、weekMemberCount、powerLevel | 含握手/信号两格（握手恒为 0 → 显示 —） | 能 | 是 —— 与 ui-home-10/11 同属"本周/今日读数" | 中 |
| ui-home-13 | 开门历史面积图（近 21 天） | 自动展示 | dailyOpenCounts | 页面级标题 + 150pt 面积图 | 能 | 是 —— 与 StatsPage trendCard「近 14 天趋势」重复 | 中 |
| ui-home-14 | 「今日开门分布」24 根发丝柱图 | 点图任意位置 | hourCounts | SpatialTapGesture 换算小时 | 能 | 是 —— 与 FeedPage todayOverviewCard、StatsPage rhythmCard 三份同类图 | 中 |
| ui-home-15 | 点柱图 → 弹出该小时的事件记录 | 点柱 | hourSheet | sheet 内 EventsPage(initialHour:) | 能 | 否 | 低 |
| ui-home-16 | 卡头「›」→ 打开事件记录 | 点 headerAction | showEvents | sheet | 能 | 是 —— MePage「事件记录」行同目标 | 低 |
| ui-home-17 | 卡内「最早一次」读数 | 自动展示 | firstOpenText | 与 ui-home-10 的「最早开门」重复 | 能 | 是 —— 同一读数列两次 | 中 |
| ui-home-18 | 成员横向胶囊（最多 6 人） | 点胶囊 | memberStats | 打开 MemberDetail360View sheet | 能 | 否 | 低 |
| ui-home-19 | 成员卡头「›」→ 切到成员 Tab | 点 | openGroup(.members) | | 能 | 是 —— 底部 Tab 3 同一去处 | 低 |
| ui-home-20 | 下拉刷新（真连 BLE 读状态） | 下拉 | refreshStatusQuietly(manual:) | 与「回前台只重算本地」刻意区分 | 能 | 否 | 低 |
| ui-home-21 | 深链 / 摇一摇落点：tabSelection 变化 → 打开管理组 | 外部触发 | app.tabSelection | 需访客闸 | 需外部触发 | 否 | 低 |

**本文件疑点**
- `ui-home-11` 的细三环比例是**写死的常量**，不是真实统计（源码注释也承认"数据不足时返回固定的示意比例"）。若保留 UI 建议接真数据，否则是伪读数。
- `ui-home-12` 的「握手」恒为 `0`（`handshake = 0` 硬编码，`HomeConsole.swift:991`），永远显示 `—`。
- 同一"今日开门分布"图在 3 个文件各画一份（HomeConsole / FeedPage / StatsPage），见 §末汇总。

---

## 2. ManagerFace.swift（底部导航 + 管理组 · 515 行）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mgr-01 | 底部 5 Tab（门厅/钥匙/设备/成员/系统） | 点 Tab | ManagerTab 枚举 | 原生 TabView，Liquid Glass 胶囊 | 能 | 否 | 低 |
| ui-mgr-02 | 访客闸：受限 Tab 点击弹口令复核 | 点受限 Tab | app.requestGroupGate | `tabIndex` set 里判 guestAreaLocked | 需访客通道开启 | 否 | 低 |
| ui-mgr-03 | 组页顶部胶囊行（每 Tab 三枚读数） | 横向滚动 | DB.keychains / members / dongles / hasPasscode / AuditLog | 四组读数各不同 | 能 | 是 —— 与 MePage 芯片行、各页内统计卡重复 | 中 |
| ui-mgr-04 | 组内入口卡（一卡多行 + 行间细线） | 点行 | rowsFor 常量表 | NavigationLink(value:) push | 能 | 否 | 低 |
| ui-mgr-05 | 钥匙组三口：钥匙管理 / 指纹 / 临时密码 | 点行 | rowsFor(.ledger) | → KeysPage / AddFingerPage / TempCodeStudio | 能 | 否 | 低 |
| ui-mgr-06 | 设备组五口：门锁/固件/网关/钥匙串/校准时间 | 点行 | rowsFor(.devices) | | 能 | 否 | 低 |
| ui-mgr-07 | 成员组三口：成员 / 添加成员 / 已归档 | 点行 | rowsFor(.members) | | 能 | 否 | 低 |
| ui-mgr-08 | 系统组九口 | 点行 | rowsFor(.system) | 隐私看板/审计/销毁/安全模式/备份/导出/外观/本机设置/诊断 | 能 | 否 | 低 |
| ui-mgr-09 | 深链焦点退化：pendingSettingsFocus → 切系统 Tab | 外部触发 | app.pendingSettingsFocus | 只切 Tab，不再定位到具体行 | 需外部触发 | 否 | 中 |
| ui-mgr-10 | 组页摘要文案（ManagerGroup.summary） | 自动 | DB.* | | 能 | 否 | 低 |

**本文件疑点**
- 「添加成员」在 Tab 3 组页有入口（`routeDestination .memberWizard`），同时 `MembersPage` 右上角也有「新增成员」→ 两个入口同一页。
- 「已归档」在 Tab 3 组页有入口，`MembersPage` 的 secondaryCard 也有一行 → 重复入口。

---

## 3. KeysPage.swift（钥匙管理 · 876 行）

Tab 1 组页第一行「钥匙管理」→ 本页。页内再 push `CredentialDetailView`。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-keys-01 | 顶部五枚分类芯片（全部/密码/临时码/指纹/即将到期） | 横向滚动 | DB.listPwds / listFps / dueSoonPwds | 与下方 overviewCard 三读数重复 | 能 | 是 —— 与 overviewCard「库存分布」同一组数字 | 中 |
| ui-keys-02 | 页内副标题「N 项 · 指纹 x / 密码 y / 临时码 z」 | 自动 | 同上 | HTML 对齐项 | 能 | 是 —— 与 ui-keys-01 完全同一组计数，第三次出现 | 中 |
| ui-keys-03 | 「本周到期」预警卡（总计/密码/指纹三列） | 自动展示 | CredentialOrg.dueSoonPwds | 指纹列**写死 "0 份"**（`KeysPage.swift:159`） | 能 | 是 —— 与 ui-keys-01「即将到期」重复 | 中 |
| ui-keys-04 | 「库存分布」主角卡（44px 总数 + 三环 + 本周新增/即将到期） | 自动展示 | pwds/fps/weekAdded | | 能 | 是 —— 与 ui-keys-01/02 重复第三份计数 | 中 |
| ui-keys-05 | 分段器 全部/密码/指纹/临时码 | 点分段 | Seg 枚举 | XSegmented | 能 | 否 | 低 |
| ui-keys-06 | 「N 份生效」大数字（当前分段行数） | 自动 | rows.count | | 能 | 否 | 低 |
| ui-keys-07 | 凭证行（类型徽章 + 标题 + 归属/到期 + 状态胶囊） | 点行 | DB.ledger | NavigationLink → 详情 | 能 | 否 | 低 |
| ui-keys-08 | 行尾 ellipsis 可发现性提示 | 静态 | 无 | 纯装饰图标 | 能 | 否 | 低 |
| ui-keys-09 | 行点击 → 凭证详情页 | 点行 | CredentialDetailView | 2026-10-24 才补 | 能 | 否 | 低 |
| ui-keys-10 | 行长按菜单：星标 | 长按 → 星标 | CredentialOrg.toggleStar | | 能 | 是 —— 详情页「星标这一项」同一动作 | 中 |
| ui-keys-11 | 行长按菜单：删除 | 长按 → 删除 | confirmationDialog → batchDisable | 弹窗写清「本机删 / 锁端撤销 / 回收站 30 天」 | 能 | 是 —— 详情页「停用并入回收站」同一动作 | 中 |
| ui-keys-12 | 行 VoiceOver 动作：置顶/归档/改备注/删除 四条 | 读屏操作 | CredentialOrg.* | 视觉上不可见 | 能（读屏） | 是 —— 与长按菜单、详情页重叠 | 中 |
| ui-keys-13 | 工具栏「成员」→ MembersPage | 点图标 | 无 | | 能 | 是 —— 底部 Tab 3 同一去处 | 中 |
| ui-keys-14 | 工具栏「+」→ 添加钥匙 sheet | 点图标 | AddKeyPage | | 能 | 否 | 低 |
| ui-keys-15 | 搜索框（名称/备注/归属） | 点搜索 | .searchable | 过滤 pwds/fps | 能 | 否 | 低 |
| ui-keys-16 | 空态卡（无钥匙 / 无匹配） | 自动 | rows.isEmpty | 带「添加钥匙」按钮 | 能 | 否 | 低 |
| ui-keys-17 | 详情：两张并排 metric-card（已使用柱图 / 最近一次） | 自动 | DB.readLogs、StatsKit.openTypes | | 能 | 是 —— 与详情下方「使用记录」卡读同一批日志 | 中 |
| ui-keys-18 | 详情：码值卡（44px 码值 + 锁内编号 + 指纹位） | 自动 | LedgerPwd.pwd / LedgerFp.batch | | 能 | 否 | 低 |
| ui-keys-19 | 详情：归属与授权卡（归属 / 类型） | 自动 | row.owner | | 能 | 否 | 低 |
| ui-keys-20 | 详情：使用记录卡（本月使用 / 最后使用） | 自动 | DB.readLogs | 与 ui-keys-17 同源 | 能 | 是 —— 同一批日志算两遍 | 中 |
| ui-keys-21 | 详情：操作卡——星标这一项 | 点行 | CredentialOrg.toggleStar | | 能 | 是（见 ui-keys-10） | 中 |
| ui-keys-22 | 详情：操作卡——停用并入回收站 | 点行 → 确认 | batchDisable | | 能 | 是（见 ui-keys-11） | 中 |

**本文件疑点（重要）**
- `renameFingerprint(_:)`（`KeysPage.swift:342`）**全仓零调用** —— 给指纹改名的功能没有入口，是死函数。
- `editNote(_:)` 只被 VoiceOver 的 accessibilityAction 调用（`KeysPage.swift:663`），**视觉上没有任何入口**能改备注。
- 长按菜单注释说"六个动作"，实际只有 2 个（星标 + 删除）；归档只在 VoiceOver action 里。
- 页面顶部三处（芯片行、副标题、库存分布卡）都在报同一组「全部/密码/指纹/临时码」计数 —— 一屏内同一信息出现 3 次。

---

## 4. CredentialStudio.swift（工坊：临时码 / OTP / 扫码 / 掩码组件 · 1074 行）

`TempCodeStudio` 由 Tab 1 组页第三行「临时密码」进入；`CodeScanSheet` 由 AddKeyPage 之外的扫码路径进入；
`MaskedDigits / CodeBigCard / WindowBar / StepDots` 是**共用组件**（被别的页面引用）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-studio-01 | 场景预设胶囊（选一个用途自动填名称与时长） | 点胶囊 | StudioTools.scenes | | 能 | 否 | 低 |
| ui-studio-02 | 码值输入框（6~8 位数字） | 输入 | 手动 | 数字键盘 | 能 | 否 | 低 |
| ui-studio-03 | 「清除」码值 | 点 | 清空 pwd | | 能 | 否 | 低 |
| ui-studio-04 | 「生成」6 位随机码 | 点 | StudioTools.genDigits(6) | | 能 | 否 | 低 |
| ui-studio-05 | 「扫一扫」相机取号 | 点 | CodeScanSheet → DataScannerView | 打开相机 sheet | 能 | 是 —— 与 ExportCenter「扫码核对」共用 DataScannerView，但用途不同 | 中 |
| ui-studio-06 | 剪贴板候选码识别（来自剪贴板 · 已识别） | 自动（onAppear/onChange） | UIPasteboard | | 能 | 否 | 低 |
| ui-studio-07 | 批量张数选择（1/2/4/8…） | 点数字键 | batchCount | | 能 | 否 | 中 |
| ui-studio-08 | 同值重复告警（本锁已有 N 条同值） | 自动 | CredentialOrg.duplicatePwdValues | + 其它锁同值 | 能 | 否 | 低 |
| ui-studio-09 | 生效时段设置（from / to DatePicker） | 点日期 | 手动 | | 能 | 否 | 低 |
| ui-studio-10 | 快捷时长胶囊（1 小时 / 今天内 / 7 天 / 30 天） | 点胶囊 | TimeFormat.dayEnd | | 能 | 否 | 低 |
| ui-studio-11 | 时段冲突提示（与本成员其它 N 张码撞车） | 自动 | CredentialOrg.overlapWindows | | 能 | 否 | 低 |
| ui-studio-12 | 归属选择胶囊 + 备注输入 | 点 / 输入 | DB.members | | 能 | 是 —— 与 AddKeyPage 归属段同形 | 中 |
| ui-studio-13 | 「发起 N 张临时码」下发 | 点主按钮 | app.lock.pwdAdd 逐条 | 批量即串行逐条，失败逐条报 | 能 | 是 —— 与 AddKeyPage「下发 10 分钟临时密码」同一下发路径 | 中 |
| ui-studio-14 | 完成页：口述卡（大字码值 + 时长） | 自动 | 刚下发的 pwd | 长辈模式下只留这张 | 能 | 否 | 低 |
| ui-studio-15 | 完成页：生成「一句话口令」 | 点 | StudioTools.oneLine | | 能 | 否 | 中 |
| ui-studio-16 | 完成页：复制一句话口令 | 点 | ClipboardCare.copySecret | | 能 | 否 | 中 |
| ui-studio-17 | 完成页：分享一句话口令 | 点 ShareLink | 系统分享 | | 能 | 否 | 中 |
| ui-studio-18 | 完成页：首用回执（等待首次使用 / 约在 xx 有人开过门） | 自动轮询 | CredentialOrg.firstUse | | 能 | 否 | 中 |
| ui-studio-19 | 完成页：「再发一张」 | 点 | 重置表单 | | 能 | 否 | 低 |
| ui-studio-20 | 双签确认（删除/停用一个已录入指纹前验证前缀） | 触发破坏性动作时 | CredentialOrg.fpCountByOwner | 独立 UIAlert 流程 | 能 | 否 | 中 |
| ui-studio-21 | OTP 大卡 CodeBigCard（码值 + 环形倒计时 + 复制 + 分享口述卡） | 组件 | CredentialOrg.TOTPEntry | 被其它页复用的组件；`TempCodeStudio` 本体不渲染它 | 不能（无独立入口） | 否 | 中 |
| ui-studio-22 | MaskedDigits 掩码数字（点按逐位揭示 + 双击整串复制） | 组件 | SecurityPolicy.maskStyle | 同一处负责「贴近复遮」ProximityRemask | 能（被详情/凭证页复用） | 否 | 低 |
| ui-studio-23 | WindowBar 倒计时窗口条（剩约 N 秒） | 组件 | 时间戳 | | 能（组件） | 否 | 低 |
| ui-studio-24 | StepDots 步骤点 | 组件 | 索引 | 视觉指示 | 能（组件） | 否 | 低 |
| ui-studio-25 | CodeScanSheet 扫码取号 sheet（关闭按钮） | 点扫一扫 | DataScannerView | 与 ReportScanSheet 几乎同形 | 能 | 是 —— 与 ReportScanSheet 两份同构扫码壳 | 中 |
| ui-studio-26 | StudioTools.parseOtpAuth（解析 otpauth:// URI） | 内部 | 字符串 | 无 UI 入口 | 不能 | 否 | 高 |
| ui-studio-27 | StudioTools.totp（TOTP 计算）+ base32Decode | 内部 | secret | 无 UI 入口（无 OTP 录入页） | 不能 | 否 | 高 |

**本文件疑点（重要）**
- `StudioTools.parseOtpAuth` / `base32Decode` / `totp` 一整套 OTP 引擎**没有任何 UI 入口**：
  `CredentialStudio` 里没有录入 otpauth URI 的页面，`CodeBigCard`（唯一的 OTP 展示组件）也**零调用**。
  → 这是一整套「做了但没接」的功能，冗余嫌疑高。
- `CodeScanSheet` 与 `ReportScanSheet` 是两个几乎逐字相同的扫码壳（都用 `DataScannerView` +
  `cancellationAction` 关闭），只是标题和回调不同。

---

## 5. AddKeyPage.swift（添加密码 · 491 行）

入口：KeysPage 工具栏「+」sheet（唯一入口）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-addkey-01 | 密码容量卡（可建 N 条 + 三环 + 已用/上限） | 自动 | DB.readStatus.pwdCap / pwdStock | 库存满时转 warn 色 | 能 | 是 —— 与 KeysPage/DevicePage 容量读数重复 | 中 |
| ui-addkey-02 | 8 格数字槽位输入（6~8 位密码） | 输入 | 手动 | 隐藏 TextField + 自绘槽位 | 能 | 否 | 低 |
| ui-addkey-03 | 密码强度提示 | 自动 | StudioTools.pwdStrength | | 能 | 否 | 中 |
| ui-addkey-04 | 前缀冲突提示（与已有密码前 N 位相同） | 自动 | CredentialOrg.prefixConflict | | 能 | 否 | 低 |
| ui-addkey-05 | 弱密码提示 | 自动 | pwdWeak | | 能 | 否 | 中 |
| ui-addkey-06 | 有效期分段：永久 / 自定义 | 点分段 | 无 | | 能 | 是 —— 与 TempCodeStudio 生效时段同一件事 | 中 |
| ui-addkey-07 | 自定义「生效 / 到期」两个 DatePicker | 点日期 | 手动 | | 能 | 是（同上） | 中 |
| ui-addkey-08 | 归属横向胶囊（未归属 + 每位成员，带已有条数） | 点胶囊 | DB.members、DB.listPwds | | 能 | 是 —— TempCodeStudio「归属与备注」同一控件 | 中 |
| ui-addkey-09 | 「备注自动填命名模板」开关 | 开关 | 拼 who-place-when | | 能 | 否 | 中 |
| ui-addkey-10 | 主按钮「添加密码」下发 | 点 | app.lock.pwdAdd + DB.addPwd + snapshot | 成功后 dismiss + toast 提示"用这串密码开一次锁确认" | 能 | 否 | 低 |
| ui-addkey-11 | 次按钮「下发 10 分钟临时密码」 | 点 → 确认弹窗 | pwdAdd + 10 分钟窗口 | | 能 | 是 —— TempCodeStudio 已能建任意时长临时码 | 中 |
| ui-addkey-12 | 底部提示「请将手机靠近门锁」 | 静态 | 无 | | 能 | 否 | 低 |

---

## 6. AddFingerPage.swift（录入指纹 · 474 行）

入口：Tab 1 组页第二行「指纹」（`ManagerRoute.fingerprints`）→ 本页。**这是唯一入口**。
另：`MemberCenterView.swift:672` 有一个 `NavigationLink("录指纹后到钥匙页指归属")` 也指向本页（成员建档向导第 3 步内）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-fp-01 | 指纹容量卡（可录 N 枚 + 三环 + 上次录入/建议补录） | 自动 | DB.readStatus.fpCap / fpStock、DB.ledger.fps | | 能 | 是 —— 与 DevicePage 容量卡同一读数 | 中 |
| ui-fp-02 | 归属选择（每成员一枚胶囊 + 已有枚数） | 点胶囊 | DB.members、CredentialOrg.fpCountByOwner | | 能 | 是 —— 与 AddKeyPage 归属段、TempCodeStudio 归属段三处同形 | 中 |
| ui-fp-03 | 8 段环形录入进度（每次按压点亮一段） | 自动（BLE 回调） | app.lock.fpStart(times:8, onPress:) | 中心显示 N/8 | 能 | 否 | 低 |
| ui-fp-04 | 「开始录入」按钮 | 点 | fpStart 8 次 | 归属未选时禁用并提示 | 能 | 否 | 低 |
| ui-fp-05 | 通信中提示「正在与门锁通信…」 | 自动 | busy | | 能 | 否 | 低 |
| ui-fp-06 | 错误横幅 + 「重新录入」 | 自动/点 | error | XInlineError | 能 | 否 | 低 |
| ui-fp-07 | 成功页（勾 + 「请用这枚新指纹开一次锁，确认它能用」+ 完成） | 自动 | doneBatch | | 能 | 否 | 低 |

**本文件疑点**
- 归属选择用的是**页内自绘胶囊**（`ownerChip`），而专门为这件事写的 `FpOwnerPicker` 组件
  **全仓零实例化**（见 §21）——两套实现，一套是死代码。

---

## 7. FpOwnerPicker.swift（指纹归属选择器 · 116 行）★ 死代码

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-fpowner-01 | 成员归属列表（每行：色点 + 名 + N 枚 / 无指纹） | 点行 | CredentialOrg.fpCountByOwner | 选中即写 owner 绑定 | **不能** | 是 —— 与 AddFingerPage ui-fp-02 完全同一件事 | **高** |
| ui-fpowner-02 | 「新增归属 / 新增一位成员」按钮 + 建成员弹窗 | 点 → alert | DB.addMember | 姓名校验汉字/英文/数字 ≤20 字 | **不能** | 是 —— 与 MemberWizardView 建档重复 | **高** |
| ui-fpowner-03 | 空态自动弹「新增归属」 | 自动（onAppear） | members.isEmpty | 用户口径 317 的落点 | **不能** | 否 | **高** |

**结论**：`FpOwnerPicker` 在整个 App 里**没有任何实例化点**
（`grep -r "FpOwnerPicker" ios-app/App` 只命中定义行和一条注释）。
AddFingerPage 自己重写了一套归属胶囊。**建议直接删除本文件**。

---

## 8. CredentialBinView.swift（回收站 · 321 行）

入口：系统 Tab → 销毁数据 → 回收站（`SecurityCenterView.swift:1230`）；
另 `SecurityPage`「回收站」行也可达（`SecurityPage.swift:315`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-bin-01 | 回收站统计卡（N 项 + 恢复率环 + 保留期） | 自动 | CredentialOrg.bin(mac) | | 能 | 否 | 低 |
| ui-bin-02 | 保留期说明卡（删除后保留 N 天，可恢复） | 自动 | CredentialOrg.reclaimDays() | | 能 | 否 | 低 |
| ui-bin-03 | 条目行（类型 + 名称 + 删除时间 + 「恢复」按钮） | 点恢复 | CredentialOrg.undoRemove | | 能 | 否 | 低 |
| ui-bin-04 | 恢复结果 alert | 自动 | lastMessage | | 能 | 否 | 低 |
| ui-bin-05 | 锁端下发回执卡（刚刚已向门锁发出 N 项变更） | 自动 | Sense.lastReceipt | | 能 | 否 | 低 |
| ui-bin-06 | 待下发队列卡（N 条等待门锁确认） | 自动 | CredentialOrg.queue | | 能 | 否 | 低 |
| ui-bin-07 | 空态（回收站空但有 N 条撤销未发） | 自动 | entries.isEmpty && !pending.isEmpty | | 能 | 否 | 低 |

---

## 9. LocksPage.swift（我的门锁 · 365 行）

入口：Tab 2 组页第一行「我的门锁」→ 本页；另 MePage「门锁」摘要有第二条路径（`MePage.swift:178`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-locks-01 | 门锁列表（每行：名 + MAC + 电量% + 锁态胶囊 + 凭证数） | 点行 | DB.keychains、DB.readStatus | 点击 = 切换当前锁 app.select | 能 | 否 | 低 |
| ui-locks-02 | 左滑「隐藏」 | 左滑 | LockArchive.setHidden | | 能 | 否 | 低 |
| ui-locks-03 | 左滑「设为当前」（非当前锁才出现） | 左滑 | app.select | | 能 | 是 —— 与 ui-locks-01 行点击同一效果 | 中 |
| ui-locks-04 | 左滑「分享给安卓」 | 左滑 | ShareToAndroidView sheet | | 能 | 否 | 中 |
| ui-locks-05 | 左滑「解除绑定」+ 二次确认 | 左滑 → 确认 | DB.removeDevice | 说明"门锁里的密码/指纹不受影响" | 能 | 否 | 低 |
| ui-locks-06 | 列表拖动排序（onMove → persistOrder） | 长按拖动 | DB.store 持久化 | 决定启动默认选中 | 能 | 否 | 低 |
| ui-locks-07 | 工具栏「排序 / 完成」编辑模式切换 | 点 | editMode | | 能 | 是 —— 与 ui-locks-06 同一能力的手动开关 | 中 |
| ui-locks-08 | 已隐藏区 + 逐条「取消隐藏」 | 点 | LockArchive.setHidden(_, false) | | 能 | 否 | 低 |
| ui-locks-09 | 空态「去配对」 | 点 | AddLockPage sheet | | 能 | 是 —— HomeConsole 空态、FeedPage 空态同去处 | 低 |
| ui-locks-10 | 工具栏「+」添加门锁 | 点 | AddLockPage sheet | | 能 | 是 —— 与 ui-locks-09 同一 sheet | 低 |

---

## 10. AddLockPage.swift（配对门锁 · 606 行）

入口：LocksPage「+」/ 空态、HomeConsole 空态、FeedPage 空态 —— 三处 sheet。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-addlock-01 | 四步脊（发现→校验→初始化→命名）进度指示 | 自动 | Flow 枚举 | 顶部 spine | 能 | 否 | 低 |
| ui-addlock-02 | 「重新扫描」按钮（10s 扫描窗口） | 点 | BLEService 广播 | 扫到后按 scoreAdv 排序 | 能 | 否 | 低 |
| ui-addlock-03 | 发现的设备行（名 + MAC + 信号格） | 双击行 | ZKProtocol.parseAdv | 双击开始配对 | 能 | 否 | 低 |
| ui-addlock-04 | 重复设备检测 → 「跳转到已有锁」 | 自动 → 对话框 | DB.keychains 比对 | 提示"重新配网会换掉密钥" | 能 | 否 | 低 |
| ui-addlock-05 | 配对中进度（LockService.pair 回调，逐阶段文案） | 自动 | pair(deviceId:mac:progress:) | 不可滑动关闭 | 能 | 否 | 低 |
| ui-addlock-06 | 命名阶段（昵称 + 场所两个输入框） | 输入 | 手动 | 默认名按型号 + 同型号序号 | 能 | 否 | 低 |
| ui-addlock-07 | 完成页「已添加」+ 三条「接下来」建议 | 自动 | 静态文案 | 引导去录指纹/同步/试开 | 能 | 否 | 低 |
| ui-addlock-08 | 关闭按钮（配对中触发 rollback 回滚） | 点 | rollback(reason:) | | 能 | 否 | 低 |
| ui-addlock-09 | 错误横幅 + 重试 | 自动 | errorBanner | | 能 | 否 | 低 |

---

## 11. DevicePage.swift（这台锁 · 554 行）

入口：MePage「这台锁」行（`MePage.swift:331`）。**只此一条**。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-devic-01 | 身份卡：锁名 + 连接胶囊（已连接/连接中/未连接） | 自动 | LinkSense.linkState | | 能 | 是 —— 与 HomeConsole 芯片「连接」同一读数 | 中 |
| ui-devic-02 | 连接明细（握手耗时 N ms · 信号 N dBm / 数据截至 N 分钟前） | 自动 | LinkSense.connectMs、DB.statusTime | | 能 | 是 —— 与 HomeConsole 脚注行重复 | 中 |
| ui-devic-03 | 电量仪表 XBatteryGauge（116pt） | 自动 | snap.powerLevel | | 能 | 是 —— 与 HomeConsole 电量芯片、LocksPage 电量重复 | 中 |
| ui-devic-04 | 密码余量 / 指纹余量两行读数 | 自动 | snap.pwdStock / fpStock | | 能 | 是 —— 与 AddKeyPage/AddFingerPage 容量卡重复 | 中 |
| ui-devic-05 | 待处理提示卡（低电 / 弱信号 / N 条告警未处理） | 自动 | attentionItems | | 能 | 是 —— 与 HomeConsole criticalNotice 同族 | 中 |
| ui-devic-06 | 「锁内容量」卡（密码 used/cap + 指纹 used/cap 进度条） | 自动 | DB.readStatus | | 能 | 是 —— 与 ui-devic-04 同一组数 | 中 |
| ui-devic-07 | 三枚状态芯片（信号 / 固件 / 握手） | 横向滚动 | DB.readStatus | | 能 | 是 —— 又一次同读数 | 中 |
| ui-devic-08 | 「明细」折叠区（锁 ID / 配对时间 / 固件 / 安全等级 / 广播模式 / 单日掉电） | 点展开 | DB.readStatus、BatteryCare | 折叠按钮 | 能 | 否 | 低 |
| ui-devic-09 | 「最近」区块（最近 3 条记录） | 自动 | app.recentRecords(3) | | 能 | 是 —— 与 EventsPage / FeedPage 同一批日志 | 中 |
| ui-devic-10 | 下拉刷新（真连 BLE 读状态） | 下拉 | 无 | | 能 | 是 —— 与 HomeConsole 下拉刷新同一动作 | 低 |

---

## 12. LockProfilePage.swift（锁档案 · 557 行）

入口：MePage「锁档案」行（`MePage.swift:344`）。**只此一条**。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-profile-01 | 顶部牌匾预览（符号大图 + 色标辉光 + 名字 + 场所 + 状态条） | 自动（随输入实时变） | LockArchive.meta | 所见即所得预览 | 能 | 否 | 低 |
| ui-profile-02 | 牌匾状态条（电量/固件/指纹余量 三枚小 chip） | 自动 | DB.readStatus | | 能 | 是 —— 与 DevicePage 同读数 | 中 |
| ui-profile-03 | 指标双卡（电量 / 固件） | 自动 | DB.readStatus | | 能 | 是 —— 第三次重复电量固件 | 中 |
| ui-profile-04 | 指纹余量卡（可用槽位 + 环） | 自动 | DB.readStatus.fpStock | | 能 | 是 —— 第四次重复容量读数 | 中 |
| ui-profile-05 | 身份事实卡（名字 / 锁态 / 配对时间） | 自动 | DB.readStatus、DB.keychains | | 能 | 是 —— 与 DevicePage 明细重复 | 中 |
| ui-profile-06 | 名字输入（上限 20 字，实时预览） | 输入 | LockArchive | | 能 | 否 | 低 |
| ui-profile-07 | 场所输入（如 玄关 / 车库） | 输入 | LockArchive | 用于 AddKeyPage 的备注模板 | 能 | 否 | 低 |
| ui-profile-08 | 分组输入（家用 / 仓库 / 办公） | 输入 | LockArchive | | 能 | 否 | 中 |
| ui-profile-09 | 备注多行输入（换电历史 / 安装细节） | 输入 | LockArchive | | 能 | 否 | 中 |
| ui-profile-10 | 符号选择（横向 SF Symbols 选择器） | 点图标 | LockArchive | 影响牌匾与桌面图标位 | 能 | 否 | 低 |
| ui-profile-11 | 色标选择（横向色板） | 点色块 | LockArchive | | 能 | 否 | 低 |
| ui-profile-12 | 电池型号输入（如 CR2032） | 输入 | LockArchive | | 能 | 否 | 中 |
| ui-profile-13 | 「保存档案」 | 点 | DB.saveKeychain + app.loadDevices | | 能 | 否 | 低 |

---

## 13. DeviceHomeView.swift（校准时间 SyncTimeView · 304 行）

文件里只有一个 `SyncTimeView`（+ 一个共用小组件 `LabeledRow`）。
入口：Tab 2 组页第五行「校准时间」（`ManagerRoute.syncTime`）；另 `CareViews.swift:437` 换电指引里有一条。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-sync-01 | 未选锁提示卡 | 自动 | app.current == nil | | 能 | 否 | 低 |
| ui-sync-02 | 偏差范围卡（允许 ±5 秒 / 当前偏差 N 秒） | 自动 | app.status 锁钟 vs 手机钟 | | 能 | 否 | 低 |
| ui-sync-03 | 锁钟偏差卡（偏差条 + 正负判断文案 + 刻度） | 自动 | skewSeconds | 正=锁慢 / 负=锁快 | 能 | 否 | 低 |
| ui-sync-04 | 锁内时钟卡（读到的锁钟 vs 手机现在） | 自动 | app.status | | 能 | 否 | 低 |
| ui-sync-05 | 「写入」按钮：把手机时间写进锁（cmd 0E） | 点 | app.lock + showToast | | 能 | 否 | 低 |
| ui-sync-06 | 底部提示「请将手机靠近门锁 · 请确保手机时间准确」 | 静态 | 无 | | 能 | 否 | 低 |
| ui-sync-07 | `LabeledRow` 共用标签行组件（中西文间距） | 组件 | cjkSpaced | 被 CareViews/CareReminders/ExportCenter/LinkSense/AutoOpen 共用 | 能（组件） | 否 | 低 |

---

## 14. DonglesPage.swift（钥匙串 · 428 行）

入口：Tab 2 组页第四行「钥匙串」（`ManagerRoute.dongles`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-dongle-01 | 页头说明卡（钥匙串靠近门锁即可开门） | 自动 | 静态 | | 能 | 否 | 低 |
| ui-dongle-02 | 未配对门锁横幅（写入钥匙前需先配对） | 自动 | app.current == nil | | 能 | 否 | 低 |
| ui-dongle-03 | 钥匙串卡（名 + MAC + 已配钥匙胶囊 + 电量条 + 钥匙存量 + 固件） | 自动 | Dongle.stat | | 能 | 否 | 低 |
| ui-dongle-04 | 时间戳三行（最近看到 / 上次写钥匙 / 绑定时间） | 自动 | Dongle 字段 | | 能 | 否 | 低 |
| ui-dongle-05 | 菜单「读取状态」 | 菜单 | readStatus(d) | BLE 直连 | 能 | 否 | 低 |
| ui-dongle-06 | 菜单「给当前门锁写入钥匙」+ 确认 | 菜单 → 确认 | writeKey(d) | 破坏性确认 | 能 | 否 | 低 |
| ui-dongle-07 | 菜单「查询全部钥匙」 | 菜单 | listKeys(d) | | 能 | 否 | 中 |
| ui-dongle-08 | 菜单「删除本锁钥匙」+ 确认 | 菜单 → 确认 | deleteKey(d) | | 能 | 否 | 低 |
| ui-dongle-09 | 菜单「删除记录」+ 确认 | 菜单 → 确认 | DB.removeDongle | 只删本机记录 | 能 | 否 | 低 |
| ui-dongle-10 | 「搜索钥匙串」按钮（BLE 扫描添加） | 点 | scan() | | 能 | 否 | 低 |
| ui-dongle-11 | 空态（还没有钥匙串 → 上电后点搜索） | 自动 | dongles.isEmpty | | 能 | 否 | 低 |

---

## 15. GatewayPage.swift（网关配网 · 508 行）

入口：Tab 2 组页第三行「网关配网」（`ManagerRoute.gateway`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-gw-01 | 三步进度指示（①重置 → ②连 WiFi → ③等出现） | 自动 | confirmed | | 能 | 否 | 低 |
| ui-gw-02 | 第一步卡「先把网关重置」+ 「指示灯已变成橙色」勾选 | 开关 | confirmed | 不勾选不能进入下一步 | 能 | 否 | 低 |
| ui-gw-03 | 第二步卡：WiFi 名称输入（仅 2.4GHz 提示） | 输入 | 手动 | | 能 | 否 | 低 |
| ui-gw-04 | 第二步卡：WiFi 密码输入（SecureField） | 输入 | 手动 | | 能 | 否 | 低 |
| ui-gw-05 | 第二步卡「上一步」回退 | 点 | confirmed = false | | 能 | 否 | 低 |
| ui-gw-06 | 「开始配网」按钮 + 确认 | 点 → 确认 | provision() | | 能 | 否 | 低 |
| ui-gw-07 | 配网进度卡（逐阶段文案） | 自动 | running | | 能 | 否 | 低 |
| ui-gw-08 | 网关卡（名 + MAC + 在线态 + 信号 + 固件） | 自动 | Gateway 记录 | | 能 | 否 | 低 |
| ui-gw-09 | 时间戳两行（最近看到 / 绑定时间） | 自动 | 记录字段 | | 能 | 否 | 低 |
| ui-gw-10 | 菜单「刷新状态」 | 菜单 | refresh(g) | | 能 | 否 | 低 |
| ui-gw-11 | 菜单「重启网关」+ 确认 | 菜单 → 确认 | reboot(g) | | 能 | 否 | 低 |
| ui-gw-12 | 菜单「删除记录」+ 确认 | 菜单 → 确认 | DB.removeGateway | 只删本机 | 能 | 否 | 低 |
| ui-gw-13 | 空态（还没有添加网关） | 自动 | 列表空 | | 能 | 否 | 低 |

---

## 16. FirmwarePage.swift（固件升级 · 808 行）

入口：Tab 2 组页第二行「固件升级」（`ManagerRoute.firmware`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-fw-01 | 版本卡（当前版本 / 固件包版本 / 对比标签 新/同/旧） | 自动 | app.status.firmware、包解析 | | 能 | 否 | 低 |
| ui-fw-02 | 固件包选择（.zip 文件选择器） | 点 | importZip | 解析 bin/dat 与版本 | 能 | 否 | 低 |
| ui-fw-03 | 就绪双卡（电量 ≥30% / 蓝牙已开） | 自动 | snap.powerLevel、BLE state | | 能 | 否 | 低 |
| ui-fw-04 | 检查项清单（电量充足 / 蓝牙已开 / 上次备份时间） | 自动 | BackupStudio.lastBackupText | 三项全过才允许升级 | 能 | 否 | 低 |
| ui-fw-05 | 「开始升级」按钮 + 破坏性确认 | 点 → 确认 | app.lock DFU | 提示"中断可能需重新配网" | 能 | 否 | 低 |
| ui-fw-06 | 升级进度卡（百分比 + 阶段名 + 阶段节点） | 自动 | progress 回调 | | 能 | 否 | 低 |
| ui-fw-07 | 升级失败卡 + 「重试」 | 自动/点 | failed | | 能 | 否 | 低 |
| ui-fw-08 | 批量升级：逐锁勾选 | 点勾选 | app.devices | | 能 | 否 | 中 |
| ui-fw-09 | 「批量升级 N 把」+ 串行执行 | 点 → 确认 | runQueue | 一把失败不中断其余 | 能 | 否 | 中 |
| ui-fw-10 | 升级历史列表（时间 + from→to + 结果） | 自动 | 历史记录 | | 能 | 否 | 中 |
| ui-fw-11 | 升级后自动校验（verifyAfterUpgrade） | 自动 | app.lock 读状态 | 无独立 UI，仅 toast | 能 | 否 | 低 |

---

## 17. ShareToAndroidView.swift（分享给安卓 · 153 行）

入口：LocksPage 左滑「分享给安卓」（`LocksPage.swift:136` sheet）。**只此一条**。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-share-01 | 开锁二维码图（CIQRCodeGenerator，纠错档 M） | 自动（onAppear） | AndroidPair.payload(kc) | 白底不跟随主题（静区要求） | 能 | 否 | 低 |
| ui-share-02 | 锁名 + MAC 显示（供人核对） | 自动 | kc.mac 格式化 | | 能 | 否 | 低 |
| ui-share-03 | 扫这张码的说明文案 | 静态 | 无 | | 能 | 否 | 低 |
| ui-share-04 | 「这张码等于一把钥匙」警示条 | 静态 | 无 | | 能 | 否 | 低 |
| ui-share-05 | 「关于这个码」卡（有效期=一次性 / 作用=导入钥匙） | 静态 | 无 | | 能 | 否 | 低 |
| ui-share-06 | 「分享二维码」ShareLink | 点 | 系统分享 | | 能 | 否 | 低 |
| ui-share-07 | 生成失败态（ekey/PIN 都缺时如实报错，不生成假码） | 自动 | failed | | 能 | 否 | 低 |
| ui-share-08 | 工具栏「关闭」 | 点 | dismiss | | 能 | 否 | 低 |

---

## 18. MembersPage.swift（成员 · 455 行）

入口：Tab 3 组页第一行「成员」（`ManagerRoute.members`）；另 KeysPage 工具栏「成员」图标也可达（`KeysPage.swift:84`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mem-01 | 四枚芯片（成员 / 活跃 / 归档 / 未归属记录） | 横向滚动 | DB.members、MemberHub.archivedIDs、DB.listPwds | | 能 | 是 —— 与 ManagerFace 组页胶囊「成员/活跃/归档」同一组数 | 中 |
| ui-mem-02 | 「钥匙分布」卡（密码/临时码/指纹三条 + 三环） | 自动 | DB.listPwds / listFps | | 能 | 是 —— 与 KeysPage「库存分布」几乎同一张卡 | **中** |
| ui-mem-03 | 「成员分布」卡（钥匙总数 / 指纹总数 + 环） | 自动 | 同上 | 与 ui-mem-02 数据源完全相同 | 能 | 是 —— **同页两张卡读同一批数据** | **高** |
| ui-mem-04 | 头像横滑条（每位成员一枚头像） | 点头像 | MemberAvatar | push 成员详情 | 能 | 是 —— 与 rosterCard 同一去处 | 中 |
| ui-mem-05 | 成员名单卡（行：头像 + 名 + 角色 + 名下钥匙数 + 最近开门） | 点行 | DB.members、MemberHub.activity | push MemberDetail360View | 能 | 是（与 ui-mem-04 同一去处） | 中 |
| ui-mem-06 | 归档成员入口行 → MemberArchivedView | 点行 | 无 | | 能 | 是 —— Tab 3 组页「已归档」同一页 | 中 |
| ui-mem-07 | 匿名认领入口行 → UnclaimedClaimView | 点行 | 无 | | 能 | 否 | 低 |
| ui-mem-08 | 家庭设置入口行 → MemberFamilySettingsView | 点行 | 无 | | 能 | 否 | 低 |
| ui-mem-09 | 空态「添加成员」 | 点 | MemberWizardView sheet | | 能 | 是 —— 工具栏「+」与 Tab 3「添加成员」同一页 | 中 |
| ui-mem-10 | 工具栏「新增成员」 | 点 | MemberWizardView sheet | | 能 | 是（同上） | 中 |

---

## 19. MemberCenterView.swift（成员中心五页 · 1832 行）

本文件含 6 个 struct：`MemberDetail360View` / `MemberWizardView` / `MergeMembersView` /
`MemberArchivedView` / `MemberFamilySettingsView` / `UnclaimedClaimView` / `MemberExitWizard` / `MemberAvatar`。

### 19.1 MemberDetail360View（成员详情 360°）

入口：MembersPage 名单行 / 头像条 / HomeConsole 成员胶囊（三处）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mdet-01 | 三枚指标卡（名下钥匙 / 可证明归属凭证 / 近 30 天开门） | 自动 | MemberHub.activity | | 能 | 否 | 低 |
| ui-mdet-02 | 「最近活动」卡（最近 N 条可归属开门） | 自动 | MemberHub.recentExcerpts | | 能 | 是 —— 与下方 ui-mdet-05「最近开门(约)」读同一函数 | **高** |
| ui-mdet-03 | 本周一句话（MemberHub.weekSentence 高亮条） | 自动 | MemberHub.weekSentence | | 能 | 否 | 低 |
| ui-mdet-04 | 「档案」区（关系/电话/生日/代号/分组/便签 分行） | 自动 | MemberHub.ext、DB.setMemberInfo | | 能 | 否 | 低 |
| ui-mdet-05 | 「名下钥匙」区（密码 N 条 / 指纹 N 条 + 逐条列出） | 自动 | DB.listPwds / listFps | 逐条**不可点** | 能 | 否 | 低 |
| ui-mdet-06 | 「最近开门 (约)」区（10 条，标「约」） | 自动 | MemberHub.recentExcerpts(m.id,10) | | 能 | 是（见 ui-mdet-02） | **高** |
| ui-mdet-07 | 「钥匙停用动态」区（SensitiveLedger.memberItems） | 自动 | SensitiveLedger | | 能 | 否 | 中 |
| ui-mdet-08 | 「授权来源」三格（创建 / 移交 / 恢复） | 自动 | MemberHub.sourceCounts | | 能 | 否 | 中 |
| ui-mdet-09 | 「家庭场景」区（角色说明 + 权限能/不能 + 代管提示） | 自动 | MemberHub.permAllows / permRows | | 能 | 否 | 低 |
| ui-mdet-10 | 工具栏 ⋯ 菜单「补全档案」 | 菜单 | editProfile | 打开编辑弹窗（关系/电话/生日/代号/分组/便签） | 能 | 否 | 低 |
| ui-mdet-11 | 工具栏 ⋯ 菜单「重复合并」 | 菜单 | MergeMembersView sheet | | 能 | 否 | 中 |
| ui-mdet-12 | 工具栏 ⋯ 菜单「退出处置向导」 | 菜单 | MemberExitWizard sheet | | 能 | 否 | 中 |
| ui-mdet-13 | 工具栏 ⋯ 菜单「删除并级联提示」 | 菜单 → 对话 | DB.removeMember / cascadeBin | 两个选项：只移除档案 / 连锁端一起收回 | 能 | 否 | 低 |
| ui-mdet-14 | 「补全档案」编辑弹窗：姓名 / 关系 / 电话 / 生日 / 代号 / 分组 / 便签 | 输入 | DB.renameMember、setMemberInfo | | 能 | 否 | 低 |

### 19.2 MemberWizardView（建档向导）

入口：MembersPage 工具栏「+」/ 空态按钮；Tab 3 组页第二行「添加成员」。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mwiz-01 | 三步步骤条 | 自动 | step | | 能 | 否 | 低 |
| ui-mwiz-02 | 第 1 步：称呼输入（汉字/英文/数字 ≤20） | 输入 | 手动 | | 能 | 否 | 低 |
| ui-mwiz-03 | 第 1 步：代号（emoji）横向画廊 | 点 | emoji | 8 个预设 + 首字 | 能 | 否 | 低 |
| ui-mwiz-04 | 第 2 步：角色选择（inline Picker，带每档能力副标题） | 点 | MemberHub.roles / rolePickHint | | 能 | 否 | 低 |
| ui-mwiz-05 | 第 2 步：备注名输入 | 输入 | remark | | 能 | 否 | 低 |
| ui-mwiz-06 | 第 3 步：「顺路建 10 分钟临时码」开关 + 6~8 位码值输入 | 开关/输入 | app.lock.pwdAdd | | 能 | 否 | 中 |
| ui-mwiz-07 | 第 3 步：「录指纹后到钥匙页指归属」跳转链接 | 点 | AddFingerPage | 建完成员再录指纹 | 能 | 是 —— AddFingerPage 主入口在 Tab 1 | 中 |
| ui-mwiz-08 | 「下一步 / 完成」主按钮（三步校验） | 点 | createMember / submit | | 能 | 否 | 低 |
| ui-mwiz-09 | 工具栏「取消」 | 点 | dismiss | | 能 | 否 | 低 |

### 19.3 MergeMembersView（合并成员）

入口：MemberDetail360View ⋯ 菜单「重复合并」。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mmerge-01 | 主档展示（当前成员，不可改） | 自动 | MemberHub.display | | 能 | 否 | 低 |
| ui-mmerge-02 | 副档选择 Picker（名下钥匙数一并显示） | 点 | DB.members、MemberHub.activity | 无同名候选时提示先重命名 | 能 | 否 | 低 |
| ui-mmerge-03 | 「会发生什么」迁移预览（逐锁逐类条数） | 自动 | DB.listPwds / listFps | | 能 | 否 | 低 |
| ui-mmerge-04 | 「执行合并」（不可撤销） | 点 | setPwdOwner / setFpOwner / reassignClaims / removeMember | | 能 | 否 | 低 |

### 19.4 MemberArchivedView（已归档成员）

入口：Tab 3 组页第三行「已归档」；MembersPage secondaryCard 亦有入口（两条）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-march-01 | 「归档规则」三格（钥匙不删 / 记录保留 / 不占名额） | 静态 | 无 | | 能 | 否 | 低 |
| ui-march-02 | 归档总览双卡（已归档 N 位 / 待认领 N 份钥匙） | 自动 | DB.members、DB.keychains | | 能 | 否 | 低 |
| ui-march-03 | 归档统计卡（环 + 归档率） | 自动 | 同上 | | 能 | 是 —— 与 ui-march-02 同读数 | 中 |
| ui-march-04 | 归档成员行 + 「恢复」 | 点 | MemberHub.saveExt(archived=false) | 恢复后钥匙仍是「未分配」 | 能 | 否 | 低 |
| ui-march-05 | 空态（归档列表为空） | 自动 | 列表空 | | 能 | 否 | 低 |

### 19.5 MemberFamilySettingsView（家庭设置）

入口：MembersPage secondaryCard 第三行。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mfam-01 | 「长辈模式」开关（钥匙页大字/只留两组、临时码完成页收成口述卡） | 开关 | MemberHub.setElderMode | 展开后有大段说明 | 能 | 否 | 中 |
| ui-mfam-02 | 「隐私浏览」开关（10 分钟自动关闭 + 剩余秒数回显） | 开关 | MemberHub.setPrivacy | | 能 | 是 —— 与 SecurityPeekView「限时可见」概念重叠（但作用域不同） | 中 |
| ui-mfam-03 | 「家庭协作」状态卡（代管中 / 3 天内到期临时码） | 自动 | MemberHub.proxyNames、careDue | | 能 | 否 | 中 |
| ui-mfam-04 | 工具栏「保存」 | 点 | 写两项设置 | | 能 | 否 | 低 |

### 19.6 UnclaimedClaimView（匿名认领）

入口：MembersPage secondaryCard 第二行「匿名认领」。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mclaim-01 | 认领统计卡（未归属记录 N 条 + 环） | 自动 | DB.listPwds（owner 为空） | | 能 | 否 | 低 |
| ui-mclaim-02 | 未归属记录列表（时间 + 类型 + 「当天还有 N 条」） | 自动 | 同上，最多 20 条 | | 能 | 否 | 低 |
| ui-mclaim-03 | 每条一个「认领给」Picker（排除已归档成员） | 点 | DB.members | | 能 | 否 | 低 |
| ui-mclaim-04 | 「认领所选 (N)」批量提交 | 点 | MemberHub.claim | 只写本机覆盖层，不改锁端 | 能 | 否 | 低 |
| ui-mclaim-05 | 工具栏「完成」 | 点 | dismiss | | 能 | 否 | 低 |

### 19.7 MemberExitWizard（退出处置向导）

入口：MemberDetail360View ⋯ 菜单「退出处置向导」。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mexit-01 | 待处置总览卡（保留 N / 移交 N / 停用 N） | 自动 | decisions | | 能 | 否 | 低 |
| ui-mexit-02 | 逐条处置菜单（移交他人 / 停用入回收站 / 保留原样） | 菜单 | decide(it, …) | | 能 | 否 | 低 |
| ui-mexit-03 | 「移交给谁」二次确认（多候选时） | 点 → 对话 | moveTargets | 不替用户抓第一个 | 能 | 否 | 低 |
| ui-mexit-04 | 「归档并执行」 | 点 | MemberHub.saveExt(archived=true) | 未全部决策时 toast 拦截 | 能 | 否 | 低 |
| ui-mexit-05 | 工具栏「取消」 | 点 | dismiss | | 能 | 否 | 低 |

### 19.8 MemberAvatar

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-mavatar-01 | 成员头像组件（首字/emoji + 色底 + 角标：访客/代管） | 组件 | MemberHub.ext、visitorId | 被 MembersPage / 详情 / 门厅复用 | 能（组件） | 否 | 低 |

---

## 20. MePage.swift（本机设置 · 480 行）

入口：系统 Tab 组页「本机设置」（`ManagerRoute.me`）。**这是全 App 最关键的二级入口枢纽** ——
SecurityPage / AlarmsPage / BackupPage / LocksPage / DevicePage / LockProfilePage / LinkPrefsView /
AutoCalView / EventsPage / FeedPage / IconPicker / CarePage / CareRemindersView 十三页都从这里进。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-me-01 | 四枚芯片（应用锁 / 待处理告警 / 上次导出 / 门锁数） | 横向滚动 | DB.hasPasscode、unhandledAlarmCount、kf_bk_last_export、DB.keychains | | 能 | 是 —— 与 ManagerFace 系统组胶囊、ui-me-02 重复 | 中 |
| ui-me-02 | 「本机状态」主角卡（待办 N 项 + 72pt 环 + 四枚可点瓦片） | 点瓦片 | 同上 | 四瓦片 = 应用锁/告警/备份/门锁 四个入口 | 能 | 是 —— **瓦片与芯片行报同一组数**；瓦片目标又和下面各 section 行重复 | **高** |
| ui-me-03 | 瓦片「应用锁」→ SecurityPage | 点 | 无 | | 能 | 是 —— ui-me-04 同目标 | 中 |
| ui-me-04 | 瓦片「待处理告警」→ AlarmsPage | 点 | 无 | | 能 | 是 —— ui-me-05 同目标 | 中 |
| ui-me-05 | 瓦片「上次备份」→ BackupPage | 点 | 无 | | 能 | 是 —— ui-me-06 同目标 | 中 |
| ui-me-06 | 瓦片「门锁」→ LocksPage | 点 | 无 | | 能 | 是 —— Tab 2 与 ui-me-07 同目标 | 中 |
| ui-me-07 | 「隐私与伪装」行 → SecurityPeekView | 点行 | 无 | | 能 | 是 —— SecurityPage「防窥与遮蔽」同一页 | 中 |
| ui-me-08 | 「备份恢复」卡（上次备份 / 门锁数 / 钥匙总数 + 去备份与恢复） | 点 | DB.keychains、kf_bk_last_export | | 能 | 是（见 ui-me-05） | 中 |
| ui-me-09 | 「这台锁」行 → DevicePage | 点行 | 无 | 副标题 容量/固件/信号 | 能 | 是 —— Tab 2「我的门锁」不同页（DevicePage vs LocksPage） | 低 |
| ui-me-10 | 「锁档案」行 → LockProfilePage | 点行 | 无 | | 能 | 否 | 低 |
| ui-me-11 | 「开锁偏好」行 → LinkPrefsView（Core 层） | 点行 | 无 | | 能 | 否 | 低 |
| ui-me-12 | 「靠近自动开锁」行 → AutoCalView（Core 层） | 点行 | 无 | | 能 | 否 | 低 |
| ui-me-13 | 「事件记录」行 → EventsPage | 点行 | 无 | | 能 | 是 —— HomeConsole「今日开门分布」卡头同目标 | 中 |
| ui-me-14 | 「动态消息」行 → FeedPage | 点行 | 无 | 带未处理告警角标 | 能 | 是 —— 与 EventsPage 内容高度重叠（见 ui-feed 段） | **高** |
| ui-me-15 | 「App 图标」行 → IconPicker | 点行 | 无 | | 能 | 否 | 低 |
| ui-me-16 | 「维护与保养」行 → CarePage | 点行 | 无 | | 能 | 否 | 低 |
| ui-me-17 | 「关怀提醒」行 → CareRemindersView | 点行 | 无 | | 能 | 否 | 低 |

**本文件疑点**
- 「本机状态」卡的 4 枚瓦片与紧邻上方的 4 枚芯片**报的是同一组数**，且瓦片目标在本页下方全部又出现一遍
  （应用锁→SecurityPage、告警→AlarmsPage、备份→BackupPage、门锁→LocksPage 各有一行/一卡）。
  一屏之内 4 个入口各有 2 份 → 冗余嫌疑高。
- `FeedPage`（动态消息）与 `EventsPage`（事件记录）都从本页进，都读同一批 `kf_logcache`，
  一个按天分组时间线、一个按天分组动态卡 —— 用户很难说清两者差别（见 §26/§23）。

---

## 21. SecurityPage.swift（安全总览 · 364 行）

入口：MePage 瓦片「应用锁」/ ui-me-03（`MePage.swift:144`）；StatsPage 的 sheet 也可达（`StatsPage.swift:91`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-sec-01 | 「现在安全吗」状态卡（总判 + 四盏灯：应用锁/审计链/备份/告警） | 自动 | DB.hasPasscode、AuditLog、kf_bk_last_export | | 能 | 是 —— 与 ui-me-02「本机状态」同族判读 | 中 |
| ui-sec-02 | 「有没有事」风险卡（逐条风险：到期/审计断链/告警） | 自动 | risks 计算属性 | | 能 | 是 —— 与 AlarmsPage 待处理列表重叠 | 中 |
| ui-sec-03 | 行「应用锁」→ AppLockSetupView | 点行 | 无 | | 能 | 否 | 低 |
| ui-sec-04 | 行「防窥与遮蔽」→ SecurityPeekView | 点行 | 无 | | 能 | 是 —— ui-me-07 同目标 | 中 |
| ui-sec-05 | 行「审计日志」→ SecurityAuditView | 点行 | 无 | | 能 | 是 —— 系统 Tab 组页「安全审计」同目标 | 中 |
| ui-sec-06 | 行「回收站」→ CredentialBinView | 点行 | 无 | | 能 | 是 —— 销毁数据页内也有回收站入口 | 中 |
| ui-sec-07 | 行「彻底销毁」→ SecurityDestroyView | 点行 | 无 | | 能 | 是 —— 系统 Tab 组页「销毁数据」同目标 | 中 |
| ui-sec-08 | 底部说明「这几条都是本机能力」 | 静态 | 无 | | 能 | 否 | 低 |

---

## 22. SecurityCenterView.swift（隐私/审计/销毁三页 · 1880 行）

含 `SecurityPeekView` / `SecurityAuditView` / `SecurityDestroyView` / `PrivacyDashboard` + 令牌类。

### 22.1 SecurityPeekView（防窥与遮蔽）

入口：MePage「隐私与伪装」行、SecurityPage「防窥与遮蔽」行、PrivacyDashboard 反向无入口。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-peek-01 | 遮蔽样式预览卡（圆点/星号/末4位 三种样例） | 点分段 | SecKey.maskStyle | | 能 | 是 —— 与下方 ui-peek-03 同一设置 | 中 |
| ui-peek-02 | 「隐私总览」四格（已开启/未开启计数） | 自动 | 各项开关 | | 能 | 是 —— 与 PrivacyDashboard ui-peek-14 重复 | 中 |
| ui-peek-03 | 「码值遮蔽样式」Picker（圆点/星号/末 4 位） | 点菜单 | SecKey.maskStyle | | 能 | 是（见 ui-peek-01） | 中 |
| ui-peek-04 | 「剪贴板自动清除」Picker（关/30s/60s/5min） | 点菜单 | ClipboardCare.setTTL | | 能 | 否 | 低 |
| ui-peek-05 | 「隐私总览」→ PrivacyDashboard 跳转行 | 点行 | 无 | | 能 | 是（ui-peek-14 是被指向页） | 中 |
| ui-peek-06 | 「切后台即糊」开关 | 开关 | SecKey.bgBlurOn | 立即生效 + overlay 遮罩 | 能 | 否 | 低 |
| ui-peek-07 | 「限时可见」Picker（关/10/30/60 秒） | 点菜单 | SecKey.timedReveal | 到点自动复遮 | 能 | 是 —— 与 ui-mfam-02 隐私浏览概念重叠 | 中 |
| ui-peek-08 | 「磨砂挡片」演示行（长按 0.5s 揭开） | 长按 | SecKey.frostedOn | 演示型交互 | 能 | 否 | 中 |
| ui-peek-09 | 「分享遮半」开关 | 开关 | SecKey.shareHalfOn | | 能 | 否 | 低 |
| ui-peek-10 | 「访客通道」开关（打开即收起两页） | 开关 | SecurityPolicy.guestActive | | 能 | 否 | 低 |
| ui-peek-11 | 「访客隐藏敏感成员」开关（仅访客通道开时出现） | 开关 | SecKey.sensitiveOnly | 源码自注"判据口已就位等数据侧"→ 实际不生效 | 需访客通道开 | 否 | **高** |
| ui-peek-12 | 「常驻水印」开关 | 开关 | SecKey.watermarkOn | | 能 | 否 | 低 |
| ui-peek-13 | 「水印文案」自定义（UIAlertController 输入） | 点 → alert | SecKey.watermarkTxt | 仅水印开时出现 | 能 | 否 | 低 |
| ui-peek-14 | PrivacyDashboard：总览卡（已启用 N/M 项 + 84pt 环） | 自动 | PeekItem.all | | 能 | 是 —— 与 ui-peek-02 同读数 | **高** |
| ui-peek-15 | PrivacyDashboard：逐项开关列表（点即切换） | 点行 | togglePeek | 5 项：切后台即糊/磨砂挡片/分享遮半/访客通道/常驻水印 | 能 | 是 —— **与 ui-peek-06/08/09/10/12 完全同一批开关** | **高** |
| ui-peek-16 | 切后台自动遮罩（"已切后台 — 回前台过应用锁后恢复清晰"） | 自动（scenePhase） | SecKey.bgBlurOn | | 能 | 否 | 低 |

**22.1 疑点（重要）**：`PrivacyDashboard` 里 5 个开关与 `SecurityPeekView` 主页面上的 5 个开关
**逐项一一对应**（同一批 `SecKey` 常量、同一个 `togglePeek` 写同一存储键），
且两者都有总览计数卡。这是一个页面被拆成两屏、内容几乎相同 —— 冗余嫌疑高。

### 22.2 SecurityAuditView（审计流水）

入口：系统 Tab 组页「安全审计」；SecurityPage「审计日志」行（两条）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-audit-01 | 双流水分段（管理流水 N / 门锁流水 N） | 点分段 | AuditLog.adminEvents / doorEvents | | 能 | 否 | 低 |
| ui-audit-02 | 审计条目列表（时间 + 动作 + 目标 + 操作者，可展开详情） | 点行展开 | AuditLog().load() | duress 标记 | 能 | 否 | 低 |
| ui-audit-03 | 「校验完整性」按钮 + 结果条 | 点 | AuditLog 链式 SHA-256 重算 | | 能 | 否 | 低 |
| ui-audit-04 | 「手动补记一条」按钮 | 点 | AuditLog().append | 记一条"手动补记" | 能 | 否 | 中 |
| ui-audit-05 | 保留期 Picker（3/6/12 个月/永久） | 点菜单 | SecKey.auditRetention | | 能 | 否 | 低 |
| ui-audit-06 | 「立即清理到期条目」 | 点（guardedDestroy 闸） | AuditLog().purgeExpired | 只读模式/无口令时被拦 | 能 | 否 | 低 |
| ui-audit-07 | 「导出审计 JSON（脱敏）」 | 点（闸） | doExport("脱敏") | | 能 | 是 —— 与 ExportCenter 导出一族重叠 | 中 |
| ui-audit-08 | 「导出含明文（需确认）」 | 点 → alert | doExport("含明文") | 明文口令原样写出 | 能 | 是（同上） | 中 |
| ui-audit-09 | 「毁灭操作 sudo 口令」开关 | 开关 | SecKey.sudoOn | 无应用锁时警告 | 能 | 否 | 低 |
| ui-audit-10 | 敏感操作视图（最近 5 条：查看/复制/导出明文） | 自动 | SensitiveLedger().recent(5) | | 能 | 是 —— 与成员详情的「钥匙停用动态」同源账本 | 中 |
| ui-audit-11 | 快捷指令执行记录（最近 10 条 intent） | 自动 | SensitiveLedger().intentItems(10) | | 能 | 否 | 中 |

### 22.3 SecurityDestroyView（销毁与应急）

入口：系统 Tab 组页「销毁数据」；SecurityPage「彻底销毁」行。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-destroy-01 | 「销毁会删掉多少」卡（N 条密码 + N 枚指纹 + 全部审计链） | 自动 | DB.keychains / listPwds / listFps | | 能 | 否 | 低 |
| ui-destroy-02 | 三级销毁条（三级刻度可视化） | 自动 | DestroyKit | | 能 | 否 | 低 |
| ui-destroy-03 | 「销毁前备份闸」状态行 | 自动 | DestroyKit.backupGatePass | | 能 | 否 | 低 |
| ui-destroy-04 | 「我理解销毁不可恢复」勾选 | 开关 | ack | 未勾选时其余控件不出现 | 能 | 否 | 低 |
| ui-destroy-05 | sudo 口令输入 + 「验证」 | 输入/点 | DB.verifyPasscode | 仅 sudoRequired 且未验证时出现 | 能 | 否 | 低 |
| ui-destroy-06 | 「键入 销毁 二字」输入框 | 输入 | typedWord == "销毁" | 双闸第二道 | 能 | 否 | 低 |
| ui-destroy-07 | 「销毁全部数据」主按钮 | 点 → 备份闸对话 | runDestroy / commitDestroy | 有"先去备份 / 仍要销毁"分支 | 能 | 否 | 低 |
| ui-destroy-08 | 销毁结果报告 + 残留检测提示 | 自动 | destroyReport / residueMsg | | 能 | 否 | 低 |
| ui-destroy-09 | 「查看回收站（可恢复）」→ CredentialBinView | 点 | 无 | | 能 | 是 —— SecurityPage 也有回收站入口 | 中 |
| ui-destroy-10 | 「清空回收站」长按 2 秒填充控件 | 长按 2s | clearTrash（guarded） | 松手取消 | 能 | 否 | 低 |
| ui-destroy-11 | 「离职清除」逐成员「清除」按钮 | 点 | Offboard.markDeparted | 归档名下钥匙并留痕 | 能 | 是 —— 与成员退出处置向导语义重叠 | 中 |
| ui-destroy-12 | 「只读安全模式」开关 + 已接线拦点说明 | 开关 | SecKey.safeModeOn | 源码自注"还没接上的：添加/改造钥匙、网关配网、固件升级" | 能 | 否 | 中 |
| ui-destroy-13 | 「口令复用检测」开关 + 演示行 | 开关 | SecKey.pwdReuseOn | | 能 | 否 | 低 |
| ui-destroy-14 | 「保存密码二次输入」开关 | 开关 | kf_scred_2nd | 无任何 UI 读取它做实际拦截 | 能 | 否 | **高** |
| ui-destroy-15 | 「敏感操作视图」两个 XDataRow（重输口令=是 / 键入销毁=是） | 静态 | SecurityPolicy.sudoRequired | 纯说明 | 能 | 否 | 低 |
| ui-destroy-16 | 页面每 2 秒重算（Timer.publish） | 自动 | center.bump() | 用于 sudo 票据过期刷新 | 能 | 否 | 低 |

---

## 23. AppLockSetupView.swift（应用锁设置 · 275 行）

入口：SecurityPage「应用锁」行（`SecurityPage.swift:297`）。**只此一条**。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-applock-01 | 主卡「应用锁」状态（1/0 + 锁图标 + 76pt 环 + 一句后果说明） | 自动 | on = hasPasscode | | 能 | 否 | 低 |
| ui-applock-02 | 「保护项」三行（打开 App 要口令 / 密码默认不显示 / 切后台变糊） | 自动 | on | 纯展示，三项共享同一个 on | 能 | 否 | 中 |
| ui-applock-03 | 设置/修改口令：两个 SecureField（至少 N 位 + 再输一遍） | 输入 | 手动 | | 能 | 否 | 低 |
| ui-applock-04 | 两遍不一致即时提示 | 自动 | pw != pw2 | | 能 | 否 | 低 |
| ui-applock-05 | 「启用应用锁 / 保存新口令」主按钮 | 点 | DB.setPasscode | | 能 | 否 | 低 |
| ui-applock-06 | 「取消」编辑态 | 点 | editing = false | 仅编辑时出现 | 能 | 否 | 低 |
| ui-applock-07 | 「修改口令」行 | 点 | editing = true | | 能 | 是 —— 与 ui-applock-03 同一表单 | 中 |
| ui-applock-08 | 「关闭应用锁」行 + 破坏性确认 | 点 → 对话 | DB.setPasscode(off) | 说明"关闭后谁都能看到密码" | 能 | 否 | 低 |
| ui-applock-09 | 「它保护什么」说明卡 | 静态 | 无 | | 能 | 否 | 低 |

---

## 24. EventsPage.swift（事件记录 · 904 行）

入口：MePage「事件记录」行（`MePage.swift:400`）；HomeConsole 两处 sheet（卡头 › + 柱图点选，均带 initialHour）；StatsPage sheet。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-ev-01 | 顶部三芯片（今日 / 告警 / 本机保留） | 横向滚动 | filtered | | 能 | 是 —— 与页面副标题同组数 | 中 |
| ui-ev-02 | 大标题「事件」+ 副标题（本机保留 N 条 · 今日 N 条） | 自动 | 同上 | | 能 | 是（同上） | 中 |
| ui-ev-03 | 搜索框（`.searchable`，回车入历史） | 输入/回车 | RecordSearch.pushHistory | | 能 | 否 | 低 |
| ui-ev-04 | 工具栏「统计」→ StatsPage | 点图标 | 无 | | 能 | 是 —— StatsPage 无其他入口，此处即唯一 | 低 |
| ui-ev-05 | 工具栏「告警」→ AlarmsPage | 点图标 | 无 | | 能 | 是 —— MePage 瓦片也到同一页 | 中 |
| ui-ev-06 | 工具栏筛选菜单：只看告警（记住选择） | 菜单开关 | filters.save(mac) | | 能 | 是 —— FeedPage 也有同款"只看告警" | **高** |
| ui-ev-07 | 工具栏筛选菜单：刷新 | 菜单 | load() | | 能 | 是 —— 下拉刷新同效 | 低 |
| ui-ev-08 | 工具栏筛选菜单：从门锁同步日志 | 菜单 | app.lock 日志拉取 → DB.writeLogs | 同步详情可复制 | 能 | 否 | 低 |
| ui-ev-09 | 工具栏筛选菜单：存为筛选视图 | 菜单 → alert 命名 | RecordSearch.saveNamedView | | 能 | 否 | 中 |
| ui-ev-10 | 工具栏筛选菜单：清空最近搜索 | 菜单 | RecordSearch.clearHistory | | 能 | 否 | 低 |
| ui-ev-11 | 工具栏筛选菜单：清除失败记录 | 菜单 | DB.clearFailEvents | 破坏性 | 能 | 否 | 中 |
| ui-ev-12 | 已存筛选视图胶囊（点应用 / 长按删除） | 点 / 长按 | RecordSearch.namedViews | | 能 | 否 | 中 |
| ui-ev-13 | 最近搜索胶囊（点应用 / 长按移除） | 点 / 长按 | RecordSearch.history | | 能 | 否 | 中 |
| ui-ev-14 | 小时过滤条（只看今天 H:00–H:59 / 看全部） | 点 | hourFilter | 从门厅柱图进入时出现 | 需从柱图进入 | 否 | 低 |
| ui-ev-15 | 概览条（N 条记录 + 环 + 告警 N 条提示） | 自动 | recs | | 能 | 是 —— 与 ui-ev-01/02 第三次重复 | **高** |
| ui-ev-16 | 按天分组时间线（日期头 + 条数 + 告警计数） | 自动 | grouped | | 能 | 是 —— FeedPage 同一天分组结构 | **高** |
| ui-ev-17 | 单条时间线行（时间 + 类型点 + 动词 + 类型标签 + 归属"约"） | 自动 | RecordSearch.buildRecs | | 能 | 否 | 低 |
| ui-ev-18 | 行长按菜单：添加/编辑备注 | 长按 | RecordOverlay.setNote | 最多 60 字 | 能 | 否 | 低 |
| ui-ev-19 | 行长按菜单：删除备注 | 长按 | 同上置空 | | 能 | 否 | 低 |
| ui-ev-20 | 行备注展示（气泡图标 + 备注） | 自动 | RecordOverlay.note | | 能 | 否 | 低 |
| ui-ev-21 | 下拉刷新 | 下拉 | load() | | 能 | 否 | 低 |
| ui-ev-22 | 同步中顶部浮条（"正在从门锁同步…"） | 自动 | syncing | | 能 | 否 | 低 |

**疑点**：本页与 `FeedPage` 都读 `kf_logcache`、都按天分组、都有"只看告警"开关、
都在天头显示告警计数 —— 结构差异只剩"卡片 vs 时间线"。两者并存冗余嫌疑高（见 §26）。

---

## 25. AlarmsPage.swift（告警中心 · 466 行）

入口：EventsPage 工具栏「告警」、MePage 瓦片、StatsPage 安全卡 sheet、（QuickPool 不可达不算）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-alarm-01 | 严重度总览卡（N 条 + 三环 + 一级/二级/三级三列） | 自动 | AlarmMeta.level | | 能 | 是 —— 与 ui-ev-15 同读数族 | 中 |
| ui-alarm-02 | 一级告警置顶大卡（红色 + 已持续时长 + 「知道了」按钮） | 点 | markHandled(top) | | 能 | 否 | 低 |
| ui-alarm-03 | 待处理列表（N 条待处理组头 + 逐条行） | 自动 | RecordSearch.buildRecs | | 能 | 是 —— EventsPage 告警过滤视图重复 | **高** |
| ui-alarm-04 | 行内「标记已处理」按钮 | 点 | markHandled(rec) | | 能 | 否 | 低 |
| ui-alarm-05 | 已处理折叠（显示 N 条已处理 → 展开） | 点 | showHandled | | 能 | 否 | 低 |
| ui-alarm-06 | 空态（没有告警 · 所有记录都正常） | 自动 | alarms.isEmpty | | 能 | 否 | 低 |

---

## 26. StatsPage.swift（统计 · 467 行）

入口：EventsPage 工具栏「统计」（`EventsPage.swift:165`）。**只此一条**（sheet 除外）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-stats-01 | 顶部双胶囊（总开门 / 告警） | 自动 | StatsKit.build | | 能 | 否 | 低 |
| ui-stats-02 | 「今日构成」三环卡（密码/指纹/自动比例） | 自动 | model | | 能 | 是 —— HomeConsole ui-home-11 同构（但本页接真数据） | 中 |
| ui-stats-03 | 「安全」卡（告警率 / 有告警的天 / 总开门 → sheet SecurityPage） | 自动/点 | model | | 能 | 是 —— ui-sec-01 同页重复进入 | 中 |
| ui-stats-04 | 「怎么开的门」帕累托条形卡（密码/指纹/临时码/钥匙 + 占比） | 自动 | model.pareto → showEvents | | 能 | 否 | 低 |
| ui-stats-05 | 「一天里什么时候最忙」分段卡（早/中/晚/夜） | 自动 | model.dayparts | | 能 | 是 —— 与 ui-stats-08 同维度 | 中 |
| ui-stats-06 | 「工作日出门 · 通常第一次开门」卡 | 自动 | model | | 能 | 是 —— 与 HomeConsole「最早开门」同读数 | 中 |
| ui-stats-07 | 分时分布卡（24h 柱状 + 峰值时刻） | 自动 | model | | 能 | 是 —— 第三份 24h 柱图（HomeConsole/FeedPage） | **高** |
| ui-stats-08 | 「近 14 天开门趋势」卡 | 自动 | model | | 能 | 是 —— HomeConsole「开门历史 21 天」几乎同一张图 | **高** |
| ui-stats-09 | 降级卡（样本不足） | 自动 | isDegraded | | 能 | 否 | 低 |

---

## 27. FeedPage.swift（动态 · 382 行）

入口：MePage「动态消息」行（`MePage.swift:408`）。**只此一条**。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-feed-01 | 页头卡（N 条动态 / 其中 N 条告警 + 图例） | 自动 | rows | | 能 | 是 —— 与 ui-ev-01/02 同读数 | **高** |
| ui-feed-02 | 「今日时段」概览卡（24h 柱 + 说明） | 自动 | todayCounts | | 能 | 是 —— 第三份 24h 柱图（HomeConsole/StatsPage） | **高** |
| ui-feed-03 | 按天分组动态列表（日期头 + 条数 + 告警数） | 自动 | groupedDays | | 能 | 是 —— 与 EventsPage 分组时间线几乎同构 | **高** |
| ui-feed-04 | 单条动态卡（左色条 + 文案 + 时间 + 锁名） | 自动 | FeedRow | | 能 | 是 —— 与 ui-ev-17 同一行数据的两种渲染 | **高** |
| ui-feed-05 | 空态（还没有动态 → 去添加门锁） | 点 | AddLockPage sheet | | 能 | 是 —— LocksPage/HomeConsole 空态同去处 | 低 |
| ui-feed-06 | 工具栏筛选菜单：只看告警 | 菜单开关 | filterAlarm | | 能 | 是 —— ui-ev-06 同款开关 | **高** |

**结论（重要）**：`FeedPage` 与 `EventsPage` 数据源相同、分组方式相同、过滤开关相同、
告警计数相同 —— **整页冗余嫌疑高**。差异仅是行样式（卡片 vs 时间线）与
FeedPage 不含搜索/备注/同步。保留其一即可。

---

## 28. BackupPage.swift（备份与恢复 · 697 行）

入口：系统 Tab 组页「备份恢复」；MePage 瓦片「上次备份」与「去备份与恢复」（共 3 条入口）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-bk-01 | 「备份时效」卡（环 + 上次备份天数 + 提示） | 自动 | kf_bk_last_export | 环越满越新 | 能 | 是 —— MePage 芯片/瓦片、SecurityPage 灯都报同一数 | 中 |
| ui-bk-02 | 「加密参数」卡（AES-128 / HMAC-SHA256 / PBKDF2 6万轮） | 静态 | 无 | | 能 | 是 —— BackupStudio trustHeader 也展示同参数 | 低 |
| ui-bk-03 | 导出/恢复次数对卡（N 次 / 0 次） | 自动 | BackupStudio.recordEvent | | 能 | 是 —— BackupStudio 头部"上次导出/上次导入"重复 | 中 |
| ui-bk-04 | 导出卡：「生成备份 / 重新生成」 | 点 | generateBackup → exportText | | 能 | 是 —— BackupStudio 导出向导第 4 步"立即导出"同一动作 | **高** |
| ui-bk-05 | 导出卡：「保存到文件」（fileExporter） | 点 | BackupFile | 存 iCloud/本机 | 能 | 是 —— BackupStudio 同能力 | **高** |
| ui-bk-06 | 导出卡：「复制备份文本」 | 点 | UIPasteboard | | 能 | 是 —— 同上 | **高** |
| ui-bk-07 | 恢复卡：「从文件导入」（fileImporter） | 点 | handleFileImport → parsePreview | .enc/.data | 能 | 是 —— RestoreWizardView 第 1 步粘贴/选文件同一能力 | **高** |
| ui-bk-08 | 恢复卡：「粘贴备份文本」sheet | 点 | importSheet | 从剪贴板粘贴 | 能 | 是 —— RestoreWizardView inputStep | **高** |
| ui-bk-09 | 导入 sheet：「从剪贴板粘贴」按钮 | 点 | UIPasteboard | | 能 | 是（同上） | **高** |
| ui-bk-10 | 恢复确认卡（备份时间 · N 台设备 · 同机覆盖说明） | 自动 | pendingRestore | | 能 | 是 —— RestoreWizard previewStep | **高** |
| ui-bk-11 | 口令解锁 alert（带口令的备份） | 自动 | promptSecret | | 能 | 是 —— RestoreWizard 同样问口令 | **高** |
| ui-bk-12 | 「备份工作室」入口行 → BackupStudioView sheet | 点 | showStudio | | 能 | 是 —— 页内多数按钮与工作室重复 | 中 |
| ui-bk-13 | 恢复完成 toast + Milestones.recordBackup | 自动 | 无 | 成就记录 | 能 | 否 | 低 |

**疑点（重要）**：`BackupPage` 与 `BackupStudioView`（下一节）**整页功能高度重叠** ——
BackupPage 的导出/导入/口令/确认每一个动作在 BackupStudio 的两个向导里都有"更完整的版本"
（预演、差异报告、冲突解决、快照回滚）。BackupPage 存在的意义只剩"简单路径"，
但两页同时可达，用户面对两套恢复流程。冗余嫌疑高。

---

## 29. BackupStudio.swift（备份工作室三屏 · 1419 行）

含 `BackupStudioView` / `ExportWizardView`（4 步）/ `RestoreWizardView`（4 步）/ `LocalBackupFilesSection`。
入口：BackupPage「备份工作室」行（`BackupPage.swift:113` sheet）。**唯一入口**。

### 29.1 BackupStudioView（工作室主页）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-stu-01 | 「本机备份」卡（N 份文件 + 上次导出 / 上次导入 / 撤销窗口三格） | 自动 | BackupStudio.localFiles / 事件表 | | 能 | 是 —— BackupPage ui-bk-03 重复 | 中 |
| ui-stu-02 | 「撤销本次恢复 (24h 内)」按钮（确认） | 点 → 确认 | undoLastRestore | 无快照时置灰 | 能 | 否 | 中 |
| ui-stu-03 | 信任头（AES 参数徽章 + 自检警告） | 自动 | BackupStudio.selfCheckWarning | | 能 | 是 —— ui-bk-02 | 低 |
| ui-stu-04 | 新鲜度横幅「距上次备份已 N 天 · 立即备份」 | 点 | showExport | | 能 | 是 —— 与 ui-stu-05 同去处 | 低 |
| ui-stu-05 | 「导出向导」「恢复向导」双卡入口 | 点 | sheet | | 能 | 否 | 低 |
| ui-stu-06 | 「备份策略」卡：手动/每周/每月 分段 | 点分段 | BackupStudio.cadence + 日历提醒 | | 能 | 否 | 低 |
| ui-stu-07 | 滚动保留 Stepper（远端只留 N 份 0–20） | 步进 | BackupStudio.rollingKeep | | 能 | 否 | 低 |
| ui-stu-08 | 「导出目录」选择 / 更换 / 取消固定 | 点（fileImporter） | ExportDir.set/clear | | 能 | 否 | 低 |
| ui-stu-09 | 「月度备份日」Picker（关 / 1/5/10/15/20/25/30 日） | 点菜单 | scheduleMonthlyBackup | 本地通知 | 能 | 否 | 中 |
| ui-stu-10 | 「充电时自动备份」开关 | 开关 | kf_bk_bgtask + BGTask | | 能 | 否 | 中 |
| ui-stu-11 | 「本地备份文件」列表（逐文件大小/日期/算法/「删除」） | 点删除 | BackupStudio.deleteLocalFile | 只列"锁管家_"族 | 能 | 否 | 低 |

### 29.2 ExportWizardView（导出向导 4 步）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-expw-01 | 步骤 1：数据分区开关（钥匙区 / 记录区 / 设置区 / OTP） | 开关 | zoneToggle | 记录区超阈值自动拆卷 | 能 | 否 | 低 |
| ui-expw-02 | 步骤 2：加密口令两遍输入（可留空 = 明文） | 输入 | 双 SecureField | 弱口令仅提醒不拦截 | 能 | 否 | 低 |
| ui-expw-03 | 步骤 3：导出前体检（统计摘要 + 问题清单） | 自动 | preExportHealth | | 能 | 否 | 低 |
| ui-expw-04 | 步骤 4：导出完成（已写入本机 + 分享 + 二维码） | 自动 | exportNow | | 能 | 是 —— ui-bk-04/05 | **高** |
| ui-expw-05 | 步骤 4：「生成加密二维码」（钥匙小包，口令信封） | 点 | credentialQRPayload + qrImage | | 能 | 否 | 中 |
| ui-expw-06 | 步骤 4：二维码 ShareLink（口令请另渠道告知提示） | 点 | 系统分享 | | 能 | 否 | 中 |
| ui-expw-07 | 步骤 4：增量补传（逐锁勾选 → 生成增量小包 → 分享） | 勾选+点 | incrementalExportText | | 能 | 否 | 中 |
| ui-expw-08 | 步骤 4：「再生成一份」 | 点 | 重置向导 | | 能 | 否 | 低 |
| ui-expw-09 | 向导底部「上一步 / 下一步 / 导出 / 取消」 | 点 | advance() | | 能 | 否 | 低 |

### 29.3 RestoreWizardView（恢复向导 4 步）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-rstw-01 | 步骤 1：粘贴备份文本（加密或明文 canonical） | 输入 | textEditor | | 能 | 是 —— ui-bk-08 | **高** |
| ui-rstw-02 | 「解析预演」按钮 | 点 | BackupStudio.parsePreview | | 能 | 否 | 低 |
| ui-rstw-03 | 步骤 2：预演卡（schema 升级链 v→v5 逐级） | 自动 | upgradeSteps | | 能 | 否 | 低 |
| ui-rstw-04 | 步骤 2：文件三层检查卡（口令层 / 文件头 / 内容哈希） | 自动 | Preview | 无校验和时"兼容放行"说明 | 能 | 否 | 低 |
| ui-rstw-05 | 步骤 2：同 ID 冲突解决（整批取备份 / 整批取本机 / 逐条选） | 点 | conflicts + conflictChoice | | 能 | 否 | 低 |
| ui-rstw-06 | 步骤 2：合并策略说明 + 「执行前自动打本地快照 24h 可撤销」 | 静态 | makeRollbackPoint | | 能 | 否 | 低 |
| ui-rstw-07 | 「执行恢复」按钮 | 点 | BackupStudio.restore | | 能 | 是 —— ui-bk-10 简化版 | **高** |
| ui-rstw-08 | 步骤 3：差异报告（逐锁对账 N 把 / 记录时间域 / 条数对比） | 自动 | BackupStudio.compare + lockDiffRows | | 能 | 否 | 低 |
| ui-rstw-09 | 完成按钮 | 点 | dismiss | | 能 | 否 | 低 |

---

## 30. ExportCenter.swift（导出中心 · 2687 行）

入口：系统 Tab 组页「导出中心」（`ManagerRoute.export`）。**只此一条**。
含 `ExportCenterView`（主屏）+ 引擎层（`ExportKit` / `CSVBuild` / `ReportBuild` / `PDFText` /
`ReportVerify` / `AlarmShareCardView` / `RecordShareCardView` / `QLPreviewView` / `ExportHistory`）。

### 30.1 ExportCenterView 主屏

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-ex-01 | 「历史导出」卡（近 3 个月柱图 + N 次导出） | 自动 | ExportHistory.monthlyBars | | 能 | 否 | 中 |
| ui-ex-02 | 「将要导出」统计卡（行数 + 分时环） | 自动 | ExportKit.filtered | | 能 | 否 | 中 |
| ui-ex-03 | 范围分段（本周 / 本月 / 近 90 天 / 全部） | 点分段 | ExportRange | | 能 | 否 | 低 |
| ui-ex-04 | 「只看某个成员」菜单（逐成员） | 点菜单 | DB.members | | 能 | 否 | 低 |
| ui-ex-05 | 「列选择」六开关（CSV 六列逐列开关） | 开关 | ExportCols.save | | 能 | 否 | 中 |
| ui-ex-06 | 「脱敏导出」开关（成员名/钥匙号替换） | 开关 | redact | | 能 | 否 | 低 |
| ui-ex-07 | 「CSV 标准导出」 | 点 | buildCSV → 分享 | 表格软件可开 | 能 | 否 | 中 |
| ui-ex-08 | 「原始 JSON + hex」 | 点 | rawJSON → 分享 | 供开发核对 | 能 | 否 | **中**（小众） |
| ui-ex-09 | 「月度 PDF 报告」 | 点 | buildReport（PDF 排版）→ 分享 | 含三句话摘要/柱图/成员条 | 能 | 否 | **中**（可能没人用） |
| ui-ex-10 | 「运行日志」格式分段（CSV/JSON/纯文本）+「生成」 | 点 | runLogData | | 能 | 否 | **中** |
| ui-ex-11 | 「用系统邮件发送」 | 点 | MFMailCompose | | 能 | 否 | 中 |
| ui-ex-12 | 「邮件模板 .eml」 | 点 | emailTemplate | 复制到邮件客户端 | 能 | 是 —— 与 ui-ex-11 目标重叠 | **中** |
| ui-ex-13 | 「导出哪一天」Picker（最新一天 / 逐日） | 点菜单 | latestDayKey | | 能 | 否 | 中 |
| ui-ex-14 | 「单日长图」 | 点 | renderDayPage 拼长图 → 分享/存照片 | | 能 | 否 | 中 |
| ui-ex-15 | 「告警分享卡」（9:16 卡片图） | 点 | AlarmShareCardView | | 能 | 否 | 中 |
| ui-ex-16 | 「告警事实单页」（PDF，物业沟通用） | 点 | alarmFactSheetPDF | | 能 | 否 | **中**（小众） |
| ui-ex-17 | 「加密压缩导出」（口令 ≥6 位 → zip） | 输入+点 | AES-128 zip | | 能 | 否 | 中 |
| ui-ex-18 | 「打印月度记录」 | 点 | presentPrint | 走系统打印 | 能 | 是 —— ui-ex-09 同一 PDF 不同出口 | **高** |
| ui-ex-19 | 「告警一页纸」打印 | 点 | alarmOnePagerPDF + presentPrint | | 能 | 是 —— ui-ex-16 打印版 | **高** |
| ui-ex-20 | 「口述卡打印」 | 点 | oralCardPDF + presentPrint | 给不会用手机的人 | 能 | 否 | 中 |
| ui-ex-21 | 进度区（运行中进度 + 取消 + 失败重试） | 自动/点 | ExportProgress | | 能 | 否 | 低 |
| ui-ex-22 | 完成区（SHA-256 + 逐文件「预览」/「复制文本」/「分享」） | 点 | progress.done | QuickLook 全屏 | 能 | 否 | 低 |
| ui-ex-23 | 「报告校验二维码」生成（范围数据指纹） | 自动（范围变化时） | ReportVerify.code | 无记录时给说明 | 能 | 否 | 中 |
| ui-ex-24 | 「分享这张二维码」ShareLink | 点 | 系统分享 | | 能 | 否 | 中 |
| ui-ex-25 | 「扫码核对」（相机扫别人报告的码） | 点 → sheet | ReportScanSheet → runVerify | 一致/不一致判定 | 能 | 否 | **中**（小众） |
| ui-ex-26 | 「重算本机指纹」 | 点 | loadVerifyCode | | 能 | 否 | 中 |
| ui-ex-27 | 导出路径显示行 | 自动 | lastPath | | 能 | 否 | 低 |
| ui-ex-28 | 工具栏「关闭」 | 点 | dismiss | | 能 | 否 | 低 |

### 30.2 引擎与卡片（同文件，无独立入口）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-ex-29 | `ExportKit.buildReport` PDF 报告排版（封面/目录/柱图/成员条/告警卡） | 由 ui-ex-09 调 | DB | ~220 行绘图代码 | 经 ui-ex-09 | 否 | 中 |
| ui-ex-30 | `ExportKit.oralCardPDF` 口述卡 PDF | 由 ui-ex-20 调 | DB | | 经 ui-ex-20 | 否 | 中 |
| ui-ex-31 | `ExportKit.alarmFactSheetPDF` 告警事实单 | 由 ui-ex-16 调 | DB | | 经 ui-ex-16 | 否 | 中 |
| ui-ex-32 | `ExportKit.alarmOnePagerPDF` 告警一页纸 | 由 ui-ex-19 调 | DB | | 经 ui-ex-19 | 是 —— 与事实单内容高度重叠 | **高** |
| ui-ex-33 | `ExportKit.alarmCard` 告警分享卡图 | 由 ui-ex-15 调 | DB | | 经 ui-ex-15 | 否 | 中 |
| ui-ex-34 | `ExportKit.presentPrint` 打印呈现 | 由打印三钮调 | UIPrintInteractionController | | 经打印钮 | 否 | 低 |
| ui-ex-35 | `ReportVerify.verify` 报告指纹比对文案（四档结果） | 由 ui-ex-25 调 | 报文 token | | 经扫码 | 否 | 中 |
| ui-ex-36 | `ExportHistory` 导出历史记录（monthlyBars） | 由 ui-ex-01 读 | DB.store | | 经 ui-ex-01 | 否 | 低 |
| ui-ex-37 | `QLPreviewView` QuickLook 全屏预览 | 由 ui-ex-22 调 | URL | | 经预览钮 | 否 | 低 |
| ui-ex-38 | `MailDismisser` 邮件控制器托管 | 由 ui-ex-11 调 | MFMailCompose | | 经邮件钮 | 否 | 低 |

**本文件疑点**
- 导出形态多达 **12 种**（CSV/JSON/PDF/运行日志×3 格式/邮件/.eml/长图/告警卡/事实单/加密 zip/打印×3），
  其中"打印月度记录 / 告警一页纸 / 口述卡打印"与"月度 PDF / 告警事实单页 / 口述卡"是**同一批生成器**的
  第二个出口，属重复出口。
- `alarmFactSheetPDF` 与 `alarmOnePagerPDF` 两套 PDF 单页内容高度重叠（均为"单条告警 · 仅含本条数据"）。

---

## 31. ReportVerifyView.swift（扫码核对 sheet · 47 行）

`ReportScanSheet` —— 由 ExportCenter「扫码核对」弹出。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-rv-01 | 相机取景扫码（QR + DataMatrix） | 相机 | DataScannerView | 首条命中即回传 | 经 ui-ex-25 | 是 —— 与 CodeScanSheet 同构扫码壳 | 中 |
| ui-rv-02 | 导航标题「扫码核对」+ 关闭按钮 | 点 | dismiss | | 经 ui-ex-25 | 否 | 低 |

---

## 32. CarePage.swift（维护与保养 · 437 行）

入口：MePage「维护与保养」行（`MePage.swift:458`）。**只此一条**（QuickPool "care" 不可达不算）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-care-01 | 「还剩多少」周期卡（44px 天数 + 三色环 + 上次/下次/周期三列） | 自动 | BatteryCare.care | | 能 | 否 | 低 |
| ui-care-02 | 「该做的」待办卡（换电池/清洁锁体/年度换电/应急钥匙） | 自动 | powerLevel、lastCareAt、yearlyBattDay | | 能 | 是 —— HomeConsole criticalNotice 同族（但更细） | 中 |
| ui-care-03 | 入口行「锁体保养（五项清单）」→ CareChecklistView | 点行 | 无 | | 能 | 是 —— MaintenanceView 内也有同入口 | 中 |
| ui-care-04 | 入口行「换电指引（四步换电 · 记录一次）」→ BatterySwapGuideView | 点行 | 无 | | 能 | 是 —— MaintenanceView swapSection 同入口 | 中 |
| ui-care-05 | 入口行「保养历史」→ MaintenanceView sheet | 点行 | showHistory | | 能 | 否 | 低 |
| ui-care-06 | 「记录本次保养」按钮（todo 行内） | 点 | markCare() | | 能 | 是 —— 五项清单"完成保养"同一动作的捷径 | 中 |

---

## 33. CareViews.swift（保养历史/换电指引/五项清单 · 702 行）

含 `MaintenanceView`（保养历史）、`BatterySwapGuideView`（换电指引）、`CareChecklistView`（五项清单）。
入口：MaintenanceView ← CarePage「保养历史」；BatterySwapGuide ← CarePage / MaintenanceView 换电关怀；CareChecklist ← CarePage / MaintenanceView「开始五项保养」。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-carev-01 | 「保养周期」段（上次保养 + 进度条 + 天数文案） | 自动 | BatteryCare.care | | 能 | 是 —— CarePage ui-care-01 同读数 | **高** |
| ui-carev-02 | 「开始 / 再做一次五项保养」按钮 | 点 | CareChecklistView sheet | | 能 | 是 —— CarePage ui-care-03 同目标 | 中 |
| ui-carev-03 | 「保养历史」列表（前 5 条：更换电池 / 保养完成） | 自动 | BatteryCare.events | | 能 | 否 | 低 |
| ui-carev-04 | 「到记录页查看全部（保养过滤）」 | 点 | pendingRecordsFilter="__care" → .records | | 能 | 是 —— EventsPage 换个过滤器 | 低 |
| ui-carev-05 | 「换电关怀」段：换电池图文指引链接 | 点 | NavigationLink | | 能 | 是 —— CarePage ui-care-04 同目标 | 中 |
| ui-carev-06 | 年度换电提醒开关 + 日期选择（每年 N 月 N 日 10 点通知） | 开关/日期 | saveYearly + CareSchedule | | 能 | 是 —— BackupStudio 月度备份日同机制 | 低 |
| ui-carev-07 | 「上次充电（可充电型号）」记录（弹窗输入分钟） | 点 → alert | markCharge | | 能 | 否 | 中 |
| ui-carev-08 | 「应急钥匙」段：上次打卡 + 「确认应急钥匙还在 · 打卡」 | 点 | saveEkey | 半年一次 | 能 | 否 | 中 |
| ui-carev-09 | 换电指引：当前电量 + 上次换电卡 | 自动 | DB.readStatus、BatteryCare | | 能 | 否 | 低 |
| ui-carev-10 | 换电指引：四步图文步骤（逐条 VoiceOver 描述） | 自动 | BatterySwapGuide 步骤表 | | 能 | 否 | 低 |
| ui-carev-11 | 换电指引：「我换好了 / 已换新」记录按钮 | 点 | recordBatterySwap | 复位低电提醒武装位 | 能 | 否 | 低 |
| ui-carev-12 | 换电指引：「去校准门锁时间」链接 | 点 | SyncTimeView | 换电后建议 | 能 | 是 —— Tab 2 校准时间同目标 | 低 |
| ui-carev-13 | 五项清单：进度环卡（N/5 + 还差 N 项） | 自动 | checks | | 能 | 否 | 低 |
| ui-carev-14 | 五项清单：逐项勾选（滑轨/锁舌/电池触点/指纹头/应急钥匙） | 点 | checks[i].toggle() | 全勾才能完成 | 能 | 否 | 低 |
| ui-carev-15 | 五项清单：「完成保养」按钮 | 点 | markCareToday + addEvent | 记入台账 | 能 | 是 —— CarePage ui-care-06 捷径同效 | 低 |
| ui-carev-16 | 五项清单：保养台账卡（周期 / 上次 / 应急钥匙） | 自动 | BatteryCare | | 能 | 是 —— 与 ui-carev-01 同读数 | 中 |

---

## 34. CareRemindersView.swift（关怀提醒 · 331 行）

入口：MePage「关怀提醒」行（`MePage.swift:465`）。**只此一条**。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-cr-01 | 「生日填写」进度卡（N/M 已填 + 格式说明） | 自动 | Milestones.memberBirthdays | | 能 | 是 —— 与 ui-cr-04 生日卡同读数 | 中 |
| ui-cr-02 | 「最近的纪念」主角卡（N 天 + 倒计时） | 自动 | 结缘日 + 生日取最近 | | 能 | 否 | 低 |
| ui-cr-03 | 「家庭公告板」文本框（写一句常驻家里的话） | 输入（失焦/提交存） | Milestones.bulletin | 显示在多处空态旁 | 能 | 否 | 中 |
| ui-cr-04 | 「纪念日 / 生日」双卡（结缘日 + N 位已填） | 自动 | Milestones | | 能 | 是 —— 与 ui-cr-01 重复 | 中 |
| ui-cr-05 | 「纪念日」卡：结缘日显示 + 「结缘纪念日提醒」开关 | 开关 | CareReminders.reschedule | 本地通知 | 能 | 否 | 低 |
| ui-cr-06 | 「成员生日」卡：「成员生日提醒（提前一天）」开关 + 逐成员生日行 | 开关/自动 | 同上 | | 能 | 否 | 低 |

**疑点**：与门锁本身无关（家庭情感功能），若产品定位收缩，本页整体冗余嫌疑中。
生日数据只能在「成员管理 → 补全信息」里填，本页只读 + 两个开关。

---

## 35. AppearancePage.swift（外观工作室 · 112 行）

入口：系统 Tab 组页「外观工作室」（`ManagerRoute.appearance`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-ap-01 | 「高对比」开关 | 开关 | app.setHighContrast → kf_hc | 跟随系统「增加对比度」再加强 | 能 | 否 | 低 |
| ui-ap-02 | 「一周从 X 开始」四选一（跟随系统/周一/周日/周六） | 点行 | app.setWeekStart → kf_week_start | 影响 Stats/导出周口径 | 能 | 否 | 低 |

**说明**：2026-10-23 裁定「不提供配色选择」，原品牌色七选一已删；本页现在只有这两个开关，
页面标题还叫「外观工作室 · 主题 / 强调色 / 密度」（组页副标题）—— **副标题与实际内容不符**（主题/强调色/密度均不存在）。

---

## 36. IconPicker.swift（App 图标 · 208 行）

入口：MePage「App 图标」行（`MePage.swift:451`）。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-icon-01 | 九宫格图标选择（轻点立即生效） | 点 | setIcon → 替换 alternate icon | | 能 | 否 | 中 |
| ui-icon-02 | 当前图标名 caption | 自动 | currentIcon | | 能 | 否 | 低 |
| ui-icon-03 | 「桌面预览」卡（真实位图 + KF Key 行 + 说明） | 自动 | 位图 | | 能 | 否 | 低 |

---

## 37. DiagnosticsPage.swift（诊断与自检 · 537 行）

入口：系统 Tab 组页「诊断与自检」（`ManagerRoute.diagnostics`）。
源码注释自认："ManagerRoute.diagnostics 之前**没有任何入口行**（死用例）"，2026-10-24 补了入口行。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-diag-01 | 「数据健康」指标卡（孤儿数据 N 项 + 日志断档 N 天 + 自检项逐行） | 自动 | DiagKit 解析 | 进入即重算 | 能 | 否 | 低 |
| ui-diag-02 | 健康结论卡（无问题 / 日志有 N 天没记录） | 自动 | 同上 | | 能 | 否 | 低 |
| ui-diag-03 | 「稳定性」卡（异常退出 / 日志条数 / 本次启动耗时） | 自动 | 运行日志 | 注明"热启动会快很多" | 能 | 否 | 中 |
| ui-diag-04 | 「最近操作」卡（流水 N 条） | 自动 | 操作日志 | | 能 | 是 —— 与审计流水 ui-audit-02 不同账本但同族 | 中 |
| ui-diag-05 | 「蓝牙连接」卡（最近握手 / 失败 N 次 / 提示靠近） | 自动 | 连接日志 | | 能 | 否 | 低 |
| ui-diag-06 | 「日志保留期」四档（90/180/365/全部） | 点 | kf_diag_log_retention | 当场生效 | 能 | 否 | 低 |
| ui-diag-07 | 「归档一年前的旧日志」 | 点 | 归档动作 | | 能 | 否 | 中 |
| ui-diag-08 | 「记录最近操作」开关（关=不写操作流水） | 开关 | 键值 | | 能 | 是 —— 与审计双流水语义冲突（这边关、那边还在记） | **高** |
| ui-diag-09 | 「清空页面耗时记录」 | 点 | 清空 | | 能 | 否 | 中 |
| ui-diag-10 | 「复制全部诊断信息」按钮 | 点 | fullReport() → 剪贴板 | | 能 | 否 | 低 |

---

## 38. SettingsView.swift（安全模式 / ZOTP 说明 · 285 行）

`SafemodeIntroView`（mode 参数复用两种形态）。入口：系统 Tab 组页「安全模式」（mode="safe"）。
mode="otp" 的调用点只在 `QuickPool`（不可达）→ **OTP 介绍页当前不可达**。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-set-01 | ZOTP 临时密码介绍卡（30 分钟窗口 / 最多 99 个 / 先校时） | 自动 | 静态文案 | | **不能**（仅 QuickPool 引用） | 否 | **高** |
| ui-set-02 | A/B 模式双卡（单一 / 组合） | 自动 | 静态 | | 能 | 否 | 低 |
| ui-set-03 | 「验证强度」进度条对比（A 1/3 · B 2/3） | 自动 | 静态 | | 能 | 否 | 低 |
| ui-set-04 | 「两种模式的差别」两行 | 自动 | 静态 | | 能 | 否 | 低 |
| ui-set-05 | 「锁端开关实况」卡（验证方式 / 广播模式 / 临时密码 三行只读） | 自动 | app.status | 需先读过锁状态 | 能 | 否 | 低 |
| ui-set-06 | 「静音模式」开关（写锁端音量） | 开关 | setSilentMode | | 能 | 否 | 低 |
| ui-set-07 | 「切换到 B 模式（双验，更严）(cmd 20)」+ 破坏性确认 | 点 → 确认 | switchToDoubleVerify | 只能变严不能回 A | 能 | 否 | 低 |
| ui-set-08 | 未读到锁状态时的占位说明 | 自动 | app.status == nil | | 能 | 否 | 低 |

---

## 39. Alerts.swift（全局弹窗助手 · 141 行）

四个 UIKit alert 助手 + `topViewController`，全仓共用。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-alert-01 | `confirmDestructive`（取消 / 标红确认） | 各处破坏性动作 | 无 | 确认词必须动词+对象 | 能（被 20+ 处调用） | 否 | 低 |
| ui-alert-02 | `confirmDestructiveTyped`（逐字键入解锁删除） | 高危动作 | requireWord | | **不能** —— 全仓零调用 | 否 | **高** |
| ui-alert-03 | `promptPasscode`（应用锁口令复核） | 250 二次开锁闸 / 访客闸 | isSecureTextEntry | | 能 | 否 | 低 |
| ui-alert-04 | `promptText`（单行文本编辑） | KeysPage 改名/改备注 | 无 | | 能 | 否 | 低 |
| ui-alert-05 | `promptSecret`（备份口令等） | BackupPage 两处 | 无 | | 能 | 否 | 低 |

---

## 40. Celebration.swift + MomentLayer.swift（庆祝时刻 · 118 行）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-moment-01 | 一次性时刻卡（渐变卡 + 辉光 + 图标 + 标题/副标题） | 事件触发（如 24 首次完成） | app.moment 队列 | 轻点任意处继续 | 能（事件触发） | 否 | 低 |
| ui-moment-02 | 5.4s 防滞留自动收起 | 自动 | task(id:) | 换卡重开计时 | 能 | 否 | 低 |
| ui-moment-03 | `MomentLayer` 挂载层（LockKeeperApp 根部 overlay） | 自动 | app.moment | | 能 | 否 | 低 |

---

## 41. DataScannerView.swift（扫码取景包装 · 69 行）

UIKit `DataScannerViewController` 的 SwiftUI 包装，全仓唯一扫码实现。

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-scan-01 | 相机扫码（QR + DataMatrix，识别即回调） | 相机 | RecognizedItem.barcode | 不支持时停在取景页回退手工输入 | 经 CodeScanSheet / ReportScanSheet | 否 | 低 |
| ui-scan-02 | 捏合缩放 / 引导高亮（VC 自带配置） | 手势 | 无 | | 经扫码 sheet | 否 | 低 |

---

## 42. CJKSpacing.swift（中西文间距 · 49 行）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-cjk-01 | `cjkSpaced(_:)`：汉字与拉丁/数字间加 kerning | 组件（LabeledRow 等调用） | 无 | 快路：纯中文零成本 | 能（组件） | 否 | 低 |

---

## 43. XLockBlade / BladeGeometry / BladeMesh / RealityAPIProbe（3D 锁体四件套 · 898 行）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-blade-01 | `XLockBlade` RealityKit 3D 锁体视图（九零件 + 状态着色 + 无障碍标签） | 无入口 | BladeGeometry/BladeMesh | **全仓零实例化**（仅 RealityAPIProbe 注释提及） | **不能** | 否 | **高** |
| ui-blade-02 | `BladeGeometry` 几何计算（轮廓/内缩/拉伸/超椭圆/放样） | 内部 | 纯数学 | 仅被 BladeMesh/XLockBlade 用 | 不能 | 否 | **高** |
| ui-blade-03 | `BladeMesh.build`（去重/法线/UV → MeshDescriptor） | 内部 | 顶点数组 | | 不能 | 否 | **高** |
| ui-blade-04 | `RealityAPIProbe` 7 个探针块（RealityView/Mesh/Material/Entity/Anchor/嵌套/文件枚举） | 无入口 | 注释记录 run #439/#443/#458 验证结论 | 编译期探针，无 UI | **不能** | 否 | **高**（保留价值=文档） |

**结论**：3D 锁体四件套（898 行）当前**整体不可达**。
`grep -r "XLockBlade(" ios-app/App` 零命中 —— 组件完成但从未挂上任何页面。

---

## 44. 死文件四件（DeviceStripCard / LockOverviewView / AlarmCenterView / FindArrowLayer · 103 行）

| ID | 功能点 | 触发方式 | 数据来源 | 说明 | 是否可达 | 是否重复 | 冗余嫌疑 |
|---|---|---|---|---|---|---|---|
| ui-dead-01 | `DeviceStripCard.swift`（12 行）：只有 import + 头注释，**无任何代码** | 无 | 注释描述"288 电量总览条带" | **空文件** | **不能** | 否 | **高** |
| ui-dead-02 | `LockOverviewView.swift`（6 行）：只有头注释，**无任何代码** | 无 | 注释描述 768-787 功能 | **空文件**；统计逻辑在 Core/LockStats | **不能** | 否 | **高** |
| ui-dead-03 | `AlarmCenterView.swift`（46 行）：旧告警中心已删，剩两个扩展 | 被调 | `toneColor`（仅自身定义处）、`atLabel`（ExportCenter 3 处调用） | 旧页面 2026-10-24 删除后残留 | **半**（atLabel 活、toneColor 死） | 否 | **高**（toneColor 零调用） |
| ui-dead-04 | `FindArrowLayer.swift`（39 行）：`FindArrowPower` 激进档标记 | 被调 | Locked box | AutoOpen 读 `intensive`，但**没有任何界面会置它为 true**（置位点在已删的箭头界面里） | **不能**（写侧无入口） | 否 | **高** |

---

---

## 45. 汇总：跨文件重复与死代码清单

### 45.1 整页级重复（冗余嫌疑 高）

| 组 | 重复双方 | 证据 | 建议 |
|---|---|---|---|
| A | `FeedPage`（动态） vs `EventsPage`（事件记录） | 同读 `kf_logcache`；同按天分组；同"只看告警"开关；同天头告警计数 | 二选一保留（建议留 EventsPage：功能更全） |
| B | `BackupPage` vs `BackupStudioView` 两向导 | 导出/导入/口令/确认每个动作两边各一份；向导版多预演/差异/冲突/回滚 | 保留 BackupPage 仅作入口 + 状态展示，动作全走向导；或直接合并 |
| C | `SecurityPeekView` vs `PrivacyDashboard` | 5 个开关逐项一一对应（同一批 SecKey 键 + 同一 togglePeek）；两边都有总览卡 | 合并为单页 |
| D | `AlarmsPage` vs `EventsPage` 告警过滤 | AlarmsPage 本质 = EventsPage 的告警子集 + 处置按钮 | 可合并（EventsPage 告警开关已有，缺"标记已处理"） |
| E | `SecurityPage` vs 系统 Tab 组页 + MePage | SecurityPage 五行入口在组页/MePage 各有平行入口；状态卡与 MePage 本机状态卡同族 | 收敛入口层级 |

### 45.2 同页内重复（冗余嫌疑 中-高）

| 页 | 重复内容 |
|---|---|
| KeysPage | 顶部芯片 / 副标题 / 库存分布卡 —— 同一组计数出现 3 次 |
| MePage | 瓦片四入口 vs 芯片行四读数 vs 下方 section 行 —— 一屏 4 个入口各 2 份 |
| MemberDetail360View | 「最近活动」与「最近开门(约)」读同一函数（recentExcerpts） |
| EventsPage | 三芯片 / 大标题副标题 / 概览条 —— 同一组数 3 次 |
| BackupStudio 主页 vs BackupPage | 上次导出/导入/加密参数各两份 |
| HomeConsole | 本周三环 / 今日三读数 / 分时柱图 / 开门历史面积图 —— 四种"量"的展示，两种与 StatsPage 重复 |

### 45.3 同一图表的多份实现

| 图 | 出现处 |
|---|---|
| 24 小时柱状图 | HomeConsole（dayChart）/ FeedPage（todayOverviewCard）/ StatsPage（rhythmCard）—— 3 份 |
| 近 N 天趋势 | HomeConsole（开门历史 21 天面积图）/ StatsPage（近 14 天趋势）—— 2 份 |
| 三环比例环 | HomeConsole×2（metricsRow 细三环 + weekCard 三环）/ StatsPage（activityRings）/ KeysPage（overviewCard）/ MembersPage（membersDistribution）—— 6 份 |
| 电量读数 | HomeConsole 芯片 / DevicePage 仪表 / LocksPage 行 / LockProfilePage 牌匾 + 指标卡 / CarePage 待办 —— 5 处 |

### 45.4 死代码 / 零入口（冗余嫌疑 高）

| 项 | 文件:行 | 证据 |
|---|---|---|
| `FpOwnerPicker` 整个文件（116 行） | FpOwnerPicker.swift:9 | 全仓零实例化；AddFingerPage 自绘了同功能 |
| `XLockBlade`+`BladeGeometry`+`BladeMesh`+`RealityAPIProbe`（898 行） | XLockBlade.swift:26 等 | 全仓零实例化 |
| `DeviceStripCard.swift`（12 行空文件） | DeviceStripCard.swift | 无代码体 |
| `LockOverviewView.swift`（6 行空文件） | LockOverviewView.swift | 无代码体 |
| `RecordSearch.toneColor` | AlarmCenterView.swift:26 | 零调用（旧页面删除后残留） |
| `FindArrowPower` 写侧 | FindArrowLayer.swift:33 | 无任何界面调用 beginIntensive；AutoOpen 的读分支永不触发 |
| `KeysPage.renameFingerprint` | KeysPage.swift:342 | 零调用 |
| `KeysPage.editNote` 视觉入口 | KeysPage.swift:354 | 仅 VoiceOver action 可达，视觉不可达 |
| `confirmDestructiveTyped` | Alerts.swift:34 | 零调用 |
| `SafemodeIntroView(mode:"otp")` ZOTP 介绍 | SettingsView.swift:13 | 唯一调用在 QuickPool（不可达） |
| `StudioTools.parseOtpAuth / totp / base32Decode` + `CodeBigCard` | CredentialStudio.swift:68/139/121/357 | OTP 引擎 + 展示组件零调用 |
| `QuickPool.quickDestination`（10 个落点） | Core/QuickPool.swift:143 | 零调用（属 Core 层，UI 侧无快捷格渲染） |
| `kf_scred_2nd` 保存密码二次输入开关 | SecurityCenterView.swift:1356 | 开关可写但无任何执行点读取它拦截 |
| "访客隐藏敏感成员"开关 | SecurityCenterView.swift:332 | 源码自注"已开但筛不出东西"——判据无数据侧 |

### 45.5 冗余嫌疑 中（功能小众 / 藏得深）

- ExportCenter 的 12 种导出形态中：原始 JSON+hex（开发向）、邮件模板 .eml、告警事实单页、
  告警一页纸打印、口述卡打印 —— 5 种属小众出口；打印三钮与分享三钮是同一生成器的重复出口。
- BackupStudio：加密二维码换机迁移、增量补传小包 —— 依赖"另一台 iPhone 也在用本 App"的前置条件。
- CareRemindersView 整页（生日/结缘日/公告板）—— 与门锁主业关联弱。
- MemberWizard 第 3 步"顺路建 10 分钟临时码"—— 与 TempCodeStudio / AddKeyPage 临时密码三个入口同能力。
- DonglesPage / GatewayPage —— 依赖对应硬件存在；无硬件时整页空态。
- StatsPage 需从 EventsPage 工具栏进入（唯一路径），入口偏深。

### 45.6 可达性总览（46 个有代码的视图）

- **底部 Tab 直达（4 级内）**：HomeConsole、KeysPage、AddFingerPage、TempCodeStudio、LocksPage、
  FirmwarePage、GatewayPage、DonglesPage、SyncTimeView、MembersPage、MemberWizardView、MemberArchivedView、
  PrivacyDashboard、SecurityAuditView、SecurityDestroyView、SafemodeIntroView、BackupPage、ExportCenterView、
  AppearancePage、MePage、DiagnosticsPage —— 21 页
- **经 MePage 二跳**：SecurityPage、AlarmsPage、BackupPage、LocksPage、DevicePage、LockProfilePage、
  EventsPage、FeedPage、IconPicker、CarePage、CareRemindersView —— 11 页（BackupPage/LocksPage 双入口）
- **三跳以上**：CredentialDetailView（KeysPage 行）、SecurityPeekView（Me/Security）、AppLockSetupView（Security）、
  CredentialBinView（Destroy/Security）、CareChecklistView / BatterySwapGuideView / MaintenanceView（Care 系）、
  BackupStudio 三屏（BackupPage）、MemberDetail360 / Merge / ExitWizard / FamilySettings / UnclaimedClaim（Members 系）、
  StatsPage（Events 工具栏）—— 15 屏
- **不可达**：FpOwnerPicker、XLockBlade 四件套、SafemodeIntroView(otp)、CodeBigCard（组件级）—— 见 §45.4

---

## 46. 统计

| 维度 | 数 |
|---|---|
| 文件 | 51（其中 2 个纯注释空文件：DeviceStripCard、LockOverviewView） |
| 有代码视图 | 46 屏/组件 |
| 本清单功能点 | **531 条**（表行 530 条 + 索引补 1 条；交互约 300 / 展示区块约 150 / 数据动作约 80，估算） |
| 死代码 | 整文件 7 个（FpOwnerPicker、XLockBlade、BladeGeometry、BladeMesh、RealityAPIProbe、DeviceStripCard、LockOverviewView）+ 半死文件 2 个（AlarmCenterView 的 toneColor、FindArrowLayer 的写侧）+ 零调用函数/组件/开关 10 项 |
| 整页级重复组 | 5 组（A-E） |
| 冗余嫌疑「高」条目 | 49 条 |
| 冗余嫌疑「中」条目 | 168 条 |

> 不确定项均以「?」或源码行号注明；行号基于 2026-10-24 工作区快照。
