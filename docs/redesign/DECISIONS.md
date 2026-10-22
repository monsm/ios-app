# DECISIONS · v10「一扇门」重设计 · 不可协商的决策（Lead 定稿）

> ⚠️ **本文档属于一代（v10 / BDF 三棱柱），已放弃。** 现行结构见 `SINGLE-CONSOLE.md`，
> 决定依据见 `DESIGN-DECISIONS.md`。保留本文是因为其中的功能清单与闸门矩阵仍然有效。


> 本文件是**唯一裁判**。实施 AI 与其下游协作者在遇到歧义时以本文件为准；
> 本文件与本仓既有闸门冲突时，**先让闸门过**（见 §9）。
> 每条决策给出：结论 / 理由 / 反例（不这么做会怎样）/ 落地写法。
> 状态：`LOCKED` 表示不许改；`OPEN(n)` 表示留待第 n 阶段拍板。

---

## D1 · 门是「封面层」，不是第 5 个 Tab（LOCKED）

**结论**：`LockFace` 是一个 ZStack 容器，把**现有的整个 App（TabView + 全部 76 目的地）**包在里面。
门这一层与 `Route` 结构**正交**：进门不改`tabSelection`、不改 `Route.byHost`、不改 `guestBlocked`、不改深链。

**理由**：v10 原型的 Tab 是「门 / 设备 / 记录 / 全部」，而本仓是 `Route` 四域
「设备 / 凭证 / 记录 / 设置」。若照搬 v10 的 Tab 表，会同时打断 6 处同源声明：
`Route.byHost`、`Route.guestBlocked`、`Route.guestBlockedTabs`、`Route.deepLinkHosts`、
`AppState.rememberTab/restoreLastTab`、`mainTabView` 里按序号摘除的两处访客逻辑
（证据见 EVIDENCE-IOS.md / `App/Core/Route.swift` 头部注释：那里明确记录了"访客模式静默失去覆盖"这一类事故）。
收益（多一个 Tab）远小于风险（静默失去门禁覆盖）。

**反例**：把 Tab 改成 v10 原样 ⇒ 访客模式（377）与 `kf://credentials` 深链会静默错位，不崩不报错，只有人读代码才能发现。

**落地写法**：
- v10 的「门」Tab 由 LockFace 封面**吸收**（门永远是一级入口，不需要占 Tab 位）。
- v10 的「全部」Tab 由 **App Index（76 项目录）** 吸收，入口有三处：
  ① 每个 Tab 右上角「全部」按钮；② 长按任意 Tab 项；③ 下拉搜索。它是一个 `NavigationStack` 目的地，不是 Tab。
- 保留 4 Tab：设备 / 凭证 / 记录 / 设置。**Tab 0 的根 = 「前门」页**（即 v10 的"门后第一屏"），
  设备管理与其它低频项下沉一级（v10 的"渐进披露"原则）。

**v10 元素 → 落地形态对照**

| v10 原型 | 本仓落地 | 是否改数据模型 |
|---|---|---|
| 关着的整屏门（`.door`+两扇 leaf） | `LockFace` 封面层 | 否 |
| 门缝透光 `.gap` | 开锁成功的第一个视觉信号 | 否 |
| 锁体 `.plate` | `UnlockDial`（重做外观，保留状态机） | 否 |
| 门后 App `.app` | 现有 `mainTabView`（4 Tab） | 否 |
| Tab「门」 | LockFace 封面本身 | 否 |
| Tab「设备」 | 现有 Tab 0（根=前门页） | 否 |
| Tab「记录」 | 现有 Tab 2 | 否 |
| Tab「全部」（76 项） | `AppIndexView`（sheet/目的地，非 Tab） | 否 |
| — | 现有 Tab 1 凭证 / Tab 3 设置 | **保留** |

---

## D2 · 门的两种「开」必须分开（LOCKED）

**结论**：门的开有两套语义，**不许合并成一次轻点**：

1. **开锁开门**（主路径，安全动作）：按住锁体充能 → BLE 开锁成功 → 门开。
   —— 门开是**开锁成功的结果**，不是独立动画。
2. **推门而入**（不改锁状态）：从屏幕**左缘向右拖 ≥ 72pt**（或点右上角「进入」小按钮、或从底部上滑）。
   门开，锁状态**保持"已锁定"**，落 Tab 0。

**理由**：v10 写「轻点锁体 → 进门」。在演示原型里成立（轻点=开锁），但在真机上把"轻点"绑成"进门"会造成两个不可接受的后果：
① 只想看记录的人被迫对一把真锁发起开锁指令；② 把一个**安全动作**降级成一次误触可达的轻点，
与本仓既有的误触围栏（`armed`）、信号弱暂缓（`weakNudge`）、`hold/triple/charge` 三档手势设置、`tapDirect` 双击直开全部冲突。

**反例**：轻点即开门 ⇒ 锁没开但门开了，用户以为开了锁；或者锁开了门没开，用户以为没开。两种都会导致"被关在门外"。

**落地写法**（状态机，唯一实现）：
```
LockFacePhase: .locked → .charging(0…1) → .unlocking → .peeking(门缝透光) → .open → .closing → .locked
                                 ↘ .failed(锁体抖动, 门不动)
```
- `.locked` 的锁体手势沿用 `UnlockPrefs.mode`（hold / triple / charge）与 `tapDirect`，**行为逐字不变**。
- `.peeking` = `gap` 亮起（v10 的 420ms 暖光），并**只在 `LockService` 返回成功之后**进入。
- `.failed` 时门**完全不动**（只抖锁体 + 触觉 + 文案），这是安全语义的关键：门不动 = 没开。
- 关门：在 App 层**右滑 ≥ 96pt** 或点导航栏「关门」→ `.closing`；`Escape`（外接键盘）同效。

---

## D3 · 锁体的物理量必须连续（LOCKED）

**结论**：充能进度是**按压时长的连续函数**，1:1 上屏，由一个 `CGFloat` 单一来源驱动
（环的 `trim`、光晕 `opacity`、盘体 `scaleEffect`、刻度点亮数、触觉节拍全部读它）。

**理由**：本仓既有实现里出现过"计时到点→切状态"的脚本动画（`MASTER.md` §3.2 已判死）。
v10 原型的 `.plate.press{scale(.972)}` + 固定时长也只表达了两态。

**反例**：两态跳变 ⇒ 手指停在 60% 时界面没有任何反馈，用户以为没按到。

**落地写法**：`.onLongPressGesture(minimumDuration: 10, maximumDistance: .infinity, pressing:)` 驱动 `holdProgress`，
或 `DragGesture(minimumDistance: 0)` 手动计时；**不要**用 `Timer` 分段推进。
触觉节拍：每 10% 一次 `UIImpactFeedbackGenerator(style: .light)`，充满一次 `.medium`；
`reduceMotion` 下改为一次性 `.solid` 三连 + 静态终态渲染（不逐帧）。

---

## D4 · 视觉令牌只增不改，且必须过闸门（LOCKED）

**结论**：v10 的材质/光照**不得引入新的语义色令牌**。v10 的暖白门面、金属倒角、深色玻璃面
一律以**装饰层（decoration）**身份存在，不进入 `Palette`，不参与 `tools/contrast.js` 的语义对比。
新增的只有**装饰性渐变/阴影/模糊**，全部写在一个新文件 `App/Core/LockFaceStyle.swift`（见 §6 文件清单）。

**理由**：`tools/contrast.js` 现有 36 条断言、6 套主题、`aurora-lock/MASTER.md` §2 明令
「不新增色板、不新增字体、不新增圆角档」。v10 的 `#F6F3EC` 暖白若进语义层，
明暗双模 + 对比度表全部要重跑，且中文字色在白底上的对比需要重新验证。

**落地写法**：
- 门面材质 = `LinearGradient` + `Canvas` 噪声纹理（**零位图**，本仓"除 App 图标外零位图"的纪律不破）。
- 锁体金属倒角 = `AngularGradient`（对应 CSS conic-gradient）。
- **深色模式**：门面整体走 `Palette` 的深色档（夜景门廊），不是把浅色灰搬过去（`MASTER.md` §1 已判死）。
- 所有新文字色在浅/深两套下都必须过既有对比断言；门面上的临时文案（如"轻点锁体"）用
  `.secondary`/`Palette.textSub` 而非自定义灰。

---

## D5 · 动效必须挂进既有双闸，且时长由 DS.Motion 持有（LOCKED）

**结论**：本设计引入的全部动画，**必须**通过 `DS.Motion.tier`（`reduceMotion` → calm）与
`BatteryCare.appLowBattery` → calm 两道既有降级闸；`reduceMotion` 下：
门不转，改为 200ms 交叉淡入淡出（对应 v10 的 `@media (prefers-reduced-motion)` 分支），
中缝光不闪、锁体不逐帧充能（一次性到终态）、高光不跟随指针。

**理由**：v10 的 reduced-motion 分支写对了（`v10.html:201-206`），值得照搬；本仓已有单一读点，不许绕开。

**落地写法**：新增时长常量集中放在 `LockFaceStyle.swift`，**不得**散写 `withAnimation(.easeInOut(duration: 0.82))`。
时长表见 MASTER-PLAN §动效表（门转 820ms 曲线 `.timingCurve(0.22, 0.76, 0.03, 1)`；
SwiftUI 的 spring 在 106° 这种大角度下会过冲，**这里用 timingCurve 而不是 spring**，并在注释里写明原因）。

---

## D6 · 门必须支持"角色化"外观（LOCKED）

**结论**：同一套 `LockFace` 支持 4 种外观，由数据驱动，**不是 4 份实现**：
`wood`（默认，原木/哑光漆）、`metal`（拉丝金属）、`darkGlass`（深色玻璃）、`frosted`（磨砂白）。
外观只改材质与光位，几何（中缝位置、锁体大小、门开角度）**完全一致**。

**理由**：v10 只有一种暖白门面。真机上用户家里是金属门/玻璃门时，暖白木质会显得错位；
而多门（本 App 支持多把锁）同屏时需要靠外观区分。这是"用户想不到但一定会问"的一条。

**落地写法**：`LockFaceSkin` 枚举 + 一个 `surface(for:skin)->some View`；皮肤只影响 4 个参数：
底色渐变三停、噪声强度、倒角亮度、投影强度。

---

## D7 · 「全部」= App Index，76 项一个都不能少（LOCKED）

**结论**：`AppIndexView` 必须列出 `Destination.allCases` 的**全部 76 项**，
分组与 `uiux-v3.data.js` 的 `group` 字段同源，且**由 `tools/destmap.js` 生成的分组数据驱动**，
不许手写数组。搜索框匹配标题 + 分组 + 同义词表。

**理由**：`Destination.swift` 头注释写明「少一条就是某套界面会缺一个页面而没人发现」；
`tools/uicoverage.js` 会与本台账对账。手写第二份清单 = 必然漂移（v10 原型就是这么坏的：
它的内联 `G` 数组与 `uiux-v3.data.js` 不同源，`v10.html:307-315`）。

**反例**：v10 原型的 `G` 数组 78 项 vs 数据类型 76 项（v10 里多出「上锁/静音」类条目）⇒ 两边都不再是事实来源。

---

## D8 · 关门、返回、Tab 的优先级（LOCKED）

**结论**：手势冲突按此优先级裁决，**依次判定、不并行**：

| 位置 | 手势 | 结果 |
|---|---|---|
| 锁面 `.locked` | 按住（≥ 手势档阈值） | 开锁（安全动作） |
| 锁面 `.locked` | 左缘右拖 ≥ 72pt | 推门而入（**不开锁**） |
| App 层 | 右滑 ≥ 96pt（从屏幕左缘 24pt 内起手） | 关门 |
| App 层 | 右滑（非左缘起手） | 交给内容：`NavigationStack` 原生返回 |
| 任意 Tab 根 | 再次点当前 Tab | 滚到顶；再点一次 → App Index |
| 任意处 | 长按 Tab 项 | App Index |

**理由**：v10 的"往回推一下就回到门外"（`v10.html:283`）在真机上会和 `NavigationStack` 的
交互式返回抢手势；且 v10 的实现里关门热区挂在已转到侧棱的门板上，实际点不到（`v10.html:435`）。

**落地写法**：关门手势用 `DragGesture` 且**只在 `edgepan` 区域起手时接管**；
更稳的做法是给 Tab 根加自定义 `UINavigationController` 式边缘手势优先级，
或直接**只保留导航栏的「关门」按钮 + 左缘拖**（推荐后者，见 MASTER-PLAN 风险章）。

---

## D9 · 两端数值同源，但**单一来源是 DesignSystem.swift**（LOCKED，2026-10-18 对抗审核后重写）

**结论**（方向修正）：本仓**已经有一个**令牌导出器 —— «ios-app/tools/layout-replica/build.js:81»，
它从 «App/Core/DesignSystem.swift» **导出**令牌产物。所以：

- **来源 = «App/Core/DesignSystem.swift»**（现有，唯一）。
- **产物 = «tools/layout-replica/build.js» 的输出**（现有管线，不要另建）。
- Android 侧令牌（«Tokens.kt»）由**同一份产物**转出，或直接由一个新增的小脚本从
  «DesignSystem.swift» 解析出数值再生成 —— **不要**新建 «design-system/tokens.json» 作为来源，
  更不要新建 «tools/gen-tokens.js» 走反向。

**上一稿错在哪**：我写了「新增 «design-system/tokens.json» 作为单一来源，由 «tools/gen-tokens.js»
生成两端」——**方向反了、且那两个东西在本仓都不存在**（实测）。
照那一稿做，实施 AI 会先把现有导出管线推翻，属于纯粹的无收益返工。

**真正要保证的只有一条**：iOS 与 Android 的**几何/间距/圆角/字号/时长/曲线数值逐字相同**。
做法：在生成物里加一张对照表，改完跑一次 diff；**色板不参与**（D14：两端各自保留）。

**理由**：本仓已有"同一量的双实现"引发静默事故的先例（«Route.swift» 头注释）。
但**双实现的解法是把来源钉在一处**，不是**再叠一层**。

---

## D11 · Android **不做门面** —— 只共享视觉语言（LOCKED，2026-10-18 用户拍板修订）

**结论**：门（LockFace：两扇门 / 中缝 / 锁体 / 透光 / 推门而入）是 **iOS 独有**的入口仪式。Android 端**不实现门面**，直接进主界面。Android 本轮范围收窄为：

1. **共享视觉语言**：颜色、间距、圆角、字号、字重、时长、曲线、深浅双模 —— 与 iOS **逐字同源**（D9）。
2. **现有功能 UI 重做**：Android 现有 2 屏 + 3 覆盖层，按新视觉语言重做，**行为逐字不变**。
3. **工程底座**：触觉封装、深浅双模、令牌同源。（**不**为 edge-to-edge 升 SDK，本轮不引入 Navigation 库。）
4. **不移植** iOS 的 76 个功能页，只交付《功能对齐路线图》（PART6 §7）。
5. **不做门面**，也不做其任何变体（半扇门、门缝、锁体动画）。

**Android 的入口形态**：启动即主界面，**开锁台就是首页主体** —— Android 现有设计里开锁入口本来就在首页（`MainActivity.kt` 单 Composable 根），比 iOS 更直接。iOS 需要门是因为要做「走进一个房间」的仪式，Android 不需要。

**理由（用户直接指令 + 机器证据）**：现有 Android 只覆盖 3 条协议命令（`KfProtocol.kt:180-192` 的 01/03/04），iOS `ZKCmdBuilder` 有 31 个构造器 ⇒ 凭证、记录、DFU、网关、备份域在 Android 侧 **0 实现**；且 Android **本地没有 UI 层编译闸门**（`tools/kotlinlocal.js:9-10` 只编 4 个非 UI 文件）。在没有编译反馈的环境里做重动画门面 + 移植 76 页 = 必然返工。

**仍然共享（不可省）**：令牌数值同源（D9）、`KFA1` 配对二维码、协议字节面（NUS UUID / KLV / 令牌 KLV#0xEE / 广播 0x98ED / rc 表）。

**边界**：存储命名空间互不相识（Android 只有 `kf_key_v1` 的 2 个键，iOS 有 336 个 `kf_*` 键）—— **不许**在 Android 端假装能读写 iOS 的 `kf_*` 键；跨端只用二维码/文件，不用存储。路线图里排期第一是**协议层对齐**，**不是**页面。

---

## D12 · 门锁体直径必须尊重既有的 `kf_dial_size`（LOCKED）

**结论**：门面上的锁体**不是**一个固定 240pt 的新东西，它是既有圆盘设置的**放大投影**：

| `kf_dial_size` | 用户语义 | 门锁体直径（基准 393pt 宽） |
|---|---|---|
| 160 | 紧凑 | 220pt |
| 176（默认） | 标准 | **240pt** |
| 200 | 大 | 272pt |

上限 `min(直径, screenW * 0.68)`；iPad 上仍以 272pt 封顶（不是无限放大）。

**理由**：本仓已有 `DS.Metric.dial`（`DesignSystem.swift:152-156`，读 `kf_dial_size`，默认 176）以及设置项「圆盘大小三档」。若门面另立一个 240pt 固定值，用户在设置里调小/调大后回到门外会**看到尺寸没变** —— 这正是本仓反复判死的「假开关」（切了没反应），`keydead.js` 的顾问检查也在盯这一族。

**反例**：门面写死 240pt ⇒ 设置里「圆盘大小」对门外失效，用户认为设置坏了。

**落地写法**：`LockFaceStyle.plateDiameter(screenW:)` 单点换算，入参读 `DS.Metric.dial`；**不许**在视图里再写一次映射。实测 `enum Metric` 六成员全是 internal，**新文件可直接读**（audit-B ✅）。

---

## D13 · 门面不得声称锁端不存在的状态（LOCKED）

**结论**：门面上的每一句话，都必须是**本机真知道**的事实。v10 原型的三句文案里，**一句可用、一句要改写、一句必须删**：

| v10 文案 | 处置 | 为什么 |
|---|---|---|
| 「在线 · 电量 92%」 | **改写**为「已连接 · 电量 92%」 | 协议里**没有「在线」状态**（`CAPABILITY.md` §5 第 3 条）。「已连接」是 `CoreBluetooth` 的**本机事实**，可以说 |
| 「已锁定 · 3 小时」 | **改写**为「门关着 · 上次开锁 3 小时前」 | 协议里**没有反锁/上锁状态位**（§5 第 2 条）。「锁定」是 UI 概念不是锁端事实；「上次开锁时间」是本机记录，是真的 |
| 「门磁未检测到合上」 | **必须整句删除** | 协议里**没有门磁**（§5 第 1 条：无字段无命令；`rc=21`「反锁状态」只是开锁失败错误码）。**门有没有合上，本机根本不知道** |

**理由**：本仓把「不虚构精度」写进了否决项（`DEFERRED.md` 里 46 电池健康、119 充电状态、1029/1032/1040 掉电斜率全部因「协议无字段」被硬划掉）。门面是**用户看到的第一屏**，在这里编一个「门磁」比在二级页编读数更贵 —— 它会让人真的以为门没关，跑回去看一趟。

**落地写法**：门面状态文案**只允许**来自三个真源：① `CoreBluetooth` 连接态；② cmd 03 状态帧的 `0x11 powerLevel`；③ **本机记录**（`kf_*`：上次开锁时间、上次同步时间）。

**禁止**在门面上出现：门磁 / 门是否合上 / 反锁 / 已上锁（作为锁端事实）/ 在线。未知就说未知：连不上时显示「状态未知 · 上次同步 14:20」，**不许**把上一次快照当实时（`MASTER.md` §1 的遥测纪律）。「门开着 / 门关着」是**本机 UI 状态**，可以随便显示 —— 但**不要**把它说成锁的状态。

**配套红线（来自 `CONSTRAINTS.md`）**：

| 平台事实 | 对设计的影响 |
|---|---|
| **无 App Groups**（`CONSTRAINTS.md:22`） | Widget **读不到** App 数据 ⇒ 小组件只能是「拉起 App 的哑按钮」。**所以**：从小组件进来**必须跳过门** |
| **签名 7 天过期**（`:30`） | 不许设计任何依赖「长期后台驻留」的体验 |
| **后台 BLE 扫描受限**（`:34`） | 不许承诺「回到门口自动开锁」这类后台自动完成；近场自动弹层只能**前台** |
| **NFC capability 未实测**（`:32`） | **不许**设计 NFC 碰一碰进门 |
| **多锁并行预连 ❌**（`DEFERRED.md` 276） | 门面只服务**当前选中的那一把锁** |

---

## D14 · Android 的配色基调：保留暗色 + 暖金，不改成 iOS 的暖白（LOCKED）

**结论**：两端共享的是**几何、间距、圆角、字号档、时长、曲线、材质做法**；**配色基调各自保留**：iOS 用浅色暖白木质门面 + 蓝色强调（既有 `Palette`）；Android **保留现有暗色 + 暖金**（`Theme.kt:10-17`：BgTop #0A0C10 / BgBottom #141A22 / Surface #161C24 / Ink #F3F6FA / InkSub #8B96A8 / **Accent #E8B45C** / Ok #6EE7A8 / Bad #F87171）。

**理由**：① Android 现有注释写明这套色是刻意的 —— 「钥匙/黄铜的联想，不是科技蓝紫」（`Theme.kt:8`），强行改成浅色木质 = 把已有品牌意图推倒；② v10 的锁体语言本身就是**黄铜/金属倒角**，`#E8B45C` 与它**同族**，天然接得上；③ 这不是「同一款 App 的两个版本」，而是**同一套设计语言的两个实现**，用户不会并排比对底色。

**落地写法**：令牌数值同源（D9），但**色板 per-platform**。Android 材质照 v10：**倒角用 `Brush.sweepGradient`**、**投影用多层柔和阴影**、**玻璃用 `Modifier.blur` + 半透明**。**不做门面**（D11），但**保留并重塑** Android 现有的开锁台：用 v10 的材质语言重画，交互不变。

---

## D15 · 排版七条（用户 2026-10-18 拍板，全部采纳推荐值）（LOCKED）

v10 原型是 Web 口径，其排版数值与本仓既有规范在 **7 处**直接冲突。逐条裁定如下，**实施 AI 一律照「裁定值」执行**，不许回退到 v10 的原始 px。

| # | 项 | v10 原值 | **裁定值** | 理由 |
|---|---|---|---|---|
| 1 | 标题左边距 | `26px` | **`DS.Space.gutter` = 16pt** | 开门前后标题不横向跳位，且与卡片左边距对齐；不新增令牌 |
| 2 | 门面大标题 | `34px / bold` | **34pt / semibold** | 与 iOS 大标题、门后 App 的 h1 同档；苹方无 Bold，`.bold()` 会静默回退 |
| 3 | 底部提示语 | `12.5px` | **13pt / `.footnote`** | 中文 12pt 以下笔画粘连；13pt 在昏暗楼道可读 |
| 4 | 列表行高 | `52px` | **沿用既有 44 / 60 两档**（`DS.Metric.rowMinH`，受 `kf_row_h` 控制） | 改行高是全 App 密度变更（76 页），属**行为级**改动而非视觉改动 |
| 5 | 卡片圆角 | `14px` | **`DS.Radius.card` = 22pt** | 与全 App 一致，且 `kf_radius` 的 soft/plump 三档设置仍生效 |
| 6 | 读数排版 | 列表值有 `tabular-nums`，门面 meta 行漏了 | **一律 `.monospacedDigit()`，并跟随 `kf_digit_font`** | 电量 9%→10% 时整块不跳；同时让设置里的「数字字体」在门外也生效 |
| 7 | 动态字体封顶 | 无此概念 | **跟随 Dynamic Type，封顶到 accessibility2**。⚠️ **不要**写 `.dynamicTypeSize(...accessibility2)`（`PartialRangeThrough` 语义、仓内 0 先例）；照抄既有唯一先例 `LockKeeperApp.swift:1336` 的 `AXFlags.typeSize()` 精确档写法 | 与锁体内部文案口径一致；最大字号下标题换行到 2 行，**锁体几何不缩放** |

**两条附带纪律**：

1. **中文不加 tracking**（汉字是等宽方块）；只有全大写拉丁（如 BLE）才加。
2. **一屏只允许一个大标题**：门面「锁名」与门后 App 的 h1 都用 34pt semibold，所以开门前后标题**字号不变、只有位置换** —— 这正是选 1 号（16pt）与 2 号（34pt）组合的原因。

**反例**：若把 v10 的 26pt 搬进来，逻辑上必须把门后 76 个页面也改成 26pt 才自洽 —— 那是 76 个文件的改动，且打破 `DS.Space.gutter` 的单一来源。收益为零。

---

## D10 · 本轮**不做**的事（LOCKED，不许实施 AI 自行加回）

1. 不做在线/云功能（厂商已破产，用户明确不做）。
2. 不引入自定义字体（`MASTER.md` §1 已驳回 Plus Jakarta Sans）。
3. 不改协议层、不改 `fixtures/golden.json`、不动 `vendor/app`。
4. 不新增位图资源（门面纹理用 `Canvas` 程序化生成）。
5. 不做 3D 门在 Android 上的"真 3D"（用 `graphicsLayer.rotationY` + 相机距离近似，够用且不掉帧）。
6. 不把 76 个目的地重排分组（分组沿用 `uiux-v3.data.js`，只做视觉改造）。
7. 不删任何既有功能页；本设计只重做**入口层 + 导航层 + 组件外观**。
8. Android 端**不做门面**、不移植 iOS 的 76 个功能页（见 D11），只做设计语言 + 现有功能重做 + 工程底座。

---

## 对抗审核更正记录（2026-10-18，与 D1–D15 同等效力）

本方案在交付前做了三轮**对抗式**核查（AUDIT-A 符号 / AUDIT-B 接线 / AUDIT-C 目的地表，报告见同目录）。
查出 **11 处真实错误**，其中 **3 处会直接导致编译失败**。全部已修正，清单如下 ——
实施 AI 若在旧副本或对话记录里见过被更正的写法，**以本表为准**。

| # | 错在哪 | 错写成 | **实际** | 后果 |
|---|---|---|---|---|
| 1 | VK 语法层调用形式 | `VK.card` / `VK.sectionTitle` / `VK.statusPill`（当属性） | 三个都是 **@MainActor func**：`VK().card { }` / `VK().sectionTitle(text:count:)` / `VK().statusPill(text:systemImage:tone:)`（`VariantGrammar.swift:81/113/138`） | **编译失败**；错写法曾被复制到 PART5 九处 |
| 2 | 开锁入口 | 「照抄 UnlockDial 里的解锁调用」 | UnlockDial 是**纯视图**，只调 `action: () -> Void`（`:323`）。正确入口 **`app.requestUnlock()`**（`LockKeeperApp.swift:488`），内部含三道安全闸 | **编译失败 + 绕过安全策略** |
| 3 | 动效降级读点 | 新文件读 `DS.Motion.tier` | `tier` 是 **private**（`DesignSystem.swift:286`），新文件读不到。`doorSwing` 必须写在 `DesignSystem.swift` 内 | **编译失败** |
| 4 | 令牌来源 | 「`design-system/tokens.json` 是来源，由 `tools/gen-tokens.js` 生成」 | **方向反了且两者都不存在**。真实管线是 `tools/layout-replica/build.js:81` 从 `DesignSystem.swift` **导出** | 推翻现有管线 = 无收益返工 |
| 5 | 皮肤载体 | `LockProfile.skin` | `LockProfile` **全仓 0 类型**。真实是 `struct LockMeta: Codable`（`LockStats.swift:16`），加字段需三步齐改 | 漏改 `decodeIfPresent` ⇒ **老档案整本变空** |
| 6 | Sheets 容器 | 「现有 `CoverRegistry`」 | **幻觉符号**，全仓 grep 0 命中。cover 直接挂在 `mainTabs`（`:1246/1252`）与 `mainTabsChrome`（`:1270`） | 实施 AI 会去找一个不存在的东西 |
| 7 | 布局层 | 「现有 `AppLockView` / `DecoyView` 两层」 | **两者都不存在**（启动门禁 2026-10-17 已删，`LockKeeperApp.swift:1319`） | 会被「补回」成第二套门禁 |
| 8 | 动效令牌 | `DS.Motion.calm` | **不存在**。`calm` 只是 `tier` 的取值，六个成品令牌各自内部 switch | 编译失败 |
| 9 | 动态字体 | `.dynamicTypeSize(...accessibility2)` | 区间语义、仓内 0 先例；唯一先例是 `LockKeeperApp.swift:1336` 的 `AXFlags.typeSize()` 精确档 | 封顶语义丢失 |
| 10 | 门面元素 | 「27% 处的静态装饰缝 `SurfaceSeam`」 | v10 定义了 `.seam` 但 **HTML 里 0 次使用**（死 CSS）。门面上**只有 50% 一处**竖缝 | 实施 AI 会去实现一个不存在的元素 |
| 11 | 验收数字 | 「残留竖条 26–40pt」「perspective 先取 0.55」 | **都是没推导依据的估数**。正交投影解 `(屏宽÷2)×cos θ`：88° ≈ 7pt。改用两条可测判据（残留 5–16pt + 45° 梯形畸变 <8%） | 验收标准本身是错的 |

| 12 | 失败文案符号 | `StatusParser.rcMsg(rc)`（当函数） | `rcMsg` 是**字典**（`StatusParser.swift:154`）；函数是 **`rcFriendly(rc)`**（:181，`rcHint` 兜底 `rcMessage`:162） | 编译失败（拿字典当函数调） |
**另有 3 处风险分级虚高**（AUDIT-C 实测切片串边界）：`lockProfile` 高→**低**、`restoreWizard` 中→**低**、`defend` 低→**中**。修正后计数为 **高 12 · 中 8 · 低 56**。

**已核对为真、不要改动的**：`DS` 十一族、`DS.Motion` 六档、`DS.Metric` 六项（全 internal，新文件可直读）、
`AXFlags` 四旗标 + `reduceMotionSnapshot:56`、`BatteryCare.appLowBattery:102`、`axGlass` **388/393/400**、
`UnlockPrefs` **:7/:12/:17**、`StatusParser.rcMsg:154`、76 条实现落点 **0 处不符**、76 个 View 名互不重复。

---

## 交付物与写入边界（防止两个 AI 互相覆盖）

| 文件 | 作者 | 谁读 |
|---|---|---|
| `ios-app/docs/redesign/DECISIONS.md` | Lead | 所有人（先读） |
| `ios-app/docs/redesign/EVIDENCE-*.md` | 取证员 | 所有人 |
| `ios-app/docs/redesign/MASTER-PLAN.md` | Lead | 实施 AI |
| `ios-app/docs/redesign/PART1-LOCKFACE.md` 等 | Lead | 实施 AI |
| `ios-app/docs/redesign/PARTn-*.md` | 各自作者 | 实施 AI |
| 源码 | **实施 AI** | — |
