# docs/redesign 索引

> ## ⚠️ 这个目录里有两代文档，先看清楚你在读哪一代
>
> | 代 | 文档 | 状态 |
> |---|---|---|
> | **一代**（v10 / BDF 三棱柱）| `BDF-*` `PART0–7` `DECISIONS` `MASTER-PLAN` `PRISM-*` `AUDIT-*` `EVIDENCE-*` `M5-SHAPE-AUDIT` `PAGE-ADAPT-LEDGER` `LOCK-3D-RESEARCH` | **已放弃**（见下）|
> | **二代**（现行）| `SINGLE-CONSOLE` `DESIGN-DECISIONS` `DEAD-SURFACE` `PRE-RELEASE-CHECK` `CI-VS-GATES` `DESIGN-SYSTEM-V2` `KNOWN-GAP-BACKUP-FILES` `SECTION-MIGRATION-LESSON` `REFACTOR-STATUS` `FEATURE-BRAINSTORM` | **现行** |
>
> **一代为什么被放弃**：三棱柱要求用户先理解一个隐喻才能开门。
> 产品方原话：「放弃吧 只留下一个界面，删掉门面和仪表，相关功能合并进剩余的」。
> 一代文档**保留不删** —— 里面的 76 项功能清单、闸门矩阵、对抗审核记录仍然是有效参考，
> 只是「三棱柱/门面」这个形态被否掉了。
>
> **要干活，从下面「二代」那一节开始读。**

---

## 二代（现行）：从这里开始

| 顺序 | 文件 | 读它是为了 |
|---|---|---|
| 1 | **`SINGLE-CONSOLE.md`** | 现在的界面是什么结构、为什么这么定（设计契约）|
| 2 | **`DESIGN-DECISIONS.md`** | 22 条决定的**依据、取舍、以及什么时候该推翻** |
| 3 | **`DEAD-SURFACE.md`** | 零调用 API 的**处置总表**（该接/不接/为什么）|
| 4 | **`PRE-RELEASE-CHECK.md`** | 每个工具的有效范围 + 各轮审计结论 + **哪些结论必须由人验证** |
| 5 | **`MANUAL-ACCEPTANCE.md`** | **人工验收表**：哪 12 件事没有任何机器能替你确认，怎么验、什么算过 |
| 6 | **`CI-VS-GATES.md`** | 闸门全绿 ≠ 能编译。一次误报的完整记录 |
| 7 | `DESIGN-SYSTEM-V2.md` | 26 个组件、令牌、Dynamic Type 两条口径 |
| — | `KNOWN-GAP-BACKUP-FILES.md` | 一个具体缺口的实现记录（含仍未验证的部分）|
| — | `SECTION-MIGRATION-LESSON.md` | 三个坑：`Section` 带 header/footer、CRLF、正则漏匹配 |
| — | `REFACTOR-STATUS.md` | 重构进度与诚实清单（哪些没做完）|
| — | `FEATURE-BRAINSTORM.md` | 15 条功能点的「价值 ÷ 成本」排序 |

**二代的读法建议**：先读 `SINGLE-CONSOLE` 知道屏幕长什么样，
再读 `DESIGN-DECISIONS` 知道为什么，然后 `DEAD-SURFACE` 知道哪些坑不用再踩。

**最该信的一句**（来自 `PRE-RELEASE-CHECK`）：
> 视觉观感、真机手感、动画效果、协议行为 —— **这四件事本会话没有任何一项被验证过**。
> 所有判断来自代码结构、状态机推演、数值计算，以及 CI 的编译结论。

---

# 附：v10「一扇门」重设计 · 交付包索引（一代，已放弃）

> **给实施 AI 的第一句话**：这套文档是**可执行规格**，不是灵感稿。
> 每个数值都是验收值，每条「不许」都有反例。遇到歧义先查裁决表，再查 `DECISIONS.md`。

**改造对象**：iOS 全原生 SwiftUI App（`ios-app/`，iOS 26.5+）与 Android Compose App（`ios-app/android-app/`）。
**设计来源**：`ios-app/docs/preview/v10.html`（单文件原型）+ `ios-app/docs/preview/uiux-v3.data.js`（76 项功能清单）。

---

## 一分钟了解方案的五个结论

1. **门是封面层，不是第 5 个 Tab。** 4 个 Tab（设备/凭证/记录/设置）与 76 个目的地的语义一个字都不改；
   v10 的「全部」Tab 改成 **App Index**（sheet 级目录）。
2. **开锁是安全动作，进门是导航动作，两者分开。** 按住锁体 = 开锁；左缘右拖 = 进门（不改锁状态）。
3. **门面上的话必须是真的。** 协议里没有「在线」「反锁状态」「门磁」——v10 的三句文案必须改写或删除（D13）。
4. **Android 不做门面**，保留暗色 + 暖金基调；它做的是同一套**材质语言** + 现有功能 UI 重做 + 工程底座（D11/D14）。
5. **有闸门，而且有一道基线本来就是红的。** 动手前先修基线（`uicoverage` 的两条），再开工（PART7 §2）。

---

## 文件清单与阅读顺序

| 顺序 | 文件 | 页数级 | 读它是为了 |
|---|---|---|---|
| 0 | **`README.md`**（本文件） | 短 | 先建立全局认识 |
| 1 | `DECISIONS.md` | 长 | **D1–D15 全部 LOCKED，违反即返工** |
| 2 | `PART0-OVERVIEW.md` | 中 | 设计总纲 + **26 条补充决策** + 术语表 + **§6 令牌真实值附录** |
| 3 | `MASTER-PLAN.md` | 中 | 分层、阶段、速查表、12 条歧义裁决 |
| 4 | `PART1-LOCKFACE.md` | 长 | **门面层规格（最高风险，先做这个）** |
| 5 | `PART4-MOTION.md` | 中 | 逐帧时间轴 + 曲线词典（两端共用数值） |
| 6 | `PART2-NAV-IA.md` | 中 | 4 Tab 根屏、76 项分层、App Index、尺寸断点 |
| 7 | `PART3-COMPONENTS.md` | 中 | 表面预算、组件台账、**圆盘装饰层 7→3** |
| 8 | `PART5-DESTINATIONS.md` | 长 | **76 行逐条改造表**（干活时当清单打勾） |
| 9 | `PART7-ACCEPTANCE.md` | 长 | **闸门矩阵、迁移 10 步、12 条风险、DoD** |
| 10 | `PART6-ANDROID.md` | 中 | Android 侧（**无门面**，暗色暖金） |
| — | `EVIDENCE-DOCS.md` | 很长 | 76 项功能清单原文 + **禁区清单** + 34 个闸门口径 |
| — | `EVIDENCE-ANDROID.md` | 中 | Android 现状与厂商 APK 基线 |
| — | `EVIDENCE-IOS.md` | 中 | iOS UI 结构清单（grep 级） |
| — | `_gen/` | — | 生成 `PART5` 用的中间产物（可重跑对比） |
| — | `AUDIT-A/B/C-*.md` | 长 | **三轮对抗审核报告**（查出 11 处错误，更正记录见 `DECISIONS.md` 末章） |
| — | `AUDIT-A/B/C-*.md` | 三份**对抗审核**记录（含对方案自身的更正） |

**不要跳读 1 和 3**：这两份是「为什么这么做」的答案，跳过它们会在实施时自由发挥，那正是返工的来源。

---

## 15 条决策速览（全文见 `DECISIONS.md`）

| # | 决策 | 一句话 |
|---|---|---|
| D1 | 门是封面层，不是第 5 个 Tab | 保护 `Route` / `guestBlocked` / 深链不被破坏 |
| D2 | 开锁与进门分开 | 轻点不再等于进门，避免把安全动作降级成误触 |
| D3 | 充能是连续物理量 | 由一个 `p` 驱动全部视觉 |
| D4 | 视觉令牌只增不改，走装饰层 | 不新增语义色，不碰 397 条对比度断言 |
| D5 | 动效挂既有双闸 | `reduceMotion` + 低电量 → calm |
| D6 | 门面 4 种皮肤 | 木/金属/深色玻璃/磨砂，几何逐字相同 |
| D7 | 「全部」= App Index，76 项由 destmap 生成 | 不许手写数组 |
| D8 | 手势优先级表 | 关门/返回/Tab 依次判定，不并行 |
| D9 | 两端数值同源 | 来源就是 `App/Core/DesignSystem.swift`（**不新建 tokens.json**） |
| D10 | 本轮不做的事 | 8 条（在线功能/字体/协议/位图…） |
| D11 | **Android 不做门面** | 只共享视觉语言 + 重做现有 UI |
| D12 | 门锁体直径尊重 `kf_dial_size` | 否则「圆盘大小」设置变假开关 |
| D13 | 门面不得声称锁端不存在的状态 | 删「门磁未合上」，改写「在线」「已锁定」 |
| D14 | Android 保留暗色 + 暖金 | 不改成 iOS 的暖白 |
| D15 | **排版七条** | v10 的 26/52/14 一律不照抄：16pt 边距 / 44-60 行高 / 22pt 圆角 / 34pt semibold / 13pt 提示 |

---

## 开工前必须做的三件事

1. **修基线红**：`cd ios-app && node tools/uicoverage.js` 当前 **判失败**
   （`ShareToAndroidView` 未挂缝；`RecordsTimeline.swift:450` 绕过漏斗）。先各修一行（PART7 §2.1）。
2. **确认环境**：闸门在 `ios-app/` 下跑（不是仓库根）；小程序测试在 `miniprogram-app/tests/run.js`。
3. **认清约束**：UI 必须走 VK 语法层；自绘容器预算 111 **只许减**；`budget.json` **不许自己改**。

---

## 文档自身的边界（诚实声明）

- 本方案**不含源码改动**；所有源码由实施 AI 写。
- 有几处结论需要**真机复核**，已在 `PART7-ACCEPTANCE.md` §7 逐条列出
  （最关键的三个：门面透视强度的最终值、iPhone SE 上的性能、门面噪声 `Canvas` 的光栅化开销）。
- v10 原型本身有两处技术缺陷已在方案中修正：
  ① `v10.html:449` 在 `pointermove` 里对 `open` 调 `classList.remove`（非法且会中断手势脚本）；
  ② 它的 76 项内联数组与 `uiux-v3.data.js` 不同源（本方案规定由 `tools/destmap.js` 生成）。
- 闸门基线数字（397 条对比度断言、111 自绘预算、76 目的地、35 个脚本）均为 **2026-10-18 实测**；
  文档里的旧数字（如 `DESIGN-SPEC.md:106` 的 42 条）已过期，**以实跑为准**。

---

## 一句话交接

先读 `DECISIONS.md` 与 `MASTER-PLAN.md`，再按 `PART7-ACCEPTANCE.md` §3 的 10 步走；
每一步跑完闸门再进下一步。**闸门不让过的写法就是错的写法。**