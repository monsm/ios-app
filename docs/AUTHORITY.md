# 权威顺序（2026-10-24 用户裁定）

> 「**规范有时候可能是错的，以 html 的视觉审美为标准！**」

## 一句话判据

| 维度 | 权威来源 |
|---|---|
| 视觉审美 / 令牌数值 | **tools/proto/tokens.css（HTML 原型）** |
| 功能与业务逻辑 | iOS / Android 实际 App |
| 仓库规范文档 | 仅参考；与 HTML 冲突时**以 HTML 为准** |

## 已按此口径改判据的四处

| 令牌/项 | 仓库规范 | HTML | 采纳 | 影响 |
|---|---|---|---|---|
| `surfaceAlt` | `#24242A` | `#202022` | **HTML** | iOS `XPalette` + Android `KfColors` + `tools/contrast.js` 规范值表三处同步 |
| `XRadius.chip` | 14（§7.2 实测 13.3）| **22** | **HTML** | 全站顶部胶囊从「圆角矩形」变成「胶囊」 |
| 卡片面材质 | 平色 `#1C1C1E`（§6.3）| 平色 `#1C1C1E` | 一致 | App 此前用渐变（与两边都冲突），已回退 |
| 二级页标题 | `.inline`（标题只在导航栏）| **页内 `.h1` + `.sub`** | **HTML** | 31 页补回页内大标题 |

## 31 道闸门分类（各管哪一层）

| 层 | 闸门 | 测的对象 |
|---|---|---|
| 协议正确性 | golden / shadowdiff | BLE 核心 JS↔Swift 字节级差分（**与 UI 无关**，UI 改动不影响它们）|
| 编译形状 | swiftcheck / swiftshape / swiftsyn / apicheck / apisig / declcheck | 括号/参数标签/成员存在/重复声明 |
| 风格令牌 | tokendrift / contrast / glassaudit / dynamictype / uicoverage | 三端同源/对比度/自绘预算/AX 字号/缝覆盖 |
| 内容基线 | subtitlesync / reviewsync / protosweep / copynum / changelogcheck / keyspace | 副标题/验收页/原型完整性/文案数/变更记录 |
| 导航 | destmap / entrygate / sheetcover | 路由表/入口动作/sheet 收摊 |
| Android | kotlinbalance / kotlinshadow | 字面量/字阶 |

## 「HTML 为准」的精确含义（第 80 轮补充）

HTML **内部**也会矛盾。chip 圆角的三层冲突实例：

| 层 | 值 | 来源 |
|---|---|---|
| `.chip` CSS 规则 | 高 56 / **r18**，注释"不是全圆胶囊" | 渲染事实（用户看到的）|
| `--r-chip` 变量 | 22 | 变量声明（可能没被 .chip 引用/已过期）|
| 仓库规范 §7.2 | 13.3 | 更早的实测 |

**裁决规则：渲染规则 > 变量声明 > 规范文档。**

⚠ 补充实证：`--r-chip: 22` 在两个原型的 CSS 里**零使用者**（死变量）——
HTML 的 chip 实际写死 `border-radius: 18px`。第 59 轮按这个死变量把 iOS 改成 22 是误读。
死变量不能当"HTML 的意愿"引用；这也是"渲染规则 > 变量"的又一实证。 理由：渲染规则连同它的实测注释
才是"用户在屏幕上看到的东西"；变量可能改了值没改引用。据此 iOS `XRadius.chip`
定为 **18**（Android 等比 13dp）——第 59 轮按变量改成 22 是误读，本轮纠正。

## 闸门有效性实证（2026-10-24）

判断"一把尺子还有没有用"的方法不是看它绿不绿，而是**注入坏值看它响不响**：

| 闸门 | 注入测试 | 结果 |
|---|---|---|
| `tokendrift`（色板/字阶两端同源）| 临时把 Android `surfaceAlt` 改回 `0x24242A` | ✅ 立即报 MISMATCH，还原后恢复 |
| `SecFmt.__bogus`（apicheck 自检）| 注入不存在的成员符号 | ✅ 报出（仓内既有自检）|
| `subtitlesync`（S1-S4 基线对账）| 基线表漏一行/副标题含数字 | ✅ 两个方向都报 |
| `swiftmember.js`（成员精确边界）| 三次 CI 失败的沉淀：'下一个 private var' 边界法在 func 成员处漏判（c6c802a/6270b60 两次失败）→ 深度归 0 法 + 计数验证 + 读回，一次成功 | ✅ 自测三成员边界全对 |
| `swiftshape` 正控 | 12 种坏形状 | ✅ 各开火一次 |

## 原有闸门仍然有效

`contrast.js` 里 `danger` / `textTertiary` 那两次历史事故的教训**不变**：
把令牌往「偏离规范且**没有 HTML 依据**」的方向改，仍然要拦。
本条只把权威来源从规范文档换成 HTML —— **不是取消锁定**。

## 全量 token 对账（HTML ↔ iOS ↔ Android）

| 类别 | 项数 | 一致 |
|---|---|---|
| 画布/表面/文字/语义色 | 12 | 12 |
| 间距（gutter/pageTop/section/titleToCard/align/rowGap/cardPad/xs..xl）| 12 | 12 |
| 圆角（card/cardLg/inner/chip/min）| 5 | 5 |
| 字号（display..caption + hero）| 11 | 11 |

**结论：设计令牌层已与 HTML 逐值同源。剩余差异只在「页面结构内容」，不在令牌。**

## 三端字号档对账（2026-10-24 复核）

| HTML --f-* | iOS XText / DSFont | Android Type | 值 |
|---|---|---|---|
| display / display-num | display / displayNumber | display / displayNumber | 36 / 56 |
| large | largeTitle | largeTitle | 30 |
| title2 / title3 | title2 / title3 | title2 / title3 | 19 / 18 |
| headline / body | headline / body | headline / body | 16 / 16 |
| subhead | subheadline | subhead | 14 |
| footnote / caption | footnote / caption(+caption2) | footnote / caption | 12 / 11 |
| （无）| hero / small | hero / small | 44 / 13 |

**三端 12 档逐值相同**（含六图补档 hero=44 与 small=13 —— 它们是 HTML 里 44px 大数字与
13px 卡内副文的档位化，Android/iOS 的 tokendrift 闸门守着不许漂移）。
另有页面级排版逐值核对：XScreen 大标题 = .h1（30 Bold / -0.4 / 1.15）✓，
副标题 = .sub（16 / textSub）✓。
