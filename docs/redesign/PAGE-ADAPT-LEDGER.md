# 页面深度适配台账

> 目标：所有界面都要做一次深度适配。

## 交付状态

| 项 | 状态 |
|---|---|
| CI 编译 | ✅ **SUCCESS**（run 39580979109, HEAD c471dc7）|
| 本地 23 道闸门 | ✅ 全绿 |
| 页面深度适配 | **27 / 45** |

> ⚠ 本地闸门全绿 **不等于** 能编译 —— 见 [CI-VS-GATES.md](CI-VS-GATES.md)。
> 闸门是文本级检查，没有类型系统。

## ✅ 已深度适配（27 页）

| 页面 | 文件 | 行数 |
|---|---|---|
| AutoCalView | AutoOpen.swift | 239 |
| LinkPrefsView | LinkSenseKit.swift | 181 |
| AddFingerPage | AddFingerPage.swift | 381 |
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
| UnclaimedClaimView | MemberCenterView.swift | 150 |
| MembersPage | MembersPage.swift | 322 |
| MePage | MePage.swift | 286 |
| SecurityPage | SecurityPage.swift | 272 |
| SafemodeIntroView | SettingsView.swift | 163 |
| StatsPage | StatsPage.swift | 340 |
| StudioPage | StudioPage.swift | 210 |

## ⬜ 待做（18 页）

| # | 页面 | 文件 | 行数 |
|---|---|---|---|
| 1 | RootView | LockKeeperApp.swift | 370 |
| 2 | AddKeyPage | AddKeyPage.swift | 340 |
| 3 | AddLockPage | AddLockPage.swift | 516 |
| 4 | AlarmCenterView | AlarmCenterView.swift | 836 |
| 5 | BackupStudioView | BackupStudio.swift | 257 |
| 6 | ExportWizardView | BackupStudio.swift | 448 |
| 7 | RestoreWizardView | BackupStudio.swift | 407 |
| 8 | BackupView | BackupView.swift | 266 |
| 9 | MaintenanceView | CareViews.swift | 285 |
| 10 | ExportCenterView | ExportCenter.swift | 972 |
| 11 | FirmwarePage | FirmwarePage.swift | 645 |
| 12 | MemberDetail360View | MemberCenterView.swift | 447 |
| 13 | MemberWizardView | MemberCenterView.swift | 198 |
| 14 | MemberFamilySettingsView | MemberCenterView.swift | 80 |
| 15 | SecurityPeekView | SecurityCenterView.swift | 311 |
| 16 | SecurityAuditView | SecurityCenterView.swift | 394 |
| 17 | SecurityDestroyView | SecurityCenterView.swift | 476 |
| 18 | ShareToAndroidView | ShareToAndroidView.swift | 114 |