# MASTER-PLAN · v10「一扇门」重设计 · 总纲

> **给实施 AI 的第一句话**：这份方案是**可执行规格**，不是灵感稿。
> 每一个数值都是验收值，每一个"不许"都有反例。遇到歧义先查本文件 §6 裁决表，再去 DECISIONS.md。
> 本仓既有闸门（§5）**优先于本方案**——闸门不让过的写法就是错的写法。

**目标**：把 v10 原型（`ios-app/docs/preview/v10.html`）的"一扇门"设计语言，落到
iOS 原生 App（SwiftUI，iOS 26.5+）与 Android App（Kotlin + Compose）两端，
**不推翻**既有协议层、76 个目的地、36 条对比度断言与全部静态闸门。

---

## 1. 阅读顺序（按这个顺序读，别跳）

| # | 文件 | 读它是为了 |
|---|---|---|
| 1 | `DECISIONS.md` | D1–D11 全部 LOCKED，**违反即返工**。读完再动手。 |
| 2 | `PART0-OVERVIEW.md` | 设计总纲 + **26 条补充决策**（S/L/M/A/V/E 六组）+ 术语表 |
| 3 | 本文件 `MASTER-PLAN.md` | 全局分层、步骤、速查表、裁决表 |
| 4 | `EVIDENCE-IOS.md` | 现状：令牌、动效、导航、76 目的地的真实行号 |
| 5 | `EVIDENCE-DOCS.md` | 76 项功能清单（单一事实来源）、已被否决的提议、闸门清单 |
| 6 | `PART1-LOCKFACE.md` | 门面层规格（**最高风险，先做这个**） |
| 7 | `PART4-MOTION.md` | 动效逐帧总谱（两端共用数值） |
| 8 | `PART2-NAV-IA.md` | 导航与信息架构（4 Tab + App Index） |
| 9 | `PART3-COMPONENTS.md` | 组件台账与表面预算 |
| 10 | `PART5-DESTINATIONS.md` | 76 行逐条改造表（干活时当清单打勾） |
| 11 | `PART7-ACCEPTANCE.md` | 闸门矩阵、迁移顺序、DoD |
| 12 | `EVIDENCE-ANDROID.md` + `PART6-ANDROID.md` | Android 侧（D11 已限定范围） |

---

## 2. 一句话架构

`
LockFace（门面层，ZStack 最底）
   └─ MainTabs（现有 4 Tab：设备 / 凭证 / 记录 / 设置，一个字都不改语义）
         └─ 76 个 Destination 按 PART5 表逐个改造外观
App Index（76 项目录，sheet 级，非 Tab）
`
门是**封面**，不是第 5 个 Tab（D1）。锁开是**安全动作**，进门是**导航动作**，两者分开（D2）。

---

## 3. 分层与实施阶段（每层独立可验收）

| 层 | 内容 | 依赖 | 产出文件 |
|---|---|---|---|
| **L0 令牌** | **不新建来源**。iOS 的 `App/Core/DesignSystem.swift` 就是唯一来源（D9）；Android 侧 `Tokens.kt` 由现有导出产物 `ios-app/tools/layout-replica/` 转出 | 无 | DesignSystem.swift（加令牌）/ Tokens.kt |
| **L1 门面** | LockFace 容器 / 门扇 / 门面材质 / 锁体 / 中缝透光 / 展示策略 | L0 | `App/UI/LockFace/*`、`LockFaceStyle.swift`、`LockFacePolicy.swift` |
| **L2 导航** | 根 ZStack 接线、App Index、Tab 根屏改"前门页"、液态玻璃 Tab | L1 | `LockKeeperApp.swift`（受限改）、`AppIndexView.swift` |
| **L3 组件** | 表面预算清理、圆盘装饰层删并、组件台账落地、深浅双模 | L1 | 各 UI 文件 |
| **L4 目的地** | 76 行逐条改造（PART5） | L2+L3 | 各 UI 文件 |
| **L5 Android** | Compose 侧视觉语言实现（**无门面**）+ 现有功能重做 + 工程底座 | L0 | `android-app/...` |

**顺序不可颠倒**：L0 没做就改 L3，令牌会散落成字面量（本仓已有先例：页面各自写死颜色）。

---

## 4. 关键数值速查（两端必须一致；详细规格见 PART1/PART4）

| 量 | 值 | 出处 |
|---|---|---|
| 锁体直径 | `min(240, screenW * 0.61)` pt | PART1 §2 |
| 锁体中心 Y | 屏高 46% | PART1 §2 |
| 玻璃面内缩 / 凹槽外扩 | 8pt / 8pt | PART1 §2 |
| 字形尺寸 | 60pt（渐变填充，**非纯白**） | PART1 §2/§3 |
| 中缝宽度 | 3pt（左暗右亮，不对称） | PART1 §3.2 |
| 门板厚度边 | 16pt | PART1 §2 |
| 开门角度 | ±106° | PART1 §4 |
| 门转动 | 820ms，曲线 `(.22,.76,.03,1)`，t=+340ms 启动 | PART4 |
| 中缝透光 | 420ms，**先于**门转动 | PART4 |
| App 层入 | opacity 460ms + scale `.986→1` 700ms，delay 140ms | PART4 |
| 锁体按压反馈 | 100ms，`scale(.972)` | PART4 |
| 字形换态 | 260ms 交叉淡入 + `scale .9→1` | PART4 |
| 充能回零 | 180ms | PART4 |
| 关门全程 | 780ms 尾段 | PART4 |
| 推门而入阈值 | 左缘 24pt 带内右拖 ≥72pt | D2/PART1 §5 |
| 关门阈值 | 左缘 24pt 带内右拖 ≥96pt | D8 |
| 门面重现间隔 | 300s（两端同值） | PART1 §7 |
| 触达 | iOS 44pt / Android 48dp | DESIGN-SPEC |
| 标题左边距 | 16pt（`DS.Space.gutter`） | D15 |
| 门面大标题 | 34pt semibold | D15 |
| 底部提示语 | 13pt | D15 |
| 列表行高 | 44 / 60（沿用既有） | D15 |
| 卡片圆角 | 22pt（`DS.Radius.card`） | D15 |
| 同屏玻璃面 | ≤3，且玻璃不叠玻璃 | MASTER.md §3.1 |

---

## 5. 闸门（改完必须跑，红了不算完成）

启动前先自己确认命令存在与通过条件（详表见 `PART7-ACCEPTANCE.md`）：

`
node tests/run.js                      # 小程序侧（25 套协议测试）
node tools/swiftcheck.js               # iOS 静态闸门（本地唯一可跑的 Swift 检查）
node tools/golden.js                   # 金标漂移
node tools/destmap.js                  # Destination 台账（76 项）
node tools/uicoverage.js               # 界面覆盖对账
node tools/sheetcover.js               # sheet/cover 规则
node tools/contrast.js                 # 36 条对比度断言
node tools/copynum.js                  # 文案中的数字写法
`
**红线**：
1. 不许改 `fixtures/golden.json`、`vendor/app/**`、协议层任何文件来"让闸门过"。
2. 新增页面必须出现在 `Destination.swift` 台账里（该文件由 `tools/destmap.js --emit` 生成，**不要手改**）。
3. 新增玻璃面**只走 `axGlass(_:)` / `axGlassCircle()` / `axGlassCapsule()`**，不许就地写 `glassEffect`。
4. 对比度断言只许增加，不许删改来适配新配色。

---

## 6. 歧义裁决表（实施时最常撞上的 12 个问题）

| 疑问 | 裁决 | 依据 |
|---|---|---|
| 门要不要占一个 Tab？ | **不占**。门是封面层 | D1 |
| v10 的「全部」Tab 怎么办？ | 做成 App Index（sheet），三处触达 | D1/D7 |
| 轻点锁体就进门可以吗？ | **不可以**。轻点=开锁动作；进门=左缘右拖 | D2 |
| 锁开失败门要不要开一条缝？ | **不要**。门一个像素都不动 | D2 |
| 门开了还要不要"门"的隐喻？ | 不要。门后是常规 iOS，Tab 就是 Tab | v10 自述 §3 |
| 能不能把 v10 的暖白加进 Palette？ | 不能。装饰层令牌，不进语义色 | D4 |
| 大角度旋转用 spring 行不行？ | 不行。106° 下 spring 会过冲，用 timingCurve | D5/PART4 |
| `rotation3DEffect` 会自动隐藏背面吗？ | **不会**。要自己叠 88°–106° 的透明度斜坡 | PART1 §11 坑 1 |
| 门面纹理能用 PNG 吗？ | 不能。用 Canvas 程序化生成（固定种子） | D4/D10 |
| 76 项清单能不能手写一份？ | 不能。由 destmap 生成 | D7 |
| Android 要照 iOS 做门吗？ | **不要**。门是 iOS 独有；Android 直接进主界面 | D11 |
| 门面能写"在线 / 已锁定 / 门磁未合上"吗？ | **不能**。协议没有这三个事实；三句文案的处置见 D13 | D13 |
| 从小组件进来要不要演门？ | **不要**，直接执行开锁。免费账号**无 App Groups**，小组件读不到数据、只是哑按钮 | D13 / CONSTRAINTS.md:22 |
| 能不能做 NFC 碰一碰进门？ | **不做**。NFC capability 在免费账号下未实测 | D13 / CONSTRAINTS.md:32 |
| 门锁体直径要不要读设置里的圆盘大小？ | **要**。否则「圆盘大小」对门外失效 = 假开关 | D12 |
| Android 要不要改成 iOS 的暖白配色？ | **不要**。Android 保留暗色 + 暖金（#E8B45C 与 v10 的暖金属同族） | D14 |
| v10 的 26pt 左边距 / 52pt 行高 / 14pt 圆角要不要照抄？ | **都不照抄**，按 D15 七条：16pt / 44 或 60 / 22pt | D15 |
| 门面标题能不能用 .bold()？ | **不能**。苹方无 Bold，会静默回退 semibold | D15 |
| Android 要不要做锁体？ | **不要做门面**；但它现有的开锁台要用 v10 的材质语言重画 | D11/D14 |
| Android 要照 iOS 做 76 页吗？ | **不要**。见 D11 的三做两不做 | D11 |
| 深色模式能不能把浅色的灰直接搬过去？ | 不能。两套独立取值 | D4/MASTER.md |

---

## 7. 交付物与写入边界

| 文件 | 作者 | 说明 |
|---|---|---|
| `DECISIONS.md` | Lead | 决策（LOCKED） |
| `MASTER-PLAN.md` | Lead | 本文件 |
| `EVIDENCE-IOS.md` / `EVIDENCE-ANDROID.md` / `EVIDENCE-DOCS.md` | 取证员 | 现状证据 |
| `PART1…PART7-*.md` | Lead + 各作者 | 分册规格 |
| 源码 | **实施 AI** | 本方案不含源码改动 |

**多 AI 并行时的写入边界**：每个 PART 的源码落点见该 PART 的"文件清单"章；
两个 AI 不得同时改同一文件（尤其 `LockKeeperApp.swift` 与 `DesignSystem.swift`，
它们是受限改文件，建议**串行**）。
