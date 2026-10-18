# PART 7 · 闸门矩阵 · 迁移顺序 · 风险 · DoD

> **这一份是实施的"安全带"。** 本仓的规矩是"改完即跑闸门，失败不扩散"。
> 下面每个数字都是 Lead 在 2026-10-18 实测的**基线**，不是估计。
> 基线红的项，动手前先知道它本来就红；基线绿的项，你把它弄红就是你的事。

---

## 0. 三条铁律（先记这个）

1. **闸门必须在 `ios-app/` 目录下跑**。从仓库根跑 `node tools/uicoverage.js` 会因为
   脚本内部用相对路径 spawn `tools/destmap.js` 而报"尺子坏了"（实测 exit=2）。
   正确姿势：`cd ios-app` 后 `node tools/<名称>.js`。
2. **UI 必须走 VK 语法层**（`App/Core/VariantGrammar.swift` 的 `struct VK`）：
   `VK().card { }` / `VK().sectionTitle(text:count:)` / `VK().statusPill(text:systemImage:tone:)` / `.vkFont(...)` / `VariantToggleStyle`。
   自绘容器有**预算**（`fixtures/uicoverage/budget.json` 当前 `selfDrawnContainers: 111`），
   **只许减不许增**：新增一处判失败。
   门面层确实必须自绘，**必须**逐处留痕 `// @layout-allow VK豁免 <类名>` 并说明理由
   （仓内已有先例：语义色填充 / 控件可识别性 / 面板实底 / 刻度点 / 触达托管Picker）。
3. **不许为了过闸门而改判据**。`fixtures/golden.json`、`vendor/app/**`、协议层、
   对比度断言表、`Destination.swift`（由 `tools/destmap.js --emit` 生成）都是**只读**。

---

## 1. 闸门矩阵（35 个脚本，按"判失败 / 顾问级"分）

### 1.1 判失败闸门（红了必须修）

| 脚本 | 检查什么 | 本设计会不会触发 | 触发时怎么办 |
|---|---|---|---|
| `swiftcheck.js` | Swift 括号/字符串平衡 | 会（新增 6-8 个文件） | 修到平衡；跑完必绿 |
| `swiftlint.js` | 结构性粗检：函数体首条语句并到 `func … {` 同行、截断方向、回收站天数口径、时间单位 | 会 | 按提示修，别绕过 |
| `swiftshape.js` | 视图形状机检 R1–R12：缺 `@ViewBuilder`、属性挂到值类型、调用点参数标签对不上、实参个数、重复 `@ViewBuilder`、`Section` 带 footer 写法、`frame` 次序、`as:` 缺 `.self`、View 扩展丢 `self` | **高危**：门面层参数多、修饰符长 | 每个子视图单独拆函数；`frame` 次序写在最后 |
| `swiftsyn.js` | 语法形状 S1–S4：for-in 头逗号、带标签尾随闭包后接非花括号、裸 `$`、参数名后属性缺冒号 | 会 | 按提示修 |
| `destmap.js` | **目的地台账 = 76**；枚举与台账逐条一致 | **会（+2 个新页面）** | 跑 `node tools/destmap.js --emit` 重新生成 `Destination.swift`，**不要手改**；总数变 78 要在本文件与本方案里同步改口径 |
| `uicoverage.js` | 八项检查：漂移 / 缝覆盖率 100% / 裸换页 / 自绘容器预算 / 裸 `Toggle` / 裸 `.font` | **会（这是本设计最可能撞红的一道）** | 见 §2 专章 |
| `sheetcover.js` | 被 sheet 盖住时切 Tab 必须同时 `dismiss()` | **会**（App Index 是 sheet，里面可能有跳转） | 跳转前先 `dismiss()`；照抄既有正确写法 |
| `contrast.js` | 397 条对比度断言（6 套主题 + AMOLED；正文 4.5:1 / 非文本 3:1 / 分隔线 1.2:1） | **会**（新材质上的文字） | 门面上的文字一律用 `Palette.text` / `.textSub`，不要自定义灰 |
| `copynum.js` | 用户可见文案里不许出现内部规格编号（`(N 说明)` 这类） | 会（新文案） | 注释里可以写编号，**界面上不行** |
| `dynamictype.js` | Dynamic Type / 触达尺寸 / 中文字重静态检查 | **会**（字号与触达） | 中文标题最高 semibold；触达 ≥44pt；文本下限 `.caption` |
| `golden.js` `--check` | 金标是否与 JS 核心一致 | 不会（不碰协议） | 不许改金标 |
| `cmdsshadow.js` / `parseshadow.js` / `zotpshadow.js` / `shadowdiff.js` / `logicparity.js` / `autoopenshadow.js` / `bundleshadow.js` | 跨语言字节面/逻辑面差分 | 不会 | 不碰协议层即安全 |
| `kotlinlocal.js` | 本地真编译 Kotlin 的**非 UI** 4 个文件 | Android 侧改造会 | 改 Kotlin 后必跑；**UI 层它不覆盖**（见 §5 风险 R8） |
| `kotlinshadow.js` | Android 侧帧字节面影子对拍（含 MainActivity 正则结构检查） | Android 侧会 | 改 MainActivity 结构后必跑 |
| `changelogcheck.js` | 43/44 更新说明的反吹牛（不许手写） | 会（若改版本号） | 更新说明从代码生成，不手写 |
| `citecheck.js` | 文档里的 `文件:行 + 摘录` 必须真实存在且指向同一处 | **会（本方案这批 md！）** | 新写的 md 若被纳入扫描，行号必须实测；引用别凭印象 |

### 1.2 顾问级（不判失败，但要人读一遍）

`apisweep.js`（框架不存在的 API 名）、`assetscheck.js`（219 资源纪律）、
`deadscan.js`（零引用声明）、`delsweep.js`、`docpointers.js`、`featuremap.js`（1050 项功能点台账）、
`iconmap.js`（210 图标一致性）、`keydead.js`（假开关 / 同一键两套默认值）、
`lockpair.js`、`macpin.js`（活读 mac 写库）、`typepred.js`（同一日志类型写两遍）、
`bigfiles.js`（大文件盘点）。

**与本次相关的高价值两条**：
- `apisweep.js`：门面层会用到大量 SwiftUI 修饰符，**写完跑一次**，
  它能抓到"SwiftUI 里根本没这个 API"（仓内真实踩过 `.listItemSpacing` 的坑）。
- `keydead.js`：新增的 `kf_start_at_door` / 皮肤键必须**有读点**，否则算假开关。

### 1.3 非 ios-app 的闸门

| 命令 | 位置 | 说明 |
|---|---|---|
| `node tests/run.js` | **`miniprogram-app/`** | 小程序侧 25 套协议测试。**注意：不在仓库根的 `tests/`**（根目录没有这个文件） |
| CI `.github/workflows/` | `ios-app/.github` | GitHub Actions：`stamp` → `build`(iOS) + `android`。**`stamp` 一红两端全 skip**（README 有专章） |

---

## 2. uicoverage 专章（本设计必撞的一道）

### 2.1 今天的真实状态（实测，不是"应该绿"）

`
目的地总数 = 76   台账 = 76   → 检查一 通过
检查二 缝覆盖率 = 75/76 (99%)   → **已有 1 条未挂缝: ShareToAndroidView**
检查四 绕过漏斗的裸写换页: 1 处  → **App/UI/RecordsTimeline.swift:450  app.pendingDiag = mac**
检查五 自绘容器预算: 111 = 基线（未新增）
结论: 判失败    ← 基线就是红的
`

**处置**：
- 这两条**不是本次改造引入的**，但会让"改完跑闸门"永远绿不了。
  建议**在 L0 之前先修掉**（各一行，低风险）：
  ① `RecordsTimeline.swift:450` 改用漏斗（`app.pendingDiag = mac; app.requestRoute(.settings)` 的合法形态，
     参照 `LockKeeperApp.swift:1197` 的既有正确写法）；
  ② `ShareToAndroidView` 挂一条呈现缝（它已在 `SettingsView.swift:126` 以 `.sheet` 呈现，
     多半是闸门没认出来 —— 查闸门的呈现通道识别规则，别改视图去迎合闸门）。
- **修完再动手做门面**，这样后面每一步的红都是你自己弄红的，归因清晰。

### 2.2 门面层怎么不被判"自绘容器超预算"

门面层（LockFace / LockLeaf / DoorSurface / LockPlate / SeamGap）**本质上是自绘的**，
完全走 VK 不现实。规则是：

1. **能走 VK 的一律走 VK**：门后 App 里的卡片、分组标题、状态胶囊、开关、文字，
   全部用 `VK().card { }` / `VK().sectionTitle(text:count:)` / `VK().statusPill(text:systemImage:tone:)` / `VariantToggleStyle` / `.vkFont(...)`。
   （这也是"门后是常规 iOS"的另一种意义。）
2. **必须自绘的逐处留痕**：每一处自绘容器紧邻上一行写
   `// @layout-allow VK豁免 <类名>: <为什么必须自绘>`。
   类名取自既有枚举：**语义色填充 / 控件可识别性 / 输入框底衬 / 进度条实底 / 面板实底 / 刻度点 / 触达托管**。
   门面层新增的合理理由（建议措辞）：
   - 锁体玻璃面 → `控件可识别性`（它本身就是被按压的控件本体）
   - 锁体充能环 → `刻度点` 或新增口径（环是刻度不是容器）
   - 门扇材质 → 建议走「装饰层」口径，若闸门无此项，**与闸门的作者口径对齐后再写**，
     不要自己发明豁免类名（闸门按类名白名单判定）。
3. **预算只许减**：本次新增的自绘容器若被闸门计入，需在 `fixtures/uicoverage/budget.json` 里
   **说明并上抬基线**——但这**违反"只能下调"的注释**，所以正确做法是**先问**：
   把新增处数与理由写进 PR 描述，由人拍板是否调整基线。
   ⚠️ **实施 AI 不许自行改 budget.json**。

### 2.3 新增页面必须进台账

门面层会带来 2 个新"目的地"级页面：
- `AppIndexView`（76 项目录，sheet 级）
- 可能还有 `LockFaceSettingsView`（皮肤 / 门面行为的设置页）

**两者都要出现在 `Destination.swift`**，做法是让 `tools/destmap.js --emit` 重新生成，
总数从 76 变 78。**同步要改的地方（sp-nav 已实测：`ios-app/tools/**` 与 `fixtures/**` 里 0 处硬编码 76）**：
① `Destination.swift:2` 的头注释（由 `destmap --emit` 自动改）；
② 本文件 §2.1；③ `MASTER-PLAN.md` 速查与裁决表；④ `PART5-DESTINATIONS.md` §0 与统计表；
⑤ `PART0-OVERVIEW.md`；⑥ `README.md`。
⇒ 只需改**人写的文档**（5 处）+ 1 处自动生成，闸门侧无需改（总数是算出来的）。

---

## 3. 迁移顺序（10 步，每步独立可合入、可回滚）

| 步 | 内容 | 前置 | 触碰文件 | 闸门 | 回滚 |
|---|---|---|---|---|---|
| **S0** | 修基线红：RecordsTimeline 漏斗 + ShareToAndroidView 缝 | 无 | 2 个文件各 1 行 | `node tools/uicoverage.js`（应变绿） | 单行 revert |
| **S1** | **不新建来源**：在 `DesignSystem.swift` 内加 `doorSwing` 等令牌，并用现有 `tools/layout-replica/` 导出对照表（D9） | S0 | DesignSystem.swift（受限改）+ 生成的 Tokens.kt | `contrast.js` `swiftcheck.js` | 单处 revert |
| **S2** | 新增 `LockFaceStyle.swift` / `LockFacePolicy.swift`（**纯常量与纯函数，零视图**） | S1 | 新增 2 | `swiftlint.js` `swiftshape.js` | 删文件 |
| **S3** | 门面视图：`DoorSurface` → `SeamGap` → `LockPlate` → `LockLeaf` → `LockFaceView`（**先静态，不接状态机**） | S2 | 新增 5 | `swiftcheck` `swiftshape` `swiftsyn` `uicoverage` | 删目录 |
| **S4** | 接状态机（`LockFacePhase`）+ 手势 + 触觉 + `LockService` 接线 | S3 | LockFace 目录 | 上面 4 条 + 手工回归开锁 | 回退接线那一处 |
| **S5** | 根容器接线（`LockKeeperApp.swift` 加一层 ZStack）+ `LockFacePolicy` 生效 | S4 | `LockKeeperApp.swift`（受限改） | 全部判失败闸门 + `sheetcover` | 单处 revert |
| **S6** | App Index（76 项目录，由 destmap 生成数据）+ 三处触达 | S5 | 新增 2 + `Destination.swift`(生成) | `destmap` `uicoverage` `sheetcover` | 删文件 |
| **S7** | Tab 根屏改"前门页"（4 个 Tab 根） | S6 | `DeviceHomeView` 等 4 个 | `uicoverage` `dynamictype` `contrast` | 逐步 revert |
| **S8** | 组件层清理：圆盘装饰层删并、表面预算、胶囊种类收敛 | S7 | `UnlockDial.swift` 等 | `uicoverage`（预算应**下降**，下调 budget.json） | 分文件 revert |
| **S9** | 76 目的地逐条改造（按 PART5 表，每批 8-10 个） | S8 | 各 UI 文件 | 全量判失败闸门 | 按批 revert |
| **S10** | Android 侧（D11 范围：**无门面**）+ 由导出产物生成 `Tokens.kt` | S1 | `android-app/**` | `kotlinlocal` `kotlinshadow` + CI android job | 分支回滚 |

**为什么 S1/S2 必须先做**：本仓踩过"页面各自写死颜色/尺寸"的坑（DESIGN-SPEC 明令页面不许写死）。
先有令牌再有视图，是唯一能避免这次重演的顺序。

---

## 4. 风险登记册

| # | 风险 | 可能性 | 影响 | 早期信号 | 缓解 |
|---|---|---|---|---|---|
| **R1** | **type-check 超时**：门面层参数多、修饰符长，撞上"该表达式报 type-check 超时" | **高** | 编译不过，全盘停 | 编译时间变长、Xcode 报 `unable to type-check in reasonable time` | 本仓已有 3 处先例（`LockKeeperApp.swift:1056/1126/1155` 都是被逼抽函数）。**每个视图 body ≤ 30 行**，拆子视图；长表达式显式标注类型 |
| **R2** | `@State` 被重建：用 `if` 切换门/App 导致 Tab 内容重建 | 中 | 凭证页状态丢失（用户看得见） | 切换回来时页面回到初始态 | 用 `opacity`/`scale` 显隐，**不用条件插入**；本仓 `LockKeeperApp.swift:1065` 有专门注释 |
| **R3** | 关门手势与 `NavigationStack` 交互式返回抢手势 | **高** | 用户想返回却关了整个 App，或反之 | 真机上边缘滑动行为不一致 | 按 D8：**只保留导航栏「关门」按钮 + 左缘 24pt 带内拖**（推荐），别做全屏右滑 |
| **R4** | `reduceMotion` 漏接：门转动画没走 `DS.Motion.tier` | 中 | 无障碍不合格 | 开"降低动态效果"后门照样转 | 所有动画只读 `DS.Motion`，禁止散写 `withAnimation(duration:)` |
| **R5** | 深色模式漏测：浅色上好看，深色下门面发灰/文字不可读 | **高** | 一半用户看到半成品 | 深色下截图对比度视觉塌陷 | `contrast.js` 只覆盖语义色，**装饰层要人工过一遍**；PART1 §13 验收第 10 条 |
| **R6** | iPad / 分屏布局崩：用了整屏硬值 | 中 | 平板上不可用 | 分屏后锁体跑位 | `GeometryReader` + 相对定位；锁体直径 `min(240, w*0.61)` |
| **R7** | BLE 失败态与门动画耦合：失败时门动了 | 中 | **安全语义崩塌**（用户以为开了锁） | 断网/关蓝牙测试时门有位移 | PART1 §10 验收第 5 条：逐帧像素差必须为 0 |
| **R8** | **Android UI 层没有本地编译闸门**：`kotlinlocal.js` 只编 4 个非 UI 文件 | **确定** | 写完编译不过，只能等 CI（5 分钟一轮） | CI android job 红 | 小步提交；本地能编就编；**别攒大改** |
| **R9** | 两端数值漂移：iOS 改了时长/色值没同步 Android | 中 | 观感不一致 | 两端同界面截图对比不一致 | 令牌来源是 `DesignSystem.swift`（D9 已重写）。**注意**：Android 无门面，两端只对齐**组件级**数值（间距/圆角/字号/色值/开关与列表的动效），不追求门面动画一致 |
| **R10** | 自绘容器预算超限（§2.2） | **高** | `uicoverage` 红，挡住全部提交 | 跑闸门即知 | 能走 VK 就走 VK；必须自绘的留痕；**不许自行改 budget.json** |
| **R11** | 门面「演示感」过强：每次开锁都要看 1.5 秒动画 | 中 | 老用户烦，最终关掉 | 用户反馈"太慢" | `LockFacePolicy` 的 300s 阈值 + 设置里「开锁后直接进主页」开关（S6/L5） |
| **R12** | 新增 `kf_*` 键无读点 → `keydead` 假开关 | 中 | 顾问级告警，长期腐化 | `keydead.js` 列出 | 新增键必须同批接上读点 |

---

## 5. DoD（完成定义，逐条可判定）

### 5.1 闸门（必须在 `ios-app/` 下跑，全绿）

`
node tools/swiftcheck.js && node tools/swiftlint.js && node tools/swiftshape.js && node tools/swiftsyn.js
node tools/destmap.js && node tools/uicoverage.js && node tools/sheetcover.js
node tools/contrast.js && node tools/copynum.js && node tools/dynamictype.js
node tools/golden.js --check
`
**另**：`cd miniprogram-app && node tests/run.js` 全绿（证明没碰协议）。

### 5.2 视觉（截图存档，量出来落区间）

1. 393×852：锁体直径 240±2pt，中心 Y = 屏高 46%±8pt。
2. 4 倍放大中缝：左暗右亮不对称可见。
3. **淡出开始那一帧**每扇门残留宽度 5–16pt（正交推导 `(屏宽÷2)×cos 88°`；393pt 基准约 7pt）。
4. 开门全过程**无镜像背面**闪现。
5. 注入开锁失败：门板区域逐帧像素差 = 0。
6. 中缝光出现在门转动**之前** ≥300ms（录屏帧级）。
7. iPhone SE(3rd) 开门 ≥55fps。

### 5.3 行为（手工回归，逐条录像或截屏）

8. VoiceOver：双击锁体能完成开锁；门开着时读不到门后内容。
9. 降低动态效果：门不转，200ms 交叉淡入。
10. 降低透明度：门面不透明。
11. 深色模式：整套截图重拍，无"浅色灰搬进深色"。
12. `kf://records?k=…` 冷启动直达详情，**不出现门**。
13. 访客模式：推门而入后进「凭证」仍要求口令。
14. 后台 5 分钟回来会重现门；<5 分钟不重现；深链永不重现。
15. 开锁途中切后台再回来：回到 `.locked`，不停在半开。

### 5.4 结构

16. `Destination` 台账 = 实际页面数（含新增的 AppIndex 等），由 destmap 生成，无手改。
17. 新增自绘容器**逐处**带 `@layout-allow` 留痕；`uicoverage` 检查五不因本次新增而涨。
18. 新 `kf_*` 键都有读点（`keydead.js` 无新增"假开关"）。
19. 两端数值同源：来源是 `App/Core/DesignSystem.swift`；两端同名令牌值逐字相同（色板按 D14 各留）。

---

## 6. 给实施 AI 的工作纪律（照做，别自创流程）

1. **动手前**：读 `DECISIONS.md` 全文（D1–D11）→ `PART0-OVERVIEW.md` → 本文件 §0–§3。
2. **每步之前**：确认这一步"触碰文件"清单与别人不重叠（多 AI 并行时尤其）。
   `LockKeeperApp.swift` 与 `DesignSystem.swift` 是受限改文件，**建议串行**。
3. **每步之后**：跑 §5.1 的闸门命令，把输出尾部 3 行贴进提交信息。
4. **不许**：改 `fixtures/**`、`vendor/**`、协议层、对比度断言表、`budget.json`、
   手改 `Destination.swift`、为了过闸门放宽判据、把 `if` 用在根容器上。
5. **不确定就问**：本方案没写到的，先查 §0 铁律与 `DECISIONS.md` §6 裁决表；
   还与方案冲突，就**停在原地**并把冲突写清楚，别自由发挥（自由发挥 = 返工）。
6. **文案**：所有用户可见中文遵守 `DESIGN-SPEC.md` §4（中文标题最高 semibold；
   数字 `.monospacedDigit()`；正文下限 `.caption`；中文不加 tracking）。

---

## 7. 本方案自身的不确定项（实施时必须在真机复核）

| # | 不确定 | 怎么定 |
|---|---|---|
| U1 | **「透视强度」的最终值**：SwiftUI 的 `perspective:` 与 CSS `perspective:1200px` 不同量纲 | 不要换算、**不要预设起始值**。按两条判据现场调：A 残留宽度 5–16pt（主）+ B 45° 时游离边与铰链边高度差 <8% 门高（防过度透视）。见 PART1 §11 坑 2 |
| U2 | **性能**：噪声 `Canvas` + 多层渐变 + 3D 旋转在 iPhone SE 上的实测帧率 | 真机 Instruments 测；不达标就把噪声改为静态光栅图（仍是程序化生成一次） |
| U3 | ~~Android 侧 `cameraDistance` 的对应值~~ | **已作废**：Android 不做门面（D11），无对应物 |
| U4 | **`uicoverage` 检查五对门面层的具体判定** | 先写一个最小门面原型跑一次闸门，**拿到真实判定再决定留痕策略**（别猜） |
| U5 | **两台设备同屏的形态** | 本方案只保证"切换当前锁"的形态；多锁并排是 v11 的事 |
| U6 | **门面语言的本地化** | 本轮只做中文；文案集中在 `LockFaceStyle` 或既有文案表，为将来留位 |
