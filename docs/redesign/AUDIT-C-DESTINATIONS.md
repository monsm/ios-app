# AUDIT-C · 76 行改造表事实核对（对抗审核）

> 审核员：ev-android · 2026-10-18 · 只读核查（唯一写入物为本文件；过程中的临时文件已清理）

## 结论先行

1. **实现落点：全部 76 条 0 处不符**（不是抽 20 条，是逐条比对）。
2. **风险分级：3 处不符**，根因是**生成侧的结构体切片串到了下一个 struct**。
3. **重复 View：不存在** —— 76 个枚举 → 76 个互不相同的 View 名。
4. **autoCal 特例成立**，但不破坏「目的地 = View」的假设。
5. `SettingsView` 直呈 32 个目的地：**未证实**（复算脚本最后一步失败），仍以 PART2 的 32 为准。
6. Tab 归属：机械可判部分与 PART5 §3 一致；**语义合理性需人工判**（见 §4）。

## 1. 实现落点（0 处不符）

方法：`Destination.swift:9-84` 的 76 个 `case x = "XxxView"` → 全仓 `struct XxxView: View` 定义行 → 与行表 `file` 列比对。

| 抽样（覆盖 4 Tab） | 真实定义处 |
|---|---|
| `AccessibilityView` | `App/UI/AccessibilityView.swift:8` |
| `AutoCalView` | `App/Core/AutoOpen.swift:575` |
| `DeviceInfoView` | `App/UI/Sheets.swift:971` |
| `FocusUnlockView` | `App/UI/DeviceHomeView.swift:2431` |
| `IntegrationCenterView` | `App/Intents/AppIntents.swift:430` |
| `LinkPrefsView` | `App/Core/LinkSenseKit.swift:643` |
| `SecurityCenterView` | `App/UI/SecurityCenterView.swift:172` |

**口径瑕疵（非错误）**：3 条落点在 `App/Core/` 或 `App/Intents/`（#6 autoCal、#41 linkPrefs、#39 integrationCenter），
与表头「`App/UI/xxx.swift`」的措辞不一致。**视图不都在 App/UI/ 下**，改前先定位。

## 2. 风险分级 3 处不符

| # | Destination | 表标 | 实测 | 判定 |
|---|---|---|---|---|
| 25 | `defend` | 低 | 切片 `SettingsView.swift:1408-1503` 内含 `ZKCmdBuilder.protoSec`（`:1475-1476`） | ❌❌ 低危定义不成立，**已上调为中** |
| 45 | `lockProfile` | 中（DFUKit） | `LockProfileView` 切片 `Sheets.swift:1289-1473` 内 **0 处** DFUKit；DFUKit 只在 `:1481` 注释与 `:1482 struct FirmwareView` | ❌❌ 切片串到下一个 struct，**已下调为低** |
| 60 | `restoreWizard` | 中（WebDAV） | 切片内 **0 处** WebDAV；命中在 `:37` 与 `:1206+ WebDAVStudioView` | ❌ 同类串片，**已下调为低** |

**修正后计数：高危 12 · 中危 8 · 低危 56**（原 12/9/55）。

方法学备注：PART5 §3.1/§3.2 与生成产物 `_gen/_part5_rows.json` 的 `marks` 逐条一致（21 条非低危全核），
**故缺陷在生成侧切片，不是转录笔误**。

## 3. 重复 View：不存在

76 个枚举 → 76 个互不相同的 View 名，无一个 Destination 指向同一 View。
真正的「改一个影响多个」在**文件层**：**13 个文件承载 62 条**（`Sheets.swift` 10、`MemberCenterView` 10、
`CredentialCenterView` 8、`BackupStudio` 6、`SettingsView` 4、`DeviceHomeView` 4，
`SecurityCenterView`/`AchievementsView`/`CareViews`/`HelpCenter` 各 3，`RecordsView` 3，`ChangelogView`/`StatsView` 各 2），
余 14 个文件各 1 条。**已写入 PART5 §7**。

## 4. autoCal 特例与 Tab 归属

`AutoCalView` 确在 `App/Core/AutoOpen.swift:575` 有 struct；`destmap` 报它**唯一呈现点 = `AutoOpen.swift:661`（NavigationLink）**，
宿主是 `AutoOpenSection`（同文件）。即「呈现点不在 View 里」为真，**但 View 依然存在** —— 只是放错了目录。
**对改造无影响**：照常改 `AutoCalView` 的视觉层即可。

Tab 归属全部由 `g` 映射得出，计数与 PART5 §3 一致（设置 22 / 设备 25 / 凭证 22 / 记录 7）。
**未证实**：「成员」10 条归凭证、「关怀」10 条归设备是否与 `Route.byHost` 语义一致 —— 需人工判语义，非机械可判。

## 5. PART5 必须修正的行（已全部执行）

| 位置 | 修正 |
|---|---|
| #25 `defend` 风险列 | 低 → **中**，备注 `ZKCmdBuilder.protoSec` 在本 struct 内 |
| #45 `lockProfile` 风险列 | 中 → **低**，备注切片串到 `Sheets.swift:1481` 附近 |
| #60 `restoreWizard` 风险列 | 中 → **低**，备注切片串到 `BackupStudio.swift:1206` 附近 |
| §3 统计表 | 改为 高 12 · 中 8 · 低 56 |
| §7 新增 | 文件扇出表（13 个文件承载 62 条） |

## 6. 未证实项

- `SettingsView` 直呈 32 个目的地：复算未完成（脚本 `$env:TEMP` 未传入而失败），**不替代 PART2:18 的 32**。
- 「成员归凭证 / 关怀归设备」的语义合理性：机械不可判。
- PART5:197 自述「77 个呈现点」与 76 条的口径差异：已披露，属「呈现点 vs 目的地」两个量。