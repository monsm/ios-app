# PART 0 · 设计总纲与补充决策

> 本文回答两个问题：**v10 的设计语言怎么翻译成 iOS/Android 原生**（§1–§3），
> 以及**你没提到、但一定会出问题的地方我们替你定了**（§4，26 条）。
> 数值与验收在 PART1/PART3/PART4；本文只讲"为什么这样定"。

---

## 1. v10 的四个决定 —— 采纳三个，修正一个

| v10 的决定 | 我们的处置 | 理由 |
|---|---|---|
| ① 关着的时候，整屏就是对开的两扇门 | **全采纳** | 这是本设计的灵魂：门不是装饰，是入口本身 |
| ② 锁开了，中缝先透光，门自己转开 | **全采纳** | "转到与视线平行而消失"比滑走/淡出高级一个量级 |
| ③ 门后是常规 iOS，不再演隐喻 | **全采纳** | 隐喻只在入口演一次，进去之后是产品 |
| ④ 关门只要一个动作（往回推一下） | **修正** | v10 写"轻点锁体开门"，这在真机上把安全动作降级成误触可达的轻点（D2）。**轻点/按住 = 开锁；左缘右拖 = 进门**，两件事分开 |

**另外修正两处技术性错误**（v10 原型的实际缺陷，逐条已核）：
- v10 的 `scr.classList.remove('open')`（`v10.html:449`）是非法写法，会中断手势脚本。
  SwiftUI 侧对应纪律：**手势回调里只许改状态机相位**（PART1 §5）。
- v10 的 76 项内联数组与 `uiux-v3.data.js` 不同源，两边都不再是事实来源。
  我们规定由 `tools/destmap.js` 生成（D7）。

---

## 2. 分层图（实施时对着这张图找自己的位置）

`
┌─ 首启引导 OnboardingView ───────────── 现有；引导期间门不渲染（还没有锁）
├─ Sheets / Covers / GuestReauthGate ─── 现有，不动（受限区复核走 fullScreenCover）
├─ MainTabs（4 Tab，语义不变）
│    ├─ Tab 设备  → 根屏 = 「前门」页（v10 门后第一屏）
│    ├─ Tab 凭证  → 现有
│    ├─ Tab 记录  → 现有（根屏改"记录时间线"视觉）
│    └─ Tab 设置  → 现有
│    └─ 每 Tab 右上「全部」→ AppIndexView（sheet）
└─ LockFace（门面层，最底）
     ├─ DoorSurface 门面材质（渐变 + 光位 + Canvas 噪声）
     ├─ DoorGap 50% 门缝（左暗右亮）
     ├─ SurfaceSeam 27% 静态装饰缝（门后露出）
     ├─ LockPlate 锁体（5 层 + 字形双态 + 充能）
     └─ LightLeak 中缝透光
`

**门的两种状态**：`closed`（显示 LockFace，MainTabs 隐藏但**不销毁**）与 `open`（反之）。
**绝不用 `if` 条件插入移除 MainTabs**——会重建 `CredentialsView` 的 `@State`（本仓已有该坑的注释）。

---

## 3. 与既有代码功能的结合点

| 门面要做的事 | 接哪段既有代码 | 不许做什么 |
|---|---|---|
| 开锁 | `LockService` 的解锁入口（照抄 `UnlockDial` 现有调用参数） | 不许直接调 `BLEService` |
| 手势档位 | `UnlockPrefs.mode` / `tapDirect` / `gestureHint` | 不许新增第二套手势设置 |
| 降级 | `DS.Motion.tier`（已含 reduceMotion + 低电量） | 不许绕开直接读 `UIAccessibility` |
| 玻璃 | `axGlass(_:)` / `axGlassCircle()` / `axGlassCapsule()` | 不许就地写 `glassEffect` |
| 失败文案 | `StatusParser` 的 rc 文案表 | 不许自己编文案 |
| 门禁与深链 | `requestRoute` / `pendingRoute` / `pendingMac` | 门层不许直接写 `tabSelection` |
| 记录/统计 | `Store` 的 `kf_*` 键 | 不许新增第二份存储命名空间 |
| 语音开锁 | `SpeechKit` | 语音路径必须也能触发门开 |

> **Android 不适用本节**：Android 不做门面（D11），上表是 iOS 专属的接线点。
> Android 侧只需共享 §4-F 的 E1（令牌同源），其余条目在 Android 上无对应物。

---

## 4. 补充决策 26 条（你没提，但不做就会返工）

### A · 安全与状态诚实

**S1 · 门面上的话必须是真的** —— 详见 **D13**（v10 的三句文案：一句改写、一句改写、一句**必须删**，
因为协议里没有"在线"、没有"反锁状态"、更没有"门磁"）。

**S2 · 开锁失败时门一个像素都不动。** 「门动了 = 锁开了」是用户唯一可靠的读法（D2）。

**S3 · 门面必须能被绕过。** 若锁离线/蓝牙关/无权限，用户仍要能进 App 看记录。
所以「推门而入」（左缘右拖）**永远可用**，且失败态要给出替代路径：
「用密码开」「用临时码」「仅查看记录（不解锁）」。

**S4 · 伪装态本轮不存在，别为它设计。** 实测：全仓 App/ 下只有**一处**给 `decoyMode` 赋值，
而且那一处在**注释里**（`AutoOpen.swift:441`）；启动门禁删除后伪装口令随之不可达
（`LockKeeperApp.swift:1319` 原话）。所以 `decoyMode` 现在是**不可达状态位**，只有 11 处读守卫。
⇒ 门面**不要**做"伪装皮肤""伪装下开锁失败"这类分支；那是给一个走不到的状态写代码。
（附带观察，不属于本设计范围：这 11 处守卫与那个状态位本身可以另开一批清理。）

**S5 · 访客模式（377）下门不变，但门后的可达性不变。** 门只做视觉，
访客仍然只能走 `requestRoute`，`guestBlockedTabs` 两条路径照旧生效。
推门而入**不得**成为绕过访客门禁的通道。

**S6 · 首启引导期间门不渲染。** 引导是全屏 `OnboardingView`（`LockKeeperApp.swift:1313-1317`），
门在它下面不参与；引导完成后才谈门。（"应用锁优先于门"这条**已不适用**：启动门禁已于 2026-10-17 删除。）

### B · 状态与生命周期

**L1 · 冷启动才演门；回前台不重演。** 阈值 300s（PART1 §7），两端同值。

**L2 · 深链/小组件/Siri 一律不演门，直达目的地。** 通知点进来还要推门 = 荒谬。

**L3 · 开锁途中被切后台 → 取消并回 `.locked`**，不许回来时门停在半开。

**L4 · App 崩溃/被杀后重启，门态一律回到 `.locked`。** 门态**不持久化**（持久化门态 = 崩溃后看到半开的门）。

**L5 · "看腻了"要给出口。** 设置里加「开锁后直接进主页」（默认关）。
仪式感是加分项，不能变成每次开锁的税。这条写进 `LockFacePolicy`。

### C · 多设备与多锁

**M1 · 门对应"当前选中的锁"**，切换锁时门面换皮肤并有 300ms 过渡，**不重演开门动画**。

**M2 · 没有任何锁时（首次启动）不显示门**，直接进引导（`Onboarding`）——
一把锁都没有的人对着一扇门会觉得莫名其妙。

**M3 · 门上的标题是锁名**（"前门"），不是 App 名。

### D · 无障碍（这一节的每一条都要能通过验收）

**A1 · VoiceOver 必须能开锁。** 按住充能对 VO 用户是不可完成的动作 ⇒
`accessibilityActivate()` 里自动充能 1.2s 后触发（PART1 §6）。

**A2 · 动态字体 200% 时几何不破。** 锁体尺寸**不随字号缩放**，其内部文案封顶
`.dynamicTypeSize(...accessibility2)`；门上的标题允许换行到 2 行。

**A3 · 降低动态效果：门不转。** 改为 200ms 交叉淡入（照搬 v10 的 reduced-motion 分支）。

**A4 · 降低透明度：门面去噪点、锁体保留描边。** 不许留半透明的"看得见门后"的假玻璃。

**A5 · 增强对比：门上提示文案用主文本色，中缝亮线加粗到 2pt。**

**A6 · 触觉可关。** 系统"触感反馈"关闭时不能有任何回退动画依赖它（视觉必须自成一体）。

**A7 · Switch Control / Voice Control 能选中锁体**（`isButton` trait + `accessibilityLabel`）。

### E · 视觉与平台

**V1 · 深色模式是"夜景门廊"**，不是把浅色灰搬过去（MASTER.md §1 已判死这条）。

**V2 · iPad / Stage Manager：等比放大，锁体直径上限 240pt**，中缝仍在 50%。
横屏时锁体中心 Y 从 46% 调到 44%（横屏视觉重心更靠上）。

**V3 · 门面纹理零位图。** `Canvas` 程序化生成 + **固定随机种子**（否则每帧重绘会闪）。

**V4 · 状态栏字色跟随皮肤亮度**（浅色皮肤用 dark content）。

**V5 · 皮肤 4 种**（wood / metal / darkGlass / frosted），几何逐字相同（D6）。

**V6 · 不用自定义字体、不加位图、不加新色板**（D4/D10）。

### F · 工程与交付

**E1 · 令牌单一来源 = `App/Core/DesignSystem.swift`（D9 已重写）。** 本仓**没有** `tokens.json` 这个来源；现有导出管线是 `ios-app/tools/layout-replica/`（`build.js:81` 从 DesignSystem **导出**）。两端数值逐字相同，色板各自保留（D14）。

**E2 · 新文件必须进台账。** 新增页面要出现在由 `tools/destmap.js --emit` 生成的 `Destination.swift`；
**不要手改该文件**（它头部写明"不要手改"）。

**E3 · 玻璃只走 `axGlass*`。** 就地写 `glassEffect` 会在"降透明度/增强对比"下与形状族分家。

**E4 · 类型检查超时是真风险。** 本仓已有 3 处注释记录"该表达式报 type-check 超时"而被迫抽函数
（如 `LockKeeperApp.swift:1056/1126/1155`）。门面层参数多、修饰符长，
**每个视图保持 body 短小、拆子视图**，否则会撞同一个坑（PART7 风险登记册有专条）。

**E5 · 闸门优先于本方案。** 闸门不让过的写法就是错的写法（MASTER-PLAN §5）。

**E6 · Android 本轮不做门面、不移植 76 页**（D11，用户已拍板）：
门是 iOS 独有的入口仪式；Android 直接进主界面，**开锁台就是首页主体**。
Android 只做三件事：共享视觉语言（令牌数值与 `DesignSystem.swift` 同源）、现有功能 UI 重做、触觉与深浅双模。
并交付《功能对齐路线图》；Android 侧第一优先是**协议层对齐**，不是页面。

---


---

## 6. 附录 · 既有令牌真实值（Lead 实测，实施时直接引用，不要再猜）

> 来源：`ios-app/App/Core/DesignSystem.swift`。**门面层必须复用这些令牌，不许另立一套。**

### 6.1 间距 `DS.Space:110-130` — 4/8 节奏 + 密度缩放
`xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32 · gutter 16`
全部经 `densityScale` 缩放（`kf_density`: compact 0.85 / standard 1.0 / relaxed 1.18），
并**吸附到 0.5pt**（避免亚像素抖动）。**门面层若要随密度呼吸，也走这套；锁体本身不缩放。**

### 6.2 圆角 `DS.Radius:135-147`
`card 22 · control 16 · tile 18`，经 `k` 缩放（`kf_radius`: soft 0.62 / plump 1.3）。
**已删除的第 4 档 `pill = 999`** —— 全仓胶囊一律走 `Capsule()`（115 处），
**新代码不许再引入 pill 常量**（那是"零读取常量还配解释注释"的典型）。

### 6.3 触达 / 图标 / 圆盘
- `DS.Hit.min = 44`（`:149`）
- `DS.Icon`: `xs 13 · sm 16 · md 20 · lg 26 · xl 44`（`:266-272`）——**全 App 只用这套**
- `DS.Metric.dial`（`:152-156`）：读 `kf_dial_size`，档位 **160 / 176 / 200，默认 176** ← **见 D12，门锁体必须映射它**
- `DS.Metric.rowMinH`（`:160-162`）：`kf_row_h` == "tall" → 60，否则 44
- `DS.Metric.tlGap`（`:166-174`）：时间线行距，× `Space.m`
- `DS.Metric.heroTexture`（`:183-186`）：`kf_hero_tex` = grid / grain
- `DS.Metric.digitDesign`（`:192-194`）：`kf_digit_font` == "plain" → .default，否则 .rounded

### 6.4 动效 `DS.Motion:280-343` —— **唯一读点，禁止绕开**

档位解析顺序（`:286-293`）：
1. 系统"减弱动态效果"（`AXFlags.reduceMotionSnapshot`）→ **calm**
2. 低电量（`BatteryCare.appLowBattery`，锁电量 ≤20%）→ **calm**
3. 用户档 `kf_motion`：calm / standard / lively

| 令牌 | calm | lively | standard（默认） |
|---|---|---|---|
| `summon` | `easeOut .12` | — | `spring(response .35, damping 1.0)` |
| `fling` | `easeOut .12` | — | `spring(.35, .82)`（**只有手势带动量时用**） |
| `quick` | `easeOut .10` | `spring(.22, .68)` | `spring(.22, .9)` |
| `standard` | `easeInOut .16` | `spring(.45, .68)` | `spring(.4, .85)` |
| `soft` | `easeInOut .12` | `easeInOut .34` | `easeInOut .25` |
| `exit` | `easeOut .08` | `easeOut .20` | `easeOut .15` |

另有 `DS.Duration`（`:349-353`）：`quick .15 / standard .25 / slow .40`（只给时长用）。

**门面层怎么接**（重要）：
- 门转动要的是 **820ms 的 cubic-bezier (.22,.76,.03,1)**，这张表里**没有**。
  **正确做法**：在 `DS.Motion` 里**新增一个令牌**（如 `doorSwing`），并让它也在 `calm` 档降级。
  **错误做法**：在视图里直接写 `withAnimation(.timingCurve(0.22, 0.76, 0.03, 1, duration: 0.82))` ——
  那就等于把降级规则实现第二遍（本仓 `:294-298` 的注释专门批过这个）。
- 同理：中缝透光 420ms、App 层入 460/700ms、字形换态 260ms、充能回零 180ms、
  关门尾段 780ms —— **全部走新增的 `DS.Motion` 令牌**，一处声明。

### 6.5 语义色 `Palette:368-391`（明 / 暗）

| 令牌 | 浅色 | 深色 |
|---|---|---|
| `canvasBase` | F2F4F9 | 070B12 |
| `surfaceBase` | FFFFFF | 151D29 |
| `surfaceAltBase` | F5F7FB | 1C2534 |
| `hairline` | D3DCE7 | 29343F |
| `text` | 0D1626 | F2F6FB |
| `textSub` | 525E77 | 9FACBE |
| `ok` | 15803D | 4ADE80 |
| `warn` | B45309 | FBBF24 |
| `danger` | B91C1C | F87171 |
| `onSem` | FFFFFF | 0A0E15 |

另有 6 套品牌主题（`themeTable:412`）、AMOLED 覆盖（`amoledOverride:449`，`kf_theme == "black"`）、
App 内高对比皮肤（`kf_hc`，与系统旗标**并联**，`:361-365`）。

**门面层的硬约束**：门面是**装饰层**，它的底色、渐变、金属倒角**不参与**这 397 条对比度断言；
但**门面上的文字**（标题、提示、失败文案）必须用 `Palette.text` / `Palette.textSub`，
不许自定义灰（见 D4）。

### 6.6 触觉 `DS.Haptics:254-258`
- `tick` = `UIImpactFeedbackGenerator(style: .light)` —— 过程触感（围栏解锁 / 进度刻度 / 就绪轻震）
- `trigger` = `UIImpactFeedbackGenerator(style: .medium)` —— 动作触感（手势确认 / 断连提醒）
- 结果档 = `UINotificationFeedbackGenerator` 的 success / warning / error，**只用于操作结果**

**门面层对应**：充能刻度 → `tick`；开锁触发 → `trigger`；开锁成功/失败 → success/error。
**禁止**自己 `UIImpactFeedbackGenerator(style: .heavy)`（本仓触感只允许这三档，`:248-253`）。

### 6.7 两条既有的"装饰层纪律"（门面必须遵守）
1. **夜间降亮度** `DS.isNightDim`（`:259-264`）：22:00–06:00 **只降装饰层**峰值（圆盘光晕 / Hero 光源），
   文字与语义对比度不受影响。→ **门面的 sheen / 中缝亮光 / 锁体辉光必须接这一条**，
   否则半夜开锁会刺眼。
2. **装饰层不许越过无障碍与素颜开关**：已有先例 `DS.Metric.heroTexture` 的注释（`:179-182`）明说
   "装饰层不许越过无障碍与素颜模式开关"。→ 门面同理：`reduceTransparency` / 高对比 / 素颜模式下
   该降的降（PART1 §6）。
3. **噪声纹理的既有实现可照抄**：`DS.HeroTexture` 的 "grain" 档（`:214-230`）用
   **固定种子的线性同余**（`seed 0x9E3779B9`, `6364136223846793005 / 1442695040888963407`）画点，
   注释写明原因："纹理必须每次重建都长一样，否则外观种子每变一次，卡面上的点就整体重掷一次，看着像闪了一下噪点"。
   → **门面噪声直接复用这个模式**（可复用同类 LCG，点数按门面面积放大），
   **不要**自己写 `Double.random(in:)`。

### 6.8 其他门面会用到的既有件
| 件 | 位置 | 用途 |
|---|---|---|
| `axGlass(_:)` / `axGlassCircle()` / `axGlassCapsule()` | `AccessibilityKit.swift:388/393/400`（**已实测更正**：MASTER.md 与部分文档写的 348/353/360 是错的） | 唯一玻璃入口（含降透明实底回落） |
| `VK` 语法层 | `VariantGrammar.swift:37` | 卡片/分组标题/状态胶囊/开关/字体 |
| `VKTypography` | `VariantGrammar.swift:437` | 字体取字唯一入口 |
| `DS.Gradient.hero` / `screenMesh` / `screen` / `button` | `DesignSystem.swift:620-668` | 既有渐变，优先复用 |
| `HeroCard` / `MetricTile` / `StatusPill` / `HeroPill` / `EmptyState` | `DesignSystem.swift:794-1100` | 门后 App 用的既有组件 |

---

## 5. 术语表（全方案统一用词，避免实施 AI 理解偏差）

| 术语 | 含义 | 对应 v10 |
|---|---|---|
| **门面层 / LockFace** | 覆盖整屏的两扇门的容器 | `.door` + `.scr` 的封面态 |
| **锁体 / LockPlate** | 压在中缝上的圆形锁体，唯一可交互元素 | `.plate` |
| **门缝 / DoorGap** | 50% 处两扇门的交界（左暗右亮） | `.leaf .edge` |
| **装饰缝 / SurfaceSeam** | 27% 处的静态竖缝（门后露出） | `.seam` |
| **中缝透光 / LightLeak** | 开锁成功后门缝亮起的一线暖光 | `.gap` |
| **充能 / charging** | 按住锁体的连续进度 0→1 | v10 只有两态，我们改成连续量 |
| **开锁 / unlock** | 安全动作：发 BLE 指令 | v10 的"轻点" |
| **推门而入 / enter** | 导航动作：不改锁状态，直接进 App | v10 的"轻点即进"（已修正） |
| **进门 / open** | 门已转开、App 已显示 | `.scr.open` |
| **关门 / close** | 回到门外 | v10 的"往回推" |
| **皮肤 / skin** | 门面材质变体（4 种） | v10 只有一种 |
| **App Index** | 76 项目录（sheet 级，非 Tab） | v10 的「全部」Tab |
