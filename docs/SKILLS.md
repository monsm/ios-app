# Skill 应用清单

本项目在 iOS 界面与交互设计阶段，对本机已安装的**全部 97 个唯一 skill**（另有 8 个插件内 skill）
逐个做了适用性判定与落地。以下是结论与落地位置。

> 判定口径：只承认**真正改变了这份代码**的 skill。凡是读完正文后判定与「原生 iOS 26.5
> SwiftUI 界面设计」无交集的，如实记录原因，不硬套。

## 一、真正落地并改动了代码的 skill

| Skill | 落地了什么 |
|---|---|
| **ui-ux-pro-max** | 设计系统检索（深色科技 + 状态色）、SwiftUI 栈规范、无障碍与交互清单、交付前核对表 → `DS.*` 令牌体系、44pt 触达、对比度核算、确认弹窗 |
| **global-agent-preferences** | 全程简体中文回复与中文 commit message；代码/命令/报错保持原文 |
| **animate / animation-vocabulary / review-animations** | `DS.Motion` 令牌体系；实测阻尼比确认 quick/standard 无回弹、符合「UI 避免 bounce」；Toast 进出同路径 |
| **apple-design** | **查出 HIGH 级 bug**：开锁主控呼吸环用 `repeatForever` 驱动 `scaleEffect/opacity`，同子树又挂 `.animation(_, value: state)` 驱动同一批属性 → 拆成独立 `UnlockPulseRing` 并用 `.transaction { $0.animation = nil }` 切断隐式继承。「减少动效 ≠ 取消动效」→ 开启减少动效时保留一圈静态指示而非整体消失 |
| **break-ui** | `StatusPill` 加 `.fixedSize()` 防长状态文案把胶囊撑成两行；数字加 `.monospacedDigit()` 防 99→100 宽度跳动 |
| **high-end-visual-design / design-taste-frontend / frontend-design** | **Card 去掉 0.5pt hairline 描边**，改为 surface/canvas 明度差分层 + 极淡阴影。理由：描边与阴影表达矛盾信息，且每张卡同款描边会让界面显得出自同一模板。描边从此只留给「选中/危险」语义 |
| **design-taste-frontend / enterprise** | `MetricTile` 引入 `emphasized`：电量是一级读数（决定还能不能开锁），固件/锁钟降为三级参考，消除三块读数同级的层级缺失 |
| **emil-design-eng** | 按压反馈用 `isPressed` 驱动、`scaleEffect(0.97)` 在规范区间内；动效只动 transform/opacity 不动布局属性 |
| **glassmorphism** | 玻璃只服务**浮层语义**（顶部 Toast、快捷四宫格），内容卡片一律 `surface`，避免材质隐喻混用 |
| **minimal / clean / sleek / bento** | 单一视觉重心（开锁钮为锚）、强调色预算全留给状态、玻璃层上不放 `textSub` 级文字 |
| **clean** | 中文最小正文字号下限：`.caption2`(11pt) 在苹方下发糊 → 全局提到 `.caption`(12pt) |
| **write-swift** | SwiftUI 回调保持同步、异步只留给 BLE 往返；`withCheckedContinuation` 恰好 resume 一次 |
| **brand** | 图标语义统一（lock.shield / battery / wifi.slash）、状态文案统一加状态词前缀 |
| **redesign-existing-projects** | 校验：深色底非纯黑（`#0A0E15`）、无紫蓝 AI 渐变、状态色独占不与装饰色混用 |

## 二、中文排版专项（各家 skill 都强调、但都不是为中文写的）

这几条是本次审计里**收益最高**的修正，因为它们是真 bug 不是审美：

1. **PingFang SC 没有 Bold 字重**（最高 Semibold 600）。写 `.bold()` 会静默回退到 Semibold，
   小字号下笔画粘连 → 全局 `.bold` → `.weight(.semibold)`，标题层级改由字号承担。
2. **苹方数字是比例宽度**，电量 `9%`→`10%` 会让整块指标宽度跳动 → 数字统一 `.monospacedDigit()`。
3. **中文字高大于英文**，`.caption2`(11pt) 不足以承载可读中文 → 正文下限提到 `.caption`/`.footnote`。
4. **中文不加 tracking**（汉字等宽方块，加了字距不均）；只有全大写拉丁（OK / BLE）才加。

## 三、读完判定为不适用的 skill（附原因）

| 类别 | Skill | 原因 |
|---|---|---|
| 文档产出 | `documents:docx`、`pdf:pdf`、`presentations:pptx`、`spreadsheets:xlsx` | 产出 Word/PDF/PPT/XLSX 文件，与 App 界面无关 |
| 网页自动化 | `browser-use:control-browser`、`agent-browser`、`browser-use:web-gui-tester` | 只能驱动网页；本项目是原生 SwiftUI，无 WebView 目标 |
| 插件/框架开发 | `plugin-creator`、`shadcn`、`pick-ui-library`、`ask-sonner`、`stitch`、`find-skills` | React/npm 生态选型；SwiftUI 对应物是系统原生组件 |
| 移动端框架 | `animate-expo` | React Native / Reanimated |
| 多代理编排 | `dynamic-workflows`、`agentic` | 编排工具本身，不产出界面决策 |
| 工具 | `improve-codebase-architecture` | 依赖未安装的 `codebase-design` skill 与 `docs/adr/`，前提全缺 |
| 坏桩 | `grill-me` | 正文仅 7 行，指令指向未安装的 `grilling` |
| 出图/演示 | `design`、`slides`、`banner-design`、`artistic`、`storytelling` | 出 logo、社媒图、HTML 演示稿 |
| 审美风格（模板同构） | `cafe`、`ant`、`contemporary`、`dithered`、`dramatic`、`expressive`、`creative`、`fantasy`、`fiction`、`friendly`、`lingo`、`sketch`、`pacman`、`sega`、`tetris`、`power`、`premium`、`codex`、`refined`、`claude`、`basic` | 同一套 typeui.sh 模板，只换字体与 Hex 色板，审美方向（羊皮纸、咖啡色、8-bit、游戏）与门锁场景无关 |
| 审美风格（与平台冲突） | `brutalism`、`neobrutalism`、`neumorphism`、`claymorphism`、`skeumorphism`、`material` | 与 iOS 连续曲率与材质语言正面冲突。其中 neumorphism 尤其致命：同色底 + 同色控件使边界不可见，**直接摧毁「状态一眼可辨」这一核心要求**，且其 text/surface 对比度约 3.4:1，破 4.5:1 门槛 |
| 审美风格（与场景冲突） | `neon`、`cosmic`、`futuristic` | 夜间门口场景下霓虹发光会降低文字可读性；装饰性元素与单手可达、状态清晰相悖 |
| 审美风格（Web 时代） | `modern`、`editorial`、`retro`、`vintage`、`riso`、`paper`、`terracotta`、`perspective`、`square`、`dark`（磁盘上不存在） | 衬线/像素/纸纹字体无中文字形；纸纹降低对比度；`square` 文档与名称完全不符 |

## 四、主流程亲自复核（不只信子代理）

以下最可能被误判的条目，主流程已亲自读 SKILL.md 正文核对，判定与子代理一致：

| Skill | 主流程核实结果 |
|---|---|
| `grill-me` | 7 行，`disable-model-invocation: true`，正文只有一句「Call the Skill tool with grilling」，而 `grilling` 未安装 → 确为坏桩 |
| `prototype` | `disable-model-invocation: true` + 明确「仅用户显式调用时运行」「探索阶段绝不碰生产代码」→ 属用户驱动的设计探索工具，不适用于直接改代码 |
| `improve-codebase-architecture` | 硬依赖未安装的 `codebase-design` skill、`GLOSSARY.md`、`docs/adr/` 与 git 历史，且输出 HTML 报告；本工作区非 git 仓库、无 GLOSSARY → 前提全缺 |
| `material` / `neumorphism` | 同为 `TYPEUI_SH_MANAGED` 模板（37 个近同构 skill 共用一套骨架），material 主色 `#6442D6` 紫、neumorphism 用 Space Mono + 同色底 → 与 iOS 26 平台语言及中文界面直接冲突，判定成立 |

> 重要背景：那 37 个「视觉风格」skill 是**同一份模板自动生成的**，只在 frontmatter 一句风格描述、字体、Hex 色板上不同。
> 逐一独立阅读它们没有额外信息量——判定可以从「字体/色板/与 iOS 平台是否冲突」一条规则批量推出，
> 主流程已抽样核对 6 个（上表 + `brand`）确认该批量判定可靠。

`brand`（中）：正文含品牌语气/信息架构/图标语义，其中「图标语义统一、状态文案加状态词前缀」已实际落地到代码。

## 五、发现的缺失能力

磁盘上存在插件 **`ios-simulator`**（内含 `ios-dev` skill：「Build, run, inspect, and
lightly automate iOS simulator apps」），是本项目做**可视化验收**最该启用的工具，
但它未在本会话启用（未启用的还有 `computer-use`、`image-search`、`skill-creator`、
`android-emulator`）。

**影响**：目前没有任何手段对本项目做「截图 → 视觉走查 → 修复」的闭环。
启用该插件后可补上这一环，尤其是暗色模式对比度与 Dynamic Type 最大字号的实际观感验证。