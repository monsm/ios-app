# EVIDENCE-IOS — iOS UI 结构清单（grep 取证）

- 取证方式：`grep -n` 取 **声明行**，未通读任何大文件 body（仅按需读 LockKeeperApp.swift 三段行区间）。
- 范围：`ios-app/App/**`（Swift）+ `ios-app/tools/*.js`。
- 本文件为新建产物，**未修改任何源码**。
- 全部行号为当前工作树实测值。

---

## §1 大文件子视图清单（struct 名 + 行号，按行号排序）

> 这些文件内 **没有一行 `// MARK`**（`grep -c MARK` = 0），分区靠 `// ---------- 标题 ----------` 中文注释，见 §1.6。

### 1.1 App/UI/DeviceHomeView.swift（148KB）

| struct | 位置 | 用途（≤10 字） |
|---|---|---|
| `DeviceHomeView` | DeviceHomeView.swift:7 | 设备主页根视图 |
| `SyncTimeView` | DeviceHomeView.swift:2320 | 校时页（App synctime） |
| `BreathingGlyph` | DeviceHomeView.swift:2395 | 呼吸字形修饰器（private） |
| `LabeledRow` | DeviceHomeView.swift:2408 | 标签值行 |
| `FocusUnlockView` | DeviceHomeView.swift:2431 | 81 全屏专注开锁 |
| `UnlockGateView` | DeviceHomeView.swift:2492 | 250 二次开锁应用锁闸 |

### 1.2 App/UI/RecordsView.swift（213KB）

| struct | 位置 | 用途（≤10 字） |
|---|---|---|
| `RecordsView` | RecordsView.swift:20 | 记录页根视图 |
| `RowVM` | RecordsView.swift:96 | 时间线行视图模型 |
| `DayGroup` | RecordsView.swift:121 | 日分组模型 |
| `HlSeg` | RecordsView.swift:2118 | 检索高亮片段 |
| `LaneDay` | RecordsView.swift:2513 | 785 泳道日模型 |
| `FlashWash` | RecordsView.swift:2961 | 闪烁洗色层（private） |
| `AlarmKindsSheet` | RecordsView.swift:3335 | 565 告警类型多选 |
| `ActiveCredsSheet` | RecordsView.swift:3389 | 574 活跃凭证排序 |
| `OutWinSheet` | RecordsView.swift:3448 | 575 越界开门清单 |
| `GratitudeView` | RecordsView.swift:3500 | 1045 感谢清单 |
| `RecordsSampleGuideView` | RecordsView.swift:3582 | 808 记录空态引导 |

### 1.3 App/UI/SettingsView.swift（104KB）

| struct | 位置 | 用途（≤10 字） |
|---|---|---|
| `SettingsView` | SettingsView.swift:7 | 设置页根视图 |
| `SearchHit` | SettingsView.swift:266 | 页内搜索命中（private） |
| `IconOption` | SettingsView.swift:1119 | 备选 App 图标项（private） |
| `MechCounter` | SettingsView.swift:1385 | 机制计数行 |
| `DefendView` | SettingsView.swift:1408 | 布防页（外出/在家/撤防） |
| `TailgateView` | SettingsView.swift:1506 | 防尾随页（cmd24 档位） |
| `SafemodeIntroView` | SettingsView.swift:1549 | 安全模式说明页 |

### 1.4 App/UI/CredentialsView.swift（156KB）

| struct | 位置 | 用途（≤10 字） |
|---|---|---|
| `CredentialsView` | CredentialsView.swift:16 | 凭证 Tab 根视图 |
| `CredHit` | CredentialsView.swift:731 | 凭证搜索命中 |
| `HintRow` | CredentialsView.swift:1070 | 提示行（private） |
| `HistItem` | CredentialsView.swift:2685 | 历史条目模型 |

### 1.5 App/UI/UnlockDial.swift（976 行）

| struct | 位置 | 用途（≤10 字） |
|---|---|---|
| `UnlockPulseRing` | UnlockDial.swift:33 | 26 呼吸环（private） |
| `UnlockShimmer` | UnlockDial.swift:74 | 68/75 待机流光（private） |
| `UnlockRadarRing` | UnlockDial.swift:109 | 65 雷达波纹环（private） |
| `UnlockRadarWave` | UnlockDial.swift:131 | 65 雷达波（private） |
| `DialRipple` | UnlockDial.swift:157 | 73/1009 成功涟漪（private） |
| `ChargeTicks` | UnlockDial.swift:192 | 52 旋转充能刻度（private） |
| `DrillTrace` | UnlockDial.swift:231 | 59 手势演练层（private） |
| `PhaseBar` | UnlockDial.swift:271 | 三段进度细条（private） |
| `UnlockDial` | UnlockDial.swift:314 | 圆盘主视图（唯一非 private） |

### 1.6 分区锚点（代替 MARK，注释行长号）

| 文件 | 分区锚点（行号 → 标题摘要） |
|---|---|
| DeviceHomeView.swift | 317 设备切换 · 435 多锁状态行 · 710 状态卡 · 1024 待处理异常 · 1070 连接感知区 · 1186 摇一摇迷你面板 · 1235 开锁主控 · 1386 换机验证向导 · 1494 快捷操作 · 1679 最近开门 · 1859 安心夜打卡 · 1899 家庭关怀行 · 2061 派生数据 · 2319 校时页 · 2429 81 全屏专注开锁 · 2490 250 二次开锁闸 |
| RecordsView.swift | 42/550 包9 检索态 · 454 735 角标刷新 · 886 筛选 chip 行 · 1066 顶部情绪行 · 1491 顶部状态条 · 1567 时间线 · 2410 成员过滤 · 2496 785 泳道时间线 · 2590 数据 · 2856 详情翻页数据源 · 3331 告警类型面板 · 3388 活跃凭证 · 3447 越界清单 · 3499 感谢清单 · 3577 空态引导卡 |
| SettingsView.swift | 218 页内搜索 · 340 演练区 · 366 帮助区 · 410 门锁 · 582 安全 · 597 开锁 · 647 时间显示 · 705 靠近自动开锁 · 713 家人与钥匙 · 749 凭证整理 · 780 工具 · 797 无障碍 · 813 本机数据保护 · 859 外观 · 1114 备选图标 · 1223 纪念与成就 · 1235 维护提醒 · 1246 告警音分级 · 1312 关于 · 1407 布防 · 1505 防尾随 · 1548 安全模式说明 |
| CredentialsView.swift | 30 列表组织 · 183 顶部工具条 · 219 577 定位高亮 · 293 510 待下发横条 · 530 主列表 · 550 806 首录分流 · 760 365 下发状态步条 · 828 359 到期提醒 · 865 锁内存量/台账对账 · 906 密码段 · 1080 指纹段 · 1130 组内拖动排序 · 1242 355 成员视图 · 1296 统一行渲染 · 1572 347 编辑模式 · 1710 批量操作栏 · 1883 智能列表 · 1968 OTP 内联卡 · 2011 OTP 科普空态 · 2288 506 误删撤销条 · 2366 动作 · 2691 全局弹窗助手 |
| UnlockDial.swift | 1 手势模式单点 · 26 呼吸环 · 68 待机流光 · 101 雷达波纹 · 150 成功涟漪/涟漪结界 · 188 旋转充能刻度 · 222 手势演练层 · 269 三段进度细条 · 331 手势态 · 341 手势与动效族 · 352 开锁偏好 · 371 无障碍 · 718 手势围栏 |

---

## §3 证据表（一问一行 + 文件:行号）

| # | 问题 | 答案 | 证据（文件:行号） |
|---|---|---|---|
| 1 | 深链解析入口函数名 | `AppState.handleDeepLink(_ url: URL)` | LockKeeperApp.swift:124 |
| 1a | kf:// 校验与白名单 | `guard url.scheme == "kf"` + `AppState.deepLinkHosts[host]`；未知 host 直接 return | LockKeeperApp.swift:125-126 |
| 1b | 白名单定义 | `Route.deepLinkHosts` 由 `Route.allCases` 派生（device/credentials/records/settings） | Route.swift:73-77 |
| 1c | 其余受限参数 | `?k=`→`pendingRecordKey`；`?mac=` 仅 device 且本机有该锁才收 | LockKeeperApp.swift:127-132 / 133-141 |
| 2 | `pendingRoute` | 声明 LockKeeperApp.swift:119；写：142、BackupStudioKit.swift:146/1626/1648；消费 `applyPendingRoute` 146-148，调用点 1372 | LockKeeperApp.swift:119,142,144-148,1372 |
| 3 | `pendingMac` | 声明 LockKeeperApp.swift:120；写 140；消费 145（同在 applyPendingRoute 内） | LockKeeperApp.swift:120,140,145 |
| 4 | `pendingDiag` | 声明 LockKeeperApp.swift:361；写 1197、RecordsTimeline.swift:450；消费 SettingsView.swift:151-152；清 163 | LockKeeperApp.swift:361,1197 · SettingsView.swift:151-152,163 |
| 5 | `pendingCare` | 声明 LockKeeperApp.swift:364；写 BackupStudioKit.swift:1647；消费 SettingsView.swift:153-154；清 171 | LockKeeperApp.swift:364 · SettingsView.swift:153-154,171 |
| 6 | `DecoyView`（伪装）在哪、哪个布尔控制 | **不存在**：全仓无 `struct DecoyView`；伪装由 `@Published var decoyMode` 控制，且伪装入口已随启动门禁删除而不可达 | LockKeeperApp.swift:69（布尔）,1319-1320（删除拍板）· LockGuard.swift:54-55（isDecoy 判据） |
| 7 | `AppLockView` 在哪、哪个布尔控制 | **不存在**：全仓无 `struct AppLockView`（仅注释提及）；现存门面是 `GuestReauthGate`，由 `showGuestGate` 经 fullScreenCover 挂载；启动门禁布尔为 `appUnlocked` | LockKeeperApp.swift:1616,85,1246-1249,67,1319-1320,1614 |
| 8 | `guestBlockedTabs` 全部使用点 | 声明 LockKeeperApp.swift:97；使用 170、227、253；派生源 Route.swift:81-83，判据 Route.swift:47 | LockKeeperApp.swift:97,170,227,253 · Route.swift:47,81-83 |
| 8a | 视图侧摘层级的实际条件 | 用的是 `app.guestAreaLocked`（非 guestBlockedTabs 本身）：1136、1149 决定 Tab 是否入树；1227 决定访客复核按钮；99 定义 | LockKeeperApp.swift:99,1136,1149,1227 |
| 9 | `ExpressionTooComplex` / type-check 注释行 | 字面量 `ExpressionTooComplex` **全仓 0 命中**；实际措辞为「type-check 超时」/「unable to type-check … in reasonable time」，共 **47 行**，分布见下行 | 见下行 |
| 9a | 上述 47 行分布 | LockKeeperApp.swift 11（1056,1090,1126,1155,1274,1302,1326,1406,1456,1505,1529）· StatsView.swift 12（45,49,61,1343,1354,1361,1405,1409,1426,1431,1888,2478）· RecordsView.swift 12（186,196,236,299,311,314,752,1783,1824,2557,2568,2591）· SettingsView.swift 2（83,1328）· Sheets.swift 2（525,543）· BackupStudio.swift 2（2446,2510）· CredentialStudio.swift 1（247）· DiagnosticsView.swift 1（860）· FpOwnerPicker.swift 1（62）· MemberCenterView.swift 1（1060）· UnlockDial.swift 1（934）· VariantGrammar.swift 1（14） | 同左 |
| 10 | tools/ 下 MainActivity / Kotlin 相关闸门脚本 | `ios-app/tools/kotlinshadow.js`（读 MainActivity.kt，4 处断言）· `ios-app/tools/kotlinlocal.js`（说明只编 4 个非 UI 文件，MainActivity.kt 因 Compose/androidx 不参与） | kotlinshadow.js:104,107,152,163 · kotlinlocal.js:9 |

> 未证实/口径说明：`grep 'MainActivity' ios-app/tools` 仅命中上述 2 个脚本，其余 32 个 tools 脚本与 Kotlin/MainActivity 无关；本表行号均为 `grep -n` 原始输出，未做推断性补全。


---

## §2 根容器事实（App/LockKeeperApp.swift，只读三段行区间）

> 读取区间：1045-1062、1126-1161、1155-1212，另加 1210-1261、1261-1305 补足底栏与 chrome 层。
> **根容器里没有 ZStack**：`grep ZStack App/LockKeeperApp.swift` = 0 命中。层序由 `@ViewBuilder` 计算属性**顺序拼接**（隐式 tuple）+ 修饰符叠加实现。

### 2.1 根层序（外 → 内，逐层给行号）

| 层 | 承载体 | 行号 | 内容 |
|---|---|---|---|
| L0 | `RootView.body` | LockKeeperApp.swift:1305-1307 | 只有一行 `rootChrome` |
| L1 | `rootChrome` | LockKeeperApp.swift:1357-1403 | rootCore + `.onOpenURL { handleDeepLink }`(1363) + tabSelection 双 onChange(1364/1382) + appUnlocked onChange(1369) + linkState/unlockState 播报(1388/1397) + sensoryFeedback(1401) + preferredColorScheme(1402) |
| L2 | `rootCore` | LockKeeperApp.swift:1328-1353 | rootGroup + `.onDeviceShake()`(1332) + `.id(appearanceSeed)`(1334) + `.dynamicTypeSize`(1336) + `.saturation`(1338) + `.legibilityWeight`(1342) + `.animation`(1343) + `.overlay { SecurityWatermark }`(1346-1352) |
| L3 | `rootGroup` | LockKeeperApp.swift:1311-1324 | `Group`：`!Onboarding.allDone` → `OnboardingView`(1316)；否则 → `mainTabsChrome`(1321) |
| L4 | `mainTabsChrome` | LockKeeperApp.swift:1261-1277 | mainTabs + `.safeAreaInset(.top){ topBanners }`(1263) + `.modifier(MomentLayer())`(1270) + `.task { bootstrapOnce() }`(1271) + `.onChange(scenePhase)`(1276) |
| L5 | `mainTabs` | LockKeeperApp.swift:1156-1257 | mainTabView(1161) + `.contextMenu(forSelectionType: Int.self)`(1172-1204) + `.safeAreaInset(.bottom){ 底栏 + 访客复核 }`(1210-1242) + `.animation`(1243) + `.fullScreenCover { GuestReauthGate() }`(1246-1249) + `.sheet { AmbientOverflowSheet() }`(1252-1255) |
| L6 | `mainTabView` | LockKeeperApp.swift:1128-1153 | `TabView(selection: $app.tabSelection)`(1129) —— 最内层容器 |

> ⚠ 事实纠偏：LockKeeperApp.swift:1309 的注释写「四种形态（引导/伪装空壳/主界面/应用锁）」，但 1319-1320 已注明 **2026-10-17 拍板 A：应用锁启动门禁已删（伪装口令 390 随之不可达，一并移除）**，实际分支只有 2 个（1313 / 1318）。

### 2.2 TabView 声明位置与四个 Tab

| Tab | value | 声明行 | 内容视图 | badge / 条件 |
|---|---|---|---|---|
| 设备 | 0 | LockKeeperApp.swift:1131 | `deviceTabContent`(1059) | `.badge(handshakeDoneAway ? "✓" : nil)`(1133) |
| 凭证 | 1 | LockKeeperApp.swift:1141 | `credentialsTabContent`(1090 附近) | `.badge(CredentialOrg.expiringSoonCount)`(1142)；**包在 `if !app.guestAreaLocked`(1136) 内 —— 受限时不进层级树** |
| 记录 | 2 | LockKeeperApp.swift:1144 | `recordsTabContent` | `.badge(RecordSearch.unhandledAlarmCount)`(1146) |
| 设置 | 3 | LockKeeperApp.swift:1150 | `settingsTabContent` | **包在 `if !app.guestAreaLocked`(1149) 内** |

- 访客受限 Tab 的摘除方式：`if` 条件**不挂进层级树**（1134-1135 注释原话：「不是禁点、不是加遮罩」）。
- 底栏中央主按钮：`.safeAreaInset(edge: .bottom)`(1210) 内 `VStack`(1211)，**只导航不开锁**（1208-1209 注释）；条件 `app.tabSelection != 0, !app.decoyMode`(1212)。
- 访客复核按钮：1212-1239，条件 `app.guestAreaLocked`(1227)，动作 `app.openGuestGate()`(1230)，承载体 `GuestReauthGate`(1247)。
- 长按菜单：`.contextMenu(forSelectionType: Int.self)`(1172)，形参是 `Set<Int>`（1169-1171 记录原写法编译失败）。

### 2.3 Tab 内容视图抽取原因（type-check）

| 抽取物 | 行号 | 注释原文要点 |
|---|---|---|
| `mainTabView` | LockKeeperApp.swift:1126 | 「四个 Tab 的 TabView (从 mainTabs 抽出: 该表达式报 type-check 超时)」 |
| `mainTabs` | LockKeeperApp.swift:1155 | 「主 TabView + 长按菜单 + 底栏/访客复核 —— 从 appUnlocked 分支抽出: 该表达式报 type-check 超时」 |
| `deviceTabContent` 等四个 Tab 内容 | LockKeeperApp.swift:1056-1058 | 「从 body 内联的 TabView 里抽出: 该表达式报 type-check 超时」；并记录 **Tab 是 TabContent 不是 View**，`.keyboardShortcut` 只能挂内容视图 |
| `bootstrapOnce` | LockKeeperApp.swift:1279-1303 | 为非 type-check 原因抽取（变体不挂 mainTabsChrome 会静默跳过启动链），顺带保持 body 小 |
| `rootGroup` / `rootCore` / `rootChrome` | LockKeeperApp.swift:1309 / 1326 / 1355 | 均标注「从巨型 body 拆出」 |

