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
