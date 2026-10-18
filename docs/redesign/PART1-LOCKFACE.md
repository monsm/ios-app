# PART 1 · LockFace 门面层（iOS 实施规格）

> 前置：先读 `DECISIONS.md`（D1–D10 全部 LOCKED）。
> 本文只描述**怎么做**；与 v10 原型数值不一致处，以本文为准（本文已按真机 pt 重新标定）。
> 所有数值都是**验收值**：截图量出来必须落在给定区间内。

---

## 1. 层级顺序（唯一权威，做错这一条全盘返工）

**（2026-10-18 实测更正，见下）先认清现状**：
- 根视图是 `RootView.body → rootChrome → rootGroup → rootCore`，最内层是 **`Group`（不是 ZStack）**
  （`LockKeeperApp.swift:1305-1334`）。
- `rootGroup` **只有两种形态**：首启引导 `OnboardingView` / `mainTabsChrome`。
  原话在 `LockKeeperApp.swift:1319-1320`：「2026-10-17 拍板 A: 应用锁启动门禁已删……进 App 只分两种形态」。
- ⚠️ **全仓 App/ 下不存在 `struct AppLockView`，也不存在 `DecoyView`**（grep 实测 0 命中，只有注释提到历史）。
  `decoyMode` / `appUnlocked` 作为**状态位**仍在，被大量守卫读（如 `:199`、`:244`、`BackupStudioKit.swift:139`）。
  ⇒ **实施 AI 不许"补回"这两层**：那等于新增第二套门禁。

**目标层级（本轮要接出来的形状）**：

```
View (root)
 ├─ 首启未完成 → OnboardingView（原样，门不参与）
 └─ 否则 → ZStack ← 【本轮新增这一层 ZStack】
      ├─ 3. Sheets / fullScreenCovers   ← 现有，直接挂在 mainTabs(:1246/:1252) 与 mainTabsChrome(:1270)，不动
      ├─ 2. mainTabsChrome（4 Tab）      ← 现有；门关着时 opacity 0 + allowsHitTesting(false)
      └─ 1. LockFace（本文件新增）        ← 最底
```

**规则**
- `LockFace` 在层级 **1**（最底）。MainTabs 在它上面，靠 `opacity/scale` 显隐——
  **不许用 `if` 条件插入/移除主界面**：那会重建 `CredentialsView` 的 `@State`，
  本仓已有注释记录过这个坑（`LockKeeperApp.swift:1065` 附近，Tab 内容的 @State 由 TabView 持有）。
- **首启引导期间不渲染门**：一把锁都没有的人对着一扇门会觉得莫名其妙（PART0 的 M2）。深链/小组件同理（现有 `pendingRoute` 机制不改）。
- **访客模式（377）不受门影响**：门只做视觉，不放行任何目的地；
  仍然只能走 `requestRoute`，`guestBlockedTabs` 两条路径照旧生效。**门层禁止直接写 `tabSelection`**。
- 门开着时，LockFace 必须 `.accessibilityHidden(true)`（VoiceOver 不许读到门后的东西）。
- 门关着时，MainTabs 必须 `.accessibilityHidden(true)` 且 `.allowsHitTesting(false)`。

---

## 2. 几何（基准：iPhone 393×852pt，全部用 pt，不用 px）

| 元素 | 值 | 容差 | 备注 |
|---|---|---|---|
| 中缝位置 | 屏幕宽度 50% | ±0 | 两扇门各占一半 |
| 锁体直径 `plateD` | **由 `DS.Metric.dial` 映射**：160→220 / 176→240 / 200→272，再 `min(…, screenW*0.68)` | ±2pt | 见 D12。393pt 宽 + 默认档 → 240pt |
| 锁体中心 Y | 屏幕高度 46%（含安全区） | ±8pt | 视觉中心偏上，给底部提示留位 |
| 凹槽环 | 外扩 **9pt**（即 `plateD + 18`） | ±1pt | 对应 v10 `.groove{inset:-9px}`，1:1 照搬 |
| 玻璃面内缩 | 8pt | ±1pt | `.face{inset:8px}` |
| 字形尺寸 | 60pt | ±2pt | v10 `62px` |
| 门板厚度边 | 16pt | ±2pt | 中缝两侧的明暗边 |
| 中缝光纤宽度 | 3pt | ±0.5pt | `.gap` |
| 标题左边距 | **16pt**（`DS.Space.gutter`） | ±0 | **D15 第 1 条**：不用 v10 的 26pt，否则开门前后标题会横向跳位 |
| 标题基线上边距 | safeArea.top + 12pt | ±4pt | 不用 52pt 硬值（刘海高度机种不同） |
| 门面大标题 | **34pt semibold** | ±0 | **D15 第 2 条**；与门后 App 的 h1 同字号，开门前后只有位置变 |
| 底部提示语 | **13pt（`.footnote`）** | ±0.5pt | **D15 第 3 条**；不用 v10 的 12.5px |
| 提示文案底边距 | safeArea.bottom + 32pt | ±4pt | v10 是 74px 硬值，**不要照抄** |
| 锁体投影 | offset (14, 20)pt, blur 26, `Palette.text` 12% | — | 光源在左上 |
| 门板压暗（开时） | 黑 32% | ±4% | `.leaf:after` |

> **不许用 `.frame(height: 862)` 之类整屏硬值**：必须是 `GeometryReader` + 相对定位，
> 否则 iPhone SE / iPad / 分屏全崩。iPad 上锁体直径上限 240pt，其余等比。

---

## 3. 材质（零位图，全部程序化）

### 3.1 门面 `DoorSurface`
三层叠，顺序不可换：

1. **底色斜向渐变**（主光方向：左上 → 右下）
   浅色：`#FBF9F5 → #F6F3ED (46%) → #EDE9E1`，角度 102°（从正上方顺时针量）。
   深色：`#141618 → #0F1113 (46%) → #0A0B0C`。
2. **光位叠加**
   - 右上角径向高光：中心 (78%, 4%)，半径 46%×30%，白 95% → 透明 64%。
   - 左下角压暗：中心 (18%, 100%)，半径 52%×40%，黑 10% → 透明 70%。
   - 左右边缘暗角：96° 线性，黑 5.5% → 透明 22% → 透明 70% → 黑 4.5%。
3. **噪声纹理**：**照抄既有实现** `DS.HeroTexture` 的 "grain" 档
   （`DesignSystem.swift:214-230`）——固定种子的线性同余画点，注释原文已经写明原因：
   "纹理必须每次重建都长一样，否则外观种子每变一次，卡面上的点就整体重掷一次，看着像闪了一下噪点"。
   门面做法：同一 LCG，点数按面积放大（Hero 卡是 130 点；门面约 6 倍面积 → 约 700-800 点，
   点半径 0.9-1.4），`blendMode(.multiply)`，整体 opacity 0.30（深色 0.18），
   外层 `.drawingGroup()` 光栅化一次。
   **禁止** `Double.random(in:)` / `arc4random`。

**验收**：截图里门面不能出现可见的"带状色阶"（banding）；若出现，把噪声 opacity 提到 0.35。

### 3.2 门缝 `DoorGap`（50% 处，两扇门的交界）

对应 v10 的 `.leaf .edge`（`v10.html:175-177`，**实例**在 `:240` 与 `:244`）：

| 侧 | 宽度 | 渐变 |
|---|---|---|
| 左扇右缘 | 16pt | 深棕 `rgba(26,15,3,.52)` 起 1pt → `rgba(40,24,8,.20)` 至 22% → `rgba(40,24,8,.06)` 至 46% → 透明 |
| 右扇左缘 | 16pt | 白 `rgba(255,255,255,.92)` 起 1.3pt → 白 34% 至 16% → 透明 |

**为什么不对称**：左扇边缘「吃暗」、右扇边缘「吃亮」，一条缝因此有了厚度（v10 自述「光的做法」）。
**做成对称即判错。**

> ⚠️ **对抗审核更正（2026-10-18）**：上一稿里我还写了一个「27% 处的静态装饰缝 `SurfaceSeam`」，
> **那是错的，现已整段删除**。原因：v10 确实定义了 `.seam` 与 `.seam:after`（`v10.html:54-58`），
> 但**整个 HTML 里没有任何元素用过它** —— 实测 `class="seam"` 出现 **0 次**，
> 而 `.leaf .edge` 在 `:240`/`:244` 有真实实例。
> **那是 v10 作者的死 CSS，不是设计意图。**
> ⇒ 实施 AI **不要**去实现任何 27% 的竖缝；门面上**只有 50% 一处**竖缝。
> （教训，适用于本包全部规格：**CSS 里定义了 ≠ 设计里有**，一切以 HTML 实例为准。）

**验收**：放大 4 倍看 50% 处的门缝，左暗右亮不对称可见。

### 3.3 锁体 `LockPlate`（5 层，从外到内）
1. `groove`：外扩 8pt 的圆环，`#DCD5C9 → #EBE6DC(42%) → #F3EFE7`，
   内阴影 `y:3, blur:6` 黑 26% + 下沿 `y:-1` 白 95% ⇒ 读作"铣进去的"。
2. `ring` 金属倒角：**`AngularGradient`**(startAngle: 158°)，色停
   `#FEFDFB, #C3BCB1(11%), #FBF9F5(26%), #B6AFA4(44%), #EFEBE3(58%), #C8C1B6(74%), #FCFDFA(88%), #C3BCB1`。
   ⇒ 亮面随角度变化，这是金属的唯一判据。
3. `face` 深色玻璃：`RadialGradient` 中心 (26%, 4%)，`#3A4044 → #202528(34%) → #0F1214(70%) → #080A0B`；
   内阴影 `y:4, blur:9` 黑 90%；内描边 1pt 黑 60%。
4. `bounce` 地面反光：底部 46% 高度的椭圆径向，白 10% → 透明 72%。
5. `spec` 镜面高光条：旋转 **-24°**，宽 136%，高光带在 49% 处最亮（白 52%），两侧渐隐，
   `blur(3pt)`，`opacity 0.9`；**随指针微移 ±9pt / ±7pt**（见 §5 光照跟随）。

> **夜间降亮度**：`DS.isNightDim`（22:00–06:00，`DesignSystem.swift:259-264`）已在仓内生效，
> 门面的 sheen、中缝亮光、锁体辉光、spec 高光**必须接这一条**（只降装饰层峰值，不降文字对比度）。
> 夜里开锁被自己的锁闪一下，是这类设计最容易翻车的地方。

字形：**不是纯白**，是 `#FFFFFF → #F4F0E9(50%) → #C6C0B5` 的自上而下渐变填充，
外加 `shadow(y:1, black 55%)` + `shadow(blur:14, #FFF4E2 10%)` 两层。

字形两个态（闭环 / 开环）= v10 的两个 SVG path，请**照抄 path 数据**（`v10.html:256-257`），
转成 SwiftUI `Path` 或用 `Shape` 手写；闭环→开环 = 260ms 交叉淡入 + `scale 0.9→1`。

---

## 4. 状态机（唯一实现，禁止第二处）

```swift
enum LockFacePhase: Equatable {
    case locked            // 门关着，可充能
    case charging(CGFloat) // 0…1，连续量，唯一驱动
    case unlocking         // 已发出 BLE 开锁，等回包
    case peeking           // 成功：中缝透光（门还没转）
    case opening           // 门在转（820ms）
    case open              // 门后就是 App
    case closing           // 门在转回来
    case failed(String)    // 失败原因（StatusParser 的 rc 文案），门**完全不动**
}
```

**迁移表（唯一真值，实施时逐行对照）**

| 当前 | 事件 | 下一个 | 副作用 |
|---|---|---|---|
| `.locked` | 按住开始 | `.charging(0)` | 触觉 light；盘 scale→0.972 |
| `.charging(p)` | 每 16ms 更新 | `.charging(p')` | 环 trim / 光晕 / 刻度 全读同一个 p |
| `.charging(1)` | — | `.unlocking` | 触觉 medium；调 `LockService.unlock()` |
| `.unlocking` | 成功 | `.peeking` | **t=0**：字形换开环(260ms) + 中缝光 0→1(420ms) |
| `.peeking` | 340ms 后 | `.opening` | 门转 ±106°（820ms）；标题/提示/锁体淡出(260ms) |
| `.opening` | 同刻（+140ms） | — | App 层 opacity 0→1(460ms) + scale .986→1(700ms) |
| `.opening` | 760ms | `.open` | 中缝光淡出；门层 `.accessibilityHidden(true)` |
| `.unlocking` | 失败 | `.failed(rc文案)` | 锁体抖 3 次 + 触觉 error；**门不动、中缝不亮** |
| `.failed` | 1.2s 或再按 | `.locked` | 抖回原位 |
| `.open` | 左缘右拖 ≥96pt / 点「关门」/ Esc | `.closing` | App 淡出；门转回；780ms 后回 `.locked` |
| `.open` | 后台 >5 分钟 | `.locked`（冷态） | 见 §7 `LockFacePolicy` |
| `.charging` | 松手且 p<1 | `.locked` | 环 180ms 回零 |

**红线**
- `.failed` 时门**一个像素都不许动**。"门动了 = 锁开了"是用户唯一可靠的读法。
- `.peeking` 只能在**收到成功回包之后**进入；不许用"动画放完就算了"。
- 全流程只有一个 `Task`（超时用 `Task.sleep` + 取消），不许用 `Timer` 分段。

---

## 5. 手势与光照跟随

| 手势 | 区域 | 阈值 | 结果 |
|---|---|---|---|
| 按住充能 | 锁体（`plateD` 圆内 + 8pt 容差） | `UnlockPrefs.mode` 决定 | 开锁 |
| 三连点 / 旋转充能 | 同上 | 档位设置 | 开锁（行为沿用现有） |
| 双击直开 | 同上 | 仅 `hold` 档且 `tapDirect` | 开锁 |
| **推门而入** | **屏幕左缘 24pt 带内右拖** | ≥72pt | 进门，**不改锁状态** |
| 关门 | App 层左缘 24pt 带内右拖 | ≥96pt | 回门外 |
| 键盘 Esc | 任意 | — | 关门 |

**光照跟随**：`spec` 层的 offset = 归一化指针位置 × (9pt, 7pt)。
`reduceMotion` 或 `reduceTransparency` 下**关闭**跟随（不做成 0 位移的假跟随）。

**反例（必须避免）**：v10 在 `pointermove` 里同时调 `scr.classList.remove('open')`（`v10.html:449`），
一旦异常整段手势失效。SwiftUI 侧对应要求：**手势回调里不许改状态机相位以外的任何东西**。

---

## 6. 无障碍（照抄不可省）

| 项 | 要求 |
|---|---|
| VoiceOver 元素 | 锁体 = 一个 `accessibilityElement`，label「开锁，前门」，value = 当前相位文案，hint = `UnlockPrefs.gestureHint` |
| **双击激活** | `accessibilityActivate()` 必须能开锁：hold 档 → 自动充能 1.2s 后触发（VoiceOver 用户按不住） |
| 门开着 | LockFace `.accessibilityHidden(true)`；焦点移到页面标题；MainTabs 恢复可访问 |
| 转子 | 沿用 `voRotorIndex`（状态 / 电量 / 连接），门层不新增转子项 |
| 降低动态效果 | 门不转：200ms 交叉淡入；中缝光不闪；锁体不逐帧充能（直接到终态）；高光不跟随 |
| 降低透明度 | 门面用实色（去噪声/光位叠加可留），锁体保留描边，中缝白线保留 |
| 增强对比 | 提示文案用 `Palette.text`（不用 textSub）；中缝亮线加粗到 2pt |
| 动态字体 | 标题/正文/提示跟随，**统一封顶到 accessibility2**（D15 第 7 条）。⚠️ 不要写 `.dynamicTypeSize(...accessibility2)`（区间语义，仓内 0 先例）；照抄 `LockKeeperApp.swift:1336` 的 `AXFlags.typeSize()` 精确档写法。最大字号下标题换行到 2 行，**锁体几何不缩放** |
| 触达 | 锁体 ≥ 44pt（远大于）；「关门」按钮 ≥ 44×44pt；「进入」小按钮 ≥ 44×44pt |
| 读数 | 电量/时长等一律 `.monospacedDigit()` 且跟随 `kf_digit_font`（**D15 第 6 条**） |
| Switch Control | 锁体必须可被扫描选中（`isButton` trait） |

---

## 7. 入口策略 `LockFacePolicy`（用户想不到但一定会问）

一个纯函数，决定启动/回前台时**是否展示门**：

| 场景 | 结果 | 理由 |
|---|---|---|
| 冷启动 | 展示门 | 仪式感 |
| 从后台回来，间隔 < 5 分钟 | 不展示（保持上次状态） | 频繁开关会烦 |
| 从后台回来，间隔 ≥ 5 分钟 | 展示门（`.locked`） | 回到"门口"的心智 |
| 深链 `kf://records?k=…` | **不展示门**，直达目的地 | 小组件/通知点进来还要推门 = 荒谬 |
| 小组件"开锁"按钮 | 不展示门，直接执行开锁 | 同上 |
| Siri / AppIntent | 不展示门 | 同上 |
| 首启引导未完成 | 门不渲染（`OnboardingView` 全屏） | 还没有锁，门没有意义 |
| 设置 `kf_start_at_door = false` | 永不展示 | 高级用户开关（默认 true） |

间隔阈值写成常量 `LockFacePolicy.revealAfter: TimeInterval = 300`，
**Android 端必须用同一个 300**（见 PART 6）。

---

## 8. 门面皮肤（D6）

`LockFaceSkin`：`.wood`(默认) / `.metal` / `.darkGlass` / `.frosted`。
皮肤只改 4 个参数：底色渐变三停、噪声 opacity、倒角亮度系数、投影强度。
**几何、中缝位置、锁体尺寸、开门角度在所有皮肤下逐字相同。**

| 皮肤 | 底色（浅色档） | 倒角系数 | 噪声 | 投影 |
|---|---|---|---|---|
| wood | `#FBF9F5/#F6F3ED/#EDE9E1` | 1.0 | .30 | 1.0 |
| metal | `#F2F3F4/#E4E6E8/#D3D6D9` | 1.35 | .18 | 1.15 |
| darkGlass | `#2A2D31/#1C1F22/#101214` | 1.5 | .12 | 1.3 |
| frosted | `#FFFFFF/#FAFAFA/#F2F2F2` | 0.7 | .22 | 0.75 |

深色模式下上表整体走深色档（DECISIONS D4）。


---

## 9. 与既有实现的接线点（**2026-10-18 对抗审核后重写：全部为可直接照抄的真实签名**）

> 上一稿写的是「照抄 UnlockDial 里既有的调用」——**那是错的**，UnlockDial 里根本没有 LockService 调用。
> 下面每一行都经 audit 实测核对。

| 要做什么 | **真实入口（照抄）** | 证据 |
|---|---|---|
| **发起开锁** | `app.requestUnlock()` —— **唯一正确入口** | `LockKeeperApp.swift:488` |
| ↳ 真正下发 | 由 `requestUnlock` 内部走到 `try await lock.unlock(mac:pinDec:)`，返回 rc | `LockKeeperApp.swift:594/599` → `Services/LockService.swift:447` |
| ⛔ **禁止** | **不要**在新代码里直连 `LockService`：`requestUnlock` 内含三道闸（296 只读 / 244 去重 / 250 二次锁），绕过它们 = 绕过安全策略 | audit-B ❌❌ |
| UnlockDial 的角色 | 它是**纯视图**：按下完成点只调 `action: () -> Void`（`UnlockDial.swift:323`，触发于 `fire()` `:886`）。门面复用它的**视觉与手势**，但开锁动作走 `requestUnlock` | audit-B |
| 手势档位与提示 | `UnlockPrefs.mode` / `UnlockPrefs.tapDirect` / `UnlockPrefs.gestureHint` | `App/UI/UnlockDial.swift:7 / :12 / :17` |
| **失败文案** | 用 **`StatusParser.rcFriendly(rc)`**（:181，= `rcHint` 兜底 `rcMessage`）。注意 `rcMsg` 是**字典**（:154）不是函数，直接调用会编译不过 | `App/Core/StatusParser.swift:154 / :162 / :181` |
| 玻璃 | `axGlass(_:)` / `axGlassCircle()` / `axGlassCapsule()` | `App/Core/AccessibilityKit.swift:388 / 393 / 400` |
| 触觉 | `DS.Haptics.tick`（light）/ `DS.Haptics.trigger`（medium）/ 结果用 `UINotificationFeedbackGenerator` 的 success·warning·error。**`DS.Haptics` 标了 @MainActor**，只能从视图动作里调 | `App/Core/DesignSystem.swift:254-258` |
| ↳ 既有替代 | 仓内已有 `.sensoryFeedback` 用例（`LockKeeperApp.swift:1401`、`UnlockDial.swift:597/607`、`DeviceHomeView.swift:246/727`）—— 门面**优先沿用既有写法**，不要新造一套 | audit-B ❌5 |
| 降级判据 | ⚠️ `DS.Motion.tier` 是 **private**（`DesignSystem.swift:286`），**新文件读不到**。新动效令牌（`doorSwing`）**必须写在 `DesignSystem.swift` 内部**（六个成品令牌附近，约 `:342`），同文件内才可见 | audit-A/B ❌❌ |
| 锁体直径 | `DS.Metric.dial` —— `enum DS`(:106) 与 `enum Metric`(:152) 都是 **internal，新文件可直接读**，不必改 DesignSystem | audit-B ✅ |
| 门禁/深链 | `AppState.handleDeepLink` 起点在 `LockKeeperApp.swift:124`（不是 :133）；白名单 `Route.deepLinkHosts`（`Route.swift:73-77`）；`pendingRoute` :119、`pendingMac` :120 | audit-B ❌6 |
| 状态栏字色 | 按皮肤亮度切 `.dark`/`.light` content，跟随 `colorScheme` | 新写 |

**⛔ 唯一幻觉符号已删**：上一稿写「现有 `CoverRegistry` 管理 sheets」——全仓 grep **0 命中**（audit-B ❌4）。
真实情况：cover 直接挂在 `mainTabs`（`LockKeeperApp.swift:1246 / 1252`）与 `mainTabsChrome`（`:1270`）。

---

## 10. 验收（实施完必须逐条自证，截图存档）

1. **几何**：393×852 上量锁体直径 240±2pt、中心 Y = 46%±8pt。
2. **中缝厚度**：4 倍放大截图，左暗右亮不对称可见。
3. **开门角度与残留宽度（可算，不要凭感觉）**：
   每扇门在屏上的正交投影宽度 = `(屏宽 ÷ 2) × cos θ`。在截图基准 393pt 下：
   `60°→98pt · 75°→51pt · 80°→34pt · 85°→17pt · 88°→7pt · 90°→0pt · 106°→54pt（转过去了，背面）`。
   本设计的**淡出起点是 88°**（§11 坑 1），所以「淡出开始那一刻的残留宽度」≈ **7pt**（393pt 基准）。
   **判据**：量淡出开始那一帧，残留落在 **5–16pt** 通过；若 >24pt，说明角度不够、门还看得出是一块板；
   若为 0，说明淡出起得太晚（会看到一条硬边消失）。
   ⚠️ 上一稿写的「26–40pt」是**没有推导依据的估数**，已按本节更正。
4. **背 facing**：开门过程中**不得出现镜像背面**（见 §11 的 opacity 斜坡）。
5. **失败不动门**：注入开锁失败，逐帧对比截图，门板区域像素差为 0。
6. **中缝光时序**：帧级录屏，光出现在门转动**之前** ≥ 300ms。
7. **性能**：iPhone SE(3rd) 上开门全过程 ≥ 55fps，无掉帧卡顿；`Instruments` 里 `Canvas` 只光栅化一次。
8. **无障碍**：VoiceOver 打开，双击锁体能完成开锁；门开着时读不到门后内容。
9. **降级**：开启"降低动态效果"，门不转、直接交叉淡入；开启"降低透明度"，门面不透明。
10. **深色**：整套截图重拍一遍，**不许出现浅色灰直接搬进深色**。
11. **深链**：`kf://records?k=…` 冷启动直达记录详情页，**不出现门**。
12. **访客模式**：开访客通道，推门而入后进「凭证」仍要求口令。

---

## 11. 两个已知的坑（照此实现，别踩）

**坑 1 · 背 facing**：SwiftUI `rotation3DEffect` **不会**自动隐藏背面（CSS 的
`backface-visibility:hidden` 没有等价物）。106° 意味着最后 16° 会露出镜像的背面。
做法：对每扇门叠一个与角度联动的透明度斜坡——

```swift
// 88° 之前完全不透明；88°→106° 线性降到 0；反向关闭时自然恢复
let fade = 1 - min(max((angle - 88) / 18, 0), 1)
leaf.opacity(fade)
```
**必须用连续函数，不许 `angle > 90 ? 0 : 1`** —— 后者会在 90° 处闪一帧。

**坑 2 · 透视强度**：SwiftUI 的 `perspective:` 与 CSS `perspective:1200px` **不是同一个量纲，不要换算**。
而且**不要预设任何起始值** —— 上一稿写的 `perspective: 0.55` 是没有依据的估数，现已删除。
**用下面两条判据现场调**（都可测）：

| 判据 | 怎么量 | 通过标准 |
|---|---|---|
| **A · 残留宽度**（主判据） | 截图取「淡出开始那一帧」，量每扇门残留的竖条宽度 | 393pt 基准下 **5–16pt**（正交推导值 7pt，见 §10 第 3 条） |
| **B · 梯形畸变**（防过度透视） | 门转到 45° 时，量门扇**游离边**与**铰链边**的高度差 | 差 < 8% 门高（即看起来是"退开"，不是"被拉成梯形"） |

调法：先按 B 判据把 `perspective` 调到"退开感明显但不变形"，再用 A 判据复核残留宽度。
把最终值写进 `LockFaceStyle.swift` 并**注明是按这两条判据定的**（不是抄来的）。

> Android **不做门面**（D11），所以**没有**「Android 也要对齐同一视觉结果」这回事；
> `cameraDistance` 的换算知识留着备用即可，别为它写任何 Android 侧实现。

---

## 12. 文件清单（新增，写权限边界）

| 文件 | 内容 | 允许改动 |
|---|---|---|
| `App/UI/LockFace/LockFaceView.swift` | 容器、层级、相位编排 | 新增 |
| `App/UI/LockFace/LockLeaf.swift` | 单扇门（几何/旋转/背面斜坡） | 新增 |
| `App/UI/LockFace/DoorSurface.swift` | 门面材质（渐变+噪声+光位） | 新增 |
| `App/UI/LockFace/LockPlate.swift` | 锁体 5 层 + 字形双态 | 新增 |
| `App/UI/LockFace/SeamGap.swift` | 中缝 + 透光 | 新增 |
| `App/Core/LockFaceStyle.swift` | 装饰层色值/曲线/皮肤常量（**动效时长走 DesignSystem 的 `doorSwing`**，不在这里重复声明） | 新增 |
| `App/Core/LockFacePolicy.swift` | 展示策略（§7） | 新增 |
| `App/Core/DesignSystem.swift` | **只加不动**：新增令牌。⚠️ 本仓**没有** `tokens.json` 这个来源；「令牌单一来源」**指的就是本文件**（D9 已重写）。`doorSwing` 必须写在本文件内，因为 `tier` 是 private | 受限改 |
| `App/LockKeeperApp.swift` | 在 `rootGroup`（现有 `Group`，`:1312`）内接一层 **ZStack** 承载 LockFace | 受限改 |

**新增页面还要挂台账**：若门面设置页/App Index 成为「目的地」，必须进 `tools/destmap.js --emit` 生成的
`App/Core/Destination.swift`（**不许手改**），总数 76 → 78（见 PART7 §2.3）。

**禁止**：改 `Route.swift`、`Destination.swift`、`fixtures/`、`vendor/`、协议层任何文件。

> ⚠️ **也不许"补回" `AppLockView` / `DecoyView`** —— 这两层在 2026-10-17 已删除、当前无实体（见 §1）。
