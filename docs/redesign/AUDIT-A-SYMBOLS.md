# AUDIT-A · 方案引用的 API 符号是否真实存在

> 对抗审核员 au-sym · 2026-10-18 · **只读核查，未改动任何源码**
> 核查方式：`tools.grep` 精确模式 + 定点 `read` 行段（未通读任何大文件）。
> 判定口径：✅ = 存在且写法与签名相符 / ❌ = 写法错误或访问方式错误，照抄**编译不过** /
> ❌❌ = 符号**根本不存在**或不可访问 / 未证实 = 该写法在两份方案文档里的**原文**未找到，无法对号入座。
> **红线**：任何 ❌ / ❌❌ 条目若被实施 AI 照抄，会直接红在 `xcodebuild`；`tools/swiftcheck.js` 是静态闸门，未必抓得住访问级错误。

---

## 结论先行（5 条）

1. **符号族本身几乎全是真的**：`DS` 及其 11 个子命名空间、`DS.Motion` 六档、`DS.Metric` 六项、`AXFlags` 四旗标+`reduceMotionSnapshot`、`BatteryCare.appLowBattery`、`axGlass` 三兄弟、`UnlockPrefs` 三项、`StatusParser.rcMsg` —— **全部存在，签名与行号也对得上**。
2. **唯一的 ❌❌ 出在 VK 语法层的调用形式**：`VK.card` / `VK.sectionTitle` / `VK.statusPill` 写成**点号属性**是错的，三个都是 `@MainActor func`；全仓 13 处真实调用一律是 `VK().card(...)` / `VK().sectionTitle(text:count:)` / `VK().statusPill(text:systemImage:tone:)` 或 `VK.current.…`。**而 `PART5-DESTINATIONS.md` 把 `VK.card` 这种错误写法复制了 9 遍**（另有 PART2 1 处、PART7 2 处、PART3 1 处），是本轮最容易批量传染的编译错误。
3. **第 9、10 项是「未证实」而非「错」**：`rotation3DEffect` 用法的原文（含 `perspective` 参数名）在两份方案文档里找不到出处；`.dynamicTypeSize(...accessibility2)` 的原文在 `DECISIONS.md:201` / `PART0-OVERVIEW.md:122` / `PART1-LOCKFACE.md:205` / `PART3-COMPONENTS.md:169`，与 `AccessibilityKit.swift:1336` 的真实调用**不是同一枚修饰符**（细节见 #23、#24）。
4. **两处「方案自己把话说软/说错」要修但不算编译风险**：`DS.Motion.tier` 是 `private`（#20）；`DS.Metric` 的能力被低估（#6 附注）。
5. **无编造**：本表所有行号均来自本次 grep/read 实测；凡未实测的一律标「未证实」。

---

## 一、主表

| # | 方案里的写法 | 真实情况 | 文件:行号 | 判定 |
|---|---|---|---|---|
| 1 | `DS.Space` | `enum Space`：`densityScale` + `xxs/xs/s/m/l/xl/xxl/gutter`（**没有 `xxl` 之外的 `huge`**） | `App/Core/DesignSystem.swift:110-130` | ✅ |
| 2 | `DS.Radius` | `enum Radius`：`card=22 / control=16 / tile=18`（`pill` 已在第 93 批删除，**不可再用**） | `DesignSystem.swift:135-147`（`card` :144 / `control` :145 / `tile` :146） | ✅ |
| 3 | `DS.Hit` | `enum Hit { static let min: CGFloat = 44 }` | `DesignSystem.swift:149` | ✅ |
| 4 | `DS.Icon` | `enum Icon`：`xs=13 / sm=16 / md=20 / lg=26 / xl=44` | `DesignSystem.swift:266-272` | ✅ |
| 5 | `DS.Motion` | `enum Motion`（内部 `tier` 为 private，见 #20） | `DesignSystem.swift:280-343` | ✅ |
| 6 | `DS.Duration` | `enum Duration`：`quick=0.15 / standard=0.25 / slow=0.40`，均为 `TimeInterval` | `DesignSystem.swift:349-353` | ✅ |
| 7 | `DS.Metric` | `enum Metric`：`dial/rowMinH/tlGap/emptyMascot/heroTexture/digitDesign` 六项齐全 | `DesignSystem.swift:152-195` | ✅ |
| 8 | `DS.Palette` | `enum Palette`：`canvas/surface/surfaceAlt/accent/accentText/onAccent/hairline/…`；消费点遍布全仓 | `DesignSystem.swift:368-486` | ✅ |
| 9 | `DS.Haptics` | `@MainActor enum Haptics`：`tick`(light) / `trigger`(medium)，**只有这两档**。⚠ 从**非主 actor**（ButtonStyle/ToggleStyle 的 makeBody）调会被 Swift 6 判错 | `DesignSystem.swift:254-258` | ✅ |
| 10 | `DS.isNightDim` | `static var isNightDim: Bool`，22:00–06:00 为 true | `DesignSystem.swift:261-264` | ✅ |
| 11 | `DS.Gradient` | `enum Gradient`：`hero`/ `screenMesh`/ `screen`/ `button`（**没有 `dxScreenBackground` 之类成员**；带"降级"的屏幕底在 `dsScreenBackground` 里回落线性渐变） | `DesignSystem.swift:620-664` | ✅ |
| 12 | `DS.Motion.summon` | `static var summon: Animation` — calm=.easeOut(0.12)，默认 .spring(response:0.35, damping:1.0) | `DesignSystem.swift:299-304` | ✅ |
| 13 | `DS.Motion.fling` | `static var fling: Animation` — calm=.easeOut(0.12)，默认 damping 0.82 | `DesignSystem.swift:308-313` | ✅ |
| 14 | `DS.Motion.quick` | `static var quick: Animation` — calm 0.10 / lively 0.22·0.68 / 默认 0.22·0.9 | `DesignSystem.swift:315-321` | ✅ |
| 15 | `DS.Motion.standard` | `static var standard: Animation` — calm 0.16 / lively 0.45·0.68 / 默认 0.4·0.85 | `DesignSystem.swift:322-328` | ✅ |
| 16 | `DS.Motion.soft` | `static var soft: Animation` — easeInOut 0.12/0.34/0.25 | `DesignSystem.swift:329-335` | ✅ |
| 17 | `DS.Motion.exit` | `static var exit: Animation` — easeOut 0.08/0.20/0.15 | `DesignSystem.swift:336-342` | ✅ |
| 18 | `DS.Motion.calm` | ❌❌ **不是成员**。calm 是 `tier` 的**取值**，六个属性各自 `switch tier { case "calm": … }`；`DS.Motion.calm` 编译不过（`PART4-MOTION.md:79` 表格里出现过这个写法） | `DesignSystem.swift:286-293`（tier）、:299-342（六档内部分支） | ❌❌ |
| 19 | `DS.Metric.dial` | `static var dial: CGFloat`，读 `kf_dial_size`，白名单 160/176/200（默认 176） | `DesignSystem.swift:153-156` | ✅ |
| 20 | `DS.Motion.tier` | `private static var tier: String`。**新文件（LockFaceStyle.swift 等）读不到，`DS.Motion.tier` 会编译不过**；也没发现任何公开入口。外部只能读 `DS.Motion.xxx` 的成品 Animation，或新增一个 `internal` 档位读点 | `DesignSystem.swift:286`（`private` 就在该行）；`PART1-LOCKFACE.md:256`、`PART0-OVERVIEW.md:56`、`PART4-MOTION.md:110` 都写了这个不可访问的写法 | ❌ |
| 21 | `DS.Metric.rowMinH` | `static var rowMinH: CGFloat`，`kf_row_h == "tall" ? 60 : 44` | `DesignSystem.swift:160-162` | ✅ |
| 22 | `DS.Metric.tlGap` | `static var tlGap: CGFloat`，读 `kf_tl_gap`（tight 0.5 / loose 2.0），**返回值含 `DS.Space.m` 密度缩放** | `DesignSystem.swift:166-174` | ✅ |
| 23 | `DS.Metric.emptyMascot` | `static var emptyMascot: Bool { !Milestones.plainMode }` — **是 Bool，不是图形/尺寸** | `DesignSystem.swift:178` | ✅ |
| 24 | `DS.Metric.heroTexture` | `static var heroTexture: String`，白名单 `"grid"`/`"grain"`/`""` | `DesignSystem.swift:183-186` | ✅ |
| 25 | `DS.Metric.digitDesign` | `static var digitDesign: Font.Design`，`kf_digit_font == "plain" ? .default : .rounded` | `DesignSystem.swift:192-194` | ✅ |
| 26 | `DS.Metric` 可直接读 | ⚠ 方案（AUDIT-B 第 9 问口径）以为 `DS.Metric.dial` 是 "private 所在文件的 internal 成员"：**其实不是** —— `enum Metric` 是 `internal`，六个成员全 `internal`，**任何新文件读 `DS.Metric.dial` 都合法**，无需加 `public`、无需挪文件。唯一要留意的是 `Metric` 里几个 `static func` 才是 private | `DesignSystem.swift:152`（`enum Metric` 无访问修饰符 = internal） | ✅ |
| 27 | `AXFlags.reduceMotionSnapshot` | `nonisolated static var reduceMotionSnapshot: Bool { reduceMotionBox.withLock { $0 } }` —— **真实存在**，底层 `Locked(false)`，由 `refreshSnapshots()`（启动 + 回前台）刷新。方案说"非 MainActor 快照"**准确** | `App/Core/AccessibilityKit.swift:55-57` | ✅ |
| 28 | `AXFlags.reduceMotion` | `static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }`；`AXFlags` 整族 `@MainActor` | `AccessibilityKit.swift:15-16`（`@MainActor` / `enum AXFlags`）、:35 | ✅ |
| 29 | `AXFlags.highContrast` | `static var highContrast: Bool { UIAccessibility.isDarkerSystemColorsEnabled }`（**官方读法就是它**，注释里记了历史打脸） | `AccessibilityKit.swift:22` | ✅ |
| 30 | `AXFlags.reduceTransparency` | `static var reduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }` —— **属性，无括号** | `AccessibilityKit.swift:39` | ✅ |
| 31 | `BatteryCare.appLowBattery` | `static var appLowBattery: Bool`（电量 ≤20%）；`enum BatteryCare` 是 internal；唯一消费点 `DS.Motion.tier` | `App/Core/BatteryCare.swift:69`（enum）、:102（成员）；`DesignSystem.swift:290` | ✅ |
| 32 | `axGlass(_:)` @388 | `func axGlass(_ radius: CGFloat) -> some View`（`extension View`） | `AccessibilityKit.swift:388` | ✅ |
| 33 | `axGlassCircle()` @393 | `func axGlassCircle() -> some View` | `AccessibilityKit.swift:393` | ✅ |
| 34 | `axGlassCapsule()` @400 | `func axGlassCapsule() -> some View`（胶囊没有半径参数，所以单独开一枚） | `AccessibilityKit.swift:400` | ✅ |
| 35 | `VK.card`（点号属性） | ❌❌ **不是属性**，是 `@MainActor func card<Content: View>(tint: Color? = nil, @ViewBuilder _ content: () -> Content) -> AnyView`。正确形式 `VK().card { … }` / `VK().card(tint: …) { … }`；真实调用点 `LockKeeperApp.swift:1729` | 定义 `App/Core/VariantGrammar.swift:81`；`struct VK` :37、`static var current: VK` :40 | ❌❌ |
| 36 | `VK.sectionTitle`（点号属性） | ❌❌ 方法：`func sectionTitle(text: String, count: Int?) -> AnyView`，用 `VK().sectionTitle(text:count:)`；真实调用点 `LockKeeperApp.swift:1738` | `VariantGrammar.swift:113` | ❌❌ |
| 37 | `VK.statusPill`（点号属性） | ❌❌ 方法：`func statusPill(text: String, systemImage: String, tone: Color) -> AnyView`，用 `VK().statusPill(text:systemImage:tone:)`；真实调用点 `DesignSystem.swift:801` | `VariantGrammar.swift:138` | ❌❌ |
| 38 | `.vkFont(...)` | `func vkFont(_ base: Font, weight: Font.Weight? = nil) -> some View`（`extension View`）—— 用法正确 | `VariantGrammar.swift:462` | ✅ |
| 39 | `VariantToggle` | **三个顶层重载**（非类型）：`(LocalizedStringKey, isOn:)` / `<S: StringProtocol>(S, isOn:)` / `(isOn:label:)`；配套 `struct VariantToggleStyle: ToggleStyle` | `VariantGrammar.swift:414 / :419 / :424`；style :398 | ✅ |
| 40 | `VKTypography.font(...)` | `static func font(_ base: Font, weight: Font.Weight?) -> Font` —— **weight 无默认值，必须显式传**（`weight: nil`）；`struct VKTypography: ViewModifier`。真实用例 `SecurityCenterView.swift:134` | `VariantGrammar.swift:437`（struct）、:450（font） | ✅ |
| 41 | `variantPlate` | `func variantPlate(_ style: Color, _ shape: PlateShape, edge: Color? = nil) -> AnyView`；`enum PlateShape { capsule, tile, control, iconBadge }` —— **没有 `plate` / `card` case** | `VariantGrammar.swift:261`；`PlateShape` :226-255 | ✅ |
| 42 | `ContentUnavailableView` 仓内用法 | 3 处，全部在 `EmptyState` 包装里（方案说"复用既有空态"成立） | `DesignSystem.swift:1022 / 1046 / 1105` | ✅ |
| 43 | `GlassEffectContainer` 仓内用法 | 2 处 | `DeviceHomeView.swift:1495 / 1503` | ✅ |
| 44 | `symbolEffect` 仓内用法 | 8 处 | `DeviceHomeView.swift:1001`、`RecordsView.swift:2282`、`UnlockDial.swift:916/924/926/927/928/930` | ✅ |
| 45 | `contentTransition` 仓内用法 | 9 处 | `UnlockDial.swift:926/928/945`、`Sheets.swift:838`、`CredentialsView.swift:2068/2071`、`DesignSystem.swift:878/880/925` | ✅ |
| 46 | `matchedGeometryEffect` 仓内用法 | **0 处（全仓未用过）**。方案要新引入，属新增依赖，必须自带降级路径 | grep `App/` 0 命中 | ❌❌（作为"既有用法"引用） |
| 47 | `navigationTransition` 仓内用法 | **0 处（全仓未用过）** | grep `App/` 0 命中 | ❌❌（作为"既有用法"引用） |
| 48 | `rotation3DEffect` | **有先例，2 处**，均为 `(x: 0, y: 1, z: 0)` 轴翻转（Hero 卡翻面）。**两处都没写 `perspective:`** | `DeviceHomeView.swift:722`、`:725` | ✅（存在）／`perspective` **未证实** |
| 49 | `perspective` 参数真实名与类型 | SwiftUI 签名是 `rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`，`perspective` 为 `CGFloat`（**类型为 Double 家族，不是 `Angle`**）。⚠ 这是框架知识，**未在本仓取证到任何使用实例**（仓内 0 处使用 `perspective`）→ 参数名按 Apple SDK 签名，取值按 PART1 §11 坑 2 现场调 | 仓内 :722/:725 均未用；方案原文 `PART1-LOCKFACE.md:301-310` | 未证实 |
| 50 | `.dynamicTypeSize(...accessibility2)` 这种"区间/封顶"写法 | 方案原文 4 处：`DECISIONS.md:201`、`PART0-OVERVIEW.md:122`、`PART1-LOCKFACE.md:205`、`PART3-COMPONENTS.md:169`。⚠ **注意**：`.dynamicTypeSize(...accessibility2)` 是 `PartialRangeThrough` 形式；**`.dynamicTypeSize(AXFlags.typeSize())`（精确档）无法表达"封顶"** | 仓内先例：`LockKeeperApp.swift:1336`（精确档形式，非区间形式） | ❌ |
| 51 | `UnlockPrefs.mode` | `static var mode: String`，`kf_gesture_mode` ∈ hold/triple/charge，非法回落 `"hold"`；`modes` 数组在 :6 | `App/UI/UnlockDial.swift:5`（enum）、:7-10 | ✅ |
| 52 | `UnlockPrefs.tapDirect` | `static var tapDirect: Bool { getBool("kf_tap_direct") && mode == "hold" }` | `UnlockDial.swift:12` | ✅ |
| 53 | `UnlockPrefs.gestureHint` | `static var gestureHint: String` — hold「可按住圆盘，也可上滑」/ triple / charge 三句，句式统一带"可" | `UnlockDial.swift:17-23` | ✅ |
| 54 | `StatusParser` 有无 rc 文案表 | 有：`static let rcMsg: [Int: String]`（码 0–27，含 4/…缺号），文案表；配套 `static func rcMessage(_ rc: Int) -> String`（未命中回落 `"错误码 \(rc)"`）、`rcHint(_:) -> String?`、`rcFriendly(_:) -> String` | `App/Core/StatusParser.swift:42`（enum）、:154-161（rcMsg）、:162 / :166-181 | ✅ |
| 55 | `StatusParser` 访问方式 | `enum StatusParser` 为 internal、无 `@MainActor`，全部 `static`，**可直接跨文件调用**（例 `LockService.swift:348`、`HardwareService.swift:242`）。新文件同样可用 | `StatusParser.swift:42` | ✅ |

### 表内注释

- **#18 补充**：方案文档里 `DS.Motion.calm` 只出现在 `PART4-MOTION.md:79` 的曲线词典表格，且那句本身是"入场 = calm 的 easeInOut 档"，**读法上更像描述而非代码**；但实施 AI 照抄符号就会红。建议改成"calm 档下的 `DS.Motion.standard`"。
- **#21 补充**：`DS.Motion.tier` 在方案里出现 4 处（`PART0-OVERVIEW.md:56`、`PART1-LOCKFACE.md:256`、`DECISIONS.md:112`、`PART7-ACCEPTANCE.md:155`），其中 PART0/PART7 是"纪律"性表述（"必须通过 `DS.Motion.tier`"），**作为纪律成立**（读 `DS.Motion.xxx` 就等于走 tier）；但 PART1 §9 接线表是"照抄签名"语境，那里的 `DS.Motion.tier` 会编译不过。
- **#35-#37 补充**：`VK` 是 `struct` 且所有语法件都是**实例方法**（`@MainActor`）；全仓真实调用 13 处：`VK().…` 4 处 + `VK.current.…` 3 处（含 PrimaryAction/Secondary/Destructive chrome）+ 文档引用。**`VK.card` 这类静态点号写法全仓 0 处**。另外 `card/sectionTitle/statusPill` 都标了 `@MainActor`，从非主 actor 上下文调用要显式跳主 actor。

---

## 二、必须修正的方案条目清单（只列 ❌ 与 ❌❌）

按"照抄后爆炸半径"排序：

| 序 | 修正对象（文档:行） | 错在哪 | 改成什么 | 级别 |
|---|---|---|---|---|
| 1 | `PART5-DESTINATIONS.md:42,49,56,63,70,77,84,91,98`（**9 处同一句**） | `VK.card` / `VK.sectionTitle` / `VK.statusPill` 当属性用 | `VK().card { … }`、`VK().sectionTitle(text:count:)`、`VK().statusPill(text:systemImage:tone:)` | ❌❌ |
| 2 | `PART3-COMPONENTS.md:81`、`PART2-NAV-IA.md:57`、`PART7-ACCEPTANCE.md:15,97` | 同上（合计 4 处） | 同上；`PART3:81` 已经在括号里给了正确行号（81/113/138），只要修写法 | ❌❌ |
| 3 | `PART1-LOCKFACE.md:256`（§9 接线表） | `DS.Motion.tier` 是 `private`，新文件不可访问 | 改为"只读 `DS.Motion` 六档成品 Animation（tier 在其内部生效）"；若确需读档位，须先在 `DesignSystem.swift:286` 新增 internal 读点 | ❌ |
| 4 | `PART4-MOTION.md:79` | `DS.Motion.calm` 不存在 | 改为"`calm` 档下的 `DS.Motion.standard`（=.easeInOut 0.16）" | ❌❌ |
| 5 | `PART1-LOCKFACE.md:205` + `PART0-OVERVIEW.md:122` + `DECISIONS.md:201` + `PART3-COMPONENTS.md:169` | `…` 省略号形式的封顶写法**在本仓无先例**；照 `LockKeeperApp.swift:1336` 抄会抄成精确档，**丢掉落字封顶语义** | 写成完整可编译形式 `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`，并说明它与 :1336 精确档的叠加关系（哪个在外层生效） | ❌ |
| 6 | 任何把 `matchedGeometryEffect` / `navigationTransition` 当"仓内既有能力"引用的条目（`EVIDENCE-DOCS.md:545` 已如实标注 0 命中，但下游 PART 文档引用时未带这条前提） | 全仓 0 处，是**新增 API 依赖**（iOS 18+ 的 `.navigationTransition(.zoom)`） | 每处补一句"新增，需自带降级路径（reduceMotion / 低版本）" | ❌❌（作为"既有用法"） |
| 7 | `PART1-LOCKFACE.md:301-310` | `perspective:` 参数**在本仓 0 用例**，无法用 grep 复核；方案已声明"不预设起始值"（这条判断是对的），但表格里仍以"坑 2 的换算提示"口吻出现 | 保留"现场调"的结论，同时显式标注：参数名 `perspective` 取自 Apple SDK 的 `rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`（`CGFloat`），**本仓未取证**，真机首跑需先验证参数名不报错 | 未证实 |

### 需要方案作者注意但**不算错**的两条（不计入 ❌ 清单）

- `DS.Metric` 的可见性被低估（#26）：`enum Metric` 及六个成员全是 internal，新文件直读合法 —— 别为它加 `internal`/`public` 而改动 `DesignSystem.swift`。
- `AXFlags` 整族是 `@MainActor`（#28-#30）：只有 `reduceMotionSnapshot` / `reduceMotionBox` / `refreshSnapshots()` 走了 `nonisolated`。新文件在 `ButtonStyle.makeBody` 之类非隔离处**只能读 `reduceMotionSnapshot`**，读 `AXFlags.reduceMotion` 会红。

---

## 三、取证方法与未覆盖项（透明声明）

- 方法：`grep` 精确模式一次取全部命中（`^(enum|struct|extension)\s+DS\b`、`^\s+(static|nonisolated)[^\n]*\b\w+`、`func\s+axGlass\w*`、`VK\.(card|sectionTitle|statusPill)|vkFont|variantPlate|VariantToggle` 等），再对 `DesignSystem.swift:100-670`、`AccessibilityKit.swift:10-407`、`VariantGrammar.swift:196-470`、`StatusParser.swift:1-185`、`UnlockDial.swift:1-42`、`BatteryCare.swift:95-109` 做定点行段读取。**未通读任何大文件**。
- 未覆盖：Android/Compose 侧符号（不在本任务 12 项内，由 AUDIT-C 与 PART6 负责）；`DS` 全部成员逐一枚举（只查了本任务点名的 11 个 + Motion/Metric 成员）；SwiftUI 框架 API 的参数名与类型（`perspective`）**依赖 Apple SDK 知识，非仓内取证**，已在 #49 标明。
- 本文件为本次核查**唯一写入物**；未修改任何源码、配置或其他文档。
