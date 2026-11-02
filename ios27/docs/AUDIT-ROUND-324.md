# AUDIT-ROUND-324 · 第 324 轮：把 40 个页面从自造容器换成系统容器

> 本轮不是又一轮找缺陷，是**执行**：把第 323 轮之前四份审计（布局 / 交互 / 信息架构 / 液态玻璃）的
> 结论落成代码。共 202 条（去重前），7 轮实施，改动 56 个文件 / +1488 −267 行。

## 1. 起点：四份审计报告

| 报告 | 结论 | 条目 |
|---|---|---|
| 布局 | 56 个页面里 4 个滚不动或溢出 | P0 5 / P1 8 / P2 15 |
| 交互 | 控件不是"全是装饰"，是"做了但用户看不到" | P0 2 / P1 12 / P2 8 |
| 信息架构 | 每个页面都在展示"同一批读数的不同排版" | 冗余 62 / 原始值 34 / 装饰卡 6 / 死字段 9 |
| 液态玻璃 | 只有底部 5 个 Tab 有玻璃，根因是**三道自锁** | 自造 85 → 可替换 23 / 保留 34 / 死代码 18 |

## 2. 「全换系统」的正确方向

用户的要求是「全换系统」，而液态玻璃审计的结论是**反直觉**的：

> 底部只有 5 个 Tab 有玻璃，不是因为"缺玻璃"，是因为
> ① `Gates/glass.js` 明令内容层不许出现 `glassEffect`（这也正是 HIG 的要求）
> ② 4 个 Tab 根把导航栏整个关掉了 ⇒ 系统导航栏那层玻璃根本不存在
> ③ 全仓 0 处 `.searchable` / `.presentationDetents` / `List` / `.buttonStyle(.glass)`

**所以方向不是"给卡片刷玻璃"，而是"内容层换系统控件，让系统在功能层自己加玻璃"。**

## 3. 组件层：改 4 个文件，覆盖约 500 处调用

| 组件 | 现在是什么 | 覆盖 |
|---|---|---|
| `VCard` | `GroupBox`（`.warm` 外层补底色、`.mini` 保留自绘） | 251 |
| `VActionButton` | `.buttonStyle(.glassProminent)` + `.tint()` | 61 |
| `VOutlineButton` | `GlassButtonStyle()` | 77 |
| `VValueRow` | `LabeledContent` | 38 |
| 4 套自绘分割线 | 统一 `Divider()` | 154 |

## 4. 页面层：53 个页面里 40 个换成 `List`

配套两个行修饰符（`Features/Shared/V7Extras.swift`）：

```swift
func plainRow()                       // .insetGrouped 用（系统已给左右留白）
func cardRow(gutter: V.S.pageGutter)  // .plain 用（系统不给留白，卡片必须自己补）
func headerRow(gutter: V.S.pageGutter)// 页头/横幅/芯片行
```

**为什么需要三个**：两种 `listStyle` 的 gutter 语义不同。第 4~6 轮曾把 20 个页面写成
`.plain` + `plainRow()` ⇒ 卡片贴屏幕边；页头没补 ⇒ 页头比卡片更靠边。这两类都是**真回归**，
由新写的 `check3.mjs` 抓出（14 → 0）。

## 5. 读数层：`Engine/Reading.swift`

终结「同一个数在不同页各有各的写法」。审计实测：电量 9 处、连接 8 处、固件 7 处、锁钟 6 处、模式 5 处。
最刺眼的是**门页同一页两个电量**（芯片直读 `lock.battery`、正文走 `BatteryCare.displayPct`，两条取值规则不同）。

## 6. 本轮抓到并修掉的两个「会回归的 P0」

| 缺陷 | 说明 |
|---|---|
| **`Reading.lockClock` 把协议秒当毫秒** | 会显示 1970-01-07、偏差约 −57 年。`531,310,986` 正是 `SyncTimeScreen` 注释里那条用户实测过的 `531260264 秒` —— **同一个 bug 修过一次，这一版差点重新引入**。由实施者在接线前用真实数值验证拦下 |
| **`LockGateScreen` 仍是「一出现就聚焦」** | 第 2 轮只改了 `UnlockGateScreen`，这一屏漏了。L1（冷启动第一屏不能滚）的另一半 |

## 7. 删掉的死代码

| 项 | 说明 |
|---|---|
| `Design/Tokens.swift`（202 行） | 旧令牌层，全仓 0 消费者；连带改 5 个闸门的豁免名单 |
| `Design/Components/` 19 个类型 | `Dial`/`LedgerRow`/`Panel`/`Reading` 等零引用；目录 9 → 3 个文件 |
| 3 个已合并页面 | `SafeModeScreen`/`TailgateScreen`/`SyncTimeScreen`（六页并两页） |
| 2 张纯装饰卡 | `KeysScreen`「本机安全」、`RecordsScreen` 三层同心圆 |
| 5 个孤儿令牌 | `heroGlyph56` / `V.Metric.medal` / `S.gapXL` 等 |

## 8. 新增 5 个检查器（无编译器环境下的替代手段）

| 检查器 | 查什么 | 为什么需要 |
|---|---|---|
| `check.mjs` | 括号/引号/冲突标记/占位符 | 最低保障 |
| `check2.mjs` | 同名顶层类型 / `.dest()` 悬空 / sheet 内容类型 | 删类型、改路由后最容易踩的编译错 |
| `check3.mjs` | 页头 vs 卡片左右基准线 / 贴边 / 双缩进 | List 化后最容易出的视觉回归 |
| `check4.mjs` | 令牌引用可解析 / 无零引用令牌 | `allgates` 的 tokens 闸门只查 `V.F`/`V.M`，有盲区 |
| `Gates/allgates.js` | 项目自带 23 道 | 既有闸门 |

**修了 2 处闸门假阳性**：`crosprivate.js` 把 `X.name` 限定访问、以及 `} header: {`（Section 语法糖）
都当成「跨文件访问 private 成员」。

## 9. 明确「不做」的三项（附理由）

| 项 | 为什么不做 |
|---|---|
| 13 个纯 `ScrollView` 页面 | 全是「sheet 内套 List 会抢 sheet 滚动」或「内容 ≤ 21 行」，换是负收益 |
| `KeyCreateParts` 四步表单 Section 化 | 四步表单不是"列表"——摊成 Section 行等于把「一次操作」拆成「一堆字段」；`Group{}.plainRow()` 本身就是「一步 = 一整块」的表达，架构在抵抗。实测会把 Section 每行的内边距/分隔线全抹掉，已完整回退，净改动 0 行 |
| 内容层刷 `.glassEffect()` | HIG *Don't use Liquid Glass in the content layer* + `Gates/glass.js` 明令禁止 |

## 10. 方法论（本轮沉淀）

| 判据 | 出处 |
|---|---|
| **改组件内部一次，比改 500 个调用点安全** —— 但也意味着一次改错影响 500 处，必须先证明调用点集合 | 本轮 §3 |
| **容器的"留白语义"必须显式化** —— `.plain` 与 `.insetGrouped` 各一套，混用就贴边或双缩进；用 `cardRow`/`headerRow` 把语义写进修饰符名 | 本轮 §4 |
| **「一值一处」要在动手前先建层** —— 否则 9 处电量会各自演进成 9 套口径 | 本轮 §5 |
| **接线前先用真实数值验证新写的换算函数** —— 协议秒/毫秒这类单位错误静态检查查不出来，但代一个真实值就能看出来 | 本轮 §6 |
| **审计报告的结论也可能是错的** —— D6「`AXSettings.holdConfirm` 零调用」实测有 2 处真实调用，删了编译失败；多锁芯片不是"重复展示"而是"别的锁的独立信息" | 本轮 §5 / §7 |

## 11. 遗留：只能在 Xcode 验证

**本轮一行都没编译过**（开发机是 Windows，无 Xcode / iOS SDK）。三处 API 需云端编译确认：

| API | 若报错的最小回滚 |
|---|---|
| `.buttonStyle(.glassProminent)` | 改 `.buttonStyle(.borderedProminent)` |
| `GlassButtonStyle()` | 改 `.buttonStyle(.bordered)` |
| `GroupBox` | 回滚 `VCard` 一个 struct（注意：圆角会从 27 变成系统值，视觉会变） |

## 12. 云端编译结果（这才是唯一真验证）

本地 5 个检查器全绿之后推送，云端 `xcode-27` 第一次编译**红了** —— 10 个 error，全在新写的 `Reading.swift` 加一处调用点笔误：

| error | 根因 |
|---|---|
| `Reading.swift:48` `connectedMAC` 从 nonisolated 上下文引用 | `LockService` 是 `@MainActor` 类 |
| `Reading.swift:55/62/63` 调 `savedRSSI`/`level`/`levelWord` | `LinkSenseModel` 是 `@MainActor` 类 |
| `DeviceInfoScreen.swift:34` `batteryCard` 当属性用 | 它是 `func`，漏了 `()` |

**这两类都是同一个错误**：我写了一个「值格式化层」，却没核对它读的那些状态的 actor 归属。

### 修法（刻意最小）

只给真正碰 `@MainActor` 状态的三个函数加标注：`link(_:)` / `signal(_:)` / `rssiText(_:)`。
**不给整个 enum 加** `@MainActor` —— `Value` 是纯数据类型，不该被 actor 绑定；
`battery` / `firmware` / `lockClock` / `clockDrift` / `lockMode` 读的是 `DB`（`@unchecked Sendable` 单例），
保持 nonisolated，任何地方都能调。

**调用点零改动**：所有消费者都是 SwiftUI View，`View` 的 `body` 本身就是 `@MainActor`，所以调用发生在主线程、不需要 `await`。这也是编译器只报那三个访问器、不报它们调用点的原因。

### 第二次编译（`aa87e487`）

```
errors=0  build_ok=1  archive_ok=1  warnings=1（AppIntents 元数据，与本仓无关）
golden: test_ok=1  test_failed=0  tests_executed=82
BUILD SUCCEEDED / ARCHIVE SUCCEEDED
```

### 方法论

**「本地检查器全绿」不等于「能编译」。** 本轮 5 个检查器证明的是括号、符号解析、布局一致性 ——
它们**看不见 actor isolation**，也看不见「func 当属性用」。这类错误只有真编译器能抓。

判据：**凡是新增一个「跨层读取状态」的抽象（本例的 Reading），必须先核对被读状态的 actor 归属，
再写第一行代码**；否则会在云端一次性爆出十条同类 error，而本地永远看不到。
