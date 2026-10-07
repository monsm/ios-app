# 离线锁管家 — 界面与交互设计规范

> 全离线智能门锁控制器 · SwiftUI · 最低部署 iOS 26.5 · 采用 iOS 26 平台原生设计语言。
> 本文档是设计系统的单一事实来源；代码里对应 `App/Core/DesignSystem.swift`。

## 1. 设计定位

- **场景**：用户站在自家门口掏手机开锁。单手、可能在昏暗楼道、失败 = 被关在门外。
- **推论**：状态必须**一眼可辨**（颜色 + 图形 + 文字三通道）、错误必须**就地清晰**、
  高频动作必须**单手可及**、玻璃等装饰材质**只用在辅助层级**，核心信息层保持实心高对比。

## 2. 设计令牌（`DS.*`）

### 2.1 间距 — 4/8 节奏
`xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32 · gutter 16`
> 卡片纵向间距统一用 `l 16`；两个逻辑组之间用 `xl 24` 拉开分组信号。

### 2.2 圆角
`card 18 · control 14 · tile 16 · pill 999`

### 2.3 触达
`Hit.min = 44`（iOS 最小触达目标）

### 2.4 图标尺寸
`xs 13 · sm 16 · md 20 · lg 26 · xl 44`（全 App 只用这套，避免 17/20/28 混用）

### 2.5 动效
`quick = spring(0.24, 0.85) · standard = spring(0.34, 0.80) · soft = easeInOut(0.22) · exit = easeOut(0.16)`
> 实测阻尼比无回弹（超冲 <1.5%），符合「UI 避免 bounce」的规范。
> 呼吸环等无限循环动画必须独立成视图并用 `.transaction { $0.animation = nil }` 切断隐式继承，
> 否则会和外层 `.animation(_, value:)` 抢同一批 scaleEffect/opacity 属性。

### 2.6 语义色（全部 `UIColor` 动态色，明暗双模，对比度由 `tools/contrast.js` 把关）
| 令牌 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `canvas` | F1F4F9 | 0A0E15 | 页面底 |
| `surface` | FFFFFF | 151C27 | 卡片 |
| `surfaceAlt` | F7F9FC | 1B2331 | 指标块/胶囊底 |
| `hairline` | D5DEE8 | 27313F | 分隔线（需 ≥1.2:1 才看得见） |
| `text` | 0E1726 | F1F5F9 | 主文本 |
| `textSub` | 55617A | 9DABBD | 次文本 |
| `accent` | 2F6FE4 | 4C93FF | 主行动填充 |
| `accentText` | 1D4ED8 | 93C5FD | 强调文字 |
| `onAccent` | FFFFFF | 0A0E15 | 压在填充色上的文字 |
| `ok / warn / danger` | 15803D / B45309 / B91C1C | 4ADE80 / FBBF24 / F87171 | 状态色 |

**为什么 `onAccent` 深色用近黑墨色**：深色模式下 accent/ok/warn/danger 都是高亮浅色，
白字压上去只有 3.03:1（成功态 1.73:1），改用 `#0A0E15` 墨色后全部 ≥6.3:1。

## 3. 组件

| 组件 | 说明 |
|---|---|
| `Card` | 靠 surface/canvas 明度差分层 + 极淡阴影，**不加描边**（描边只留给"选中/危险"语义） |
| `StatusPill` | 底色恒为中性，语义由图标形状 + 图标颜色双通道表达（颜色不作唯一信息载体） |
| `MetricTile` | `emphasized` 拉开数据层级：一级读数用主文本 + semibold，三级用次文本 |
| `EmptyState` | 系统 `ContentUnavailableView`，图标 + 说明 + 主动作三件套 |
| `BusyButton` | 自动菊花 + 禁用，杜绝重复触发 |
| `PrimaryActionStyle` / `SecondaryActionStyle` / `DestructiveActionStyle` | 统一圆角/内边距/最小高度 |
| `PressableButtonStyle` | 按压缩放 0.97 + 降透明，只做 transform 不改 bounds |

## 4. 中文排版专项（高收益、最易被忽略）

1. **PingFang SC 没有 Bold 字重**（最高 Semibold 600）。写 `.bold()` 会静默回退到 Semibold，
   小字号下笔画粘连 → 中文标题最高只到 `semibold`，层级差用字号承担。
2. **苹方数字是比例宽度**：`9%`→`10%` 会让整块宽度跳动 → 数字一律 `.monospacedDigit()`。
3. **中文字高大于英文**，`.caption2`(11pt) 不足以承载可读中文 → 正文下限 `.caption`(12pt)。
4. **中文不加 tracking**（汉字是等宽方块）；只有全大写拉丁（OK / BLE）才加。

## 5. 无障碍与交互

- 所有可点区域 ≥44×44pt；图标按钮必带 `accessibilityLabel`，装饰图标 `accessibilityHidden`。
- 状态用「形状 + 颜色 + 文字」三通道，色觉障碍可辨。
- 呼吸环等循环动效尊重 `@Environment(\.accessibilityReduceMotion)`：
  **减少动效 ≠ 取消动效**——保留静态指示，只是不再循环。
- 系统 `.sensoryFeedback` 只在结果态（成功/失败/警告）触发，不铺到每个交互。

## 6. 层级预算（同屏纪律）

来自 high-end-visual-design / design-taste-frontend，落地为可检查的规则：

- **阴影预算**：全 App 只有「开锁主控」（自带强调阴影）和 `Card`（极淡抬升）两级允许投影；
  同屏其余元素一律零阴影，靠 `surface` / `surfaceAlt` 明度差分层。阴影色染背景色相，
  深色模式改用 4% 提亮而不是纯黑投影。
- **描边语义独占**：`hairline` 描边只用于分隔线；「选中 / 危险」态才允许 1.5pt accent/danger 描边。
  普通卡片不加描边（加了所有卡就出自同一模板）。
- **同心圆角**：容器 18 → 内嵌块 16 → 控件 14，内圆角 = 外圆角 − 两级，形成同心节奏。
- **强调色预算**：同屏 `accent` 只出现在一处主动作；`ok/warn/danger` 只在真实状态出现，
  不作装饰。

## 7. 动效纪律

- **频率决定预算**：每天高几十次的动作（刷新、翻页）不加装饰动效；
  开锁成功属于罕见高情绪时刻，才允许一次克制的 spring 弹跳（`UnlockDial` 的 pop，
  `reduceMotion` 下跳过）。
- **可打断优先**：按压/悬停态用 `isPressed` 驱动的 spring，可从当前值起跳。
- **只动 transform / opacity**：不动画 `frame` / `padding` / 布局属性。
- **无限循环动画必须独立成视图**，并用 `.transaction { $0.animation = nil }` 切断
  与外层 `.animation(_, value:)` 的属性争用（`UnlockPulseRing`）。

## 8. 机器可验证的闸门（`node tools/*.js`，CI 全跑）

| 闸门 | 把关什么 |
|---|---|
| `swiftcheck.js` | 括号/字符串平衡（无本地 Swift 编译器时的静态第一道闸） |
| `contrast.js` | 从 `DesignSystem.swift` 解析 12 个色令牌的明暗取值，按 WCAG 2.1 核算 42 条断言 |
| `dynamictype.js` | 静态查 `.system(size:)` 用于 Text、固定高度约束、PingFang `.bold`、可点区 <44pt |

## 9. 尚未闭环的验证

- **15 个差分测试**：GitHub runner 镜像无 iOS 模拟器设备且禁 `simctl create`（`SimError 403`），
  云端只做 `build-for-testing` 编译校验。需在有模拟器的 Mac 上跑（命令见工作流注释）。
- **可视化验收**：需要启用 `ios-simulator` 插件（`ios-dev` skill）才能在模拟器上截图走查。
  深色对比度与 Dynamic Type 最大字号目前只能靠上面的静态闸门 + 真机侧载验证。