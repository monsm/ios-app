# AUDIT-D — HIG / 无障碍 / 设计审计

审计对象：`ios-app/ios27`（148 个 Swift 文件 + 23 个 DesignLab HTML/JS，共 171 个 code 文件）
审计日期：2026-10-31
审计口径：hig-doctor MCP（snapshot 2025-02-02）全项目审计 + 148 个 Swift 文件逐文件复核 + 55 张 DesignLab 截图（light/dark 各半）目检
HIG 参考：apple-design skill 内置 Apple HIG 快照（accessibility / layout / typography / color / dark-mode / voiceover / tab-bars / feedback / images / motion）
约束：只读审计，未修改任何源码

---

## 0. 结论摘要

- **工具原始输出：93 条 concern — 27 critical / 66 moderate。**
- **逐条 triage 后，非误报的 app 内问题：15 条（P1 2 / P2 7 / P3 6）。**
- **误报 / 非 app 范围：63 条**：
  - `swift/ignores-safe-area` 23 条全部误报 —— `.background(V.C.bg.ignoresSafeArea())` 是铺满屏幕底色的标准写法，Panel.swift:62-70 的组件注释已说明；
  - `swift/hardcoded-rgbcolor` 4 条全部误报 —— V7Tokens.swift:77/162 是令牌工厂本身，SettingsModel.swift:375 是用户自定义强调色的 HEX 解析，ShareToAndroidScreen.swift:227 是二维码位图的白底 `CIColor`，都不是样式硬编码；
  - `swift/image-without-a11y` 中 5 条误报 —— SharePreview 缩略图 2 条（系统渲染、不进 VoiceOver 焦点，代码注释已说明）、搜索框清空按钮 3 条（按钮已有 `.accessibilityLabel`）；
  - `web/missing-alt` 27 条位于 `DesignLab/out/sheet.html`（内部设计总览页），不是 app UI，按工具类问题单列 P3。
- **最严重的两个用户可见问题**：V7 调色板只有深色一套（浅色主题完全不生效，D-01）；根视图强制 `.dynamicTypeSize(.large)`，用户系统字号被覆盖（D-02）。

---

## 1. 工具聚合（ruleId / severity）

### 1.1 项目级 hig_audit

| 指标 | 数值 |
|---|---:|
| Files scanned | 171 code + 1 config |
| Concerns | **93** |
| Critical | **27** |
| Serious | 0 |
| Moderate | **66** |
| Positive patterns | 4569 |

### 1.2 按 ruleId 聚合（项目级 93 条 = 文件级 66 条 Swift + 27 条 DesignLab HTML）

| ruleId | severity | 条数 | 涉及文件数 | Triage 结论 |
|---|---|---:|---:|---|
| `web/missing-alt` | **critical** | **27** | 1（DesignLab/out/sheet.html） | 非 app 范围（内部设计总览页），P3 工具类 |
| `swift/non-private-state` | moderate | 26 | 2 | **真实**（P3 代码规范） |
| `swift/ignores-safe-area` | moderate | 23 | 19 | **全部误报**（标准全屏底色写法） |
| `swift/image-without-a11y` | moderate | 13 | 7 | 8 条真实（P2）/ 5 条误报 |
| `swift/hardcoded-rgbcolor` | moderate | 4 | 3 | **全部误报**（令牌/用户色/二维码） |
| **合计** | **27 critical + 66 moderate** | **93** | — | — |

> 备注：project 汇总把 `web/missing-alt`（27）计为 critical，其余 Swift 规则都是 moderate；文件级 `hig_audit_file` 的结果与之一致。下面所有行号均为当前工作树实际行号。

### 1.3 逐文件审计覆盖

- 对 148 个 `.swift` 全部执行了 `hig_audit_file`（0 个执行失败）。
- 有 concern 的 Swift 文件 25 个；无 concern 的 Swift 文件 123 个。
- 逐文件合计：66 条 concern，全部 moderate；类型分布：`pattern` 413、`positive` 347、`concern` 66。

---

## 2. 全量 triage（93 条逐条判定）

### 2.1 `swift/ignores-safe-area`（23 条，全部误报）

23 条全部是 `.background(V.C.bg.ignoresSafeArea())` / `CanvasBackground()` 的页面底色写法：`DoorScreen.swift:63`、`KeysScreen.swift:88`、`RecordsScreen.swift:120`、`SettingsScreen.swift:68/669`、`Shell.swift:26/28`、`Panel.swift:69` 等。`Panel.swift:62-66` 明确注释：页面底色必须铺到屏幕四边，内容层在 ScrollView 中由系统安全区避让。此模式符合 HIG `Layout › Visual hierarchy`（"Extend content to fill the screen or window"）与安全区规则，**不是违规**。

### 2.2 `swift/hardcoded-rgbcolor`（4 条，全部误报）

| 文件:行 | 内容 | 判定 |
|---|---|---|
| `V7Tokens.swift:77` | `Color(red: r / 255, ...)` | 令牌工厂 `V.C.rgb` 的定义本身，唯一职责就是把 8bit 参考值转 Color；设计系统内部必须存在 |
| `V7Tokens.swift:162` | `dimmed()` 的 `Color(red: r * factor, ...)` | 同上，按 55% 亮度派生令牌色 |
| `SettingsModel.swift:375` | `color(hex:)` 的 `Color(red:...)` | 用户在 ColorPicker 里选的任意强调色，无法预置 asset；运行时 HEX 解析是正确实现 |
| `ShareToAndroidScreen.swift:227` | `CIImage(color: CIColor(red:1,green:1,blue:1,...))` | 生成二维码位图的白色画布，是图像像素而非 SwiftUI 样式色 |

### 2.3 `swift/image-without-a11y`（13 条：8 真实 + 5 误报）

| 文件:行 | 内容 | 判定 |
|---|---|---|
| `LockProfileScreen.swift:127/141` | PIN 选择行的 `checkmark` | **真实**：装饰性勾选图未隐藏，VoiceOver 可能读成 "checkmark"；应由行按钮的 selected trait 表达 |
| `LockProfileScreen.swift:164` | 符号网格 `Image(systemName: item.name)` | **真实**：按钮已有 `.accessibilityLabel("符号 \(item.label)")`，图标应 `.accessibilityHidden(true)` |
| `CredentialStudioScreen.swift:240/280` | 选择圆形勾选图 | **真实**：按钮已有选择 label，图标应隐藏 |
| `CredentialStudioScreen.swift:251` | 静态 `star.fill` | **真实**：表示"已星标"的装饰图标，无 a11y 语义；需补 "已星标" 或并入行 label |
| `CredentialStudioScreen.swift:262` | 星标切换按钮的 `star`/`star.fill` | **真实**：按钮 label 固定 "星标"，不随状态变为 "取消星标"；也缺 `.isSelected` |
| `RecordsScreen.swift:320` | 记录卡 `figure.walk` | **真实**：装饰事件图标，应 `.accessibilityHidden(true)` |
| `ShareToAndroidScreen.swift:128` | `SharePreview(image: Image(systemName:"qrcode"))` | **误报**：SharePreview 缩略图由系统渲染、不进 VoiceOver 焦点，代码注释明确 |
| `RecordExportScreen.swift:127` | `cardPreview` 的 `Image(systemName:"doc.richtext")` | **误报**：同上，SharePreview 预览位 |
| `KeysScreen.swift:347` | 搜索清空 `xmark.circle.fill` | **误报**：外层 Button 已有 `.accessibilityLabel("清空凭证搜索")` |
| `RecordsScreen.swift:456` | 搜索清空 `xmark.circle.fill` | **误报**：外层 Button 已有 `.accessibilityLabel("清空检索")` |
| `SettingsScreen.swift:140` | 搜索清空 `xmark.circle.fill` | **误报**：外层 Button 已有 `.accessibilityLabel("清空设置搜索")` |

### 2.4 `swift/non-private-state`（26 条，真实但属代码规范）

- `MemberCreateScreen.swift:18-30`：13 个 `@State var` 未加 `private`
- `KeyCreateScreen.swift:20-34`：13 个 `@State var` 未加 `private`
- 判定：真实，但只影响状态封装与可维护性，不直接影响用户；P3。

### 2.5 `web/missing-alt`（27 条，非 app 范围）

`DesignLab/out/sheet.html:1` 的 27 个 `<img>` 均无 `alt`；因为是单行压缩 HTML，27 条命中都在 line 1。该页是团队内部设计总览（27 张截图索引），不随 app 交付；按工具类 P3 处理，建议补 alt 或 `alt=""`。这不是 App Store 构建产物的一部分。

---

## 3. 真实问题清单（按严重度）

> 严重度定义：P1 = 影响全量用户/全 app 的可达性或外观；P2 = 明确可感知的无障碍/触达/对比度缺陷；P3 = 低风险规范/一致性/内部工具问题。

| ID | 严重度 | 位置（file:line） | 问题 | HIG 引用 | 修复建议 |
|---|---|---|---|---|---|
| D-01 | **P1** | `V7Tokens.swift:75-164`（bg:80, text1:89, card:81, pink:128, blue:104）；`LockKeeperApp.swift:42`；`SettingsModel.swift:15-39`；`AppearanceScreen.swift:56-81` | V7 调色板全部是固定 RGB，没有 light/dark 双取值；用户选「浅色」后四个根页仍是 #000000 黑底白字，而标签栏 `.ultraThinMaterial` 会随系统变浅灰，形成黑页上的浅灰胶囊（半黑半白）。DesignLab 的 light 截图已给出完整浅色设计，Swift 实现没有接线。 | `color.md › Best practices`："Make sure all your app's colors work well in light, dark, and increased contrast contexts… If you define a custom color, make sure to supply light and dark variants"；`dark-mode.md › Best practices`："Ensure that your app looks good in both appearance modes." | 将 `V.C` 改为 `Color.dual(light:dark:)`（可复用 `Tokens.swift:150-160` 的 dual 实现）：paper #F2F2EF/#0B0C0D、plate #FFFFFF/#15171A、ink #14161A/#F3F4F2、base #1D6F5F/#47C9A6 等；标签栏材料按 trait 选固定不透明底；或明确只支持深色并移除浅色选项。 |
| D-02 | **P1** | `LockKeeperApp.swift:43` | `.dynamicTypeSize(settings.axBigText ? .accessibility2 : .large)` 把 Dynamic Type 环境钉死在 `.large`。用户在 iOS 设置里调大字号完全无效，除非发现 App 内「全局大字」开关；且该开关最高只到 Accessibility 2，无法使用 AX3–AX5。 | `typography.md › Supporting Dynamic Type`："Make sure your app's layout adapts to all font sizes… turn on Larger Accessibility Text Sizes in Settings… confirm your app remains comfortably readable"；`accessibility.md › Vision`："Support larger text sizes… Ideally, give people the option to enlarge text by at least 200 percent… either through custom UI, or by adopting Dynamic Type." | 删除固定 `.dynamicTypeSize(...)`；如需 App 内大字档，改为 `.dynamicTypeSize(.large ... .accessibility5)` 的下限增强或 `@Environment(\.dynamicTypeSize)` 驱动的附加缩放；在 AX3/AX5 下逐屏截图验证。 |
| D-03 | **P2** | `V7Components.swift:201-216`（`VChip` 固定 53.3pt 高、两行均 `lineLimit(1)`）；`V7Extras.swift:351-368`（`VChipRow` 固定 `V.H.chip`=32pt）；`V7Tokens.swift:268/328`；`V7Components.swift:668-673`（Tab 标签 9pt + Tab 图标 20pt 塞进 57pt 固定高） | 固定高度 + `lineLimit(1)` 的 chip/分段控件在 Accessibility 字号下会裁剪或截断文字；TabBar 图标和标签同时放大后也会溢出 57pt 高。 | `typography.md › Supporting Dynamic Type`："Keep text truncation to a minimum as font size increases… Consider adjusting your layout at large font sizes"；`layout.md › Adaptability`："table rows or other containers may need to grow in height so that text isn't cropped" | 把固定 `height` 改 `minHeight`；chip 允许两行/纵向堆叠；`VChip` 的标题/值在 Accessibility 尺寸下改用纵向布局；TabBar 按 `dynamicTypeSize` 切换紧凑图标或允许高度增长。 |
| D-04 | **P2** | `V7Extras.swift:273-289`（`VTag` 本体）；`TailgateScreen.swift:33-42`；`AccessibilityScreen.swift:87-109`；`RecordsStudioScreen.swift:139-172`；`LockPortfolioScreen.swift:96-110` | `VTag` 只有 13pt 文字 + 4pt 垂直 padding（约 24–26pt 高），却被直接当作 Button 的 label；点击区域远低于 iOS 44×44pt 推荐值，也低于 28×28pt 最低值。 | `accessibility.md › Mobility`："iOS, iPadOS: Default control size 44x44 pt; Minimum control size 28x28 pt"；"Consider spacing between controls as important as size." | 在 `VTag` 内或所有调用处加 `.frame(minHeight: V.Hit.min)` + `.contentShape(.rect)`；若视觉必须保持 26pt，使用透明扩边（padding 9pt）保证 44pt 命中区。 |
| D-05 | **P2** | `V7Extras.swift:278-287`（filled `VTag`：白字 + tint 底）；`V7Tokens.swift:104`（`V.C.blue` #3F8EF4）；使用处：`TailgateScreen.swift:38`、`AccessibilityScreen.swift:91/104`、`LockPortfolioScreen.swift:158`、`LinkSense.swift:206` | 选中 tag 为白色 13pt 常规字压在 #3F8EF4 蓝底上，WCAG 对比度 **3.29:1** < 4.5:1（13pt 不属于 18pt/粗体豁免）；同色还被 `VActionButton` 用作 17pt semibold 主按钮底（3.29:1，处于 3:1 边界）。 | `accessibility.md › Vision` 对比度表："Up to 17 pts / All / 4.5:1；18 pts / All / 3:1；All / Bold / 3:1" | 选中态改用深底：`V.C.base` #1D6F5F（白字 6.02:1）或深蓝 #2F6FC0；或 filled 状态使用深色文字；主按钮同改。 |
| D-06 | **P2** | `V7Tokens.swift:128`（`V.C.pink` #F0375F）；文本使用：`BackupStudioScreen.swift:136`、`MemberOpsScreen.swift:240`、`CredentialStudioParts.swift:120`、`BackupStudioScreen.swift:113`、`SafeModeScreen.swift:65`、`TailgateScreen.swift:54`、`ZotpScreen.swift:144`、`CredentialStudioScreen.swift:225`、`LockProfileScreen.swift:238` | 13pt 错误/破坏性文字 `#F0375F` 在卡片 `#232227` 上为 **4.07:1**、`cardAlt #1C1C1E` 上 4.39:1、`cardWarm #282322` 上 4.00:1，均低于 4.5:1。 | `accessibility.md › Vision` 对比度表 4.5:1（≤17pt）；`color.md › Inclusive color`："insufficient contrast can cause icons and text to blend with the background" | 将 `V.C.pink` 的文本用途换成 `V.C.critical` #FF6A5C（在卡上 5.62:1），或把 pink 调深到 ≥ #D92B4B；保留 pink 仅作图标/装饰。 |
| D-07 | **P2** | `LockProfileScreen.swift:127/141/164`；`CredentialStudioScreen.swift:240/251/262/280`；`RecordsScreen.swift:320` | 8 处装饰/状态图标没有 `.accessibilityHidden(true)`，或状态没有通过 accessibilityValue/trait 表达：勾选图标会被 VoiceOver 当作图片读；星标切换按钮永远读 "星标"，用户无法知道当前是否已星标。 | `voiceover.md › Descriptions`："Exclude purely decorative images from VoiceOver"；"Provide alternative labels for all key interface elements"；`accessibility.md › Vision`："Describe your app's interface and content for VoiceOver" | 装饰图标统一 `.accessibilityHidden(true)`；PIN 行和符号行按钮加 `.accessibilityValue(selected ? "已选" : "未选")` + `.accessibilityAddTraits(.isSelected)`；星标按钮 label 改为 `isStarred ? "取消星标" : "星标"`。 |
| D-08 | **P2** | `V7Components.swift:630-637`（`VTabItem.all` 只有 door/keys/records/settings 4 项）；`Router.swift:133-159`（`TabSlot.household = 3`）；`Shell.swift:23/55-65`（household 仍是顶层内容） | 家/家庭是 `TabSlot` 的第 4 个顶层页，但浮动标签栏只有 4 项且不含家；切到 `.household` 时没有任何 tab 高亮，用户无法从 tab 栏进入家。DesignLab 全部 27 张截图（`door.light.html` 的 `.tabbar` 及所有 shots）均为 5 项：门/钥匙/台账/家/设置。 | `tab-bars.md › Best practices`："Use a tab bar to support navigation… Make sure the tab bar is visible when people navigate to different sections of your app"；"Don't disable or hide tab bar buttons, even when their content is unavailable" | 在 `VTabItem.all` 中加入 `VTabItem(slot:.household, title:"家", symbol:"person.2.fill")`（5 项，268/5≈53.6pt 仍 >44pt），或把家从顶层 TabSlot 移除并明确其入口层级；同时更新 Shell 注释"v7 参考图只有 4 个标签"。 |
| D-09 | **P2** | `SettingsModel.swift:167-185`（`density` / `highContrast` / `reduceTransparency` 只存不读）；`AppearanceScreen.swift:49/326`（仅状态文案和 chip）；`V7Components.swift:694-706`（`.ultraThinMaterial` 固定使用，不读 `accessibilityReduceTransparency`） | 「减少透明」「高对比」「密度」三个外观开关是死设置：全仓没有布局/颜色/材料读取它们；标签栏始终使用 `.ultraThinMaterial`，系统开启 Reduce Transparency 时也不降级。 | `accessibility.md › Vision`："If your app doesn't provide this minimum contrast by default, ensure it at least provides a higher contrast color scheme when the system setting Increase Contrast is turned on"；`dark-mode.md › Best practices`："Test your content… in Dark Mode with Increase Contrast and Reduce Transparency turned on" | 要么删除三个死开关，要么接线：`@Environment(\.colorSchemeContrast)` + `@Environment(\.accessibilityReduceTransparency)` 注入令牌解析；`VFloatingTabBar` 在 reduceTransparency 时改用不透明 `V.C.tabGlass` 纯色；density 映射 `V.S` 间距系数。 |
| D-10 | **P3** | `V7Tokens.swift:201-204`（`small 10.7` / `micro 10` / `microMedium 10` / `microSmall 9.5`）、`V7Tokens.swift:227`（`tab = sans(9, relativeTo: .caption2)`）；`V7Components.swift:669`（Tab 标签使用 `V.F.tab`） | 多个持久显示的文字样式低于 iOS 11pt 最小字号：Tab 标签 9pt、micro 9.5–10pt、small 10.7pt。 | `accessibility.md › Vision`："Use recommended defaults for custom type sizes… iOS, iPadOS: Default size 17 pt, Minimum size 11 pt"；`typography.md › Ensuring legibility`："iOS, iPadOS default 17 pt / minimum 11 pt" | 将 `V.F.tab` 提到 ≥11pt（`sans(11, relativeTo:.caption)`）；micro 档统一 ≥11pt，必要时减少层级而非缩小字号。 |
| D-11 | **P3** | `MemberCreateScreen.swift:18-30`（13 处）；`KeyCreateScreen.swift:20-34`（13 处） | 26 个 `@State var` 缺少 `private`，与 SwiftUI 的视图私有状态约定不符（工具规则 `swift/non-private-state`；HIG 规则映射到 `feedback.md`）。 | `feedback.md › Best practices`（工具规则文档映射）；SwiftUI 状态管理：`@State` 应为视图私有 | 全部改为 `@State private var`；同文件其他 `@State` 也按此检查。 |
| D-12 | **P3** | `project.yml:54-55` | 仅声明 `UIInterfaceOrientationPortrait`，iPhone 不支持横屏；HIG 建议 iOS app 尽量同时支持横竖屏。 | `layout.md › Platform considerations — Mobile (iOS, iPadOS)`："Aim to support both portrait and landscape orientations." | 如门锁场景必须竖屏，在 README/设计说明中记录限制；否则补充 LandscapeLeft/Right 并验证布局。 |
| D-13 | **P3** | `V7Components.swift:770-789`（`VCardHeader` 默认 `showsChevron: true`）；`KeysScreen.swift:160/228/295` 等 56 处使用 | 卡片标题右侧的 chevron 看起来像可点击下钻控件，但这些卡片没有点击动作（VCard 不是 Button），产生假可点击提示。 | `layout.md › Visual hierarchy`："Differentiate controls from content"；`feedback.md › Best practices`："Make sure all feedback is accessible." | 非交互卡片一律 `showsChevron: false`；只有真正可点击的入口才显示 chevron，并给按钮加 label/role。 |
| D-14 | **P3** | `DesignLab/out/sheet.html:1` | 内部设计总览页的 27 个 `<img>` 全部缺 `alt`（hig_audit_file: `web/missing-alt` ×27 critical）。不是 app 包内文件，但若分享给他人用屏幕阅读器浏览会失去 27 张截图的语义。 | `accessibility.md › Vision` / `voiceover.md › Descriptions`："Provide alternative text… describe meaningful images" | 为每个截图加 `alt="<screen name> — <state>"`；纯重复展示用 `alt=""`。 |
| D-15 | **P3** | `AppearanceScreen.swift:56-81`；`SettingsModel.swift:15-39` | 提供 App 内「跟随系统 / 浅色 / 深色 / 纯黑」外观设置。HIG Dark Mode 明确不建议 app 自建外观设置，增加用户二次调整成本；若保留，必须保证每个选项真实生效（见 D-01）。 | `dark-mode.md › Best practices`："Avoid offering an app-specific appearance setting. An app-specific appearance mode option creates more work for people…" | 默认仅跟随系统；如保留纯黑作为 OLED 卖点，说明与系统深色关系；修复 D-01 后再保留选项。 |

---

## 4. DesignLab 截图目检（55 张：27 屏 × light/dark + 总览 _sheet）

已逐张读取：door（4 状态+空态）、keys（台账/空态/详情/新建/月历）、records（时间轴/空态/详情）、household（成员/详情/空态）、settings（分组/安全/外观/备份/硬件/关于）、door 子页（配网/配网链/锁实况/校时/布防），以及 `_sheet.png` 27 屏总览。

### 4.1 截图确认的设计事实

- **所有截图的浮动标签栏都是 5 项：门 / 钥匙 / 台账 / 家 / 设置。** 代码只有 4 项且无「家」→ D-08 的直接证据（`DesignLab/out/door.light.html` 的 `.tabbar` 同样 5 个 `.t`）。
- **Light 截图展示了一套完整的浅色设计**（paper #F2F2EF / plate #FFFFFF / ink #14161A / base #1D6F5F），而 Swift 的 V7 令牌只有深色值 → D-01 的直接证据；这不是"截图不好看"，而是设计稿与实现分叉。
- **深色截图与浅色截图在信息层级、字号、间距上一致**；浅色下 `--ink-faint #61676E` 在 paper 上 5.10:1、在 plateAlt 上 4.69:1，设计稿本身的浅色对比度达标。

### 4.2 截图可见的视觉问题 / 风险

1. **P3 · 小字号标签接近不可读**：`keycreate.light.png` 的步骤条「01 选类型 / 02 填内容…」、`appearance.light.png` 的「跟随系统/浅色/深色」及多处 10–10.5px 辅助标签，在 430px 截图里已偏小；对应代码 D-10 的 9–10.7pt 令牌。建议设计/实现统一提到 11pt。
2. **P3 · 底部浮动标签栏压住首屏最后一行**：`door.light.png` 底部「成员 ›」行被标签栏切掉；`settings.light.png` 的「关于 1.0 (27)」也压在标签栏下。若截图是首屏静态稿，应补 `contentInset`/滚动安全区；代码 Shell 已加 92pt safeAreaInset，实机需确认最后一行可完整滚出（不是永久遮挡）。
3. **通过项**：`door-failed.light` 的错误 banner 用 `--critical #A32B22` 在 10% critical 底上可读；`security.light` 开关/标签、`backup.light` 主按钮白字深绿（6.02:1）、`about.light` 计数数字均清晰。未发现截图中出现横向截断、文字重叠或控件越界（除上述标签栏遮挡外）。

---

## 5. 逐项 HIG 检查表

| HIG 维度 | 结论 | 证据 |
|---|---|---|
| Dynamic Type | ❌ 系统字号被覆盖（D-02）；固定高度控件在大字号下会裁剪（D-03）；微字号 <11pt（D-10） | `LockKeeperApp.swift:43`；`V7Components.swift:216`；`V7Tokens.swift:227` |
| VoiceOver | ⚠️ 基础很好（大量 `.accessibilityLabel`/`Hidden`/`Value`），但 8 处装饰/状态图标需修（D-07）；图表组件已有 label+value（VGauge/VSegmentedRing/VRingStack/VMiniBars/VAreaChart 均实现） | 见 `2.3 与 D-07 |
| 对比度 | ❌ 2 类失败：filled VTag 3.29:1（D-05）、pink 文本 4.00–4.39:1（D-06）；其余主要正文/次要文本 4.8–21:1 通过 | 计算见 D-05/D-06 |
| 44pt 触达 | ⚠️ 主要按钮/行 44–57pt 通过；VTag 按钮约 24–26pt（D-04）；顶部系统 toolbar 由系统保证 44pt | `V7Extras.swift:273-289` 等 |
| Reduce Motion | ✅ 页面级 25 处动画中 23 处带 `reduceMotion ? nil :` 守卫；仅 `Primitives.swift:172` 与 `Dial.swift:174` 的按压缩放无守卫（轻微，P3 观察项，不在真实问题清单单列） | grep 结果 |
| Dark Mode | ❌ V7 只有深色值，浅色主题零效果（D-01）；同类还有 `.ultraThinMaterial` 在浅色下与黑页冲突 | `V7Tokens.swift:80-164`；`V7Components.swift:696` |
| 导航/Tab | ❌ 顶层「家」不在标签栏（D-08）；自定义浮动标签栏虽实现了 label/selected trait（`V7Components.swift:641-709`），但绕过系统 TabView 的 iPad/scroll-to-top/rotor 行为，作为 P3 设计风险附于 D-08 | `V7Components.swift:630-637`；`Router.swift:133-159` |
| 字体层级 | ✅ V7 的 VFont 已用 `@ScaledMetric + relativeTo`（`V7Tokens.swift:25-71`），默认视觉与参考一致；仅微字号档位需上调 | `V7Tokens.swift:25-71` |
| 图标 | ✅ 绝大多数 `Image(systemName:)` 已 hidden 或由按钮 label 承载；发现的问题集中在 D-07 | 见 `2.3 |
| 颜色语义 | ✅ 状态点同时用形状（圆/三角/方）+ 文字，不只靠颜色（`V7Extras.swift:301-331`）；好实践 | — |

---

## 6. 误报清单（明确不报）

1. **`swift/ignores-safe-area` ×23** — 全屏底色 `.background(V.C.bg.ignoresSafeArea())` / `CanvasBackground()` 是标准实现；Panel.swift:62-70 有注释；内容层未忽略安全区。
2. **`swift/hardcoded-rgbcolor` ×4** — V7Tokens.swift:77/162 是令牌工厂，SettingsModel.swift:375 是用户自定义色，ShareToAndroidScreen.swift:227 是二维码白色位图。
3. **`swift/image-without-a11y` ×5** — SharePreview 缩略图 2 处（系统渲染，不参与 VoiceOver），搜索清空按钮 3 处（已有 accessibilityLabel）。
4. **`web/missing-alt` ×27** — 仅内部 `DesignLab/out/sheet.html`，不是 app UI；如需分享该页再按 P3 修 alt。

---

## 7. 局限与未验证

- 未编译、未在模拟器/真机运行；Dynamic Type 裁剪、对比度、材料表现均由代码语义 + HIG 令牌计算推断，建议在 iPhone 17 Pro（iOS 27）与 Accessibility 字号 AX3/AX5 下复测。
- 截图来自 DesignLab HTML 生成的静态设计稿（430×932），不等同 SwiftUI 实机渲染；截图中浅色设计稿与 app 实际 V7 调色板不一致本身已作为 D-01 报告。
- hig-doctor 对 Swift 的 `ignores-safe-area`/`hardcoded-rgbcolor` 规则为 regex 启发式，已按上述标准模式排除；未把工具统计直接当作真实缺陷数。
- VoiceOver 实际朗读顺序无法从静态代码完全验证；D-07 是基于 SwiftUI accessibility 语义的静态判断。
- 本次未修改任何源码；唯一写入文件为 `docs/AUDIT-D-HIG.md`。
