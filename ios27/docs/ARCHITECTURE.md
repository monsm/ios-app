# ios27 · 架构

> 与上一版的关系：**协议层照搬，界面层全推倒**。判据见 `docs/DESIGN-CONTRACT.md §12`，
> 由 `Gates/lineage.js` 机器把关（新 App 里出现任何上一版设计系统符号即失败）。

---

## 目录

```
ios27/
├── App/
│   ├── LockKeeperApp.swift       入口：装配环境 / 本机密码闸 / 只读试验模式条
│   ├── Design/
│   │   ├── Tokens.swift          设计令牌唯一来源（颜色/间距/圆角/字号/动效/高度）
│   │   └── Components/           组件库（Panel / Reading / Dial / Ledger / Primitives）
│   ├── Shell/
│   │   ├── Shell.swift           5 Tab + 系统搜索 Tab
│   │   ├── Router.swift          导航唯一漏斗（Dest / TabSlot / RouteContext）
│   │   ├── Destinations.swift    Dest → View 唯一映射
│   │   └── AppModel.swift        应用级状态（@Observable）
│   ├── Features/
│   │   ├── Door/                 门（刻度盘）+ 5 子页
│   │   ├── Keys/                 钥匙（凭证台账）+ 5 子页
│   │   ├── Records/              台账（时间轴）+ 2 子页
│   │   ├── Household/            家（成员）+ 3 子页
│   │   └── Settings/             设置 + 6 子页
│   └── Engine/                   57 个纯逻辑文件（协议/密码学/存储/BLE，照搬已验证实现）
├── Gates/                        9 道机器闸门
├── DesignLab/                    视觉验收台（令牌 → CSS → Edge 截图）
├── docs/                         设计契约 / 架构 / 闸门说明 / 进度
├── project.yml                   XcodeGen 工程描述（iOS 27.0 起）
└── .github/workflows/ios27.yml   闸门 → 云端编译
```

---

## 1. 为什么 Engine 是照搬的，界面是重写的

| 层 | 状态 | 理由 |
|---|---|---|
| 协议 / 密码学 / 解析 / 存储 / BLE | **照搬** | 有字节级差分金标（40 条命令帧、NIST AES 向量、状态/日志解析）。重写等于把"不要 BUG"的保证丢掉 |
| 设计令牌 / 组件 / 页面 / 导航 / 动效 | **全部重写** | 上一版的病在界面层：暖金 + 门的隐喻 + 缝补痕迹。协议层没问题 |

**切割是机器验证的，不是口头承诺**：`Gates/lineage.js` 扫全仓，
出现 `VKTypography` / `DS.Space` / `heroFg` / `LockFace` 等 18 个旧符号即失败。

---

## 2. 数据流

```
BLE 帧  ←→  Engine/BLEService (CoreBluetooth)
             ↓
        Engine/LockService (会话令牌 / 命令串行 / rc 自愈)
             ↓
        Engine/Store (kf_* 键，与小程序互通)  ←→  Engine/StoreModels (Codable 容错)
             ↓
        AppModel (@Observable，唯一跨页状态)
             ↓
        各 Feature 页面（只读 AppModel，写走 Router / 各自的 @State）
```

**纪律**：
- 页面**不直接**碰 Engine 的 BLE/LockService（除了明确标 `TODO(engine)` 的接线点）。
- 跨页状态只放 `AppModel`；页面临时态留在页面自己的 `@State`。
- 页面之间**不互相引用**；跳转一律走 `Router.request(_:)`。

---

## 3. 导航

```
RootView
 ├─ LockGateScreen      本机密码闸（冷启动才要求）
 └─ Shell
     ├─ Tab「门」    DoorScreen      → NavigationStack(path: doorPath)
     ├─ Tab「钥匙」  KeysScreen      → NavigationStack(path: keysPath)
     ├─ Tab「台账」  RecordsScreen   → NavigationStack(path: recordsPath)
     ├─ Tab「家」    HouseholdScreen → NavigationStack(path: householdPath)
     ├─ Tab「设置」  SettingsScreen  → NavigationStack(path: settingsPath)
     └─ Tab(role: .search)  SearchScreen（系统搜索 Tab，morph 成搜索框）
```

**唯一漏斗**：`Router.request(.dest(.keyCreate))` 会自动切到 `Dest.tab` 对应的 Tab 再 push。
裸切 Tab 在这个 App 里做不到 —— `Router.select` 只被 Tab 点击本身调用。

**为什么每条 Tab 一条独立 path**：上一版的真实事故是
"sheet 里 requestTab 切了一个不存在的 Tab，而 sheet 还盖在上面"。
独立 path + 上下文枚举从结构上消灭这类问题。

---

## 4. 组件库（`App/Design/Components/`）

| 文件 | 内容 |
|---|---|
| `Panel.swift` | `Panel`（内容面板，唯一容器）/ `Inset`（凹槽块）/ `SectionLabel` / `CanvasBackground` |
| `Reading.swift` | `Reading`（定宽读数）/ `FieldRow`（左标签右读数）/ `ReadingGrid`（读数网格） |
| `Dial.swift` | `DialPhase`（真实开锁链相位）/ `Dial`（蚀刻刻度盘 + 真进度弧 + 轨道）/ `DialPressStyle` |
| `Ledger.swift` | `LedgerEntry` / `LedgerRow` / `LedgerDayHeader` / `LedgerGrouping`（纯逻辑，可测） |
| `Primitives.swift` | `Tone` / `StateDot`（形状+色+词三通道）/ `StatusLine` / `ChipRow` / `PrimaryAction` / `SecondaryAction` / `PressStyle` / `EmptyPanel` / `BusyRow` |

**没有的东西**（故意的）：没有 `Card`（用 Panel）、没有 `HeroCard`、没有渐变纹理、
没有"三个图标卡片并排"的网格组件 —— 那些是上一版的模板脸来源。

---

## 5. 闸门（`Gates/`，本地与 CI 同款）

| # | 闸门 | 判什么 | 会不会误报 |
|---|---|---|---|
| 1 | `swiftparse` | **真语法树**（tree-sitter-swift）的 ERROR/MISSING 节点 | 3 个已知语法盲区做了**换源再解析**（不是按行豁免），其余逐字受检 |
| 2 | `swiftcheck` | 括号 / 字符串 / 块注释平衡 | 无（纯计数） |
| 3 | `tokens` | 硬编码颜色/间距/圆角/字号 | 白名单只有 2 条，都写了理由 |
| 4 | `contrast` | 从 Tokens.swift 解析色值，48 条 WCAG 断言（明暗各一套） | 无（纯计算） |
| 5 | `glass` | 内容层不许 `glassEffect`；同屏玻璃 ≤2；不许自铺半透明底 | — |
| 6 | `motion` | `.animation` 必带 `value:`；不许 `.linear`；不许裸时长；`repeatForever` 必独立视图 | — |
| 7 | `a11y` | 图标按钮必有 label；可点区 ≥44pt | 判据是"只有 Image 且无任何文字承载"，避免误报 |
| 8 | `lineage` | 与上一版切割（18 个旧符号零残留） | 无 |
| 9 | `destmap` | Dest 台账 ↔ View 实现一一对应 | 无 |

**每道闸门都有正控**（故意注入一个缺陷，确认它会红）。做过正控的：
`swiftparse`（少一个右括号）、`tokens`（`.frame(height: 32)`）、`contrast`（单位小字 3.22:1）、`a11y`（图标按钮无 label）。

---

## 6. 视觉验收台（`DesignLab/`）

本机没有 Mac / 没有 iOS 模拟器 ⇒ SwiftUI 渲染不了。但"观感"必须被看见。

```
App/Design/Tokens.swift  ──解析──▶  DesignLab/lab.js（令牌 → CSS 变量）
                                        ↓
                              DesignLab/primitives.js（每个函数镜像一个 Swift 组件）
                                        ↓
                              DesignLab/screens.js（每屏 1:1 镜像）
                                        ↓
                              DesignLab/run.js ──Edge headless──▶ shots/*.png
```

**能验**：版式 / 层级 / 间距 / 色彩 / 信息密度 / 空态 / 加载态 / 失败态 / 明暗双模。
**不能验**（诚实边界）：手势手感、真实液态玻璃折射、PingFang 中文度量（Windows 用雅黑近似）。

---

## 7. 已知未闭环

| 项 | 状态 | 说明 |
|---|---|---|
| 真机编译 | ❌ 未验 | 本机无 Xcode；CI 用 `macos-26` + 最新 Xcode。**必须等 CI 绿才算过编译** |
| 真机手感 | ❌ 未验 | 刻度盘按压、进度弧跟手度、触觉 |
| Engine 与页面的接线 | ⚠️ 部分 | 页面里 `TODO(engine)` 标注的字段目前是 AppModel 种子数据 |
| 动态字体极端值 | ⚠️ 未验 | 静态只保证字号走令牌；最大字号下的截断需真机 |
| 横屏 / iPad | ❌ 不支持 | 本仓锁竖屏（`UISupportedInterfaceOrientations` 只给 Portrait） |
