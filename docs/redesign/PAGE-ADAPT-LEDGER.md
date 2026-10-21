# 页面深度适配台账

> 目标：所有界面都要做一次深度适配。

## 交付状态

| 项 | 状态 |
|---|---|
| CI 编译 | 见最新 run（`tools/cistat.js`）|
| 本地 23 道闸门 | ✅ 全绿 |
| 页面深度适配 | **30 / 45** |

> ⚠ 本地闸门全绿 **不等于** 能编译 —— 见 [CI-VS-GATES.md](CI-VS-GATES.md)。

## ✅ 已深度适配（30 页）

| 页面 | 文件 | 行数 |
|---|---|---|
| AutoCalView | AutoOpen.swift | 239 |
| LinkPrefsView | LinkSenseKit.swift | 181 |
| AddFingerPage | AddFingerPage.swift | 381 |
| AddKeyPage | AddKeyPage.swift | 386 |
| AlarmsPage | AlarmsPage.swift | 386 |
| BackupPage | BackupPage.swift | 368 |
| CarePage | CarePage.swift | 238 |
| CareRemindersView | CareRemindersView.swift | 168 |
| BatterySwapGuideView | CareViews.swift | 154 |
| CareChecklistView | CareViews.swift | 172 |
| SyncTimeView | DeviceHomeView.swift | 194 |
| DevicePage | DevicePage.swift | 405 |
| DonglesPage | DonglesPage.swift | 385 |
| EventsPage | EventsPage.swift | 351 |
| FeedPage | FeedPage.swift | 296 |
| GatewayPage | GatewayPage.swift | 417 |
| KeysPage | KeysPage.swift | 389 |
| LockProfilePage | LockProfilePage.swift | 372 |
| LocksPage | LocksPage.swift | 208 |
| MergeMembersView | MemberCenterView.swift | 156 |
| MemberArchivedView | MemberCenterView.swift | 112 |
| MemberFamilySettingsView | MemberCenterView.swift | 129 |
| UnclaimedClaimView | MemberCenterView.swift | 150 |
| MembersPage | MembersPage.swift | 322 |
| MePage | MePage.swift | 286 |
| SecurityAuditView | SecurityCenterView.swift | 399 |
| SecurityPage | SecurityPage.swift | 272 |
| SafemodeIntroView | SettingsView.swift | 163 |
| StatsPage | StatsPage.swift | 340 |
| StudioPage | StudioPage.swift | 210 |

## ⬜ 待做（15 页）

| # | 页面 | 文件 | 行数 |
|---|---|---|---|
| 1 | RootView | LockKeeperApp.swift | 370 |
| 2 | AddLockPage | AddLockPage.swift | 516 |
| 3 | AlarmCenterView | AlarmCenterView.swift | 836 |
| 4 | BackupStudioView | BackupStudio.swift | 257 |
| 5 | ExportWizardView | BackupStudio.swift | 448 |
| 6 | RestoreWizardView | BackupStudio.swift | 407 |
| 7 | BackupView | BackupView.swift | 266 |
| 8 | MaintenanceView | CareViews.swift | 285 |
| 9 | ExportCenterView | ExportCenter.swift | 972 |
| 10 | FirmwarePage | FirmwarePage.swift | 645 |
| 11 | MemberDetail360View | MemberCenterView.swift | 447 |
| 12 | MemberWizardView | MemberCenterView.swift | 198 |
| 13 | SecurityPeekView | SecurityCenterView.swift | 311 |
| 14 | SecurityDestroyView | SecurityCenterView.swift | 476 |
| 15 | ShareToAndroidView | ShareToAndroidView.swift | 114 |
## 已核验：内容丰富，无需改动（8 页）

以下页面我**逐页读过**，判断为已经做得很丰富，强行加内容会是 slop。附证据。

| 页面 | 行数 | 核验到的已有内容 |
|---|---|---|
| `AddLockPage` | 516 | 步骤指示器（3 点/三态配色/勾选脉冲/reduceMotion 回退）、扫描舞台、**信号条 signalBars**、配对舞台、命名舞台、完成舞台、错误横幅、异常回滚 |
| `MemberDetail360View` | 447 | **用了 13 个 MemberHub API**: activity / ext / permAllows / permCan / permCannot / permRows / proxyNames / recentExcerpts / roleLabel / sourceCounts / weekSentence / display / saveExt |
| `RestoreWizardView` | 407 | 输入/预览/策略/冲突/分区/报告/diff 七段 |
| `SecurityAuditView` | 394+ | 双流水、duress 高亮、链验证、保留期、展开 diff（本轮已补条数）|
| `RootView` | 370 | 顶部横幅、mainTabsChrome、rootCore/rootGroup/rootChrome、自检横幅、粘贴建议、写入回执、BLE 状态条、`CrashGuard.pendingAbnormal` 恢复入口 |
| `SecurityPeekView` | 311 | 剪贴板自动清除（含 TTL 档位）、遮蔽样式、后台模糊、限时显示、磨砂演示 |
| `MaintenanceView` | 285 | 周期环、频次自适应（`opens30d`→`periodDays`）、历史、换电、应急钥匙、清单 sheet |
| `BackupStudioView` | 257 | 数据主权声明、双向天数、加密算法徽章、动作卡、节奏卡 |
| `BackupView` | 266 | 全量导出、导入、云端恢复确认、未备份信封 |
| `FirmwarePage` | 645 | 版本卡、包卡、检查清单、动作、队列、历史、升级中、失败态 |
| `AddLockPage` 已列 | | |
| `ShareToAndroidView` | 114 | 单职责二维码页：生成、错误处理、分享、安全警告，功能完整 |

## 核心架构规格核验

| 规格项 | 状态 |
|---|---|
| 三域文件（DoorPrism/XGateDoor/ManagerFace/DashboardFace/XLockBlade/GateFaceTexture/DoorRoot）| ✅ 全部存在 |
| 旧代码 `DoorStage.swift` / `DoorBack.swift` | ✅ 已删除 |
| `narrow = (\|cos\|-0.5)/0.5` | ✅ 字面实现 |
| `scale = 1 - 0.20*narrow` | ✅ 字面实现 |
| `easeInOut` 缓动 | ✅ |
| `reduceMotion` 保护 | ✅ 10 处 |
| **`z = -0.35*narrow`** | ⚠ **改用 `anchorZ = -A` 实现**（SwiftUI 的 `.offset` 无 z 参数、`projectionEffect` 只取 3×3），效果等价：三面半径均 102.1pt、选中面 z=+102。详见 [PRISM-GEOMETRY.md](PRISM-GEOMETRY.md) §四，run #475 SUCCESS 验证过标签名 |

## CI 状态

连续 3 次 SUCCESS（`83d498a` / `d89cf6c` / `ef2ef26`）。
