# 49 页深度适配台账

> 2026-10-21。用户要求「所有的界面都要做一次深度适配」。

## 判据（三版才做对）

每页统计它调用了多少个**领域数据门面**（`DB.*` / `MemberHub.*` / `StatsKit.*` / `RecordSearch.*` / `AutoOpen*.*` / `LinkSense.*` / `Milestones.*` / `LockArchive.*` / `CredentialOrg.*` / `BatteryCare.*` / …）。

### 判据演进（记录踩过的坑）

1. **第一版**：按字段访问（`rec.kind` / `m.name`）→ 漏掉一切间接调用
2. **第二版**：手写门面白名单 → 漏掉 `ProtoTime` / `ZKProtocol`，SyncTimeView 被误判为 0
3. **第三版（现在）**：自动发现 static 成员 ≥5 的类型 + 排除设计令牌（`XPalette`/`XSpace`/`XIcon` 等）

**分级**：≤1 🔴 / =2 🟡 / ≥3 🟢

## 台账（45 页，按门面数升序）

| # | 页面 | 文件 | 行数 | 门面 | 分级 | 用到的 |
|---|---|---|---|---|---|---|
| 1 | SafemodeIntroView | SettingsView.swift | 119 | 0 | 🔴 |  |
| 2 | ShareToAndroidView | ShareToAndroidView.swift | 114 | 0 | 🔴 |  |
| 3 | StudioPage | StudioPage.swift | 182 | 0 | 🔴 |  |
| 4 | CareChecklistView | CareViews.swift | 96 | 1 | 🔴 | BatteryCare |
| 5 | DonglesPage | DonglesPage.swift | 354 | 1 | 🔴 | DB |
| 6 | GatewayPage | GatewayPage.swift | 375 | 1 | 🔴 | DB |
| 7 | MemberFamilySettingsView | MemberCenterView.swift | 80 | 1 | 🔴 | MemberHub |
| 8 | StatsPage | StatsPage.swift | 190 | 1 | 🔴 | StatsKit |
| 9 | LinkPrefsView | LinkSenseKit.swift | 177 | 2 | 🟡 | DB, LinkSense |
| 10 | AddFingerPage | AddFingerPage.swift | 329 | 2 | 🟡 | DB, MemberHub |
| 11 | RestoreWizardView | BackupStudio.swift | 407 | 2 | 🟡 | BackupStudio, LockArchive |
| 12 | CarePage | CarePage.swift | 206 | 2 | 🟡 | BatteryCare, DB |
| 13 | BatterySwapGuideView | CareViews.swift | 106 | 2 | 🟡 | BatteryCare, LockArchive |
| 14 | SyncTimeView | DeviceHomeView.swift | 194 | 2 | 🟡 | ProtoTime, ZKProtocol |
| 15 | FeedPage | FeedPage.swift | 233 | 2 | 🟡 | DB, StatsKit |
| 16 | KeysPage | KeysPage.swift | 389 | 2 | 🟡 | CredentialOrg, DB |
| 17 | LockProfilePage | LockProfilePage.swift | 316 | 2 | 🟡 | DB, LockArchive |
| 18 | LocksPage | LocksPage.swift | 150 | 2 | 🟡 | DB, LockArchive |
| 19 | MergeMembersView | MemberCenterView.swift | 101 | 2 | 🟡 | DB, MemberHub |
| 20 | MemberArchivedView | MemberCenterView.swift | 72 | 2 | 🟡 | DB, MemberHub |
| 21 | MembersPage | MembersPage.swift | 322 | 2 | 🟡 | DB, MemberHub |
| 22 | SecurityPage | SecurityPage.swift | 249 | 2 | 🟡 | CredentialOrg, DataHealth |
| 23 | AddLockPage | AddLockPage.swift | 516 | 3 | 🟢 | DB, LockArchive, ZKProtocol |
| 24 | BackupPage | BackupPage.swift | 368 | 3 | 🟢 | BackupKit, DB, WeekCal |
| 25 | BackupStudioView | BackupStudio.swift | 257 | 3 | 🟢 | BackupStudio, DB, ExportDir |
| 26 | CareRemindersView | CareRemindersView.swift | 168 | 3 | 🟢 | DB, Milestones, WeekCal |
| 27 | EventsPage | EventsPage.swift | 351 | 3 | 🟢 | DB, RecordSearch, WeekCal |
| 28 | MemberWizardView | MemberCenterView.swift | 198 | 3 | 🟢 | CredentialOrg, DB, MemberHub |
| 29 | MePage | MePage.swift | 286 | 3 | 🟢 | AutoOpen, DB, RecordSearch |
| 30 | SecurityPeekView | SecurityCenterView.swift | 311 | 3 | 🟢 | DB, SecKey, SecurityPolicy |
| 31 | SecurityAuditView | SecurityCenterView.swift | 394 | 3 | 🟢 | DB, SecKey, SecurityPolicy |
| 32 | AutoCalView | AutoOpen.swift | 240 | 4 | 🟢 | AutoOpen, AutoOpenKit, LinkSense, WeekCal |
| 33 | AlarmsPage | AlarmsPage.swift | 386 | 4 | 🟢 | AlarmMeta, DB, RecordSearch, WeekCal |
| 34 | ExportWizardView | BackupStudio.swift | 448 | 4 | 🟢 | BackupStudio, DB, LockArchive, Milestones |
| 35 | BackupView | BackupView.swift | 266 | 4 | 🟢 | BackupKit, BackupStudio, DB, Milestones |
| 36 | DevicePage | DevicePage.swift | 394 | 4 | 🟢 | DB, LinkSense, LockArchive, RecordSearch |
| 37 | UnclaimedClaimView | MemberCenterView.swift | 124 | 4 | 🟢 | Attribution, DB, MemberHub, StatsKit |
| 38 | AddKeyPage | AddKeyPage.swift | 340 | 5 | 🟢 | CredentialOrg, DB, LockArchive, MemberHub, WeekCal |
| 39 | MaintenanceView | CareViews.swift | 285 | 5 | 🟢 | BatteryCare, CareSchedule, LockArchive, LockStats, WeekCal |
| 40 | FirmwarePage | FirmwarePage.swift | 645 | 5 | 🟢 | BatteryCare, DB, FirmwareKit, LockArchive, WeekCal |
| 41 | MemberDetail360View | MemberCenterView.swift | 447 | 5 | 🟢 | CredentialOrg, DB, LockArchive, MemberHub, Milestones |
| 42 | SecurityDestroyView | SecurityCenterView.swift | 476 | 5 | 🟢 | CredentialOrg, DB, DestroyKit, SecKey, SecurityPolicy |
| 43 | RootView | LockKeeperApp.swift | 370 | 6 | 🟢 | BackupStudio, CrashGuard, DB, HolidayFeed, LinkSense, SecKey |
| 44 | ExportCenterView | ExportCenter.swift | 972 | 6 | 🟢 | BackupStudio, DB, DiagLogs, ExportKit, LockArchive, ReportVerify |
| 45 | AlarmCenterView | AlarmCenterView.swift | 836 | 7 | 🟢 | AlarmMeta, DB, LockArchive, MemberHub, RecordSearch, StatsKit, WeekCal |

## 汇总

| 分级 | 数量 | 含义 |
|---|---|---|
| 🔴 门面 ≤1 | 8 | 内容未适配，只显示一两个字段 |
| 🟡 门面 =2 | 14 | 偏薄 |
| 🟢 门面 ≥3 | 23 | 已适配 |

## 🔴 优先清单（8 页）

```
 1. SafemodeIntroView         SettingsView.swift  (119 行, 门面 0)
 2. ShareToAndroidView        ShareToAndroidView.swift  (114 行, 门面 0)
 3. StudioPage                StudioPage.swift  (182 行, 门面 0)
 4. CareChecklistView         CareViews.swift  (96 行, 门面 1: BatteryCare)
 5. DonglesPage               DonglesPage.swift  (354 行, 门面 1: DB)
 6. GatewayPage               GatewayPage.swift  (375 行, 门面 1: DB)
 7. MemberFamilySettingsView  MemberCenterView.swift  (80 行, 门面 1: MemberHub)
 8. StatsPage                 StatsPage.swift  (190 行, 门面 1: StatsKit)
```

## 进度

- [ ] 🔴 8 页
- [ ] 🟡 14 页
- [ ] 🟢 23 页复核

每完成一页勾掉一个，提交信息注明页面名。