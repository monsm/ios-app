# 冗余清理候选清单（Lead 独立核实部分）

> 这部分是我（Lead）在等三名成员分析期间，**逐符号 grep 核实**过的确定项。
> 全部证据都是「跨文件零引用 / 零调用 / 仅注释」。

## A. 完全死代码（可整体删除）

| 文件 | 行数 | 证据 | 说明 |
|---|---|---|---|
| `Core/DevModules.swift` | 18 | **非注释行只有 1 条 `import Foundation`** | 「设备页模块显隐」批次的半成品，只有设计注释没有实现 |
| `Core/SpeechKit.swift` | 9 | 全仓零引用 | 注释说「全站唯一朗读出口」，但没有任何调用方 |
| `UI/RealityAPIProbe.swift` | 259 | 零引用 | RealityKit API 探针（累加式，只增不删） |
| `UI/BladeMesh.swift` | 109 | 只被 XLockBlade 用 | 3D「刃」组装层 |
| `UI/BladeGeometry.swift` | 296 | 只被 BladeMesh/XLockBlade 用 | 3D「刃」几何 |
| `UI/XLockBlade.swift` | 233 | 只被 RealityAPIProbe 用 | 3D「刃」视图层 |

**RealityKit「刃」整族 = 890 行**：它们互相引用形成闭环，但**没有任何入口**（没有任何页面把 XLockBlade 挂到界面上）。这是最典型的"做了一个 3D 组件但没接进 App"。

## B. 定义了但没接入的功能（半成品）

| 文件 | 行数 | 证据 |
|---|---|---|
| `Core/SettingsGroups.swift` | 53 | 定义了 `SettingsGroup` 枚举 + `settingsSectionShown()`，但**该函数全仓零调用** —— 设置页五组分区只做了骨架没接进去 |

## C. 零使用的 UI 组件

| 组件 | 文件 | 证据 |
|---|---|---|
| `StepDots` | CredentialStudio | 本文件 0 次 + 跨文件 0 次 |
| `FindArrowLayer` | FindArrowLayer.swift (40 行) | 零引用（Android 有 SignalArrow.kt，iOS 版没接入）|
| `DeviceStripCard` | DeviceStripCard.swift (12 行) | 零引用 |
| `LocalBackupFilesSection` | BackupStudio | 只在本文件用 1 次，但 BackupStudio 本身是可达页 |
| `MemberExitWizard` | MemberCenterView | 本文件 1 次，跨文件 0 次 |
| `MergeMembersView` | MemberCenterView | **只在 Destination.swift 里出现**（枚举登记），无实际调用点 |

## D. 需要你判断的「功能重叠」

| 现象 | 涉及 | 说明 |
|---|---|---|
| 两套「统计」 | `StatsPage`(467行) + `HomeConsole` 里的面积图 | StatsPage 只能从 EventsPage 进 |
| 两套「告警」 | `AlarmsPage`(466行) + `SecurityAuditView` | 前者是告警流，后者是变更记录，有重叠 |
| 两套「备份」 | `BackupPage`(697) + `BackupStudio`(1419) | BackupStudio 从 BackupPage 进，是"高级"版 |
| 三套「保养」 | `CarePage` + `MaintenanceView` + `CareChecklistView` + `BatterySwapGuideView` | CarePage 是总页，另三个是子页 |
| 两套「安全总览」 | `SecurityPage`(364) + `PrivacyDashboard` | 前者"本机保护"，后者"隐私看板" |

---

## 还在等的部分

三名成员正在并行分析：
- **ui-inventory** → `docs/FEATURES/ios-ui.md`（51 个 UI 文件的最小功能点）
- **core-inventory** → `docs/FEATURES/ios-core.md`（55 个 Core/Services 文件）
- **android-inventory** → `docs/FEATURES/android.md`（9 个 Kotlin 文件）

他们产出后我会合并成一张**全量功能点总表**给你逐条判断。
