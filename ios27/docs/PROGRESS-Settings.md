# PROGRESS · Settings 域（task-4）

写作用域：`ios27/App/Features/Settings/`（只新增文件，未改动 Design/ / Shell/ / 其它 Features/）

## 文件清单

| 文件 | 行数 | 一句话 |
|---|---|---|
| `SettingsModel.swift` | 198 | 设置域唯一的本机偏好模型：外观四档 / 本机密码位 / 备份时刻 / 自动开锁拒因 / 钥匙串台账，页面不各存副本。 |
| `SettingsParts.swift` | 327 | 设置域的语法层：`SettingsHeader`（34pt semibold + 一行状态）/ `SettingRow`（标签左、`FieldRow` 读数右、44pt 可点）/ `SettingToggle` / `SettingRule`（0.5pt 蚀刻线）/ `PasscodeSheet`（本机密码与胁迫码共用一条校验链）。 |
| `SettingsScreen.swift` | 340 | 设置 Tab 根：本机状态读数（密码 / 上次备份 / 自动开锁）做主角，四节各一行读数入口；空态给「添加门锁」出路；删除设备走键入锁名的两道闸。 |
| `AppearanceScreen.swift` | 196 | 主题 / 高对比 / 减少透明 + 密度 / 动效 + 时间制式，底部有会跟着档位变的样例读数，恢复默认只重置外观。 |
| `SecurityScreen.swift` | 221 | 本机密码（设 / 改 / 关）+ 胁迫码 + 锁端安全入口 + 开锁确认两项 + 只读试验模式；未设密码时给「先看看锁端安全」的出路。 |
| `BackupScreen.swift` | 226 | 加密/明文全量导出（密钥泄露警示常驻最上方）+ 粘贴/剪贴板恢复，恢复走二次确认与合并语义。 |
| `AutoOpenScreen.swift` | 173 | 走近自动开门主开关（默认关，fail-closed）+ 面容确认两档 + RSSI 距离标定 + 「上次没自动开的原因」。 |
| `HardwareScreen.swift` | 215 | 蓝牙钥匙串台账：每台一段三枚读数（电量/钥匙/固件）+ 写入/撤销 + 15 秒扫描；空态给「扫描钥匙串」。 |
| `AboutScreen.swift` | 145 | 累计开锁机械计数器（每位一格）+ 构建号 + 版本行连点 10 次展开离线声明。 |

## 未接真数据（全部标了 `TODO(engine)`）

| 位置 | 字段 / 链路 |
|---|---|
| SettingsModel · 外观 | `theme` / `density` / `motion` / `highContrast` / `reduceTransparency` —— 需 Design 令牌按档重建（现在只改状态，不改令牌） |
| SettingsModel · 开锁确认 | `holdConfirm` / `autoRetry` —— 需 Dial 与开锁链读这两个键（现在是常量行为） |
| SettingsModel · 时间 | `timeStyle` / `showSeconds` / `twoLineDate` —— `TimeFormat` 现在是常量格式，尚未读这三个键 |
| SettingsModel · 安全 | `hasPasscode` / `hasDuressCode` —— 摘要应落 SecretStore（PBKDF2-HMAC-SHA256，旧摘要验过即静默升级） |
| SettingsModel · 备份 | `lastBackupAt` —— 上次成功备份时刻（kf_backup_hist） |
| SettingsModel · 自动开锁 | `calibrationAt`（RSSI 门槛）/ `lastSkipReason`（core-auto 记账） |
| SettingsModel · 锁端 | `lockClockSyncedAt`（cmd0E 回执）/ `unlockTotal`（Milestones.unlockTotal） |
| SettingsModel · 硬件 | `DongleRecord.sample` / `.discovered` —— 应读 kf_keychain_dongles（按 mac 索引、空字段不覆盖旧值） |
| PasscodeSheet | 本机密码 / 胁迫码摘要落盘与空壳模式判据（LockGate 侧） |
| BackupScreen | `collectAll` + CryptoBox（PBKDF2-HMAC-SHA256 + AES-CBC + HMAC）+ canonical 序列化；导入侧「解密 → 内容哈希 → 升级链」的拦截 |
| AutoOpenScreen | 连锁后按 RSSI 采样 3~5 秒取中位数作为距离门槛 |
| HardwareScreen | BLE 扫描 15 秒（pid 16289 且广播带 MAC）；cmd41 写 ekey + cmd43/44 回读；cmd41 空 ekey 删除 |
| SettingsScreen · 门锁节 | `智能网关`「未绑定」应读 kf_gateways 台账（op=getDeviceStatus 刷新）；`布防`「未布防」应读 op=getDeviceSetting（defenceControl / StartTime / EndTime） |
| AboutScreen | 主题套数应由外观令牌表给出（现在写死 2 套：浅色 / 深色） |

> 说明：以上位置的相位机 / 样本值只驱动界面状态，**不伪造锁端回执**。所有写操作的界面文案据此写成
> 「命令已下发 / 已恢复 N 项」，不写成「锁端已生效」。

## 自查

`node Gates/swiftcheck.js` → OK（102 个文件括号/字符串/注释全平衡）
`node Gates/tokens.js` → OK（102 个文件 0 处硬编码样式字面量）

Settings 目录内逐项 grep：
- `Color(hex:` → 0
- `.padding(数字)` → 0
- `.system(size: 数字)` → 0
- `.bold()` → 0（唯一命中是 `SettingsParts.swift` 注释里那句纪律说明）
- `glassEffect` → 0
- 破坏性动作不用 `signal` 填充：删除设备走 `DangerAction`（填 `State.critical`），不用品牌色去按「删除」
- `.animation(` → 2 处，均带 `value:`（`AboutScreen` 的彩蛋展开、`AppearanceScreen` 的样例读数）

## 语法对齐

- 7 屏全部：`ScrollView` + `VStack(spacing: T.S.l)` + `CanvasBackground()` + `.scrollEdgeEffectStyle(.soft, for: .top)` + `.navigationTitle` + `.inline`
- 每屏一个 `SettingsHeader`（34pt semibold 大标题 + 一行状态），中文标题无 `.bold()`
- 每屏一个主角：Settings = 本机状态读数面板；Security = 本机数据保护读数；Backup = 导出面板；
  AutoOpen = 主开关面板；Hardware = 钥匙串台账；About = 机械计数器；Appearance = 主题档位
- 同屏只有一个 `PrimaryAction`（signal 填充）：Security 的「设置/更改本机密码」、Backup 的「生成备份」、
  AutoOpen 的「标定」、Hardware 的「扫描钥匙串」；Appearance 与 About 刻意无主动作（读数屏）
- 所有数字走 `Reading` / `FieldRow` / `ReadingGrid`；所有时间走 `TimeFormat`（clock / dayShort / ago）
- 设置页**不用系统 Form**：全部 `Panel` + `FieldRow` 语法
- 交互全部真：开关改 `SettingsStore` 状态并立即回读；行入口走 `router.request(.dest(...))`；
  空态给下一步；破坏性动作走 `confirmationDialog` + 键入锁名
