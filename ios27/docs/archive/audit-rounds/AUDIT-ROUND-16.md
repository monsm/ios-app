# AUDIT-ROUND-16 · 第十六轮：同一个盲区扫干净 —— 又 18 个死令牌

> 执行日期：2026-11-01 08:50 → 09:25（+08:00）
> 起点 `ca8c0b1` → 终点 `dcb0505`
> CI：build `errors=0`

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **18 个死令牌**（1 个动效 + 17 个布局） |
| 累计死令牌清理 | 24 个（第 14 轮 1 + 第 15 轮 3 + 本轮 18 + 2 个早期） |
| 闸门 | 20 / 20；死令牌检查覆盖 `C` / `F` / `M` 三个枚举 |

---

## 1. 把"逐令牌查消费"从三个枚举扩到全部

前两轮分别修了颜色（`C.blueCursor`）与字号（`F.title20/cardBodyStrong/icon22Medium`）。
本轮对 `V7Tokens.swift` 里**所有** token 枚举做同样的逐令牌扫描，又找到 18 个零消费：

| 枚举 | 死令牌 |
|---|---|
| `M`（动效） | `exit`（easeOut 0.18） |
| `S`（间距） | `screenH` `cardGap` `statValueGap` |
| `Gauge` | `gapEnd` |
| `Segmented` | `numberSize` |
| `Tab` | `selectedRadius` |
| `List` | `chevronSize` `badgeSize` |
| `Metric` | `miniCardW` `miniChartW` |
| `Page` | `sectionGap` `headerGap` `bodySpacing` `cardHeaderGap` `dividerY` `statTop` `sparklineH` |

### 为什么 `M.exit` 比死颜色更值得在意

一个没被用的颜色只是"多了一个色号"；一个没被用的**动效**暗示
"这里设计过一个退场过渡，但没实现"。后来的人看到 `V.M.exit` 会以为
退出动画有既定节奏、于是照着它写新动画 —— 而它从来没在任何地方生效过。

### 删除前先排掉"文件内部使用"

第一遍扫描报了 22 个，其中 5 个是**误报** —— 它们被同文件里的派生令牌使用：

| 令牌 | 实际用途 |
|---|---|
| `S.densityScale` | 被 `d()` 读（第 13 轮接的密度缩放） |
| `R.factor` | 被 `V.R.card/mini/action/…` 六处派生 |
| `Ring.trackOpacity` | 被 `Ring.track(for:)` 读 |
| `Page.bodyLine` / `bodyLineGap` | 被同枚举其它令牌派生 |

排掉这 5 个后剩 **17 个**真死（外加 `M.exit` 共 18）。

> 方法上的要点：**"零外部消费"不等于"零消费"**。令牌系统里派生令牌是常态，
> 只看外部引用会把它们误删 —— 那会直接改坏设计。

---

## 2. 闸门扩到 `M` 枚举

死令牌检查现在覆盖三个枚举：

| 枚举 | 排除的"非令牌" |
|---|---|
| `C` | `rgb` / `dual` / `dimmed` / `trackOf` / `highContrastOn` |
| `F` | `sans` / `serif` / `mono` / `gaugeNumber` / `gaugeNumberPlain` |
| `M` | （无 —— 五个动效全是令牌） |

**当场验证**：塞一个 `zzDeadMotion` 进 `V.M`，闸门立刻红并打出正确前缀 `M.zzDeadMotion`
（第一版打成了 `C.M.zzDeadMotion`，前缀写死成 `C.` —— 已修，因为错的前缀会把排查引向错误方向）。

---

## 3. 文件头留下清理记录

在 `V7Tokens.swift` 顶部写了这段，让后来人知道**为什么少了 24 个令牌**、
以及为什么不能再堆积：

> 令牌文件被 tokens.js / dynamictype.js **整体豁免**（它是字面量的家），
> 于是没有任何闸门检查"令牌是否被使用"；这些令牌看起来完全合理，
> 后来的人会以为它们是设计系统的一部分、不敢删、甚至照着它们挑新值。

---

## 4. 验证链

```
$ node Gates/allgates.js
… 20 道闸门全部通过
tokens: OK — 148 个 Swift 文件，0 处硬编码样式字面量（含 V7 字号/色板）

$ node -e "brace balance" -> 0   # 删除后文件结构完整

$ git show origin/ci-log:meta.txt
commit=dcb0505… errors=0  build_ok=1  archive_ok=1
```

---

## 5. 仍未闭环

### P2（6 项，均需设备/外部决定/平台限制）
SEC-01 残余 · SEC-18 残余 · SEC-22（固件 AES-ECB）· SEC-26（出口合规）·
SEC-01 单测（未签名宿主 skipped）· D-12（竖屏产品决定）。

### P3
D-11 误报已确认。D-14（DesignLab `<img>` 缺 alt）、`ForEach` 下标身份若干处、
`.toolbar(.hidden, for:)` 软废弃、VoiceOver 转子（可选优化）。

### 需要真机/人工的
SwiftUI 真实渲染与浅色主题观感、手势、触觉、BLE 回执、指纹录入、
DFU 真实续传、WebDAV 真实链路、密度三档观感。

### 令牌系统的现状
删完 24 个之后，令牌表更短、更密 —— 但**这只能证明"每个令牌都有消费点"**，
不能证明"每个令牌的取值都对"。后者仍需要设计对照与人眼验收。
