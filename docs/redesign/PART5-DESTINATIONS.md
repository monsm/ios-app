# PART 5 · 全部 76 目的地逐条改造表

> 本表由脚本从两处**机器事实**生成后人工校订：
> ① 功能语义（标题/分组/why/act/层级）= `ios-app/docs/preview/uiux-v3.data.js` 的 `window.SCREENS`（76 条，已机检 76/76 完整）；
> ② 实现落点与风险 = `App/Core/Destination.swift` 的 76 个枚举 + 对每个 View 的**结构体切片**做风险标记扫描。
> 生成脚本的中间产物留在 `_part5_rows.json` / `_part5_map.json`，改完可重跑对比。

## 0. 两条必须先知道的事实

**① 76 条 id 与 Destination 枚举一一对应，无缺无多**（机检：仅数据 0 条、仅枚举 0 条）。
所以「76」这个数字本轮**不因改造而变**；只有新增的 App Index / 门面设置页会让它变成 78（见 PART2 与 PART7 §2.3）。

**② `uiux-v3.data.js` 的树结构早于当前的 4 Tab 结构。** 它只有 3 个无父节点的根：
`deviceHome`（tab: 锁）、`records`（tab: 记录）、`settings`（tab: 设置）；
而「凭证」与「成员」两组被挂在 `锁` 之下（`credentials.parent = 锁`、`members.parent = 锁`）。
当前 App 是 **4 个 Tab**（`Route.byHost` = 设备 / 凭证 / 记录 / 设置），
因此本表按 **`g`（分组）→ Tab** 重新归属。**不要**照搬数据文件里的 `parent` 当导航层级 ——
本表的「数据树深度」列同理，只是语义参考；真正的落地层级见 `PART2-NAV-IA.md` §3。
（两处数字不同不是矛盾：一个是数据文件的树，一个是 `tools/destmap.js` 实测的呈现通道。）

| 分组 `g` | 归到哪个 Tab | 条数 |
|---|---|---|
| 锁 | 设备 | 15 |
| 凭证 | 凭证 | 12 |
| 成员 | 凭证 | 10 |
| 记录 | 记录 | 7 |
| 安全 | 设置 | 10 |
| 数据 | 设置 | 8 |
| 关怀 | 设备 | 10 |
| 诊断 | 设置 | 3 |
| 设置 | 设置 | 1 |
| **合计** | | **76** |

## 1. 分组改动模板（76 行表用 G1–G9 引用，避免 76 段重复文字）

总原则：**只改壳，不改行为**。壳 = 卡片/分组标题/状态胶囊/按钮/排版/间距/圆角/动效；
行为 = 数据读写、锁端指令、文案语义、跳转目标。

### G1 · 开锁与锁本体（锁，15 条 → Tab 设备）

- 门面层直接相关；行为零改动
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G2 · 凭证与钥匙（凭证，12 条 → Tab 凭证）

- 高危（写锁端）
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G3 · 成员与家庭（成员，10 条 → Tab 凭证）

- 中危
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G4 · 记录与统计（记录，7 条 → Tab 记录）

- 只读，低危
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G5 · 安全与防御（安全，10 条 → Tab 设置）

- 高危（安全语义）
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G6 · 备份与迁移（数据，8 条 → Tab 设置）

- 高危（格式契约）
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G7 · 关怀与维护（关怀，10 条 → Tab 设备）

- 低危
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G8 · 诊断与排查（诊断，3 条 → Tab 设置）

- 低危
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

### G9 · 设置与帮助（设置，1 条 → Tab 设置）

- 低危
- **改动**：卡片走 `VK().card { }`；分组标题走 `VK().sectionTitle(text:count:)`；状态胶囊走 `VK().statusPill(text:systemImage:tone:)`（**三个都是 @MainActor func，不是属性**，写成 `VK.card` 编译不过）；文本一律 `.vkFont(...)`；**字号/行高/圆角/左边距按 D15 七条**（34 semibold / 13 提示 / 行高 44 或 60 / 圆角 22 / 左边距 16 / 读数 monospacedDigit / 动态字体封顶 accessibility2）；
  间距用 `DS.Space`、圆角用 `DS.Radius`；主操作按钮走 `PrimaryActionStyle`，破坏性操作走 `DestructiveActionStyle`（颜色语义不变）。
- **不许动**：任何 `LockService` / `HardwareService` / `BLEService` / `DFUKit` / `BackupKit` 调用及其参数；任何 `kf_*` 键名与默认值；rc 文案表；跳转目标（仍走 `requestRoute`）。

## 2. 76 行主表

列义：
- **数据树深度** = «uiux-v3.data.js» 里沿 «parent» 上溯的层数（一级 / 二级）。**它不是导航层级**，
  只是数据文件里的语义树（见 §0 ②）。
- **真正的导航层级以 `PART2-NAV-IA.md` §3 为准**：实测 = **4 根屏 + 51 一级 + 22 二级 = 77 个呈现点**
  （由 `tools/destmap.js --json` 复算；`SettingsView` 直呈 32 个是全仓最大入口）。
  两个数字口径不同，**别混用**：本文的「数据树深度」只帮你理解语义归属。
- **风险** 由该 View 结构体切片内出现的服务类数量判定（≥2 高 / 1 中 / 0 低）。

| # | Destination | 标题 | Tab | 数据树深度 | 数据 path | 实现落点 | 这一屏回答什么 | 主动作 | 风险 | 改动 | 不许动 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `accessibility` | 无障碍 | 设置 | 二级 | 设置 › 无障碍 | `App/UI/AccessibilityView.swift` | 每个人都能开门，包括看不清、听不见、手不稳的人。 | 调字号、对比度、减弱动效。 | 低 | G5 模板 | 跳转目标 |
| 2 | `achievements` | 成就 | 设备 | 二级 | 设置 › 成就 | `App/UI/AchievementsView.swift` | 长期使用需要一点正反馈，但不喧宾夺主。 | 查看已达成与进行中。 | 低 | G7 模板 | 跳转目标 |
| 3 | `addDevice` | 添加门锁 | 设备 | 二级 | 锁 › 添加门锁 | `App/UI/Sheets.swift` | 第一次用，或者添第二把锁。 | 扫 iOS 生成的钥匙码，或靠近自动发现。 | 高 | G1 模板 | **服务调用与参数、kf_* 键** |
| 4 | `addPwd` | 添加密码 | 凭证 | 二级 | 锁 › 凭证 › 添加密码 | `App/UI/Sheets.swift` | 新增一条能开门的密码。 | 输入两遍并写入锁端。 | 中 | G2 模板 | kf_* 键与文案 |
| 5 | `alarmCenter` | 告警中心 | 记录 | 二级 | 记录 › 告警 | `App/UI/AlarmCenterView.swift` | 真正需要注意的事，不该混在流水里。 | 逐条确认、跳转到对应锁或成员。 | 低 | G4 模板 | 跳转目标 |
| 6 | `autoCal` | 自动开锁校准 | 设备 | 二级 | 锁 › 自动开锁校准 | `App/Core/AutoOpen.swift` | 每个人家门口的信号都不同，阈值必须能调。 | 走一遍校准，或手动改阈值。 | 低 | G1 模板 | 跳转目标 |
| 7 | `backupStudio` | 备份工作台 | 设置 | 二级 | 设置 › 备份 › 工作台 | `App/UI/BackupStudio.swift` | 备份不是一次按钮，是一份可验证的包。 | 生成包、核对校验和、查看历史。 | 高 | G6 模板 | **服务调用与参数、kf_* 键** |
| 8 | `backup` | 备份与恢复 | 设置 | 二级 | 设置 › 备份与恢复 | `App/UI/BackupView.swift` | 换手机、丢手机时，钥匙不能丢。 | 立即备份，或从备份恢复。 | 高 | G6 模板 | **服务调用与参数、kf_* 键** |
| 9 | `batterySwapGuide` | 换电池指南 | 设备 | 二级 | 设置 › 保养 › 换电池 | `App/UI/CareViews.swift` | 用户第一次换电池时，不该靠猜。 | 按步骤操作；每步可放大。 | 低 | G7 模板 | 跳转目标 |
| 10 | `borrowSheet` | 借用钥匙 | 凭证 | 二级 | 锁 › 成员 › 借用 | `App/UI/MemberCenterView.swift` | 借一次，而不是送一把。 | 设归还时间，生成临时凭证。 | 低 | G3 模板 | 跳转目标 |
| 11 | `butlerCertificate` | 管家证书 | 设置 | 二级 | 设置 › 安全 › 管家证书 | `App/UI/HelpCenter.swift` | 长期帮忙的人需要稳定授权，也要能随时收回。 | 签发、查看、撤销。 | 低 | G5 模板 | 跳转目标 |
| 12 | `capsuleCompose` | 胶囊编辑 | 设备 | 二级 | 设置 › 成就 › 胶囊 | `App/UI/AchievementsView.swift` | 把此刻的心情留在 App 里。 | 写、封存、到期打开。 | 低 | G7 模板 | 跳转目标 |
| 13 | `careReminders` | 关怀提醒 | 设备 | 二级 | 设置 › 关怀 | `App/UI/AchievementsView.swift` | 技术之外，家人之间的小事。 | 开关各类提醒与时间。 | 低 | G7 模板 | 跳转目标 |
| 14 | `changeBatch` | 更新批次 | 设备 | 二级 | 设置 › 更新说明 | `App/UI/ChangelogView.swift` | 用户要知道升级带来了什么，而不是看提交记录。 | 阅读；可回看历史版本。 | 低 | G7 模板 | 跳转目标 |
| 15 | `changelog` | 更新日志 | 设备 | 二级 | 设置 › 更新日志 | `App/UI/ChangelogView.swift` | 完整的历史，供排查与回溯。 | 展开某一版。 | 低 | G7 模板 | 跳转目标 |
| 16 | `credBin` | 回收站 | 凭证 | 二级 | 锁 › 凭证 › 回收站 | `App/UI/CredentialCenterView.swift` | 删错了还能救回来。 | 恢复，或彻底删除。 | 低 | G2 模板 | 跳转目标 |
| 17 | `credCenter` | 凭证中心 | 凭证 | 二级 | 锁 › 凭证 › 中心 | `App/UI/CredentialCenterView.swift` | 所有凭证的单一入口。 | 按类型或状态筛选。 | 低 | G2 模板 | 跳转目标 |
| 18 | `credentials` | 凭证与钥匙 | 凭证 | 二级 | 锁 › 凭证与钥匙（原第 2 个 Tab，降为二级） | `App/UI/CredentialsView.swift` | 谁能开这把门：这是锁的属性，不是独立世界。 | 搜索，或进入某一类凭证。 | 高 | G2 模板 | **服务调用与参数、kf_* 键** |
| 19 | `credExtend` | 延长临时码 | 凭证 | 二级 | 锁 › 凭证 › 延长 | `App/UI/CredentialCenterView.swift` | 访客还没走，权限要能顺延。 | 选新的失效时间并写回。 | 低 | G2 模板 | 跳转目标 |
| 20 | `credHistoryList` | 凭证变更总表 | 凭证 | 二级 | 锁 › 凭证 › 变更总表 | `App/UI/CredentialCenterView.swift` | 一次看完全部改动，而不是逐条翻。 | 按凭证或时间筛选。 | 低 | G2 模板 | 跳转目标 |
| 21 | `credHistory` | 凭证历史 | 凭证 | 二级 | 锁 › 凭证 › 历史 | `App/UI/CredentialCenterView.swift` | 这条密码什么时候改过、谁改的。 | 查看变更记录；可回滚到上一版。 | 低 | G2 模板 | 跳转目标 |
| 22 | `credOrganize` | 整理建议 | 凭证 | 二级 | 锁 › 凭证 › 整理 | `App/UI/CredentialCenterView.swift` | 凭证会自己长出来，需要定期收。 | 按建议合并、停用或删除。 | 低 | G2 模板 | 跳转目标 |
| 23 | `credQueue` | 待补拉队列 | 凭证 | 二级 | 锁 › 凭证 › 待补拉 | `App/UI/CredentialCenterView.swift` | 网络/链路失败时，改动不能悄悄丢。 | 重试写回，或放弃并说明后果。 | 低 | G2 模板 | 跳转目标 |
| 24 | `credTransfer` | 凭证迁移 | 凭证 | 二级 | 锁 › 凭证 › 迁移 | `App/UI/CredentialCenterView.swift` | 换机时把钥匙带走，而不是重新配。 | 生成一次性迁移码。 | 低 | G2 模板 | 跳转目标 |
| 25 | `defend` | 尾随防护 | 设置 | 二级 | 设置 › 安全 › 尾随防护 | `App/UI/SettingsView.swift` | 有人跟着进门时，给自己一个提醒。 | 开关与延迟。 | **中** ⚠️audit | G5 模板 | **`ZKCmdBuilder.protoSec` 在本 struct 内（`:1475-1476`），不许当低危处理** |
| 26 | `demoLabs` | 实验室 | 设备 | 二级 | 设置 › 实验室 | `App/UI/HelpCenter.swift` | 把试验功能收在一处，默认关闭。 | 逐项开启，随时可关。 | 低 | G7 模板 | 跳转目标 |
| 27 | `deviceHome` | 锁 | 设备 | 一级 | 锁（主 Tab） | `App/UI/DeviceHomeView.swift` | 能不能开：这一屏只回答这一件事。 | 轻点黄铜圆盘开锁（或说“开锁”）。 | 高 | G1 模板 | **服务调用与参数、kf_* 键** |
| 28 | `deviceInfo` | 设备信息 | 设备 | 二级 | 锁 › 设备信息 | `App/UI/Sheets.swift` | 排查时第一眼要看的事实。 | 查看或复制诊断信息。 | 高 | G1 模板 | **服务调用与参数、kf_* 键** |
| 29 | `deviceManage` | 设备管理 | 设备 | 二级 | 锁 › 设备管理 | `App/UI/DeviceManageView.swift` | 锁多了以后，顺序与分组决定找得快不快。 | 拖动排序、批量改分组。 | 低 | G1 模板 | 跳转目标 |
| 30 | `diagnostics` | 诊断 | 设置 | 二级 | 设置 › 诊断 | `App/UI/DiagnosticsView.swift` | 出问题时，先看事实，不看猜测。 | 跑自检、复制摘要、查协议。 | 高 | G8 模板 | **服务调用与参数、kf_* 键** |
| 31 | `diagReference` | 协议参考 | 设置 | 二级 | 设置 › 诊断 › 协议 | `App/UI/DiagReferenceView.swift` | 排查时要能对照协议，而不是背。 | 搜索命令或返回码。 | 低 | G8 模板 | 跳转目标 |
| 32 | `exportCenter` | 导出中心 | 记录 | 二级 | 记录 › 导出 | `App/UI/ExportCenter.swift` | 把记录带走，用于报修或留档。 | 选格式与范围，导出到文件。 | 低 | G4 模板 | 跳转目标 |
| 33 | `exportWizard` | 导出向导 | 设置 | 二级 | 设置 › 备份 › 导出 | `App/UI/BackupStudio.swift` | 把数据交出去时，范围要说清楚。 | 选范围 → 选格式 → 确认。 | 低 | G6 模板 | 跳转目标 |
| 34 | `firmware` | 固件 | 设备 | 二级 | 锁 › 固件 | `App/UI/Sheets.swift` | 有没有更新、更新会改什么。 | 检查更新；有更新时查看变更再执行。 | 高 | G1 模板 | **服务调用与参数、kf_* 键** |
| 35 | `focusUnlock` | 专注开锁 | 设备 | 二级 | 锁 › 专注开锁 | `App/UI/DeviceHomeView.swift` | 在走廊、夜里、单手时，减少一切干扰。 | 按住圆盘确认；超时可取消。 | 高 | G1 模板 | **服务调用与参数、kf_* 键** |
| 36 | `gateway` | 网关 | 设备 | 二级 | 锁 › 网关 | `App/UI/Sheets.swift` | 要远程开门时，网关是前提。 | 绑定网关、查看在线状态。 | 中 | G1 模板 | kf_* 键与文案 |
| 37 | `gratitude` | 感谢与致谢 | 记录 | 二级 | 记录 › 致谢 | `App/UI/RecordsView.swift` | 把人和事的来处写清楚。 | 阅读即可。 | 低 | G4 模板 | 跳转目标 |
| 38 | `houseCleaningPreset` | 保洁预设 | 设置 | 二级 | 设置 › 安全 › 保洁预设 | `App/UI/MemberCenterView.swift` | 给保洁开门，不该给一把长期钥匙。 | 选时段与范围，一次生成。 | 低 | G5 模板 | 跳转目标 |
| 39 | `integrationCenter` | 集成 | 设备 | 二级 | 设置 › 集成 | `App/Intents/AppIntents.swift` | 把开锁接进系统能力，而不是再造一个入口。 | 开关集成，查看权限。 | 低 | G7 模板 | 跳转目标 |
| 40 | `keychainHW` | 钥匙硬件 | 设备 | 二级 | 锁 › 钥匙硬件 | `App/UI/Sheets.swift` | 实体钥匙也要能被管理、挂失、补配。 | 登记或挂失一把实体钥匙。 | 中 | G1 模板 | kf_* 键与文案 |
| 41 | `linkPrefs` | 连接偏好 | 设备 | 二级 | 锁 › 连接偏好 | `App/Core/LinkSenseKit.swift` | 连接行为要可预期，也要可关闭。 | 开关自动重连、调整超时。 | 低 | G1 模板 | 跳转目标 |
| 42 | `localFiles` | 本机文件 | 设置 | 二级 | 设置 › 备份 › 文件 | `App/UI/BackupStudio.swift` | 文件都在哪，占了多少空间。 | 查看、分享、删除。 | 低 | G6 模板 | 跳转目标 |
| 43 | `lockCompare` | 锁对比 | 设备 | 二级 | 锁 › 对比 | `App/UI/LockCompareView.swift` | 排查“为什么这台更慢”时，需要并排看。 | 选两台锁，比较信号、电量、固件。 | 低 | G1 模板 | 跳转目标 |
| 44 | `lockOverview` | 多锁总览 | 设备 | 二级 | 锁 › 全部锁 | `App/UI/LockOverviewView.swift` | 有多把锁时，一屏看清谁在线、谁该处理。 | 点任意一把切为当前锁。 | 低 | G1 模板 | 跳转目标 |
| 45 | `lockProfile` | 这把锁 | 设备 | 二级 | 锁 › 这把锁 | `App/UI/Sheets.swift` | 它是谁、装在哪、叫什么名字。 | 改名、换位置、看序列号。 | **低** ⚠️audit | G1 模板 | kf_* 键与文案 |
| 46 | `maintenance` | 保养 | 设备 | 二级 | 设置 › 保养 | `App/UI/CareViews.swift` | 锁也需要被照顾，尤其是电池与锁芯。 | 查看保养项，标记完成。 | 低 | G7 模板 | 跳转目标 |
| 47 | `maintSettings` | 保养设置 | 设备 | 二级 | 设置 › 保养 › 设置 | `App/UI/CareViews.swift` | 不同家庭的节奏不同。 | 调周期与提醒。 | 低 | G7 模板 | 跳转目标 |
| 48 | `memberArchived` | 已归档成员 | 凭证 | 二级 | 锁 › 成员 › 已归档 | `App/UI/MemberCenterView.swift` | 离开的人不该还在列表里，但记录要留。 | 恢复或彻底移除。 | 低 | G3 模板 | 跳转目标 |
| 49 | `memberCenter` | 成员中心 | 凭证 | 二级 | 锁 › 成员 › 中心 | `App/UI/MemberCenterView.swift` | 把“人”和“钥匙”放在一起看。 | 进入某人，或管理借还。 | 低 | G3 模板 | 跳转目标 |
| 50 | `memberDetail360` | 成员 360 | 凭证 | 二级 | 锁 › 成员 › 详情 | `App/UI/MemberCenterView.swift` | 关于这个人，所有相关事实在一页。 | 调整权限、撤销凭证、看记录。 | 低 | G3 模板 | 跳转目标 |
| 51 | `memberFamilySettings` | 家庭设置 | 凭证 | 二级 | 锁 › 成员 › 家庭设置 | `App/UI/MemberCenterView.swift` | 这个家作为一个整体，怎么被称呼与提醒。 | 改家庭名、开关怀提醒。 | 低 | G3 模板 | 跳转目标 |
| 52 | `memberStacked` | 成员叠放视图 | 凭证 | 二级 | 锁 › 成员 › 叠放 | `App/UI/MemberCenterView.swift` | 权限多起来后，用层叠看清谁能做什么。 | 点某一层看这组人。 | 高 | G3 模板 | **服务调用与参数、kf_* 键** |
| 53 | `members` | 家人与访客 | 凭证 | 二级 | 锁 › 家人与访客 | `App/UI/Sheets.swift` | 谁能进这个家，各自有什么权限。 | 添加成员，或调整某人的权限。 | 低 | G3 模板 | 跳转目标 |
| 54 | `memberWizard` | 添加成员 | 凭证 | 二级 | 锁 › 成员 › 添加 | `App/UI/MemberCenterView.swift` | 不要在添加时就要求一串技术决定。 | 填名字 → 选凭证 → 设有效期。 | 中 | G3 模板 | kf_* 键与文案 |
| 55 | `mergeMembers` | 合并成员 | 凭证 | 二级 | 锁 › 成员 › 合并 | `App/UI/MemberCenterView.swift` | 同一个人被录了两次，要能收拢。 | 选主档案，把凭证并过去。 | 低 | G3 模板 | 跳转目标 |
| 56 | `messages` | 消息 | 设置 | 二级 | 设置 › 消息 | `App/UI/Sheets.swift` | App 想告诉你的非紧急事项。 | 读，或全部标为已读。 | 低 | G6 模板 | 跳转目标 |
| 57 | `migrationWizard` | 换机向导 | 设置 | 二级 | 设置 › 备份 › 换机 | `App/UI/BackupStudio.swift` | 换手机时，按步骤走不会漏。 | 在旧机导出 → 在新机导入 → 逐锁验证。 | 中 | G6 模板 | kf_* 键与文案 |
| 58 | `recordsSampleGuide` | 记录样例说明 | 记录 | 二级 | 记录 › 样例说明 | `App/UI/RecordsView.swift` | 没有记录时，解释记录会长什么样。 | 看完即关闭，不再打扰。 | 低 | G4 模板 | 跳转目标 |
| 59 | `records` | 记录 | 记录 | 一级 | 记录（主 Tab） | `App/UI/RecordsView.swift` | 发生过什么：时间、谁、结果。 | 筛选类型，或点开一条看详情。 | 低 | G4 模板 | 跳转目标 |
| 60 | `restoreWizard` | 恢复向导 | 设置 | 二级 | 设置 › 备份 › 恢复 | `App/UI/BackupStudio.swift` | 恢复是破坏性动作，必须先看清会覆盖什么。 | 选文件 → 对比差异 → 确认恢复。 | **低** ⚠️audit（WebDAV 命中的是下一个 struct `:1206+`，切片串了） | G6 模板 | kf_* 键与文案 |
| 61 | `safemodeIntro` | 安全模式说明 | 设置 | 二级 | 设置 › 安全 › 安全模式 | `App/UI/SettingsView.swift` | 出了问题时，App 会怎么保护你。 | 了解并开启。 | 低 | G5 模板 | 跳转目标 |
| 62 | `securityAudit` | 安全审计 | 设置 | 二级 | 设置 › 安全 › 审计 | `App/UI/SecurityCenterView.swift` | 把“感觉安全”换成可核对的事实。 | 运行审计；每项给出证据。 | 低 | G5 模板 | 跳转目标 |
| 63 | `securityCenter` | 安全中心 | 设置 | 二级 | 设置 › 安全 | `App/UI/SecurityCenterView.swift` | 这个家现在的安全状态，以及下一步做什么。 | 按建议逐项加固。 | 高 | G5 模板 | **服务调用与参数、kf_* 键** |
| 64 | `securityDestroy` | 远程销毁 | 设置 | 二级 | 设置 › 安全 › 销毁 | `App/UI/SecurityCenterView.swift` | 最坏情况下，把本机凭证清干净。 | 二次确认后销毁；不可撤销。 | 低 | G5 模板 | 跳转目标 |
| 65 | `securityPeek` | 防偷窥 | 设置 | 二级 | 设置 › 安全 › 防偷窥 | `App/UI/SecurityCenterView.swift` | 在公共场合输入密码时，别让旁人看到。 | 开关遮挡与自动模糊。 | 低 | G5 模板 | 跳转目标 |
| 66 | `settings` | 设置 | 设置 | 一级 | 设置（主 Tab） | `App/UI/SettingsView.swift` | 这把锁怎么行为：连接、数据、安全、关于。 | 进入某一组；危险动作都要二次确认。 | 中 | G9 模板 | kf_* 键与文案 |
| 67 | `shareToAndroid` | 分享给安卓 | 凭证 | 二级 | 锁 › 凭证 › 分享给安卓 | `App/UI/ShareToAndroidView.swift` | 家里另一台手机不该被系统排除在外。 | 生成二维码，让对方扫码导入。 | 低 | G2 模板 | 跳转目标 |
| 68 | `startAddFp` | 添加指纹 | 凭证 | 二级 | 锁 › 凭证 › 添加指纹 | `App/UI/Sheets.swift` | 把一个人的手指变成一把钥匙。 | 按提示完成 3 次采集。 | 中 | G2 模板 | kf_* 键与文案 |
| 69 | `stats` | 统计 | 记录 | 二级 | 记录 › 统计 | `App/UI/StatsView.swift` | 用趋势回答“这个月正常吗”。 | 切时间范围；点柱子看当天。 | 低 | G4 模板 | 跳转目标 |
| 70 | `symptomGuide` | 症状指南 | 设置 | 二级 | 设置 › 诊断 › 症状 | `App/UI/HelpCenter.swift` | 用户描述的是现象，不是错误码。 | 选症状，得到可执行的下一步。 | 低 | G8 模板 | 跳转目标 |
| 71 | `syncTime` | 时间同步 | 设备 | 二级 | 锁 › 时间同步 | `App/UI/DeviceHomeView.swift` | 日志时间对不上时，先校准时钟。 | 把手机时间写入锁端。 | 低 | G1 模板 | 跳转目标 |
| 72 | `tailgate` | 门未关提醒 | 设置 | 二级 | 设置 › 安全 › 门未关 | `App/UI/SettingsView.swift` | 门没关严，是这个家最常见的风险。 | 开关提醒与重复间隔。 | 低 | G5 模板 | 跳转目标 |
| 73 | `unclaimedClaim` | 认领指纹 | 凭证 | 二级 | 锁 › 家人与访客 › 认领 | `App/UI/MemberCenterView.swift` | 有人录了指纹但没说是谁，需要认领。 | 指定归属，或删除。 | 低 | G3 模板 | 跳转目标 |
| 74 | `unlockGate` | 开锁前置检查 | 设备 | 二级 | 锁 › 开锁前置检查 | `App/UI/DeviceHomeView.swift` | 开不了时，先告诉用户缺什么，而不是转圈。 | 按缺项逐条修复（开蓝牙 / 给权限 / 靠近）。 | 低 | G1 模板 | 跳转目标 |
| 75 | `webDAVStudio` | WebDAV 备份 | 设置 | 二级 | 设置 › 备份 › WebDAV | `App/UI/BackupStudio.swift` | 不想用第三方云，就把包放到自己的盘。 | 填地址与账号，测试连接并上传。 | 高 | G6 模板 | **服务调用与参数、kf_* 键** |
| 76 | `yearReport` | 年度报告 | 记录 | 二级 | 记录 › 年度 | `App/UI/StatsView.swift` | 一年结束，给自己看的一页总结。 | 生成并保存/分享。 | 低 | G4 模板 | 跳转目标 |

## 3. 风险统计

| 维度 | 分布 |
|---|---|
| 风险 | 低 55 · 高 12 · 中 9 |
| 数据树深度 | 二级 73 · 一级 3（**语义树，非导航层级**） |
| 导航层级（以 PART2 §3 为准） | 根屏 4 · 一级 51 · 二级 22 = **77 个呈现点** |
| Tab | 设置 22 · 设备 25 · 凭证 22 · 记录 7 |

### 3.1 高危 12 条（改前改后必须逐字回归）

| # | Destination | 出现的服务 |
|---|---|---|
| 3 | `addDevice` | LockService, DFUKit, BLEService, ZKP |
| 7 | `backupStudio` | WebDAV, WebDAVStudio |
| 8 | `backup` | BackupKit, WebDAV, WebDAVStudio |
| 18 | `credentials` | LockService, delPwd, addPwd |
| 27 | `deviceHome` | LockService, BLEService |
| 28 | `deviceInfo` | ZKP, ZKProtocol |
| 30 | `diagnostics` | LockService, BLEService |
| 34 | `firmware` | DFUKit, BLEService |
| 35 | `focusUnlock` | LockService, BLEService |
| 52 | `memberStacked` | ZKP, ZKProtocol |
| 63 | `securityCenter` | LockService, ZKP, ZKProtocol |
| 75 | `webDAVStudio` | WebDAV, WebDAVStudio |

### 3.2 中危 9 条

⚠️ **audit 复核后：本行有 3 处分级虚高，已下调** —— `defend` **上升到中**（`ZKCmdBuilder.protoSec` 在 `SettingsView.swift:1475-1476`）；`lockProfile` **降为低**（DFUKit 实为下一个 struct）；`restoreWizard` **降为低**（WebDAV 实为 `:1206+`）。
其余仍为中：`addPwd` · `gateway` · `keychainHW` · `memberWizard` · `migrationWizard` · `settings` · `startAddFp`。
**修正后的计数：高危 12 · 中危 8 · 低危 56**（原 12/9/55 因切片串边界而不准）。

### 3.3 低危 56 条（audit 修正后）

低危 = 该 View 的结构体切片里没有任何服务类引用（纯展示/导航/本地状态）。
**但低危不等于可以随便改**：仍受 PART3 的表面预算与 PART7 的闸门约束。

## 4. 回归断言（高危 12 条逐条）

做法：改造前后各跑一遍同样操作，断言**结果值相同**（不是「看起来一样」）。

| Destination | 断言 |
|---|---|
| `addDevice`（添加门锁） | 配网编排仍是 23→05→01→08×4→21→03，写入的 mac/密钥与改造前逐字节相同（对照 fixtures/golden.json） |
| `backupStudio`（备份工作台） | 生成的备份包字节与改造前一致（BackupCanonical 的规范化输出不变） |
| `backup`（备份与恢复） | 信封格式 version/iv/tag 不变；WebDAV 上传路径不变 |
| `credentials`（凭证与钥匙） | 增删改凭证后锁端收到的帧与改造前逐字节相同；本地台账 diff 为空 |
| `deviceHome`（锁） | 开锁指令帧不变；失败 rc 文案逐字不变 |
| `deviceInfo`（设备信息） | 复制出来的诊断文本逐字不变（含顺序） |
| `diagnostics`（诊断） | 每条自检项的判定与文案不变 |
| `firmware`（固件） | DFU 包解析结果与升级编排不变；cmd22 参数不变 |
| `focusUnlock`（专注开锁） | 服务调用参数与返回值不变 |
| `memberStacked`（成员叠放视图） | 服务调用参数与返回值不变 |
| `securityCenter`（安全中心） | 安全项开关映射不变；反锁语义不变 |
| `webDAVStudio`（WebDAV 备份） | 服务调用参数与返回值不变 |

## 5. 只改壳的页面

与协议、加密、备份格式强绑定的：「firmware」（DFU 包解析）、「backup」/「backupStudio」（信封格式）、
「credentials」/「credCenter」（凭证字节面）、「securityDestroy」（不可逆动作）。
这些页面**只允许**改视觉层，**任何**逻辑、顺序、文案、参数都不许动；改完必须跑 `node tools/golden.js --check` 并确认 exit 0。

## 6. 动手纪律

1. 按 Tab 分批，每批 8–10 条，**一批一跑闸门**（命令见 PART7 §5.1）。
2. 高危条**先写回归断言再动手**。
3. 低危条也不许顺手改文案 —— 文案属于行为。
4. 「数据 path」只作语义参考，**不要**据此建导航层级（见 §0 ②）。
---

## 7. 文件扇出（对抗审核补充：改一个文件会触及几个目的地）

76 个 Destination 枚举**互不重复**（无两个目的地指向同一个 View），但**多个目的地共处同一个 .swift 文件**：

| 文件 | 承载的目的地数 | 风险 |
|---|---|---|
| `App/UI/Sheets.swift` | **10** | 改视觉层时极易误触邻近 struct（本文件还包含大量 sheet 内容视图） |
| `App/UI/MemberCenterView.swift` | **10** | 同上 |
| `App/UI/CredentialCenterView.swift` | **8** | 同上 |
| `App/UI/BackupStudio.swift` | **6** | 高危（备份格式契约） |
| `App/UI/SettingsView.swift` | 4 | 含 32 个目的地的直呈入口（PART2 §3） |
| `App/UI/DeviceHomeView.swift` | 4 | 门面相关（deviceHome / focusUnlock 都在这） |
| `App/UI/SecurityCenterView.swift` | 4 | 高危（安全语义） |
| `App/UI/AchievementsView.swift` / `CareViews.swift` / `HelpCenter.swift` | 各 3 | 低危 |

**纪律**：在这 10 个文件里改动时，**以 struct 为边界**——先用 `grep -n "^struct \|^private struct "` 确认目标 struct 的起止行，
只改该区间；不要用「整文件替换色彩/字体」的手法（那会波及同文件内其它 9 个目的地，且 `uicoverage` 会一次性报一堆）。

**其余文件的实现落点已逐条核对**（对抗审核 AUDIT-C）：
`IntegrationCenterView → App/Intents/AppIntents.swift:430`、`LinkPrefsView → App/Core/LinkSenseKit.swift:643`、
`AutoCalView → App/Core/AutoOpen.swift:575`、`CareRemindersView → App/UI/AchievementsView.swift:605`、
`CapsuleComposeView → App/UI/AchievementsView.swift:560`、`MessagesView → App/UI/Sheets.swift:2896`、
`LocalFilesView → App/UI/BackupStudio.swift:2410`。
⇒ **视图不都在 App/UI/ 下**，有些在 `App/Core/` 与 `App/Intents/`；改之前先定位，别按目录想当然。
