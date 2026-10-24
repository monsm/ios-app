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
