# Round 3 · 专业 iOS 27 设计重构（Native Instrument）

> 背景：用户反馈「现在的真的好丑啊，能不能做专业的 iOS 27 设计」。Round 1/2 修的是「错」（拆卡、裁字、死设置），
> 这一轮改的是「丑」——不是配色问题，是**页面骨架和排版语法**不是 iOS 的。

## 0. 结论先说

旧版不是「设计得不够花」，而是**不像 iOS**：

1. **26 个页面全部没有导航标题**：每页顶部是 34pt 自绘判断句，系统导航栏里空着。iOS 用户第一眼找不到「这是哪一页」。
2. **每张卡都是「14.5pt 灰眉标 + 21.5pt 判断句」**：小字在上、大字在下，正好是设计审查明令禁止的「kicker / eyebrow」模板。25 页 × 3–6 张卡 = 上百个同一节奏的标题块。
3. **字号整体比 HIG 大 1–2 档**：正文 19.6（HIG 17）、卡标题 21.5、按钮 12.6（比正文还小）。结果既「不精致」又「读起来累」。
4. **26pt 圆角 + 10pt 投影的浮岛卡**：一屏 5–6 张白卡浮在浅灰底上，是仪表盘模板，不是 iOS 分组列表。
5. **点线分隔**：参考图的签名细节，但在真机上像装饰性虚线，不是系统 separator。
6. **芯片是「24pt 分段环 + 两行字」**：一排 4–5 枚小仪表盘，环的填充比例与右侧数字重复表达同一件事。
7. **设置页没有图标**：iOS 设置的核心识别是「彩色圆角图标砖 + 标题 + 右侧 chevron」，旧版只有文字行。

## 1. 新方向：Native Instrument（原生仪器）

一句话：**结构交给 iOS，品牌留在数据与颜色里。**

| 维度 | 旧（V8 参考图） | 新（Round 3） |
|---|---|---|
| 页面标题 | 34pt 自绘判断句 | 系统 `navigationTitle`：根页 `.large`、子页 `.inline`；判断句降级为 20pt status 行 |
| 卡片标题 | 14.5pt 眉标 + 21.5pt 判断 | 17pt semibold 卡名 + 13pt 次级说明（层级反转） |
| 正文 | 19.6pt | 17pt（HIG Body） |
| 卡脚注 | 15.8pt | 15pt |
| 按钮 | 12.6pt | 15pt semibold |
| 卡片 | 26pt 圆角 + 10pt 投影 | 14pt 圆角、无投影（原生分组） |
| 分隔线 | 点线 | 0.5pt 实线 separator |
| 芯片 | 24pt 分段环 + 两行 | 6pt 类别色点 + 单行「标签 值」，选中强调色填充 |
| 设置行 | 纯文字 + chevron | 30pt SF Symbol 圆角图标砖 + 标题 + 详情 + chevron |
| 页间距 | 卡间 11pt、卡内 20.6pt | 卡间 16pt、卡内 16pt |

保留的品牌资产：强调蓝 `#0558B8`、数据五色（密码/指纹/临时码/手机钥匙/告警）、英雄环与仪表图形、判断句文案本身。

## 2. 代码落点（全部在共享层，26 页自动继承）

| 文件 | 改动 |
|---|---|
| `App/Shell/Router.swift` | 新增 `currentDest` / `currentTitle`：标题文案的唯一来源（Dest.title / TabSlot.title） |
| `App/Design/V8/V8Tokens.swift` | 字号落到 HIG 阶梯（body 17 / footnote 15 / label 13 / caption 12 / tab 15）；行高重配；圆角 26→14；投影清零；卡片改纯白；新增 `pageStatus`、`onAccent`、`chipDot`、`iconTile`、`gapHair` |
| `App/Design/V8/V8Components.swift` | `VPage` 改用系统 navigationTitle（large/inline 自动判根页）；`VCardHead` 层级反转；`VChip2` 原生化；`VDotRule` 改实线；`VNavRow` 支持 SF Symbol 图标砖 |
| `App/Features/Settings/SettingsHomeScreen.swift` | 设置索引页 12 行全部加 SF Symbol 图标砖与分组色 |
| 27 个页面文件 | 删除 32 处 `.navigationBarTitleDisplayMode(.inline)` 覆盖，标题模式交给 VPage |

## 3. 验证

- 41 道静态闸门全绿（含 a11y / dynamictype / tokens / contrast 62 条）。
- CI run 42053133202（commit 91445b3b）编译（iOS 27 SDK）success、Android success、26 张截图已发布。
- 新增 `root-<tab>.png` 根页视口图：整页截图不含导航栏，标题只能在这组图里验证。

## 4. 还没做完（下一轮继续）

| 优先级 | 页面 | 还差什么 |
|---|---|---|
| P0 | 记录页 | 台账行仍是 3 行标签式；要改原生 List 行（时间列 + 事件 + 副行） |
| P0 | 家门页 | 英雄环卡片可再收：状态 + 主按钮 + 两个次要读数 |
| P1 | 家页 | 成员行改头像 + 角色 + 最近，去掉「无归属记录」重复标签 |
| P1 | 门/钥匙子页 | 把卡内行表逐步换成原生 grouped rows（图标 + 标题 + 值 + chevron） |
| P2 | 全部页面 | 深色模式截图矩阵；AX5 截图；iPhone Duo / iPad 尺寸类 |
| P2 | 品牌 | 60 刻度盘、Dial Mark、6 套品牌色真正驱动语义色 |

## 5. 纪律

- 不再新增「eyebrow + 判断句」卡头；新卡片一律 `VCardHead(eyebrow: 卡名, statement: 一句说明)`。
- 不再自绘页面标题；标题只走 `VPage` → `Router.currentTitle`。
- 页面正文只用 HIG 阶梯：17 / 15 / 13 / 12；不再出现 19.6 或 21.5。
- 分隔线只用 `VDivider2` / `VDotRule`（现在都是 0.5pt 实线）。
- 动效仍走 `V8.M.*`，并遵守 Reduce Motion。
