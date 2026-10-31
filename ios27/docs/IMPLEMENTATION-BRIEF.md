# ios27 · 实施须知（给所有 AI 的同一份）

先读 `docs/DESIGN-CONTRACT.md`。它是唯一事实来源，本文件只讲**怎么落地**。

## 1. 目录与写作用域

```
ios27/App/Design/Tokens.swift            设计令牌（唯一来源，**不许改**）
ios27/App/Design/Components/*.swift      组件库（可新增，**不许改已有语义**）
ios27/App/Shell/*.swift                  Router / Shell / AppModel / Destinations
ios27/App/Features/<域>/*.swift          各域页面（各人只写自己的域）
ios27/Gates/*.js                        机器闸门
ios27/DesignLab/                        1:1 视觉镜像 + 截图
```

**只写你被分配的那个 `Features/<域>` 目录。** 需要新的共享组件 → 在你自己目录里写
`private struct`，不要动 `Design/Components`（那是 lead 的地盘，会冲突）。

## 2. 已存在的 API（直接用，不要重新发明）

### 令牌
`T.S.{xxs,xs,s,m,l,xl,xxl,gutter}` · `T.R.{plate,inset,control,pill}` ·
`T.Hit.min` · `T.Stroke.{hair,focus}` · `T.Icon.{s,m,l,xl}` ·
`T.F.{display(),section,body,bodyStrong,caption,unit,reading(),stamp}` ·
`T.M.{snap,move,sweep,exit,tickStep}`

### 颜色
`Ink.{paper,plate,plateAlt,hairline,ink,inkSub,inkFaint}`
`Signal.{base,on,wash}` · `State.{attention,critical,ok}`

### 组件（`App/Design/Components/`）
| 名字 | 签名 | 用途 |
|---|---|---|
| `Panel` | `Panel { content }` | 内容面板（唯一容器） |
| `Inset` | `Inset { content }` | 面板内的凹槽块 |
| `SectionLabel` | `SectionLabel(text:trailing:)` | 小节标题 |
| `CanvasBackground` | `CanvasBackground()` | 页面底（每页都用） |
| `Reading` | `Reading(value:unit:size:weight:tint:animated:)` | 定宽读数 |
| `FieldRow` | `FieldRow(label:value:unit:tint:mono:)` | 左标签右读数 |
| `ReadingGrid` | `ReadingGrid(items:columns:)`，item=`.init(label:value:unit:tint:)` | 读数网格 |
| `Dial` | `Dial(phase:footnote:hint:enabled:action:)` + `.environment(\.dialDiameter, N)` | 刻度盘 |
| `StateDot` | `StateDot(tone:word:)` | 状态点（形状+色+词） |
| `StatusLine` | `StatusLine(tone:text:)` | 状态行 |
| `ChipRow` | `ChipRow(items:title:selection:)` | 分段 chip |
| `PrimaryAction` | `PrimaryAction(title:systemImage:busy:action:)` | 唯一主动作 |
| `SecondaryAction` | `SecondaryAction(title:systemImage:action:)` | 次级动作 |
| `EmptyPanel` | `EmptyPanel(title:message:actionTitle:systemImage:action:)` | 空态（必须给出路） |
| `BusyRow` | `BusyRow(text:)` | 加载态 |
| `LedgerRow` | `LedgerRow(entry:showDay:)` | 台账行 |
| `LedgerDayHeader` | `LedgerDayHeader(dayKey:count:)` | 日组头 |
| `Tone` | `.ok/.attention/.critical/.neutral/.live` | 语义色 |

### 数据与路由
`AppModel`：`lock: LockSummary?` · `dialPhase` · `entries: [LedgerEntry]` ·
`keys: [KeyItem]` · `members: [Member]` · `trialGuard` · `runUnlockChain()`
`Router`：`request(_ context: RouteContext)`（**唯一跳转入口**）· `select(_ slot: TabSlot)` · `consume()`
`TimeFormat`：`clock(_:)` `dayKey(_:)` `dayShort(_:)` `dayTitle(_:)` `ago(_:)`

## 3. 硬纪律（违反 = 返工）

1. **不许出现颜色/间距/圆角/字号字面量。** 一切走 `T.` / `Ink.` / `Signal.` / `State.`。
   （`Gates/tokens.js` 会扫：`Color(hex:)` 出现在 Design 之外、`.padding(20)`、`.system(size: 17)` 都红）
2. **不许在内容层用 `glassEffect`。** 玻璃只在系统控件上（系统自己会加）。
3. **同屏只有一个 `PrimaryAction` 或一处 `Signal.base` 填充。**
4. **所有 `.animation` 必须带 `value:`。**
5. **图标按钮必须有 `.accessibilityLabel`。** 触达 ≥ `T.Hit.min`。
6. **数字一律走 `Reading`（等宽 + 右对齐）**；时间一律走 `TimeFormat`。
7. **中文标题不用 `.bold()`**（苹方无 Bold，静默回退）。
8. **每个页面必须有：空态（给出路）/ 加载态（若异步）/ 错误态（若会失败）。**
9. **不许写死"暂无数据"** —— 空态要写下一步该做什么。
10. 只写你的域目录。不要改 `Design/`、`Shell/`、别人的域。

## 4. 页面骨架（照抄这个形状）

```swift
struct XxxScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                // 1) 页头（标题 + 一行状态）
                // 2) 主角（一个 Panel 或一个 Dial）
                // 3) 读数区 / 列表
                // 4) 次级入口（Panel + 分隔线行）
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("标题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { /* 最多 2 个图标按钮 */ }
    }
}
```

**子页标题**：`navigationTitle` 用 `Dest.title` 的中文。`.inline` 显示模式。
**Tab 根**：`.inline` + 页内自己的大标题（34pt），不用系统 large title（会撞玻璃）。

## 5. 交付要求

- 每个页面 1 个文件（超过 400 行就拆成 `XxxScreen.swift` + `XxxParts.swift`）。
- 文件头写 3 行注释：这屏干什么 / 数据从哪来 / 哪个交互是主动作。
- 完成后在 `ios27/docs/PROGRESS-<域>.md` 写一行：页面清单 + 未接真数据的部分。
- **诚实**：接不到真数据的字段，标 `// TODO(engine)` 并说明，不要假装已接。
