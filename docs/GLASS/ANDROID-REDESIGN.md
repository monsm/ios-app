# ANDROID-REDESIGN —— Android 端令牌层 + 4 屏重做记账

> 作者：android-inventory（teammate）· 任务卡 task-4
> 写入范围：`KfTheme.kt`、`Tokens.kt`、`MainActivity.kt`（+ 本文件）。
> **未碰**：`BleUnlocker.kt` / `KfProtocol.kt` / `AutoOpenKit.kt` / `LockStore.kt` 的任何一行；`SignalArrow.kt` 只改颜色取值来源（算法零改动）；iOS 侧 .swift 一行未动。
> **未编译**。本机无 java/javac/gradle/kotlinc（E1 实测），本地无 Compose 编译通道。本文所有"应该没问题"的判断都是**静态自查**，不等于编译通过。

---

## 0. 开工基线（E1）

```
$ node tools/kotlinshadow.js      -> exit 0 / 0 FAIL / 末行「全部通过」   (改动前)
$ node tools/kotlinshadow.js      -> exit 0 / 0 FAIL / 末行「全部通过」   (全部改动完成后, 含本轮跨端修正)
$ node tools/kotlinlocal.js --quiet -> exit 0
    本地 Kotlin 编译: 跳过 (缺 java / kotlin-compiler-embeddable / kotlin-stdlib / android.jar)
    判不了 ≠ 不合格: 这条分支退 0。
```

**闸门解读（重要，别误读成"编译过了"）**：
- `kotlinshadow.js` 是通过**正则读源码**做字节面对拍，其中 A8 的 21 条断言直接把 `MainActivity.kt` 当输入。它证明的是「自动开锁状态机那八处源码形状还在」，**不证明任何一行 Compose 能编译**。
- `kotlinlocal.js` 明说只编 4 个非 UI 文件，且本机缺工具链 → 它退 0 是"跳过"，不是"通过"。

---

## 1. 逐屏改动记账

| 屏 | 改了什么 | 依据规范哪一节 | 未验证项 |
|---|---|---|---|
| **全局 / 画布** | ①根背景从 `Brush.verticalGradient(bgTop -> bgBottom)`（#0A0C10 -> #141A22）改成纯黑实底 `colors.canvas`。②页边距从硬编码 `horizontal = 24.dp` 改成 `KfTokens.Space.gutter`（14dp）；上留白从 28dp 改成 `KfTokens.Space.pageTop`（40dp）。 | §0 总则 1「黑色是画布，不是背景色」；G1「页面底 #000000」；验收 A5；§5.1 `s5=14`、`s8=40` | 14dp 页边距在窄屏/大字号下是否显挤。**未渲染，判不了** |
| **全局 / 色板** | `KfColors` 从 9 字段扩到 **18 字段**，字段名按角色重命名（`bgTop/bgBottom/ink/inkSub` → `canvas/text/textSub/…`）。深浅双档逐值镜像 iOS `App/Core/Theme.swift` 的 `XPalette`（见 §6 对账表，18/18 一致）。 | §3.1 应用体四档表面 + 两档描边；§3.3 五档文字 + 镜面；§3.4 语义色；§13.4（浅色档保留为**非默认等价映射**） | 18 个字段**全部有消费点**（本轮已清零，见 §5） |
| **全局 / 令牌** | `KfTokens` 重写并**收紧到消费点驱动**：`Space` 9 成员 / `Radius` 2 成员 / `Hit` 2 成员 / `Icon` 2 成员，**共 15 个，零引用成员 0 个**。每个成员注释里写明「= iOS 的哪个成员 + 行号」；被删掉的成员与理由写在文件头。 | §5.1 间距；§5.2 圆角；§7.7「视觉行高 20 与触达 48 是两个数」；§10 图标 | 无零消费；未来要用需连消费点一起加 |
| **S1 空态屏** | ①改三段式：二维码角框(96dp) → 标题 14 Semibold → 说明 12 Regular，间距 10 / 4，上下各 24。②文案按 §12 改成**原因**：`还没有绑定门锁` → `本机还没有钥匙`。③主按钮从 `PillButton`（圆角写死 50 / 高≈46dp）换成 `PrimaryButton`：**accent 底 + onAccent 字 + r12 + 48dp + 按下 0.98 缩放/0.82 透明度 + specular 顶部高光**。 | §7.17 EmptyState；§12「空态标题说原因不说状态」 | ①角框 96dp vs 规范「图标 28pt」—— **主动偏离**，见 §3；②accent 底按钮与 **iOS `XPrimaryButtonStyle`（Components.swift:263-292）同一做法**，不是自创 |
| **S2 主解锁屏** | ①锁名 26sp Light → **30sp Bold / 字距 -0.4**。②MAC 行 `inkSub@0.75`（3.83:1）→ 12sp `textTertiary`。③**箭头降级**：208dp → 仪表行里 72dp 指示器，主视觉只剩圆盘。④状态行 15sp Semibold，配色改 `danger/ok/text` 语义色。⑤新增 `SignalMetric` 仪表行（7.7：色点 8 + 名称 14 + 值 14 SB + dBm 11）。⑥trace 行 `inkSub@0.55`（2.73:1）→ `textTertiary`。⑦圆盘轨道改 `verticalGradient(surfaceSunken -> surfaceAlt)`；**进度弧改 sweepGradient 并用 `rotate(-90f)` 把渐变 0 位对齐到 12 点**（见 §4-3）；按下 0.972/100ms → 0.97/120ms。⑧圆盘加 `contentDescription`。 | §9/§14-13「一屏只能 1 个主角」；§7.1；§4.2；§7.7；§7.8「环必须渐变或分色」；§11.1「按压缩放 0.12s 1→0.97」；§13.5 | ①72dp 箭头是否还看得清填充 —— **未渲染**；②`rotate` 后弧的观感 —— 算式已写进注释，**仍需真机确认** |
| **S3 设置抽屉** | ①贴底 → **垂直居中 + 上下 48dp + verticalScroll 兜底**（7.0.6 plain 卡骨架）。②遮罩 `Color(0xB3050709)` → `canvas@0.72`。③新 `SettingsCard`，内部节奏照 7.6：卡头→标题 6 / 标题→控件 12 / 控件→值 2 / 值→分隔线 14 / 分隔线→动作 12。④加 `hairline` 全宽分隔线 + **`hairlineStrong` 1dp 卡片描边**（玻璃不可用时的退路）。⑤「完成」36dp → `TextButton + heightIn(48)`。⑥「重新扫码」「解绑」28dp → `Box + heightIn(48)`。⑦整卡消费点击（点空白不关面板）。⑧解绑色 → `danger`。 | §7.0.6 plain 卡；§7.6 纵向节奏表；§6.3「浮层 = 玻璃 + 0.5pt 描边」；§13.2；§7.20.3 | ①**没有真玻璃**（Compose 的 `Modifier.blur` 不采样背景），当前是 72% 遮罩 + 实色卡 + 1dp 描边，**已知降级**，见 §3 偏离-2；②`verticalScroll + Center` 超屏表现未验证 |
| **S4 AirTag 查找层** | ①单层纯色 → **三停 `verticalGradient`**（#003D12 / #00260A / #001505，范式 `sportsGradient`）。②**删掉米数**：`distanceMeters()` 本屏不再调用；新 `distanceTier(fill,rssi)` 输出「还在找/远/有点远/近/很近」。③emoji（✕/🔊/🔇）→ 自绘矢量 `GlyphButton`。④箭头颜色由主题解析。⑤上留白 = `pageTop + l` = 56dp（令牌推出）。⑥距离字 34sp → **36sp Bold / -0.6**（`display` 档）；方向字 26sp → **19sp Bold**（`title2` 档）。 | §3.5 `sportsGradient`；§14-24「全屏彩色底必须亮头+暗板两层」；§14-18「禁止 emoji 当图标」；§4.2；**iOS `FindArrowLayer.swift:13`「不显示米数」**（lead 拍板：Android 跟这条） | 三停底白字对比度：**12.53 / 16.39 / 18.93**（E1 实算，全达标）。`GlyphButton` 手绘路径的实际观感**未渲染** |
| **D1 换绑确认** | ①`AlertDialog` 加 `shape = RoundedCornerShape(24dp)`。②标题 `Medium` → `SemiBold`。③确认按钮 `accent` → **`danger`**（破坏性动作）。 | §5.2 `rCard=24`；§7.20.3 | 文案未改（已合格） |
| **SignalArrow.kt（只改取值来源）** | 默认参数 `okColor: Color = KfDarkColors.ok` → `okColor: Color? = null`，函数体解析 `okColor ?: LocalKfColors.current.ok`；`outlineColor` 同理。调用点改用解析后的局部量。**算法（signalFill / relativeBearing / peakUpdate / distanceMeters / drawAirTagArrow 几何）一行没改。** | §13.4 主题必须真的控制颜色 | 两个调用点都显式传色，null 分支当前未走到 —— 它只是把默认值从"写死暗色"变成"跟主题" |

---

## 2. 令牌层逐值对账（照抄 iOS，未发挥）

### 2.1 色板（深色档 = 范式本体）
逐值见 **§6 对账表**（19 行 × 明暗两档 = 38 个值，18 一致 / 1 有意不镜像 / 0 不一致）。

### 2.2 间距 / 圆角 / 触达 / 图标（15 个成员，全部有消费点）

| KfTokens 成员 | 值 | iOS 对应 | 消费点（MainActivity.kt） |
|---|---|---|---|
| Space.xs | 4.dp | `XSpace.xs` Theme.swift:173 | 三处 Spacer |
| Space.s | 8.dp | `:174` | SignalMetric 色点间距、动作行 |
| Space.m | 12.dp | `:175` | S2 区块间距、SettingsCard 分隔线上下 |
| Space.l | 16.dp | `:176` | 圆盘下间距、卡片外边距 |
| Space.xl | 24.dp | `:177` | 齿轮内边距、动作行水平间距 |
| Space.gutter | 14.dp | `:182` | 根 Column 左右 |
| Space.section | 28.dp | `:187` | S4 左/底/右内边距 |
| Space.pageTop | 40.dp | `:189` | 根 Column 顶部、S4 标题区 |
| Space.card | 16.dp | `:192` | SettingsCard 内边距 |
| Radius.card | 24.dp | `XRadius.card` `:208` | SettingsCard、AlertDialog |
| Radius.control | 12.dp | `XRadius.control` `:214` | PrimaryButton |
| Hit.min | **48.dp** | iOS 是 `XHit.min=44`（**pt**，`:230`） | 所有可点元素 |
| Hit.metricRow | 20.dp | — | SignalMetric 视觉行高 |
| Icon.md | 20.dp | `XIcon.md` `:237` | GlyphButton 字形画布 |
| Icon.lg | 26.dp | `XIcon.lg` `:238` | GearButton 画布 |

**48dp ≠ 44pt**：两个单位、两个数，写死在 `KfTokens.Hit` 的注释里，不许合并。

### 2.3 对比度实测（E1：node 实算 WCAG，不是引用）

深色档（本轮变化的三处已重算）：

| 组合 | 比值 | 判定 |
|---|---|---|
| text on canvas / surface | **21.00 / 17.01** | AAA |
| textSub on canvas / surface | **6.36 / 5.16** | AA |
| textTertiary on canvas / surface / surfaceSunken | **6.13 / 4.97 / 5.55** | AA（三底全过 → 可承载信息） |
| textQuaternary on surface | **3.16** | 只许装饰 |
| textFaint on surface | **1.81** | 只许装饰 |
| accent / accentText on surface | **6.26 / 7.79** | AA |
| **onAccent on accent** | **6.97** | AA（白字压铜只有 2.2:1，所以用墨色） |
| ok / warn on canvas | **10.39 / 10.22** | AA |
| **danger #FF4A40 on surfaceAlt** | **4.63** | AA（旧 #FF3B30 只有 4.35 —— 这就是 iOS 改色的原因） |
| danger on surface / canvas | **5.11 / 6.31** | AA |
| hairline on surface | **1.51** | 分隔线（非文字） |

浅色档（本轮变化的三处已重算）：

| 组合 | 比值 |
|---|---|
| text on canvas | **15.25** |
| textSub on canvas / surface | **6.74 / 7.52** |
| **textTertiary #5E5E63 on surfaceSunken** | **4.82**（旧 #646469 只有 4.40） |
| textTertiary on canvas / surface | **5.78 / 6.45** |
| accent / accentText on surface | **5.39 / 5.74** |
| onAccent on accent | **5.39** |
| ok on surface | **6.30** |
| **warn #9A4708 on surfaceSunken** | **4.79**（旧 #A94E08 只有 4.15） |
| warn on surface / canvas | **6.40 / 5.74** |
| danger on surface / canvas | **6.54 / 5.86** |
| **hairline #C8C8D2 on surfaceSunken** | **1.24**（旧 #D0D0D8 只有 1.15，低于 1.2 机检阈值） |

**结论**：本次用到的**每一组文字/背景**都 ≥ 4.5:1。INVENTORY-ANDROID §3.1 里那 5 处跌破 4.5 的派生灰（`inkSub@0.55/0.60/0.70/0.75`）**已全部消除** —— 做法是删掉"靠叠 alpha 造第三级灰"这条路，改用真正的 `textTertiary` 令牌。

---

## 3. 主动偏离规范的登记（2 条）

> ⚠ **这两条目前只记在本文件里，还没有并进仓库的统一偏离台账 `docs/GLASS/DEVIATIONS.md`。**
> 那个文件是 lead 在维护的（§1 明暗双模 / §2 Tab 5 项 / §3 hairline 实色 都已在册），我没有写权限。
> **请 lead 决定是否收进 §6/§7** —— DEVIATIONS.md 开头写得很清楚：「下一个人看到代码与规范不符，会以为是漏改，然后『修』回去」。
>
> （原「偏离-3 主按钮白底黑字」**已撤销**：那是照字面抄范式 7.0.6，而 7.0.x 是展示壳组件；
> 本 App 没有展示壳层，iOS 侧已删 `shellCard` 并改用 accent 底 —— 本端已跟随，见 §6。）

| # | 偏离 | 规范原文 | 我的做法 | 理由 | 什么时候该推翻 |
|---|---|---|---|---|---|
| 偏离-1 | 空态用 96dp 二维码角框，不是 28pt 图标 | §7.17「图标 28pt + 标题 14 Semibold + 说明 12 Regular」 | 标题/说明按规范；图标位保留 96dp 自绘角框 | 角框承担「取景框」语义（告诉用户这里要扫一张码），不是装饰图标。换成 28pt 图标会丢掉"扫码"这个唯一动作的视觉锚点 | 若后续空态不再以扫码为唯一出路（例如加了"从备份恢复"），角框就该降级成图标 |
| 偏离-2 | S3 浮层是 72% 不透明纯黑遮罩 + 实色卡片 + 1dp 描边，**不是玻璃** | §6.2 玻璃配方 / §6.3「浮层 = 玻璃 + 0.5pt 描边」 | `canvas@0.72` + `surface` 实卡 + `hairlineStrong` 描边 | **技术限制**：Compose 的 `Modifier.blur` 只模糊自身，不能采样背后内容；真玻璃需 `RenderEffect`(API 31+) 或 `RuntimeShader`，本轮无编译通道、无法验证。范式同时禁止"实色 + 投影"，所以**没有加投影**，改用 1dp 描边把卡片从遮罩上分出来 | API 31+ 可用了要第一时间换成真玻璃；或引入现成的 blur 库并经真机验证 |

---

## 4. 未做 / 做不到的（诚实清单）

| # | 项 | 状态 | 原因 |
|---|---|---|---|
| 1 | **编译验证** | **未做** | 本机无 java/javac/gradle/kotlinc（E1）。代码只经过：① `kotlinshadow.js` 正则闸门 ② 括号/引号配对自查（code-only，结果 0/0）③ import 双向核对（0 未用）④ `KfTokens`/`KfColors` 符号存在性核对（0 缺失 / 0 零引用）⑤ 对比度实算。**四条都不等于编译通过** |
| 2 | **渲染验证** | **未做** | 无模拟器无真机（adb NOT FOUND）。所有"看起来会怎样"都是推断 |
| 3 | 圆盘进度弧 `sweepGradient` 起点对齐 | **已按 `rotate(-90f)` 对齐，仍未渲染验证** | iOS 用 `AngularGradient(startAngle:-90)` 把 0 位对齐 12 点；Compose 的 `Brush.sweepGradient` 0 位固定在 3 点且没有 startAngle 参数。已用 `rotate(degrees = -90f, pivot = 圆心)` 包住 `drawArc`，让渐变与弧同起点（等价于 iOS 的写法）。**算式写进注释，观感待真机** |
| 4 | 箭头仍保留无限摆动 + 3D 视差 | **未动** | 这是 `SignalArrow.kt` 的**动效算法**，任务卡限定"只许改颜色与尺寸常量的取值来源"。规范 §11.2 明令禁止"旋转 / 3D 翻转 / 视差"，**这条留着违规**，需要单独一张卡（改法：删 `sweep` 无限过渡与 `rotationX/rotationY`，只留 `rotationZ = bearing`） |
| 5 | 触觉密度 | **未动** | 仍只有 `MainActivity.kt:201` 一处（开锁结果）。§11.4 要求四类事件都有反馈；扩 API 要改 `Haptics.kt` —— **不在本次写入范围** |
| 6 | 浅色档整体观感 | **未验证** | 色值全部镜像 iOS 且对比度实算达标，但没渲染过。S4 查找层三停深绿在浅色档下仍是深绿（有意：查找层是沉浸态，不跟随主题） |
| 7 | `AndroidManifest.xml` / `themes.xml` 窗口底色 | **未改** | 仍在写入范围外。`themes.xml:4-7` 还是 `#0A0C10`，与新纯黑画布**不一致**（启动瞬间会闪一下深灰） |
| 8 | 安全区 / edge-to-edge | **未做** | 全仓 `WindowInsets` 命中 0。仍靠 `pageTop = 40dp` 硬留白，有状态栏的机型上会被吃掉一部分。需 `enableEdgeToEdge()` + `WindowInsets.systemBars` |

---

## 5. 遗留 / 需要下一张卡

| # | 项 | 为什么留 | 建议 |
|---|---|---|---|
| 遗留-1 | `res/values/themes.xml` 窗口底色 `#0A0C10` | 不在写入范围 | 改成 `#000000`。一行改动 |
| 遗留-2 | 零消费令牌 | **本轮已清零**：`KfTokens` 15 个成员全有消费点；`KfColors` 18 个字段全有消费点（`specular` 接给主按钮高光、`hairlineStrong` 接给卡片描边；`surfaceChip` 直接删掉） | 保持这条纪律：加成员必须同时加消费点，或写清"留给哪件还没做的事" |
| 遗留-3 | `SignalArrow.distanceMeters()` 现在**零调用** | 纯函数，注释说与闸门对拍（实际 `kotlinshadow.js` 里没有这条断言） | 保留并注明"当前无调用点"，或下一轮删掉 |
| 遗留-4 | 解绑仍**无二次确认** | 需新增状态 + Dialog，属结构改动 | 高优先。参照 iOS `LocksPage.swift:142-152` |
| 遗留-5 | 开锁仍是**单击**（iOS 是按住 1.05s） | 改交互 = 改 `doUnlock` 触发路径，与 A8 的 busy 断言耦合 | 单独一张卡，改完立刻跑闸门 |
| 遗留-6 | `KfColors` 未镜像 iOS 的 5 个成员（`surfaceChip` / `kindFp` / `kindTemp` / `kindOtp` / `qrQuietZone`） | 本端确实没有对应功能（无 StatChip / 无凭证工坊 / 不渲染二维码） | 保持不镜像。**加回来之前先确认本端真有那个组件**，否则就是凭空造成员 |

---

## 6. 与 iOS 的最终对账表（每次改令牌都要重跑）

**数据来源**：iOS `App/Core/Theme.swift:54-158` 的 `XPalette`（22 个成员）× Android `KfTheme.kt` 的 `KfColors`（18 个字段）× 明暗两档。
**生成方式**：从两个文件里正则解析真实值后比对（不是手抄）。脚本一次性跑、不落盘。

| 字段 | iOS 深色 | Android 深色 | iOS 浅色 | Android 浅色 | 判定 | 备注 |
|---|---|---|---|---|---|---|
| `canvas` | #000000 | #000000 | #F2F2F7 | #F2F2F7 | ✅ 一致 | `App/Core/Theme.swift:54` |
| `surface` | #1C1C1E | #1C1C1E | #FFFFFF | #FFFFFF | ✅ 一致 | `App/Core/Theme.swift:58` |
| `surfaceAlt` | #24242A | #24242A | #E9E9EE | #E9E9EE | ✅ 一致 | `App/Core/Theme.swift:60` |
| `surfaceSunken` | #101012 | #101012 | #DEDEE6 | #DEDEE6 | ✅ 一致 | `App/Core/Theme.swift:63` |
| `surfaceChip` | #232326 | — | #E4E4EA | — | ⏸ 不镜像（有意） | 本端无 StatChip 组件（范式 7.2 的顶部胶囊只存在于 iOS 设备页） |
| `hairline` | #3A3A40 | #3A3A40 | #C8C8D2 | #C8C8D2 | ✅ 一致 | `App/Core/Theme.swift:73` |
| `hairlineStrong` | #4A4A52 | #4A4A52 | #ADADB8 | #ADADB8 | ✅ 一致 | `App/Core/Theme.swift:75` |
| `text` | #FFFFFF | #FFFFFF | #1C1C1E | #1C1C1E | ✅ 一致 | `App/Core/Theme.swift:79` |
| `specular` | #C8C8D4 | #C8C8D4 | #FFFFFF | #FFFFFF | ✅ 一致 | `App/Core/Theme.swift:81` |
| `textSub` | #8D8D93 | #8D8D93 | #54545A | #54545A | ✅ 一致 | `App/Core/Theme.swift:83` |
| `textTertiary` | #8A8A92 | #8A8A92 | #5E5E63 | #5E5E63 | ✅ 一致 | `App/Core/Theme.swift:88` |
| `textQuaternary` | #6A6A6E | #6A6A6E | #86868B | #86868B | ✅ 一致 | `App/Core/Theme.swift:92` |
| `textFaint` | #46464A | #46464A | #AEAEB2 | #AEAEB2 | ✅ 一致 | `App/Core/Theme.swift:94` |
| `accent` | #D98B45 | #D98B45 | #9C5A22 | #9C5A22 | ✅ 一致 | `App/Core/Theme.swift:124` |
| `accentText` | #E8A05C | #E8A05C | #8F5A28 | #8F5A28 | ✅ 一致 | `App/Core/Theme.swift:127` |
| `onAccent` | #14100A | #14100A | #FFFFFF | #FFFFFF | ✅ 一致 | `App/Core/Theme.swift:133` |
| `ok` | #30D158 | #30D158 | #1B6E38 | #1B6E38 | ✅ 一致 | `App/Core/Theme.swift:147` |
| `warn` | #FF9F0A | #FF9F0A | #9A4708 | #9A4708 | ✅ 一致 | `App/Core/Theme.swift:151` |
| `danger` | #FF4A40 | #FF4A40 | #B3261E | #B3261E | ✅ 一致 | `App/Core/Theme.swift:158` |

**汇总：18 一致 / 0 不一致 / 1 有意不镜像。**

**iOS 有、Android 不镜像的 5 个成员及理由**：

| iOS 成员 | 为什么不镜像 |
|---|---|
| `surfaceChip` #232326 / #E4E4EA | 本端没有 StatChip 组件（范式 7.2 的顶部胶囊只在 iOS 设备页出现） |
| `kindFp` / `kindTemp` / `kindOtp` | 凭证工坊四类色；本端没有凭证功能 |
| `qrQuietZone` | 本端只**扫**二维码，不渲染 —— 渲染在 iOS 的 `ShareToAndroidView` |

**Android 有、iOS 没有的成员**：**0 个**。（`shellCard` / `shellTextPrimary` 上一版有，本轮已按 iOS 侧同步删除 —— 本 App 没有展示壳层，见 `docs/GLASS/DEVIATIONS.md §5`。）

---

## 7. 改了哪几个文件（完整清单）

| 文件 | 改动量 | 性质 |
|---|---|---|
| `android-app/.../KfTheme.kt` | 79 行 → **129 行** | 重写。9 字段 → 18 字段，两档值全部镜像 iOS |
| `android-app/.../Tokens.kt` | 36 行 → **95 行** | 重写。删掉三处假注释；收紧到 15 个**全部有消费点**的成员 |
| `android-app/.../MainActivity.kt` | 914 行 → **1207 行** | 前 333 行（import 区 + 自动开锁状态机 + BackHandler）**逐字节保留**，仅删 1 个未用 import + 加 7 个新 import。334 行之后全部重写 |
| `android-app/.../SignalArrow.kt` | 225 行 → **231 行** | 只改两个默认参数的类型与取值来源。**算法零改动** |
| `docs/GLASS/ANDROID-REDESIGN.md` | 本文件 | 记账 |

**没碰**：`BleUnlocker.kt`、`KfProtocol.kt`、`AutoOpenKit.kt`、`LockStore.kt`、`Haptics.kt`、`AndroidManifest.xml`、`res/**`、`*.gradle.kts`、`tools/**`、全部 `App/**/*.swift`。

---

## 8. 闸门与静态自查记录（E1）

```
# 改动前基线
$ node tools/kotlinshadow.js   -> 全部通过 (exit 0)

# 全部改动完成后 (含本轮跨端修正)
$ node tools/kotlinshadow.js   -> 全部通过 (exit 0), 0 条 FAIL
$ node tools/kotlinlocal.js --quiet -> exit 0 ("跳过", 缺工具链)

# 静态自查 (脚本都在 run_code 里跑, 无输出文件)
花括号深度扫描(code-only, 跳过字符串/注释/raw string)  -> MainActivity 0/0, SignalArrow 0/0, KfTheme 0/0, Tokens 0/0
圆括号配对(code-only)                                  -> 同上 全部 0/0
未使用 import 扫描                                     -> 0 条
KfTokens.X.Y 引用存在性                                 -> 15 个引用全部存在, 0 缺失, 0 零引用
colors.X 引用 vs KfColors 声明                          -> 18 声明 / 18 消费, 0 缺失, 0 零引用
对比度实算(WCAG)                                       -> 40+ 组, 文字对全部 >= 4.5:1
与 iOS 令牌对账                                        -> 18/18 一致, 0 不一致, 1 有意不镜像
```

**A8 断言为什么没红**：改动全部落在 `MainActivity.kt` **第 334 行之后**。前 333 行里那八处被正则锁住的形状（`armed = AutoOpenKit.rssiSample(prevArmed = armed, rssi = r)`、`if (!armed) { fired = false; prewarmStarted = false }`、`if (!armed || fired) return`、`AutoOpenKit.coolReady(lastAuto, now)`、`LaunchedEffect(proximity, lock?.mac, busy, warming, foreground)`、`if (!proximity || busy || warming || !foreground) return@LaunchedEffect`、`unlocker.release()`、`unlocker.prewarm(`）逐字节未变。

---

## 复核 (2026-10-23)：Android 侧已核项清单

| 维度 | 结论 |
|---|---|
| 颜色令牌 | 16 字段与 iOS `XPalette` 逐值相同（`tokendrift` 机检）|
| 数值令牌 | Space / Radius / Icon **13 个同名成员逐值相同** |
| 字阶 | `Type` 11 档与 iOS `XText` 逐值同源（caption2 与 caption 合并为一档，规范里同为 11）|
| 间距使用 | 页边距 `gutter` / 区块 `section` / 页顶 `pageTop` 全走令牌；**零硬编码同值 dp** |
| 触达 | `KfTokens.Hit.min = 48.dp`（Android 最小触达）；扫全仓可点元素，**无 <48dp** |
| 破坏性操作 | 解绑走 AlertDialog，正文说清三件事（本机会删什么 / 无法找回 / 锁本体不受影响）|
| 空态 | `EmptyState` 有图标+标题+说明+动作 |
| 深色单模 | 无浅色档，`KfTheme(dark:)` 参数保留但不生效（§13.4）|

### 仍缺 / 待定

| 项 | 状态 |
|---|---|
| 玻璃浮层 | Compose 无等价 `.ultraThinMaterial`；手搓模糊在半透明浮层上会糊。**待你拍板** |
| 96dp 扫码取景框 | 规范 §7.17 给 28pt 图标，但本端它是**可点的主操作**。**待你拍板** |
| 骨架屏 | 本端数据全在本地同步读，没有「加载中」这一段 —— 不适用 |
