# 实施方案 · 按 6 参考图改造 iOS / Android 实际项目

> 状态：**执行中**　最后更新：2026-10-23
> 依据：`tools/proto/`（iOS 50 页 HTML 原型）、`tools/android-proto/`（Android 5 页 HTML 原型）
> 参考图：图1 Health Age / 图2·3 Winding Down / 图4 Sports / 图5 Activity Details / 图6 Face Gallery

---

## 0. 一句话目标

把 HTML 原型里已经验证过的**六图设计语言**，落到两个真实工程（SwiftUI / Jetpack Compose）的每一页，
使原生实现与 HTML 原型在**版式、层次、组件形态、数据密度**上一致。

**不做的事**：不改业务逻辑、不改协议、不改数据模型。本次只改**呈现层**。

---

## 1. 六图设计语言 → 可执行令牌（唯一事实来源）

| # | 特征 | 具体值 | HTML 出处 | 原生落点 |
|---|---|---|---|---|
| 1 | 画布 | `radial-gradient(ellipse 130% 85% at 50% 6%, #0A0E1A, #06070C 38%, #000)` | tokens.css | `XPalette.canvas` / `KfTokens.canvas` |
| 2 | 卡片材质 | `linear-gradient(180deg,#202020,#191919 26%,#171717)` + `inset 0 .5px 0 rgba(255,255,255,.055)` | tokens.css | `XCardSurface` / `KfCard` |
| 3 | 卡解剖 | cardlink 14 → title 19 → label 12 / value 16 → sep → cols → footer 12 | 图2 | `XCardAnatomy` |
| 4 | 渐变大环 | 5-stop `#4A9E96→#2E8FC0→#1E6AAE→#1560A8→#0A84FF`，宽 9.2%，底部开口 11.5%，游标白边，顶部 tick | 图1 | `XGradientDial` |
| 5 | 主角数字 | MetricCard 44px / 旗舰 96–118px，带 glow | 图1/图5 | `XHeroNumber` |
| 6 | 细三环 | 线宽 = 尺寸 × 0.045，中心数字 | 图2 | `XTripleThinRing` |
| 7 | 彩色数据行 | dot + 数字 + 单位同色 | 图2 | `XDataRow` |
| 8 | 玻璃 chip | 图标砖 + label/value 双行 | 图1 | `XChip`（已有 `XStatChip`）|
| 9 | footer 整句 | 12px 灰，一句说清"为什么这样设计" | 图2 | 卡组件内置 |
| 10 | 两层结构 | 深头（亮 2×）+ 内容板圆角 17 上叠 22 | 图4 | `XTwoToneSheet` |

---

## 2. 分阶段计划

### 阶段 0 · 令牌同步（0.5 天）

| 项 | iOS | Android |
|---|---|---|
| 画布径向渐变 | `App/Core/Theme.swift` → `XPalette.canvasGradient` | `Tokens.kt` → `canvas` Brush |
| 卡片顶光渐变 | `XCardSurface` 新组件 | `KfCard` modifier |
| 字阶补 44 / 96 / 118 | `DSFont` 增 `hero` / `dialBig` | `KfTokens.Type` 同步 |
| 渐变停止点 | `XGradient.dial` 5-stop | `KfTokens.dialStops` |

**验收**：两端口径一致（同值，注释互指）。

### 阶段 1 · 共享组件（1 天）

新增/改造（iOS `App/Core/Components.swift`，Android `ui/components/`）：

1. `XGradientDial` — 图1 渐变开口环（5-stop、游标、tick、中心插槽）
2. `XCardAnatomy` — 图2 卡解剖容器（cardlink/title/label/value/sep/cols/footer）
3. `XHeroNumber` — 44/96/118 三档大数字 + glow
4. `XTripleThinRing` — 图2 细三环 + 中心数字
5. `XDataRow` — 图2 彩色数据行
6. `XTwoToneSheet` — 图4 两层结构
7. `XBarChart` — 图5 柱图 + 轴标（已有 `XDayClock` 可复用）

**验收**：每组件有 Preview，与 HTML 截图并排比对。

### 阶段 2 · iOS 50 页逐页改造（主要工作量）

按 Tab 分组，每页流程：
1. 打开对应 HTML（`tools/proto/NN-xxx.html`）与当前 SwiftUI 文件
2. 对照六图逐元素列出差异（写进进度文件）
3. 改代码
4. `xcodebuild` 构建 + 截图比对
5. 更新进度

**分组与顺序**：

| 组 | 页（HTML） | SwiftUI 落点 | 优先级 |
|---|---|---|---|
| A 门厅 | 01-home | HomeConsole.swift | P0 |
| B 钥匙 | 02-keys / 10-keys-manage / 11-fingerprint / 12-tempcode / 13-key-detail / 15-add-key / 14-otp | KeysPage / AddFingerPage / TempCodeStudio / AddKeyPage | P0 |
| C 设备 | 03-devices / 20-locks / 21-lock-profile / 22-firmware / 23-gateway / 24-dongles / 25-synctime | DevicePage / LocksPage / LockProfilePage / FirmwarePage / GatewayPage / DonglesPage / SyncTime | P0 |
| D 成员 | 04-members / 30-members-list / 31-member-wizard / 32-member-detail / 33-archived / 34-merge | MembersPage / MemberWizardView / MemberArchivedView | P1 |
| E 系统 | 05-system / 40-security / 41-applock / 42-peek / 43-privacy-dash / 44-audit / 45-destroy / 46-safemode / 47-backup / 48-export / 49-appearance / 4a-me | SettingsView / SecurityPage / AppLockSetupView / PrivacyDashboard / SecurityAuditView / SecurityDestroyView / SafemodeIntroView / BackupPage / ExportCenterView / StudioPage / MePage | P1 |
| F 记录 | 50-events / 51-feed / 52-stats | EventsPage / FeedPage / StatsPage | P1 |
| G 关怀 | 60-care / 61-reminders / 85-battery / 86-checklist | CarePage / CareRemindersView / BatteryCare | P2 |
| H 周边 | 70-icon-picker / 75-shell / 80-states / 81-backup-studio / 82-bin / 83-studio / 84-diagnostics / 87-claim / 88-exit / 89-share-android | IconPicker / BackupStudio / CredentialStudio / DiagnosticsPage / ShareToAndroidView | P2 |

### 阶段 3 · Android 5 屏改造

| HTML | Compose 落点 | 改造点 |
|---|---|---|
| 01-home | `KfApp` + `UnlockDial` | 渐变开口环（当前是纯色描边圆）、中心大字、双 chip |
| 02-scan | 新增 `ScanSheet` | 蓝渐变 hero + 取景框 + 权限卡 |
| 03-settings | `SettingsCard` | 图2 卡解剖 + 开关组 |
| 04-success | 新增 `UnlockSuccess` | 环转绿 + 回执卡 |
| 05-rebind | 新增 `RebindConfirm` | 双卡对照 + 红色警告 |

### 阶段 4 · 验证与收尾

| 验证 | 方法 |
|---|---|
| 构建 | iOS `xcodebuild`；Android `gradlew assembleDebug` |
| 视觉 | 每页模拟器截图 vs HTML 截图并排 |
| 令牌 | iOS `tools/apisig.js` 零引用检查；Android 消费点检查 |
| 对比度 | `tools/contrast.js`（WCAG AA）|
| 回归 | 现有 Tests/ 全绿 |

---

## 3. 约束（不可违反）

1. **只改呈现层** —— 不动 Store/Service/Protocol
2. **令牌唯一来源** —— 颜色走 `XPalette`/`KfTokens`，不散落 `Color(hex:)`
3. **只做深色** —— 规范 §13.4，不提供 App 内明暗切换
4. **一屏一个主角** —— 最多一个 ≥200pt 环或一个 ≥44px 数字
5. **一屏 ≤3 种强调色**
6. **Dynamic Type** —— 全部走语义字号，不裸写 `.font(.system(size:))`
7. **触达尺寸** —— iOS ≥44pt，Android ≥48dp（不混用）

---

## 4. 每页完成定义（DoD）

- [ ] 与对应 HTML 逐元素比对过，差异清单写进进度文件
- [ ] 六图特征至少落实 3 条（写清是哪几条）
- [ ] 构建通过，无新增 warning
- [ ] 截图归档到 `docs/IMPL-SNAPS/`
- [ ] 进度文件状态更新为 ✅
