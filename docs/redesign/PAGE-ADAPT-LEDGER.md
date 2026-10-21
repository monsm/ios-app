# 页面深度适配台账

> 目标：所有界面都要做一次深度适配。

## 进度

| 项 | 数量 |
|---|---|
| 页面型视图总计 | **45** |
| ✅ 已深度适配 | **22** |
| ⬜ 待做 | **23** |

## 判据（三版才做对）

统计每页调用了多少个**领域数据门面**（`DB.*` / `MemberHub.*` / `StatsKit.*` / `LockArchive.*` / `BatteryCare.*` / …）。

1. 第一版：按字段访问 → 漏掉一切间接调用
2. 第二版：手写白名单 → 漏掉 `ProtoTime` / `ZKProtocol`
3. **第三版（现在）**：自动发现 static 成员 ≥5 的类型 + 排除设计令牌

## ✅ 已深度适配（22 页）

| 页面 | 文件 | 行数 | 门面 | 主要改动 |
|---|---|---|---|---|
| AutoCalView | AutoOpen.swift | 240 | 4 | RSSI 波形 + 阈值区间 |
| LinkPrefsView | LinkSenseKit.swift | 177 | 2 | 信号五格条 |
| AlarmsPage | AlarmsPage.swift | 386 | 4 | 主告警卡 + 持续时长 |
| BackupPage | BackupPage.swift | 368 | 3 | iCloud 文件选择器 |
| CarePage | CarePage.swift | 238 | 3 | 修周期 bug + 应急钥匙 |
| CareRemindersView | CareRemindersView.swift | 168 | 3 | 生日倒计时 |
| CareChecklistView | CareViews.swift | 172 | 3 | 保养台账 |
| SyncTimeView | DeviceHomeView.swift | 194 | 2 | 锁钟偏差刻度条 |
| DevicePage | DevicePage.swift | 394 | 4 | 容量格子表 |
| DonglesPage | DonglesPage.swift | 385 | 1 | 三个时间戳 |
| EventsPage | EventsPage.swift | 351 | 3 | 节点按 kind 着色 + provable |
| FeedPage | FeedPage.swift | 296 | 3 | 日期分组 |
| GatewayPage | GatewayPage.swift | 417 | 1 | 三态 + IP + 时间戳 |
| KeysPage | KeysPage.swift | 389 | 2 | owner 归属 |
| LockProfilePage | LockProfilePage.swift | 372 | 2 | 实时状态条 |
| LocksPage | LocksPage.swift | 208 | 2 | 状态簇 + 凭证拆分 |
| MemberArchivedView | MemberCenterView.swift | 96 | 2 | 身份 + 事实行 |
| MembersPage | MembersPage.swift | 322 | 2 | last/month/permRows + 头像带 |
| MePage | MePage.swift | 286 | 3 | 大数字仪表 |
| SecurityPage | SecurityPage.swift | 272 | 3 | 加应用锁/备份两盏灯 |
| StatsPage | StatsPage.swift | 340 | 1 | 凭证分布/一天分段/出门时间 |
| StudioPage | StudioPage.swift | 210 | 2 | 四宫格数量 |

## ⬜ 待做（23 页）

| # | 页面 | 文件 | 行数 | 门面 |
|---|---|---|---|---|
| 1 | SafemodeIntroView | SettingsView.swift | 119 | 0 |
| 2 | MemberFamilySettingsView | MemberCenterView.swift | 80 | 1 |
| 3 | ShareToAndroidView | ShareToAndroidView.swift | 114 | 1 |
| 4 | AddFingerPage | AddFingerPage.swift | 329 | 2 |
| 5 | RestoreWizardView | BackupStudio.swift | 407 | 2 |
| 6 | BatterySwapGuideView | CareViews.swift | 106 | 2 |
| 7 | MergeMembersView | MemberCenterView.swift | 101 | 2 |
| 8 | AddLockPage | AddLockPage.swift | 516 | 3 |
| 9 | BackupStudioView | BackupStudio.swift | 257 | 3 |
| 10 | MemberWizardView | MemberCenterView.swift | 198 | 3 |
| 11 | SecurityPeekView | SecurityCenterView.swift | 311 | 3 |
| 12 | SecurityAuditView | SecurityCenterView.swift | 394 | 3 |
| 13 | ExportWizardView | BackupStudio.swift | 448 | 4 |
| 14 | BackupView | BackupView.swift | 266 | 4 |
| 15 | UnclaimedClaimView | MemberCenterView.swift | 124 | 4 |
| 16 | AddKeyPage | AddKeyPage.swift | 340 | 5 |
| 17 | MaintenanceView | CareViews.swift | 285 | 5 |
| 18 | FirmwarePage | FirmwarePage.swift | 645 | 5 |
| 19 | MemberDetail360View | MemberCenterView.swift | 464 | 5 |
| 20 | SecurityDestroyView | SecurityCenterView.swift | 476 | 5 |
| 21 | RootView | LockKeeperApp.swift | 370 | 6 |
| 22 | ExportCenterView | ExportCenter.swift | 972 | 6 |
| 23 | AlarmCenterView | AlarmCenterView.swift | 836 | 7 |