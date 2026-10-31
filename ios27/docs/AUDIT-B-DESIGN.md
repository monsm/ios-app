# AUDIT-B — 设计一致性与旧系统残留

审计对象：`ios-app/ios27/App/Design/V7/*.swift` vs `lock27-preview/v7/TOKENS.md` + `lock27-preview/v7/R1-device.html` / `R2-credentials.html` / `R3-records.html`
审计日期：2026-10-31 · 立场：默认"有遗漏"，只报有证据的问题
证据口径：代码行号 = `文件:行`；"实测" = 我对 `R1-device.png`（1206×2622 @3x）做像素测量，或对 HTML/CSS 逐值读数

---

## 0. 结论摘要

| 维度 | 结论 |
|---|---|
| V7 常量 vs TOKENS.md | **19 处不一致**，最大偏差 i 按钮 **Δ179.3pt** |
| TOKENS.md vs R1/R2/R3 | **12 组互斥数值**。TOKENS 自称"实测自参考图"，但与 R1/R2/R3 实现值对不上；V7 逐项只能选一边，选法不统一 |
| 硬编码（题目指定三类） | `Color(red:` 4 处（0 违规）、`.font(.system(size:` **0** 处、`padding(<数字>)` **0** 处 —— 但这三个口径**扫不到真正的绕过通道**：`V.F.sans(<数字>)` **52 处 / 12 文件** |
| 四根页是否用 V7 组件 | **是**（Door 26 / Keys 35 / Records 20 / Settings 43 调用点，Shell 1）。但 **33 个二级页仍是旧 Tokens/Ink/Panel**（995 处 `T.*`、396 处 `Ink.*`、118 处 `Panel(`） |
| 暗/亮 | V7 调色板 **100% 固定值**，浅色主题对四个根页**完全无效**；标签栏 `.ultraThinMaterial` 却跟随浅色 → 黑页上的浅灰胶囊 |
| 动态字号 | V7 全部字体 `Font.system(size:)` **固定 pt**（30 个字体常量 + 52 处裸数字）；```ScaledMetric` **0**、`relativeTo:` **0** → 大字开关对 V7 页面**无效**，而 AccessibilityScreen:62 明写"所有页面跟着放大" |
| 减弱动效 | V7 组件无动画；页面 `withAnimation` 9 处全部带 reduceMotion 守卫；2 处按压动画无守卫（旧组件） |
| VoiceOver | 组件标签基本齐；但 `VListRow` **吞掉 value**，3 个图表组件只有名词没有数值 |

**最重要的一条**：仓库自带 4 个设计闸门（tokens / dynamictype / contrast / a11y）**全部报 OK**（143 个 Swift 文件、0 处硬编码、"Dynamic Type 真生效"、"52 条对比度断言全部达标"），但它们**都不认识 `V.*` 令牌体系**。V7 是在闸门视野之外落地的 —— 见第 5 节。

---

## 1. 方法与可复现性

- 代码：全仓 `ios-app/ios27` 143 个 `.swift` 逐文件正则扫描 + 人工通读 V7 两个文件。
- HTML：R1/R2/R3 的 `<style>` 与内联 SVG 生成脚本逐值读取（本工程 CSS px = pt，画布 402×874）。
- 位图：对 `lock27-preview/v7/R1-device.png` 按 3x 采样，关键测量：
  - 环带中心线 r=121.5pt 上逐 0.1° 取色，判"背景"→ 可见缺口 bearing **165.3°–199.7°（34.4°）**
  - i 按钮圆盘 `#1D1D21` 连通域 → bbox **330.7–350.7 × 147.7–167.7 pt**（Ø20.0，中心 (340.7, 157.7)）
  - 顶部刻度 `#384064` bbox → **5.33 × 23.33 pt**（中心 x=200.8）
  - 标签栏在 y=825.8pt 行的亮区 → **76.0–325.7 = 250.0pt 宽**
  - 图表点线在 y=760pt 行的列 → x = **50.7 / 93.7 / 136.7 / 179.7 / 222.7 / 265.7**（间距精确 43.0）

---

## 2. 一、逐条数值比对

### 2.1 与 TOKENS.md 直接不一致（V7 代码 vs TOKENS.md）

| # | 项 | TOKENS.md | V7 代码（file:line） | 差值 |
|---|---|---|---|---|
| 1 | 图表绘图区高度 | y720–831 = **111pt** | `V.Chart.height = 125` · V7Tokens.swift:242 | **+14.0pt（+12.6%）** |
| 2 | 竖向点线间距 | **43pt** | `size.width * i / 5` = 282.4/5 = **56.48** · V7Components.swift:458 | **+13.48pt（+31%）** |
| 3 | 竖向点线首条位置 | 实测距绘图区左沿 **+14.4**（R1 绝对 50.7 − 左 36.3） | **0**（贴左沿）· V7Components.swift:458 | **−14.4pt** |
| 4 | 点线暗段 | **2.6px** | `dash: [1.2, 2.4]` · V7Tokens.swift:251 | −0.2px |
| 5 | 右侧双层刻度色 | **#4E4E50** | DoorScreen.swift:214 用 `V.C.text4` = **#6D6D6D** | Δ(+31,+31,+29)；且 `V.C` 内**没有** #4E4E50 令牌 |
| 6 | 左下 "0 时" | 有 | **无**（VAreaChart 无任何文字；DoorScreen 只画"高峰/平时"） | 缺失 |
| 7 | 迷你柱图轴标 | **11px #8E8E93** | **无**（VMiniBars 只有网格+柱，V7Components.swift:399-430） | 缺失 |
| 8 | 活动环组外径 | **153pt（38% 屏宽）** | `V.Ring.referenceOuter = 133.7` · V7Tokens.swift:226 | **−19.3pt（−12.6%）** |
| 9 | 活动环环宽 | **16.5pt（4.1%）** | `V.Ring.width = 14` · V7Tokens.swift:223 | **−2.5pt（−15.2%）** |
| 10 | 活动环环间 | **2.4pt** | `V.Ring.gap = 1.2` · V7Tokens.swift:224 | **−1.2pt（−50%）** |
| 11 | 活动环轨道色 | **#33080F / #2E4A12 / #16283A** | `color.opacity(0.22)` 压黑合成 · V7Components.swift:381 | 红 (56,12,21) vs (51,8,15)；绿 (42,54,22) vs (46,74,18) **G −20**；青 (22,52,51) vs (22,40,58) **B −7** |
| 12 | 红环渐变 | **(103,0,0)→(255,53,135)** | 纯色 `V.C.red` #FF375F · RecordsScreen.swift:189 | **完全没有渐变** |
| 13 | 起点方向箭头 | 红→ / 绿» / 青↑ | **无** | 缺失 |
| 14 | 分段环暗层 | **55% 亮度**（同色变暗） | `.opacity(0.55)`（半透明压卡底）· V7Components.swift:345 | 合成后偏亮：mint Δ(+18,+24,+25)、coral Δ(+25,+14,+10)、indigo Δ(+5,+9,+31) |
| 15 | 标签栏选中胶囊 | **60×49** | `selectedW = 56` · V7Tokens.swift:261 | **−4.0pt** |
| 16 | 脚注字号 | **16.5px / 行高 16.7pt** | `footnote = sans(12)` · V7Tokens.swift:101 | **−4.5**（按 pt 读）；TOKENS 自身 px/pt 混用，见 2.2 |
| 17 | 数字大值 22pt/700 环色 | 有 | **无令牌**（最近的 `titleC` 是 22/**600**）· V7Tokens.swift:90 | 缺档位 + 字重 −100 |
| 18 | 分组小标题 10.7/500 #8E8E93 | 有 | `VSectionLabel` 用 `F.section` = **20/700 #FFF** · V7Components.swift:651-652 | **+9.3pt**、字重 +200、颜色由灰变白 |
| 19 | 正文行高 23pt | 有 | `V.Page.bodyLine = 23` **声明但全仓 0 引用**；页面改用 `.lineSpacing(6)`（DoorScreen:153）→ 17pt 系统行高 20.3+6 = **26.3** | **+3.3pt/行** |

> 第 19 条旁证：`bodyLine` 在 V7Tokens.swift:304 定义后从未被引用（全仓 grep 仅 1 命中 = 定义处）。

### 2.2 TOKENS.md 与 R1/R2/R3 互斥 —— V7 只能对一边，且选法不统一

TOKENS.md 开头写"实测自 3 张 Apple 第一方参考图"，但 R1/R2/R3 是工程内实现基线，两边数值对不上。**这是设计一致性审计里最该报的一类问题：令牌文档和参考实现不同源。**

| # | 项 | TOKENS.md | R1/R2/R3 实现（或实测） | V7 选了 | 后果 |
|---|---|---|---|---|---|
| A | 主环缺口 | 163°–201°（38°） | R1 JS：`A0=208.4, A1=516.6`；**实测可见缺口 165.3°–199.7° = 34.4°** | TOKENS（弧端 201→163） | 圆头帽再吃 8.58°，V7 **可见缺口只剩 20.8°** → 比参考窄 **13.6°（−40%）** |
| B | 主环渐变 11 stop | 25,29,46 … 58,121,199 | R1 19 个 stop，**逐点比 TOKENS 亮 +9/+9/+10**（11 点全部同向） | TOKENS | 整条环**系统性偏暗 ~9/255**；282° 处 (58,121,199) vs (64,124,201) |
| C | 顶部刻度宽 | **4.3pt** | R1 CSS 5.3；**实测 5.33** | TOKENS | **−1.03pt（−19%）** |
| D | i 按钮位置 | **(325, 337)** Ø20.7 | R1 CSS (330.6,147.8)；**实测中心 (340.7,157.7) Ø20.0** | TOKENS | **Δ(−15.7, +179.3)pt** —— 参考图里它在环的**右上角**，V7 放到了环心右侧下方 |
| E | 标签栏宽 | **268** | R1 CSS 250；**实测 250.0** | TOKENS | **+18pt（+7.2%）**（R2/R3 才是 268） |
| F | 玻璃底色 | rgba(32,32,32,**.72**) | R1 **.62** / R2 **.60** / R3 .72 | TOKENS | 比 R1 不透明度 **+0.10** |
| G | 选中胶囊 | 60×49 | R1 **56×49**；R2/R3 60×49 | R1（56） | 与 TOKENS **−4pt**（V7Tokens.swift:11-12 有文字说明该取舍，但仍是偏离文档） |
| H | 分段环中心数字 | **21.3pt** | R2 `.ring1 .num` = **29px/700** | TOKENS | **−7.7pt（−27%）** |
| I | 活动环 153/16.5/2.4 | 见 2.1 #8-10 | R3：R=59.85/44.65/27.3、W=**14**、间距 **1.2** | R3 | 与 TOKENS 三项全不符 |
| J | 图表高度 | **111** | R1 `.chart{height:125}` | R1（125） | 与 TOKENS **+14** |
| K | 迷你柱宽 | **1.8 / r0.9** | R3 `.chart b{width:2.1px;border-radius:1.05px}` | TOKENS | **−0.3pt（−14%）**、圆角 −0.15 |
| L | 图表轴标 | **11px #8E8E93** | R3 `.xlab{font-size:8px;color:#86868C}` | **都没实现** | 三方差 3px + 色差 |

R1 内部自相矛盾（供追溯）：
- R1-device.html:9 注释写 `tabbar 268x57 … pill 60x49`，同文件 CSS:59 是 `width:250px`、CSS:61 是 `width:56px` —— 注释与实现差 18pt / 4pt。
- R1-device.html:6 注释写 `gap159..201`、`dot d18 @292deg`，而 CSS:32 是 `23.3px`、JS:135 是 `289deg` —— 旧版本残留。
- R1-device.html:125 注释写 `clockwise 200.5 -> 159.5`，JS 实际 `A0=208.4, A1=516.6`。

### 2.3 TOKENS.md 没有、V7 自创的值

| 项 | V7 值（file:line） | 问题 |
|---|---|---|
| `Gauge.baseOpacity = 0.72` | V7Tokens.swift:189 → V7Components.swift:89 "底环" | TOKENS/R1 都只有**一条**满亮环。加 72% 底环后，282° 处 (58,121,199) 实际渲染为 **(42,87,143)**，Δ(−16,−34,−56) |
| `fraction` 遮罩亮环 | V7Components.swift:92-97；DoorScreen.swift:100 传 `battery/100` | TOKENS 明写主环是"**角向连续渐变（非进度条）**"，R1 画满 308.2°、无进度语义。V7 让它变成进度环 → 电量 60% 时环只亮 60% |
| `F.section = 20/700` | V7Tokens.swift:102 | R1 `.sec` 是 **18/700**（+2）；TOKENS 无此档。于是 DoorScreen 同屏两种区块标题：:202 写死 `V.F.sans(18, weight: .bold)`、:256/:315 用 `V.F.section`(20) |
| `Tab.contentInset = 92` | V7Tokens.swift:266 | 无来源（57+19.7=76.7，多出 15.3 无推导） |
| 标签栏阴影 `radius: 12, y: 8` | V7Components.swift:606 | 无令牌；R1 是 `0 8px 24px`（**半径 12 vs 24**） |
| `V.C.text8 #A2A1A6`、`V.C.cardWarm #282322` | V7Tokens.swift:40,27 | 有 R2 支撑 ✓；但 R2 第三张卡是 **#282222**（R2:31），V7 无对应令牌，KeysScreen.swift:268 用 `.warm` 顶替 → Δ(0,−1,0) |

### 2.4 TOKENS 有、V7 完全没建模的元素

- 主环内盘径向渐变的 **60% 中间档**（R1 CSS:29 `#020E18 60%`）—— V7 的 `RadialGradient` 只用三色等距，无 stop 位置（V7Components.swift:73-79）。
- 活动环 **内盘青弧**、**绿环最亮段在弧头**（TOKENS 第 44-45 行）。
- 图表 **右侧双层刻度** 与 **左下 "0 时"**（TOKENS 第 52 行）。
- 迷你柱图 **轴标**（TOKENS 第 56 行）。

---

## 3. 二、硬编码扫描

### 3.1 题目指定三类口径（全仓 `ios-app/ios27`，143 个 .swift）

| 模式 | 命中 | 违规 | 说明 |
|---|---|---|---|
| `Color(red:` | **4** | **0** | V7Tokens.swift:18/21 是令牌层自身；ShareToAndroidScreen.swift:223/227 是 `CIColor(red:1,green:1,blue:1)` 生成二维码位图，不是样式 |
| `.font(.system(size:` | **0** | **0** | — |
| `.padding(<数字>)` | **0** | **0** | 全仓 `.padding` 一律走 `V.S.*` / `T.S.*` |
| `.cornerRadius(<数字>)` | 0 | 0 | — |
| `spacing: <数字>` | 37 | **0** | 37 处全是 `spacing: 0`（布局复位，tokens.js:61 已豁免） |

**按题目给的三条正则，一处违规都没有。** 这正是问题 —— 真正的绕过不走这三个模式。

### 3.2 真正的绕过通道：`V.F.sans(<数字>)` —— 52 处 / 12 文件

令牌层提供 `static func sans(_ size: CGFloat, weight:)`（V7Tokens.swift:84），于是"字号字面量"可以合法写进调用参数，既躲开 `.font(.system(size:` 正则，也躲开 dynamictype 闸门。

| 文件 | 行:字号 |
|---|---|
| Records/RecordsScreen.swift（**18 处**） | 139:11.5, 147:13, 232:11, 288:11, 297:17, 303:14.5, 307:28, 334:11, 357:10, 361:9.5, 394:15, 411:15, 426:15, 456:22, 501:15, 535:15, 633:15, 742:13 |
| Settings/SettingsScreen.swift（7） | 76:**34**, 102:11, 107:20, 123:11, 128:20, 390:15, 406:15 |
| Design/V7/V7Components.swift（**5**） | 115:11.5, 194:17, 625:16, 678:9, 701:15 |
| Keys/KeysScreen.swift（5） | 139:13.5, 239:19, 274:13.5, 285:56, 345:15 |
| Keys/CredentialStudioScreen.swift（4） | 241:18, 251:11, 263:15, 281:18 |
| Door/DoorScreen.swift（3） | 112:13, 202:18, 213:8.6 |
| Door/LockProfileScreen.swift（3） | 84:26, 91:20, 165:18 |
| Features/Shared/V7Extras.swift（2） | 20:15, 56:14 |
| Door/LinkSense.swift（2） | 172:15, 192:13 |
| Records/RecordsStudioScreen.swift（1） | 105:15 |
| Door/BatteryProfileScreen.swift（1） | 71:28 |
| Settings/BackupStudioScreen.swift（1） | 124:16 |

其中 **V7Components.swift 自己的 5 处**最刺眼：组件库声称"只引用 V.*，不写样式字面量"（V7Tokens.swift:14），却在芯片图标（:194 17pt）、动作按钮图标（:625 16pt）、卡头 chevron（:678 9pt）、列表图标（:701 15pt）、i 字形（:115 11.5pt）直接写数字。

### 3.3 其他硬编码

| 项 | 位置 | 值 |
|---|---|---|
| `.frame(width: 48)`（时间列宽） | RecordsScreen.swift:745 | 48pt，无令牌 |
| `.frame(width: 143)` | V7Components.swift:821 | 仅 `#Preview`，可接受 |
| `.opacity(<小数>)` | 17 处 / 8 文件（V7Components 5、RecordsScreen 4…） | 发光强度未令牌化：V7Components.swift:98 走 `glowOpacity`，:110 的 `0.8` 没走 |
| 令牌层内部 `Font.system(size:)` | V7Tokens.swift:85 | 1 处，服务 **30 个**固定字体常量 |

---

## 4. 三、四根页的 V7 覆盖与旧系统残留

### 4.1 四个根页确实在用 V7 组件（调用点计数）

| 组件 | Door | Keys | Records | Settings | Shell |
|---|---:|---:|---:|---:|---:|
| VCard | 3 | 7 | 13 | 7 | – |
| VChip | 2 | 4 | – | 2 | – |
| VListRow | 9 | 6 | – | 16 | – |
| VDivider | 8 | 10 | 1 | 13 | – |
| VActionButton | 1 | 2 | 3 | 3 | – |
| VStatPair | 1 | 1 | 1 | 1 | – |
| VCardHeader | – | 3 | – | – | – |
| VGauge | **1** | – | – | – | – |
| VSegmentedRing | – | **1** | – | – | – |
| VRingStack | – | 1 | 1 | – | – |
| VMiniBars | – | – | 1 | – | – |
| VAreaChart | 1 | – | – | – | – |
| VToggleRow | – | – | – | 1 | – |
| VFloatingTabBar | – | – | – | – | **1** |
| **合计** | **26** | **35** | **20** | **43** | **1** |

`VSectionLabel`（V7Components.swift:644）**全仓 0 调用点** —— 四个根页各自用 `.font(V.F.section)` 手搓区块标题（DoorScreen:256/315、KeysScreen:305、SettingsScreen:145），组件形同虚设。

### 4.2 旧系统残留（按文件统计 `V.*` vs `T./Ink.` 引用数）

- **纯 V7（无旧令牌）：19 个** —— DoorScreen(74)、KeysScreen(144)、RecordsScreen(194)、SettingsScreen(96)、LockSettingsScreen(42)、LockProfileScreen(60)、LockPortfolioScreen(40)、BatteryProfileScreen(37)、SafeModeScreen(21)、TailgateScreen(23)、MemberOpsScreen(59)、CredentialStudioScreen(75)、CredentialStudioParts(47)、RecordsStudioScreen(59)、BackupStudioScreen(43)、AccessibilityScreen(28)、ZotpScreen(29)、LinkSense(42)、ToastCenter(14)
- **纯旧令牌：33 个** —— HouseholdScreen(43)、HouseholdParts(69)、MemberDetailScreen(48)、MemberDetailParts(47)、MemberCreateScreen(18)、MemberCreateParts(31)、MemberArchiveScreen(31)、MemberMergeSheet(13)、KeyDetailScreen(45)、KeyCreateScreen(20)、KeyCreateParts(53)、KeyCalendarScreen(32)、KeysBits(51)、KeysParts(13)、MobileKeyScreen(30)、ShareToAndroidScreen(33)、RecordDetailScreen(62)、RecordExportScreen(83)、LockStatusScreen(49)、AddLockScreen(71)、GatewayScreen(59)、DefendScreen(52)、DFUScreen(23)、SyncTimeScreen(28)、QuickPoolEditSheet(17)、SecurityScreen(30)、AppearanceScreen(47)、BackupScreen(23)、AutoOpenScreen(24)、HardwareScreen(25)、ProtocolTestScreen(28)、AboutScreen(29)、SettingsParts(44)
- **混合：1 个** —— V7Extras.swift（V7:32 / 旧:1，旧引用在注释里）

全仓旧令牌引用总量（`App/` 下非 `Design/`）：`T.*` **995** 处、`Ink.*` **396** 处、`Panel(` **118** 处、`SectionLabel(` **97** 处、`FieldRow(` **34** 处、`StateDot(` **37** 处、`Reading(` **19** 处、`StatusLine(` **19** 处、`LedgerRow(` **2** 处、`Dial(` **0** 处。

### 4.3 具体残留点（用户可达路径）

| 路径 | 证据 | 后果 |
|---|---|---|
| 冷启动密码闸 | LockKeeperApp.swift:37 → `LockGateScreen`（:127-227）：`T.F.display(24)`(:146)、`Ink.plate`(:159)、`Ink.ink`(:147)、`PrimaryAction`(:172) | **每次冷启动第一屏是旧"石墨/铜锈仪表盘"，解锁后瞬间切成 v7 纯黑** |
| 只读试验横幅 | LockKeeperApp.swift:108-124：`T.S.s`、`T.F.icon`、`State.critical`、`T.S.gutter` | 常驻旧令牌 |
| 全局 tint | LockKeeperApp.swift:19 `.tint(Signal.base)` | 旧品牌铜锈色 **#47C9A6（暗）/ #1D6F5F（亮）** 不在 V7 调色板内；所有系统控件（TextField 光标、sheet 按钮、alert）仍用它 |
| 门页「成员」入口 | DoorScreen.swift:369-374 → `.dest(.household)` → Destinations.swift:14 → `HouseholdScreen`（纯旧，43 处） | **从 v7 门页点进去，整页变成旧仪表盘** |
| 门页「锁实况/锁设置/网关/校时/布防/固件」 | DoorScreen.swift:324/332/346/353/360/304 | 6 个二级页全部旧设计 |
| 设置页 16 条 `VListRow` 目的地 | SettingsScreen.swift:164/173/181/189/197/205/219/227/247/255/264/278… | 除 LockSettings 外全部旧设计（Security / AutoOpen / Appearance / Backup / Hardware / ProtocolTest / About） |
| 凭证详情 | KeysScreen.swift:363 → `KeyDetailScreen`（旧，45 处） | 列表是 v7 行、详情是旧面板 |
| 记录详情/导出 | RecordsScreen → RecordDetailScreen（旧，62 处）/ RecordExportScreen（旧，83 处） | 同上 |

即：**四个根页是新皮肤，往下钻一层基本全是旧皮肤**。33/53 个功能文件（62%）仍在旧系统。

### 4.4 旧系统里已经死掉/半死的代码

- `Dial.swift`（184 行，本设计的 signature 刻度盘）：`Dial(` 调用点 **0**。
- `Design/Components/SectionLabel`（旧）：97 处；新 `VSectionLabel`：0 处。
- `Design/Components/Ledger.swift`：仅 2 处 `LedgerRow(`（RecordDetailScreen、MemberDetailParts），但 `LedgerEntry` 模型仍被 DoorScreen/RecordsScreen 使用 → 模型留着、展示组件半废弃。

---

## 5. 四、暗/亮、动态字号、减弱动效、VoiceOver

### 5.1 暗色 / 亮色

| 事实 | 证据 |
|---|---|
| V7 调色板 **全部固定 RGB**，没有一条 `Color.dual` | V7Tokens.swift:19-80（`rgb(_:_:_:)` 返回不随 trait 变化的 `Color`） |
| App 支持浅色主题 | LockKeeperApp.swift:98-104 `preferredColorScheme` 返回 `.light`；SettingsScreen.swift:241-247「外观 · 跟随系统/浅色/深色」 |
| 旧系统本来是双套色 | Tokens.swift:148 `Color.dual(light:dark:)`，11 个令牌 × 2 模式 |
| 浅色下会发生什么 | 四个根页 `.background(V.C.bg)` = **#000000** 恒定、文字恒白 → **浅色主题对 v7 页面零效果**；但 VFloatingTabBar 的 `.ultraThinMaterial`（V7Components.swift:595）**会**跟随浅色变浅灰 → 纯黑页面上浮一条浅灰胶囊；Toggle、光标、sheet、alert 全部转浅色 → 半黑半白 |
| 对比度闸门只认旧令牌 | Gates/contrast.js:16-23 只解析 `Tokens.swift` 的 `Color.dual`，V7 的 60+ 个 `rgb()` 完全不在扫描范围 |

**实测对比度（WCAG 2.1，未达标项）**：

| 前景/背景 | 比值 | 字号 | 判定 |
|---|---:|---|---|
| `V.C.text4` #6D6D6D / 芯片顶 #262626 | **2.92:1** | 11pt 芯片标签 | < 4.5:1 ✗ |
| `V.C.text5` #48525B / #000（主环下"电量"） | **2.63:1** | 13.5pt | < 4.5:1 ✗ |
| `V.C.infoGlyph` #5D5D62 / #1D1D21 | **2.57:1** | i 字形 | < 3:1 ✗ |
| 图表轴标 #4E4E50 / #000 | **2.53:1** | 8.6pt | < 4.5:1 ✗ |
| `V.C.text2` #828282 / #000 | 5.46:1 | 17pt | ✓ |
| `V.C.text3` #8E8E93 / 卡 #232227 | 4.84:1 | 12pt | ✓（擦边） |
| `V.C.text7` #D2D0D0 / 卡 #232227 | 10.28:1 | 12pt | ✓ |

> 这些值是 TOKENS.md 从 Apple 参考图"实测"来的，复刻没错；但**参考图是视觉稿，不是可交付的对比度**。HIG 对 <18pt 文本要求 4.5:1，4 处不达标且全在四个根页首屏。

### 5.2 动态字号（固定 pt 是否不响应）

**是，完全不响应。**

- V7 的 30 个字体常量全部 `Font.system(size:)`（V7Tokens.swift:84-118），这是**固定字号**，不参与 Dynamic Type 缩放。
- 另有 52 处裸数字走同一通道（见 3.2）。
- `@ScaledMetric` 全仓 **0**；`Font.custom(_:size:relativeTo:)` **0**。
- RootView 唯一响应点是 LockKeeperApp.swift:42 `.dynamicTypeSize(settings.axBigText ? .accessibility2 : .large)` —— 只影响语义字阶字体（旧系统 `T.F.*`）与系统控件，对 `Font.system(size:)` **无效**。
- 更糟：它**覆盖了用户的系统设置**。用户在 iOS 设置里调大字号，App 仍强制 `.large`，除非打开 App 自己的"全局大字"。

**自相矛盾**：AccessibilityScreen.swift:62 的开关文案写着"动态字重放大到辅助功能档（Accessibility 2），**所有页面跟着放大**"。在 v7 页面上这句话是假的 —— 而四个根页正是 v7。

对照：旧系统 Tokens.swift:63-69 明确写了"全部走语义字阶，不写死 point size……否则 Dynamic Type 纹丝不动（那是最常见的一类'假适配'）"。**v7 迁移把这条纪律整条丢掉了。**

### 5.3 减弱动效

- V7 组件（VGauge / VChip / VCard / VSegmentedRing / VRingStack / VMiniBars / VAreaChart / VFloatingTabBar / VActionButton / VListRow / VToggleRow）**0 个动画** → 无违规，但也意味着 v7 的"进度/选中"没有过渡反馈。
- 页面级 `withAnimation` 9 处，**全部**带 `reduceMotion ? nil :`（RecordsScreen:116/123、KeyCreate*、RecordDetailScreen）。
- `.animation(` 11 处：9 处带守卫；**2 处没有** —— Primitives.swift:172 与 Dial.swift:174 的 `PressedButtonStyle`（旧组件，按压缩放）。属轻微，但 Gates/reducedmotion.js 报 OK 说明它只查"是否带 value"，不查 reduceMotion。

### 5.4 VoiceOver

| 组件 | 现状 | 问题 |
|---|---|---|
| VGauge | `.accessibilityElement(children:.ignore)` + label/value（V7Components.swift:139-141） | ✓ 但 DoorScreen:106-107 在 Button 上又覆盖成"开锁/dialPhase.word" → **电量数字不再被朗读** |
| VChip | label = "标题，值"（:227-228） | ✓ |
| VStatPair | `.combine`（:312） | ✓ |
| VSegmentedRing | label "分段环" + value 中心数字（:361-363） | 三段比例不朗读 |
| **VRingStack** | 只有 label "活动环"（:391-392） | **三条环的进度完全不可读** |
| **VMiniBars** | 只有 label "柱状图"（:427-428） | **24 根柱的数据完全不可读** |
| **VAreaChart** | 只有 label "面积图"（:526-527） | **曲线数据完全不可读** |
| **VListRow** | :736 label = title + detail，**不含 value** | 设置页 16 行、门页 9 行的右侧读数（"82%"、"已设"、"从未备份"）**对 VoiceOver 消失** |
| VCardHeader | 无 a11y 修饰，chevron hidden | 卡头「门锁 ›」**有箭头但没有点击动作**（KeysScreen:135/203/270）→ 假可达性 |
| VGauge 的 i | `Text("i")` + `.accessibilityHidden(true)`（:114-124） | 视觉上是标准 info 按钮（圆底+字形），实际**不可点、不朗读** |
| RecordsScreen 头像 | `.accessibilityHidden(true)`（:151） | 连"我"文本一起藏了；可接受但记录 |

---

## 6. 五、为什么这些没被发现：四个设计闸门全绿

实跑（`cd ios-app/ios27 && node Gates/<x>.js`，只读）：

```
tokens:      OK — 143 个 Swift 文件，0 处硬编码样式字面量
dynamictype: OK — 0 处写死字号，全部走语义字阶（Dynamic Type 真生效）
contrast:    OK — 52 条断言全部达标（解析到 11 个色令牌 × 2 模式）
a11y:        OK — 图标按钮都有 label，无 <44pt 可点区
```

四个闸门判据都只认旧体系，V7 在视野之外：

| 闸门 | 判据 | 为什么 V7 逃逸 |
|---|---|---|
| tokens.js:38-45 | 只认 `T./Ink./Signal./State.`；规则是 `.system(size:`、`.padding(\s*[0-9]` 等 | `V.F.sans(34)` 不含 `.system(size:`；`V.S.*` 全是合法标识符 |
| dynamictype.js:36-39 | 只抓 `.font(.system(size:`，统计 `T.F.` 次数 | 同上；V7Tokens.swift:85 的 `Font.system(size:)` 因缺 `.font(` 前缀也不被抓 |
| contrast.js:16-23 | 只解析 `Tokens.swift` 里的 `Color.dual(...)` | V7 的 `rgb(r,g,b)` 一个都解析不到；#48525B 的 2.63:1 从未被核算 |
| a11y.js:52-57 | 只匹配 `frame(width: 数字, height: 数字)` 成对字面量 | V7 全走令牌，无字面量 → 无命中；且没有"图表必须有数值标签"这类规则 |

**不是"闸门写错了"，而是"新体系接入时没有扩闸门"。** 结果是一份"0 违规"的绿色报告，掩盖了 52 处字号字面量、4 处对比度不达标、3 个图表组件无数据标签。

---

## 7. 六、优先级建议

**P0（用户可见 / 可达性）**
1. i 按钮位置 (325,337) → 参考实测 (340.7,157.7)：`V.Gauge.infoX/infoY`（V7Tokens.swift:182-183）差 **179.3pt**。
2. 主环缺口：`sweepDegrees` 322 未扣圆头帽 → 可见缺口 20.8° vs 参考 34.4°。改 `sweepDegrees ≈ 339.2` 或把端点外扩 8.58°。
3. `VListRow` 的 value 未进 accessibilityLabel（V7Components.swift:736）。
4. 动态字号：`V.F.sans` 改为 `Font.custom(..., relativeTo:)` 或语义字阶；否则删掉 AccessibilityScreen:62 的"所有页面跟着放大"。
5. 浅色主题：要么 V7 提供 dual 色板，要么在 `theme == .light` 时禁用/说明；至少把 `.ultraThinMaterial` 换成固定材质。

**P1（一致性）**
6. 图表点线间距 56.48 → 43（V7Components.swift:458），补 3 个轴标 + "0 时"。
7. 记录页卡片栅格：外边距 14.67→25、微卡间距 14.3→10.6、卡宽 372.66→352（V.S.cardGutter 需按页区分）。
8. `VRingStack` 在 `size: 88`（KeysScreen.swift:211）时第三环半径 7 < 半环宽 7 → **退化成实心点**（实测算式：88−14−4×15.2=13.2 → frame 被 max(14,13.2) 抬到 14，描边 14 覆盖整个圆盘）；参考 R2 是 r=13.5/w=11。
9. `VStatPair` 在 R2 语境（KeysScreen:215）应为 14/600，现在统一 17/600（+3pt）。
10. TOKENS.md 与 R1/R2/R3 的 12 组互斥值必须先定一个"唯一真源"，否则每次复刻都要重新二选一。

**P2（卫生）**
11. 33 个旧设计二级页的迁移排期；至少先迁 `HouseholdScreen`（门页"成员"直达）和 `LockGateScreen`（冷启动首屏）。
12. `VSectionLabel` 0 调用 / `Dial` 0 调用 / `V.Page.bodyLine`、`S.statValueGap`、`Metric.miniChartW`、`List.badgeSize` 无引用 —— 清理或接线。
13. 把 V7 纳入四个闸门（新增 `V.*` 感知 + V7 色板对比度断言）。

---

## 8. 未验证 / 边界

- 未编译、未在模拟器/真机渲染；所有"渲染结果"由代码语义推导（SwiftUI `Font.system(size:)` 不缩放、`.ultraThinMaterial` 随 trait 变化、`.opacity` 与"亮度"不等价）。
- 像素实测只针对 `R1-device.png`；R2/R3 只读 HTML/CSS，未做位图复核（其 CSS 与 JS 生成参数本身自洽）。
- 对比度按 WCAG 2.1 计算，未叠加 iOS 的 Increase Contrast / Reduce Transparency 行为。
- "旧系统残留"按 `T.*`/`Ink.*` 引用计数判定，未逐行确认每处都是样式用途（抽样：LockKeeperApp、DoorScreen、SettingsScreen 均属实）。
