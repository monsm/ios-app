# SWEEP-REPORT — 全仓 V7 迁移与设计闸门修复

日期：2026-10-31 · 执行：重构执行者（子代理）
范围：`ios-app/ios27`（Engine 层不参与设计迁移）

---

## 0. 结论

| 项 | 结果 |
|---|---|
| 设计闸门 | **15/15 全绿**（`node Gates/allgates.js`，见 §4） |
| 33 个旧设计二级页 | **33/33 已迁 V7**，旧令牌引用清零 |
| `Features/**` 的 `T.*` / `Ink.*` / `Panel(` | **0 / 0 / 0**（连注释一起扫也是 0） |
| 全仓非 Engine / 非令牌定义层的旧令牌 | **0**（唯一保留的是 `Design/Tokens.swift` 自身的定义） |
| `V.F.sans(<数字>)` | 页面/组件层 **0 处**；只有 `V7Tokens.swift` 的 81 个命名档定义 |
| V7 常量纠偏 | 19 条中 18 条落地；脚注 16.5px 因 TOKENS 自身 px/pt 混用保留 13pt 可读档（见 §6 豁免 7） |
| 本轮改动 | **59 个设计相关文件**（46 Features + LockKeeperApp + 6 Design/Components + 2 Design/V7 + 4 Gates） |

> 注：`App/Shell/AppModel.swift` 的改动是并行的功能改动，不属于本次设计迁移，未计入上面的 59 个文件与行数。

---

## 1. 闸门修复（优先级 1）

四个闸门原来只认 `T./Ink./Color.dual`，V7 在视野之外。本次全部扩到 `V.*`：

### 1.1 `Gates/tokens.js`
新增判据：
- `V.F.sans(<数字>)` → 违规（V7 字号必须走 `V.F.xxx` 命名档）。
- `.font(... size: <数字>)` / `Font.system(... size: <数字>)` → 违规。
- `V.C.rgb(...)` 只允许出现在 `Design/V7/V7Tokens.swift`（原始 RGB 不得回流页面）。
- 保留原 `.padding(<数字>)` / `spacing:` / `.frame(height: 数字)` / `cornerRadius` / 系统颜色字面量等规则。
- 白名单只有：`Design/Tokens.swift`、`Design/V7/V7Tokens.swift`、`Design/Components/Dial.swift`（Canvas 几何）。

### 1.2 `Gates/dynamictype.js`
- 继续禁止 `.font(.system(size: N))`，并新增禁止 `V.F.sans(<数字>)` 与 `Font.system(size: 数字)`。
- 增加令牌层自检：`V7Tokens.swift` 必须存在 `@ScaledMetric` 且以 `relativeTo:` 接线，否则判失败。
- 显式豁免名单（带理由）：`Design/Tokens.swift`（旧语义字阶）、`Design/V7/V7Tokens.swift`（V7 字体令牌的家）。
- 实际落地：`V.F` 的 81 个命名档全部是 `VFont(size/weight/design/relativeTo)`，由 `VScaledFontModifier` 里的 `@ScaledMetric` 在渲染时缩放。默认字号仍是参考图像素值，Dynamic Type 真生效；页面不再出现字号字面量。

### 1.3 `Gates/contrast.js`
- 解析 `V7Tokens.swift` 的全部 `rgb(r,g,b)` 色令牌，逐对按 WCAG 2.1 核算（正文 4.5:1 / 大字 3:1 / 非文本 3:1）。
- 新增低对比黑名单，命中即失败并给出达标替代：
  - `#48525B`（2.63:1 on #000）→ `V.C.text5 = #8E98A3`（7.17:1）
  - `#6D6D6D`（2.92:1 on #262626）→ `V.C.text4 = #9A9A9F`（5.40:1）
  - `#5D5D62`（2.57:1 on #1D1D21）→ `V.C.infoGlyph = #8E8E93`（5.15:1）
  - `#4E4E50`（2.53:1 on #000）→ `V.C.axisLabel = #8E8E93`（6.44:1）
- 结果：11 个旧令牌 × 2 模式 + 57 个 V7 色令牌，71 条断言全部达标。

### 1.4 `Gates/a11y.js`
- 保留图标按钮 label 与 <44pt 可点区规则。
- 新增：`VListRow` 的 `accessibilityLabel` 必须拼上 `value`（设置页 16 行的 "82% / 已设 / 从未备份" 不能再被 VoiceOver 吞掉）。
- 新增：`VRingStack` / `VMiniBars` / `VAreaChart` / `VSegmentedRing` 必须有 `accessibilityValue` 描述数据（环进度 / 柱值峰值合计 / 曲线起终峰值 / 分段比例）。
- 同时修复了旧实现里 `VListRow` 的 label 拼接与三个图表组件的数值朗读。

---

## 2. V7 常量纠偏（优先级 2，对照 AUDIT-B §2.1 的 19 条）

| # | 审计项 | 落地 |
|---|---|---|
| 1 | 图表高度 125 → 111 | `V.Chart.height = 111` |
| 2 | 点线间距 43pt | `V.Chart.verticalSpacing = 43`；`VAreaChart` 按 `firstInset + index*43` 画 |
| 3 | 首条内缩 14.4 | `V.Chart.firstInset = 14.4` |
| 4 | 点线暗段 2.6 | `V.Chart.dash = [1, 2.6]` |
| 5 | 右侧刻度 #4E4E50 | 换成 `V.C.axisLabel #8E8E93`，`VAreaChart` 的 "高峰/平时" 使用它；TOKENS.md 同步 |
| 6 | 左下 "0 时" | `VAreaChart` 左下轴标 |
| 7 | 迷你柱图轴标 | `VMiniBars` 补 0/6/12/18/24 时轴标（`V.C.axisLabel`） |
| 8 | 活动环外径 133.7 | `V.Ring.referenceOuter = 133.7` |
| 9 | 环宽 14 | `V.Ring.width = 14` |
| 10 | 环间 1.2 | `V.Ring.gap = 1.2` |
| 11 | 环轨道色 | `V.C.ringTrackRed/Green/Cyan` = #33080F/#2E4A12/#16283A，替换 `opacity(0.22)` |
| 12 | 红环渐变 (103,0,0)→(255,53,135) | `V.C.redDeep/redBright` + `VRingStack` 的 `AngularGradient` |
| 13 | 起点方向箭头 | `VRingStack` 12 点处 → / » / ↑ |
| 14 | 分段环暗层同色 55% 亮度 | `V.C.dimmed(color, by: 0.55)`（RGB 直接乘 0.55，不再叠半透明） |
| 15 | 选中胶囊 56 → 60 | `V.Tab.selectedW = 60` |
| 16 | 脚注 16.5px | 未强行套用（TOKENS px/pt 混用）；保留 `V.F.footnote = 13pt`，见 §6 豁免 7 |
| 17 | 22pt/700 数字档 | `V.F.number22`；记录页筛选计数使用 |
| 18 | 分组小标题 10.7/500 #8E8E93 | `VSectionLabel` 改用 `V.F.small` + `V.C.text3` |
| 19 | 正文行高 23pt | `V.Page.bodyLine = 23`；`bodyLineGap = bodyLine - 20.3`；根页 `.lineSpacing(V.Page.bodyLineSpacing)`（不再用 lineSpacing(6)） |

附加 P0：主环缺口按 R1 JS 实测 `A0=208.4 / A1=516.6` → `sweepDegrees = 308.2`；两端圆头帽各吃 8.58°，可见缺口约 34.6°，与像素实测 34.4° 一致（AUDIT 建议的 339.2 与圆头帽方向相反，未采用）。

附加（AUDIT-B P1 #8）：`VRingStack` 线宽改为 `V.Ring.lineWidth(for: size) = min(14, size * 0.09)`；`size: 88` 时 7.92pt，三环半径 80.08 / 61.84 / 43.6，不再退化成实心点。

`lock27-preview/v7/TOKENS.md` 已同步：活动环 133.7/14/1.2、选中胶囊 60、图表 111/43/14.4、轴标 #8E8E93 的替代说明。

---

## 3. 33 个二级页迁移（优先级 3）

### 3.1 迁移方式
- 逐文件把 `T.S/R/H/Stroke/Icon/F/M`、`Ink.*`、`Signal.*`、`State.*` 换成 `V.S/R/H/Stroke/Icon/F/M`、`V.C.*`、`V.M.*`。
- `Panel {}` → `VCard {}`；`Inset {}` → `VInset {}`；`SectionLabel` → `VSectionLabel`；`ReadingGrid` → `VReadingGrid`；`Reading` → `VReading`；`FieldRow` → `VFieldRow`；`StatusLine` → `VStatusLine`；`StateDot` → `VStateDot`；`PrimaryAction` → `VActionButton`；`SecondaryAction` → `VOutlineButton`；`EmptyPanel` → `VEmptyState`；`BusyRow` → `VBusyRow`；`ChipRow` → `VChipRow`；`LedgerRow` → `VLedgerRow`。
- 保留业务逻辑、数据绑定、路由、动效守卫不动；只换设计系统。

### 3.2 33 个文件（全部清零）
Door（7）：`AddLockScreen` `DefendScreen` `DFUScreen` `GatewayScreen` `LockStatusScreen` `QuickPoolEditSheet` `SyncTimeScreen`
Household（8）：`HouseholdScreen` `HouseholdParts` `MemberDetailScreen` `MemberDetailParts` `MemberCreateScreen` `MemberCreateParts` `MemberArchiveScreen` `MemberMergeSheet`
Keys（8）：`KeyDetailScreen` `KeyCreateScreen` `KeyCreateParts` `KeyCalendarScreen` `KeysBits` `KeysParts` `MobileKeyScreen` `ShareToAndroidScreen`
Records（2）：`RecordDetailScreen` `RecordExportScreen`
Settings（8）：`SecurityScreen` `AppearanceScreen` `BackupScreen` `AutoOpenScreen` `HardwareScreen` `ProtocolTestScreen` `AboutScreen` `SettingsParts`

优先级入口全部覆盖：
- 冷启动 `LockGateScreen`（LockKeeperApp.swift）：旧 `T.F.display(24)` / `Ink.plate` / `PrimaryAction` 全部换 V7。
- 门页「成员」入口 → `HouseholdScreen` 已迁。
- 设置页 16 条 `VListRow` 目的地（Security / AutoOpen / Appearance / Backup / Hardware / ProtocolTest / About 等）全部已迁。

### 3.3 处数
- AUDIT-B 口径：33 个文件共 **995 处 `T.*` + 396 处 `Ink.*` + 118 处 `Panel(` = 1,509 处**。
- 本轮按代码行重新扫描的基线：33 个文件 1,607 处（`T.*` 1,111 / `Ink.*` 379 / `Panel` 117，含 V7Extras 注释）。
- 迁移后：`Features/**` 的 `T.*` / `Ink.*` / `Panel(` = **0**（原始文本扫描，含注释）；全仓非 Engine 非令牌定义层同样为 0。

### 3.4 额外归一
- 4 个根页（Door / Keys / Records / Settings）：字号字面量归一到 `V.F.xxx` 命名档，正文改用 `V.Page.bodyLineSpacing`。
- 8 个原本已是 V7 的页面（CredentialStudio / LinkSense / LockProfile / BatteryProfile / RecordsStudio / Accessibility / Zotp / BackupStudio）：仅做 `V.F.sans(<数字>)` → 命名档归一。
- `V7Extras.swift`：补齐 `VReading` / `VFieldRow` / `VValueRow` / `VReadingGrid` / `VStatusLine` / `VStateDot` / `VEmptyState` / `VBusyRow` / `VChipRow` / `VInset` / `VLedgerRow`，并全部只用 V 令牌。

---

## 4. 验收

### 4.1 闸门
```
$ node Gates/allgates.js
swiftparse: OK — 148 个 Swift 文件无语法错误（已知语法盲区豁免 14 处）
types: 148 个文件，367 个顶层类型，SDK 白名单 332 项
swiftcheck: OK — 148 个文件括号/字符串/注释全部平衡
tokens: OK — 148 个 Swift 文件，0 处硬编码样式字面量（含 V7 字号/色板）
contrast: 解析到 11 个旧色令牌 × 2 模式 + 57 个 V7 色令牌
glass: 扫 148 个文件，自定义玻璃面 0 处
motion: 扫 148 个文件，.animation 调用 13 处
a11y: 扫 148 个文件
dynamictype: 148 个文件，772 处走令牌字号（其中 V7 772 处经 VFont/@ScaledMetric）
reducedmotion: 21 处已守卫
crosprivate: 检查 7 组 Screen+Parts 拆分
callsig: 跟踪 14 个组件，检查 0 处具名调用
lineage: OK — 148 个文件，0 处上一版设计系统残留
workflow: 检查 1 个文件
destmap: Dest 44 项，映射 44 项，已声明 View 147 个

allgates: 全部 15 道闸门通过
```

> 并行分支仍在新增页面，文件/调用计数会随验收时刻变化；**15/15 的闸门结论不变**。

### 4.2 旧令牌 grep
```
Features/**  T.* = 0   Ink.* = 0   Panel( = 0
全仓非 Engine / 非 Design/Tokens.swift  T.* = 0   Ink.* = 0   Panel( = 0
V.F.sans(<数字>) 在 V7Tokens.swift 之外 = 0
```

---

## 5. 改动文件（59）

| 组 | 数量 | 文件 |
|---|---:|---|
| 33 个二级页 | 33 | 见 §3.2 |
| 4 个根页 | 4 | DoorScreen / KeysScreen / RecordsScreen / SettingsScreen |
| 已 V7 页的字体归一 | 8 | CredentialStudioScreen / LinkSense / LockProfileScreen / BatteryProfileScreen / RecordsStudioScreen / AccessibilityScreen / ZotpScreen / BackupStudioScreen |
| 共享件 | 1 | Features/Shared/V7Extras.swift |
| 冷启动 | 1 | LockKeeperApp.swift |
| 旧组件壳（内部改 V 令牌） | 6 | Design/Components/{CaptureShield,Dial,Ledger,Panel,Primitives,Reading}.swift |
| V7 核心 | 2 | Design/V7/{V7Tokens,V7Components}.swift |
| 闸门 | 4 | Gates/{tokens,dynamictype,contrast,a11y}.js |
| **合计** | **59** | |

另：`lock27-preview/v7/TOKENS.md` 更新（不在 ios27 仓内）。

> 仓库中另有并行的功能改动（`AppModel.swift`、`Destinations.swift`、`Router.swift`、新增 Door/Records 页面等），不属于本次设计迁移。

---

## 6. 剩余豁免清单

1. **Engine 层**：按任务约定不参与设计迁移；Engine 内的泛型 `T.self` 不是旧令牌。
2. **`Design/Tokens.swift`**：保留旧 `T./Ink./Signal./State.` 的定义，作为旧组件壳与 `contrast.js` 旧色对断言的兼容层；**全仓已无调用点**。后续可整体删除。
3. **`Design/Components/*` 旧组件壳**：`Panel/Inset/SectionLabel/Reading/FieldRow/ReadingGrid/StateDot/StatusLine/PrimaryAction/SecondaryAction/EmptyPanel/BusyRow/ChipRow/Dial` 仍存在，但内部已全部改用 V 令牌；`Features/**` 已无调用（LedgerRow 的最后 2 处已换 `VLedgerRow`）。保留是为了不打断并行分支的编译面。
4. **`Design/V7/V7Tokens.swift`**：tokens/dynamictype 的显式豁免——它是唯一允许出现 `V.F.sans(<数字>)` 与 `V.C.rgb` 的地方；数值字号只在这里定义，并经 `VFont` + `@ScaledMetric` 缩放。
5. **`Design/Components/Dial.swift`**：Canvas 几何计算（刻度长度/角度）沿用既有 tokens 豁免，不是样式令牌。
6. **低对比原色**：`#48525B / #6D6D6D / #5D5D62 / #4E4E50` 已从 V7 色板移除并列入 `contrast.js` 黑名单；旧 `Design/Tokens.swift` 里没有这些值。
7. **脚注 16.5px**：TOKENS.md 自身 px/pt 混用（16.5px vs 16.7pt），本轮保留 `V.F.footnote = 13pt` 的可读档，不把全仓次要文本放大到接近正文；该项列为待设计裁决，不计入已落地的 18 条。
8. **V7 固定像素默认值**：默认字号是参考图像素值，靠 `@ScaledMetric` 在大字档缩放；若未来新增页面直接写 `V.F.sans(数字)`，`tokens.js` 与 `dynamictype.js` 会同时判失败。

---

## 7. 未验证 / 风险

- 本机无 Swift 编译器（`swiftc` 不存在），所有验证是 tree-sitter 语法树 + 括号/字符串平衡 + 静态类型名/令牌引用扫描；未在模拟器/真机渲染。
- `VFont` 的 Dynamic Type 依赖 SwiftUI `@ScaledMetric` 的运行时行为；默认字号与参考图一致，但极端辅助字号下的换行/截断未做像素回归。
- 旧组件壳虽然内部已 V 化，但它们的布局语言仍是旧的（例如旧 `Reading` 的 size 参数）；Features 已不依赖它们，后续可整体删除。
- 并行分支的 `AppModel.swift` 改动未纳入本次设计 diff，验收时以本报告 §4 的 59 个文件为准。
