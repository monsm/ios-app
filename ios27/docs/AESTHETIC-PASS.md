# 审美打磨记录 · 用过的 skill 与 MCP

> 目标：把界面打磨到"最深层次的审美"。这份文件记录**每一条判据来自哪里**，
> 以及**它在这个项目上具体改了什么**。没有来源的"我觉得更好看"不写进来。

---

## 一、可用性盘点（先说清楚哪些工具真能用）

| 工具 | 状态 | 用了吗 / 为什么 |
|---|---|---|
| **MCP · hig-doctor** | ✅ 可用 | **核心**。全量审计 131 文件，给出 136 条 concern + 4373 条 positive |
| MCP · rea | ✅ 可用 | 用来从原版 APK 里抽真实文案（1186 条中文串），核对有没有丢交互 |
| skill · apple-design | ✅ | 五 lens 框架（无障碍/平台/工艺/交互/文案） |
| skill · impeccable | ✅ | craft floor（禁用清单）+ critique 流程 |
| skill · design-taste-frontend | ✅ | app-screens 八条房规（色彩上数据不上装饰等） |
| skill · frontend-design | ✅ | "生成感"五类特征清单（meta 串用中点、eyebrow 等） |
| skill · swiftui-pro | ✅ | 视图结构 / 性能判据（computed some View、LazyVStack） |
| skill · motion-design | ✅ | 动效人格四档 + 时长表 |
| skill · swiftui-expert-skill | ✅ | iOS 26/27 API 面（@Entry、Tab、glassEffect） |
| skill · office-xlsx | ✅ | 评估后不用：这是代码仓库，台账用 Markdown |
| MCP · mobbin | ❌ 需付费 | 试了，明确拒绝 |
| MCP · sleek | ❌ 需登录 | 试了 |
| MCP · microsoft-learn | ❌ TLS 超时 | 试了两次 |
| MCP · nuget | ❌ 不适用 | 无 .NET 项目 |
| MCP · mockit | ⚪ 空 | 可用但没有生成过屏 |
| skill · ui-design / uizze-ui / anti-ui-slop / ios-glass-design-spec / transitions-* / image-to-ui / design-mobile-apps | ❌ 本会话不可用 | 逐个试过，skill 不存在 |

**诚实说明**：所谓"全部 skill 和 MCP"在本机实际可用的只有上表 9 个。
不能用的我都试过了，不是跳过。

---

## 二、每一条判据 → 具体改了什么

### 1. HIG Doctor：Dynamic Type（最重的一条）

**判据**：`swift/hardcoded-font-size` —— 写死 point size 意味着用户调大字号时它纹丝不动。
（HIG《Typography》："Use the system text styles so text follows the user's reading size"）

**实测**：51 处。这是"假适配"——只有系统控件跟着放大，我们自己的文字不动。

**改法**：`T.F` 全部改成语义字阶。设计稿的 34/22/17/15/13/11 正好落在
largeTitle/title2/body/subheadline/footnote/caption2 —— **默认视觉完全不变**，只是可缩放。
新增 `T.F.icon(size:weight:)` 给 Image(systemName:) 用。

**防回退**：新增闸门 `dynamictype.js`（0 处写死字号才算过）。

### 2. HIG Doctor：VoiceOver（44 处）

**判据**：`swift/image-without-a11y` —— 装饰图标不该进 VoiceOver 焦点。

**改法**：装饰性图标一律 `.accessibilityHidden(true)`；图标按钮保留 `.accessibilityLabel`。
例外：`SharePreview(image:)` 的参数类型是 `Image`（要 Transferable），挂不了修饰符 ——
那是分享卡缩略图，本来就不进焦点，改成纯 `Image`。

### 3. 减弱动态（18 处，我自己查出来的）

**判据**：HIG《Motion》"Make motion optional"；swiftui-pro accessibility.md。
**实测**：10 个文件完全没读 `accessibilityReduceMotion`。
**改法**：全部加 `reduceMotion ? nil : T.M.x` 守卫。
**例外**：按压反馈（`configuration.isPressed`）保留 —— 那是直接操作回执，不是装饰动效。
**防回退**：新增闸门 `reducedmotion.js`。

### 4. craft floor：列表页不该写解释

**判据**：impeccable craft-floor —— "A kicker or eyebrow above a heading. This one is a ban."
以及 Apple 自己的设置页：**列表不解释，解释留在真正做决定的那一页。**

**实测**：设置页 12 条"下一页有什么"的说明。那会把列表变成说明书，失去可扫读性。
**改法**：全部移除，只留 1 条真需要警告的（只读试验模式）。

### 5. app-screens 房规：主动作不该夹在列表中间

**判据**："12 of 23 screens have no filled primary button at all" —— 色彩上数据不上 chrome。
**实测**：钥匙页一条填充绿按钮夹在两块面板之间，那是 Web 形态。
**改法**：移进导航栏（iOS 里主动作属于工具栏）。

### 6. 过滤条 vs 表单框

**判据**：表单输入框的圆角胶囊形状 = "要填的东西"。
**实测**：台账页检索框是圆角胶囊，但它其实是**过滤器**。
**改法**：改成蚀刻下划线 —— 读起来像"正在筛"而不是"要填表"。

### 7. 对比度实测（这条是我自己算出来的，审计没报）

**判据**：UI 组件边界 ≥3:1（WCAG 1.4.11）。
**实测**：选中描边 `Signal.base @ 35%` = **1.69:1**（浅色）/ 2.13:1（深色）—— 强光下等于没有选中态。
**改法**：提到 75%（3.55:1 / 4.87:1），新增 `Signal.edge` 令牌；选中底 12% → 16%。
**防回退**：contrast 闸门加 4 条断言（共 52 条）。

### 8. 状态行可读性

**判据**：11pt 是下限；截断/缩字比换行更糟。
**实测**：5 处状态行最长 81 字，却挂 `lineLimit(1)` + `minimumScaleFactor(0.8)`
—— 在 430pt 宽下必然截断或缩到 10pt。
**改法**：`lineLimit(2)` + `fixedSize(vertical)`。2 处 34pt 标题的 0.6 收到 0.85。

### 9. 失败态信息收敛

**判据**：apple-design Lens 4 —— "Feedback lives in the interface"；同一件事说三遍是噪音。
**实测**：失败时红弧 + 黑色"失败" + 红横幅，三处都在喊同一件事。
**改法**：中心词跟着变红（最重要信息放最先读到的地方）；横幅只说原因与下一步。

### 10. 动效人格

**判据**：motion-design 四档人格表。
**实测**：220/320ms 属 Corporate 档，但"开锁成功"这种高情绪时刻没有对应档。
**改法**：补 `settle`（420ms / 0.95 阻尼，几乎无过冲）只给结果时刻；
人格命名从"Premium"改成 **"Precision"**（短时长 + 高阻尼，不是套模板）。

### 11. 跨文件 private（11 处，CI 只报了 1 处）

**判据**：Swift `private` 只在同文件可见。本仓 6 组 `<Screen>` + `<Parts>` 拆分。
**实测**：CI 报 1 处，静态扫描出 11 处 —— 剩下 10 处只是"那个分支还没被实例化"。
**改法**：全部改 internal 并注明理由。
**防回退**：新增闸门 `crosprivate.js`。

### 12. 大列表用 Lazy

**判据**：swiftui-pro performance.md —— "For large data sets in ScrollView, use LazyVStack".
**实测**：台账时间线用非 Lazy 的 VStack，而锁端缓存上限 300 条。
**改法**：`LazyVStack`。

---

## 三、闸门：12 → 15 道

| 新增 | 判什么 |
|---|---|
| `dynamictype` | 写死字号（0 才过） |
| `reducedmotion` | 装饰动效是否尊重减弱动态 |
| `crosprivate` | 跨文件访问 private 成员 |
| `workflow` | workflow YAML 结构（TAB / run 块缩进 / 顶层键） |

（`types` / `callsig` / `lineage` 是之前加的）

---

## 四、复测结果

| 指标 | 打磨前 | 打磨后 |
|---|---|---|
| HIG critical | 27 | **0** |
| HIG serious | 0 | **0** |
| HIG moderate | 109 | **14**（余下 12 条是 KeyCreate 的 internal @State，跨文件必要） |
| 写死字号 | 51 | **0** |
| 无 a11y 的图标 | 44 | **0** |
| 未守卫的装饰动效 | 18 | **0** |
| 跨文件 private | 11 | **0** |
| 对比度断言 | 48 | **52**（全过） |
| 静态闸门 | 12 | **15**（全绿） |
| CI | 红（4 错） | **绿** |
