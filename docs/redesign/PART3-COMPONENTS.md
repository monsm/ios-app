# PART 3 · 组件与视觉语言（iOS）

> 作者：`sp-comp`（共享任务 task-5）· 本文件是 task-5 的**唯一写入物**；全程未改任何源码/配置/测试。
> 证据口径：★ = 我逐行读过源码并给出实测行号；◐ = 转引既有文档；○ = **未证实**，实施前必须回源。
> 上游裁判：`DECISIONS.md`（D1–D12 LOCKED）> 本文件；与闸门冲突时**先让闸门过**（PART7 §0）。
> ⚠ 引用 `MASTER.md` 必须避开 `10.1` —— 那张四 Tab 旧→新映射表已被作者在 `MASTER.md:221` 整体作废。
> 本文件取代 Lead 的 144 行骨架稿；**与骨架稿结论不同的 4 处**集中列在 §3.4，逐条给证据。

---

## 0. 结论先行（TL;DR）

1. 本仓的丑不是没玻璃（玻璃 2026-10-14 已统一），是**没有表面预算**——每个功能都要求一个可见表面，于是没有主角（`MASTER.md:11`）。PART3 的力气全部花在**减面**。
2. 五条预算（`MASTER.md:58-66`）本仓**可机检**：同屏玻璃面 ≤3 / 玻璃不叠玻璃 / 单元素渐变与发光层 ≤2 / Hero 条件行 ≤1 / 全 App 胶囊种类 ≤3。**现状全部超标**（§1）。
3. **圆盘 7 个装饰子视图：删 4、并 2、留 1**（§3）。判断口径只有三条：**信息 vs 气氛** / **有没有真实触发点** / **与 LockPlate 是否重复**。
4. 组件台账不许新造第二套：能走 VK 语法层的一律走（PART7 §0 铁律 2）。真正需要新建的是 **4–5 件**：LockPlate、LockFace、LockSwitcher、NoticeBar（SearchField 视 PART2 是否用系统 `.searchable` 而定，§2.3）。
5. 全 App 胶囊收敛到 3 类：导航胶囊 / 状态胶囊 / 筛选片（`MASTER.md:66`）。`StatusPill` 已是唯一状态胶囊实现（★ `DesignSystem.swift:794` → `VariantGrammar.swift:138`）；要收的是**筛选片**（★ `Capsule()` 实测 **127 处 / 22 文件**）。
6. 中文排版四条不是建议是闸门：★ `tools/dynamictype.js` 静态查 PingFang `.bold()`、固定高度、可点区 <44pt（`DESIGN-SPEC.md:107`）。
7. **锁体上的字符不许 bold**：PingFang SC 没有 Bold 字重，`.bold()` 静默回退 Semibold，小字号笔画粘连（`DESIGN-SPEC.md:64-65`）。锁体走**渐变填充 + medium**，层级差由**字号**承担（§4.1）。
8. 装饰层令牌只增装饰，**不进 `Palette`**（D4）：全部落在 `App/Core/LockFaceStyle.swift`（PART1 §12），不参与 `contrast.js` 语义对比，但**必须**接夜间降亮度（★ `DesignSystem.swift:261-264`）。

---

## 1. 表面预算（先治吵，再谈美）

### 1.1 五条硬预算与实测

| # | 项 | 预算 | MASTER 自述现状 | 本仓实测（★ 2026-10-18） | 判失败时怎么办 |
|---|---|---|---|---|---|
| B1 | 同屏玻璃面 | **≤3** | ≥5 | `axGlass` 三族调用点 **21 处 / 10 文件**（★，已排除定义文件 `AccessibilityKit.swift`） | 降级为实底 `surface`/`surfaceAlt`，不是删内容 |
| B2 | 玻璃叠玻璃 | **0** | 待测 | 未机检：尺子 `tools/uibudget.js` 尚未存在（EVIDENCE-DOCS §5.4） | 子元素撤 `axGlass`，只留外层面 |
| B3 | 单元素渐变/发光层 | **≤2** | 圆盘 ≥6、Hero 4 | 圆盘 ★ `UnlockDial.swift:444-540` 数出 **≥9 层**（§1.3） | 见 §3 删并清单 |
| B4 | Hero 条件提示行 | **≤1 行** | 5–6 行 | ◐ `MASTER.md:147-151`（DeviceHomeView Hero 区，逐条待 PART5 核） | 按 `MASTER.md:149-151` 默认线：影响能不能开锁的留，观感类下沉 |
| B5 | 全 App 胶囊种类 | **≤3** | ≥10 | ★ `Capsule()` 字面量 **127 处 / 22 文件**；最多三处 StatsView 29 / RecordsView 19 / DeviceHomeView 11 | 只留导航/状态/筛选三类，其余改 `PlateShape.tile` |
| B6 | 阴影预算（DESIGN-SPEC 加的一条） | 全 App **两级** | 三级 | Hero 卡 `DesignSystem.swift:994`、主按钮 `VariantGrammar.swift:323`、`VK().card { }` `VariantGrammar.swift:97` | 同屏只留一处强调阴影：**主按钮投影降为 0** |

> **口径警告（★）**：`MASTER.md:47` 记 `axGlass` 调用点 **24**（19+2+3），并把它定为 `uibudget.js` 反控的期望值（`MASTER.md:120-122`）。我实测 **21**。
> 两个数不是谁错，是**两个形状**：24 数三族之和（含定义文件与注释行），21 数真调用点。**先与尺子作者对齐，再改代码**（`MASTER.md:126`），否则「期望 24、实跑 21」会被判成尺子坏了。

### 1.2 分 Tab 违规清单与改法

| Tab | 主要违规 | 证据 | 改法 |
|---|---|---|---|
| **设备** | 玻璃面超预算：本文件内 **7 处** `axGlass*`（全仓 21 处的三分之一） | ★ `DeviceHomeView.swift:644 / 1231 / 1342 / 1350 / 1495 / 1503 / 1509 / 1648` 一带 | 只保留 `GlassEffectContainer`（:1503，注释在 :1495）内**一组**相邻玻璃；容器外全部改实底 |
| **设备** | 圆盘同元素叠 **≥9 层**（B3 超 4.5 倍） | ★ `UnlockDial.swift` 见 §1.3 | §3 全表执行，目标 **≤2** |
| **设备** | Hero 卡 4 层：渐变→纹理→柔光→黑纱 | ★ `DesignSystem.swift:958-983` | 纹理与柔光**二选一**（默认留柔光；`kf_hero_tex` 非空才挂纹理，★ `DesignSystem.swift:183-186`） |
| **设备** | 可点表面过多：Hero + 圆盘 + 快捷池 + 中央按钮 | ★ `LockKeeperApp.swift:1210-1214` | 按 `MASTER.md:203-208` 既有结论：快捷池整块废除，换圆盘下两枚大按钮（属 IA，PART2 落） |
| **凭证** | 筛选片与状态标签共用同一种 `Capsule()` | ★ `CredentialsView.swift`：6 处 `Capsule()` + 6 处 `variantPlate` | 筛选片统一走 `FlowLayout`（★ `DesignSystem.swift:63`）+ `PlateShape.capsule`；状态一律 `StatusPill` |
| **凭证** | 玻璃面落在列表行上 | ★ `CredentialsView.swift:2328` | 列表行**不许玻璃**（玻璃只做容器级）→ `variantPlate(surfaceAlt, .tile)` |
| **记录** | 胶囊最多的 Tab：19 处 `Capsule()` | ★ 计数 | 时间轴的类型片/状态片/时长片**并成一枚状态胶囊**，其余改 tile |
| **记录** | 筛选条 + 告警横幅同屏叠 | ◐ `MASTER.md:139` | 横幅约 10 行 → **1 行状态条**；4 排 chips → 单一筛选条 + sheet |
| **设置** | 17 节 + 工具节，无表面预算 | ◐ `MASTER.md:203-208`（判据仍有效，只避开 `10.1` 那张表） | 分组标题统一 `VK().sectionTitle`；折叠复用仓内既有的 10 处 `DisclosureGroup` 实例 |
| **门面（覆盖层）** | 门面本身是新增的大表面 | ◐ PART1 §3 | 门面**不计入 B1**（它不是卡片），但必须满足 B3：只有 `spec` 高光 + `bounce` 反光两层装饰；噪声算材质不算装饰 |
| **全局** | 开关与卡片样式不统一 | ★ `VariantGrammar.swift:414-426`（3 个 `VariantToggle` 重载）、`SettingsGroupChips.swift:54` | 开关一律 `VariantToggle`；chip 一律 `FlowLayout` |

### 1.3 圆盘层的逐行清点（B3 的证据）

★ `UnlockDial.swift` 的 `body`（:443-589）在同一 `ZStack` 里可同时挂 **9 个圆层**：

| 行 | 层 | 挂载条件 |
|---|---|---|
| :447-457 | 呼吸光晕（RadialGradient） | 恒在（reduceMotion 下只静止） |
| :459-462 | 静态外环（hairline） | 恒在 |
| :464-466 | 待机流光 `UnlockShimmer` | `connected` 且 `idle` |
| :468-475 | 成功冲击波（ok 圈） | `shock` |
| :477 | 呼吸环 `UnlockPulseRing` | `isBusy`（connecting / opening） |
| :479 | 雷达双圈 `UnlockRadarWave` | `state == .connecting` |
| :482-485 | 涟漪 `DialRipple` | `rippleKey > 0` |
| :487-489 | 充能刻度 `ChargeTicks` | `gestureMode == charge` |
| :514-520 | 按住进度环（trim，读 `holdProgress`） | `holdProgress > 0.001` |
| :523-530 | 围栏提示虚线环 | `armed` |

> 静态外环 :459 与 PART1 §3.3 的 LockPlate `groove`（铣进去的外圈）是**同一个结构**，属重复；删。

---

## 2. 组件台账（v10 元素 → 本仓组件）

### 2.1 台账规则（三条，先于表格）

- **R1 语法层优先**：页面**不许**自己画容器。卡片 `VK().card`（★ `VariantGrammar.swift:81`）、分组标题 `VK().sectionTitle`（:113）、状态胶囊 `VK().statusPill`（:138）、底衬 `variantPlate`（:261）、行内排版 `.vkFont`（:462）、开关 `VariantToggle`（:414）。**这是 PART7 §0 铁律 2，也是 uicoverage 检查八守的东西。**
- **R2 自绘必须留痕**：必须自绘的，紧邻上一行写 `// @layout-allow VK豁免 <类名>: <理由>`，类名只能取既有枚举（语义色填充 / 控件可识别性 / 输入框底衬 / 进度条实底 / 面板实底 / 刻度点 / 触达托管）。**不许自创类名**（PART7 §2.2 ⚠）。
- **R3 预算只许减**：★ `fixtures/uicoverage/budget.json` 当前 `selfDrawnContainers: 111`（PART7 §2.1，**基线本来就是红的**）。实施 AI **不许自行改** `budget.json`。

### 2.2 台账

| # | v10 元素 | 组件名 | 新建? | 尺寸与圆角 | 层级用法 | 何时**不许**用 |
|---|---|---|---|---|---|---|
| C1 | 白卡 `.card` | `VK().card` ★`VariantGrammar.swift:81` | 否 | 圆角 `DS.Radius.card`=22×k；内边距 `Space.l`=16；外边距 `gutter`=16 | 一次玻璃（`axGlass(DS.Radius.card)` :91）+ 极淡阴影（:97） | 列表行内、sheet 内、门面层；**不许卡里再套玻璃卡**（B2） |
| C2 | 行 `.row2` / `.grow` | `LabeledRow`（★ `DeviceHomeView.swift:2408`）+ `variantPlate(surfaceAlt, .tile)` | 否 | 行高 `DS.Metric.rowMinH`=44/60（★ `DesignSystem.swift:160-162`）；圆角 `Radius.tile`=18×k | 实底、零阴影、零玻璃 | 一行内不许两个主操作；一屏 >7 行必须分组折叠 |
| C3 | 状态块 `.st` | `MetricTile` ★`DesignSystem.swift:850` / `HeroStat` ★:897 | 否 | tile 圆角；padding H `Space.m`、V `Space.s+2` | 一级读数 `subheadline/semibold` + `text`，三级用 `textSub` | 读数不许染语义色当装饰；**一屏最多一个 Hero**（数据里只有 2 个 hero：`deviceHome` / `focusUnlock`） |
| C4 | 状态下标签 | `StatusPill` ★:794 → `VK().statusPill` ★:138 | 否 | `caption/medium` + 图标 `Icon.xs`=13；padding H `Space.s+2`、V `Space.xs+1`；`Capsule()` | 底色恒中性 `surfaceAlt`，语义走**图标形状 + 图标色**双通道 | 不许当按钮、不许当筛选片；一屏不许两个胶囊说同一件事 |
| C5 | 主按钮 `.act` | `PrimaryActionStyle` → `VK().primaryActionChrome` ★`VariantGrammar.swift:311` | 否 | `Radius.control`=16×k；最小高 `Hit.min+6`=50；字 `headline` | 同屏**只允许一处** `accent` 填充（★ `DESIGN-SPEC.md:88`） | 一屏两个主按钮 = 没有主动作；门面上不许用（门面主动作是锁体） |
| C6 | 次按钮 | `SecondaryActionStyle` ★:331 | 否 | 同 C5，最小高 44；底色 `tint.opacity(0.09/0.16)` | 与主按钮同组、成对出现 | 不许单独承担破坏性动作 |
| C7 | 破坏性按钮 | `DestructiveActionStyle` ★:350 | 否 | 同 C6，色 `Palette.danger` | **颜色 + 文字双通道**（★:349 注释即纪律） | 不许只靠颜色说危险 |
| C8 | 搜索框 `.search` | 优先系统 `.searchable`；需要常驻可见时才建 `SearchField` | 视 PART2 | 自建时：高 44、圆角 `Radius.control`、图标 `Icon.sm` | 实底 + 1pt `hairline` 描边 | ★ 全仓 `searchable(` **0 处**（实测）—— 两条路都没先例；**不许自绘**，除非 PART2 明确要常驻框 |
| C9 | 分组折叠 `.group` | 系统 `DisclosureGroup`（★ 既有 10 处）+ `VK().sectionTitle` | 否 | 标题 `headline`；内容缩进 `Space.l` | 折叠内**不许**再放玻璃面（B2）；<6 项全开，≥6 项收起 | 不许用在必须一眼看到的状态上（在线/电量/告警） |
| C10 | Tab 栏 | 系统 `TabView` + `Tab(_:systemImage:value:)` ★ `LockKeeperApp.swift:1131-1151` | 否 | 系统持有；角标 `.badge` 已有 2 处 | 4 Tab 语义不变（D1） | **不许自绘 Tab 栏**；不许绕过 ★ `:1136`/`:1149` 的条件摘除另做访客门禁 |
| C11 | 锁体 `.plate` | `LockPlate` | **是** | 直径 = `DS.Metric.dial` 映射 160→220 / 176→240 / 200→272，再 `min(…, screenW*0.68)`（D12 / PART1 §2） | 5 层，**全程只有 1 处发光**（§3.3） | 门后不许再出现锁体；不许出现第二个同款盘（PART1 §5：第二个开锁入口 = 第二套误开面）；Android 不做（D11） |
| C12 | 门面 `.door` | `LockFace` + `DoorSurface` | **是** | 中缝 50%；装饰缝 27%；门板厚度边 16pt（PART1 `2/§3.2） | `ZStack` 最底层（PART1 §1）；用 `opacity/scale` 显隐，**不许 `if`** | 深链/小组件/Siri/伪装态/访客**不展示**（PART1 §7）；不许当背景复用 |
| C13 | 字形 `.glyph` | 内嵌于 `LockPlate`（两条 `Path`，照抄 `v10.html:256-257`） | **是** | 60pt | 只闭环/开环两态，260ms 交叉淡入 | 不许当 App 图标；不许用文字渲染替代 |
| C14 | Hero 条件行 | `NoticeBar`（1 行） | **是** | 高 44；圆角 `Radius.tile`；图标 `Icon.sm` | 同屏**最多 1 行**（B4），其余下沉二级页 | 不许在 Hero 卡内再叠第二行（这条正是 B4 要治的病） |
| C15 | 多锁切换 | `LockSwitcher`（门牌选择器） | **是** | 胶囊高 32、触达 44 | 四 Tab 共享当前门上下文（◐ `MASTER.md:213` 默认线） | 不许做成第二个 Tab；切换锁**不重演开门动画**（M1） |
| C16 | 空态 | `EmptyState` ★:1024 / `GuidedEmptyView` ★:1067 | 否 | 系统 `ContentUnavailableView` | 图标 + 说明 + 主动作三件套 | 不许自绘空态插画（零位图纪律，D4/D10） |

### 2.3 新建件清单与共同约束

**确定新建 4 件**：`LockPlate`（C11）、`LockFace`（C12，含 `LockLeaf`/`DoorSurface`/`SeamGap`，PART1 §12 已列文件）、`LockSwitcher`（C15）、`NoticeBar`（C14）。
**第 5 件视 PART2 而定**：`SearchField` —— 若 App Index 用系统 `.searchable` 就不新建（省一处自绘预算）。★ 实测全仓 `searchable(` 0 处，两条路都没有先例，**不要两边都做**。

**共同约束**：成为目的地的必须挂 `.destined(...)` 并进 `Destination.swift` 台账（由 `tools/destmap.js --emit` 生成，**不许手改**，★ PART7 §2.3）；自绘处逐处 `@layout-allow` 留痕；每个视图 `body` ≤30 行（`type-check` 超时是本仓 R1 风险，★ `LockKeeperApp.swift:1056/1126/1155` 三处先例）。

---

## 3. 圆盘装饰层：7 → 3（治吵的主要抓手）

§1.3 的清点是**挂载层**（同一 ZStack 里最多 9 层）；本节是**代码里的子视图**处置。两者要一起看：
层数收敛 = 删子视图 + 收紧挂载条件。

| # | 子视图 | 位置 | 处置 | 理由 |
|---|---|---|---|---|
| 1 | `UnlockPulseRing` | `UnlockDial.swift:33` | **保留**（降为唯一呼吸层） | 它承载「已连接 / 就绪」的**状态语义**，是信息不是装饰 |
| 2 | `UnlockShimmer` | `:74` | **合并**进 `LockPlate` 的 spec 层 | 流光与镜面高光语义重复；合并后由指针位移统一驱动（PART1 §3.3 第 5 层） |
| 3 | `UnlockRadarRing` | `:109` | **删除** | 与呼吸环语义重复（都在表达等待），两层叠一起只是更亮 |
| 4 | `UnlockRadarWave` | `:131` | **删除** | 同上；且雷达隐喻在锁的语境下没有对应物 |
| 5 | `DialRipple` | `:157` | **删除**，改由按压反馈承担 | 波纹与 `scale(0.972)` 的按压反馈重复，保留其一 |
| 6 | `ChargeTicks` | `:192` | **保留** | 充能刻度是**功能**（进度可读），与 `p` 1:1 绑定 |
| 7 | `DrillTrace` | `:231` | **保留**（仅 hold 档） | 它已按档位分叉（`:237` 的 `swipeTrace`），非 hold 档不画 —— 这个判断是对的 |

**结果**：子视图 7 → 3；配合 §1.3 的挂载条件收紧，同一 ZStack 的可见层从 9 降到 **3**
（呼吸光晕 / 充能环 / 充能刻度），达到「单元素发光层 ≤2」的预算（呼吸光晕 + 充能环算两处，刻度不算发光）。

**并且**：删除的 4 个会让 `uicoverage` 的自绘预算**下降** —— 这正是本轮要的方向（R3）。

> ⚠️ 删之前先跑 `node tools/deadscan.js` 确认没有别处引用（它是零引用声明扫描）。

---

## 4. 中文排版四条（`DESIGN-SPEC.md` §4 的应用）

| 规则 | 原文 | 本设计的应用 |
|---|---|---|
| ① 苹方没有 Bold（最高 Semibold 600） | 写 `.bold()` 会静默回退到 Semibold，小字号笔画粘连 | 门上「前门」标题用 **semibold**，层级差靠字号（34pt vs 正文 16pt）承担 |
| ② 苹方数字是比例宽度 | `9%` 到 `10%` 会整块跳动 | 所有读数 `.monospacedDigit()`：电量、剩余天数、时长、计数 |
| ③ `.caption2`(11pt) 载不动中文 | 正文下限 `.caption`(12pt) | 门上提示语（轻点锁体）**最小 12.5pt**；v10 原型的 12.5px 正好落在这条线上 |
| ④ 中文不加 tracking | 汉字是等宽方块 | 门面中文**不加** `tracking`；只有全大写拉丁（如 BLE）才加 |

**门面专属例外**：锁体上的字形**不是文字**（是矢量 `Path`），中文排版规则不适用；
但门面下方的提示语、失败文案**必须**遵守上述四条。

### 4.1 排版硬数值（D15，用户已拍板，照抄不要重选）

| 位置 | 字号 | 字重 | 备注 |
|---|---|---|---|
| 门面锁名大标题 | **34pt** | semibold | 与门后 App 的 h1 同字号；`.bold()` 禁用 |
| 门后 App 的 h1 | 34pt | semibold | 同上（开门前后只有位置变） |
| 正文 | 16pt | regular | — |
| 次级说明 / 列表副行 | 14pt | regular | 用 `Palette.textSub` |
| 底部提示语 | **13pt**（`.footnote`） | regular | 不用 v10 的 12.5px |
| 分组标题（`VK().sectionTitle`） | 13pt | semibold | 全大写拉丁才加 tracking |
| 最小可用字号 | 12pt（`.caption`） | — | 中文下限，不许更小 |

| 项 | 裁定 | 令牌来源 |
|---|---|---|
| 左边距 | **16pt** | `DS.Space.gutter`（**不用 v10 的 26pt**） |
| 列表行高 | **44 / 60 两档** | `DS.Metric.rowMinH`（受 `kf_row_h` 控制，**不用 v10 的 52pt**） |
| 卡片圆角 | **22pt** | `DS.Radius.card`（**不用 v10 的 14pt**） |
| 读数 | `.monospacedDigit()` + 跟随 `kf_digit_font` | `DS.Metric.digitDesign` |
| 动态字体 | 跟随，**封顶到 accessibility2**（写法照抄 `LockKeeperApp.swift:1336` 的 `AXFlags.typeSize()` 精确档；**不要**写 `.dynamicTypeSize(...accessibility2)`） | — |

> **为什么行高不改**：v10 的 52pt 看着更舒展，但它是**全 App 密度**级改动，
> 会波及 76 个页面，并让已有的「舒适档 (60)」失去意义 —— 那是行为改动，不是视觉改动。
> **为什么圆角不改**：改 `DS.Radius.card` 会同时改掉全部页面，且让 `kf_radius` 的 soft/plump 三档失真。

---

## 5. 深浅双模对照表

| 元素 | 浅色 | 深色 | 理由 |
|---|---|---|---|
| 门面底色 | `#FBF9F5 → #F6F3ED → #EDE9E1` | `#141618 → #0F1113 → #0A0B0C` | **夜景门廊**，不是把浅色灰搬过去（`MASTER.md` §1 已判死） |
| 门面噪声 opacity | 0.30 | 0.18 | 深色下噪声更明显，要压 |
| 中缝暗部 | `rgba(26,15,3,.52)` | `rgba(0,0,0,.65)` | 深色下暗部要更实 |
| 中缝亮线 | 白 92% | 白 78% | 深色下白线过亮会刺眼 |
| 锁体玻璃面 | `#3A4044 → #080A0B` | **相同** | 锁体本来就是深色玻璃，两模式一致 |
| 锁体金属倒角 | 亮面系数 1.0 | 系数 0.82 | 深色下降峰值 |
| 门面文字 | `Palette.text`（0D1626） | `Palette.text`（F2F6FB） | 走语义令牌，不自定义 |
| 门面提示 | `Palette.textSub`（525E77） | `Palette.textSub`（9FACBE） | 同上 |
| 卡片（门后） | `Palette.surface` FFFFFF | 151D29 | 既有令牌 |
| 分隔线 | `Palette.hairline` D3DCE7 | 29343F | 既有令牌 |
| AMOLED | — | `kf_theme == black` 走 `amoledOverride` | 既有机制 |
| 高对比 | — | `kf_hc` 与系统旗标**并联** | 既有机制（`DesignSystem.swift:361-365`） |
| 夜间降亮度 | — | 22:00–06:00 装饰层峰值下调 | `DS.isNightDim`（`:259-264`），只降装饰不降文字 |

**验收**：深色模式整套截图重拍一遍；**不许**出现浅色灰直接搬进深色。

---

## 6. 装饰层新增令牌（**不加语义色**）

写进 `App/Core/LockFaceStyle.swift`，**不进 `Palette`**（D4）：

| 令牌 | 值 | 说明 |
|---|---|---|
| `surfaceTop/Mid/Bottom` | 见 §5 | 门面三停渐变 |
| `noiseOpacity` | 0.30 / 0.18（深） | 噪声强度 |
| `bevelBrightness` | 1.0（wood）/ 1.35（metal）/ 1.5（darkGlass）/ 0.7（frosted） | 倒角亮面系数（D6） |
| `shadowStrength` | 1.0 / 1.15 / 1.3 / 0.75 | 投影强度（D6） |
| `plateDiameter(screenW:)` | 见 D12 | **唯一换算点**（读 `DS.Metric.dial`） |
| `doorAngle` | 106° | 开门角度 |
| `doorSwing` | **新增到 `DS.Motion`** | 820ms / `(0.22,0.76,0.03,1)`，calm 档降级（PART4 §0） |
| `lightLeakRise` | 420ms | 中缝透光亮起 |
| `glyphSwap` | 260ms | 字形换态 |
| `chargeReset` | 180ms | 充能回零 |
| `nightDimFactor` | 0.72 | 夜间装饰层峰值系数 |

**禁止**：新增语义色、新增字体、新增圆角档 —— 三样都会让 397 条对比度断言与 6 套主题失效。

---

## 7. 每条验收

| 组件 | 验收（可截图/可计数） |
|---|---|
| 门面 | 同屏玻璃面 ≤3；单元素发光层 ≤2（数图层数即可判定） |
| 锁体 | 直径符合 D12 映射：**改设置里的「圆盘大小」，门外尺寸必须跟着变**（这是假开关的直接检验） |
| 中缝 | 4 倍放大截图，左暗右亮不对称可见 |
| 卡片 | 同屏卡样式 ≤2 种 |
| 胶囊 | 全 App 胶囊种类 ≤3（按形状+用途计数） |
| 圆盘 | 子视图 7 → 3；可见层 9 → 3；`uicoverage` 检查五计数**下降** |
| 排版 | 中文标题无 bold；所有读数 monospacedDigit；无中文 tracking |
| 深色 | 门面、锁体、文字全部重拍；无浅色灰搬进深色 |
| 夜间 | 22:00 后开锁，装饰层峰值明显下降且**文字不变暗** |

---

## 8. 与其他 PART 的接口

| 本文给的 | 谁用 |
|---|---|
| §2.2 台账（C1–C16） | PART5 的 76 行表（每条改动用这里的组件名） |
| §1 预算 + §3 删除清单 | PART7 的闸门检查（自绘预算应下降） |
| §6 令牌清单 | PART1（门面）、PART6（Android 同名令牌） |
| §5 双模表 | PART7 §5.3 验收第 11 条 |

**本文与 PART1 的分工**：PART1 说门面**怎么做**（几何/材质/状态机）；本文说门后的 App**怎么收敛**（预算/组件/排版）。两者重叠处（锁体、门面）以 PART1 为准。