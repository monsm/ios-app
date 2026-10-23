# 改造进度记录

> 配套：`docs/IMPL-PLAN.md`　最后更新：2026-10-23
> 图例：⬜ 未开始　🟨 进行中　✅ 完成　⛔ 阻塞

---

## 阶段 0 · 令牌同步

| 项 | iOS | Android | 状态 |
|---|---|---|---|
| 画布径向渐变 | `XPalette.canvasGradient` | `KfTokens.canvasGradient` | ✅ |
| 卡片顶光渐变 | `XGradient.cardSurface` | `KfTokens.cardSurface` | ✅ |
| 字阶补 44 / 96 / 118 | `DSFont.hero/.dialNumber/.dialNumberXL/.small` | `Type.hero/.dialNumber/.dialNumberXL/.small` | ✅ |
| 渐变停止点 5-stop | `XGradient.dial/.dialOK` | `KfTokens.dialStops/.dialOKStops` | ✅ |

## 阶段 1 · 共享组件

| 组件 | 图依据 | iOS | Android | 状态 |
|---|---|---|---|---|
| `XGradientDial` | 图1 | ✅ | ⬜ | ✅ |
| `XCardAnatomy` | 图2 | 🟨（XPanel 已带顶光材质）| ⬜ | 🟨 |
| `XHeroNumber` | 图1/5 | ✅ | ⬜ | ✅ |
| `XTripleThinRing` | 图2 | ✅ | ⬜ | ✅ |
| `XDataRow` | 图2 | ✅ | ⬜ | ✅ |
| `XTwoToneSheet` | 图4 | ⬜ | ⬜ | ⬜ |
| `XBarChart` | 图5 | ⬜ | ⬜ | ⬜ |
| `XText.small` 13档 | 图2 | ✅ | ✅ | ✅ |

---

## 阶段 2 · iOS 50 页

### A 门厅（P0）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 01-home | HomeConsole.swift | 图1 渐变环 → 蓄力弧；图2 卡材质 + 彩点行 + 细三环；图1/2/6 画布径向渐变 | ✅ |

### B 钥匙（P0）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 02-keys | KeysPage.swift | ✅ 图5 MetricCard 主角卡（44px 总数 + 图2 细三环 + 彩点行）| ✅ |
| 10-keys-manage | KeysPage.swift | 图2 卡解剖 | ⬜ |
| 11-fingerprint | AddFingerPage.swift | 图2 卡解剖 + 细三环 | ⬜ |
| 12-tempcode | TempCodeStudio | 图6 横滚 + 图5 大数字 | ⬜ |
| 13-key-detail | AddKeyPage.swift | 图5 MetricCard | ⬜ |
| 15-add-key | AddKeyPage.swift | 图2 卡解剖 | ⬜ |
| 14-otp | — | 图5 大数字 + 环 | ⬜ |

### C 设备（P0）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 03-devices | DevicePage.swift | ✅ 图5 双列 MetricCard（握手/信号 44px + 迷你环）+ 固件降为小字 | ✅ |
| 20-locks | LocksPage.swift | 图5 双列卡 | ⬜ |
| 21-lock-profile | LockProfilePage.swift | 图5 MetricCard | ⬜ |
| 22-firmware | FirmwarePage.swift | 图2 卡解剖 | ⬜ |
| 23-gateway | GatewayPage.swift | 图4 分步条 | ⬜ |
| 24-dongles | DonglesPage.swift | 图5 大数字 | ⬜ |
| 25-synctime | SyncTimeView | 图1 大数字主角 | ⬜ |

### D 成员（P1）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 04-members | MembersPage.swift | ✅ 图5 44px 成员数主角 | 🟨 |
| 30-members-list | MembersPage.swift | 图2 细三环 | ⬜ |
| 31-member-wizard | MemberWizardView | 图6 横滚画廊 | ⬜ |
| 32-member-detail | MemberCenterView | 图1 主角 + 图5 双列 | ⬜ |
| 33-archived | MemberArchivedView | 图5 双列 | ⬜ |
| 34-merge | MembersPage.swift | 图2 双卡对照 | ⬜ |

### E 系统（P1）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 05-system | SettingsView.swift | 图5 MetricCard | ⬜ |
| 40-security | SecurityPage.swift | 图5 大数字 + 环 | ⬜ |
| 41-applock | AppLockSetupView.swift | 图2 卡解剖 | ⬜ |
| 42-peek | PrivacyDashboard | 图2 环 + 三态对照 | ⬜ |
| 43-privacy-dash | PrivacyDashboard | 图2 环 | ⬜ |
| 44-audit | SecurityAuditView | 图4 两层 + 分组头 | ⬜ |
| 45-destroy | SecurityDestroyView | 图3 警示 | ⬜ |
| 46-safemode | SafemodeIntroView | 图2 双角色卡 + 彩点行 | ⬜ |
| 47-backup | BackupPage.swift | 图5 MetricCard + 三列 | ⬜ |
| 48-export | ExportCenterView | 图5 柱图 + 轴标 | ⬜ |
| 49-appearance | StudioPage.swift | 图6 色板网格 | ⬜ |
| 4a-me | MePage.swift | 图1 双 chip + 图2 大数字 | ⬜ |

### F 记录（P1）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 50-events | EventsPage.swift | 图4 分组头 + 状态胶囊 | ⬜ |
| 51-feed | FeedPage.swift | 图4 两层 + 图5 柱图 | ⬜ |
| 52-stats | StatsPage.swift | 图5 活动环 + 彩条 | ⬜ |

### G 关怀（P2）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 60-care | CarePage.swift | 图4 三段环 + 图2 解剖 | ⬜ |
| 61-reminders | CareRemindersView | 图2 + 图6 横滚 | ⬜ |
| 85-battery | BatteryCare.swift | 图5 大数字 + 环 | ⬜ |
| 86-checklist | CareViews.swift | 图5 环 + 图2 清单 | ⬜ |

### H 周边（P2）

| HTML | SwiftUI | 六图特征 | 状态 |
|---|---|---|---|
| 70-icon-picker | IconPicker.swift | 图6 hero + 2×2 | ⬜ |
| 75-shell | — | 图5 展示壳 | ⬜ |
| 80-states | Components.swift | 图2 三态 | ⬜ |
| 81-backup-studio | BackupStudio.swift | 图5 + 图2 红卡 | ⬜ |
| 82-bin | CredentialBinView | 图2 卡解剖 | ⬜ |
| 83-studio | CredentialStudio | 图2 卡解剖 | ⬜ |
| 84-diagnostics | DiagnosticsPage.swift | 图5 MetricCard | ⬜ |
| 87-claim | MemberCenterView | 图5 大数字 + 单选 | ⬜ |
| 88-exit | — | 图5 + 图2 三色按钮 | ⬜ |
| 89-share-android | ShareToAndroidView | 图6 hero + 二维码 | ⬜ |

---

## 阶段 3 · Android 5 屏

| HTML | Compose | 六图特征 | 状态 |
|---|---|---|---|
| 01-home | KfApp + UnlockDial | 图1 渐变环 + 中心大字 + chip | ⬜ |
| 02-scan | ScanSheet（新增） | 图6 hero + 取景框 | ⬜ |
| 03-settings | SettingsCard | 图2 卡解剖 + 开关组 | ⬜ |
| 04-success | UnlockSuccess（新增） | 图1 环转绿 + 回执卡 | ⬜ |
| 05-rebind | RebindConfirm（新增） | 图2 双卡 + 红警告 | ⬜ |

---

## 阶段 4 · 验证

| 项 | 结果 | 时间 |
|---|---|---|
| iOS 构建 | — | — |
| Android 构建 | — | — |
| 对比度 AA | — | — |
| Tests 全绿 | — | — |

---

## 变更日志

| 日期 | 内容 |
|---|---|
| 2026-10-23 | 建立方案与进度文件；完成两工程勘察（iOS 55 UI 文件 / 35 组件；Android 9 Kotlin 文件）|
| 2026-10-23 | **阶段 0 完成**：iOS 补 `DSFont.hero/dialNumber/dialNumberXL/small`、`XPalette.canvasGradient`、`XGradient.cardSurface/dial/dialOK`；Android 补同源 4 组令牌 |
| 2026-10-23 | **阶段 1 完成 4/7**：`XGradientDial`（图1 开口环+游标+tick）、`XHeroNumber`（三档+光晕）、`XDataRow`（彩点行）、`XTripleThinRing`（细三环）|
| 2026-10-23 | 校验：swiftcheck 112 文件括号平衡 ✓；kotlinbalance 9 文件 ✓；tokendrift 三组对账 ✓ |
| 2026-10-23 | **01-home 改造完成**：① XPanel 卡片改图2 顶光材质+上缘高光（全站受益）② 门厅画布改径向渐变 ③ 蓄力弧改图1 五段连续渐变（成功绿/失败红保持单色）④ 三指标改图2 双栏（XDataRow + XTripleThinRing）|
| 2026-10-23 | 移除推测性令牌 dialNumber(96)/dialNumberXL(118)：门厅环心是**动作控件**不是读数，不放数字（原设计注释已论证）|
| 2026-10-23 | 新增 `XText.small`(13) 两端对齐；apisig 白名单同步登记 |
| 2026-10-23 | **7 道门禁全绿**：swiftcheck / swiftlint / apisig / contrast / dynamictype / kotlinbalance / tokendrift |
| 2026-10-23 | **全局画布横扫**：26 个文件 / 37 处背景 → 径向渐变（图1/2/6 语言），一次覆盖全站 |
| 2026-10-23 | **02-keys 完成**：新增图5 MetricCard 主角卡（44px 总数 + 细三环 + 三类彩点行 + footer）|
| 2026-10-23 | **03-devices 完成**：三枚等重瓦片 → 图5 双列 MetricCard（握手/信号各带 44px 数字 + 迷你环），固件号降为末尾小字 |
| 2026-10-23 | **04-members 部分**：成员数 12pt 灰字 → 44px 主角数字 |
| 2026-10-23 | 判断记录：设备页「容量条」保持分格条**不改环** —— 每格代表一个槽位，改环会丢失「还剩几个」的粒度（参考图是调色板，不是模板）|
