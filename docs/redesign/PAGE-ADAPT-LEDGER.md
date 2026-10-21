# 52 页深度适配台账

> 2026-10-21。目标写的是「52 个 UI 页面」，我之前只数了 45 个 —— **漏了 7 个**。

## 清单口径的修正（重要）

第一版我只按命名筛 `*Page` / `*View`，得到 45 个。
但全仓有 **98 个 `: View` struct**，其中 7 个是**真正的用户可达页面**却不这么命名：

| 页面 | 行数 | 入口 |
|---|---|---|
| `OtpStudio` | 507 | `StudioPage.swift:88` |
| `TempCodeStudio` | 469 | `StudioPage.swift:82` + `ManagerFace.swift:172` |
| `FpStudio` | 401 | `StudioPage.swift:85` |
| `MemberExitWizard` | 165 | `MemberCenterView.swift:87` sheet |
| `IconPicker` | 112 | `MePage.swift:278` NavigationLink |
| `FpOwnerPicker` | 108 | `CredentialStudio.swift:1117` |
| `PrivacyDashboard` | 90 | `SecurityCenterView.swift:216` NavigationLink |

**45 + 7 = 52** —— 正好是目标里的数字。说明这个口径是对的。

## 进度

| 项 | 数量 |
|---|---|
| 页面总计 | **52** |
| ✅ 有实质内容改动 | **32** |
| ✅ 逐页核验为已丰富 | **20** |
| ⬜ 未处理 | **0** |

## ✅ 有实质内容改动（32 页）

- `AutoCalView` (AutoOpen.swift, 239 行)
- `LinkPrefsView` (LinkSenseKit.swift, 181 行)
- `AddFingerPage` (AddFingerPage.swift, 381 行)
- `AddKeyPage` (AddKeyPage.swift, 386 行)
- `AlarmsPage` (AlarmsPage.swift, 386 行)
- `BackupPage` (BackupPage.swift, 368 行)
- `CarePage` (CarePage.swift, 238 行)
- `CareRemindersView` (CareRemindersView.swift, 168 行)
- `BatterySwapGuideView` (CareViews.swift, 154 行)
- `CareChecklistView` (CareViews.swift, 172 行)
- `SyncTimeView` (DeviceHomeView.swift, 194 行)
- `DevicePage` (DevicePage.swift, 405 行)
- `DonglesPage` (DonglesPage.swift, 385 行)
- `EventsPage` (EventsPage.swift, 351 行)
- `FeedPage` (FeedPage.swift, 296 行)
- `GatewayPage` (GatewayPage.swift, 417 行)
- `KeysPage` (KeysPage.swift, 389 行)
- `LockProfilePage` (LockProfilePage.swift, 372 行)
- `LocksPage` (LocksPage.swift, 208 行)
- `MergeMembersView` (MemberCenterView.swift, 156 行)
- `MemberArchivedView` (MemberCenterView.swift, 112 行)
- `MemberFamilySettingsView` (MemberCenterView.swift, 129 行)
- `UnclaimedClaimView` (MemberCenterView.swift, 150 行)
- `MembersPage` (MembersPage.swift, 322 行)
- `MePage` (MePage.swift, 286 行)
- `SecurityAuditView` (SecurityCenterView.swift, 399 行)
- `SecurityPage` (SecurityPage.swift, 272 行)
- `SafemodeIntroView` (SettingsView.swift, 163 行)
- `StatsPage` (StatsPage.swift, 340 行)
- `StudioPage` (StudioPage.swift, 210 行)
- `TempCodeStudio` (CredentialStudio.swift, 489 行)
- `FpStudio` (CredentialStudio.swift, 401 行)

## ✅ 逐页核验为已丰富（20 页）

- `RootView` (LockKeeperApp.swift, 370 行)
- `AddLockPage` (AddLockPage.swift, 516 行)
- `AlarmCenterView` (AlarmCenterView.swift, 836 行)
- `BackupStudioView` (BackupStudio.swift, 257 行)
- `ExportWizardView` (BackupStudio.swift, 448 行)
- `RestoreWizardView` (BackupStudio.swift, 407 行)
- `BackupView` (BackupView.swift, 266 行)
- `MaintenanceView` (CareViews.swift, 285 行)
- `ExportCenterView` (ExportCenter.swift, 972 行)
- `FirmwarePage` (FirmwarePage.swift, 645 行)
- `MemberDetail360View` (MemberCenterView.swift, 447 行)
- `MemberWizardView` (MemberCenterView.swift, 198 行)
- `SecurityPeekView` (SecurityCenterView.swift, 311 行)
- `SecurityDestroyView` (SecurityCenterView.swift, 476 行)
- `ShareToAndroidView` (ShareToAndroidView.swift, 114 行)
- `OtpStudio` (CredentialStudio.swift, 507 行)
- `FpOwnerPicker` (FpOwnerPicker.swift, 108 行)
- `IconPicker` (IconPicker.swift, 112 行)
- `MemberExitWizard` (MemberCenterView.swift, 165 行)
- `PrivacyDashboard` (SecurityCenterView.swift, 90 行)

## ⬜ 未处理（0 页）

无

## 本轮从漏掉的 7 页里找到的缺口

`FpStudio` / `TempCodeStudio` 都**不显示容量**：

- `FpStudio` 只有「仅剩 1 枚指纹」这一个极端提示，看不到总共能录几枚
- `TempCodeStudio` 完全不显示 —— 而临时码与常驻密码**共用同一个库存池**（协议 0x25 `pwdStock`），填完表单才被锁端拒绝

两处都已补（`fpCap/fpStock`、`pwdCap/pwdStock`，与 `AddFingerPage`/`AddKeyPage` 同口径）。

## CI

见最新 run（`node tools/cistat.js`）。本地 23 道闸门全绿。
> ⚠ 本地闸门是文本级检查，**不等于**能编译 —— 见 [CI-VS-GATES.md](CI-VS-GATES.md)。

## 迁移遗留清理（本轮）

逐页核验「核验为已丰富」的那批页面时，发现了 **4 类 Form→ScrollView 迁移遗留**：

| 遗留 | 位置 | 处理 |
|---|---|---|
| 裸 `Section` 装在 `ScrollView` 里（List 外无视觉容器，是死包装）| `MemberExitWizard` ×2 | 改成 `XPanel(kind: .group)` |
| 同上 | `AlarmCenterView` ×3 | 改成透明 `Group`（外观不变，构造变正确）|
| 同上 | `MemberWizardView` ×2 | 改成透明 `Group` |
| `List` + `.listStyle(.insetGrouped)`（全仓 33 个文件用 XPanel，List 只剩 1 处）| `IconPicker` | 换成 `ScrollView` + `XPanel` 并补「当前图标名」|

### 为什么 `Section` 在 List 外是错的

`Section` 是 `List`/`Form` 的行分组容器。在 `ScrollView` 里它**不产生任何视觉容器**，
只是把子视图原样透出 —— 写它与写 `Group` 等价，但会让读者以为这里有分组语义。

### `LocksPage` 的 `List` 要保留

`LocksPage.swift:39` 的 `List` 是**故意的**：它需要 `.swipeActions` + `.onMove`，
`ScrollView` 给不了。这是全仓唯一合法的 `List`。

### 相关闸门

`swiftshape` 的 R8/R9 只查 `Section("标题")` 带 footer 的写法，**查不出 List 外的裸 Section**。
这批是逐页阅读时人工发现的 —— 说明闸门覆盖不到"容器语义错位"。
