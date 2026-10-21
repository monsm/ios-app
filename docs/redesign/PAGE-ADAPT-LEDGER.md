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