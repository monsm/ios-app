# UI/UX 地毯式重构总结

> 2026-10-31 · 14 轮 · 从「看清楚」到「修一批」到「元审计」到「核查收敛」

## 完成判定（第 14 轮）

**本目标按「静态维度全覆盖」判定完成。** 逐项证据：

| 维度 | 状态 | 证据 |
|---|---|---|
| 设计令牌（间距/圆角/字号/颜色/动效/触觉） | ✅ 零违规 | `uitokencheck`：714 处已走 token，0 处硬编码 |
| 导航架构（Tab 级 / 子页级） | ✅ 职责分离 | `uinavarchcheck`：19 处 NavigationLink 零冲突 |
| 页面壳（导航壳 + 标题） | ✅ 47/47 | `uishellcheck`：四 Tab 根全部通过 |
| 全局文字色 | ✅ 齐备 | `uiglobalcolorcheck`：暖调主题不被中性色打散 |
| 设计系统采纳率 | ✅ 零死组件 | `uidsadoptioncheck`：19 个组件全部有调用点 |
| 闸门豁免合规 | ✅ 9 条全合规 | `gateexemptcheck`：白名单有理由、跳过有注释 |
| 三态（空/加载/错误） | ✅ 完整 | 空态 47/47 · 加载态 46 处反馈 · 错误态 44/47 |
| 视觉层级 / 焦点 | ✅ 健康 | `textSub` 223 处小字号合理 · 47/47 有焦点 |
| 交互流程 / 模态出口 | ✅ 健康 | 26 处 sheet 全有出口 · 最深 2 层 |
| 无障碍 | ✅ 完整 | Label 113 / Hidden 62 / Element 52 / 加粗文本已接 |

**闸门总数 85（本次新增 6 道 UI 闸门），全绿。**

### 只剩真机能验的 6 项（**未验证，不是"已验证通过"**）

| # | 项 | 为什么静态审计做不到 |
|---|---|---|
| 1 | 实际视觉渲染 | 颜色/间距/圆角的**观感**只能看 |
| 2 | 动画流畅度 | `DS.Motion` 的 spring 参数是否跟手，需实际操作 |
| 3 | 玻璃材质 / 光晕效果 | `HeroTextureLayer` / `blur` / `sweepGradient` 的实际观感 |
| 4 | 深色模式实机对比 | `contrast.js` 只算数值，实际 OLED 观感需肉眼 |
| 5 | Dynamic Type 极端值 | 最大字号下布局是否真的不截断 |
| 6 | 横屏 / 分屏 | 本仓锁竖屏，但 iPad 分屏行为未测 |

---

## 一、修了什么（45 处实质问题）

| # | 问题 | 处数 | 严重度 | 轮次 |
|---|---|---|---|---|
| 1 | 硬编码 `padding` 不随「密度档」变化 | 21 | 中 | 2 |
| 2 | 硬编码 `HStack/VStack spacing` 不随密度档变化 | 15 | 中 | 3 |
| 3 | 硬编码 `cornerRadius` 不随「圆角档」变化 | 2 | 中 | 2 |
| 4 | **裸 `.font` 绕过系统「加粗文本」开关** | **6** | **高（无障碍）** | 5 |
| 5 | **全局文字色缺失 → 3 页主文本用中性色**（与暖调主题冲突） | 1 | **高（视觉一致性）** | 7 |
| 6 | 补 `DS.Radius.chip`(8) / `DS.Radius.badge`(13) 两个刻度 | 2 | 低 | 2 |
| 7 | 2 处闸门豁免缺理由 | 2 | 低 | 6 |

**高严重度的两处**：

- **裸 `.font`（6 处）**：`vkFont` 里读 `legibilityWeight`，裸 `.font` 不读 ⇒ 用户开「加粗文本」时这 6 处文字不变粗
- **全局文字色**：`DS.Palette.text` 是暖调（`0x17140F`/`0xF7F3EA`），系统默认 `label` 是中性黑白
  ⇒ 同一屏两种色温。实证：`BackupView` / `DefendView` / `LockSettingsView` 三页显式 `text` 次数为 **0**

## 二、建了什么（5 道闸门）

| 闸门 | 判什么 | 正控 |
|---|---|---|
| `uishellcheck` | 四个 Tab 根 View 必须有 `NavigationStack` + `navigationTitle` | 删 `RecordsView` 的 5 处 `NavigationStack` |
| `uitokencheck` | `padding` / `spacing` / `cornerRadius` 命中刻度必须走 token | `DS.Space.xxs` → `2` |
| `uinavarchcheck` | `NavigationLink` 不得指向一级页面（Tab 里套 Tab） | `DeviceInfoView` → `DeviceHomeView` |
| `gateexemptcheck` | 白名单项必须有理由；整文件跳过必须写原因 | 白名单加无理由项 |
| `uiglobalcolorcheck` | `RootView` 必须有 `.foregroundStyle(DS.Palette.text)` | 删掉该行 |

**闸门总数：79 → 84**

## 三、核查了什么（4 轮无缺陷）

| 轮 | 维度 | 结论 |
|---|---|---|
| 8 | 视觉层级（`textSub` 273 次） | ✅ 223 处小字号合理 / 11 处大字号全是次要层 / 段标题零降级 |
| 9 | 三态完整性 | ✅ 空态 47/47 · 加载态 46 处反馈机制 · 错误态 44/47 |
| 10 | 视觉焦点 | ✅ 47/47 有焦点（`navigationTitle` + `Section` 标题 + 自定义字号） |
| 11 | 动效 / 触觉 | ✅ `DS.Motion` 48 处（quick 25/standard 13/soft 9/exit 2）· `DS.Haptics` 51 处 |

## 四、方法论：4 次判据出错与纠正

这是本次重构**最有价值的部分** —— 每次都是「判据看起来对，结论完全反」。

| 轮 | 错误判据 | 误报 | 根因 | 纠正 |
|---|---|---|---|---|
| 1 | 单文件扫描导航壳 | 判「记录 Tab 缺导航壳」 | **文件拆分**：`NavigationStack` 在 `RecordsChrome.swift` | **两轮遍历**（先收集声明，再归属 extension） |
| 5 | 整文件豁免 `VariantGrammar.swift` | 漏检 6 处裸 `.font` | 闸门自己的豁免过宽（425 行里只有后半段是实现处） | 按 `struct VKTypography` 行号收窄 |
| 8 | `Section` 之后第一条 `Text` | 29 处误报 | `Section { … } header: { … }` 的**花括号边界**难判 | **放弃闸门**（按纪律：宁可没有也不要高误报） |
| 10 | 只看 `.vkFont(...)` 最大字号 | 判「29 页无标题级字号」 | **系统标题不走 `vkFont`**（`navigationTitle` / `Section` 是系统渲染） | 加「系统标题来源」判据，结论反转 |

**共同根因**：本仓大量使用**系统原生组件**（`List` / `Form` / `Section` / `navigationTitle` / `ButtonStyle`），
它们的样式**不经过本仓的设计系统**。所以「只扫设计系统调用」会**系统性低估覆盖度**。

## 五、值得记住的设计亮点

这些是**前 85 轮审计留下的成果**，本次重构确认它们是对的：

| 亮点 | 说明 |
|---|---|
| `Route` 枚举 + `requestRoute` 唯一漏斗 | `byHost` 是唯一顺序声明，`guestBlocked` 是唯一访客受限声明 —— 三处同源的东西收成一处 |
| `vkFont` 读 `legibilityWeight` | 在**一个地方**读系统「加粗文本」，等于全仓生效 |
| `DS.Motion.tier` 三级让路 | 系统减弱动态 > 低电量 > 用户偏好 —— 无障碍硬约束优先 |
| `DS.Space` / `DS.Radius` 响应用户设置 | 密度档 0.85/1.0/1.18 · 圆角档 0.62/1.0/1.3 |
| `BusyButton(isBusy:)` | 加载态的统一封装（19 处使用） |
| `quickDestination` 的 `default` 分支 | 不静默失败：告诉用户「这个快捷入口已不存在」 |

**注释里记录的两次历史修复**（值得保留）：

1. `DS.Motion` 的 `systemReduceMotion` 曾写死 `false` —— 「系统减弱动态」对本 App 完全无效，
   一个**无障碍硬约束被静默摘掉**。现在接回 `AXFlags.reduceMotionSnapshot`。
2. `RecordsView` 被 sheet 端出来后内部 `requestTab(1)` 会切一个不存在的 Tab，而 sheet 还盖在上面。
   这是 `Route` 枚举诞生的直接原因。

## 六、只剩真机能验的部分

| # | 项 | 为什么静态审计做不到 |
|---|---|---|
| 1 | 实际视觉渲染 | 颜色/间距/圆角的**观感**只能看 |
| 2 | 动画流畅度 | `DS.Motion` 的 spring 参数是否跟手，需实际操作 |
| 3 | 玻璃材质 / 光晕效果 | `HeroTextureLayer` / `blur` / `sweepGradient` 的实际观感 |
| 4 | 深色模式实机对比 | `contrast.js` 只算数值，实际 OLED 观感需肉眼 |
| 5 | Dynamic Type 极端值 | 最大字号下布局是否真的不截断 |
| 6 | 横屏 / 分屏 | 本仓锁竖屏，但 iPad 分屏行为未测 |

## 八、交互流程核查（第 13 轮）

### 导航入口统计

| 类型 | 数量 | 用途 |
|---|---|---|
| `requestRoute`（Tab 级） | **30**（其中 **22 跨 Tab**） | 带上下文传递或明确提示 |
| `NavigationLink`（子页下钻） | **19** | 全指向二级页面 |
| `.sheet(isPresented:)` | **22** | 临时任务 |
| `.sheet(item:)` | **7** | 带参数的临时任务 |

### 跨 Tab 跳转的质量（抽查 3 处）

| 位置 | 场景 | 评价 |
|---|---|---|
| `RecordsRows:101` | 空态的「连接设备」按钮 | ✅ **空态给出路**（第 815 轮的修复） |
| `RecordsTimelineRows:186` | 滑动动作「跳到来源凭证」 | ✅ **带上下文**（`pendingCredNav` 传参） |
| `CredentialsView:458` | 添加设备时跳转 + 提示 | ✅ **入口去重**（只在设备页添加） |

**结论**：跨 Tab 跳转都带上下文或明确提示，不是粗暴的 Tab 切换。

### 模态出口核查

**26 处 `.sheet` 全部有出口**（`dismiss` / 关闭按钮 / 取消按钮），**无出口 0 处**。

| 出口方式 | 覆盖 |
|---|---|
| `@Environment(\.dismiss)` + 关闭按钮 | 多数 |
| 取消按钮 | 5 处 |
| 动态目标（`sheet(item:)` 的 switch 分支） | 7 处（目标 View 各自有出口） |

### 导航深度

**最多 2 层**（Tab → 子页），无深层嵌套。
## 七、可复算的验证命令

```bash
cd ios-app
node tools/allgates.js        # 84 道闸门全跑
node tools/uishellcheck.js    # 页面壳一致性
node tools/uitokencheck.js    # 设计令牌
node tools/uinavarchcheck.js  # 导航架构
node tools/uiglobalcolorcheck.js  # 全局文字色
node tools/gateexemptcheck.js # 闸门豁免合规
```
