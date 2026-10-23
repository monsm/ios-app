# 审美对齐与入口修复 · 专项记录

> 目标（用户 2026-10-24 明确）：
> **① 审美**：界面必须严格以 `tools/proto/` 的 HTML 原型为标准
> **② 功能**：业务逻辑以真实 App 为准；HTML 的链接只是原型脚手，不参与评判

---

## 工具

| 工具 | 作用 |
|---|---|
| `tools/parity.js` | HTML ↔ SwiftUI **审美**逐页对照：卡头 / 区块标签 / 大数字 / 视觉词汇（环、胶囊、彩点行、柱图、画廊、两层结构、渐变 hero）|
| `tools/entrygate.js` | 入口可点性闸门（E1）：带 `showsChevron` 的行必须有动作 |

### parity.js 的口径

- **比审美结构**：HTML 有的卡头/标签/组件形态，App 对应页必须有
- **不比导航**：HTML 的 `href` 是原型脚手（含 TabBar 与返回），App 用 NavigationStack 表达，两者不可直接比

---

## 已修复清单

### 审美术语缺口（25 → 4）

| 页 | 缺口 | 处理 |
|---|---|---|
| 47-backup | 卡头「备份时效」「加密参数」/ 标签「算法·认证·派生」| ✅ 全补 |
| 89-share-android | 卡「关于这个码」+ 有效期/作用 | ✅ 新增整卡 |
| 05-system | 卡「备份恢复」+ 上次导出/本机门锁/钥匙总数 | ✅ 新增整卡 |
| 4a-me | 卡头「本机状态 / 本机数据与访问权限 / 门锁与设备 / 导出与关怀」| ✅ 全部改名对齐 |
| 21-lock-profile | 卡「指纹余量」「身份（名字·锁态）」+ 身份/符号/配色/更多 四卡头 | ✅ 新增 |
| 25-synctime | 卡头「偏差范围」「写入」| ✅ 改名对齐 |
| 41-applock | 卡「保护项」| ✅ 新增 |
| 60-care | 卡头「该做的」| ✅ 补 |
| 80-states | ① 骨架屏 ② 空态 ③ 错误态 | N/A（组件规范，无独立页）|

### 视觉词汇缺口（12 → 9）

| 页 | 缺口 | 处理 |
|---|---|---|
| 61-reminders | 横向画廊 | ✅ 生日清单 → 图6 横滑卡（104pt）|
| 60-care | 横向画廊 | ✅ 保养历史横滑卡 |
| 03-devices | 玻璃胶囊 | ✅ XStatChip 行 |
| 51-feed / 44-audit | 两层结构 | ⬜ 待做 |
| 01-home | 大数字 | ⬜ 待做（环心是动作控件，需另定位置）|
| 04-members / 30-members-list / 14-otp | 彩色数据行 | ⬜ 待做 |
| 05-system / 4a-me | 玻璃胶囊 | ⬜ 待做 |

### 入口可点性（真 bug）

| 位置 | 问题 | 处理 |
|---|---|---|
| MePage.statusSummary | 四个状态瓦片注释写着「每项都是能直接跳过去的入口」，但 `summaryTile` 无 action、未包导航 —— **点上去毫无反应** | ✅ 逐个包 NavigationLink（应用锁→SecurityPage / 告警→AlarmsPage / 备份→BackupPage / 门锁→LocksPage）|

---

## 累计被工具拦下的编译错误（本轮新增）

| 错误 | 抓到它的工具 |
|---|---|
| `TimeFormat.day` / `BatteryCare.daysAgoText` 不存在 | apicheck |
| `TimeFormat.daysSince` 需要 `ms:` 标签 | 人工比对签名 |
| `.frame(width:104)` 违反 §13.1 | glassaudit |
| 手绘 `Circle`/`RoundedRectangle` 超自绘预算 | uicoverage |
