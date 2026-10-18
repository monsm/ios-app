# PART 2 · 导航与信息架构（iOS）

> 作者：sp-nav（共享任务 task-4；Lead 骨架 + 实测数据合稿）· 唯一产出文件。
> 前置：`DECISIONS.md` 的 **D1 / D7 / D8 / D11 / D13** + `PART0-OVERVIEW.md` + `MASTER-PLAN.md` + `PART1-LOCKFACE.md` + `PART7-ACCEPTANCE.md`。
> 本文行号均为**实测**（2026-10-18，D:\aapk 工作副本）；拿不准的一律标「未证实」。路径相对 `ios-app/`（闸门必须在 `ios-app/` 下跑）。

---

## 0. 一句话结论

**门是封面层，4 个 Tab 是骨架，App Index 是目录。** 三者职责不重叠：
- 门（LockFace）：决定「你能不能进去」，不决定「进去之后看到什么」。
- 4 Tab：沿用 `Route.byHost` = 设备 / 凭证 / 记录 / 设置，**顺序与语义一个字都不改**。
- App Index：所有目的地的总目录，**是 sheet，不占 Tab 位**（D1）。

**三条数字结论**（机器复算，非估计）：
1. 目的地分层 = 4 根屏 + **51 一级** + **22 二级** = **77**（`destmap --json` 复算；口径见 §3）。
2. `SettingsView` 直呈 **32** 个目的地，是全仓最大入口（分组与落点冲突的真实来源，§3.3）。
3. 新增 2 个目的地后 **76 → 78**，需同步 6 处口径（§9）。

---

## 1. 层级总表（**已按实测校正**）

| 层 | 是什么 | 承载 | 谁决定可见 |
|---|---|---|---|
| L5 | 伪装态（`app.decoyMode`） | **现状：无独立全屏视图**；`decoyMode` 是状态位（`LockKeeperApp.swift:69`），守卫 9 处（`:100/140/142/145/148/161/199/244/249`） | `app.decoyMode` |
| L4 | 受限区复核 `GuestReauthGate` | 现有，以 `.fullScreenCover` 挂在 `mainTabs`（`LockKeeperApp.swift:1244-1249`） | `app.showGuestGate` |
| L3 | Sheets / fullScreenCovers | 现有：根层仅 2 个（`:1246` cover、`:1252` sheet）；其余散在各页 | 各自 binding |
| L2 | `MainTabs`（4 Tab） | 现有 `mainTabView`（`LockKeeperApp.swift:1128-1153`）；根容器是 **`Group`**（`:1312`） | 门开着 |
| L1 | `LockFace` 封面 | **新增** | 门关着 |

> ⚠ **两处必须纠正的旧写法**（本文件上一稿沿用了已删结构的名字，实测不存在）：
> ① **`AppLockView` 不存在**——启动门禁已于 2026-10-17 删除，`LockKeeperApp.swift:1319-1321` 原话「应用锁启动门禁已删…进 App 只分两种形态: 首启引导 / 主界面」；
> ② **`DecoyView` 不存在**（全仓 `App/` 下无 `struct DecoyView`）。
> ⇒ PART1 §1 的层级图里 `DecoyView` / `AppLockView` 两层**当前没有实体**，门面接线时**只新增 L1**，**不许**顺手把这两层“补回来”（那是新增第二套门禁，违反 §6-G9）。

**两条铁律**：
1. L2 **不许用 `if` 插入/移除**（会重建 `CredentialsView` 的 `State`，`LockKeeperApp.swift:1065-1068` 有专门注释）——用 `opacity` + `scale` 显隐，并配 `allowsHitTesting(false)`。
2. 门层**禁止直接写 `tabSelection`**。所有换页一律走 `requestRoute(_:)`（`LockKeeperApp.swift:168-175`），
   它内部含访客门禁（`:170` 的 `guestBlockedTabs.contains(r.tabIndex)`）。绕过它 = 绕过访客模式。

**接线动作（本 PART 唯一要求动 `LockKeeperApp.swift` 的地方）**：根容器 `Group`（`:1312`）外面**新增一层 `ZStack`**，把 `LockFace` 放在 `mainTabsChrome` 下面一层；
`OnboardingView` 分支（`:1313-1317`）**不套门**（一把锁都没有的人不演门，PART0 M2）。

---

## 2. 4 个 Tab 的根屏（「前门页」）

每个 Tab 的**根**都是「一屏只回答一件事」的页面（v10 渐进披露）。

### 2.1 统一骨架（7 区，4 屏同构）

| 区 | 行数 | 内容 | 约束 |
|---|---|---|---|
| A 大标题 | 1 | 系统 `.navigationTitle` | **禁止自绘标题栏**；四屏现状已是系统大标题（§2.3） |
| B 状态胶囊 | 1 行 | `VK().statusPill(text:systemImage:tone:)` | 颜色+图形+文字**三通道**（`docs/DESIGN-SPEC.md:9`） |
| C 副标题 | 1 行 | `Route.domainNote`（`Route.swift:63-70`）+ 当前锁名 | **不许读 `SCREENS[].sub`**（设计稿示意值） |
| D 主操作 | 1 个 | 每屏**只有一个** `accent` 主动作（`DESIGN-SPEC.md:88`） | 见 §2.2 |
| E 最近记录 | **≤ 3 行** | 该域已有列表前 3 条 | 数据源见 §12-U5 |
| F 域内跳转条 | ≤ 4 入口 | 本域最常用 4 个目的地 | 走既有 `.destined(.xxx)` 呈现缝 |
| G Tab 右上「全部」 | 1 个 44×44pt | 打开 App Index（§4） | `accessibilityLabel("全部功能")` |

**全屏预算**：同屏玻璃面 ≤ 3、玻璃不叠玻璃、单元素发光/渐变层 ≤ 2、Hero 条件提示行 ≤ 1 行（`design-system/aurora-lock/MASTER.md:62-65`）。

### 2.2 四屏逐屏线框（按现有实现填，不新造）

| Tab | 根屏文件（实测） | A 大标题 | D 主操作 | E 最近记录 3 行 | F 域内跳转（≤4） |
|---|---|---|---|---|---|
| 设备 | `App/UI/DeviceHomeView.swift:7`（body `:52`，NavigationStack `:54`） | `.navigationTitle(app.displayName)`（`:172`） | 「开锁」——**只导航** `requestRoute(.device)`；**不许新增第二个开锁面**（`LockKeeperApp.swift:1208` 既定判断） | 最近 3 条开锁结果 | 这把锁 `lockProfile` / 设备信息 `deviceInfo` / 全部锁 `lockOverview` / 固件 `firmware` |
| 凭证 | `App/UI/CredentialsView.swift:16`（body `:70`，`:72`） | `.navigationTitle("凭证")`（`:101`） | 「添加密码」`addPwd`（写锁端，走既有通路） | 最近 3 条凭证变更 | 凭证中心 `credCenter` / 回收站 `credBin` / 待补拉 `credQueue` / 家人与访客 `members` |
| 记录 | `App/UI/RecordsView.swift:20`（body `:294` → `recordsChrome:392` → `:393`） | `.navigationTitle("记录")`（`:317`） | 「看今天的记录」（`pendingRecordsDay`） | 时间线前 3 条 | 告警 `alarmCenter` / 统计 `stats` / 年度 `yearReport` / 导出 `exportCenter` |
| 设置 | `App/UI/SettingsView.swift:7`（body `:72`，`:74`） | `.navigationTitle("设置")`（`:116`） | 「安全中心」`securityCenter` | ⚠ **本屏不放 E 区**（设置不是流）→ 改为「最近改动 1 行」 | 安全中心 / 备份与恢复 / 诊断 / 无障碍 |

**根屏的状态行必须真实**（D13/S1）：只允许「已连接 / 未连接 / 连接中」+ 电量 + 上次开锁时间。
**不许**出现「已锁定」「在线」「门磁未合上」——没有实时源就不许标 live。

> ⚠ 记录根屏是 **`RecordsView`**；`App/UI/RecordsTimeline.swift:13` 里只有 `RecDetailSheet`（记录详情 sheet），**不是** Tab 根屏。
> ⚠ 四根屏**已是系统大标题**（0 处自绘、0 处 `.navigationBarTitleDisplayMode(.inline)`）⇒ 改造只动 B–F 区，**A 区一个字符都不改**。

---

## 3. 目的地分层（**口径已统一**）

### 3.1 三个口径，别混用

| 口径 | 含义 | 数量 | 依据（实测） |
|---|---|---|---|
| **D1 · Tab 根** | 4 个 `Tab(...)` 直接挂的内容视图 | **4** | `App/LockKeeperApp.swift:1131/1141/1144/1150` |
| **D2 · 一级（根屏直呈）** | 由 4 根屏**直接** `.sheet`/`.fullScreenCover`/`NavigationLink` 端出 | **51** | 设置 32 / 凭证 12 / 设备 8 / 记录 6（去重 51） |
| **D3 · 二级（再呈现）** | 由一级目的地（或中心页）再端出 | **22** | 10 个宿主文件，见 §3.2 |
| 合计 | 4 + 51 + 22 | **77**（缺 1 条见下注） | `node tools/destmap.js --json` 复算 |

> **注 · 77 vs 76 的口径差**：`autoCal` 的唯一呈现点是 `App/Core/AutoOpen.swift:661`（宿主 struct `AutoOpenSection`，不是 `...View`），
> 它既是计划落点 `destination/autoCal`、又是实测唯一入口 ⇒ 在“分层计数”里**计一次**，而在 `Destination` 台账里仍是 76 条之一。
> 差异来自“按呈现点分层”与“按 View 类型计目的地”两个口径，**不是漂移**。

> ⚠ 本文件上一稿写的「73/76 条是二级」**未复算**，与上表口径不同（那一稿把根屏直呈也算二级）。
> **以本节为准**：一级 51 / 二级 22。任一稿都不许在实施时当成“可以少摆几条”的理由——76 条一条都不能少（D7）。

### 3.2 二级目的地（22 条，实测宿主）

| 宿主文件 | 条数 | 二级目的地 |
|---|---|---|
| `App/UI/MemberCenterView.swift` | 5 | borrowSheet, memberArchived, memberDetail360, memberWizard, mergeMembers |
| `App/UI/BackupStudio.swift` | 5 | exportWizard, localFiles, migrationWizard, restoreWizard, webDAVStudio |
| `App/UI/SecurityCenterView.swift` | 3 | securityAudit, securityDestroy, securityPeek |
| `App/UI/StatsView.swift` | 2 | lockCompare, yearReport |
| `App/UI/Sheets.swift` | 2 | memberCenter, symptomGuide |
| `App/UI/BackupView.swift` | 1 | backupStudio |
| `App/UI/AchievementsView.swift` | 1 | capsuleCompose |
| `App/UI/ChangelogView.swift` | 1 | changeBatch |
| `App/UI/DiagnosticsView.swift` | 1 | diagReference |
| `App/Core/AutoOpen.swift` | 1 | autoCal（形状可疑，§12-U4） |

### 3.3 分组（`g`）与落点的冲突 —— 本 PART 最重要的一条

| `g` 分组 | 条数 | 现状主要入口 | 冲突条数 |
|---|---|---|---|
| 锁 | 15 | 6 条在**设置页**（deviceInfo / deviceManage / firmware / gateway / keychainHW / lockOverview） | 6 |
| 成员 | 10 | 3 条在设置页、1 条在 `Sheets.swift` | 4 |
| 关怀 | 10 | 7 条在**设置页** | 7 |
| 凭证 | 12 | 1 条在设置页（shareToAndroid） | 1 |
| 其余 5 组 | 29 | 与 `g` 同域 | ~5 |

**裁决（定死，不许实施时自由发挥）**：

| 方案 | 做法 | 判决 |
|---|---|---|
| A 按 `g` 强行搬家 | 把 23 条呈现点从设置页挪到对应域 | ❌ **判死**：违反 D10-6「不把 76 个目的地重排分组」+ 23 处回归面 |
| B 忽略 `g`，按现状落点分组 | 分组用实测宿主文件 | ❌ **判死**：违反 D7「分组与 `uiux-v3.data.js` 的 `group` 同源」 |
| **C（采用）** | **分组用 `g`；落点不动**。App Index 点一条 = 跳到**现状宿主所在 Tab**，再由现状呈现缝打开它 | ✅ 满足 D7 + 零 IA 改动 + `sheetcover` 语义正确（§5.3） |

**C 的唯一代价**：少数条目跨域跳转（设备域点「固件」→ 落设置页再弹 sheet）。这是**现状既有行为**，不是新引入的。
**必须做**：App Index 每行右侧显示归属 Tab 短标签（「设置」），**别让用户以为自己还在设备域**。

**分层规则（沿用上一稿，与本节口径不冲突）**：
1. 一级 = Tab 根（4 个）。2. 二级 = 从 Tab 根进一次可达。3. 三级 = 从二级再进（如「成员 360」从「成员」进）。
4. sheet/cover = 只读或短流程（详情、选择器、确认、向导第 1 步）。

> 数据文件里的 `parent` 只能当**语义**用，**不能**当导航层级——它的树结构早于当前 4 Tab（只有 3 个无父根 `deviceHome/records/settings`，PART5 §0-②）。

---

## 4. App Index（sheet 级，**非 Tab**）

### 4.1 三处触达与去重

| # | 入口 | 位置 | 语义 | 判据 |
|---|---|---|---|---|
| ① | 右上「全部」按钮 | 每个 Tab 根屏导航栏 trailing，44×44pt | 任何 Tab、任何访客态都可用（它是**目录**，不是受限区） | 新增，走 `.toolbar` |
| ② | 长按 Tab 项 | 既有 `.contextMenu(forSelectionType: Int.self)`（`LockKeeperApp.swift:1172-1204`）**追加一项** | 与既有 8 项并列，**不删不改**任何既有项 | 既有菜单每项只给 2–3 个**真做得到**的动作（`:1163-1165` 明写） |
| ③ | 下拉搜索 | 根屏列表下拉 → 进 App Index 搜索结果态（**同一视图**，参数 `initialQuery`） | 输入即搜 | 新增 |

**去重（硬要求）**：同一时刻**只允许一个 App Index 实例**。判据 = 单一 `Bool` `app.showAppIndex`（**不是每个 Tab 一份**），三处入口共用同一个状态位——
本仓“同一个量算两次”的老病灶，这里必须一开始就只有一个声明处。

### 4.2 数据来源（D7，**不许手写数组**）

- **唯一台账**：`tools/destmap.js`（它产出的 76 条 + 6 条呈现通道，见 §7）。
- **新增产物**：`App/Core/AppIndexData.swift`，由 `tools/destmap.js --emit` **一并生成**（D7 原话「由 `tools/destmap.js` 生成的分组数据驱动」。
  实现上 = 扩展 `--emit` 分支，新增第二份写盘；`Destination.swift` 的生成逻辑与全部判据**一个字不改**）。
- **生成内容** = 每组标题 + 该组目的地数组（标题取数据文件的 `t`，顺序取数据文件/台账顺序），**以及**每条的 `hostTab`（§3.3-C）。
- **禁止**在视图里写 `let groups = [...]` 这种字面量数组（v10 正是因此与数据类型漂移：v10 内联 78 项 vs 数据 76 项，D7 反例）。
- **搜索匹配**：标题 + 分组名 + **同义词表**（如「密码」↔「凭证」、「回收站」↔「删除/恢复」）。同义词表也放生成物里，随台账更新，**只增不改**。
- **失败即红**：若 `docs/preview/uiux-v3.data.js` 缺失或解析失败，`--emit` 必须 exit 1，**不许**悄悄生成一份空分组（那会让目录静默变空）。

**新增判失败检查（建议进 `tools/uicoverage.js` 检查九）**：`AppIndexData.rows.count == Destination.allCases.count`。
理由同 `App/Core/Destination.swift:2-3`：「少一条就是某套界面会缺一个页面而没人发现」。

### 4.3 id 连接规则（**已验证：76/76 零缺零多**）

`@
Destination case 名  ==  SCREENS[].id        （实测：仅数据 0 条、仅枚举 0 条）
DisplayName          =  SCREENS[].t
Group                =  SCREENS[].g         （9 组，顺序 = 文件出现顺序）
HostTab              =  呈现点所在 struct 回溯到 4 根屏之一（§3.3-C）
SearchTerms          =  t + g + 同义词表[case]
`@

**生成器必须内建自检**（两条）：
① 遍历 76 条，若 `SCREENS[].path` 含全角括号「（）」⇒ **只取 `›` 之后的次级路径**（实测 4 条带括号：`deviceHome`/`records`/`settings` 的主 Tab 标注、`credentials` 的「（原第 2 个 Tab，降为二级）」）；
② 若某条 `g` 与“呈现点所属根屏域”不一致 ⇒ **打印警告但不改分组**（§3.3-C）。

**分组顺序固定**（= 数据文件出现顺序）：锁(15) → 凭证(12) → 成员(10) → 记录(7) → 安全(10) → 数据(8) → 关怀(10) → 诊断(3) → 设置(1)。

### 4.4 交互

- 列表分组折叠（v10 的 `.grow` + `.sub`，展开 220ms；时长进 PART4 动效表，**不许就地写死**）。
- 搜索：输入即过滤；无结果用系统 `ContentUnavailableView`；命中时自动展开所在组。
- 点条目 → `dismiss()` 后 `requestRoute(...)`（顺序反了会切到被盖住的那层，`sheetcover.js` 专抓这个，见 §5.3）。
- 无障碍：行 `accessibilityLabel = "标题，在<域>"`；搜索框 `accessibilityLabel = "搜索全部功能"`。

---

## 5. 返回语义与 sheet / push 判据

### 5.1 现状（先知道再动手）

- **全仓 `NavigationStack(path:)` / `.navigationDestination(` = 0 命中** ⇒ 路径**未绑定**，返回靠系统隐式栈。
- `tools/sheetcover.js` 判据（**照抄，不自创**）：失败集 = `tabSelection = <数字>` 或 `.requestTab(<数字>)`（`tools/sheetcover.js:32`）；
  只判“确被 `.sheet`/`.fullScreenCover` 端出过”的 struct（`:12`、`:80-99`）；窗口 = 动作行**前一行 + 后六行**的**代码**（`:120-126`）；
  销号 `收摊口径：` 写在原始行（`:17`、`:125`）；**不判**间接呈现与 push 该不该退栈（`:19-20`）。
- **关键**：该闸门对 `requestTab` 与 `tabSelection` **一视同仁**（`:8-9` 原话「改成走 requestTab 就算修好了」是错的）。

### 5.2 sheet 还是 push（四问顺序判定）

| 序 | 问题 | 是 ⇒ sheet | 否 ⇒ push |
|---|---|---|---|
| 1 | “看一眼就回去”的面（设置 / 列表 / 详情）？ | ✅ sheet | ↓ |
| 2 | 多步流程（向导 / 采集 / 扫描）？ | ✗ | ✅ NavigationLink |
| 3 | 需要同时看到上一层内容？ | ✅ sheet | ↓ |
| 4 | 破坏性动作确认？ | ✗ | ✅ sheet + `DestructiveActionStyle` |

现状分布作先例：`sheet` 39 / `NavigationLink` 32 / `fullScreenCover` 1（`focusUnlock`）/ `Tab` 4（合计 76）。
App Index 属第 1 问 ⇒ `sheet`；门面设置页（`LockFaceSettingsView`）属多段设置 ⇒ `push`（从设置根屏进）。

### 5.3 App Index 那一跳的正确写法

`@swift
// AppIndexView 内：dismiss() 与换 Tab 必须在同一动作窗口内（窗口 = 本行前一行 + 后 6 行）
private func open(_ item: AppIndexItem) {
    dismiss()                                       // 先收摊：被盖住的那层 TabView 不切
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(220))  // 与 dismiss 动画同量级
        app.requestRoute(item.route)                // 唯一漏斗（guestBlocked 在这里判）
    }
}
`@

> 顺序反了会闪（Tab 先换、sheet 还盖着 ⇒ 用户看到旧内容被换）。**禁用** `tabSelection =`：`uicoverage` 检查四判失败（`tools/uicoverage.js:294-310`），且绕过访客门禁。

---

## 6. 不许破坏的行为（逐条给证据）

| # | 行为 | 约束 | 证据（实测） |
|---|---|---|---|
| G1 | 访客模式只放行 设备 / 记录 | 受限 Tab **不进层级树**（不是禁点、不是遮罩） | `LockKeeperApp.swift:1136` / `:1149` |
| G2 | 换页唯一漏斗 | 门层与 App Index 都必须走 `requestRoute` | `:168-175`（`:170` 判 `guestBlockedTabs`） |
| G3 | 受限集**派生**而非手写 | `AppState.guestBlockedTabs = Route.guestBlockedTabs`（`:97`）← `Route.guestBlocked`（`Route.swift:47`）← `guestBlockedTabs`（`:81-83`） | `Route.swift:12-15` 原话「两处同时失去指称对象 ⇒ **访客模式静默失去…整块的覆盖**，不崩、不报错」 |
| G4 | 锁落下即收回授权 + 落点收回设备页 | App Index 打开时也要收 | `revokeSessionGrants()` `:222-228`；`onChange(of: app.appUnlocked)` `:1369-1380` |
| G5 | 深链先挂起、解锁后落地 | 门开着时深链目标仍走 `pendingRoute` / `pendingMac`；**不新增 host** | `:119-120`、`:142`、`:144-149`；消费 `:1363`、`:1372` |
| G6 | 伪装态优先于一切 | `decoyMode` 为真时门不渲染；App Index 照旧可用（与现状一致） | `:69`、`:100` |
| G7 | 上次停留位置 | `rememberTab` / `restoreLastTab` 逻辑不变；**App Index 不写 `kf_last_tab`** | `:242-254`（`:253` 明写“恢复上次停留不拉门禁”） |
| G8 | 被 sheet 盖住时换 Tab 要先收摊 | App Index 的跳转必须先 `dismiss()` | `tools/sheetcover.js:32/120/126` |
| G9 | **不新增第二套门禁** | 受限区复核复用同一载体 `GuestReauthGate` | 启动门禁已删：`LockKeeperApp.swift:1319-1321`；载体 `:1244-1249` |
| G10 | 从小组件进来不演门 | 小组件是哑按钮（免费账号无 App Groups） | `CONSTRAINTS.md:22`、D13 |

---

## 7. Tab 栏外观（液态玻璃）

**结论：保留系统 iOS 26 原生 `TabView`，不自绘。**

理由（三条，全部实测）：
1. **自绘 = 判失败**：`fixtures/uicoverage/budget.json:2` 的 `selfDrawnContainers = 111`，闸门判据是 `cur > base ⇒ fail`（`tools/uicoverage.js:342`）——自绘 Tab 至少 +1，直接把整条闸门弄红。
2. **玻璃形状族只有一个入口**：`axGlass(_:)` / `axGlassCircle()` / `axGlassCapsule()`（`App/Core/AccessibilityKit.swift:388/393/400`）；
   就地写 `glassEffect` 会让“降透明度/增强对比要落回哪枚形状”与玻璃支分家（`:396-399` 原话）。
3. **系统旗标自动降级**：`GlassModifier` 已处理 `reduceTransparency || DS.Appearance.highContrast`（`AccessibilityKit.swift:427`），
   但它**只管自己包住的形状**——Tab 栏不是它的子视图，自绘就得自己重写一遍降级。

**写法与禁止**：

| 项 | 写法 | 禁止 |
|---|---|---|
| 容器 | 保留 `TabView(selection: $app.tabSelection)`（`LockKeeperApp.swift:1129`）+ `Tab(_:systemImage:value:)`（`:1131-1151`） | 不加 `.tabViewStyle(...)`（全仓 3 处 `.tabViewStyle(.page)` 是向导分页，与 Tab 栏无关） |
| 玻璃观感 | **不写参数**。若真机证实系统 Tab 栏未走液态玻璃，**也不自绘**，改为在 `mainTabView` 外挂一层 `axGlass` 背景且**先问 Lead**（预算） | 就地 `glassEffect`；自绘 `RoundedRectangle(cornerRadius: 29)` |
| v10 数值 | `h 58 / r 29 / blur 26 / sat 190%`（`docs/preview/v10.html:133-135`）**只作观感对齐目标**，不进代码、不进 `tokens.json` | 把 58 / 29 / 26 / 190 写进 `DesignSystem.swift` |
| 角标 | 保留三处 `.badge(...)`（`:1133/1142/1146`） | 改角标口径（凭证角标 0 时系统自动隐藏，`:1140` 已定） |
| 键盘 | 保留 `.keyboardShortcut("1"..."4")`（`:1062/1071/1080/1086`） | 挂到 `Tab` 上（Tab 是 TabContent 不是 View，`:1057-1058` 已踩过） |

> **上一稿的「只在一种情况下自绘」请按本节收窄**：门面层的悬浮胶囊形态属于 **`LockFace`**（iOS 独有，PART1 管辖），
> 它**不在 Tab 栏位置上**，也**不许替换系统 Tab**；如果真要叠，那层只走 `axGlassCapsule()` 且必须逐处留 `// @layout-allow VK豁免` 痕迹。

> ⚠ **未证实**：iOS 26 系统 `TabView` 是否自带液态玻璃、是否有 `tabBarMinimizeBehavior` 一类新 API——本仓 **0 处使用**（grep 全 `ios-app/` 仅文档提及）。
> 按 PART7 §0-2「不许凭印象写 API」：实施时先跑 `node tools/apisweep.js`（`tools/apisweep.js:1-11` 专抓臆造的小写成员名，曾抓到 `.listItemSpacing`），并到 Apple 一手文档核实后再落笔。

---

## 8. 尺寸与断点

| 机型 | 宽 | App Index 形态 | Tab 根屏 | 门面（锁体直径，D12） |
|---|---|---|---|---|
| iPhone SE(3rd) | 375pt | 全屏 sheet（`.presentationDetents([.large])`） | 单列；F 区改 **2×2** | `min(240, 375×0.68=255)` → **240** |
| iPhone 15/16 | 393pt | 全屏 sheet | 单列（基准机） | **240**（默认档） |
| iPhone Pro Max | 430pt | 全屏 sheet，行高 +2pt | 单列，卡片留白 +8pt | **240**（不再随宽度放大） |
| iPad 竖 | 820pt | **两栏 sheet**（左 9 组 / 右条目） | E 与 F 并排（2 列） | **272**（上限） |
| iPad 分屏 1/2 | ~360–500pt | 退回全屏 sheet（**与 SE 同形态**） | 单列 | `min(240, w×0.68)` → 240 |
| iPad 分屏 1/3 | <360pt | 全屏 sheet | 单列；F 区 2×2 | 240 |
| 横屏 | 高 < 宽 | 同宽档 | 同宽档 | 240；锁体中心 Y 从 46% 调到 44% |

**三条纪律**：
1. **不用宽度断点切视图结构**（iOS 无 CSS 断点）——用 `horizontalSizeClass` + `GeometryReader`；MASTER §1 已驳回 375/768/1024/1440 那套。
2. 数字一律 `.monospacedDigit()`（`docs/DESIGN-SPEC.md:66`：苹方数字是比例宽度，`9%`→`10%` 会让整块跳动）。
3. 中文正文下限 `.caption`（12pt）；标题最高 `.semibold`（苹方无 Bold，写 `.bold()` 会静默回退，`DESIGN-SPEC.md:64-65`）。

**禁止整屏硬值**（如 `.frame(height: 862)`）；一律 `GeometryReader` + 相对定位。

---

## 9. 76 → 78：口径同步清单（**漏一处就漂移**）

| # | 位置 | 现状 | 动作 |
|---|---|---|---|
| 1 | `App/Core/Destination.swift:2` | “生成时的目的地总数 = 76” | ✅ **自动**（重跑 `node tools/destmap.js --emit`） |
| 2 | `PART7-ACCEPTANCE.md` §2.1 / §2.3 | 76 / “76 变 78” | 人改：跑完闸门回填实测数 |
| 3 | `MASTER-PLAN.md` | 多处 76 | 人改（Lead 持有） |
| 4 | `PART5-DESTINATIONS.md` §0-① 统计表 | “合计 76” | 人改（sp-dest 持有） |
| 5 | 闸门硬编码 | **实测：`ios-app/tools/**` 里 0 处**（grep `76` 只命中 `deadscan.js:176` 与 `delsweep.js:46,107` 的**注释 / 文案截断长度**，与目的地数无关）；`ios-app/fixtures/**` 里 0 处 | **无需改**——总数是**算出来**的（`tools/destmap.js:342`、`:361`） |
| 6 | `docs/preview/uiux-v3.data.js:1` | 头注释“76 个目的地（与 `Destination.swift` 一一对应）” | 人改：加一行“2026-10-18 起新增 AppIndex / LockFaceSettings 两个目的地；数据文件仍只写功能页 76 条” |

**唯一新增的 2 个目的地**（与 PART7 §2.3 一致）：
① `AppIndexView`（sheet，§4）；② `LockFaceSettingsView`（push，PART1 §12 的皮肤 / 门面行为设置）。
**不新增第 3 个**（“搜索页”必须复用 `AppIndexView` 的搜索态，不许独立成目的地）。

---

## 10. 验收与闸门（`cd ios-app` 后跑）

| 闸门 | 本 PART 相关判据 | 阈值 |
|---|---|---|
| `node tools/destmap.js` | 6 正控 4 反控全过；总数 = 78 | 全过 |
| `node tools/uicoverage.js` | 检查一 漂移：枚举 = 台账；检查二 缝覆盖率 **基线 75/76**（`App/UI/ShareToAndroidView.swift` 内 `.destined(` = 0 命中）；检查四 裸写换页 **基线 1 处**（`App/UI/RecordsTimeline.swift:450`）；检查五 自绘预算 ≤ 111 | 只许变好 |
| `node tools/sheetcover.js` | App Index 那一跳 = 0 新增违规 | 0 |
| `node tools/dynamictype.js` | 新文案 ≥ `.caption`；触达 ≥ 44pt | 0 新增 |
| `node tools/apisweep.js` | 新增 `TabView` / `toolbar` / `presentationDetents` 相关修饰符逐个人工核 | 人工 |
| `node tools/citecheck.js` | **本文档**若被纳入扫描：`文件:行 + 摘录` 必须真实 | 0 失败 |
| `cd miniprogram-app && node tests/run.js` | 证明没碰协议 | 全绿 |

**结构验收（可判定）**：
1. `AppIndexData.rows.count == Destination.allCases.count`（§4.2 新增检查九）。
2. 三处触达**共用同一状态位**：grep 全仓只允许一处 `showAppIndex` 声明。
3. 受限区（`guestAreaLocked`）点受限条目 ⇒ `showGuestGate == true` 且 `tabSelection` **不变**（拉起复核页而不是切 Tab）。
4. 自绘容器计数**不上升**（`node tools/uicoverage.js --verbose` 看 top 文件）。
5. 门开着时 `mainTabs` 必须 `.accessibilityHidden(true)` + `.allowsHitTesting(false)`（PART1 §1）。
6. `Group` → `ZStack` 接线后 `CredentialsView` 的 `State` **不重建**（切锁后 `selPwds` 不残留，`LockKeeperApp.swift:1065-1068`）。

---

## 11. 文件清单与写入边界（多 AI 并行）

| 文件 | 动作 | 归属 |
|---|---|---|
| `App/Core/Destination.swift` | **生成**（`destmap --emit`） | 机器 |
| `App/Core/AppIndexData.swift` | 新增（`destmap --emit` 一并生成） | 机器 |
| `App/UI/AppIndexView.swift` | 新增 | L2 实施 AI |
| `App/Core/AppIndexSynonyms.swift` | 新增（同义词表） | L2 实施 AI |
| `App/LockKeeperApp.swift` | **受限改**：根 `Group`→`ZStack`、`showAppIndex` 状态位、`contextMenu` 追加一项、`onChange(appUnlocked)` 里收摊 | L2 实施 AI（**与门面接线串行**，MASTER-PLAN §7） |
| `DeviceHomeView` / `CredentialsView` / `RecordsView` / `SettingsView` | 受限改：B–F 区（`navigationTitle` 一行不动） | L2 实施 AI |
| `tools/destmap.js` / `tools/uicoverage.js` / `fixtures/uicoverage/budget.json` | **不许手改判据**；`budget.json` 仅在**下调**时改 | Lead 拍板 |

**禁止**：手改 `Route.swift` / `Destination.swift` / `fixtures/**` / `vendor/**` / 协议层 / 对比度断言表 / 上抬 `budget.json`。

---

## 12. 未证实 / 待复核

| # | 不确定 | 怎么定 |
|---|---|---|
| U1 | iOS 26 系统 `TabView` 是否自带液态玻璃、有无新 API | 跑 `apisweep.js` + 查 Apple 一手文档；**查不到就用系统默认，不许自绘**（预算红线） |
| U2 | 系统 Tab 栏在“增强对比 / 降透明”下的实际表现 | 真机开两个开关截图；不达标走 `axGlass` 包装并**先问 Lead**（预算） |
| U3 | App Index 跨域跳转的延迟（220ms 是否够） | 真机录屏；若闪帧改为 `dismiss()` 后由 `onDisappear` 触发跳转（窗口内仍有 `dismiss()`，闸门语义不变） |
| U4 | `autoCal` 的唯一呈现点 `App/Core/AutoOpen.swift:661`（struct `AutoOpenSection`，非 `...View`）是真入口还是形状可疑 | 实施前人工读该段；若确认死链按既有“零引用声明”口径处理（`deadscan.js` 顾问级），**本 PART 不做增删** |
| U5 | 4 根屏 E 区“最近 3 行”的数据源是否已有可用缓存 | `RecordsView` 有 `groups/allRows`；设备 / 凭证**未证实** |
| U6 | iPad 两栏 sheet 的分栏宽度 | 真机截图定稿；只对齐“同屏玻璃 ≤3、触达 ≥44pt”两条硬指标 |
| U7 | 上一稿「73/76 条是二级」的原始口径 | **未复算**，已由 §3.1 的 51/22 取代；若 Lead 有别的口径依据，以 PART5 主表复核后统一 |
