# 页面深度适配台账

> 目标：所有界面都要做一次深度适配。

## 进度

| 项 | 数量 |
|---|---|
| 页面型视图总计 | **45** |
| ✅ 已深度适配 | **18** |
| ⬜ 待做 | **27** |

## 判据（三版才做对）

统计每页调用了多少个**领域数据门面**（`DB.*` / `MemberHub.*` / `StatsKit.*` / `LockArchive.*` / `BatteryCare.*` / `CredentialOrg.*` / …）。

1. 第一版：按字段访问 → 漏掉一切间接调用
2. 第二版：手写门面白名单 → 漏掉 `ProtoTime` / `ZKProtocol`
3. **第三版（现在）**：自动发现 static 成员 ≥5 的类型 + 排除设计令牌

## ✅ 已深度适配（18 页）

| 页面 | 文件 | 行数 | 门面 | 主要改动 |
|---|---|---|---|---|
| AutoCalView | AutoOpen.swift | 240 | 4 | RSSI 实时波形 + 阈值区间 |
| LinkPrefsView | LinkSenseKit.swift | 177 | 2 | 信号强度五格条 + 围栏判定 |
| AlarmsPage | AlarmsPage.swift | 386 | 4 | 主告警卡 + 已持续时长 |
| BackupPage | BackupPage.swift | 368 | 3 | iCloud 文件选择器（导入+导出对称） |
| CareRemindersView | CareRemindersView.swift | 168 | 3 | 生日倒计时 + 按紧急度排序 |
| CareChecklistView | CareViews.swift | 172 | 3 | 保养台账（上次/周期/到期/应急钥匙） |
| SyncTimeView | DeviceHomeView.swift | 194 | 2 | 锁钟偏差刻度条（三档配色） |
| DevicePage | DevicePage.swift | 394 | 4 | 锁内容量格子表 |
| DonglesPage | DonglesPage.swift | 385 | 1 | 三个时间戳（最近看到/上次写钥匙/绑定） |
| EventsPage | EventsPage.swift | 351 | 3 | 节点按 kind 着色 + 类型标签 + provable 可信度 |
| GatewayPage | GatewayPage.swift | 417 | 1 | netState 三态 + 2×2 读数 + 时间戳 |
| KeysPage | KeysPage.swift | 389 | 2 | owner 归属显示（字段一直没用） |
| LockProfilePage | LockProfilePage.swift | 372 | 2 | 实时状态条（电量/锁态/固件） |
| LocksPage | LocksPage.swift | 208 | 2 | 状态簇（电量色/锁态）+ 凭证拆分 + 型号/配对时间 |
| MembersPage | MembersPage.swift | 322 | 2 | last/month/permRows 三类数据 + 头像带 |
| MePage | MePage.swift | 286 | 3 | 大数字仪表（去图标圆，数值提到 title2） |
| StatsPage | StatsPage.swift | 340 | 1 | 凭证分布 + 一天分段 + 工作日出门时间 |
| StudioPage | StudioPage.swift | 210 | 2 | 四宫格实时数量 |

## ⬜ 待做（27 页，按门面升序）

| # | 页面 | 文件 | 行数 | 门面 | 用到的 |
|---|---|---|---|---|---|
| 1 | SafemodeIntroView | SettingsView.swift | 119 | 0 |  |
| 2 | MemberFamilySettingsView | MemberCenterView.swift | 80 | 1 | MemberHub |
| 3 | ShareToAndroidView | ShareToAndroidView.swift | 114 | 1 | AndroidPair |
| 4 | AddFingerPage | AddFingerPage.swift | 329 | 2 | DB, MemberHub |
| 5 | RestoreWizardView | BackupStudio.swift | 407 | 2 | BackupStudio, LockArchive |
| 6 | CarePage | CarePage.swift | 206 | 2 | BatteryCare, DB |
| 7 | BatterySwapGuideView | CareViews.swift | 106 | 2 | BatteryCare, LockArchive |
| 8 | FeedPage | FeedPage.swift | 233 | 2 | DB, StatsKit |
| 9 | MergeMembersView | MemberCenterView.swift | 101 | 2 | DB, MemberHub |
| 10 | MemberArchivedView | MemberCenterView.swift | 72 | 2 | DB, MemberHub |
| 11 | SecurityPage | SecurityPage.swift | 249 | 2 | CredentialOrg, DataHealth |
| 12 | AddLockPage | AddLockPage.swift | 516 | 3 | DB, LockArchive, ZKProtocol |
| 13 | BackupStudioView | BackupStudio.swift | 257 | 3 | BackupStudio, DB, ExportDir |
| 14 | MemberWizardView | MemberCenterView.swift | 198 | 3 | CredentialOrg, DB, MemberHub |
| 15 | SecurityPeekView | SecurityCenterView.swift | 311 | 3 | DB, SecKey, SecurityPolicy |
| 16 | SecurityAuditView | SecurityCenterView.swift | 394 | 3 | DB, SecKey, SecurityPolicy |
| 17 | ExportWizardView | BackupStudio.swift | 448 | 4 | BackupStudio, DB, LockArchive, Milestones |
| 18 | BackupView | BackupView.swift | 266 | 4 | BackupKit, BackupStudio, DB, Milestones |
| 19 | UnclaimedClaimView | MemberCenterView.swift | 124 | 4 | Attribution, DB, MemberHub, StatsKit |
| 20 | AddKeyPage | AddKeyPage.swift | 340 | 5 | CredentialOrg, DB, LockArchive, MemberHub, WeekCal |
| 21 | MaintenanceView | CareViews.swift | 285 | 5 | BatteryCare, CareSchedule, LockArchive, LockStats, WeekCal |
| 22 | FirmwarePage | FirmwarePage.swift | 645 | 5 | BatteryCare, DB, FirmwareKit, LockArchive, WeekCal |
| 23 | MemberDetail360View | MemberCenterView.swift | 447 | 5 | CredentialOrg, DB, LockArchive, MemberHub, Milestones |
| 24 | SecurityDestroyView | SecurityCenterView.swift | 476 | 5 | CredentialOrg, DB, DestroyKit, SecKey, SecurityPolicy |
| 25 | RootView | LockKeeperApp.swift | 370 | 6 | BackupStudio, CrashGuard, DB, HolidayFeed, LinkSense, SecKey |
| 26 | ExportCenterView | ExportCenter.swift | 972 | 6 | BackupStudio, DB, DiagLogs, ExportKit, LockArchive, ReportVerify |
| 27 | AlarmCenterView | AlarmCenterView.swift | 836 | 7 | AlarmMeta, DB, LockArchive, MemberHub, RecordSearch, StatsKit, WeekCal |