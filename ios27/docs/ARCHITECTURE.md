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
├── Gates/                        24 道机器闸门
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
| 2 | `types` | 顶层类型重复声明 / Engine 引用不存在的类型 | SDK 类型走白名单（`Gates/sdk-types.txt`） |
| 3 | `swiftcheck` | 括号 / 字符串 / 块注释平衡；**`Tests/` 也在扫描范围** | 无（纯计数） |
| 4 | `tokens` | 硬编码颜色/间距/圆角/字号；**颜色/字号/动效令牌必须有消费点** | 只豁免 3 个文件（令牌层两个 + Dial 的 Canvas 几何），每条都写了理由 |
| 5 | `contrast` | 从 `Tokens.swift` / `V7Tokens.swift` 现场解析色值做 WCAG 断言（明暗各一套） | 无（纯计算）。**不钉死断言条数**（色板一变就过期） |
| 6 | `glass` | 内容层不许 `glassEffect`；同屏玻璃 ≤2；不许自铺半透明底 | — |
| 7 | `motion` | `.animation` 必带 `value:`；不许 `.linear`；不许裸时长；`repeatForever` 必独立视图 | — |
| 8 | `a11y` | 图标按钮必有 label；可点区 ≥44pt；**DesignLab 生成器不许产出无 alt 的 img** | 判据是"只有 Image 且无任何文字承载"，避免误报 |
| 9 | `dynamictype` | 字号必须走令牌（`V.F.*`），不许写死数值字号 | 令牌层豁免（那是字面量的家） |
| 10 | `reducedmotion` | 动效必须带减少动态守卫 | — |
| 11 | `crosprivate` | Screen + Parts 跨文件 private 可达性 | — |
| 12 | `callsig2` | 调用标签/参数个数/构造签名/@MainActor 隔离 | **只覆盖裸调用与构造器**：`类型.方法(...)` 因无类型推断被整段跳过（见文件头「已知盲区」） |
| 13 | `lineage` | 与上一版切割（18 个旧符号零残留） | 无 |
| 14 | `workflow` | GitHub Actions 结构；**文档声称的闸门数必须等于真实数量** | 无 |
| 15 | `destmap` | Dest 台账 ↔ View 实现一一对应 | 无 |
| 16 | `privacy` | 隐私/安全回归（判红，**21 条判据**） | 每条都写了「为什么这么判」 |
| 17 | `tests` | 测试目标 + 金标夹具接线 + 协议/安全/并发覆盖面的静态证明 | 它只证"接线对"，不等于"跑过了" |
| 18 | `feedback` | 用户动作里的 `try? await` 必须有错误通道（HIG feedback） | 排除 `Task.sleep` 与 `throws` 函数 |
| 19 | `modal` | 对话框不许直接抢 sheet（HIG sheets：一次只呈现一个模态） | 多入口只提示不判红 |
| 20 | `settings` | 给了开关就必须有效果（**warn-only**：只追一层直接消费） | 间接消费追不到，故只提示 |
| 21 | `reserved` | `RESERVED.md` 清单与源码 `【保留未接` 标记对账（两向） | 只查「登记了就必须有标记」，不判功能本身是否该保留 |
| 22 | `memberfill` | **带默认值的结构体字段**在「逐字段重建」处必须显式传（否则编译不报错但语义丢失） | 只覆盖 `WATCHED` 里登记的类型；新增带默认值字段要手动登记 |

**当前共 24 道**（这个数字由 `Gates/workflow.js` 对账，写错会本地判红）。

### 5.1 每道闸门的已知边界（**绿 ≠ 没问题**）

> 这张表是给"看到绿就放心"的人看的。每道闸门都只在一个很窄的形状上判红，
> 表里写的是**它管不到的事**。写不出来边界的闸门，不该出现在上面那张表里。

| 闸门 | 管不到什么 |
|---|---|
| `swiftparse` | tree-sitter 语法盲区（当前 14 处换源再解析）；语义/类型层面完全不看 |
| `types` | 只查顶层类型重名与 Engine 的未解析类型名；泛型约束、协议一致性、扩展成员冲突都不查 |
| `swiftcheck` | 只数字符平衡；`if` 少 `else`、`switch` 漏 `case` 这类结构问题看不见 |
| `tokens` | 只抓**字面量**；由变量拼出来的样式（`let h = 32; .frame(height: h)`）不查 |
| `contrast` | 只算令牌定义之间的对比度；真实渲染中叠了半透明层之后的实际对比度不算 |
| `glass` | 只数静态出现的玻璃调用；运行时组合出来的层数不算 |
| `motion` | 只查 `.animation` 是否带 `value:`、是否裸时长；曲线是否合适、时长是否跟手无法判 |
| `a11y` | 只查"纯图标按钮有 label"与"可点区 ≥44pt"；VoiceOver 顺序、rotor、朗读语义都不管 |
| `dynamictype` | 只查字号是否走令牌；极大字号下的截断/换行必须真机看 |
| `reducedmotion` | 只查动效处是否出现 reduceMotion 判断；判断得对不对不管 |
| `crosprivate` | 只查本仓已知的 6 组 `*Screen + *Parts` 配对；其它拆分方式不查 |
| `callsig2` | **所有 `类型.方法(...)` 调用被跳过**（无类型推断）；只覆盖裸调用与构造器 |
| `lineage` | 只认那 18 个旧符号名；换个名字的旧设计照样漏过 |
| `workflow` | 只查 YAML 结构与文档里的闸门数；工作流**逻辑**（步骤顺序、条件）不管 |
| `destmap` | 只证 `Dest` 有对应分支且 View 类型存在；跳过去之后对不对不管 |
| `privacy` | 第 13–21 条多为**同一文件内的形状检查**，不做跨文件数据流；动态键（`"kf_x_" + mac`）不识别 |
| `tests` | 只证测试目标/夹具/覆盖面静态接线正确；**它不运行测试**（真跑在 CI 的 golden job） |
| `feedback` | 只查用户动作函数里 `try? await` 有没有错误通道；其它吞错形式（空 `catch`）不查 |
| `modal` | 只查对话框按钮闭包里**直接**置 sheet 布尔；经中间函数间接置位不查 |
| `settings` | **warn-only**，只追一层直接消费；间接消费追不到，报的是「请人工确认」 |
| `memberfill` | 只查已登记类型（`KeyItem`）的已登记字段（`createdAt`）；其它类型/字段要手动加进 `WATCHED`。它只看「有没有写这个标签」，不检查值是否来自正确的源 |

合并成一句话：**这 24 道闸门保证的是"已知的坑没有重新挖开"，不是"没有坑"。**
真正的语义正确性仍由 CI 的编译 + 金标测试 +（缺失的）真机验证承担。

**核对 CI 时必须读四样，不能只看前两样**（2026-11-01 的教训）：

| `ci-log:meta.txt` 字段 | 说明 |
|---|---|
| `errors=` | 只说明"没有 error 行"，**不等于 job 绿** |
| `build_ok=` / `archive_ok=` | 真正的绿/红判据 |
| `warnings=` | **源码告警数**（`App/` 开头的告警行）。这一项此前不存在，于是 `build.log` 里的 6 条 warning 从来没人看 —— 而其中一条是真缺陷（`AppLock` 的 `return` 之后有死代码，刷脸成功永不清冷却） |

`warnings` 不是 0 就必须逐条看是什么：可能是类型标注缺失，也可能是不可达代码。

**正控 = 故意注入一个缺陷，确认它会红**（只测「能判红」不够，还要确认修好后会转绿）。

已做过正控：`swiftparse`（少一个右括号）· `tokens`（`.frame(height: 32)`；以及塞一个死令牌）·
`contrast`（单位小字 3.22:1）· `a11y`（图标按钮无 label；以及 `DesignLab` 的 `<img>` 去掉 alt）·
`motion`（把带 `value:` 的动画换成裸 `.animation(.easeInOut)`）·
`privacy`（备份校验和改成硬拒绝；`addCalendar` 改回同步）· `feedback`（去掉 `do/catch`）·
`modal`（对话框里直接置 sheet 布尔）· `settings`（塞一个没人读的开关）· `workflow`（把闸门数写错）。

注：`settings` 是 **warn-only**（只追一层直接消费，间接消费追不到），它报的是「请人工确认」，
不是「可证明已死」—— 宁可不判红，也不产生假红。

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
| 真机编译 | ✅ **CI 已通过** | 本机 Windows 无 Xcode；CI 用 `xcode-27` 镜像 BUILD/ARCHIVE SUCCEEDED。**不钉 run 号**（钉死会被后续提交甩开），查当前：`git show origin/ci-log:meta.txt` |
| 真机手感 | ❌ 未验 | 刻度盘按压、进度弧跟手度、触觉 |
| Engine 与页面的接线 | ✅ **主要链路已接** | 开锁/凭证/记录/配网/备份/校时/布防/网关/DFU 全走真协议；剩余零星 `TODO(engine)` 见 `COMPLETION.md` 的「未接项」表（次要字段，非主链路） |
| 动态字体极端值 | ⚠️ 未验 | 静态只保证字号走令牌；最大字号下的截断需真机 |
| 横屏 / iPad | ❌ 不支持 | 本仓锁竖屏（`UISupportedInterfaceOrientations` 只给 Portrait） |
