# 新页面端到端链路核对

> 4 个页面是本会话新写的，**都没有被亲眼看过**。
> 这份记录它们的数据链路逐段是否接通 —— 静态可验的部分。

## 1. 外观工作室（AppearancePage）

| 开关 | 写入 | 读取方 | 结果 |
|---|---|---|---|
| 主题 | `kf_theme` | `LockKeeperApp.scheme(for:)` / `XPalette.isAMOLED` | ✓ |
| 强调色 | `kf_accent` | `Theme.accentOverride`（6 个 case，与页面选项逐一对应）| ✓ |
| 高对比 | `kf_hc` | `XAppearance.highContrast` → `XPlate` 降实底 | ✓ |
| 周起始日 | `kf_week_start` | `WeekCal.key` → 本周区/月历表头 | ✓ |

**没有发现假开关。**（第 97 轮核过默认值；第 105 轮核过链路）

## 2. 应用锁（AppLockSetupView）

| 环节 | 结果 |
|---|---|
| 设口令 → `DB.setPasscode` → 写 `{s, d, d2}` | ✓ |
| 校验 → `verifyPasscode` 优先 `d2`（PBKDF2 60k 轮），旧库回退 `d` 并**静默升级** | ✓ 不会把老用户锁在外面 |
| 门禁 | `showGate` → 30 秒内二次开锁要复核（第 51 轮修的）| ✓ |
| 毁灭动作复核 | `LockGuard.sudoOk`：空输入不放行、没设口令不放行 | ✓ fail-closed |

**性能**：PBKDF2 60k 轮 ≈ 30–60ms，只在按钮动作里跑，不在 `body` 里。

## 3. 回收站（CredentialBinView）

| 环节 | 结果 |
|---|---|
| 列数据 | `CredentialOrg.bin(mac)` + `queue(mac)` | ✓ |
| 恢复 | `DB.undoRemove` | ✓（第 28 轮之前零调用）|
| 保留期文案 | 全部来自 `reclaimDays()`，无硬编码 | ✓（第 97 轮核过）|
| 回执卡 | `LinkSense.lastReceipt` 5 分钟内显示 | ✓（第 76 轮接通）|

## 4. 诊断与自检（DiagnosticsPage）

| 环节 | 结果 |
|---|---|
| 体检数据 | `.task` 里算一次存 `@State`（原先每帧重算）| ✓ 第 100 轮修 |
| 保留期切换 | `applyRetentionNow()` 当场生效 + 播报条数 | ✓ 第 97 轮修 |
| 崩溃档案 | `CrashGuard.archList()`，启动卡显示「崩在「X」」| ✓ 第 101 轮 |
| 日志断档 | `DataHealth.gapDays` | ✓ 第 83 轮 |

## 仍然只能靠真机验的

- 这 4 个页面的**排版观感**（我看不到渲染结果）
- 应用锁在真机上输入口令的**键盘体验**
- 回收站恢复后**锁端是否真的删了**（要连真锁）
- 诊断页各项读数是否与真机状态一致

> 静态链路全通，不等于好用。这条界线不会因为多核几轮而消失。
