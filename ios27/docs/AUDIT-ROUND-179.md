# AUDIT-ROUND-179 · 第 179 轮：12/24 小时制**只在记录页生效**（15 处 UI 用了写死 24 小时的引擎格式器）

> CI：**`23d9a46` 已验证绿**（build_ok=1 errors=0 warnings=0）；`38a9f13` 待回执。

## 1. 缺陷

本仓有两个同名出口：

| 出口 | 行为 |
|---|---|
| `TimeFormat.clock(_:)`（Engine） | **恒 24 小时** `HH:mm` —— 机器口径 |
| `TimeDisplay.clock(_:)`（Features/Settings） | 读 `SettingsStore.timeStyle`，跟随系统或用户选的 12/24 |

但界面里大量地方用的是**引擎那个**：

```
DefendScreen「上次改动」 / GatewayScreen「上次核对」 / HardwareScreen「上次扫描」
SyncTimeScreen「锁内时间」「手机当前时间」/ BackupScreen「上次备份」
DoorScreen 刷新提示 / RecordsScreen「已读取 …」/ CredentialStudioParts / MemberCreateScreen
KeysState.expiryLine（凭证明细的到期时刻）/ V7Extras.VLedgerRow / Ledger.LedgerRow
```

**后果：用户在「外观 → 时间显示」里切到 12 小时，只有记录页的时间变了，其它页面照旧 24 小时。**
一个设置只有一半生效 —— 比没有这个设置更让人困惑。

## 2. 修法：15 处全部改走 `TimeDisplay.clock`

| 层 | 文件 | 处数 |
|---|---|---|
| Features | `DefendScreen` / `DoorScreen` / `GatewayScreen` / `SyncTimeScreen`(2) / `MemberCreateScreen` / `CredentialStudioParts` / `KeysParts` / `RecordsScreen` / `BackupScreen` / `HardwareScreen` / `V7Extras`(2) | 13 |
| Design | `Ledger.swift`(2) | 2 |

改完 `App/` 下 **`TimeFormat.clock` 零调用**，`TimeDisplay.clock` 共 25 处。

### 连带修的两处

**（a）`KeysState.expiryLine` 加 `@MainActor`**

`TimeDisplay` 是 `@MainActor`（它读 `@MainActor` 的 `SettingsStore`），而 `KeysState` 不是。
唯一调用点是 `KeyDetailScreen` 的 View body（本来就是主线程），所以加 `@MainActor` 安全。

**（b）`LedgerRow` 的时刻列 `frame(width: 48)` → `minWidth`**

12 小时制下「3:05 PM」比「15:05」宽得多，固定 48pt 会裁字。
（这正是前几轮那条判据：**改格式就要连带查"这个文本的容器够不够宽"**。）

## 3. 本轮另外 4 项「审过、判定正确」

| 疑点 | 结论 |
|---|---|
| 通知 identifier 撞车 | ✅ `c6.alert.<mac>.p<alias>` + 后缀 `.d7/.d3/.d1/.h24/.h2/.t0`；`cancelAlerts` 用 `hasPrefix(id + ".")` 一次清干净 |
| `WeekCal.shifted` 用时长算日期 | ✅ 用的是 `date(byAdding: .day)`（日历日），不是 `addingTimeInterval(86400)`；注释也写明"算时长的调用点不该来这里" |
| `Locale.current` 是否污染固定格式 | ✅ 全仓只有 1 处，用途是取「系统 12/24 制式」模板（`fromTemplate: "j"`），本就该用当前区域 |
| `TimeDisplay.clock` 的 12 小时换算 | ✅ `hour % 12 == 0 ? 12 : hour % 12`（0→12 AM、12→12 PM），12 小时制不加前导零 |

## 4. 一个**未改**的观察

12 小时制下后缀硬编码英文 `" AM"/" PM"`，中文界面里会显示「3:45 PM」。
改成「下午 3:45」需要同时定中文排版（前缀 vs 后缀），属产品/文案决定 —— **记录不改**。

## 5. 方法论

**「同名两套实现」是设置失效的常见原因 —— 而且失效是静默的（不报错、不告警）。**

| 症状 | 根因 |
|---|---|
| 某个设置"有时生效有时不生效" | 一半代码走读设置的实现，一半走写死的那个 |
| 某个设置"完全没反应" | 全部走写死的那个 |

判据：**新增一个"用户可选"的格式/行为时，立刻 grep 旧实现的调用点并全部迁移**；
否则旧实现会长期潜伏在"还没改到的页面"里。

本轮的做法可以直接复用：

```
grep "TimeFormat.clock(" App/Features App/Design   → 15 处
全部替换为 TimeDisplay.clock(...)
re-grep 确认 0 残留
```
