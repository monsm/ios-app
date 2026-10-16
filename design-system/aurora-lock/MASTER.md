# Aurora Lock · iOS 原生 UI 重构方案（MASTER）

> **这份文件覆盖谁**：`design-system/aurora-lock/MASTER.md` 由 ui-ux-pro-max 技能自动生成后，
> 经人工核校**整体改写**为 iOS 原生口径。原生成稿是 Web/CSS 口径（Google Fonts、`cursor:pointer`、
> 375/768/1024/1440 断点、GSAP Flip），留在仓里会误导后续会话，故不留原文。
> 采信与驳回逐条记在 §1，不静默丢弃。
>
> 页面级覆盖写 `design-system/aurora-lock/pages/<page>.md`，存在即优先于本文件。

**目标**：精致 / 艺术 / 动效拉满，但全部落在 Apple 官方 SDK 语汇内，且不推翻本仓既有令牌与 28 道闸门。
**基调结论**：本仓的丑不是"没玻璃"（玻璃 2026-10-14 已统一），是**没有表面预算**——每个功能都要求一个可见表面，于是没有主角。

---

## 1. 技能输出采信表（采纳 / 翻译 / 驳回，逐条给理由）

| 技能给的 | 处置 | 理由 |
|---|---|---|
| Style: **Glassmorphism**（risk: conditional，requires contrast-text-4.5 / reduced-motion / visible-focus） | **采纳** | 与本仓既有 `axGlass` 同向；且它自带条件性风险标注，正好对上本仓第八十三批踩过的坑 |
| Pattern: **Real-Time / Operations Landing**（Hero→Metrics→How→CTA） | **驳回结构，采纳条款** | 这是落地页模式，原生 App 没有 CTA/转化。但其中两条是真金：①「telemetry 只有在有当前数据源时才可标 live，且必须带更新时间与 stale 态」②「为跳动读数提供暂停/隐藏/更新频率控制，停掉离屏工作，reduced motion 下渲染静态终态」 |
| Colors: `#0F172A` 底 / `#1B2336` 卡 / `#22C55E` 强调 | **不新增色板，只做映射** | 见 §4：技能这组深色值与本仓 `Palette` 深色档同族（`surfaceBase` dark = `0x151D29`）。新增色板＝重跑 contrast.js 全表，收益为零 |
| Typography: **Plus Jakarta Sans** + Google Fonts `@import` | **驳回** | 原生 App 用 SF Pro：自带 optical sizing / tracking 表 / Dynamic Type。引自定义字体要打包资源、中文字形仍需回退苹方（等于双份字体），且与本仓"除 App 图标外零位图"的资源纪律同源精神冲突。**精致靠 tracking + leading + weight 三件套，不靠换字体** |
| Motion: **GSAP Flip** + `expo.inOut` 500–800ms | **翻译成 SwiftUI** | Flip → `matchedGeometryEffect` / `.navigationTransition(.zoom(sourceID:in:))` / `.glassEffectID(_:in:)`。`expo.inOut` 500–800ms **驳回**：Apple 判据是 spring（response 0.35–0.45 / damping 1.0），且页面转场时长由系统持有，App 侧写死时长＝造"切了没反应" |
| Checklist: `cursor-pointer` / hover 150–300ms / 375–1440 响应式 | **驳回，换原生等价物** | iOS 无 hover 主路径、无 CSS 断点。替换为：44pt 触达、8pt 间距、safe area、Dynamic Type、icon-only 按钮必须带 `accessibilityLabel` |
| `--domain web` 原生条：44pt(iOS)/48dp(Android) 不许混成一个数、相邻触达 ≥8dp、深浅两套都要测且不许把浅色灰直接搬进深色、icon-only 必须有 accessible name | **全部采纳** | 与本仓 `DS.Hit.min = 44`（`DesignSystem.swift:149`）、`DS.Space.s = 8`（`:123`）已经对上，属**已满足**，方案里只需守住不倒退 |
| `--stack swiftui`：`accessibilityReduceMotion` 必检（Severity: High）、`NavigationStack`、`withAnimation` | **采纳** | 本仓 `NavigationStack` 已用于 22 个文件；reduceMotion 单一读点已在 `DS.Motion.tier`（`DesignSystem.swift:280`） |

---

## 2. 既有事实基线（机器证据，改动前必须承认这些）

| 事实 | 证据 |
|---|---|
| 部署目标 iOS **26.5** / Xcode 26.6 | `project.yml` `deploymentTarget.iOS: "26.5"` |
| 玻璃**已统一入口** `axGlass(_:)`，含降透明实底回落 | `App/Core/AccessibilityKit.swift:348`（`axGlass(_:)`）、`:353`（`axGlassCircle()`）、`:360`（`axGlassCapsule()`）：`reduceTransparency` → `Palette.surface` + `hairlineStrong` 描边；否则 `glassEffect(.regular, in:)` |
| `axGlass` 调用点 **24** 处，跨 **9** 个文件（19 `axGlass(` + 2 `axGlassCircle(` + 3 `axGlassCapsule(`，均排除定义文件本身） | `grep -rn -E 'axGlass(Circle\|Capsule)?\(' --include=*.swift App \| grep -v '^App/Core/AccessibilityKit.swift' \| wc -l` = 24 |
| ↳ **更正**：本节旧证据写 `AccessibilityKit.swift:358-409` 与"调用点 **35** 处（`grep -ro axGlass App/ \| wc -l`）"。**两处都是错的**：行号是凭印象写的（定义实际在 348/353/360，不是 358）；35 是 `grep -o` 数**匹配行**的结果，既把定义文件自己数进了尺子，也把一行里两次调用只算一次 —— 正是本仓"grep -c 数行不数调用点"那口坑。**35 不许再被任何判据当基线引用**（§6 反控已同步改 24）。 |
| 主表面 Card 已从实底改液态玻璃（2026-10-14） | `App/LockKeeperApp.swift:2044` 注释原文 |
| `GlassEffectContainer(spacing:)` 已在用 | `App/UI/DeviceHomeView.swift:1495` |
| 对比度机检 **36** 条断言 | `grep -c 'push(' tools/contrast.js` = 36（判据形状是 `push(mode, role, bg, minRatio, reason, fg, bg)` + `process.exit(1)`） |
| **形变转场为零** | `matchedGeometryEffect` 0 文件、`navigationTransition` 0 文件 |
| 既有动效资产 | `symbolEffect` 3 文件、`contentTransition` 4 文件、`MeshGradient` 1 文件、`Canvas` 7 文件 |
| Hero 卡当前叠 **4** 层 | `DesignSystem.swift:944-969`：渐变 → 纹理 → 柔光 → 黑纱 |
| 动效降级双闸已存在 | `DesignSystem.swift:280-288`：`AXFlags.reduceMotion` → calm；`BatteryCare.appLowBattery` → calm |

**由此得出的三条纪律**：
1. 新玻璃面**只准走 `axGlass`**，不许就地写 `glassEffect`（`AccessibilityKit.swift:356-359` 的注释已是此意，原文：「实底改玻璃时必须走这里，而不是就地再写一份 glassEffect —— 胶囊没有半径参数，塞进 axGlass(_:) 只能瞎猜一个 r，于是"降透明/增强对比要落回哪枚形状"就会和玻璃支分家。形状族只在这一处枚举里」。注：旧证据引的 `:358` **落在**这段注释内，那一条侥幸对；错的是 §2 把 `:358-409` 当成三个 `axGlass*` 的**定义**行段。）
2. 不新增色板、不新增字体、不新增圆角档——三样都会让 36 条断言表与既有 6 主题失效。
3. 任何新动效必须接进既有 `DS.Motion.tier`，**不许绕开** reduceMotion 与低电量两道闸。

---

## 3. 真正要改的三件事

### 3.1 构图预算（治"吵"）
现状：设备页同屏 5 种卡样式；圆盘叠 ≥6 层发光；全页 ≥10 类胶囊；Hero 条件行最多同叠 5–6 行。

**硬规则（可机检，见 §6 尺子）**：

| 项 | 预算 | 现状 |
|---|---|---|
| 同屏玻璃面 | ≤ 3 | ≥ 5 |
| 玻璃叠玻璃 | **0**（子元素不得再上 `axGlass`） | 待测 |
| 单元素发光/渐变层 | ≤ 2 | 圆盘 ≥ 6、Hero 4 |
| Hero 条件提示行 | ≤ 1 行，其余下沉二级页 | 5–6 行 |
| 全 App 胶囊种类 | ≤ 3（导航胶囊 / 状态胶囊 / 筛选片） | ≥ 10 |

### 3.2 圆盘：状态机跳变 → 连续物理量（治"死"）
现在按住是"计时到点→切状态"，那是脚本动画。改成：
- 充能进度 = **按压时长的连续值**，1:1 上屏（环 `trim`、光晕 `opacity`、盘体 `scaleEffect` 全部由这一个值驱动）；
- 松手即中断，**从当前呈现值起步**、把当时的变化率当弹簧初速回弹（不许从目标值起跳，会跳帧）；
- 阻尼取值：日常 `spring(response: 0.35, dampingFraction: 1.0)`；只有带手势动量的动作（松手回弹、甩动翻页）给 `dampingFraction: 0.82`；
- 音触同帧：刻度 `DS.Haptics.tick` → 触发 `.trigger` → 结果 `UINotificationFeedbackGenerator.success`（本仓已有这三档，只需保证与视觉同一帧）；
- 方向预示：按住时光向圆心收拢，成功时向外扩张——中间帧指向结果；
- **降级**：reduceMotion / 低电量 calm 档 → 退化为纯进度环 + 交叉淡入，**保留进度信息**，不是不动。

### 3.3 形变转场：从 0 到 1（治"平"）
`matchedGeometryEffect` 用量为 0，是"没有艺术感"的直接原因之一。
- 卡片 → 详情：`.navigationTransition(.zoom(sourceID:in:))` 或 `matchedGeometryEffect`，元素"化"进目标页而非推入；
- 玻璃面之间：`.glassEffectID(_:in:)` 让相邻玻璃在转场中融合；
- 相邻玻璃必须同处一个 `GlassEffectContainer` 才会融成一体（`DeviceHomeView.swift:1487` 注释已写明）；
- 读数换值继续用 `.contentTransition(.numericText())` + `.monospacedDigit()`（已有，扩到全部会变数的读数）。

---

## 4. 色彩：不新增色板，只做映射

技能给的深色组与本仓 `Palette` 深色档同族，**结论是"不用换色，只用换构图"**：

| 技能值 | 本仓既有令牌 | 处置 |
|---|---|---|
| `#0F172A` background | `canvasBase` dark `0x070B12` | 保留本仓（更暗，AMOLED 档已在）；不抬亮，抬亮＝重跑 36 条断言 |
| `#1B2336` card | `surfaceBase` dark `0x151D29` | 视为等价，不动 |
| `#22C55E` accent(状态绿) | `ok` dark `0x4ADE80` | 用既有 `ok`；开锁成功态取 `ok`，不引新绿 |
| `#94A3B8` muted fg | `textSub` dark `0x9FACBE` | 视为等价，不动 |
| `#EF4444` destructive | `danger` dark `0xF87171` | 用既有 `danger` |

品牌强调色继续走 `kf_accent` 六套主题 + `CustomAccent` 派生管线，**一个色号都不新增**。

---

## 5. 排版：SF Pro + 三件套（驳回自定义字体）

| 角色 | 字号/字重 | tracking | leading |
|---|---|---|---|
| 锁名（页面主标题） | 28–34pt / bold | **−0.024em**（大字必须紧排） | 1.05 |
| 区块标题 | 13pt / semibold | −0.01em | 1.2 |
| 读数数值 | 17pt / semibold + `.monospacedDigit()` | −0.03em | 1.1 |
| 读数标签 | 10–11pt / regular | +0.03em（小字要放开） | 1.3 |
| 正文 | 13–15pt / regular | 0 | 1.5 |

规则：tracking **按字号给**，一个全局值必错一处；层级由 weight + size + leading **三件套**共同建立，不靠单加字号；全程 Dynamic Type，间距用相对量，字号变大不许破版（本仓 `tools/dynamictype.js` 已在管这条）。
发丝线用**渐变淡出**（两端 transparent）而不是 1px 实线贯穿——这是"精致"最便宜的一处。

---

## 6. 验收尺子（正控 + 反控 + 真树，缺一不可）

新增 `tools/uibudget.js`，判 §3.1 那张预算表。**尺子自身必须被验证**：

- **正控**：fixture 里放一个"玻璃套玻璃"与一个"Hero 6 行条件提示"的样例，**必须被检出**；检不出＝尺子坏了，按 0 条断言处理。
- **反控**：现有 **24** 个 `axGlass*` 调用点（9 个文件，见 §2 更正行；旧值 35 是数行的产物，作废）中合规的**必须不报**；报了＝尺子在数形状不是数违规。反控的**期望值就是 24**，跑出来不是 24 说明尺子扫的范围或形状错了，先修尺子再谈违规数。
- **真树注入**：对 `App/**/*.swift` 全量扫，报数必须**声明范围与形状**（例如"设备页 3 处玻璃面，其中 1 处嵌套"），不许只写"违规 0"。
- 注意既有坑：`grep -c` 数的是**行**不是调用点；`grep -v '//'` 会吃掉行尾注释；判据要下沉到公共脚本，别在口径注释里抄复算命令的匹配串（会把期望值顶高）。

`tools/contrast.js` 需**增补**玻璃面上的文字断言（现 36 条按纯色面与渐变端点算，玻璃面要按"最坏背景"算）：
- 待增：6 主题 × 明暗 × AMOLED × 反转 下，玻璃面上 `text` / `textSub` / `onAccent` 的 ≥4.5:1；
- 已知风险：第八十三批"白字压洗白底"实测 3.74:1 —— 玻璃化后**同一形状会再来一次**，必须先写断言再改代码，不是改完再补。

---

## 7. 施工批次（每批独立可编译、独立可回退；本机无 Xcode，全部靠 CI 验）

| 批 | 内容 | 风险 | 需先拍板 |
|---|---|---|---|
| **B1** | `DS.Motion` 增 `.physical`(1.0/0.35) 与 `.momentum`(0.82/0.4) 两档，接进既有 tier；`axGlass` 增 `.interactive` 变体；新增 `DS.Budget` 常量 | **零行为改动**，纯新增 | 否 |
| **B2** | `UnlockDial.swift`：连续按压进度 + 速度接管 + 双闸降级；发光层 ≥6 → 2 | 中：核心交互，须真机验手感 | 否 |
| **B3** | `DeviceHomeView.swift`：Hero 4 层 → 2 层；条件行 5–6 → 1；胶囊归并；槽位默认序 hero→dial→quick | **高：砍首屏可见性** | **是**，见 §8 |
| **B4** | 形变转场：`.navigationTransition(.zoom)` / `matchedGeometryEffect` / `.glassEffectID` | 中：与 GlassEffectContainer 边界交互 | 否 |
| **B5** | `RecordsView` 横幅 ~10 行 → 1 行状态条、4 排 chips → 单一筛选条 + sheet；`CredentialsView` 头部三行工具 → 一行 | 中 | 部分（哪些筛选必须常驻） |
| **B6** | `tools/uibudget.js` + `contrast.js` 玻璃断言增补 | 低 | 否 |

B1、B2 是纯增益，不砍任何功能可见性，可以先做。B6 的 contrast 断言**必须排在 B3 之前**（先立尺子再改代码）。

---

## 8. 待拍板（B3 的前置，我不替你决定）

Hero 卡当前可同时叠 5–6 行条件提示（「已守护 N 次」「今日已备份/多日未备份」「链路待验证」「该喂电了」「低温季续航」）+ 里程碑头像圈 + 翻面卡。新构图只留 **1 行告警条**，其余下沉二级页。

**默认线**（不回话即按此施工）：影响"能不能开锁"的留首屏（电量、告警、链路待验证）；只影响观感与情绪的下沉（里程碑头像圈、守护次数、节日装饰、翻面卡）。

---

## 9. iOS 27 SDK：待核，不当既成事实

二手来源称"iOS 27 SDK 下 `UIDesignRequiresCompatibility` 失效（Liquid Glass 强制）"与"新增系统级玻璃透明度滑块"。**这两条我没有从 Apple 一手页面核实**，落地前必须抓官方 release notes 复核。
一手核实过的只有 WWDC26 session 269 页面上的 API 名：`.toolbarMinimizeBehavior(.onScrollDown, for:)`、`.topBarPinnedTrailing`、`.visibilityPriority(.high)`、`ToolbarOverflowMenu`、`.reorderable()` + `.reorderContainer(for:)`、`.swipeActionsContainer()`、`@State` 改宏、`ContentBuilder`、`.asyncImageURLSession(_:)`。
建议策略：**最低部署版本保持 26.5，用 27 SDK 编译，27 独有 API 加 availability 分支**；前提是 CI 镜像换到带 Xcode 27 的（本仓唯一验证途径）。若换镜像成本高，B1–B6 全部只用 iOS 26 已有能力即可跑通，不阻塞。

---

## 10. 信息架构重构（Tab 级，2026-10-16 追加）

### 10.1 一句话原则

现状四个 Tab（设备 / 凭证 / 记录 / 设置）是**按数据表切的**，不是按任务切的 —— 这是它拥挤的根因，也是 §3.1 那些"同屏面数超标"的上游。新 IA 按 **作用对象 × 频率** 切。

| 旧 | 新 | 依据 |
|---|---|---|
| 设备页（hero + 圆盘 + 快捷 6 格 + 最近开门 + 夜检 + 家庭关怀 + 脚注） | **开门** = 圆盘 + 门口两件事（再开一次 / 临时码）+ 一行告警条 | 秒级动作独占一屏 |
| 凭证页（按状态分组：置顶 / 指纹 / 临时密码 / 未归属） | **钥匙** = 按**人**分组，硬件单独一区 | 用户想的是"给阿姨的码几点到期"，不是"哪些凭证状态为临时" |
| 记录页 + 告警中心 + 成就页（三个入口、同一条时间轴） | **动态** = 一条流（事件 / 告警 / 纪念按强调级分层） | 同一时间轴的不同强调级，不该是三个入口 |
| 设置页 17 节 + 设备页下半 + 设置-工具节 | **门锁**（作用于某一把锁）+ **本机与隐私**（从门锁 push 进去，作用于 App） | "开锁方式 / 自动上锁 / 自动开门"作用于具体锁，放在全局设置页里用户不知道改的是哪把 |

### 10.2 修掉的五条实证冲突（子代理清点功能点时自己撞出来的，均已回源）

- **E1** 备份与恢复有两个入口（设置-工具 sheet + 快捷池 backup 瓦片），且 `BackupView` / `BackupStudio` 两个文件并存。
- **E2** 默认 6 枚快捷瓦片里含一次性动作（录指纹）与月级动作（家庭便签），而**秒级的开锁本身没有瓦片**；「再开一次」只定位到凭证、不开锁。→ 快捷 6 格在新 IA 里**整块废除**，换成圆盘下两枚大按钮。
- **E3** 「家人与钥匙」一节混了四种对象：成员（人）/ 蓝牙钥匙串（硬件）/ 凭证整理（钥匙）/ 未归属认领（事件）。
- **E4** 固件升级 / 告警中心 / 家政维保同时挂在设置-工具与快捷池上 —— 低频功能占着秒级入口。
- **E5** 两个不同的"时间"能力共用一个名字：「时间显示」（12/24 小时制，属外观）vs「校准时间」（一次 BLE 操作，属维护）。→ 改名 **时钟显示** / **校准锁钟**。

另外**删除**状态图标行的图例：需要图例才能解释的颜色编码本身就是失败的编码，且与本仓 `StatusPill` 自己写的纪律"颜色不作为唯一信息载体"相矛盾（`DesignSystem.swift`）。

### 10.3 连带缺陷面（必须同批改，不能事后补 —— 命中本仓高发族"删/改名留悬空引用"）

Tab 序号在全仓是**裸整数**，不是枚举。机器实测：

| 量 | 实测值 | 复算命令 |
|---|---|---|
| `requestTab(<字面量>)` 调用点 | **40** 处，分布 0:5 / 1:16 / 2:2 / 3:17 | `grep -rhoE "requestTab\([0-9]\)" App/ --include=*.swift \| wc -l` |
| 涉及文件 | **12** 个 | `grep -rlE "requestTab\([0-9]\)" App/ --include=*.swift \| wc -l` |
| `tabSelection` 出现次数 | **74** | `grep -rn "tabSelection" App/ --include=*.swift \| wc -l` |
| 访客门禁 | `guestBlockedTabs: Set<Int> = [1, 3]`（`LockKeeperApp.swift:92`） | 硬编码序号 |
| 深链路由 | `deepLinkHosts = ["device":0,"credentials":1,"records":2,"settings":3]`（`:116`） | 硬编码序号 |
| 摇晃逻辑 | `tabSelection != 3` / `!= 0`（`:109-110`）、`== 3`（`:193`） | 硬编码序号 |

**最高危的一条**：新 IA 里「本机与隐私」（应用锁 / 访客 / 伪装 / 销毁）从 Tab 变成"门锁 push 进去的页面"，而 `guestBlockedTabs = [1, 3]` 只封 Tab —— **访客模式会静默失去对整个安全区块的覆盖**，且不会崩、不会报错，走查也看不出来。这条必须在同一批里改成"封页面身份"而不是"封 Tab 序号"。

**次高危**：`kf://` 的四个 host 名同时被三处引用 —— 主屏长按快捷（`QuickActions.swift:19-21`）、Spotlight（`SpotlightKit.swift:38`）、以及**两句用户可见说明文案**（`AppIntents.swift:466`「支持 device / credentials / records / settings 四个入口」、`ChangelogView.swift:25`）。改路由不改这两句 = 命中"说明句多写必漏"。

### 10.4 施工前置

`requestTab(Int)` 必须先收敛成 `requestTab(Route)` 枚举（或 `TabID`），把 40 处裸整数变成编译期可查 —— 这一步**零行为改动、可独立编译验证**，是 §10.1 那张表的施工前提。不做这步就改 IA，等于在 12 个文件里手工改 40 处数字，靠人眼保证不漏。

### 10.5 待拍板（两条，不回话即按括注施工）

1. **设备管理放哪**：倾向放进开门页门牌选择器的「管理门锁」——它需要 BLE 在场，与「本机与隐私」"与任何一把锁无关"的定义冲突。（默认：放门牌选择器内。）
2. **多锁的顶层表达**：倾向开门页标题处做门牌选择器，四个 Tab 共享"当前门"上下文。（默认：共享。**注意这会改变现有「首行 = 默认锁」规则的可见性**，需确认该规则是否保留。）

---

## 11. 「一枚锁核」= 选定方向，本文 §10.1 作废（2026-10-16）

全项目改造方案已另立 **`CORE.md`**（同目录）。**读方向去 `CORE.md`，不要从本文 §10.1 那张旧→新表读** ——
那张表还是在给现有容器搬家，而这次要的是把容器整个扔掉。用户原话：「你还是没忘记现有UI方案啊，
我不喜欢现有UI，彻彻底底的重构」。

- **作废**：§10.1 那张四 Tab 旧→新映射表（连同"保留 TabView / 保留圆盘 / 保留 Hero 告警条"的隐含前提）。
- **仍然有效并被 `CORE.md` 收编**：§10.2 五条实证冲突 E1–E5 → `CORE.md` §5.1；
  §10.3 连带缺陷面 → `CORE.md` §7（数字本轮全部重测，`.sheet(` 由 89 更正为 **91**）；
  §10.4 施工前置 → `CORE.md` §9 的 C1。
- **§8 待拍板**（Hero 那 10 个条件块哪些能降级）在零卡片模型下**整体失效**：那 10 块全部是候选删除项，
  不再需要逐块裁定。
- 本文 §2 的玻璃事实基线本轮已更正（定义行号 348/353/360，调用点 **24** 不是 35）；
  §6 的反控基线同步改 24。
- 原型与尺子在会话取证目录，**不是仓库文件**：`core-ui.html` / `contrast-check.js`。
  两轮独立视觉评审 5/10 → 7/10；改后的机器验证据 `contrast-check.js` 复算（36 覆盖点 + 18 防漂移锚点）。
