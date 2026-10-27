# PART 6 · Android 端改造方案（Compose）


> ⚠ **本档是历史台账，不是当前代码的说明书。**
> 里面的 `文件:行号` 指针记录的是**写档当时**的位置；后续精简/重构后部分文件已删或行号已移，
> 那些失效指针是台账的**正常内容**（它记的就是"某批删了什么"），不是错误。
> 想知道某个功能现在还在不在，请看 `docs/feature-web/features.json`（那份由工具从 inventory 重算）。

> **两条最硬的约束先看**：**D11**（Android **不做门面**）与 **D14**（Android **保留暗色 + 暖金**，不改成 iOS 的暖白）。
> 违反这两条中任何一条，本文件其余内容作废。

前置：`DECISIONS.md`（D9 / D11 / D14）、`PART0-OVERVIEW.md` §6（令牌真实值）、`EVIDENCE-ANDROID.md`（现状证据）、`PART4-MOTION.md`（B 段共用动效）。

---

## 0. 范围：三件事 + 一份路线图

| # | 做 | 不做 |
|---|---|---|
| 1 | **共享视觉语言**：几何/间距/圆角/字号/时长/曲线 与 iOS 逐字同源 | 不共享色板（D14） |
| 2 | **现有功能 UI 重做**：2 屏 + 3 覆盖层，行为逐字不变 | 不新增功能、不改协议 |
| 3 | **工程底座**：触觉封装、深浅双模、令牌单一来源 | 不为 edge-to-edge 升 SDK |
| 4 | **功能对齐路线图**（§7）：只写不做 | 不移植 iOS 的 76 个功能页 |
| — | — | **不做门面**（没有两扇门/中缝/锁体/透光/推门而入） |

---

## 1. 现状差异表

| 维度 | Android 现状 | iOS 现状 | 本轮处置 |
|---|---|---|---|
| 屏幕 | 1 个 Activity、1 个 Composable 根、**无 NavHost**（`MainActivity.kt:383-424`，靠 `showSettings` 布尔 + `AnimatedVisibility`） | 4 Tab + 76 个目的地 + NavigationStack | Android **不追平**；只把现有 2 屏 + 3 覆盖层的视觉重做 |
| 功能覆盖 | 协议只覆盖 cmd **01/03/04**（`KfProtocol.kt:180-192`） | `ZKCmdBuilder` 31 个构造器 | 不移植；写进路线图（§7） |
| 依赖 | 9 条，**无 Navigation / DataStore / Room / WorkManager** | — | 本轮**不加依赖** |
| SDK | compileSdk 35 / minSdk 33 / **targetSdk 34**（刻意停 34 避开 edge-to-edge） | iOS 26.5 | **不升 targetSdk** |
| 配色 | 暗色 + 暖金（`Theme.kt:10-17`） | 浅色暖白 + 蓝 | **各自保留**（D14） |
| 持久化 | SharedPreferences `kf_key_v1`（2 个键） | 336 个 `kf_*` 键 | 不假装互认（D11） |
| 备份 | 无 | 信封 + WebDAV | 路线图 |
| 后台 | 无 `POST_NOTIFICATIONS`、无前台服务 | 有后台/通知体系 | 路线图 |
| 本地编译闸门 | **UI 层没有**（`kotlinlocal.js` 只编 4 个非 UI 文件） | 35 个闸门 | **风险 R8**：小步改，别攒大改 |

---

## 2. 令牌映射（数值必须与 iOS 逐字相同）

来源：**`App/Core/DesignSystem.swift`**（D9 已重写；本仓**没有** `tokens.json` 这个来源）。Android 侧 `Tokens.kt` 由现有导出管线 `ios-app/tools/layout-replica/` 的产物转出。iOS 侧真实值见 `PART0-OVERVIEW.md` §6。

| 令牌 | iOS | Android（Compose） |
|---|---|---|
| 间距 xxs/xs/s/m/l/xl/xxl/gutter | 2/4/8/12/16/24/32/16 pt | 同数 dp |
| 密度缩放 | `kf_density` 0.85/1.0/1.18 | 同键同名（各端本地） |
| 圆角 card/control/tile | 22/16/18 pt | 22/16/18 dp |
| 触达 | 44 pt | **48 dp**（Android 平台最小值，不混用） |
| 图标 | 13/16/20/26/44 | 同数值 dp |
| 动效 quick | spring(response .22, damping .9) | `spring(dampingRatio = 0.9f)` 或退化为 150ms tween |
| 动效 soft | easeInOut .25 | `tween(250, easing = CubicBezierEasing(0.42f,0f,0.58f,1f))` |
| 动效 exit | easeOut .15 | `tween(150, easing = CubicBezierEasing(0f,0f,0.58f,1f))` |
| 门转（iOS 专属） | 820ms `(0.22,0.76,0.03,1)` | **不适用（D11）** |
| 触觉 tick | light | `HapticFeedbackConstants.CLOCK_TICK` |
| 触觉 trigger | medium | `HapticFeedbackConstants.CONFIRM` |
| 结果触觉 | success/warning/error | `CONFIRM` / `REJECT` |

**验收**：两端同名令牌数值逐字相同（用 `layout-replica` 的导出产物做对照表逐项 diff）。**色板除外**（D14）。

---

## 3. 开锁台重做规格（Android 的第一屏 = 它就够了）

Android 现有首页就是开锁台（`MainActivity.kt` 单 Composable 根），**这比 iOS 更直接**：
iOS 需要门是因为要做走进一个房间的仪式，Android 不需要。

沿用 v10 的**材质语言**（不是门的形态）：

| 分区 | 内容 | 材质做法 |
|---|---|---|
| ① 顶部 | 锁名 + 状态行（**只写真事实**，见 D13：已连接/未连接 + 电量 + 上次开锁） | 纯文字，`Ink` / `InkSub` |
| ② 中部 | 开锁台（圆形：金属环 + 深色玻璃面 + 字形） | **倒角** `Brush.sweepGradient`（对应 AngularGradient）；**玻璃面** 深色 radial；**投影** 多层柔和阴影 + 底光；直径沿用现有设置 |
| ③ 主操作 | 开锁按钮（保留现有冷却逻辑） | 既有 `Accent` #E8B45C 填充；保留按压反馈 |
| ④ 最近记录 | 最近 3 条 | 列表行，`Surface` + 分隔线 |
| ⑤ 设置入口 | 右上角 | 保留 `showSettings` 布尔（本轮**不引入 Navigation 库**） |

**必须保留的 Android 既有行为**（不许因重做 UI 而改动）：
1. 开锁指令帧与冷却时长（与 iOS 是否同值**未核实** —— 见 `EVIDENCE-ANDROID.md` 未证实项，实施前先核）。
2. `KFA1` 二维码解析（`LockStore.kt:62-87`，字段 v/n/m/p/e）。
3. `kf_key_v1` 里 `lock` / `proximity` 两键的语义与默认值。
4. 权限申请流程（SCAN + CONNECT + CAMERA）。
5. 竖屏锁定（`AndroidManifest.xml` 的 `screenOrientation`）。

---

## 4. 材质与动效的 Compose 实现

| v10 语言 | iOS | Compose |
|---|---|---|
| 金属倒角（conic） | `AngularGradient` | `Brush.sweepGradient(colors)` |
| 斜向主光 | `LinearGradient` | `Brush.linearGradient(...)` |
| 玻璃面 | `RadialGradient` + inset 阴影 | `Brush.radialGradient(...)` + 第二层 `drawBehind` 做内阴影 |
| 噪声纹理 | `Canvas` + 固定种子 LCG，`.drawingGroup()` | `Modifier.drawWithCache` 里画点（**缓存一次**），同一 LCG |
| 投影 | `.shadow` / 多层 | `Modifier.shadow(elevation, shape, ambientColor, spotColor)` |
| 玻璃 | `axGlass`（`glassEffect`） | **无原生 backdrop-filter**：半透明底 + `Modifier.blur` 背景层；**不追平 iOS 的液态玻璃** |
| 按压反馈 | `PressableButtonStyle`（scale .97） | `Modifier.scale` + `animateFloatAsState` |

**动效**：只做 `PART4-MOTION.md` 的 **B 段**（共用组件动效）；A 段（门面）**整段不适用**。
降级：读系统动画缩放（`Settings.Global.ANIMATOR_DURATION_SCALE == 0` 则全部瞬时）。

---

## 5. 触觉 / 深浅双模 / 工程底座

### 5.1 触觉
封装一个 `KfHaptics`（`tick` / `trigger` / `ok` / `fail` 四个入口），内部映射到 `HapticFeedbackConstants`
或 `VibratorManager`（API 33+，与本工程 minSdk 33 相符）。**禁止**在 UI 里散写 `performHapticFeedback`。

### 5.2 深浅双模
现状只有暗色一套（`Theme.kt`）。本轮：
- 暗色 = **保留现有值**（D14，它就是这套语言的暗色档）。
- 浅色 = **新做一套**，规则照 iOS 的做法反推：底 `#F5F3EF`、面 `#FFFFFF`、主文本 `#17140F`、
  次文本 `rgba(60,50,40,.62)`、**强调仍是暖金**但取深色版本 `#B8862F`（保证在浅底上 ≥4.5:1）。
- 跟随系统 `isSystemInDarkTheme()`；加一个三档开关（跟随系统 / 亮 / 暗）。
**验收**：两套各截一遍图；浅色下暖金文字的对比度用工具算一遍（≥4.5:1）。

### 5.3 不做的事
- **不升 targetSdk**（保留 34，避开 edge-to-edge 适配）。
- **不引入 Navigation / DataStore / Room**（后续真要扩功能时在路线图里再议）。
- **不做门面**（D11）。

---

## 6. BLE 与协议边界

| 项 | Android | iOS | 处置 |
|---|---|---|---|
| NUS 服务/特征 UUID | 一致 | 一致 | 已同源，不动 |
| KLV / 令牌 KLV#0xEE / 广播厂商段 0x98ED / rc 表 | 一致 | 一致 | 已同源，不动 |
| 命令构造器 | 3 条（01/03/04） | 31 条 | 路线图 |
| 配对 | `KFA1` 解析 | `KFA1` 生成 | 唯一稳定契约，**改动必须两端同步** |
| 帧字节面对拍 | `tools/kotlinshadow.js`（判失败） | `tools/cmdsshadow.js` | 改协议必须两端都过 |

**对账方法**：任何新增命令，先在 iOS 侧生成金标（`fixtures/golden.json`），
再让 Android 侧对同一组输入产出帧，用 `kotlinshadow.js` 对拍 —— **先测后编**（`AGENTS.md` 既有纪律）。

---

## 7. 功能对齐路线图（只写不做）

| 期 | 能力 | 依赖 | 粗估 | 本轮做? |
|---|---|---|---|---|
| P0 | **协议层对齐**：补 01/03/04 之外的命令 + Android 侧 golden 差分 | `kotlinshadow.js` 扩展 | 大 | ❌ |
| P0 | 后台能力：`POST_NOTIFICATIONS` + 前台服务 | Manifest + 权限流程 | 中 | ❌ |
| P1 | 记录读取（cmd 16 翻页） | P0 | 中 | ❌ |
| P1 | 凭证管理（密码/指纹增删） | P0 | 大 | ❌ |
| P2 | 备份/恢复（信封格式与 iOS 一致） | P0 + 格式冻结 | 大 | ❌ |
| P2 | 固件升级（DFU） | P0 | 大 | ❌ |
| P3 | 网关 / 校时 / 成员 / 审计 | P0-P2 | 很大 | ❌ |

**排期原则**：没有 P0 的协议层对齐与差分闸门，后面每个功能页都是在沙上盖楼。

---

## 8. 验收（Android 侧自证）

1. 现有 5 个界面（2 屏 + 3 覆盖层）外观重做后，**行为逐字不变**：开锁、冷却、扫码配对、设置项读写全部回归一遍。
2. 令牌数值与 `DesignSystem.swift` 一致（几何/间距/圆角/时长/曲线）；**色板按 D14 各留**。
3. 触觉四个入口在真机上都能触发；系统关闭触感时无异常。
4. 深浅两套截图各一遍；浅色下暖金文字对比度 ≥4.5:1。
5. 系统动画缩放关掉后，组件动效全部瞬时（不卡在半途）。
6. `node tools/kotlinlocal.js` 与 `node tools/kotlinshadow.js` 在 `ios-app/` 下均 exit 0。
7. CI `android` job 绿（gradle assembleDebug + 编译期戳核对）。
8. **没有**出现两扇门 / 中缝 / 锁体 / 推门而入中的任何一个（D11）。

---

## 9. 两端一致性判据（只覆盖组件级）

因为门面只有 iOS 有，两端的一致性只在这些维度验收：
间距、圆角、字号档、行高、按钮最小触达、开关动效、列表行按压、状态色语义、空态结构。
**不验收**：门的动画、锁体形态、配色基调（D14）。
方法：两端各截同一屏（设置列表 / 记录列表），叠图比对间距与圆角；误差 ≤1dp。