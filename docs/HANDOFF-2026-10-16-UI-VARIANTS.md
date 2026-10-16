# 交接：一套 App 内并存两套完整 UIUX（可切换）

**日期** 2026-10-16 · **状态** 结构与闸门已立，两套界面的视觉差异目前只到首屏
**接手前提** 本机无 Xcode / 无模拟器，Swift 一行都没编译过。所有"通过"都只到静态闸门为止。

---

## 0. 需求（用户原话，不要重新解释）

> 我只说我的需求，在app里面可以切换出2套不同的UIUX（一致性、完整性；就是今天新做的2套UIUX方案）剩余的你怎么实现不用问我（除非你做不下去）

两套方案是当天做的：**「一枚锁核」** 与 **「近场仪表」**。原型在
`design-system/ui-variants/prototypes/core-ui.html` 与 `gauge-ui.html`（浏览器直接打开，
右侧有浅色／减弱动态／在场等开关，`?chrome=off` 只留机身便于截图）。

---

## 1. 一分钟看懂现在到哪

| 项 | 状态 | 复算命令 |
|---|---|---|
| 切换机制 | ✅ `legacy / core / gauge` 三态，默认 legacy | `App/Core/UIVariant.swift` |
| 目的地分母 | ✅ 77 个，机器抽取 | `node tools/destmap.js` |
| 缝覆盖率 | ✅ 77/77 = 100% | `node tools/uicoverage.js` |
| 语法层穷尽性 | ✅ 三 case 齐全且非空壳 | 同上，检查三 |
| 全部门闸 | ✅ 全绿：`tools/*.js` 32 个（其中 2 个写文件的一次性迁移工具未跑）+ `tools/layout-*` 8 个 = **38 道 PASS** | 见 §8.3 |
| 两套首屏 | ✅ 都实现了；**gauge 首屏的两块面板已改由 `VK.container` 下发**（P2 完成） | `App/UI/VariantRoots.swift` |
| 裸写换页 | ✅ 代码里 **0 处** `requestTab(<字面量>)`；`pendingRoute` 也从 `Int?` 收成 `Route?`（P3 完成） | `node tools/uicoverage.js`（检查六） |
| 变体色板断言 | ✅ 10 档已从 `VariantRoots.swift` 搬进 `DS.Palette`；`contrast.js` 新增 F 节 12 条，**421 条 0 不达标** | `node tools/contrast.js` |
| **首屏以下的视觉差异** | 🟡 见下"逐页覆盖度"表；自绘容器 **151 / 176** | 见 §4 / §8.5 |
| 编译验证 | ❌ 一次都没编过 | 只能靠 CI |

**逐页覆盖度（2026-10-16 接手轮后）** —— 一个页面"新不新"看它有多少层是变体说了算的：

| 层 | 站点数 | 状态 |
|---|---|---|
| 页面底色 | 100（`dsScreenBackground` 99 + 缝） | ✅ 变体分叉 |
| 清单骨架 `.variantList()`（分组内缩/行分隔线/节距/**Section 标题渲染**） | **85** | ✅ 新增（批二） |
| 控件色 `.tint`（开关/滑杆/选择器/链接） | 缝里一行 ⇒ 全仓 **120 处 `Toggle`** 跟着走 | ✅ 新增（批二） |
| 共享按钮（主/次/破坏性） | **61** | ✅ 新增（批二） |
| `Card` / `SectionTitle` / `StatusPill` | 53 / 21 / 29 | ✅ 已有 |
| 中性底衬 `variantPlate` | 22 | ✅ 已有（批一） |
| 两套首屏 | 2 | 🟡 gauge 面板已走语法层 |
| **页面内部的排版与自绘容器** | **151 处容器** + 大量手写字号/间距 | ❌ **这是剩下的全部欠账** |

⇒ 现在切变体，**每一个页面**的底座、清单骨架、开关颜色、按钮形状都换了一套；
但**行里面那点内容怎么排**（手写的字号、间距、手画的盒子）仍然是共用的。这就是"还不算全新"的准确含义。

**最重要的一句话**：`uicoverage` 报 100% 只证明"每个目的地都挂了缝、没有页面会缺"，
**不证明两套长得不同**。后者才是用户要的东西 —— 它由下面那张**逐页覆盖度**表管着，
而不是由任何一个单一数字管着。

---

## 2. 架构决定与理由（别再走这两条弯路）

### 为什么不是"77 个页面各抄一遍"
抄两遍之后任何字段、文案、开关行为都要改两次 —— 就是本仓反复踩的"同一个量算两次"，
两套必然漂移，漂到最后就是"切到某版少一个功能"。**内容单一来源，视觉语法两套各一份。**

### 为什么不是"中央路由表"
77 个目的地绝大多数由宿主本地 `@State` 呈现（`.sheet(item: $x) { LockProfileView(mac: $0) }`），
搬到中央路由要先提升全部本地状态；而 `@ViewBuilder` 装不下 77 个分支 ——
本仓已两次因巨型 body 报 `unable to type-check this expression in reasonable time`
（见 `LockKeeperApp.swift` 的 `mainTabView` / `rootGroup` 注释）。**这条路试过，走不通，别再试。**

### 采用的做法
每个变体定义一份完整视觉语法（`App/Core/VariantGrammar.swift` 的 `VK`），
所有页面经过同一个缝 `.destined(_:)`：

- **一致性** = 语法只有一个实现处，页面拿不到"自己随便画个容器"的余地；
- **完整性** = 每个方法内部是穷尽 `switch`，少给某变体定义就编译不过；
  空壳分支（`AnyView(EmptyView())` 凑数）由 `uicoverage` 检查三抓。

共享组件是杠杆：`Card` 一处定义 53 处调用、`dsScreenBackground` 100 处、
`SectionTitle` 21 处、`StatusPill` 29 处 —— **把这四个的内部实现搬进 `VK`，
一次改动让 200 多个容器跟着两套走**。已经做了，legacy 分支是原代码逐字搬过去的。

---

## 3. 文件清单

### 新增 Swift（5 个，共 ~1290 行）
| 文件 | 内容 |
|---|---|
| `App/Core/UIVariant.swift` | 三态枚举 + 存储键 `kf_ui_variant` + 各自 title/note/unfinished 文案 |
| `App/Core/Route.swift` | 目的地身份。**顺序、深链 host、访客受限集三样都从它一处派生** |
| `App/Core/Destination.swift` | 77 个 case，**由 `destmap.js --emit` 生成，不要手改** |
| `App/Core/VariantGrammar.swift` | `VK` 语法层 + `.destined(_:)` + `VisitLedger` + `VariantCoverageRow` + 两套的"场" |
| `App/UI/VariantRoots.swift` | 两套首屏 + `LockReadout`（诚实读数层）+ 共用的域浮层 + `MomentLayer` |

### 新增工具（4 个，共 ~820 行）
`tools/destmap.js`（台账，正控 7 / 反控 3）、`tools/uicoverage.js`（四+一道检查）、
`tools/applyseam.js`（挂缝）、`tools/migrateroute.js`（一次性迁移）。
自检夹具在 `fixtures/{destmap,uicoverage,migrateroute}/`。

### 改动
`App/LockKeeperApp.swift`（变体分叉、`requestRoute` 漏斗、`bootstrapOnce` 抽取、
`MomentLayer` 抽取、`Card`/`SectionTitle` 委托）、`App/Core/DesignSystem.swift`
（`dsScreenBackground` 分叉、`StatusPill` 委托）、`App/UI/SettingsView.swift`（切换器 + 覆盖读数）、
外加 12 个文件里 23 处 `tabSelection = <序号>` → `requestRoute`。

### 设计文档
`design-system/aurora-lock/MASTER.md`（§10.1 旧→新表已作废、§2 玻璃数已更正、§11 指向 CORE.md）、
`design-system/aurora-lock/CORE.md`（「一枚锁核」全项目方案 + §13 两套并存架构）、
`design-system/ui-variants/`（两个原型 + 尺子 + 6.7MB 评审证据图）。

---

## 4. 还没做的（按优先级，每条给下一步动作）

### P1 · 把自绘容器接进 VK —— ✅ **已完成到可完成的极限**（176 → **113**，剩 113 永久豁免；见 §8.9）

<details><summary>接手时的分类口径（保留，因为那 113 处的判据就是它）</summary>
```bash
node tools/uicoverage.js --verbose      # 列出每个文件的自绘容器数
```

**接手后第一件事：先给这 176 处分类。** 它们**不是同一个东西**，一把梭会把功能改坏：

| 类 | 形状 | 能不能动 | 数量级 |
|---|---|---|---|
| ① 装饰性中性底衬 | `.background(DS.Palette.surfaceAlt, in: Capsule()/RoundedRectangle(...))` | ✅ 该接 | **22 已接，余少量带描边的** |
| ② 带状态语义的底衬 | `.background(on ? accent : surfaceAlt, in: Capsule())`、进度空槽 `Capsule().fill(surfaceAlt)` | ❌ **不许动** —— core 去掉底就等于去掉"开着/关着" | 约 60 |
| ③ 提示条 / 校验块 | `.background(warn/ok/accent.opacity(0.1), in: RoundedRectangle(control))` | 🟡 要接，但得先有能表达 tone 的语法件 | 约 40 |
| ④ 条 / 刻度 / 点 | `RoundedRectangle(cornerRadius: 1/2/3)`、开关轨道 | ❌ 不是容器 | 约 30 |

**批一（已完成）**：给语法层加了 `View.variantPlate(_:_:)` + `PlateShape`（`VariantGrammar.swift`）。
legacy 分支就是改造前那一句 `background(style, in: shape)` —— **同一句调用、同一个形状，像素不可能变**
（"默认值 = 零行为改动"这条靠构造保证，不靠"照着重写"）。core 去掉底，gauge 换成 `bezel` 凹槽。
22 处调用点已迁，基线 176 → 154。

**批二（下一步）**：给 `variantPlate` 加 `edge: Color?`（带描边的那几处：`AccessibilityView:132`、
`StatsView:742/1597/1796` 现在不敢迁，就是因为 legacy 的 `strokeBorder` 必须在同一句里复刻）。
**批三**：类 ③ 加一个带 tone 的语法件（`VK.callout(tone:)`），core 把"洗一层色"换成"染一根线"
（与 `VK.card` 的 core 分支同一条纪律）。类 ② 与类 ④ **永远不接**，这条要写进 §4 的验收口径。

</details>

### P2 · 两套首屏自己还没用 VK —— 🟡 **gauge 一半做了，另一半刻意没做**

**做了**：`GaugeHomeView` 的两块面板现在经语法层下发 —— `powerWindow` → `VK(variant: .gauge).container(.hero)`、
两个副读数小格 → `.container(.inset)`；同时**删掉 `windowShape`**（那两行 `RoundedRectangle(cornerRadius: 16)` 里的
圆角/描边/凹槽色本来就是语法层的东西）。改后圆角 16→14、描边 1.0→0.8，是刻意的"让语法层说了算"。

**刻意没做（这是结论，不是欠账）**：
- `VK.metric` 用了会让电量读数**永远染成琥珀色**（它的 gauge 分支写死 `foregroundStyle(accent)`）。
  而首屏现在靠 `here ? gaugeAmber : textSub` 表达"不在场 = 读数不可信" —— 换过去就把这个诚实信号拆了，
  直接违反 `docs/CAPABILITY.md` §5 那条（不能拿有源的口吻说没源的话）。要改得先给 `metric` 加 `unread:` 档。
- `VK.primaryButton` 的 gauge 分支是**实底 accent**，而首屏主按钮是 `gaugeAmber → gaugeDeep` **渐变**。
  换过去会将渐变拉平。要改得先给 `primaryButton` 加 `fill:` 档。
- `CoreHomeView` **没有任何 `RoundedRectangle`**（它的 5 处全在 gauge 那边），它自带的是字号与色；
  而语法层目前**没有"锁核"这个形状的语法件**（dot / core）—— 那不是"首屏没用 VK"，是 VK 还没长出那个件。
  ⇒ **合并进 P5（拖拽召唤锁核）一批**，因为那批本来就要碰 `matchedGeometryEffect` 与核的形态。

### P3 · 裸写 `requestTab(<字面量>)` —— ✅ **已完成**（2026-10-16 接手轮）

**先纠正本文件原来那条复算命令**：`grep … | grep -vE '//.*(requestTab|原写|走查)'` 会把
**带行尾注释的真代码**一起滤掉（本仓大量跨 Tab 跳转写的是 `app.requestTab(1)   // 2026-10-14 走查: …`），
于是它只报 27 处、把另外 9 处藏了起来 —— 它报的数字比实际小，**看起来像"快完了"**。
正确的判据是"剥掉行尾注释之后再匹配"，已固化成常驻**检查六**（`tools/uicoverage.js`，判失败，
带正控/反控各一）。

实际施工 36 处：全部换成 `requestRoute(.device/.credentials/.records/.settings)`（序号 0/1/2/3 → 4 个 case）。
`requestTab(Int)` 兼容适配器**保留**，只剩从深链序号（`handleDeepLink`）与 List 选中集派生的
**动态**形式（`requestTab(tab)` / `requestTab(selected.first ?? 0)` / `requestTab(goto.1)`）——
它们本来就是序号语义，且都汇进同一个漏斗。

顺带同一主题收掉的：`pendingRoute` 从 `@Published var pendingRoute: Int?` 收成 `Route?`
（`LockKeeperApp.swift` + `BackupStudioKit.swift` 共 6 处），于是"挂起的落点"不再是一个裸序号。
**零行为改动**：`requestTab(t) ≡ requestRoute(Route.from(tab: t)!)`，t 都是 0–3 的合法字面量。

### P4 · 十个大文件**从未读过源** —— ✅ **已取证**（`node tools/bigfiles.js --verbose`，2026-10-16）

`>=800 行`共 26 个文件 / 47,518 行。十个改名文件的实际内容与"按文件名推断"的归属**对不上**，
逐文件清单（类型名）已入工具输出。三条最重要的更正：

| 文件 | 旧推断 | 台账证据 |
|---|---|---|
| `Sheets.swift` (2862, 13 类) | "凭证弹层宿主" | 实为**门锁/硬件域**：`AddDevice/DeviceInfo/LockProfile/Firmware/KeychainHW/Gateway/Members/Messages/AddPwd/StartAddFp` |
| `CredentialStudio.swift` (3311, 16 类) | "凭证制作页" | 是**整个钥匙域的创作面**：`PwdStudio / TempCodeStudio / FpStudio / OtpStudio / PwdDetailStudio / FpDetailStudio / CredStudioEntryView` |
| `MemberCenterView.swift` (2412, 21 类) | （旧文写"已读"） | 21 个类型，是**钥匙域里最大的一处**（成员/借出/归档/家庭设置/会议/家庭备注） |

其余：`RecordsView`(11) `StatsView`(7，含 `YearReportView/HourDetailSheet`) `ExportCenter`(4，含两张分享卡)
`DeviceHomeView`(6，含 `SyncTimeView/FocusUnlockView/UnlockGateView`) `DiagnosticsView`(2，真的很薄) `BackupStudio`(9)。
`Onboarding`(704) 不到 800 行，未入该工具的输出；它的归属（首启流程，与三域无关）与旧推断一致。

> 工具口径：类型清单来自源码里 `struct/enum Xxx` 的声明，**不是注释也不是文件名**；
> 它只回答"这个文件里住了什么"，不回答"用户此刻想干什么"（那是 CORE.md §5 的归属判据）。
> 两者要分开看：文件是**实现归属**，域是**意图归属**，而 CORE §5 明写按后者分。

### P5 · 拖拽召唤锁核 —— ✅ **已实现**（2026-10-16）

1:1 跟手 + 橡皮筋（c=0.55）+ 动量投影（d=0.99 / 鉗位 ×1.4）+ `matchedGeometryEffect`。
物理常数逐条取自 `CORE.md` §4（response 0.35 / damping 1.0，仅带动量的释放给 0.82）。

**做法与理由（别改成"在视图里算"）**：几何全部抽进 `App/Core/SummonGeometry.swift` 的纯函数，
由 `tools/summonshadow.js` 用另一门语言逐行对拍（30 条）+ 跟 CORE.md §2 的 11 个锚点做防漂移。
视图里只剩"把拖拽位移喂进来、把结果画出去"。

**必须换掉 `sheet` 的原因（已发生）**：`matchedGeometryEffect` **跨不过 sheet 边界** ——
sheet 是另一个宿主层级，于是"同一枚锁核缩到 0.42 骑在浮层标题右侧"只能画一枚假核，
那就是公理 2 禁止的接缝。已改为**根层级自绘的玻璃层**（`DomainLayer`），
代价（模态语义 / 收起通路 / 安全区）三条都自己补了，写在那个 struct 的头注释上。

**未验的照实说**：形变观感、1:1 跟手的手感、弹簧曲线 — 一条都没被执行过（本机无 Xcode/模拟器）；
被机器验过的只有算术、常数与文档一致性。按压充能（1100ms）与开门三层涟漪**未做**。

### P6 · 真机点一轮，产生到达台账
设置页「外观」节有一行 `这套已到达 N / 77` 与未到达清单（`VisitLedger`）。
静态检查只能证明"没漏挂缝"，**只有真机能证明"走得通"**。两套各点一遍才算数。

### P7 · 待拍板 5 条（`CORE.md` §11，都有默认线）—— ✅ **三条已按默认线施工**

- ~~**P-1** 浮层态读不到锁状态~~ → 已做：浮层顶部一行小号读数（在场/电量/键盘冻结/连接），
  读数一律来自 `LockReadout`（"读不到就说读不到"的唯一出口），不新增元素。
- ~~**P-2** 浮层态没有域间横向通路~~ → 已做：顶部一条域切换带，三域互跳，再点当前域=收起。
  平铺档同样给带字条目（降档只改密度，§6.3）。
- **P-3** 平铺 + 降透明同时开那一格 —— 仍无人验过（实底 + 三行 + 无动效），要真机截图。
- ~~**P-4** 十个未读大文件~~ → 已取证，见上面 P4。
- **P-5** 浅色开关 OFF 轨道余量 —— 已按"平台基线 + 0.5px 描边而不是动品牌渐变"施工
  （描边写在开关形状里，定值在 `contrast.js` G 节）。仍未真机看。

---

## 5. 踩过的雷（每条都是被闸门或独立评审抓出来的，不是理论风险）

1. **DOM 顺序当 z 序用** → `.sheet` 排在 `.core` 之后无 z-index，浮层整个盖住锁核，
   "缩小骑在标题上"这个形态在 6 张截图里**根本没交付**。
2. **内联样式打败降档选择器** → 光点坐标写在 `style="left:…"`，平铺档重排规则一条都不生效，
   三行右缘切字、被核压住。**可被降档重排的位置数据不许写成视图内联样式。**
3. **特异度反压状态类规则** → `#cor[data-mode="light"] .sw` (1,2,0) 压掉 `.sw.on` (0,2,0)，
   浅色档四行开关渲染成同一种灰，ON/OFF 实测 1.02:1。**只在一种主题下发作，走查看不出来。**
4. **修一个量会压到另一个量** → 为把轮廓顶到 3.0 把进度空轨拧深，结果"已充能"比"还没充"还淡，
   主操作反馈层级反了。**改一个数要同时量被它压住的那个数。**
5. **自造门槛删掉并留理由** → 「空轨对盘体 ≥1.15」是我发明的、无外部依据，
   和「弧对空轨 ≥3.0」夹出无解三明治。删了，理由写在 `gchecks()` 原地，**没有降数值凑绿**。
6. **尺子里手抄的常数必然漂移** → CSS 从 `.11` 一路改到 `.035`，脚本里还留着 `.11`，
   连着两轮"改了值数字不动"。已加防漂移第 8 节：尺子回读 `core-ui.html` 的 18 个锚点。
7. **追加的校验节排在 process.exit 之后 = 从没跑过** → 第 8 节一开始挂在 exit 后面，静默不执行。
8. **崩掉的退出码和判失败的退出码一样** → `uicoverage` 里我写了个未定义变量 `VERBOSE`，
   闸门抛异常退 1，看起来像"闸门红了"，其实它从头到尾没跑完，那次正控什么都没验。
   现在 0=通过 / 1=判失败 / 2=尺子坏了，三个码已分别验证过。
9. **`node -e` 里混中文和引号必炸**（本仓记过多次）→ 一律改用 Edit 工具或落地一个临时 .js。
10. **正则吃不下带括号的参数** → `\([^)]*\)` 匹配不了 `.sheet(isPresented: Binding(get:{},set:{}))`，
    台账一直在漏计，修好后 74→77。
11. **用"注释里的关键词"当豁免条件，会把真代码一起豁免** → P3 那条 `grep -vE '//.*走查'`
    漏掉 9 处真代码（它们的行尾注释里恰好写着"走查"）。**豁免必须判"剥掉注释之后的代码"，
    不能判"这一行里有没有出现某个词"。** 现固化为 `uicoverage` 检查六 + 它自己的正/反控。
12. **工具的正则会跨越函数边界** → 检查三找方法用的是 `func …\(([\s\S]*?)\)…-> AnyView {`，
    `[\s\S]*?` 会一路吃到**下一个** `-> AnyView {`，于是失败信息指着 `destined()`，
    真正空壳的是 `variantPlate()`。**正则里的"任意字符"要问一句：它能跨过什么？**
    已用 `[^{}]*` 卡住参数表。
13. **闸门进步也是进步，且要能被证伪** → 本轮改了 uicoverage 三处（新增检查六、收紧检查三的
    `switch` 与函数边界判据）。每一处都做了**注入测试**：注入真代码/空壳 → exit 1 且点名对象正确，
    还原 → exit 0。没有这一步，"我加了个闸门"和"我加了个永远绿的装饰"看不出区别（见第 8 条）。

---

## 6. 两条 UIUX 的方向摘要（继续设计时别跑偏）

**「一枚锁核」** 北极星：导航即画面 —— 一枚可变形玻璃核 + 三个环绕光点，零 Tab 零卡片零列表页。
三条公理：零卡片定理 / 一枚物体五种形态 / 发光层预算 2。
两轮独立视觉评审 5/10 → 7/10。色 `#4338CA #6D28D9 #22D3EE` 极光，
**自我批评记在这里**：这组紫蓝弥散正是 AI/开发者工具的品类默认模板。

**「近场仪表」** 北极星：这是一台近场仪表，不是一盏状态灯 —— 每个读数都带来源和年龄，
「没在场、没读到」是正常画面不是错误页。熄屏是默认态，走近连上后逐段点亮、指针先扫满再落回真值。
色 `#0B0A08` 暖黑 + 机加工金属 + 单一琥珀 `#F2A73B` + 警示朱 `#D8583F`。
标杆拆的是 Nuki（`design-system/ui-variants/evidence/bench-nuki.png`，
另一家 Aqara 的整页太大没进仓库，看 https://www.aqara.com/en/ ）。

**两套共同的硬事实约束**（`docs/CAPABILITY.md` §5）：这台锁**没有上锁状态位、没有门磁、
没有在线状态**，纯 BLE 近场、厂商云已停服。所以任何"已上锁/已开启"式大字都是无源断言。
`LockReadout` / `VisitLedger` 就是为守住这条写的：**读不到一律显示破折号，不许显示 0 或"无"**
（不在场时把"防撬告警"显示成"无"等于给用户一份假平安）。

---

## 7. 对比度尺子

`design-system/ui-variants/prototypes/contrast-check.js`，`node` 直接跑，退出码同上三档。
36 个覆盖点（文字 16 + 非文字/有色文字/平铺档 20）+ 18 个防漂移锚点。
关键结论：**浅色彩钮要单独解一组**，不能沿用深色解出来的极光上限 0.414；
施工值 = 门槛 × 1.15 留余量。它现在锁死的是 `core-ui.html` 那套 token，
**给「近场仪表」用之前必须另建一份**，否则绿灯是借来的。

> ✅ **已解决（同日接手轮）**：那 10 档变体色已搬进 `DS.Palette`（`DesignSystem.swift` 的 `enum Palette`，
> 调用点仍是 `DS.Palette.gaugeCanvas` 这种写法），`tools/contrast.js` 新增 **F 节 12 条**断言
> （两套界面各自的场底 × 正文 / 次级文本 / 读数 / 渐变暗端）。断言总数 → **421**。
> 这批断言当场**抓到一处真实缺陷**：仪表深档主按钮文字压在琥珀渐变暗端只有 **4.47:1**，
> 差 0.03 没过 AA（而主按钮文字居中，行高会落在渐变下半段）。已把 `gaugeOnAmber` 深档改纯黑 → **4.90:1**。
> 这是“先加尺子”的价值，不是“改一个数凑绿”。
> ⚠ **仍然成立的一条**：上面这句说的是 **Swift 令牌**；`core-ui.html` 那套 **HTML 原型 token** 的尺子
> （`design-system/ui-variants/prototypes/contrast-check.js`）**仍未覆盖 gauge**。

---

## 8. 接手轮（2026-10-16 之后那次）做了什么

### 8.1 交付

1. **P3 完成（36 处）** + `pendingRoute: Int?` → `Route?`。零行为改动（见 §4 P3）。
2. **P1 批一（22 处）**：新增 `View.variantPlate(_:_:)` + `PlateShape`，
   只收"装饰性中性底衬"这一族；legacy 分支逐字等于改造前那一句，**像素不可能变**。
   基线 176 → 154（`fixtures/uicoverage/budget.json`）。
3. **P2 一半**：gauge 首屏两块面板改走 `VK.container`；另一半写了"为什么不做"（见 §4 P2）。
3b. **S4 · 变体色板入尺子**：`DS.VariantPalette` 整块搬进 `DS.Palette`（`DesignSystem.swift`），
   32 处调用点改名，`tools/contrast.js` 新增 F 节（锁核/仪表 12 条）。当场抓到并修掉一处 AA 级缺陷（见 §7）。
4. **闸门进步三处**（`tools/uicoverage.js`）：新增检查六（裸写 `requestTab(<字面量>)`，判失败）；
   检查三的 `switch` 判据从字面 `switch variant` 收紧成 `switch [\w.]*variant`（原先
   View 扩展里的语法件会静默逃过穷尽性检查）；检查三的函数边界从 `[\s\S]*?` 换成 `[^{}]*`
   （原先会把方法算到上一个函数名下，见 §5-12）。

### 8.2 怎么验的（可复算）

| 项 | 命令 | 期望 |
|---|---|---|
| 裸写序号（代码，非注释） | `node tools/uicoverage.js` | 检查四 / 检查六 均"零命中" |
| 预算 | 同上 | `154 = 基线` |
| 语法层穷尽性附带新件 | 同上 | 检查三 通过（`variantPlate` 已入查） |
| **检查六有牙** | 往 `App/UI/` 放一个 `{ app.requestTab(2) }` | **exit 1**；改成注释形态 → exit 0 |
| **检查三有牙** | 把 `variantPlate` 的 `.gauge` 分支换成 `AnyView(EmptyView())` | **exit 1 且点名 `variantPlate()`** |
| 全量 | 跳过 `applyseam.js` / `migrateroute.js`（写文件的一次性工具），其余全跑 | 38 道 PASS |

> 两个"有牙"测试都是**跑过再还原**的，不是推断。这正是 §5-8 那条教训要求的形状：
> 光看闸门绿没法区分"它在工作"和"它压根没跑"。

### 8.3 全量闸门的确切跑法（含两个写文件工具的处置）

```bash
cd ios-app
for t in tools/*.js tools/layout-audit/*.js tools/layout-replica/*.js; do
  case "$t" in *migrateroute*|*applyseam*) continue;; esac   # 一次性迁移工具: 会写文件, 不进常驻回圈
  node "$t" || echo "FAIL $t"
done
```
`tools/layout-audit/fix-spacing.js` 默认 **dry**（要 `--apply` 才写），`tools/layout-replica/build.js`
只写自己目录下的产物 ⇒ 这一圈不会动 `App/`。

### 8.4 下一步的次序建议

1. **P1 批二**：`variantPlate` 加 `edge: Color?`（把带 `strokeBorder` 的 4 处收进来）。
2. **P1 批三**：`VK.callout(tone:)` 收类 ③（提示条/校验块），core 换成"染一根线"。
3. **S4 · 变体色入 `DS.Palette` + 补 `contrast.js` 断言** —— 这是两套转正的前置，不得再押。
4. **P5**（拖拽召唤锁核）与 `CoreHomeView` 的形状语法件合批做，因为两者都要动核的形态。
5. **P4**（先读十个大文件）在批三之后的任何一批之前完成 —— 类 ③ 的容器正大量分布在那几个文件里。

### 8.5 批二：整页级的外观下发（回答"每个页面都是新的吗"）

**用户的追问**：*"是不是我切换后每个页面都是全新的？一定要做到每个页面都是全新的"*。
量过之后结论是：**只接容器不够** —— 一页的长相大半不由那几个盒子决定。批二把决定长相的
三层（清单骨架 / 控件色 / 共享按钮）也挂到变体上，三者的调用点都极其集中：

| 新语法件 | 换掉什么 | 站点 |
|---|---|---|
| `View.variantList()` | 全仓 85 处 `.scrollContentBackground(.hidden)` | 85 |
| 缝里的 `.tint(vk.accent)` | `tint` 走环境 ⇒ 全仓 120 处 `Toggle` + 所有滑杆/选择器/链接 | 1 行 |
| `VK.primary/secondary/destructiveActionChrome` | 三个共享 `ButtonStyle` 的外形 | 61 |

`.listStyle` 不只是样式 —— 它同时决定分组是否内缩、**Section 标题怎么渲染**（全仓 255 个 `Section`）。
所以这一行换掉之后，清单页的"骨架"是新的，不是只换了个背景色。

**已验证**（都是跑过再还原）：
- `variantList()` 已入检查三管辖：把 `.core` 分支换成 `return AnyView(EmptyView())` ⇒ **exit 1 且点名 `variantList()`**；还原 ⇒ exit 0。
- 三个新 `ActionChrome` 同样在检查三的名单里（clean 树下检查三通过）。
- 三个 `ButtonStyle` 的调用形状（`()` 19+7+2 / `(fullWidth: false)` 7+26）在加了 `tint` 默认值之后仍然全部成立。
- 预算 154 → **151**（三个 `ButtonStyle` 里的 `RoundedRectangle` 搬进了语法层，那文件不计入预算）。
- 38 道门全绿。

**还没做，且需要一个决定**：`Toggle` 的**形状**（现在只换了颜色）要换的话得写自定义 `ToggleStyle`。
本仓把无障碍当一等闸门，而自定义 `ToggleStyle` **会丢掉系统开关的 VoiceOver 语义**
（要手写 `.accessibilityAddTraits/.accessibilityValue` 才能补回），而这两种都只能真机验。
⇒ 单独一批做，带 VoiceOver 验收；不建议和批二混在一起。

### 8.6 批一的已知边界（这几条只有真机/像素上才看得出来）

- 批一含了 3 处**动作行**底衬（`CredentialStudio:1188/1736/1749` 那一族里带 `buttonStyle(.plain)` 的行）。
  它们在 core 下会**丢掉"这是一块可点区域"的边界**，只剩 `minHeight` + `contentShape` 撑住的命中高。
  这是 core「零卡片定理」的既定后果（用户能切回去），但**得真机看一眼才算交付**。
- **没接、也不该接**的一类（属 §4 P1 表里的类 ②）：`BackupStudio:499/505` 是 `SecureField` 的底衬 ——
  那是**输入控件的可识别性**，不是装饰。core 去掉它 = 冒出一个没有任何边界的输入框。
  同族还有 `RecordsView:587`（带 hairline 描边的输入框）与 `Sheets:215`（四步进度条实底，它自己的注释写着"保持实底"）。
  ⇒ 批一之后，类 ② 得再拆一格：**"状态底衬" vs "控件可识别性底衬"**，两者都不能接。
  （这也是为什么 `BackupStudio:483` 能接、它下面两行的 `:499/505` 不能接 —— 同一个文件里两种性质。）
- 4 处带 `strokeBorder` 的中性胶囊（`AccessibilityView:132`、`StatsView:742/1597/1796`）**不在**批一里：
  要先把 legacy 的 `strokeBorder` 在同一句 `variantPlate` 里复刻，才能保住"像素不可能变"。这是批二的入口。
  → **批四已收掉**（见 §8.8）。

### 8.7 一句话要留下来的话

**176 这个数不是一个进度条，它是四个不同问题被加在了一起。**
接手的人要做的第一件事不是减这个数，而是把要减的那部分和**不能减**的那部分分开 ——
后者（开关轨道、进度空槽、选中态）接进 VK 会把功能改坏，而闸门**看不见**这种坏。

### 8.8 批三（callout）+ 批四（带描边胶囊）：容器预算 151 → 131

20 处、6 个文件、两天内最容易做错的那一类。

**批三 · 16 处语义洗底块 → `variantCallout(_:_:wash:)`（新语法件）**
`LinkSenseKit` 1 · `BackupStudio` 6 · `CredentialStudio` 6 · `CredentialsView` 3。

为什么**不能**复用 `variantPlate`：两者看着都是"一个盒子的底"，性质相反。
`variantPlate` 收的是**装饰性底衬**，core 里整块去掉是对的；而提示条那层洗色是**信息**
（"这一段是告警"），core 去掉它 = 把信息去掉。所以 callout 的 core 分支换的是**载体**而不是"去底"：
洗底 → **左侧一根 2pt 的染色线**（和 `VK.card` 的 core 分支同一条纪律：盒子没了、语义色还在，且更显式）。
把这一族塞进 `variantPlate` 会让"零卡片定理"误杀信息，这是它单独成件的原因。

gauge 分支 = 凹槽窗格 + 同一根 tone 侧线 + `hair` 描边；legacy 分支逐字复刻原句。
**信息不靠整块洗色传达**是这两套的共同前提；gauge 保留窗格是因为它的窗格**不是装饰**（是面板基底）。

**批四 · 4 处带 `strokeBorder` 的中性胶囊 → `variantPlate(_:_:edge:)`**
`AccessibilityView` 1（`hairlineStrong`）· `StatsView` 3（`hairline`）。

描边**不能**复用 `legacy`：`strokeBorder` 只长在 `InsettableShape` 上，而 `AnyShape` 把那个能力擦掉了
（`AccessibilityKit` 里已经记过这条）⇒ 单开 `legacyEdge(_:_:)`，把原句的 `0.5pt` 逐字带上。
core 分支连描边一起去掉 —— **只剩一圈线的容器仍然是盒子**；gauge 换 0.7pt 倒角描边。

**怎么验的（都可以重跑）**
- `contrast.js` 421 条 0 不达标、`dynamictype` / `swiftshape` / `swiftsyn` / `uicoverage` / `sheetcover` 等
  **19 道判失败闸门全绿**（跑法见 §8.3）。`uicoverage` 检查三认 `variantCallout` 三个 case 都不空壳。
- **语法层**：用本机装的 tree-sitter Swift 解析器做"工作树 vs `HEAD`"逐文件差分（`_swiftparse/_vshead.js`），
  本次改动的 **37 个 `.swift` 文件全部 `+0` error node**。
  顺带定案了旧疑点：`CredentialStudio`(9) / `RecordsView`(18) / `DiagnosticsView`(3) / `DeviceHomeView`(1)
  的 error node **在 `HEAD` 上数量完全一致 ⇒ 是既有的、不是我引入的**（且抽查两簇均为合法 Swift，属解析器误报）。
- **一个自己踩的坑（值得留一笔）**：第一版批量脚本让同一个文件的**每处**替换各自读原文件、各自写回 ——
  一个文件被安排两处替换时，后一次写盘会把前一次整段盖掉（`BackupStudio`/`CredentialStudio`/`CredentialsView`）。
  是"落点核对"（`grep -c variantCallout` 数出来只有 1 处）当场抓到的。
  修正版**按文件分组、读一次、顺序替换、最后写一次**，并把 0 命中且新写法已在场当"已应用"跳过（可重入）。

### 8.9 第二接手轮：批五~批七 + P5 + P7（2026-10-16）

四批 UI 工作 + 两处尺子修补。所有数字都可复算（跑法见 §8.3）。

#### 1. 批五 · 纯装饰容器 18 处 → 自绘容器 176 → **113**

从 131 里再分出 18 处**纯装饰**接入 `variantPlate`/`gauge` 语法（core 去掉底、gauge 换凹槽）。
剩下的 113 处不是欠账，是**判据上就不该接**的三类，三类都写进了调用点的注释：

| 类 | 形状 | 接进去会怎样 |
|---|---|---|
| ① 状态语义底衬 | `on ? accent : surfaceAlt`、进度空槽 | core 去掉底 = 去掉"开着/关着"这个信息 → **功能缺陷** |
| ② 控件可识别性 | 输入框底衬/描边、实底进度、面板实底 | core 去掉 = 冒出一个没边界的输入框 |
| ③ 条 / 刻度 / 点 | `RoundedRectangle(cornerRadius: 1)`、轨道 | 它们本就不是容器 |

**留痕机制**：每处就地写 `// @layout-allow VK豁免 <类名>`（`App/` 下 **14 处**，另 11 处
`@layout-allow 触达托管 …` 是之前批次就有的、另一类原因），
预算基线钉在 `fixtures/uicoverage/budget.json`（**只能下调**，`uicoverage` 检查五判"新增一处即失败"）。
三类永久豁免这个结论同时写进了 `CORE.md` §13.4 与本文件 §4 P1。

#### 2. 批六 · 开关的**形状**（112 处）

批二只换掉了开关的**颜色**（缝里一行 `.tint`）。这一批换形状：新增 `VariantToggleStyle`
+ `VariantToggle(...)` 三个重载（逐一对照 `Toggle` 自己的重载声明，多一个不多少一个少一个）。

**无障碍是这一批的代价，必须写清**：自定义 `ToggleStyle` 会丢掉系统开关的 VoiceOver 语义，
已手写补回：`accessibilityElement` + `.isToggle` 特征 + `.accessibilityValue(开/关)` + 三个状态名。
→ **但这只能真机验**，本机验不了（与 §8.5 里做出的判断一致）。
防回潮：`uicoverage` **检查七**（裸写 `Toggle(` = 0，带正/反控；豁免语法层自己那 5 处）。

#### 3. 批七 · 行内排版接管（1,775 处）

这是"还不算全新"的最后一块。做法与 `variantPlate` 同一条纪律：

- 新增 `VKTypography` + `View.vkFont(_:weight:)`；全仓**文本** `.font(...)` 改成它（图标尺寸 `DS.Icon` 不动）。
- 变体差只有**字重与字族**两样：core 整体降一档（层级从字重挪到字号，公理 1），
  gauge 整体升一档 + `base.monospaced()`（机加工读数），legacy **逐字原样**（靠构造保证，不是照着重写）。
  升档封顶 `.semibold`：中文界面里 `.bold` 在 PingFang SC 上没有 700 档，会静默回退（`dynamictype` 规则 3）。
- **字距未接管**：那 28 处 `.tracking(...)` 仍写在调用点 —— 语法层再加一份会叠成两倍。
- 为什么用 `EnvironmentKey`（**本仓第一个**）：`.font` 有 1,775 处调用点，而 `VK.current` 是**现读存储**；
  逐处读一次就把"零行为改动"变成"每帧几百次 DB 读取"。注入点在 `RootView.rootCore` **一处**，
  默认值写死 `.legacy`（写成 `UIVariant.current` 会在切回 legacy 时被缓存成 stale 值）。
- 防回潮：`uicoverage` **检查八**（裸写文本 `.font(` = 0，带正/反控，豁免语法层自己 + 图标尺寸 + `Widget/`）。

#### 4. P5 · 拖拽召唤（含**一处架构改动**）

- 几何抽成纯函数 `App/Core/SummonGeometry.swift`，`tools/summonshadow.js` **用另一门语言对拍 30 条**，
  并把 `CORE.md` §2 的 11 个锚点当防漂移尺子（改文档改代码任一侧不同步就红）。
  另含一条**接线控制**：5 个几何入口在视图里必须有调用点 —— 纯函数没人用就是死代码，不是实现。
- **域浮层从系统 `.sheet` 改成根层级自绘的玻璃层**：`matchedGeometryEffect` 跨不过 sheet 边界，
  而"同一枚锁核骑到浮层标题右侧"要求两个状态在同一层级。代价（模态语义 / 收起通路 / 安全区）已自己补。
- 锁核层**显式在最上层**（不靠声明顺序）—— 这是 `CORE.md` §2.1 那个 z 序事故在 iOS 侧的对应物。
- 平铺档：三光点摊成三行带字条目，**拖拽退场**（按 `VK.flatTier` 同一个开关关掉）。

#### 5. P7 · 浮层态的两条默认线

P-1 一行状态读数（在场/电量/键盘冻结/连接，均出自 `LockReadout`）、
P-2 顶部域切换带（三域互跳、再点当前域=收起，平铺档同样给带字条目）。详述在那两个 `private` 成员的注释上。

#### 6. 两处尺子修补（**不是顺手，是它们本来就会漏报**）

| 缺陷 | 实测后果 | 修法与控件 |
|---|---|---|
| `destmap` 把**注释里**的实例化当目的地 | `// …不许放 DeviceHomeView()` 这句解释性注释把一个**不存在**的目的地塞进了台账（分母虚高） | 逐处判是否落在行注释里 + **反控 4** |
| `destmap` 吃不下 Tab 的"内容属性" | 四个 Tab 写的是 `{ deviceTabContent }`（内联会报 type-check 超时），于是**四个根页一个都不进台账** —— 修完发现 `DeviceHomeView` 早就靠一条注释活着 | 跟一跳属性体 + **正控 9** |
| `destmap` 少了第 7 条呈现通道 | 域浮层不再是 sheet，三张根页会**凭空从台账消失**而自检照样报通过 | 登记 `domainLayer` + **正控 8** |

台账修完仍是 **77 条 / 枚举 77 条 / 覆盖率 77/77**（数字没变，但每一条现在都有据可查）。

#### 7. 怎么验的（可复算）

```bash
cd ios-app
node tools/summonshadow.js       # 30 条纯几何 + 11 个文档锚点 + 接线控制
node tools/destmap.js            # 台账 77，正控 9 / 反控 4
node tools/uicoverage.js         # 检查一~八全通过，含新检查八
for t in tools/*.js tools/layout-audit/*.js tools/layout-replica/*.js; do
  case "$t" in *migrateroute*|*applyseam*) continue;; esac; node "$t" || echo "FAIL $t"
done                             # 全量工具 0 失败
```

- 全量工具 **0 失败**（含 `contrast.js` 431 条断言 0 不达标、`dynamictype`、`swiftshape`、`swiftsyn`、`sheetcover`）。
- **语法层**：tree-sitter 对"工作树 vs `HEAD`"逐文件差分 —— **45 个改动/新增 `.swift` 全部 `+0` error node**
  （新文件 `App/Core/SummonGeometry.swift` 单独算出 `errors=0`）。既有的 4 处 error node
  （`CredentialStudio` 9 / `DeviceHomeView` 1 / `DiagnosticsView` 3 / `RecordsView` 18）在 `HEAD` 上数量完全一致。
- `swiftlint` 报过一条 `UnevenRoundedRectangle` 疑似臆造符号 —— 那是该检查的既定误报形态（全仓只出现 2 次），
  已加白并**逐字拄上 Apple 文档的参数名与顺序**；加白不等于它编得过，仍然只能靠 CI 定案。

#### 8. 一个自己踩的坑（值得留一笔）

批量替换脚本里写了 `SKIP_FILES` 却**忘了用**，于是它把自己的语法层文件 `VariantGrammar.swift`（43 处）
和 **`Widget/LockWidget.swift`（10 处）也改了**。后者是硬伤：Widget 是独立 target，只编 `Widget + Shared`，
**看不到 `App/Core`** → 如果没发现就是 100% 编译错误。
是"目标成员核对"（读 `project.yml` 的 sources）当场抓到的，已全部回退。
⇒ 教训：批量脚本的**越界**是静默的，落地后必须拿"改动的文件集 vs 应该改的文件集"对一次差。

#### 9. 本批未验 / 已知边界（照实写）

- 三道 UI 的**观感**：形变、跟手感、弹簧曲线、玻璃面板的实际渲染 — 一行都没执行过。
- 键盘/充能/三层涟漪（按压与开门形态）**未做**。
- 字距接管未做（见上）。
- `VisitLedger` 的 N/77 仍需真机。
- 自定义 `ToggleStyle` 的 VoiceOver 行为、`.isModal` 是否真的挡住了底层光点 — 都要真机验。
