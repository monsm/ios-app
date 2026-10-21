# 49 页深度适配台账

> 2026-10-21。用户要求「所有的界面都要做一次深度适配」。

## 判据（三版才做对）

统计每页调用了多少个**领域数据门面**（`DB.*` / `MemberHub.*` / `StatsKit.*` / `LockArchive.*` / `BatteryCare.*` / `CredentialOrg.*` / …）。

1. 第一版：按字段访问 → 漏掉一切间接调用
2. 第二版：手写门面白名单 → 漏掉 `ProtoTime` / `ZKProtocol`
3. **第三版（现在）**：自动发现 static 成员 ≥5 的类型 + 排除设计令牌（`XPalette`/`XSpace`/`XIcon`）

**分级**：门面 ≤1 🔴 / =2 🟡 / ≥3 🟢

## 进度

| 项 | 数量 |
|---|---|
| 已深度适配 | **18** / 45 |
| 🔴 待做（门面≤1） | 0 |
| 🟡 待做（门面=2） | 10 |
| 🟢 待复核（门面≥3） | 17 |

## 台账（✅ = 已深度适配）

| # | | 页面 | 文件 | 行数 | 门面 | 用到的 |
|---|---|---|---|---|---|---|
| 1 |  | AddFingerPage | AddFingerPage.swift | 329 | 2 | DB, MemberHub |
| 2 |  | RestoreWizardView | BackupStudio.swift | 407 | 2 | BackupStudio, LockArchive |
| 3 |  | CarePage | CarePage.swift | 206 | 2 | BatteryCare, DB |
| 4 |  | BatterySwapGuideView | CareViews.swift | 106 | 2 | BatteryCare, LockArchive |
| 5 |  | FeedPage | FeedPage.swift | 233 | 2 | DB, StatsKit |
| 6 |  | LockProfilePage | LockProfilePage.swift | 316 | 2 | DB, LockArchive |
| 7 |  | LocksPage | LocksPage.swift | 150 | 2 | DB, LockArchive |
| 8 |  | MergeMembersView | MemberCenterView.swift | 101 | 2 | DB, MemberHub |
| 9 |  | MemberArchivedView | MemberCenterView.swift | 72 | 2 | DB, MemberHub |
| 10 |  | SecurityPage | SecurityPage.swift | 249 | 2 | CredentialOrg, DataHealth |
| 11 |  | AddLockPage | AddLockPage.swift | 516 | 3 | DB, LockArchive, ZKProtocol |
| 12 |  | BackupPage | BackupPage.swift | 368 | 3 | BackupKit, DB, WeekCal |
| 13 |  | BackupStudioView | BackupStudio.swift | 257 | 3 | BackupStudio, DB, ExportDir |
| 14 |  | MemberWizardView | MemberCenterView.swift | 198 | 3 | CredentialOrg, DB, MemberHub |
| 15 |  | SecurityPeekView | SecurityCenterView.swift | 311 | 3 | DB, SecKey, SecurityPolicy |
| 16 |  | SecurityAuditView | SecurityCenterView.swift | 394 | 3 | DB, SecKey, SecurityPolicy |
| 17 |  | ExportWizardView | BackupStudio.swift | 448 | 4 | BackupStudio, DB, LockArchive, Milestones |
| 18 |  | BackupView | BackupView.swift | 266 | 4 | BackupKit, BackupStudio, DB, Milestones |
| 19 |  | UnclaimedClaimView | MemberCenterView.swift | 124 | 4 | Attribution, DB, MemberHub, StatsKit |
| 20 |  | AddKeyPage | AddKeyPage.swift | 340 | 5 | CredentialOrg, DB, LockArchive, MemberHub, WeekCal |
| 21 |  | MaintenanceView | CareViews.swift | 285 | 5 | BatteryCare, CareSchedule, LockArchive, LockStats, WeekCal |
| 22 |  | FirmwarePage | FirmwarePage.swift | 645 | 5 | BatteryCare, DB, FirmwareKit, LockArchive, WeekCal |
| 23 |  | MemberDetail360View | MemberCenterView.swift | 447 | 5 | CredentialOrg, DB, LockArchive, MemberHub, Milestones |
| 24 |  | SecurityDestroyView | SecurityCenterView.swift | 476 | 5 | CredentialOrg, DB, DestroyKit, SecKey, SecurityPolicy |
| 25 |  | RootView | LockKeeperApp.swift | 370 | 6 | BackupStudio, CrashGuard, DB, HolidayFeed, LinkSense, SecKey |
| 26 |  | ExportCenterView | ExportCenter.swift | 972 | 6 | BackupStudio, DB, DiagLogs, ExportKit, LockArchive, ReportVerify |
| 27 |  | AlarmCenterView | AlarmCenterView.swift | 836 | 7 | AlarmMeta, DB, LockArchive, MemberHub, RecordSearch, StatsKit, WeekCal |
| 28 | ✅ | SafemodeIntroView | SettingsView.swift | 119 | 0 |  |
| 29 | ✅ | DonglesPage | DonglesPage.swift | 385 | 1 | DB |
| 30 | ✅ | GatewayPage | GatewayPage.swift | 417 | 1 | DB |
| 31 | ✅ | MemberFamilySettingsView | MemberCenterView.swift | 80 | 1 | MemberHub |
| 32 | ✅ | ShareToAndroidView | ShareToAndroidView.swift | 114 | 1 | AndroidPair |
| 33 | ✅ | StatsPage | StatsPage.swift | 340 | 1 | StatsKit |
| 34 | ✅ | LinkPrefsView | LinkSenseKit.swift | 177 | 2 | DB, LinkSense |
| 35 | ✅ | SyncTimeView | DeviceHomeView.swift | 194 | 2 | ProtoTime, ZKProtocol |
| 36 | ✅ | KeysPage | KeysPage.swift | 389 | 2 | CredentialOrg, DB |
| 37 | ✅ | MembersPage | MembersPage.swift | 322 | 2 | DB, MemberHub |
| 38 | ✅ | StudioPage | StudioPage.swift | 210 | 2 | CredentialOrg, DB |
| 39 | ✅ | CareRemindersView | CareRemindersView.swift | 168 | 3 | DB, Milestones, WeekCal |
| 40 | ✅ | CareChecklistView | CareViews.swift | 172 | 3 | BatteryCare, DB, StatsKit |
| 41 | ✅ | EventsPage | EventsPage.swift | 351 | 3 | DB, RecordSearch, WeekCal |
| 42 | ✅ | MePage | MePage.swift | 286 | 3 | AutoOpen, DB, RecordSearch |
| 43 | ✅ | AutoCalView | AutoOpen.swift | 240 | 4 | AutoOpen, AutoOpenKit, LinkSense, WeekCal |
| 44 | ✅ | AlarmsPage | AlarmsPage.swift | 386 | 4 | AlarmMeta, DB, RecordSearch, WeekCal |
| 45 | ✅ | DevicePage | DevicePage.swift | 394 | 4 | DB, LinkSense, LockArchive, RecordSearch |

## 已完成清单

```
 1. SafemodeIntroView       SettingsView.swift
 2. DonglesPage             DonglesPage.swift
 3. GatewayPage             GatewayPage.swift
 4. MemberFamilySettingsViewMemberCenterView.swift
 5. ShareToAndroidView      ShareToAndroidView.swift
 6. StatsPage               StatsPage.swift
 7. LinkPrefsView           LinkSenseKit.swift
 8. SyncTimeView            DeviceHomeView.swift
 9. KeysPage                KeysPage.swift
10. MembersPage             MembersPage.swift
11. StudioPage              StudioPage.swift
12. CareRemindersView       CareRemindersView.swift
13. CareChecklistView       CareViews.swift
14. EventsPage              EventsPage.swift
15. MePage                  MePage.swift
16. AutoCalView             AutoOpen.swift
17. AlarmsPage              AlarmsPage.swift
18. DevicePage              DevicePage.swift
```

## 仍待做

```
 1. AddFingerPage           AddFingerPage.swift  (门面 2)
 2. RestoreWizardView       BackupStudio.swift  (门面 2)
 3. CarePage                CarePage.swift  (门面 2)
 4. BatterySwapGuideView    CareViews.swift  (门面 2)
 5. FeedPage                FeedPage.swift  (门面 2)
 6. LockProfilePage         LockProfilePage.swift  (门面 2)
 7. LocksPage               LocksPage.swift  (门面 2)
 8. MergeMembersView        MemberCenterView.swift  (门面 2)
 9. MemberArchivedView      MemberCenterView.swift  (门面 2)
10. SecurityPage            SecurityPage.swift  (门面 2)
```