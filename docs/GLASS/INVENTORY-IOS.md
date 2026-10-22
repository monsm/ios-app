# INVENTORY-IOS — iOS 页面地毯式清点

> 作者：ios-inventory（teammate）· **只读清点**，未修改任何 `.swift` / `.kt` / `tools/*.js`
> 唯一产出：本文件 `docs/GLASS/INVENTORY-IOS.md`
> 取证面：`D:\aapk\ios-app\App\` 全 **109** 个 `.swift`（45,617 行，其中 `App/UI` 53 文件 24,374 行）
> 规范面：`ios-glass-design-spec/references/design-spec.md` §0/§1/§3/§4/§5/§7/§8

---

## §0 口径、证据分档与**必须先读的三条勘误**

### 0.1 证据分档（每一行都标）

| 档 | 含义 | 复现方式 |
|---|---|---|
| **E1** | 我实际跑了命令并有输出 | 命令原文 + 关键输出写在该行 |
| **E2** | 我读了源码，当行内容可复现 | `文件:行` 即证据，引用行内原文片段 |
| **E3** | 从别的文档转述 | 写出处 |
| 未读到 | 我没读到对应源码 | **不猜** |

### 0.2 勘误 · 三条任务卡前提与代码不符（**先纠正再排施工单**）

#### 勘误 1：`Destination` 不是 19 个"页面"，是 19 个"登记过的目的地"

任务卡写「Destination 枚举只有 19 个，由 tools/destmap.js 生成」—— **数量对，语义错**。

- `Destination` 只有 19 条（`App/Core/Destination.swift:8-27`，E2），但它是**台账标记**，不是页面清单。
- 挂标记的方式是 `.destined(.xxx)`，全仓只有 **18 处**（E1：`grep -c ".destined(" over HEAD` = 18）。
- 关键：**没挂 `.destined` 的页面根本不在这个枚举里**。`HomeConsole` / `ManagerFace` / `MePage` / `LocksPage` / `MembersPage` / `KeysPage` / `EventsPage` / `StatsPage` / `AlarmsPage` / `DevicePage` / `FeedPage` / `SecurityPage` 全都不在 Destination 里。
- 所以 `tools/uicoverage.js` 报的「缝覆盖率 18/19」**不等于**"19 个页面里覆盖 18 个"。

> **E1**：`node tools/destmap.js` → 末行「目的地总数 = 19 （扫 109 个 .swift…）」
> **E1**：`node tools/uicoverage.js` → 「检查二 · 缝覆盖率 = 18/19 (95%) / 未挂缝 1 条: · CredentialBinView」
> **E2**：`App/UI/CredentialBinView.swift:23` 有 `struct CredentialBinView: View`，但**全仓无 `.destined(.credentialBin)`**（grep 零命中）。

#### 勘误 2：`ManagerRoute` 是 **21** 个 case，不是 20 个

**E2** —— `App/UI/ManagerFace.swift:277`（WT）起的枚举体：

    case keys, fingerprints, tempCodes                              // 3
    case locks, firmware, gateway, dongles, syncTime                // 5
    case members, memberWizard, mergeMembers, archivedMembers       // 4
    case securityCenter, securityAudit, securityDestroy, safemode   // 4
    case backup, export, appearance, me                             // 4
    case diagnostics                                                // 1
    ── 合计 21 ──

**但只落到 20 个不同页面**：`mergeMembers` 也落到 `MembersPage`（`ManagerFace.swift:252`，注释自陈"路由层拿不到那个 Member，所以落到成员列表"）。
`tools/pagecraft.js` 的 `.routes.json` 只有 **20 行**且缺 `diagnostics`（E2：全文件 240 字节，末项 `["me","MePage"]`）—— 台账比代码少 1 条，且 `appearance` 那行写的是 `StudioPage`（见 IOS-C-10）。

#### 勘误 3（最重要）："设置页两套并行入口"低估了 —— 实际是**三套**，且两套**行为不一致**

| # | 通道 | 数量 | 证据 |
|---|---|---|---|
| A | `ManagerFace` 5 组 → `navigationDestination` | 21 route / 20 页 | `ManagerFace.swift:237`(routeDestination) / `:83`(navigationDestination) |
| B | `MePage` 内联 `NavigationLink` | **20 条** | `MePage.swift:147,156,168,191,198,206,213,219,226,235,251,259,274,281,320,324,331,337,344,350`（E2，逐条已核） |
| C | `SecurityPage` 的 `actionRow` 泛型 `NavigationLink` | 4 条 | `SecurityPage.swift:279`(定义) + `:257,262,267,271`(调用) |

A 与 B 的关键不一致：

| 功能 | A 通道 | B 通道 | 一致？ |
|---|---|---|---|
| 安全总览 | `.securityCenter` → `PrivacyDashboard` | "本机数据保护" → `SecurityPage` | ❌ 仍是两个不同页 |
| 隐私与伪装 | 无（在 `PrivacyDashboard` 里逐项开关） | "隐私与伪装" → `SecurityPeekView` | ⚠ 两套 UI 做同一件事（A 是 5 项点按行，B 是完整设置页） |
| 合并成员 | `.mergeMembers` → **`MembersPage`** | 无 | ❌ 菜单名与落点不符 |
| 外观 | `.appearance` → `AppearancePage` | **无入口** | ❌ B 完全没有外观 |
| 应用锁 | **无入口** | `SecurityPage:257` 才进得去 | ❌ 从管理面板永远开不了应用锁 |
| 回收站 | **无** | **无** | ❌ 唯一入口在 `SecurityDestroyView:998` |

> `docs/redesign/DESIGN-DECISIONS.md:25-29` 的 D3 写着"**不改**"，推翻条件是「如果出现同一功能在两处行为不一致」。
> **§5 证明这个推翻条件已经成立**（E3 出处：`docs/redesign/DESIGN-DECISIONS.md:29`）。

### 0.3 本轮**取证基准与漂移声明**（必须读）

清点期间 Lead 正在同仓改代码。我做了**两次快照**，第二次（本文采用）实测到 **43 个文件**处于 `M` 状态，其中 **36 个是 `.swift`**：

**E1** —— `git status --porcelain` @ **2026-10-22T16:06+08:00**，HEAD = `803b6c8`：

| 文件 | HEAD 行数 | WT 行数 | Δ |
|---|---|---|---|
| `App/Core/Components.swift` | 1443 | **1652** | **+209** |
| `App/Core/Theme.swift` | 412 | **560** | **+148** |
| `App/UI/HomeConsole.swift` | 1117 | **1177** | **+60** |
| `App/Core/AccessibilityKit.swift` | 336 | **296** | **−40** |
| `App/UI/ManagerFace.swift` | 299 | 335 | +36 |
| `App/UI/StatsPage.swift` | 377 | 400 | +23 |
| `App/UI/GatewayPage.swift` | 438 | 448 | +10 |
| `App/UI/DonglesPage.swift` | 407 | 416 | +9 |
| `App/UI/LockProfilePage.swift` | 394 | 403 | +9 |
| `App/UI/Celebration.swift` | 88 | 96 | +8 |
| `App/UI/DevicePage.swift` | 503 | 511 | +8 |
| `App/UI/KeysPage.swift` | 577 | 585 | +8 |
| `App/UI/MePage.swift` | 358 | 365 | +7 |
| `App/UI/StudioPage.swift` | 252 | 257 | +5 |
| `App/UI/AddKeyPage.swift` | 457 | 460 | +3 |
| `App/UI/AddLockPage.swift` | 597 | 600 | +3 |
| `App/UI/CredentialStudio.swift` | 1975 | 1978 | +3 |
| `App/UI/AlarmsPage.swift` | 417 | 419 | +2 |
| `App/UI/EventsPage.swift` | 776 | 778 | +2 |
| `App/UI/SecurityPage.swift` | 310 | 312 | +2 |
| `App/UI/ShareToAndroidView.swift` | 122 | 124 | +2 |
| `App/Core/Destination.swift` | 30 | 31 | +1 |
| `App/UI/IconPicker.swift` | 150 | 151 | +1 |
| 其余 13 个 .swift | — | — | **0**（只是被 touch/换行） |

> **结论**：本文所有行号都**符号名 + 行号成对**给出。行号对不上就用符号名 grep —— 那是稳的。
> 热文件（Components / Theme / HomeConsole / ManagerFace）**每 10 分钟就会变一次**，不要在它们上面按行号施工。

### 0.4 本轮 Lead 同步修复的（我已复核，**这几条不要再当问题报**）

| 原编号 | 原问题 | 现状 | 复核证据 |
|---|---|---|---|
| ~~**IOS-S-03**~~ | ~~`MePage` 两条 NavigationLink 指向同一页~~ | ✅ **本轮已被 Lead 修复**（详见 §0.4）：`MePage.swift:161` 现为 `SecurityPeekView()` | — | 关闭 |
| （§3.1 阴影） | `.shadow(` 14 处（11 文件） | ✅ **降至 5 处（3 文件）** | E1：快照计数 `shadow: 5` |
| （§3.1 玻璃） | `.ultraThinMaterial|.glassEffect(` 4 处 | ✅ **降至 2 处** | E1：快照计数 `ultraThin: 2` |
| （§3.1 xPlate） | `.xPlate(` 20 处 | ✅ **降至 17 处**（改用 `XGlassSurface` / `XPanel`） | E1：快照计数 `xPlate: 17` |

> 本节存在的意义：**别让 Lead 修完的东西再被下一份文档当成落后项**。

### 0.5 引用自检（E1，可复现）

本文共 **251 个 `文件:行` 引用**（去重后）。我对**当前工作树**逐条解析：

| 结果 | 数量 | 说明 |
|---|---|---|
| ✅ 行内容非空且语义匹配 | **246** | 脚本逐条打印该行文本比对 |
| ⚠ 按 **HEAD** 解析（WT 已挪行） | **5** | `Components.swift:142`(XHairline 线宽) · `Components.swift:152`(XStatusPill) · `KeysPage.swift:294`(XEmptyState) · `DevicePage.swift:93`(XBatteryGauge size 116) · `MePage.swift:318`(IconPicker link) —— 这 5 处在正文里已标注 **HEAD** |
| ❌ 解析失败 | **0** | — |

> 复现方式：把本文所有 `\.swift:(\d+)` 抽出来，逐条 `read` 该行，再与上下文比对。


---

## §1 页面总表（**地毯式全量**，62 条）

### 判据

一个 `struct X: View` 满足任一条即登记为"页"：
1. 被 `.sheet(` / `.fullScreenCover(` / `navigationDestination(` / `NavigationLink(` / `.popover(` 呈现；或
2. 是根屏；或
3. **被作为"一整屏"的私有 `var` 包着呈出**（如 `BackupPage.importSheet`，不是 struct，单列在 §1.7）。

**E1 全量扫描（WT，2026-10-22T15:58）**：

| 通道 | 站点数 | 文件数 |
|---|---|---|
| `.sheet(` | **26** | 14 |
| `.fullScreenCover(` | **1** | 1 |
| `navigationDestination(` | **1** | 1 |
| `NavigationLink(` | **35** | 9 |
| `.popover(` | **0** | 0 |
| `TabView` | **0**（4 Tab 确已删净） | 0 |
| **合计呈现站点** | **63** | — |

未解析到目标名的 7 个站点：

    App/UI/BackupPage.swift:69        sheet  → importSheet（私有 var，见 §1.7）
    App/UI/CredentialStudio.swift:1518 sheet → importSheet（私有 var）
    App/UI/ExportCenter.swift:1532     fsc   → QLPreviewView（UIViewControllerRepresentable）
    App/UI/HomeConsole.swift:203       sheet → EventsPage(initialHour:)（Binding 参数跨行）
    App/UI/HomeConsole.swift:214       sheet → MemberDetail360View（Binding 参数跨行）
    App/UI/ManagerFace.swift:83        navDest→ 21 个 ManagerRoute（A 组）
    App/UI/SecurityPage.swift:283      navLink→ 泛型 Destination（4 个实参，C 组）

### 1.1 根屏层（2 条）

| 编号 | 页面名 | 类型 | 定义位置 | 入口（文件:行 + 通道） | 入口数 | 分组 | 一句话职责 | 分区数 | 证据 |
|---|---|---|---|---|---|---|---|---|---|
| IOS-P-001 | `RootView` | 根屏（宿主，非用户页） | `App/LockKeeperApp.swift:941` | `LockKeeperApp.swift` 的 `@main` App body | 1 | 全局 | 挂 6 条顶部横幅 + 水印 + MomentLayer + 启动链 | 5（含 1 个零调用） | E2 |
| IOS-P-002 | `HomeConsole` | **根屏（唯一主界面，"门厅"）** | `App/UI/HomeConsole.swift:53`（WT） | `LockKeeperApp.swift:992`（HEAD）`mainTabsChrome` compose | 1 | 门厅 | 长按开锁 + 今日数据 + 5 个管理入口 | **9** | E2 |

> `RootView.bleStatusStrip`（`LockKeeperApp.swift:1326` HEAD）**定义后零调用** —— 顶部 BLE 细条这条路是死的（IOS-S-07）。

### 1.2 门厅 sheet（5 站点 → 4 类页面）

| 编号 | 页面名 | 类型 | 定义位置 | 入口 | 入口数 | 分组 | 职责 | 分区数 | 证据 |
|---|---|---|---|---|---|---|---|---|---|
| IOS-P-003 | `ManagerFace` | **sheet（管理面板，自带 NavigationStack）** | `App/UI/ManagerFace.swift:27`（WT） | `HomeConsole.swift:197` `.sheet(item: $managerGroup)` | 1（+4 处程序化赋值 `:190,:368,:369,:504`(HEAD)） | 管理 | 5 组 × 3–5 入口 = **21 route** | 3 | E2 |
| IOS-P-004 | `AddLockPage` | sheet（**向导 4 步**） | `App/UI/AddLockPage.swift:23`（WT） | `HomeConsole.swift:200` / `LocksPage.swift:153` / `FeedPage.swift:78` | **3** | 设备 | 发现→配网→命名→完成 | 7 | E2 |
| IOS-P-005 | `EventsPage` | sheet（**2 个入口语义不同**） | `App/UI/EventsPage.swift:32`（WT） | ①`HomeConsole.swift:203`(带 initialHour) ②`:211`(无参) ③`MePage.swift:279` | **3** | 记录 | 按天时间线 + 查询引擎 + 同步日志 | 9 | E2 |
| IOS-P-006 | `MemberDetail360View` | sheet + NavigationLink | `App/UI/MemberCenterView.swift:15`（WT） | ①`HomeConsole.swift:214`(门厅胶囊直达) ②`MembersPage.swift:91` ③`:141` | **3** | 成员 | 6 个 360° 分区 | 6 | E2 |

### 1.3 管理面板 21 route → 20 叶子（A 组）

| 编号 | route | 页面名 | 定义位置 | 组 | 一句话职责 | 分区数 | 证据 |
|---|---|---|---|---|---|---|---|
| IOS-P-007 | `.keys` | `KeysPage` | `App/UI/KeysPage.swift:31`（WT） | 钥匙 | 到期预警 + 4 段筛选 + 凭证卡 + 长按菜单 | 8 | E2 |
| IOS-P-008 | `.fingerprints` | `AddFingerPage` | `App/UI/AddFingerPage.swift:24` | 钥匙 | 指纹录入舞台 + 归属 | 6 | E2 |
| IOS-P-009 | `.tempCodes` | `TempCodeStudio` | `App/UI/CredentialStudio.swift:510`（WT） | 钥匙 | 临时码三段表单 + 扫码 | 5 | E2 |
| IOS-P-010 | `.locks` | `LocksPage` | `App/UI/LocksPage.swift:30` | 设备 | **全仓唯一 `List`** + 排序/隐藏/解绑 | 1(+2 Section) | E2 |
| IOS-P-011 | `.firmware` | `FirmwarePage` | `App/UI/FirmwarePage.swift:23` | 设备 | 版本/包/体检/升级中/失败/队列/历史 | **10** | E2 |
| IOS-P-012 | `.gateway` | `GatewayPage` | `App/UI/GatewayPage.swift:21` | 设备 | 两步配网 + 进度 + 网关卡 | 6 | E2 |
| IOS-P-013 | `.dongles` | `DonglesPage` | `App/UI/DonglesPage.swift:22`（WT） | 设备 | 蓝牙钥匙串写入/删除 | 4 | E2 |
| IOS-P-014 | `.syncTime` | `SyncTimeView` | `App/UI/DeviceHomeView.swift:9` | 设备 | 锁钟偏差条 + 校时 | 4 | E2 |
| IOS-P-015 | `.members` | `MembersPage` | `App/UI/MembersPage.swift:30` | 成员 | 头像带 + 名册 + 次要入口 | 5 | E2 |
| IOS-P-016 | `.memberWizard` | `MemberWizardView` | `App/UI/MemberCenterView.swift:478` | 成员 | 三步建档 | 1(+3 case) | E2 |
| IOS-P-017 | `.mergeMembers` | **落到 `MembersPage`**（不是合并页） | `ManagerFace.swift:252` | 成员 | **菜单名"合并成员"，落点是成员列表** | — | E2 |
| IOS-P-018 | `.archivedMembers` | `MemberArchivedView` | `App/UI/MemberCenterView.swift:837` | 成员 | 归档列表 + 恢复 | 1 | E2 |
| IOS-P-019 | `.securityCenter` | `PrivacyDashboard` | `App/UI/SecurityCenterView.swift:1390` | 安全 | 5 项防窥逐项开关 | 2 | E2 |
| IOS-P-020 | `.securityAudit` | `SecurityAuditView` | `App/UI/SecurityCenterView.swift:471` | 安全 | 双流水 + 手动记一条 | 1(+2 Panel) | E2 |
| IOS-P-021 | `.securityDestroy` | `SecurityDestroyView` | `App/UI/SecurityCenterView.swift:881` | 安全 | **三级销毁 + 备份闸 + 按住 2s 清空 + 回收站入口** | 2(+4 Panel) | E2 |
| IOS-P-022 | `.safemode` | `SafemodeIntroView` | `App/UI/SettingsView.swift:12` | 安全 | A/B 模式说明；`mode:"otp"` 变体是 ZOTP 介绍页 | 2 | E2 |
| IOS-P-023 | `.backup` | `BackupPage` | `App/UI/BackupPage.swift:28` | 数据与外观 | 状态/导出/导入/工作室/**页内恢复确认卡** | 5 | E2 |
| IOS-P-024 | `.export` | `ExportCenterView` | `App/UI/ExportCenter.swift:1475` | 数据与外观 | 范围 + 三组动作 + 失败/进度/完成/校验/路径 | **17** | E2 |
| IOS-P-025 | `.appearance` | `AppearancePage` | `App/UI/AppearancePage.swift:18` | 数据与外观 | 主题 4 档 / 品牌色 7 套 / 高对比 / 周起始 | 4 | E2 |
| IOS-P-026 | `.me` | `MePage` | `App/UI/MePage.swift:32` | 数据与外观 | **本机设置：20 条内联 NavigationLink（B 通道）** | 6 | E2 |
| IOS-P-027 | `.diagnostics` | `DiagnosticsPage` | `App/UI/DiagnosticsPage.swift:18` | 数据与外观 | 自检/健康/稳定/操作/BLE/保留/动作 | **10** | E2 |

### 1.4 MePage 的 20 条内联 NavigationLink（B 通道）

**E1/E2** —— 逐条从当前快照解析（`2026-10-22T16:06+08:00`）：

| # | MePage:行 | 行标题 | 目标页 | 目标定义 | A 通道也有？ | 证据 |
|---|---|---|---|---|---|---|
| 1 | `MePage.swift:147` | 本机数据保护 | `SecurityPage` | `App/UI/SecurityPage.swift:28` | ❌ **仅 B** | E2 |
| 2 | `MePage.swift:161` | 隐私与伪装 | `SecurityPeekView` | `App/UI/SecurityCenterView.swift:154` | ❌ **仅 B** | E2 |
| 3 | `MePage.swift:173` | 诊断与自检 | `DiagnosticsPage` | `App/UI/DiagnosticsPage.swift:18` | ✅ 与 A 重复 | E2 |
| 4 | `MePage.swift:196` | 这台锁 | `DevicePage` | `App/UI/DevicePage.swift:30` | ❌ **仅 B** | E2 |
| 5 | `MePage.swift:203` | 设备管理 | `LocksPage` | `App/UI/LocksPage.swift:30` | ✅ 与 A 重复 | E2 |
| 6 | `MePage.swift:211` | 锁档案 | `LockProfilePage` | `App/UI/LockProfilePage.swift:22` | ❌ **仅 B** | E2 |
| 7 | `MePage.swift:218` | 校准门锁时间 | `SyncTimeView` | `App/UI/DeviceHomeView.swift:9` | ✅ 与 A 重复 | E2 |
| 8 | `MePage.swift:224` | 开锁偏好 | `LinkPrefsView` | `App/Core/LinkSenseKit.swift:650` | ❌ **仅 B** | E2 |
| 9 | `MePage.swift:231` | 靠近自动开锁 | `AutoCalView` | `App/Core/AutoOpen.swift:523` | ❌ **仅 B** | E2 |
| 10 | `MePage.swift:240` | 门锁安全模式 | `SafemodeIntroView` | `App/UI/SettingsView.swift:12` | ✅ 与 A 重复 | E2 |
| 11 | `MePage.swift:256` | 备份与恢复 | `BackupPage` | `App/UI/BackupPage.swift:28` | ✅ 与 A 重复 | E2 |
| 12 | `MePage.swift:264` | 导出中心 | `ExportCenterView` | `App/UI/ExportCenter.swift:1475` | ✅ 与 A 重复 | E2 |
| 13 | `MePage.swift:279` | 事件记录 | `EventsPage` | `App/UI/EventsPage.swift:32` | ❌ **仅 B** | E2 |
| 14 | `MePage.swift:286` | 动态消息 | `FeedPage` | `App/UI/FeedPage.swift:21` | ❌ **仅 B** | E2 |
| 15 | `MePage.swift:325` | App 图标 | `IconPicker` | `App/UI/IconPicker.swift:13` | ❌ **仅 B** | E2 |
| 16 | `MePage.swift:329` | 检查固件更新 | `FirmwarePage` | `App/UI/FirmwarePage.swift:23` | ✅ 与 A 重复 | E2 |
| 17 | `MePage.swift:336` | 维护与保养 | `CarePage` | `App/UI/CarePage.swift:27` | ❌ **仅 B** | E2 |
| 18 | `MePage.swift:342` | 关怀提醒 | `CareRemindersView` | `App/UI/CareRemindersView.swift:6` | ❌ **仅 B** | E2 |
| 19 | `MePage.swift:349` | 蓝牙钥匙串 | `DonglesPage` | `App/UI/DonglesPage.swift:22` | ✅ 与 A 重复 | E2 |
| 20 | `MePage.swift:355` | 智能网关 | `GatewayPage` | `App/UI/GatewayPage.swift:21` | ✅ 与 A 重复 | E2 |

> **汇总**：20 条中 **9 条与 A 通道重复**，**11 条是 B 通道独有**。
> A 通道独有 **11 页**：`KeysPage` `AddFingerPage` `TempCodeStudio` `MembersPage` `MemberWizardView` `MemberArchivedView` `PrivacyDashboard` `SecurityAuditView` `SecurityDestroyView` `AppearancePage` `MePage` 自身。
> ⇒ **两条通道合成才是全集，缺一条丢一半功能。**
### 1.5 二层/三层子页

| 编号 | 页面名 | 类型 | 定义位置 | 入口（文件:行 + 通道） | 入口数 | 父页 | 职责 | 分区 | 证据 |
|---|---|---|---|---|---|---|---|---|---|
| IOS-P-028 | `SecurityPage` | 叶子（**仅 B，且两条链指向它**） | `SecurityPage.swift:28` | `MePage.swift:147` / `:156` | 2（同一目标） | MePage | 状态卡 + 风险卡 + 4 动作 | 4 | E2 |
| IOS-P-029 | `AppLockSetupView` | 叶子 | `App/UI/AppLockSetupView.swift:25` | `SecurityPage.swift:256`（actionRow 泛型） | 1 | SecurityPage | 设/改/关应用锁 | 4 | E2 |
| IOS-P-030 | `SecurityPeekView` | 叶子 | `SecurityCenterView.swift:154` | `SecurityPage.swift:261` | 1 | SecurityPage | 8 项防窥明细 + 磨砂演示 | 1 | E2 |
| IOS-P-031 | `CredentialBinView` | 叶子（**唯一入口在销毁页里**） | `App/UI/CredentialBinView.swift:23` | `SecurityCenterView.swift:999` | 1 | SecurityDestroyView | 回收站 + 还原 + 待下发队列 | 6 | E2 |
| IOS-P-032 | `AddKeyPage` | sheet | `AddKeyPage.swift:25` | ①`KeysPage.swift:115` ②`StudioPage.swift:83` | 2 | KeysPage / StudioPage | 密码录入 + 有效期 + 归属 | 6 | E2 |
| IOS-P-033 | `MemberArchivedView` | 叶子 | `MemberCenterView.swift:837` | `MembersPage.swift:169` | 1 | MembersPage | 归档 + 恢复 | 1 | E2 |
| IOS-P-034 | `UnclaimedClaimView` | 叶子 | `MemberCenterView.swift:1087` | `MembersPage.swift:179` | 1 | MembersPage | 未归属记录认领 | 1 | E2 |
| IOS-P-035 | `MemberFamilySettingsView` | 叶子 | `MemberCenterView.swift:956` | `MembersPage.swift:189` | 1 | MembersPage | 长辈模式 / 隐私浏览 | 1 | E2 |
| IOS-P-036 | `MemberWizardView` | **sheet** | `MemberCenterView.swift:478` | `MembersPage.swift:74` | 1 | MembersPage | 三步建档（与 A 的 .memberWizard 同页） | 1 | E2 |
| IOS-P-037 | `MergeMembersView` | sheet | `MemberCenterView.swift:678` | `MemberCenterView.swift:86` | 1 | MemberDetail360View | 成员合并（**ManagerFace 的"合并成员"不走这里**） | 1 | E2 |
| IOS-P-038 | `MemberExitWizard` | sheet | `MemberCenterView.swift:1353` | `MemberCenterView.swift:87` | 1 | MemberDetail360View | 退出处置向导 | 1 | E2 |
| IOS-P-039 | `StatsPage` | 叶子 | `StatsPage.swift:31`（WT 含 chipRow） | `EventsPage.swift:135` toolbar | 1 | EventsPage | 统计 8 卡 | 8 | E2 |
| IOS-P-040 | `AlarmsPage` | 叶子 | `AlarmsPage.swift:27` | `EventsPage.swift:141` toolbar | 1 | EventsPage | 告警分级 + 处置 | 4 | E2 |
| IOS-P-041 | `FeedPage` | 叶子 | `FeedPage.swift:21` | `MePage.swift:286` | 1 | MePage | 动态卡片流 | 4 | E2 |
| IOS-P-042 | `DevicePage` | 叶子 | `DevicePage.swift:30` | `MePage.swift:191` | 1 | MePage | 身份/待办/容量/指标/明细/最近 | 9 | E2 |
| IOS-P-043 | `LockProfilePage` | 叶子 | `App/UI/LockProfilePage.swift:22` | `MePage.swift:206` | 1 | MePage | 锁牌 + 符号 + 色标 | 6 | E2 |
| IOS-P-044 | `IconPicker` | 叶子 | `App/UI/IconPicker.swift:13` | `MePage.swift:320` | 1 | MePage | 9 款 App 图标 | 1 | E2 |
| IOS-P-045 | `CarePage` | 叶子 | `CarePage.swift:27` | `MePage.swift:331` | 1 | MePage | 周期卡 + 待办 + 历史入口 | 4 | E2 |
| IOS-P-046 | `CareRemindersView` | 叶子 | `CareRemindersView.swift:6` | `MePage.swift:337` | 1 | MePage | 公告板 + 纪念日 + 生日 | 3 | E2 |
| IOS-P-047 | `MaintenanceView` | **sheet** | `App/UI/CareViews.swift:9` | `CarePage.swift:250`（"保养历史"） | 1 | CarePage | 周期/历史/换电/电子钥匙 | 4 | E2 |
| IOS-P-048 | `CareChecklistView` | sheet | `CareViews.swift:470` | `CareViews.swift:65` | 1 | MaintenanceView | 保养勾选台账 | 2 | E2 |
| IOS-P-049 | `BatterySwapGuideView` | 叶子 | `CareViews.swift:313` | ①`CareViews.swift:226` ②`AlarmCenterView.swift:639` | 2（1 死） | MaintenanceView / **AlarmCenterView（不可达）** | 换电引导 | 1 | E2 |
| IOS-P-050 | `BackupStudioView` | **sheet** | `App/UI/BackupStudio.swift:10` | ①`BackupPage.swift:106` ②`BackupView.swift:63`（**BackupView 不可达**） | 2（实际 1） | BackupPage | 信任头/新鲜度/动作卡/节奏卡 | 5 | E2 |
| IOS-P-051 | `ExportWizardView` | sheet | `BackupStudio.swift:458` | `BackupStudio.swift:33` | 1 | BackupStudioView | 4 步导出向导（含 `XStepBar`） | 4 | E2 |
| IOS-P-052 | `RestoreWizardView` | sheet | `BackupStudio.swift:918` | `BackupStudio.swift:34` | 1 | BackupStudioView | 8 段恢复 + 冲突处置 | 8 | E2 |
| IOS-P-053 | `ShareToAndroidView` | sheet | `ShareToAndroidView.swift:8`（WT） | `LocksPage.swift:135` | 1 | LocksPage | 开锁二维码 + **白底静区** | 1 | E2 |
| IOS-P-054 | `CodeScanSheet` | sheet | `CredentialStudio.swift:447`（WT） | `CredentialStudio.swift:545` | 1 | TempCodeStudio | 相机取号 | 1 | E2 |
| IOS-P-055 | `ReportScanSheet` | sheet | `App/UI/ReportVerifyView.swift:21` | `ExportCenter.swift:1535` | 1 | ExportCenterView | 扫码核对报告 | 1 | E2 |
| IOS-P-056 | `QLPreviewView` | **fullScreenCover** | `ExportCenter.swift:2450` | `ExportCenter.swift:1532` | 1 | ExportCenterView | 文件预览（UIKit 包） | 1 | E2 |
| IOS-P-057 | `FpStudio` | sheet | `CredentialStudio.swift:1054`（WT） | `StudioPage.swift:89` | 1 | **StudioPage（不可达）** | 指纹沉浸录入 | 2 | E2 |
| IOS-P-058 | `OtpStudio` | sheet | `CredentialStudio.swift:1469`（WT） | `StudioPage.swift:92` | 1 | **StudioPage（不可达）** | ZOTP/TOTP/静态码 | 8 | E2 |
| IOS-P-059 | `StudioPage` | 叶子（**不可达**） | `App/UI/StudioPage.swift:24` | `QuickPool.swift:149`（零调用） | **0** | — | 钥匙工坊 4 卡 | 1 | E2/E1 |
| IOS-P-060 | `AlarmCenterView` | 叶子（**不可达**） | `AlarmCenterView.swift:12` | `QuickPool.swift:151`（零调用） | **0** | — | 告警流 + 分时 + 处置 | **13** | E2/E1 |
| IOS-P-061 | `BackupView` | 叶子（**不可达**） | `App/UI/BackupView.swift:7` | `QuickPool.swift:150`（零调用） | **0** | — | 备份/导入/工作室（embedded） | 4 | E2/E1 |
| IOS-P-062 | `XLockBlade` | 组件（**零构造点**） | `App/UI/XLockBlade.swift:26` | **无** | **0** | — | 60×300mm 锁体 RealityKit 视图 | 1 | E2/E1 |

### 1.6 §1 的四个硬结论

1. **登记 62 页，用户真能走到 59 页**。不可达 3 页：`StudioPage`(P-059) / `AlarmCenterView`(P-060) / `BackupView`(P-061)；`XLockBlade`(P-062) 连构造点都没有（E1：`node tools/reach.js` 报「不可达 1：XLockBlade」）。
2. 不可达的根因是**一条死函数** `QuickPool.quickDestination(_:)`（`App/Core/QuickPool.swift:143`）**零调用**；而 `AlarmCenterView.swift:34`、`BackupView.swift:28` 的注释还在说"由 quickDestination push"—— 注释与代码已脱节。
3. `MaintenanceView` 有 2 入口但只有 `CarePage:250` 能点到；`BackupStudioView` 的 `BackupView:63` 同理。
4. **`SecurityPage` 是全仓唯一"由 B 通道独占、且 B 内两条链指向同一页"的页面**（P-028）。

### 1.7 私有 `var` 承载的全屏内容（不是 struct，但确实是"一屏"）

| 名称 | 定义 | 呈现 | 承载 | 证据 |
|---|---|---|---|---|
| `BackupPage.importSheet` | `BackupPage.swift:343`（HEAD） | `BackupPage.swift:69` sheet | 粘贴备份文本整屏表单 | E2 |
| `OtpStudio.importSheet` | `CredentialStudio.swift:1701`（HEAD） | `CredentialStudio.swift:1515` sheet | OTP 批量导入 | E2 |
| `BackupPage.restoreConfirmCard` | `BackupPage.swift:266` | **页内卡片** | 恢复前确认（故意的：两层连续模态会丢第二层，`:262-265` 注释自陈） | E2 |
| `BackupStudioView.actionCards` | `BackupStudio.swift:126` | compose | 4 张入口卡 | E2 |

---

## §2 分区清单（**根屏 + 前 12 个叶子**，其余分区数见 §1）

### 违反代号表（先看这张，再对每页条目）

| 代号 | 违反的规范条款 | 判据（可机检） |
|---|---|---|
| **V1** | §0 总则二「卡片/列表/内容容器**永远不许**用玻璃」 | 内容卡底出现 `.axGlass(` / `glassEffect(` / `.ultraThinMaterial` |
| **V2** | §6.3「应用体卡片**零投影**」 | 卡片容器上有 `.shadow(`（E1 现值 **5 处 / 3 文件**，已从 14 处降下来） |
| **V3** | §5.2「`rCard` = 24」、§14「卡片圆角 <20pt 即返工」 | `cornerRadius` 令牌 < 20 且用于卡片 |
| **V4** | §4.2 字阶下限 11pt / §10 图标尺寸表 | `.system(size: 8/9/10)` |
| **V5** | §0 总则三「一屏只有一个主角」+ §7.4 HeroCard 版式 | 同屏 ≥2 个 ≥200pt 环 / ≥2 张渐变卡 / 渐变卡不是 HeroCard 版式 |
| **V6** | §7.2 自检「**值必须是白的、标签必须是灰的**」 | 标签用 `text`、值用 `textSub` |
| **V7** | §7.7「视觉行高 20pt ≠ 触摸区 44pt」 | 把 44 写成视觉行高 |
| **V8** | §5.4「整页只有**一条**文字对齐线 = 29pt」 | 大标题边距 ≠ 卡片内文字边距 |
| **V9** | §11.2「禁止超过 1.2s / 禁止渐变循环流动」 | `repeatForever` 无限循环 |
| **V10** | §3.1「`surface` = #1C1C1E」+ §7.2/7.6 层级 | 用 `surfaceAlt`（卡内次级）当卡片/瓦片主底 |

> **E1 全仓机检（HEAD，注释已剥离）**：`XPanel` **179** 处（38 文件）· `.shadow(` **14** 处（11 文件）· 渐变 **14** 处（8 文件）· `.ultraThinMaterial` 或 `.glassEffect(` **4** 处（2 文件）· `axGlass*` **7** 处（5 文件）· `system(size:8/9/10)` **4** 处 · `Divider()` **15** 处（10 文件）· `ScrollView` **66** 处（40 文件）· `List` 花括号 **1** 处。

### 2.1 IOS-P-002 `HomeConsole`（门厅，9 分区）— `HomeConsole.swift:53`（WT）

| # | 分区名 | 代码行（WT） | 承载 | 现状容器 | 符合？ | 具体违反 |
|---|---|---|---|---|---|---|
| 1 | `masthead` | `:228` | 时间（TimelineView 30s）+ 连接态圆点 | 裸 `HStack`，无容器 | 黑画布上不占视觉 | `frame(height:20)` 写死，Dynamic Type 放大后被裁（E2） |
| 2 | `noLockState` | `:258` | 未配对时唯一出口 | 裸 `VStack` + 自绘 `xPlate(accent,.capsule)` 按钮 | ⚠ **自绘主按钮** | §7.17 要求「图标 28 + 标题 14SB + 说明 12」；此处 **44pt 图标 + title3 标题 + footnote 说明**（E2）。绕过 `XPrimaryButtonStyle` |
| 3 | `identity` | `:295` | 锁名 + 一句摘要 | 裸 `VStack` | ✅ | 锁名用 `.title`（28pt），**§4.2 字阶里没有 28**（display 36 / largeTitle 30 / title2 19）（E2） |
| 4 | `noticeRow` | `:355` | 告警/低电/到期 三选一 | `xPlate(tone 0.12, .control, edge:)` | ✅ 语义洗底合规 | 三种提示**互斥**（`criticalNotice` 是 `if` 级联，`:333`）→ 告警+低电同存时低电被吞（IOS-M-02） |
| 5 | `unlockStage` | `:415` | **220pt 环形主控** | `ZStack` + Circle().trim + AngularGradient + shadow | ✅ 主角合规（220 ≥ 200） | **V2**：`:449` 环上 `.shadow(..., radius: 16)` —— §7.8「环不得有投影，只用辉光」。渐变 ✓（`AngularGradient` `:422`） |
| 6 | `metricsRow` | `:588` | 今日开门/成员/最早开门 | 裸 `HStack` + 1×34pt Rectangle 分隔 | ✅ | **V6 反向合规**（值白、标签灰 ✓）；但 `metric()` 的 `spacing: 6` 与 §7.7「标签→值 2pt」不符（E2） |
| 7 | `todaySection` + `dayChart` | `:633` / `:640` | 24 根分时柱（整块 `SpatialTapGesture`，46pt 高）+ 5 轴标签 | 裸 `VStack` + `GeometryReader` | ⚠ | §7.9 要求「柱状图 = 1px 发丝线阵列，约 30 根，间距 5pt，**无圆角、无渐变**」；此处是 **3pt 间距的 capsule 圆角柱**（`:670` 附近）→ **两种图形语言** |
| 8 | `memberSection` 胶囊行 | `:709` | 横向成员胶囊（头像 28 + 名 + 次数） | `xPlate(surface,.capsule)` | ✅ | **触达不足**：`frame(28×28)`（`:736`）+ `padding(.vertical,5)`（`:747`）= **38pt < 44**（IOS-M-10） |
| 9 | `manageSection` 5 格 | `:772` | 5 个管理瓦片 | `LazyVGrid` 5 列 + `xPlate(surface, XRadius.tile)` | ✅ | 每格宽 (393−28−4×8)/5 = **65pt**，高 62；375pt 机型退化到 60pt（E2）。**IOS-G-03 的根** |

> **一屏主角检查**：✅ 只有 1 个 ≥200pt 环（220pt），其余最大 62pt 瓦片 —— 符合 §9 权重唯一。

### 2.2 IOS-P-003 `ManagerFace`（3 分区）— `ManagerFace.swift:27`（WT）

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 具体违反 |
|---|---|---|---|---|---|---|
| 1 | `groupHeader` | `:97` | 组名（`largeTitle` 30B + `tracking(-0.4)`）+ 动态摘要 | 裸 `VStack` | ✅ **全仓唯一按 §7.1 做的标题** | V8：`.padding(.leading, XSpace.align - XSpace.gutter)`（`:110`）公式对，但 `align = gutter + card − 1` 硬编码 −1（IOS-S-02） |
| 2 | `groupContent` → `rows()` | `:115` / `:163` | **一行一张 `XPanel`** | `XPanel(.group){ XRow }` × N，spacing 8 | ✅ 深卡 / 零投影 / r24 | **IOS-G-04**：21 行 = 21 张卡。devices 组 5 张 ≈ 5×(24+44+8)−8 = **372pt**；一卡五行只需 24+5×44 = **244pt** → 高 52% |
| 3 | `groupBar` 玻璃分组条 | `:187` | 5 项图标+标签 | `XGlassTabBar`（WT 新增，`Components.swift:1598`） | ⚠ 玻璃在功能层 ✓，但 **5 项 vs §7.10「3–4 项」** | 偏离已自陈（`docs/GLASS/DEVIATIONS.md` §2，E3）。**推翻条件已踩线**：DEVIATIONS 自陈「标签超过 4 字会挤」，最长项「数据与外观」是 **5 字**（`:290`） |

### 2.3 IOS-P-007 `KeysPage`（8 分区）— `KeysPage.swift:31`（WT）

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 具体违反 |
|---|---|---|---|---|---|---|
| 1 | `expiringCard` | `:124` | 到期预警（最多 3 条） | `XPanel(tone: .warn)` | ✅ | 无 |
| 2 | `segmentBar` 4 段筛选 | `:155` | 全部/密码/指纹/临时码 + 计数 | **`axGlassCapsule()`** | ❌ **V1** | §7.3 形态 B 要求容器 rgba(255,255,255,0.06) **实色**、选中块 0.18；此处是**玻璃**（IOS-C-01 第 1 种分段控件） |
| 3 | `credentialCard` | `:210` | 凭证行 × N | `XPanel(.group, padding: 0)` | ✅ | 行内 `XHairline` 缩进写死 `XSpace.card + 28 + XSpace.m`（`:226` 附近）—— 图标尺寸一变就断 |
| 4 | `keyRow` | `:458` | 种类图标 + 名 + 归属 + 状态胶囊 | 裸 `HStack` + `XStatusPill` | ✅ | `contextMenu` 承载 置顶/归档/停用/编辑 —— **没有详情页**（`KeysPage.swift:488-493` HEAD 注释自陈） |
| 5 | `emptyCard` | `:300` | 空态 | `XPanel` + `XEmptyState` | ✅ §7.17 结构对 | 字号偏大（IOS-M-05） |
| 6 | 删除确认 | `:91`（HEAD） | `confirmationDialog` 三句话 | 系统 | ✅ | **全仓最好的确认文案**（删本机 + 撤锁端 + 可回收），见 §6 |
| 7 | `.searchable` | `:73`（HEAD） | 搜索 | 系统 | ✅ | 无 |
| 8 | toolbar 2 按钮 | `:74-90`（HEAD） | 成员 + 添加 | 系统 | ⚠ | "成员"按钮 `NavigationLink{ MembersPage() }`（`:76`）= **第三条到 MembersPage 的路** |

### 2.4 IOS-P-010 `LocksPage`（1 分区 + 2 Section）— `LocksPage.swift:30`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 具体违反 |
|---|---|---|---|---|---|---|
| 1 | body → **List** | `:43`（HEAD） | 空态 / 锁列表 / 已隐藏 三 Section | **`List(.insetGrouped)`** | ❌ **全仓唯一 List** | 40 个文件用 `ScrollView`（66 处），只有这一页用 List（IOS-S-06）。系统分组底 + **圆角 ≈10pt（§5.2 要 24）** |
| 2 | `.listStyle(.insetGrouped)` + `.scrollContentBackground(.hidden)` | `:118-119`（HEAD） | 试图隐藏系统底 | 系统 | ⚠ 半修 | `.hidden` 只隐藏**整表背景**，不隐藏**行背景**（行要 `.listRowBackground`）。只有空态行用了（`:53`） |
| 3 | `lockRow` | `:164` | 锁图标 + 名 + 当前胶囊 + 电量/锁态右簇 | 裸 `HStack`（在 List row 内） | ⚠ | §7.7 要求「色点 8pt + 名称 14 + 值 14SB」；此处是**自定义三段右簇**、无色点 —— **规范外自造** |
| 4 | 左滑 = `.onDelete` | `:67-73`（HEAD） | **隐藏**（`LockArchive.setHidden`） | 系统 swipe | ❌ **语义错** | 手势叫"删除"、实际是"隐藏"、**且无确认**；而"解除绑定"（真删）有确认（`:142`）→ 同页两种破坏性动作门槛不同（IOS-M-01） |

### 2.5 IOS-P-015 `MembersPage`（5 分区）— `MembersPage.swift:30`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `avatarStrip` | `:87` | 横向大头像带（64pt 圆 + 名 + 角色） | 裸 `ScrollView(.horizontal)` | ✅ "先认脸"符合 §1.4 | 96pt 高；横向区**又加 gutter**（`:123`）→ 两侧 28pt，与页边距 14 不一致（V8） |
| 2 | `rosterCard` | `:127` | 名册（头像 44 + 名 + 次数） | `XPanel(.group, padding: 0)` | ✅ | `Divider().overlay(hairline).padding(.leading, XSpace.card + 40 + XSpace.m)`（`:150`）= **68pt 缩进写死** |
| 3 | `secondaryCard` | `:166` | 归档/匿名认领/家庭设置 | 同上 | ✅ | 三条都是 `XRow` + 手写 padding（`:174-175` 等）—— **`XRow` 有 `action` 参数却不用**，外层 padding 破坏 `XRow` 自己的 `minHeight 44` |
| 4 | `emptyCard` | `:203` | 空态 | `XPanel` + `XEmptyState` | ✅ | 字号偏大 |
| 5 | toolbar person.badge.plus | `:61` | 添加成员 | 系统 | ✅ | 无 |

### 2.6 IOS-P-028 `SecurityPage`（4 分区）— `SecurityPage.swift:28`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `statusCard` | `:62`（WT） | 总状态 + **三盏灯** | `XPanel(kind: .hero)` | ⚠ **V5** | WT 的 hero 已改成 `fill(XGradient.hero)`（`Components.swift:124` WT）= 渐变卡。本页只有这一张 ✓；但 §7.4 要求 HeroCard「高 220 / 标题顶 / 媒体中 / 说明底」，此处是**三盏灯横排** → **规格外自造** |
| 2 | `riskCard` | `:177` | 风险清单 | `XPanel(.group)` | ✅ | 条件渲染（`:43` HEAD）→ 全绿时整卡消失，**"没有风险"无法被确认**（§7.20.4 的反面） |
| 3 | `actionsCard` | `:249` | 应用锁/防窥/审计/销毁 4 条 | `XPanel(.group, padding: 0)` + 自带 `XHairline` | ✅ | `actionRow`（`:279`）**是手搓行，不是 `XRow`** —— 与"行形状只从 XRow 一处来"（`Components.swift:394` HEAD 注释）矛盾 |
| 4 | 三盏灯 `lamp()` | `:136`（HEAD） | 钥匙/审计链/数据 | 裸 `HStack` | ✅ | 圆点 + 文字，符合 §13.3「不靠颜色单独表意」 |

### 2.7 IOS-P-019 `PrivacyDashboard`（2 分区）— `SecurityCenterView.swift:1390`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | 状态摘要 | `:1408`（HEAD） | 三态摘要（0 项 / 部分 / 全开） | `XPanel(.group)` | ✅ **全仓写得最好的一张状态卡**（§7.20 正例） | 无 |
| 2 | 逐项状态（5 项） | `:1428` | 5 行，点按即切换 | `XPanel(.group, padding: 0)` | ⚠ | **无 `XToggle`**：`onTapGesture` + `accessibilityAction`（`:1455` / `:1460`）自绘开关。视觉上只有 `checkmark.circle.fill` vs `circle`（`:1433`）→ 视力用户不知道能点（IOS-M-04） |

### 2.8 IOS-P-023 `BackupPage`（5 分区）— `BackupPage.swift:28`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `statusCard` | `:120` | 上次备份 / 新鲜度 | `XPanel(kind: .hero, tone: backupTone)` | ⚠ V5 | 渐变 hero + tone 洗底**同时**上（tone 只在描边生效）→ 两个层级信号叠一张卡 |
| 2 | `exportCard` | `:178` | 导出（文件 / 粘贴） | `XPanel(.group)` | ✅ | 无 |
| 3 | `restoreConfirmCard` | `:266` | **页内**恢复确认（3 句后果 + 2 按钮） | `XPanel(.group, tone: .warn)` | ✅ **正确处置** | 无（`:262-265` 注释解释了为什么不用弹窗） |
| 4 | `importCard` | `:311` | 从文件导入 / 粘贴 | `XPanel(.group, tone: .warn)` | ⚠ | 语义色滥用（IOS-M-03）：**两张 warn 卡同屏** |
| 5 | `studioRow` | `:479` | 进工作室 | `XRow` in `XPanel` | ✅ | 全仓 `XRow` 只有 26 处，本页 1 处 |

### 2.9 IOS-P-024 `ExportCenterView`（**17 分区**）— `ExportCenter.swift:1475`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `scopeCard` | `:1549` | 范围 + 列 + 脱敏，**三张 Panel 叠一个 VStack** | `VStack{ XPanel×3 }` | ⚠ V10 | 三张卡间距 `XSpace.m`=12，卡间距应为 8（§5.1）；三张同属"导出范围"，拆三张反而增加噪音 |
| 2 | `fileActionsCard` | `:1561` | CSV / JSON / PDF / 邮件 | `XPanel(.group)` | ✅ | 4 个 `actionButton`（`:1647`）是手搓行，非 `XRow` |
| 3 | `imageActionsCard` | `:1594` | 长图 / 告警卡 / 事实单页 / **加密 zip** | `XPanel(.group)` | ⚠ | 加密口令 `SecureField` 裸放卡里（`:1615`），无标签、无强度提示 |
| 4 | `printActionsCard` | `:1637` | 打印 3 种 | `XPanel(.group)` | ✅ | 无 |
| 5 | `progressSection` | `:1882` | 条件渲染 | `XPanel` | ✅ | 无 |
| 6 | `failedCard` | `:1687` | 失败清单 | `XPanel` | ✅ | 无 |
| 7 | `doneSection` | `:1904` | 完成卡（含 ShareLink） | `XPanel` | ✅ | 无 |
| 8 | `verifySection` | `:1995` | 校验二维码 | `XPanel` | ✅ | 无 |
| 9 | `pathSection` | `:2089` | 上次导出路径 | `XPanel` | ✅ | 无 |

> **核心问题不是分区，是规模**：973 行、**17 分区同屏串一个 ScrollView**、16 处 `XPanel`（全仓最多之一）。
> §0 总则三「一屏只有一个主角」**无解 —— 没有任何一块是主角**（IOS-S-05）。

### 2.10 IOS-P-005 `EventsPage`（9 分区）— `EventsPage.swift:32`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `hourFilterBar` | `:671` | 小时筛选条 | 裸 `HStack` | ✅ | 无 |
| 2 | `savedChips` | `:283` | 命名筛选 + 最近搜索 | 裸横向 `HStack` | ✅ | 无 |
| 3 | `eventList` | `:449` | **真时间轴**（竖线由每组 overlay 画通长） | 裸 `ScrollView` + `LazyVStack` | ✅ **全仓唯一的时间轴语言** | 时间轴里没有 `XPanel` —— 最接近 §8 模板 D「行直接铺在面板上」，但用**黑画布**不是主题色面板。**规范没有"时间轴"模板** |
| 4 | `daySection` / `dayHeader` | `:468` / `:495` | 日期分组头 | 裸 `VStack` | ✅ | 无 |
| 5 | `timelineRow` | `:574` | 单条记录 | 裸 `HStack` + 节点 | ⚠ **V4** | `:505`（HEAD）`.font(.system(size: 8, weight: .semibold))` —— **8pt 图标**；§4.2 下限 11、§10 尺寸表无 8 → 两项规范同时违反（IOS-M-08） |
| 6 | `emptyState` | `:698` | 空态 | `XEmptyState` | ✅ | 字号偏大 |
| 7 | `XSkeleton` | `:89` | 首屏骨架 | `XSkeleton(blocks:3, blockHeight:84)` | ✅ §7.20.1 | 无 |
| 8 | 同步中顶部条 | `:113` | overlay 胶囊 + ProgressView | 裸 `HStack` + `xPlate(surface,.capsule)` + hairline | ✅ 非阻塞，符合 §7.20.2 | 无 |
| 9 | toolbar 2 图标 | `:135` / `:141` | 统计 / 告警 | 系统 | ⚠ | **`StatsPage` 与 `AlarmsPage` 的唯一入口是两个图标**（IOS-A-06） |

### 2.11 IOS-P-011 `FirmwarePage`（**10 分区**）— `FirmwarePage.swift:23`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `versionCard` | `:119` | 当前版 vs 包版 | `XPanel(kind: .hero)` | ⚠ V5 | 渐变 hero；本页同时有 `upgradeStage` 的 **180pt 环** → **一屏两个主角候选**。§9「大环 ≥200，其余 ≤130」→ **180 落在未定义区间** |
| 2 | `packageCard` | `:164` | 固件包信息 | `XPanel` | ✅ | 无 |
| 3 | `checklistCard` | `:189` | 体检单（5 项） | `XPanel` + `checkRow` | ✅ | `checkRow` 是手搓行 |
| 4 | `actionCard` | `:252` | 选包 / 升级 / 批量 | `XPanel` | ✅ | 无 |
| 5 | `upgradeStage` | `:304` | **180pt 进度环 + 三节点** | `ZStack` + Circle().trim + AngularGradient | ⚠ | 环 180pt 不在 §9 权重表；AngularGradient 从 `accent.opacity(0.6)` → `accent`（`:316-317`）→ **渐变 ✓** 符合 §7.8 通用自检 |
| 6 | `failedStage` | `:410` | 失败 + 重试 | `XPanel` | ✅ | 无 |
| 7 | `queueCard` | `:439` | 批量队列 | `XPanel` | ✅ | 无 |
| 8 | `historyCard` | `:473` | 历史 | `XPanel` | ✅ | 无 |
| 9 | 2 个 `confirmationDialog` | `:101` / `:107` | 升级确认 / 批量确认 | 系统 | ✅ | **文案写清了后果**（"中断可能导致门锁需要重新配网"）→ §6 要保住 |
| 10 | `fileImporter` | `:98` | 选 zip | 系统 | ✅ | `[.zip, .data]` |

### 2.12 IOS-P-042 `DevicePage`（9 分区）— `DevicePage.swift:30`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `identityCard` | `:64` | 身份 + 连接胶囊 + `XBatteryGauge` | `XPanel(kind: .hero)` | ✅ **全仓最接近规范的一张 hero** | 无（`XBatteryGauge` 132pt 在卡内，符合 §7.6「右侧槽环 84 或更大」） |
| 2 | `attentionCard` | `:174` | 需要你处理的 | `XPanel` | ✅ | 无 |
| 3 | `capacityCard` | `:243` | 容量 3 行 | `XPanel` + `capacityRow` | ✅ | 无 |
| 4 | `metricsRow` | `:308` | **3 个 `XMetricTile`** | 裸 `HStack` | ❌ **V10** | `XMetricTile` 底是 `surfaceAlt`（`Components.swift:210` HEAD）→ 三项比周围卡片**暗一档**，读作"不可用"而非"读数"（IOS-M-07） |
| 5 | `detailSection` | `:380` | 折叠明细 | `XPanel` + `detailRow` | ✅ | 无 |
| 6 | `recentSection` | `:457` | 最近开门 | `XPanel` | ✅ | 无 |
| 7 | `.refreshable` | `:57` | 下拉刷新 | 系统 | ✅ | 无 |
| 8 | `secLabel` | `:139` | 卡内小标签 | Text + `.caption` uppercase | ⚠ | **全仓 21 个同名 `secLabel`/`sectionLabel`/`header` 副本**（IOS-C-03） |

### 2.13 IOS-P-012 `GatewayPage`（6 分区）— `GatewayPage.swift:21`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `stepOneCard` | `:66` | 第一步重置（96pt 光塔图标） | `XPanel(kind: .hero)` | ⚠ V5 | 渐变 hero + 96pt Circle 底 → 卡内已大面积图形，与"hero 是渐变主视觉"冲突 |
| 2 | `stepTwoCard` | `:108` | 第二步配 WiFi | `XPanel` | ✅ | 无 |
| 3 | `progressCard` | `:169` | 步骤进度 | `XPanel` | ✅ | 无 |
| 4 | `gatewayCard` | `:227` | 网关卡 | `XPanel` + `timestampRow` | ✅ | 3 处 `Divider()`（`:89` / `:262` 附近）→ 与 `XHairline` 混用（IOS-C-02） |
| 5 | `emptyState` | `:340` | 空态 | `XPanel` + **自绘** | ⚠ | 不是 `XEmptyState`（IOS-C-08） |
| 6 | 3 个 `confirmDestructive` | `:366` / `:376` / `:385` | 删 / 写 / 重启 | `UIAlertController` | ✅ | 配网进行中**没有** `interactiveDismissDisabled` → 已知缺口（IOS-R-08） |

### 2.14 IOS-P-026 `MePage`（6 分区，B 通道宿主）— `MePage.swift:32`

| # | 分区 | 代码行 | 承载 | 容器 | 符合？ | 违反 |
|---|---|---|---|---|---|---|
| 1 | `statusSummary` | `:72` | 4 个 `summaryTile` | `XPanel` + 4 个自绘瓦片 | ⚠ V10 | `summaryTile`（`:114`）底 = `surfaceAlt.opacity(0.6)` → **卡中卡用次级底又压 0.6**，明度落到 `surfaceSunken` 那一档（§3.1），语义漂移（IOS-M-06） |
| 2 | `protectionSection` | `:145` | 3 条（数据保护 `:147` / 隐私伪装 `:161` / 诊断 `:173`） | `XPanel` + 手搓 `XRow` 包 NavigationLink | ✅ **本轮已修**（§0.4） | 修完仍留一个语义问题：「隐私与伪装」落在 `SecurityPeekView`（8 项完整设置页），而 A 通道同一功能在 `PrivacyDashboard`（5 行点按）→ **两套 UI 同一件事**（IOS-C-11） |
| 3 | `lockSection` | `:188` | **7 条** | `XPanel` + 7×NavigationLink | ⚠ | 7 条里 **5 条 A 通道没有**；7 行 = **7×44 = 308pt**，一屏装不下（IOS-G-02） |
| 4 | `dataSection` | `:254` | 4 条（备份 `:256` / 导出 `:264` / 事件 `:279` / 动态 `:286`） | `XPanel` | ⚠ | `EventsPage` 与 `FeedPage` **职责重叠**（注释自陈"两个都在"）→ IOS-G-05 |
| 5 | `aboutSection` | `:323` | 6 条（图标 `:325` / 固件 `:329` / 维护 `:336` / 关怀 `:342` / 钥匙串 `:349` / 网关 `:355`） | `XPanel` | ❌ **分组错** | 这组叫"关于与偏好"，装的却是**固件升级 / 蓝牙钥匙串 / 智能网关**三个设备功能 → IOS-G-01 |
| 6 | `caption()` | `:291` | 卡底说明 | Text + `.caption2` | ⚠ V4 边缘 | 11pt 在下限上 ✓；但 §4.2 说 `caption2`「**仅非关键信息**」，此处承载"这一组动的是本机数据与访问权限"这类**安全提示**（`:173`）→ 应升 `footnote` |

---

## §3 控件级清点（每族：次数 / 代表位置 / 现状规格 / 规范 §7 对应 / 差距）

> **E1 口径**：以下计数对 **HEAD（`803b6c8`）** 全 109 个 `.swift` 做的，剥离行尾注释后正则计数。WT 正在改，数字有 ±5% 漂移；但**族的有无**不会变。

### 3.1 按钮（**8 种样式并存** —— 控件层最大的问题）

| 样式 | 次数 | 文件数 | 代表位置 | 规范 §7 对应 | 差距 |
|---|---|---|---|---|---|
| `.buttonStyle(.plain)` | **60** | 24 | `ManagerFace.swift:175`(HEAD) / `MembersPage.swift:118` | **无对应** | 60 处裸 `.plain` = **无按压反馈**。§11.1「按压缩放 1→0.97，0.12s」在这 60 个可点元素上**全部缺失** |
| `XSecondaryButtonStyle` | **28** | 10 | `BackupPage.swift:297` `:329` `:338` | §7.0.6 主按钮（白底黑字 r999） | 本仓是**描边式**（`Components.swift:295`）；规范主按钮是**实底白底黑字**。形态完全不同 |
| `XPrimaryButtonStyle` | **17** | 11 | `BackupPage.swift:305` | §7.0.6 | 本仓是**铜色实底 + r12**（`Components.swift:263`）；规范是**胶囊 r999**。圆角差一个数量级 |
| `.buttonStyle(.bordered)` | **10** | 1 | `CredentialStudio.swift:415`(HEAD) | 无对应 | 系统 bordered 自带系统 tint 与内边距，**10 处集中在同一文件**（口述卡） |
| `PressableButtonStyle()` | **6** | 4 | `LockKeeperApp.swift:1184`(HEAD) | §11.1 按压缩放 | ✅ **最接近规范的一档**（300ms 防连点 + 0.96 缩放 + 阴影），却只用 6 次 |
| `.buttonStyle(PlainButtonStyle())` | **5** | 2 | `MemberCenterView.swift:583` `:586` | 无 | 与 `.plain` 同义却写法不同 —— **同一语义两种写法** |
| `PressableScaleStyle()` | **3** | 1 | `HomeConsole.swift:759`(WT) | §11.1 | 0.96 + `easeOut 0.12` ✅ 合规，但**定义在页面文件里**（`HomeConsole.swift:1061` HEAD） |
| `XDestructiveButtonStyle` | **2** | 2 | 需 grep | §7.20.3 次要按钮 | 只有 2 处 —— 而全仓 **14 处 `.shadow(`、9 处 `confirmationDialog`、11 处 `confirmDestructive`**，破坏性动作几乎**都不用它** |
| `StudioCardStyle` | 1 | 1 | `StudioPage.swift` | 无 | 单文件私有样式 |

**§3.1 结论（可勾）**：
- [ ] 60 处 `.plain` 需统一到 1 个带按压反馈的样式（`PressableButtonStyle` 是现成的）
- [ ] `XPrimaryButtonStyle` 的 **r12 → r999** 是规范硬差；`XSecondaryButtonStyle` 的描边形态规范里没有
- [ ] 8 种 → 规范只承认「主 / 次 / 破坏」三种。**需砍掉 5 种**

### 3.2 行 / 列表基元

| 族 | 次数 | 文件数 | 代表位置 | 规范 §7 | 差距 |
|---|---|---|---|---|---|
| `XRow` | **26** | **5** | `MePage.swift` **20** 处、`MembersPage` 3、`BackupPage` 1、`CarePage` 1、`ManagerFace` 1 | §7.7 MetricRow / §7.11 SectionHeaderLink | **26 处 vs 179 处 XPanel** → 卡片用得极多、标准行用得极少。**大多数页面在自己手搓行** |
| `XHairline` | **23** | 10 | `AppearancePage.swift:72` `:145` `:152` | §3.1 separator 0.5pt | `1/UIScreen.main.scale`（`Components.swift:142` HEAD），@3x 上是 0.33pt ✓；但**规格写的是 0.5pt 固定** |
| `Divider()` | **15** | 10 | `SecurityPage.swift:78`、`GatewayPage.swift:89`、`KeysPage.swift:219` | §3.1 | **与 `XHairline` 并存两套分隔线**。15 处统一写成 `Divider().overlay(XPalette.hairline)` —— 作者知道要用令牌，但**没必要绕道系统控件** |
| **手搓 `secLabel`/`sectionLabel`/`header`** | **21 个定义** | 16 文件 | `SecurityCenterView` **4 个**、`MemberCenterView` **5 个**、`CareViews` **3 个** | §7.11 | **同一个视觉元素（caption uppercase 灰）被抄 21 份**（E2：`grep "func (secLabel\|sectionLabel\|header)("@）|

**§3.2 结论**：
- [ ] `XRow` 26 : `XPanel` 179 说明"卡片文化"压倒"行文化"。§7.6 StatCard 是"一张卡装多组行"，本仓是"一张卡装一行"
- [ ] 21 个 `secLabel` 副本应合成 1 个 `XSectionLabel`（§7.11 只定义了带 chevron 的版本，**缺不带 chevron 的纯标签** → 需补规范）

### 3.3 胶囊 / 瓦片 / 状态

| 族 | 次数 | 代表位置 | 现状规格 | 规范 §7 | 差距 |
|---|---|---|---|---|---|
| `XStatusPill` | **10** | `LocksPage.swift:181`、`KeysPage.swift:482`、`MemberCenterView.swift:1172` | `caption` + tone 0.12 底 + 0.24 描边 + Capsule（`Components.swift:152` HEAD） | **无对应** | §7 里没有"状态胶囊"。最接近的是 §7.2 StatChip（52pt 高、双行）—— 本仓是单行 24pt → **规范外的第三种胶囊** |
| `XMetricTile` | **6** | `DevicePage.swift:310/315/320`、`StatsPage.swift:239/244/249` | `title2` 值 + `caption` 标签 + `surfaceAlt` 底 + r14（`:183` HEAD） | §7.6 StatCard 子集 | 底用次级底当瓦片主底 → **V10**，视觉上比周围卡暗一档 |
| `XStatChip` | **2**（WT 新增） | `StatsPage.swift:78/82` | 52pt 高、r22、图标 34 + 标签上/值下 | §7.2 **正解** | ✅ WT 新加、**唯一按 §7.2 做的胶囊**。但只 2 次，`XStatusPill` 有 10 次（IOS-C-06） |
| `XEmptyState` | **12**（+7 自绘 = **19**） | `KeysPage.swift:294`、`MembersPage.swift:205`、`CredentialBinView.swift:44` | 44pt 图标 + `headline` 标题 + `subheadline` 说明 | §7.17（图标 28 + 标题 14SB + 说明 12） | **字号全线偏大**（IOS-M-05）。另有 7 处自绘：`AlarmsPage:377` `DonglesPage:282` `EventsPage:696` `FeedPage:215` `GatewayPage:340` `KeysPage:292` `MembersPage:203` |

### 3.4 环 / 图表（**§7.8 三种形态，本仓一种都没做**）

| 族 | 次数 | 唯一调用点 | 现状规格 | 规范 §7.8 | 差距 |
|---|---|---|---|---|---|
| `XCodeRing` | **1** | `CredentialStudio.swift:1662`（**在 OtpStudio 里 → OtpStudio 不可达**） | Canvas 环，线宽 `max(6, side*0.045)`（≈12pt @280） | 形态 2「三段分色 84pt / 14pt 线宽 / 3 段留 6°」 | ❌ **单色单环**（`ringTint` 单色，`Components.swift:733` HEAD）→ §7.8 通用自检直判「纯色单环 = 不合格」。尺寸 280 vs 84 |
| `XDayClock` | **1** | `StatsPage.swift:276`（size 156） | 24 辐条极坐标 + 中心总数 | **无对应**（§7.9 只给柱状/面积） | 规范外的图形语言。**价值高**（"一天本来就是圆的"理由成立），但无规范背书 |
| `XBatteryGauge` | **1** | `DevicePage.swift:93`（132pt） | 270° 开口弧 + 末端圆点 + 三档变色 | 形态 1 缺口大弧的**小尺寸变体** | 形态 1 要求 365pt / 42pt 线宽；132pt 版本规范未定义 |
| `XCycleRing` | **1** | `CarePage.swift:75`（128pt） | 360° 环 + 超期脉冲 | 形态 3 同心三环的单环版 | 单色环 → 同上不合格；且**有 `repeatForever` 脉冲**（`Components.swift:1185` HEAD）= **V9** |
| `XStepBar` | **1** | `BackupStudio.swift:494` | 序号圆点 + 标题 + 连接线 | **无对应** | 规范外。但比 §7.3 分段控件更适合向导 |
| `XSkewBar` | **1** | `DeviceHomeView.swift:116` | 居中 0 刻度 + 双向条 | **无对应** | 规范外 |
| `XOpenArcRing` | **0**（WT 新增） | 无 | — | **形态 1 正解** | ⚠ **定义了但零调用**（IOS-C-07） |
| `XConcentricRings` | **0**（WT 新增） | 无 | — | **形态 3 正解** | ⚠ **定义了但零调用** |
| `HomeConsole.dayChart` | 1 | `HomeConsole.swift:640`（WT） | 24 根 capsule 柱（3pt 间距）+ 5 轴标签 | §7.9「柱状图 = 1px 发丝线阵列，约 30 根，间距 5pt，**无圆角**」 | ❌ **形态完全不同**：圆角胶囊 vs 发丝线 |
| `StatsPage.trendCard` | 1 | `StatsPage.swift:332`(HEAD) | Swift Charts `LineMark` + `AreaMark`，`catmullRom`，轴全隐藏 | §7.9 面积图「渐变填充 + 2pt 描边 + 下方辉光」 | ⚠ 有 AreaMark 填充（`accent.opacity(0.12)`）但**无描边宽度控制、无辉光**；`chartXAxis(.hidden)` 与「轴标签最多 4 个」相反（过度隐藏） |
| `AlarmCenterView.hourBar` | 1（页不可达） | `AlarmCenterView.swift:267` | 9–14pt 宽圆角柱 + 告警点 | §7.9 | 同上 |
| `StatsPage.paretoCard` | 1 | `StatsPage.swift:104`（WT） | 横条 + 计数 + 百分比 | §7.9 | 规范外，但是**全仓最清晰的数据图**（数值 + 图形并存，符合 §9「数值优先」） |

**§3.4 结论（最狠的一条）**：
- [ ] **一屏一主角**：全仓只有 `HomeConsole`（220pt 环）与 `FirmwarePage`（180pt 环，且与渐变 hero 同屏）接近规范
- [ ] `XOpenArcRing` / `XConcentricRings` 已按规范写好但**零调用** —— 与 `XStatChip` 只 2 处同一模式：**新组件落地了，旧组件继续用**
- [ ] §7.8 通用自检「所有环必须渐变或分色」→ **现有 5 个环组件里 4 个是单色**（只有 `HomeConsole` 开锁环是 `AngularGradient` ✓）

### 3.5 空态 / 骨架 / Toast / 横幅

| 族 | 次数 | 代表位置 | 规范 §7 | 差距 |
|---|---|---|---|---|
| `XSkeleton` | **3** | `AlarmsPage.swift:40`、`EventsPage.swift:89`、`StatsPage.swift:54` | §7.20.1 ✅ | 块高各不同（84 / 96 / 132），符合"与最终内容同尺寸"；但**只有 3 页有骨架**，`KeysPage` `LocksPage` `MembersPage` `ExportCenter` 等 20+ 页**无加载态** |
| `XEmptyState` | 12（+7 自绘 = **19**） | 见 §3.3 | §7.17 | 字号偏大 + 两套实现 |
| `ToastView` | **1** | `LockKeeperApp.swift:1346`(HEAD)，挂 `RootView.topBanners` | §7.20.3 错误态 | 玻璃胶囊（`axGlass`）✓ 在功能层；但 `footnote` + `maxWidth 420` + `.shadow(0.18, r16, y6)` —— §6.3「黑底上唯一允许的阴影：设备样机 / 全屏 Sheet 边缘」→ **Toast 阴影是规范外** |
| 顶部横幅族 | **6 种**同挂 `topBanners` | `LockKeeperApp.swift:955`(HEAD)：BLEOffBanner / 自检黄条 / 粘贴条 / 汇总胶囊 / Toast / 写入回执 | §7.20 | **6 条横幅逻辑叠一个 VStack**，靠 `NoticeBudget` 排序只显示 1 条 —— 机制对，但**有 2 个 `Ambient` case 根本没有渲染分支**（IOS-A-03） |
| `Ambient` 枚举 | **4 case** | `App/Core/NoticeBudget.swift:13` | — | `firstUseCapsule` / `quickTileTip` **只参与排序、从不渲染**（E2：`LockKeeperApp.swift:965/970` 只处理 `selfCheck` 与 `pasteCare`） |

### 3.6 开关 / 输入 / 分段

| 族 | 次数 | 代表位置 | 规范 | 差距 |
|---|---|---|---|---|
| `XToggle` | **43** | 19 文件 | §7 无对应（系统开关） | ✅ `uicoverage` 检查七「裸写 Toggle 零命中」—— 唯一入口守住了 |
| `SecureField` / `TextField` | 需 grep | `SecurityCenterView.swift:943`(HEAD) / `ExportCenter.swift:1615` | §6.3 输入框底 = `surfaceSunken` | **两种底并存**：`ExportCenter` 用 `surfaceSunken`（`:1620`）✓；`SecurityDestroyView` 的 `SecureField` 用 `.textFieldStyle(.roundedBorder)`（`:944`）= **系统默认底**，在黑画布上是浅灰 → §3.1 违规 |
| `Picker` | 5 处 `.segmented` | `AddKeyPage:265` `BackupStudio:191/1081` `ExportCenter:1585` `SecurityCenterView:505` | §7.3 形态 A/B | **系统 segmented 的外观（浅灰轨道 + 白滑块）在纯黑上是最亮的一块** → 与"黑色是画布"冲突。另 `KeysPage.segmentBar` 是**自绘玻璃胶囊**（第 3 种）→ **同产品三种分段控件**，§7.3 自检明令「同一产品内只用一种」（IOS-C-01） |

---

## §4 层级与导航现状图

### 4.1 ASCII 全图

```
    ┌────────────────────────────────────────────────────────────────────────┐
    │ RootView  (LockKeeperApp.swift:941)                                    │
    │  ├ topBanners: BLEOff / 自检 / 粘贴 / 汇总胶囊 / Toast / 写入回执       │
    │  ├ MomentLayer (纪念卡 overlay)                                        │
    │  └ mainTabsChrome ─→ HomeConsole  ★唯一主界面                          │
    └────────────────────────────────────────────────────────────────────────┘
                                     │  HomeConsole.swift:53
          ┌──────────────────────────┼───────────────────────────┬──────────────────┐
          │sheet(item:$managerGroup) │sheet($showAddLock)        │sheet($showEvents)│
          │:197                     │:200                       │:211              │
          ▼                         ▼                           ▼                  │
    ┌───────────────┐        ┌──────────────┐            ┌──────────────┐         │
    │ ManagerFace   │        │ AddLockPage  │            │ EventsPage   │         │
    │  :27 (WT)     │        │  :23         │            │  :32         │         │
    └───────┬───────┘        └──────────────┘            └──────┬───────┘         │
            │ navigationDestination(for: ManagerRoute.self)  :83 │                 │
            │ 21 route → 20 页                                  │toolbar          │
    ┌───────┴────────────────────────────────┐        ┌────────┴────────┐         │
    │ ① 钥匙  ManagerGroup.ledger            │        ▼                 ▼         │
    │   .keys        → KeysPage       :31    │   StatsPage:31   AlarmsPage:27    │
    │   .fingerprints→ AddFingerPage  :24    │        │                          │
    │   .tempCodes   → TempCodeStudio :510   │        └─ 都是叶子                │
    │ ② 设备  .devices                       │                                   │
    │   .locks       → LocksPage      :30    │   ┌──── sheet(Binding) :203       │
    │   .firmware    → FirmwarePage   :23    │   ▼                               │
    │   .gateway     → GatewayPage    :21    │  EventsPage(initialHour:)  ── 同一页│
    │   .dongles     → DonglesPage    :22    │                                   │
    │   .syncTime    → SyncTimeView   :9     │   ┌──── sheet(Binding) :214       │
    │ ③ 成员  .members                       │   ▼                               │
    │   .members     → MembersPage    :30    │  MemberDetail360View :15          │
    │   .memberWizard→ MemberWizardView:478  │       ├ sheet → MergeMembersView  │
    │   .mergeMembers→ ⚠ MembersPage(同②)   │       │          :678             │
    │   .archivedMembers → MemberArchivedView│       └ sheet → MemberExitWizard  │
    │ ④ 安全  .security                      │                  :1353            │
    │   .securityCenter → PrivacyDashboard   │                                   │
    │   .securityAudit  → SecurityAuditView  │                                   │
    │   .securityDestroy→ SecurityDestroyView│                                   │
    │                     └→ CredentialBinView (唯一入口!)                     │
    │   .safemode       → SafemodeIntroView  │                                   │
    │ ⑤ 数据与外观  .backupLook              │                                   │
    │   .backup      → BackupPage     :28    │                                   │
    │   .export      → ExportCenterView:1475 │                                   │
    │   .appearance  → AppearancePage :18    │                                   │
    │   .me          → MePage         :32 ───┼──→ ★ B 通道（见 4.2）             │
    │   .diagnostics → DiagnosticsPage:18    │                                   │
    └────────────────────────────────────────┘                                   │
                                                                                 │
    ┌────────────────────────────────────────────────────────────────────────────┘
    │  B 通道：MePage.swift:32（20 条 NavigationLink）
    │
    ├─ :147 本机数据保护 ─┐
    ├─ :156 隐私与伪装   ─┴→ ★ SecurityPage :28（两条链同一目标）
    │                          ├ :257 → AppLockSetupView  :25
    │                          ├ :262 → SecurityPeekView  :154
    │                          ├ :267 → SecurityAuditView :471   ← 与 A④ 重复
    │                          └ :271 → SecurityDestroyView :881 ← 与 A④ 重复
    ├─ :168 诊断与自检 ─→ DiagnosticsPage :18        ← 与 A⑤ 重复
    ├─ :191 这台锁     ─→ DevicePage :30             ← ★仅 B
    ├─ :198 设备管理   ─→ LocksPage :30              ← 与 A② 重复
    ├─ :206 锁档案     ─→ LockProfilePage :22        ← ★仅 B
    ├─ :213 校准时间   ─→ SyncTimeView :9            ← 与 A② 重复
    ├─ :219 开锁偏好   ─→ LinkPrefsView :650         ← ★仅 B
    ├─ :226 自动开锁   ─→ AutoCalView :523           ← ★仅 B
    ├─ :235 门锁安全模式→ SafemodeIntroView :12      ← 与 A④ 重复
    ├─ :251 备份与恢复 ─→ BackupPage :28 ─→ sheet → BackupStudioView :10
    │                                       ├ sheet → ExportWizardView :458
    │                                       └ sheet → RestoreWizardView :918
    ├─ :259 导出中心   ─→ ExportCenterView :1475 ─→ fsc → QLPreviewView
    ├─ :274 事件记录   ─→ EventsPage :32             ← ★仅 B（门厅另有 2 sheet）
    ├─ :281 动态消息   ─→ FeedPage :21               ← ★仅 B
    ├─ :320 App 图标   ─→ IconPicker :13             ← ★仅 B
    ├─ :324 固件更新   ─→ FirmwarePage :23           ← 与 A② 重复
    ├─ :331 维护与保养 ─→ CarePage :27               ← ★仅 B
    │                      └ sheet :250 → MaintenanceView :9 → sheet → CareChecklistView:470
    ├─ :337 关怀提醒   ─→ CareRemindersView :6       ← ★仅 B
    ├─ :344 蓝牙钥匙串 ─→ DonglesPage :22            ← 与 A② 重复
    └─ :350 智能网关   ─→ GatewayPage :21            ← 与 A② 重复

    ┌───────────────────── 死路（可达性事故）─────────────────────┐
    │ QuickPool.quickDestination(_:)  App/Core/QuickPool.swift:143 │
    │   零调用 → 它 switch 里的 10 个目标全部不可达：              │
    │   StudioPage :24 · TempCodeStudio :510 · FpStudio :1054      │
    │   OtpStudio :1469 · AddKeyPage :25 · AddFingerPage :24       │
    │   SyncTimeView :9 · BackupView :7 · AlarmCenterView :12      │
    │   MaintenanceView :9 · FirmwarePage :23                      │
    │   ⇒ StudioPage / BackupView / AlarmCenterView                │
    │      **全仓再无第二个构造点**（E2 grep）                      │
    │   ⇒ 连带 FpStudio / OtpStudio / XCodeRing 一起死              │
    └──────────────────────────────────────────────────────────────┘
```

### 4.2 交叉 / 重叠矩阵

| 功能 | 入口 A（ManagerFace） | 入口 B（MePage） | 入口 C（别处） | 行为一致？ | 证据 |
|---|---|---|---|---|---|
| 钥匙列表 | `.keys` | — | — | — | E2 |
| 指纹 | `.fingerprints` | — | `MemberCenterView:560` NavigationLink | ✅ 同一 `AddFingerPage` | E2 |
| 临时码 | `.tempCodes` | — | — | — | E2 |
| 门锁列表 | `.locks` | `:198` | — | ✅ | E2 |
| 设备详情 | **无** | `:191` `DevicePage` | — | ❌ **仅 B** —— 且 `DevicePage.swift:6-8` 注释说它"全仓零引用，做好了没接进导航"，实际已被接 | E2 |
| 锁档案 | **无** | `:206` | — | ❌ 仅 B | E2 |
| 固件 | `.firmware` | `:324` | — | ✅ | E2 |
| 网关 | `.gateway` | `:350` | — | ✅ | E2 |
| 钥匙串 | `.dongles` | `:344` | — | ✅ | E2 |
| 校时 | `.syncTime` | `:213` | `CareViews:423`（在 MaintenanceView 里 → **不可达**） | ✅ A/B；C 死 | E2 |
| 成员 | `.members` | **无** | `KeysPage:76` toolbar | ✅ | E2 |
| 安全总览 | `.securityCenter` → `PrivacyDashboard` | `MePage.swift:147` → **`SecurityPage`** | — | ❌ **两个不同页**：A 是 5 项防窥开关，B 是状态+风险+4 动作 | E2 |
| 隐私与伪装 | 无独立入口 | `MePage.swift:161` → `SecurityPeekView` | — | ⚠ **两套 UI 同一件事**：A 的 `PrivacyDashboard` 是 5 行点按，B 的 `SecurityPeekView` 是完整设置页（8 项） | E2 |
| 应用锁 | **无入口** | `SecurityPage.swift:256` | — | ❌ 只能 B→C 两跳 | E2 |
| 销毁 | `.securityDestroy` | `SecurityPage:271` | — | ✅ 同一页（路径不同） | E2 |
| 回收站 | **无** | **无** | `SecurityDestroyView:998` | ❌ **只能从"销毁数据"页进去** | E2 |
| 备份 | `.backup` | `:251` | — | ✅ | E2 |
| 导出 | `.export` | `:259` | — | ✅ | E2 |
| 事件记录 | **无** | `:274` | `HomeConsole:203` / `:211` sheet | ✅ 三条路同一页，但**两条是 sheet、一条是 push** | E2 |
| 动态消息 | **无** | `:281` | — | ❌ 仅 B，且与"事件记录"职责重叠 | E2 |
| 外观 | `.appearance` | **无** | — | ❌ 仅 A | E2 |
| 诊断 | `.diagnostics` | `:168` | `LockKeeperApp:1199` 自检黄条（`pendingSettingsFocus="diag"`） | ✅ | E2 |
| 告警中心 | **无** | **无** | `EventsPage:141` toolbar | ❌ **三条路都没有** —— 只能从事件页 toolbar 图标进 | E2 |
| 统计 | **无** | **无** | `EventsPage:135` toolbar | ❌ 同上 | E2 |
| 关怀提醒 | **无** | `:337` | — | ❌ 仅 B | E2 |
| 维护保养 | **无** | `:331` | `CarePage:250` sheet | ✅ B/C，但 C 是 sheet | E2 |

### 4.3 §4 的三条硬结论

1. **A 通道 11 页独有，B 通道 11 页独有，9 页重叠** —— 合并任何一条都会丢功能。
2. **`SecurityPage` 与 `PrivacyDashboard` 是两个"安全总览"**，且 `PrivacyDashboard` 里没有"应用锁"入口（应用锁只在 `SecurityPage:257`）—— **用户从管理面板永远开不了应用锁**。
3. **两条最容易漏的通道**：`EventsPage` 的 toolbar（→ 统计/告警）和 `SecurityDestroyView` 里的回收站 Link。**它们不在任何 menu/列表里，是图标或卡内嵌链**。

---

## §5 明显不合理清单（5 类 / **42 条**：S 8 · G 5 · C 11 · A 8 · M 10）

> 编号：`IOS-<类别>-NN`。类别：**S**=结构 · **G**=分组 · **C**=一致性 · **A**=可达性 · **M**=语义。
> 每条写：问题 / 证据 / 后果 / 处置。

### 5.1 结构（S）

| 编号 | 问题 | 证据（文件:行） | 后果 | 处置 |
|---|---|---|---|---|
| **IOS-S-01** | **根 token 在 WT 已被改成规范值，但改动无法编译验证** —— gutter 16→14、XRadius.card 16→24、canvas #0A0A0B→#000000、surface #161618→#1C1C1E | HEAD：`Theme.swift:128`(`gutter=d(16)`)、`:139`(`card=r(16)`)、`:35`(`canvas=0x0A0A0B`)、`:37`(`surface=0x161618`)；WT：`Theme.swift:182`(`gutter=d(14)`)、`:212`(`card=r(24)`)、`:54`(`canvas=#000000`)、`:58`(`surface=0x1C1C1E`) | 本机**无编译器**（E1：swift/swiftc/xcodebuild 全 NOT FOUND）。改 4 个根 token ⇒ 派生值全部失效：`XSpace.align = gutter + card − 1`（WT `:196`）、`XRadius.inner`、以及 **29 处 `XRadius.card` 引用 + 66 处 `XSpace.gutter` 引用**（E1 计数） | **不许在本机宣布"改完能编译"**。派生公式硬编码 −1 与 §5.4「29 = 14+15」差 1pt（见 IOS-S-02），必须在 CI 上校准 |
| **IOS-S-02** | **`XSpace.align` 的 −1 是拍脑袋**：`gutter + card − 1 = 14+16−1 = 29` 恰好命中 29，公式本身无依据 | `Theme.swift:196`(WT) `static var align: CGFloat { gutter + card - 1 }` | 若 `card` 将来改 15（规范实测值），`align` 变 28 —— **对齐线自动断 1pt**，没人会想到去查公式 | 改显式常量 `static let align: CGFloat = 29` + 一条断言 `align == gutter + card`（当前 14+16=30≠29，**这条断言会立刻红**，逼作者选：gutter 15 或 align 30） |
| ~~**IOS-S-03**~~ | ~~`MePage` 两条 NavigationLink 指向同一页~~ | ✅ **本轮已被 Lead 修复**（详见 §0.4）：`MePage.swift:161` 现为 `SecurityPeekView()` | — | 关闭 |
| **IOS-S-04** | **"合并成员"落到成员列表** | `ManagerFace.swift:252` `case .mergeMembers: MembersPage()`，`:239-241` 注释自陈原因 | 菜单承诺"合并成员"，用户要**再选一次人**、还要进详情页 menu 才到合并页。**两步变四步** | 把 `MergeMembersView` 改成接受 `Member?`（nil = 先选人），route 直接落到它 |
| **IOS-S-05** | **`ExportCenterView` 973 行 / 17 分区 / 16 张 XPanel 同屏** | `ExportCenter.swift:1475-2447`；分区清单见 §2.9 | §0 总则三「一屏只有一个主角」**无解**。用户要滚 5–8 屏才到"校验" | 按"导出/分享/打印/校验"拆 4 个入口（A 通道已有一层"导出中心"菜单，可扩成 4 条 route） |
| **IOS-S-06** | **`LocksPage` 是全仓唯一 `List`**，且系统行底未关 | `LocksPage.swift:43`(HEAD) `List {`；`:118` `.listStyle(.insetGrouped)`；`:119` `.scrollContentBackground(.hidden)`；只有空态行有 `.listRowBackground(Color.clear)`（`:53`） | 行背景（分组灰/白）在纯黑画布上是一块块亮矩形，圆角 ≈10pt（§5.2 要 24）。`.hidden` 只管整表 | 改 `ScrollView + XPanel(.group, padding:0) + XRow`（与 `MembersPage.rosterCard` 同形） |
| **IOS-S-07** | **`RootView.bleStatusStrip` 定义后零调用** | `LockKeeperApp.swift:1326`(HEAD) 定义；grep 全仓**仅 1 处** | "非设备页顶部 BLE 细条"这条路死了；而 `topBanners` 里 `BLEOffBanner` 还在 —— **用户只能在蓝牙彻底关掉时才知道连接状态** | 要么挂上，要么删。**留着比删掉危险**（下一个人会以为它生效） |
| **IOS-S-08** | **`AlarmCenterView` 898 行 / 13 分区，完全不可达** | `AlarmCenterView.swift:12`；唯一构造点 `QuickPool.swift:151` 在零调用函数里 | 一个 898 行的页面（告警流/分时/处置/试验卡/响应卡）**用户永远看不到**；而可达的 `AlarmsPage`（417 行）是它的**简化版** | 二选一：把 `AlarmCenterView` 接进 `EventsPage` toolbar（替掉 `AlarmsPage`），或删掉它。**当前是最坏状态：两套告警页，一套死一套活** |

### 5.2 分组（G）

| 编号 | 问题 | 证据 | 后果 | 处置 |
|---|---|---|---|---|
| **IOS-G-01** | **`MePage` 的"关于与偏好"装的是设备功能** | `MePage.swift:318`(`aboutSection`) 内含 `FirmwarePage`(`:324`)、`DonglesPage`(`:344`)、`GatewayPage`(`:350`) | 同一个"固件升级"在 A 通道 `.devices` 组、B 通道"关于与偏好"组 —— **分组语义直接冲突**。用户按"关于"找固件永远找不到 | 把 3 条移到 `lockSection`（或删掉，A 通道已有） |
| **IOS-G-02** | **`MePage.lockSection` 7 条 = 308pt，一屏放不下** | `MePage.swift:183-247`：这台锁/设备管理/锁档案/校时/开锁偏好/自动开锁/安全模式 | 用户滚到"数据"组要滑过 7×44 ≈ 308pt。7 行在一张卡内**没有分组依据**（3 个"看"、2 个"改"、2 个"安全"） | 拆 3 卡：身份（这台锁/锁档案）· 行为（开锁偏好/自动开锁/校时）· 安全（安全模式/设备管理） |
| **IOS-G-03** | **`ManagerFace` 5 组 vs §7.10「3–4 项」—— 偏离已自陈，且推翻条件已踩线** | `ManagerFace.swift:295`(`enum ManagerGroup`)、`:290` `case backupLook = "数据与外观"`；偏离记录 `docs/GLASS/DEVIATIONS.md` §2（E3） | DEVIATIONS 自陈「5 项在 393pt 上每项约 68pt，标签超过 4 字会挤」—— 而"数据与外观"是 **5 字**；且 `backupLook` 只有 4 条 route（最小的一组）却占最长名字 | 改名（"数据"2 字）或重排。规范与现实的冲突**必须在 DEVIATIONS 里给出实测截图** |
| **IOS-G-04** | **`ManagerFace.rows()` 一行一张卡 —— 21 行 = 21 张卡** | `ManagerFace.swift:171-183` `XPanel(.group){ XRow(...) }`，spacing `XSpace.rowGap`(8) | `devices` 组 5 张卡 ≈ **372pt**，比一卡五行（**244pt**）高 52%。§8 模板 C 的"卡片内自由布局"被否掉了 | 改"一卡多行"（§7.6 StatCard 的原型），行间用 `XHairline`。**这是全仓最值得改的一处结构** |
| **IOS-G-05** | **"事件记录"与"动态消息"职责重叠** | `MePage.swift:272` `EventsPage` / `:279` `FeedPage`；`:264-271` 注释自陈「两个都在」 | 两个都按天分组、都显示告警红点（`FeedPage.swift:264` 8pt 三角 / `EventsPage.swift:505` 同款）→ **同一件事两个入口、两套实现** | 删 `FeedPage`，把"卡片流"作为 `EventsPage` 的一个分段（它已有两个 toolbar 兄弟页） |

### 5.3 一致性（C）

| 编号 | 问题 | 证据 | 后果 | 处置 |
|---|---|---|---|---|
| **IOS-C-01** | **3 种分段控件并存** | ① `KeysPage.swift:155` 自绘玻璃胶囊 ② 系统 `.pickerStyle(.segmented)` 5 处（`AddKeyPage:265` `BackupStudio:191/1081` `ExportCenter:1585` `SecurityCenterView:505`）③ `PrivacyDashboard` 的"点按行"伪开关（`SecurityCenterView:1431`） | §7.3 自检「同一产品内只用一种，不得混用」→ **直接判不合格**。系统 segmented 在纯黑上是最亮一块 | 统一到 §7.3 形态 B（胶囊式），写一个 `XSegmented` |
| **IOS-C-02** | **两种分隔线** | `XHairline` 23 处 vs `Divider().overlay(XPalette.hairline)` 15 处 | 同一个东西两套实现；`Divider` 带系统默认内边距 | 15 处 `Divider` 全换 `XHairline(inset:)` |
| **IOS-C-03** | **21 个 `secLabel`/`sectionLabel`/`header` 副本** | `SecurityCenterView` 4、`MemberCenterView` 5、`CareViews` 3、其余 9 文件各 1 | 同一视觉元素（caption + uppercase + textTertiary + 左对齐）抄 21 份；改字阶要改 21 处 | 抽 `XSectionLabel` 进 `Components.swift`；21 处全删 |
| **IOS-C-04** | **8 种 ButtonStyle 并存**（§3.1） | `.plain` 60 / `XSecondary` 28 / `XPrimary` 17 / `.bordered` 10 / `PressableButtonStyle` 6 / `PlainButtonStyle()` 5 / `PressableScaleStyle` 3 / `XDestructive` 2 / `StudioCardStyle` 1 | 60 处 `.plain` **无按压反馈** → §11.1 在全仓 60 个可点元素上缺失 | 定义 3 档（primary/secondary/destructive）+ 1 个通用 `Pressable`，其余全删 |
| **IOS-C-05** | **`PressableButtonStyle` vs `PressableScaleStyle`**：两个做同一件事 | `LockKeeperApp.swift:1378`(HEAD) 定义前者（含 300ms 防连点，0.96）；`HomeConsole.swift:1061`(HEAD) 定义后者（0.96，无防连点） | 前者"对的"，但只 6 处；后者 3 处。**通用型按钮样式定义在页面文件里** | 删后者，前者移进 `Components.swift` |
| **IOS-C-06** | **`XStatusPill` 10 处 vs `XStatChip` 2 处** —— 新组件落地了，旧组件继续用 | `XStatChip` WT `Components.swift:1465`（按 §7.2 做对了）；`XStatusPill` HEAD `Components.swift:152` | 两个胶囊族并存，**规范里只有一个（§7.2）** | `XStatusPill` 改名 `XTag`（它是"标签"不是"chip"），或全并进 `XStatChip` |
| **IOS-C-07** | **规范组件已写但零调用**：`XOpenArcRing` / `XConcentricRings` | WT `Components.swift` 约 `:1652` / `:1749`；grep 全仓**构造点 0**（E1） | §7.8 形态 1 与形态 3 是**主视觉**，写好了没人用。现有 5 个环组件里 4 个单色 | 优先把 `HomeConsole` 开锁环换成 `XOpenArcRing`（它已是 220pt 缺口大弧，语义完全对） |
| **IOS-C-08** | **`EmptyState` 两套：12 组件 + 7 自绘** | 组件：`KeysPage:294` 等；自绘：`AlarmsPage:377` `DonglesPage:282` `EventsPage:696` `FeedPage:215` `GatewayPage:340` `KeysPage:292`(`emptyCard`) `MembersPage:203` | 自绘的字号/图标尺寸各不同（`AlarmsPage` 用 `XMetric.decorIcon(44)`） | 7 处自绘全换 `XEmptyState`；并先把它的 44/17B/15 压到规范的 28/14SB/12 |
| **IOS-C-09** | **`AlarmsPage` 与 `AlarmCenterView` 是两套告警页** | `AlarmsPage.swift:27`（可达）/ `AlarmCenterView.swift:12`（不可达） | 同一功能两套实现，其中一套死 | 见 IOS-S-08 |
| **IOS-C-10** | **`pagecraft.js` 的台账数据与代码不一致** | `tools/pagecraft.js:23` 读 `.routes.json`；该文件里 `["appearance","StudioPage"]`；而代码 `ManagerFace.swift:254` 是 `AppearancePage()` | **闸门自己漂移**：`node tools/pagecraft.js` 输出「appearance → StudioPage 3/4 分 ✗ 令牌」，实际代码是 `AppearancePage`（E1 + E2） | `.routes.json` 需重新生成；且 `destmap` / `pagecraft` 之间应有一条"台账 vs 代码"漂移检查 |
| **IOS-C-11** | **同一功能两套 UI**：隐私/防窥在 A 通道是 `PrivacyDashboard`（5 行点按，无开关视觉），在 B 通道是 `SecurityPeekView`（8 项完整设置页，有磨砂演示） | A：`ManagerFace.swift:237` `case .securityCenter: PrivacyDashboard()`；B：`MePage.swift:161` `SecurityPeekView()` | 用户从不同入口进去看到**完全不同的两套界面**，且都能改同一批键 → 改一处另一处不更新 | 二选一：删 `PrivacyDashboard`（保留功能的那个），或把 `PrivacyDashboard` 降级为 `SecurityPeekView` 的顶部摘要区 |

### 5.4 可达性（A）

| 编号 | 问题 | 证据 | 后果 | 处置 |
|---|---|---|---|---|
| **IOS-A-01** | **`QuickPool.quickDestination` 零调用 ⇒ 10 个目标页不可达** | `QuickPool.swift:143` 定义；grep 全仓**仅 1 处**；其中 `StudioPage`(P-059) / `BackupView`(P-061) / `AlarmCenterView`(P-060) **再无第二个构造点** | 3 个整页 + `FpStudio` / `OtpStudio` / `XCodeRing` / `FpOwnerPicker` / `StepDots` / `MaskedDigits` / `WindowBar` / `CodeBigCard` 一起死。**`OtpStudio` 507 行、`AlarmCenterView` 898 行、`StudioPage` 210 行全部白写** | 把 `quickDestination` 接到门厅（`HomeConsole` 现在**没有任何快捷格**） |
| **IOS-A-02** | **`HomeConsole.quickTipTile` 指向不存在的快捷格** | `LockKeeperApp.swift:233`(HEAD)；`HomeConsole` 里**没有任何 QuickPool 渲染**（E2） | 首用提示把用户指向"主控卡上的快捷格"，那里什么都没有（`LockKeeperApp.swift:247` 注释甚至写"单锁也画"，但代码没有画的地方） | 要么把快捷格做进 `HomeConsole`，要么删 `quickTileTip` |
| **IOS-A-03** | **`Ambient` 4 个 case 只有 2 个有渲染分支** | `NoticeBudget.swift:13-17`（4 case）；`LockKeeperApp.swift:965/970` 只处理 `.selfCheck` / `.pasteCare`；`.firstUseCapsule`(rank 2) / `.quickTileTip`(rank 3) **只参与排序、无 UI** | 这两个提醒**永远不会出现**，但**占用了 NoticeBudget 的 rank 槽位** → 若与 `.selfCheck` 同时成立，`ambientRest` 计数会包含永不渲染的项（"还有 N 条提醒"数字虚高） | 删掉这两个 case，或补渲染分支 |
| **IOS-A-04** | **`showAmbientList` 有写无读** | `LockKeeperApp.swift:229` 声明 / `:1165` 写入 `= true`；**无任何 `if app.showAmbientList` 消费**（E2：grep 仅 2 处） | 用户点"还有 N 条提醒"胶囊 → 设一个永远没人读的布尔 → **什么都不发生**（而 `ambientOverflowChip` 的 `accessibilityLabel` 却承诺"轻点逐条查看"） | 补一个 sheet，或删胶囊 |
| **IOS-A-05** | **回收站只有一个入口，且藏在"销毁数据"页里** | `SecurityCenterView.swift:999` 是全仓唯一 `CredentialBinView()` 构造点（E2 grep） | 用户删了凭证想找回 → 必须进"管理 → 安全 → 销毁数据"（一个**红色危险页**）→ 才看到回收站。而 `KeysPage` 的删除确认文案**明确承诺**"可在「安全 → 回收站」核对"（`KeysPage.swift:282` HEAD）→ **指的路不存在** | 在 `KeysPage` toolbar 加回收站图标（文案已指路，只差入口） |
| **IOS-A-06** | **告警中心与统计只能从 `EventsPage` 的两个图标进** | `EventsPage.swift:135`(`chart.bar`) / `:141` | `ManagerFace` 的"安全"组**没有告警**；门厅 `criticalNotice.alarms` 点进去是 `managerGroup = .security`（`HomeConsole.swift:384` HEAD）→ 到的是 `PrivacyDashboard`（防窥），**不是告警列表** | 把 `AlarmsPage` 加进 `.security` 组（现 4 条，+1 = 5，与 `devices` 组持平） |
| **IOS-A-07** | **`HomeConsole` 的 `managerGroup` 4 处程序化触发，取代了 4 个 Tab** | `HomeConsole.swift:195`(深链) `:368`(到期) `:369`(告警/低电) `:504`(失败态"去处理") | 4 Tab 已删，但 `tabSelection` 仍是 `Route` 的载体（29 处引用）；`ManagerGroup.forRoute`（`:1124` WT）把 `.records` 映射到 `.ledger` —— **"记录"深链落到"钥匙"组** | `Route` + `tabSelection` + `guestBlockedTabs` 这一整套已无指称对象，应在改造中一并删 |
| **IOS-A-08** | **`XLockBlade` 零构造点** | `App/UI/XLockBlade.swift:26`；grep 全仓仅声明行（E1） | 208 行 RealityKit 锁体（`BladeGeometry` 262 行 + `BladeMesh` 98 行的唯一消费者）**永远不会显示**。`reach.js` 也报它是唯一不可达 View（E1） | 删，或接进 `HomeConsole.unlockStage`（它本来就是"物理锁体"的视觉，与 220pt 环同一语义） |

### 5.5 语义（M）

| 编号 | 问题 | 证据 | 后果 | 处置 |
|---|---|---|---|---|
| **IOS-M-01** | **`LocksPage` 左滑"删除"实际是"隐藏"，且无确认** | `LocksPage.swift:67-73`(HEAD) `.onDelete { … LockArchive.setHidden(kc.mac, true) }` —— 无 `confirmationDialog`；而"解除绑定"（真删）有确认（`:142`） | 两种破坏性动作手势相同、确认门槛不同 | 左滑改文案为"隐藏"并加轻确认（或把隐藏移到"已隐藏"区的手势里） |
| **IOS-M-02** | **三种 `criticalNotice` 互斥，低电被告警吞掉** | `HomeConsole.swift:333`(WT) `criticalNotice` 是 `if … return .alarms` → `if … return .lowBattery` → `if … return .expiring` | 同时有告警 + 低电时**低电不显示**。而低电是"门会开不了"的直接原因，比告警更紧急 | 改成"最多 2 条"或按紧急度重排（低电 < 10% 应压过非紧急告警） |
| **IOS-M-03** | **`BackupPage.importCard` 用 `tone: .warn` 当普通入口底** | `BackupPage.swift:312`(HEAD)；同页 `restoreConfirmCard`(`:267`) 也是 warn | **两张 warn 卡同屏** → 语义色失去"注意"含义。§3.4「强调色只用于数字/图标/描边/1px 指示点」 | `importCard` 改 `tone: .neutral` |
| **IOS-M-04** | **`PrivacyDashboard` 的"点按行即切换"没有开关视觉** | `SecurityCenterView.swift:1431-1462`：只有 `checkmark.circle.fill` vs `circle` + 右侧文字 | §13.3「不靠颜色单独表意」✅（有文字）；但**没有平台开关形状** → 用户不知道这里能点。`accessibilityTraits(.isButton)` 补了读屏，视力用户没有 | 换 `XToggle`（`uicoverage` 检查七要求开关只从 XToggle 来） |
| **IOS-M-05** | **`XEmptyState` 字号全线大于 §7.17** | `Components.swift:221`(HEAD)：图标 `XIcon.xl`=44（规范 28）、标题 `.headline`=17B（规范 14SB）、说明 `.subheadline`=15（规范 12） | 空态在**没有内容的页面上是唯一内容**，字号过大让"空"变成"占据一屏的告示牌" | 压到 28/14SB/12 |
| **IOS-M-06** | **`MePage.summaryTile` 底 = `surfaceAlt.opacity(0.6)`** | `MePage.swift:136`(HEAD) 附近 | 0.6 透明度把 `surfaceAlt` 压到接近 `surfaceSunken` —— **语义漂移**：四格是"读数"（该亮），却用了"凹陷"（该暗）那一档 | 改 `surfaceAlt` 实底，或按 §7.2 做 `XStatChip` |
| **IOS-M-07** | **`DevicePage.metricsRow` 三个 `XMetricTile` 用 `surfaceAlt`** | `DevicePage.swift:310/315/320`；`Components.swift:210`(HEAD) | 同 IOS-M-06（同一根因：`XMetricTile` 的默认底就是次级底） | 改 `XMetricTile` 的底为 `surface`，让它在卡内"浮起" |
| **IOS-M-08** | **`EventsPage` / `FeedPage` 的 8pt 图标** | `EventsPage.swift:505`(HEAD) `.font(.system(size: 8, weight: .semibold))`；`FeedPage.swift:264` 同 | §4.2 下限 11 + §10 尺寸表无 8 → **两项规范同时违反** | 改 12（最接近的 `XIcon.xs`=13） |
| **IOS-M-09** | **`MePage` / `LockProfilePage` 的 9pt 图标** | `MePage.swift:122`(WT) `size: 9`；`LockProfilePage.swift:153`(HEAD) `size: 9` | 同上 | 同上 |
| **IOS-M-10** | **`HomeConsole.memberChip` 触达 < 44pt** | `HomeConsole.swift:736-748`(WT)：头像 28×28 + `padding(.vertical, 5)` ⇒ 38pt | HIG 44pt 最小触达 + 全仓 `XHit.min`=44 但这里没用 | 加 `.frame(minHeight: XHit.min)` |

---

## §6 改造风险面（不可回退动作 / 必须保住什么）

> **原则**：UI 改造可以重排、可以换容器、可以删分区。但下面这些**语义门槛**一旦在重构中丢失，就是数据丢失或安全事故。
> 每条给 `文件:行` + **必须原样保住的东西**。

### 6.1 红线（**绝对不许在 UI 改造中动**）

| 编号 | 动作 | 门槛（当前实现） | 证据 | 改造时必须保住 |
|---|---|---|---|---|
| **IOS-R-01** | **三级销毁**（删 + 覆写全部本地缓存） | ① `XToggle` 我理解不可恢复 → ② `SecureField` 重输应用锁密码（`sudoSatisfied`）→ ③ `TextField` 键入"销毁"二字；三条件全满足才可用 | `SecurityCenterView.swift:931`(ack) `:943`(sudoInput) `:962`(typedWord) `:969`(**`.disabled` 三条件**) `:1298`(`DestroyKit.destroyAll`) | **三条门槛一个都不能少**。特别是 `:969` 的 `.disabled(...)` —— 它同时是 UI 与安全边界 |
| **IOS-R-02** | **销毁前的 sudo 复核**（会话券） | `SecurityPolicy.sudoRequired` 默认 `true`（`LockGuard.swift:129`）；`app.sudoTicket` 非空才放行（`SecurityCenterView.swift:1236`）；`DestroyKit.destroyAll` 在 `sudoRequired && sudo == nil` 时**直接 `return nil`**（`AuditChain.swift:312`） | 同上 + `AuditChain.swift:311-312` | **`guard !sudoRequired \|\| sudo != nil else { return nil }` 不许改** —— 这是唯一的服务端式硬闸 |
| **IOS-R-03** | **按住 2 秒清空回收站** | `holdClearControl`（`:1191`）+ `startHoldTask`（`:1333`）+ `guardedDestroy`（`:1351`）；注释自陈 P0 修复「任务跑满 2s 且未被松手取消才真正执行清空」 | `SecurityCenterView.swift:1030` `:1191` `:1333` `:1347-1351` | **"跑满 2s 且未被取消"这条判据**。改成 `.confirmationDialog` 会**降低**门槛 |
| **IOS-R-04** | **删除成员最后一枚指纹的双签** | 需输入**任一在用密码的前 N 位**；`input.hasPrefix(mask)` 才执行 | `CredentialStudio.swift:1025`(mask) `:1027`(标题"双签验证") `:1037`(`hasPrefix`) `:1041`(失败弹窗) | **前缀校验**与**"这是最后一枚"的后果预告**（`:1028`）。注意 `:1017` 的 `lastWarn` 是"连密码都没有"的更贵分支 |
| **IOS-R-05** | **成员删除的级联双选** | 弹窗两个按钮：**"只移除档案"**（默认，动本机）+ **"连锁端一起收回"**（destructive，排锁端删除） | `MemberCenterView.swift:437`(`confirmDelete`) `:443-445`(后果文案) `:447` / `:453`(两个 action) | **两个选项的措辞与顺序**。`:445`「指纹一旦在锁端删掉就无法远程补录」是**不可逆后果的唯一告知** |
| **IOS-R-06** | **恢复备份 = 整表覆盖** | 页内卡片三句：① 备份时间/设备数 ② **"备份里没有的不会保留"** ③ 想保留新增的走工作室合并 | `BackupPage.swift:266` `:280` `:286`；`applyRestore`(`:456`) | **`:280` 那句"备份里没有的不会保留"绝对不许简写成"相同设备会被覆盖"**（commit `8007b8b` 正是为修这句） |
| **IOS-R-07** | **固件升级** | 两个 `confirmationDialog`，文案含"中断可能导致门锁需要重新配网" | `FirmwarePage.swift:101` `:107` `:105`/`:111` | **中断后果的告知**。升级中 `upgradeStage` 独占（`:79` `if running`），不要加"取消"按钮 |
| **IOS-R-08** | **配网（Gateway）** | 3 个 `confirmDestructive`：删网关 / 写网关 / 重启网关 | `GatewayPage.swift:366` `:376` `:385` | 三个都要留；配网进行中**没有** `interactiveDismissDisabled` → **已知缺口**，改造时建议补 |
| **IOS-R-09** | **配对锁（AddLockPage）** | `.interactiveDismissDisabled(flow == .pairing \|\| flow == .naming)` | `AddLockPage.swift:81` | **配对/命名两步禁止下滑关闭**。换 sheet 容器时这条最容易丢 |
| **IOS-R-10** | **关闭应用锁** | `.confirmationDialog("关闭应用锁？")` + `turnOff()` | `AppLockSetupView.swift:56-57` `:230` | 确认框 + "关闭后这台手机里的密码不再受保护"文案（`:158`） |
| **IOS-R-11** | **B 模式切换（更严方向）** | `confirmDestructive`，文案含"本 App 不提供改回 A 模式的入口" | `SettingsView.swift:81-83` | **"不可回退"的告知**。这是单向门 |
| **IOS-R-12** | **钥匙串写入 / 删除** | 3 个 `confirmDestructive` | `DonglesPage.swift:317` `:326` `:335` | 全部保留 |

### 6.2 黄线（**可以改，但改法受约束**）

| 编号 | 项 | 约束 | 证据 |
|---|---|---|---|
| **IOS-Y-01** | **长按 1.05s 开锁** | 必须用 `onLongPressGesture(minimumDuration:maximumDistance:)`，**不许改回 `DragGesture + sleep`**（注释记录安全洞：手势被系统取消时 `onEnded` 不触发，`pressing` 停在 true，定时器到点真开门） | `HomeConsole.swift:480`(HEAD) `:476-478`(注释) `:96`(`chargeDuration=1.05`) |
| **IOS-Y-02** | **开锁重入闸** | `isUnlocking` 必须在**任何 `await` 之前同步置位**（VoiceOver 的 `accessibilityAction` 是独立入口，连点两次能绕过长按节流） | `HomeConsole.swift:837-839`(HEAD) `:489`(`accessibilityAction`) |
| **IOS-Y-03** | **切后台中止蓄力** | `scenePhase != .active` 必须调 `abortCharge()` | `HomeConsole.swift:157-163`(HEAD) `:807` |
| **IOS-Y-04** | **破坏性确认必须用 `UIAlertController`** | 不能用 SwiftUI `.alert`（`Alerts.swift:66` 原话「SwiftUI 的 alert 装输入框在 iOS 上不可靠」） | `Alerts.swift:16` `:29` `:68` `:95` `:119` 五个助手全是 `UIAlertController` |
| **IOS-Y-05** | **`confirmDestructiveTyped` 当前零调用** | 全仓**没有任何调用点**（E2）。删除冷静期那条路（键入指定词）**没有上岗** | `Alerts.swift:29` 定义；调用点 0。`docs/redesign/DESIGN-DECISIONS.md:201` 记录原因（"位置被输应用锁密码替代"）（E3） |
| **IOS-Y-06** | **`pendingSettingsFocus` 三个写入方只有一个读取方** | 写入：`BackupStudioKit.swift:142`("backup") / `SecurityCenterView.swift:1280`("backup") / `LockKeeperApp.swift:1199`("diag")；读取：`ManagerFace.swift:226`，只认 `backup` / `diag` | 三处写入都注释"由设置页收到即开并清空"。**改造 ManagerFace 时这条链路极易断**（`ManagerFace.swift:68-72` 注释自陈"三域合并成单一面板之后消费端丢了"） |
| **IOS-Y-07** | **`interactiveDismissDisabled` 6 处** | 都是"进行中禁止下滑"：`AddKeyPage:63` `AddLockPage:81` `BackupStudio:524/958` `CredentialStudio:538/1112` | 换 sheet 容器时**这 6 条要跟着搬** |
| **IOS-Y-08** | **`trackScreen` 崩溃面包屑 13 处** | `HomeConsole:193/196/202/207/215` `ManagerFace:231/232/233`（+ `routeDestination` 的 `管理·\(r)` at `:76`）`MePage:166/189` `SecurityCenterView:999` `SecurityPage:257` | 改造导航时**新页必须补 `trackScreen`**，否则真机闪退查不到页 |
| **IOS-Y-09** | **玻璃必须走 `axGlass` 降级通道** | `axGlass` / `axGlassCapsule` / `axGlassCircle`（`AccessibilityKit.swift:269/274/281` HEAD），**不许直接写 `glassEffect`** —— 它内部处理「降低透明度 / 高对比 → 实底 + 描边」两条降级 | `ManagerFace.swift:10-17` 注释原话「自己写 glassEffect 会绕开这三条降级，等于给无障碍挖坑」 |

### 6.3 §6 的三条施工建议

1. **先跑一遍门槛清单再动任何卡片**：`grep -n "disabled(\|confirmationDialog\|interactiveDismissDisabled\|sudoSatisfied\|hasPrefix(mask)"` —— 上面 12 条红线全部落在这 5 个模式里。
2. **IOS-A-01（quickDestination 死路）与 IOS-S-08（AlarmCenterView 死页）必须先定性**：要么接上，要么删。**接线 = 加功能，删除 = 减 1500 行**，两者改造风险完全不同。
3. **§1.4 的 11 条"仅 B 通道可达"页面是合并 A/B 时的唯一硬约束**：合并方案必须先把这 11 个功能搬进 A 通道，否则一合并就丢 11 个功能。

---

## §7 未读到 / 无法验证（诚实边界）

| # | 事项 | 为什么 | 影响 |
|---|---|---|---|
| 1 | **任何 SwiftUI 渲染结果** | 本机 `swift / swiftc / xcodebuild` 全部 NOT FOUND（E1） | 所有"看起来会怎样"都是**读码推断**，不是实测。§2 里"视觉上暗一档/亮一块"必须上机核 |
| 2 | **Dynamic Type 实际表现** | 同上 | §2.1 的 `frame(height:20)` 裁切、§2.1 的 65pt 五列瓦片，都是**推断** |
| 3 | **`XPanel(kind:.hero)` 的 WT 渐变底在真机上的观感** | WT `Components.swift:124` 改成 `fill(XGradient.hero)`；§7.4 要求 HeroCard「高 220 / 标题顶 / 媒体中 / 说明底」 | 10 张 hero 卡全部变渐变，但**版式不是 HeroCard** → 可能"10 张渐变卡各长各的样" |
| 4 | **`.ultraThinMaterial` 在纯黑画布上的观感** | §6.2 警告「玻璃必须亮底/黑底各看一次」 | `SecurityCenterView.swift:424`(HEAD) 的磨砂挡片未实测 |
| 5 | **`tools/golden.js` 会重写 fixtures** | 任务卡明令不许跑（E3） | 我**没有**跑它。`tools/contrast.js` 也未跑（Lead 正在改） |
| 6 | **`android-app/` 侧** | 不在本任务范围（由 android-inventory 负责，`docs/GLASS/INVENTORY-ANDROID.md` 已存在，60051 字节） | — |
| 7 | **`XOpenArcRing` / `XConcentricRings` 的完整实现** | 我读到时 `Components.swift` 正在被改（1443 → 1652 行） | 这两个组件的行号与 API 可能已变，**按符号名 grep** |
| 8 | **`MePage` 是否还有新增 link** | 我读 WT 时是 20 条；文件从 358 → 360 行（+2） | §1.4 的 20 条可能变 21 条，**以 `grep -c "NavigationLink {" App/UI/MePage.swift` 为准** |
| 9 | **`XStatChip` / `XGlassTabBar` / `XGlassSurface` 的最终 API** | WT 新增，我读的是中间态 | 引用行号 `Components.swift:1465 / 1598 / 1545` 可能已变 |

---

## 附：本次清点跑过的命令（E1 可复现）

    # 闸门（只读，未写任何文件）
    node tools/destmap.js        → 目的地总数 = 19（扫 109 个 .swift）
    node tools/uicoverage.js     → 检查二 缝覆盖率 18/19，未挂缝 CredentialBinView；检查四/六/七/八 零命中；检查五 自绘容器预算 32
    node tools/reach.js          → View struct 共 90 个；从 RootView 可达 89；不可达 1：XLockBlade
    node tools/uxaudit.js        → A 112 / B 23 / C 5 / D 102 / E 1 / F 0；合计 243 线索
    node tools/dynamictype.js    → ✓ 无问题
    node tools/pagecraft.js      → 平均完成度 98.8%；未满分 1 个：StudioPage（该行为 .routes.json 旧数据，见 IOS-C-10）

    # 环境
    which swift swiftc xcodebuild java javac gradle kotlinc  → 全部 NOT FOUND

    # 结构统计（HEAD 803b6c8，注释剥离后正则计数）
    .sheet( 26 / .fullScreenCover( 1 / navigationDestination( 1 / NavigationLink( 35 / .popover( 0 / TabView 0
    XPanel 179(38 文件) / XPanel(kind:.hero) 10 / XRow 26 / XStatusPill 10 / XMetricTile 6 / XEmptyState 12
    XBusyButton 21 / XHairline 23 / XSkeleton 3 / XToggle 43 / XStatChip 0(HEAD)→2(WT)
    XCodeRing 1 / XDayClock 1 / XBatteryGauge 1 / XCycleRing 1 / XStepBar 1 / XSkewBar 1 / XOpenArcRing 0 / XConcentricRings 0
    buttonStyle: .plain 60 / XSecondary 28 / XPrimary 17 / .bordered 10 / PressableButton 6 / PlainButtonStyle 5 / PressableScale 3 / XDestructive 2
    .shadow( 14 / 渐变 14 / .ultraThinMaterial|glassEffect 4 / axGlass 7 / Divider() 15 / List { 1 / ScrollView 66
    navigationBarTitleDisplayMode: .large 12 / .inline 39
    .destined( 18（Destination 枚举 19 条）
    interactiveDismissDisabled 6 / trackScreen 13

    # 漂移核对
    git status --porcelain        → 25 个 M，其中 18 个 .swift
    git log --oneline -1          → 803b6c8

---

> **一句话给 Lead**：
> §1 的 **62 页**是地毯式前提（其中 **3 页不可达 + 1 个零构造点组件** 是硬事故）；
> §5 的 **IOS-A-01 / IOS-S-08 / IOS-A-05 / IOS-G-04 / IOS-C-11** 是本轮施工单里「改了收益最大」的五条；
> §6 的 **12 条红线**在动任何 sheet / 卡片容器之前必须先过一遍；
> **§0.4 列的是 Lead 已经修完的** —— 不要重复派工。
