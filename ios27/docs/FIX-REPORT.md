# FIX-REPORT · AUDIT-A 遗漏与伪实现修复

> 执行日期：2026-10-31
> 依据：`docs/AUDIT-A-OMISSION.md` §3 / §5 / §7 / §8
> 约束遵守：只调用 `App/Engine/**`，未修改任何 Engine 文件；界面全部使用 `App/Design/V7` 的 `V.*` 令牌与组件；未引入旧 `T.* / Ink.* / Panel(`。

---

## 0. 一句话结论

**P0 6 项全部完成；P1 功能缺失 28 项全部接上入口与消费者；P2 4 个整页/面板全部补路由或入口。**
`node Gates/allgates.js` 本地 **15 / 15 通过**。AUDIT-A 的 §5 34 行与 §7 8 行均已标注「✅ 已修复 · 文件:行」。

---

## 1. P0（数据 / 正确性，全部完成）

| # | 问题 | 修复落点 | 行为 |
|---:|---|---|---|
| P0-1 | 删除设备只 `app.lock = nil` | `Features/Settings/SettingsScreen.swift:590` `deleteLocalData()` | 调 `DB.removeDevice(mac)`：钥匙串 + 台账 + 日志缓存 + 快照 + 布防/自动上锁/锁档案/电池采样/OTP/到期提醒整族清除，再清界面投影 |
| P0-2 | 凭证「停用」实际调 deletePassword/deleteFingerprint | `Features/Keys/KeyDetailScreen.swift:327` + `Shell/AppModel.swift` `CredentialLocalState` | 改为本机停用位（`kf_v7_disabled_<mac>`），可恢复；锁端一条命令都不发；详情页明确写「锁端仍有效」 |
| P0-3 | 成员向导初始临时码只写内存 | `Features/Household/MemberCreateScreen.swift:280` + `AppModel.addTempCode` | cmd0A 真下发 → 成功才 `DB.saveLedger`（temp=true + owner + note）；退出/刷新后仍在台账里 |
| P0-4 | 更改/关闭本机密码与胁迫码不验旧码 | `Features/Settings/SettingsParts.swift:298` `PasscodeSheet` + `VerifyPasscodeSheet`；`SecurityScreen` 关闭流程 | 更改密码/胁迫码先 `DB.verifyPasscode(oldCode)`；关闭密码/胁迫码先弹 `VerifyPasscodeSheet`，验证通过才执行 |
| P0-5 | DoorScreen 快捷动作 otp/tailgate/safemode 指向错误页面 | `Features/Door/DoorScreen.swift:787` `runQuick` | otp→`.zotp`，tailgate→`.tailgate`，safemode→`.safeMode` |
| P0-6 | 锁档案「启动默认锁 / 开锁 PIN」无消费者 | `Shell/AppModel.swift:294` `chosenPin` + `currentMac` | 冷启动无当前锁时先落 `LockArchive.defaultMac`；开锁把选中的第 N 枚 PIN 作为 `pinDec` 传给 `LockService.unlock` |

---

## 2. P1（功能缺失，全部接上）

### 2.1 设备页 / 开锁（#5–#12）

- **Hero 卡**：`DoorScreen.swift` `summaryBlock` —— 锁符号 / 名称 / 场所 / 三态胶囊 / RSSI / 电量·信号·固件·锁钟·钥匙读数 / 预计可用与更换日期。
- **异常提醒卡**：`attentionCard` —— 密钥未绑定、超过 30 天未校时、低电阈值（`CareSchedule.battThreshold`）、2 小时内到期凭证（`CredentialOrg.dueSoonPwds`）。
- **最近开门**：`recentBlock` —— 条数读 `kf_recent_count`（3/5/10），点行带 `.record(id:)` 上下文进记录页，右上「查看全部」。
- **下拉重扫**：`.refreshable { await rescan() }` —— 预热 + `refreshStatus`，失败写「重扫失败 · 原因」。
- **空态从备份恢复**：`noLockBlock` 第二按钮 → `.backup`。
- **自动上锁倒计时**：`AppModel.startAutoLockCountdown()` —— 开锁成功后按 `DB.tailgate(mac)?.interval ?? 6` 起秒级倒计时，门页显示「约 N 秒后自动上锁」。
- **失败处理链**：`AppModel.runUnlockChain()` —— 3 次自动重试（2s/5s，超时不重试）、`failStreak`、三段进度、失败三项自查清单与「再试一次」。
- **开锁手势圆盘**：`DoorScreen.dialGesture` —— 按住确认（时长 `kf_ax_hold` 0.4–1.6s）、上滑、误触围栏（`kf_fence`）、双击直开（`kf_tap_direct`）、双击防抖（`kf_dbltap_guard`）、轻点撤销等待；`kf_gesture_mode` 与 `kf_hold_confirm` 都有读点。

### 2.2 凭证（#13–#18）

- **搜索 / 最近搜索 / 空结果兜底**：`KeysScreen.swift:17` —— 名称/归属/类型/码值过滤，`CredentialOrg.searchHistory/pushSearchHistory`，空结果给「清空搜索 / 按成员重搜」。
- **按成员分组**：`KeysScreen.swift:33` `grouped` + 筛选行「按成员分组」chip，写 `CredentialOrg.setGroupMode`。
- **Tab 近 7 日到期角标**：`V7Components.swift:626` `VTabItem.badge` + `Shell.tabItems` 读 `CredentialOrg.expiringSoonCount`。
- **指纹重录替换**：`KeyDetailScreen.swift:406` `FingerprintReEnrollSheet` —— cmd13/14 录新的，成功后才删旧批次；失败旧批次保留。
- **临时码提前失效滑杆**：`KeyDetailScreen.swift:336` `earlyExpireCard` —— 0–120 分钟，读写 `CredentialOrg.earlyExpireMin`，文案明确「只在本机提示，锁端未改」。
- **OTP 防窥挡片**：`ZotpScreen.swift:152` —— `kf_otp_shield` 开关；挡片开启时显示圆点、长按揭开松手复位、双击切字号。

### 2.3 备份 / 钥匙串（#19–#22）

- **fileExporter**：`BackupScreen.swift:47` + `BackupDoc: FileDocument` —— 生成后可「存到文件」（文件名含锁名与日期）。
- **fileImporter**：`BackupScreen.swift:56` —— 从「文件 / iCloud 云盘」选备份文本，安全作用域 URL 成对开关，读入后走原 `BackupStudio.parsePreview/restore`。
- **查看已写入的钥匙**：`HardwareScreen.swift:284` `loadKeys`（cmd44）。
- **手动读状态**：同文件 `readState`（cmd43），显示电量/钥匙数/固件。
- **写入未知/假钥匙**：`HardwareScreen.swift:316` `writeFault`（随机 PIN、永久、不绑成员）。
- **从本机解绑**：`HardwareScreen.swift:332` `unbind`（`DB.removeDongle`，文案说明实体钥匙仍有效）。

### 2.4 记录 / 成员（#4、#23–#25）

- **告警类型多选**：`AlarmKindsSheet.swift:8` + `RecordsScreen` 「告警类型」按钮；`LedgerEntry.rawType` 从 cmd16 type 落库，`LedgerFilter.apply` 按 `Set<Int>` 过滤；记录页显示已选类型。
- **跨锁范围 / 换锁**：`RecordsScreen.swift:773` `switchLock` + `RecordLockScope`（当前锁/全部锁）；全部锁模式合并各锁 `RecordsSource.load` 缓存，换锁写 `DB.currentMac` 并重载。
- **成员电话 / 一键呼叫**：`MemberDetailScreen.swift:364` `call` + 档案里的电话字段（`DB.setMemberInfo`）；成员行 contextMenu 也有「呼叫」。
- **访客卡按访客过滤**：`HouseholdScreen` 访客卡写 `RecordsRoute.visitorOnly = true` 并切记录 Tab；`RecordsScreen.visitorCard` 显示过滤条件与「清除」，过滤口径 = owner 为空且事件含「临时/一次性」。

### 2.5 设置 / 外观（#26–#33）

- **设置搜索 + 五组筛选**：`SettingsScreen.swift:122` `searchBlock` —— 搜索命中行直达子页；五组 chip（日常/安全与钥匙/数据/外观/帮助）过滤节。
- **通知权限行**：`SettingsScreen.swift:420` —— `NotifyAuth.isOff` 时显示「通知权限 · 到期提醒不会送达」，点击去系统设置。
- **品牌色六套 + 自定义强调色**：`AppearanceScreen.swift:86` `accentPanel` + `SettingsStore.accent/accentColor/setCustomAccent`；根视图 `.tint(settings.accentColor)`。
- **圆角档位**：`AppearanceScreen.swift:157` `geometryPanel` + `V.R.card/mini/action/panel/inset/control` 按 `kf_radius` 缩放。
- **凭证行高 / 时间线行距 / 最近开门条数**：`AppearanceScreen.swift:194` `readoutPanel`；`KeysScreen` 行高、`RecordsScreen.timelineSpacing`、`DoorScreen.recentCount` 三个消费者。
- **数字字体 / 指标位 / 记录开场策略**：`AppearanceScreen.swift:194/254`；`VGauge.numberFont`、`HeroStats`、`QueryFilters.policy` 均有消费者。
- **长按时长 / 双击防抖 / 夜间免扰**：`AppearanceScreen.swift:271` `carePanel`；`DoorScreen.holdDuration`、`requestUnlock` 防抖、`CareSchedule.quietOn`。
- **纯黑主题 / 活泼档**：`SettingsModel.swift:20` `case black` + `MotionTier.lively`；`RootView` 用 `theme.colorScheme` 与 `motion` 决定动画。

### 2.6 应用锁（#34）

- `PasscodeSheet` 更改密码/胁迫码先验原本机密码；`SecurityScreen` 关闭密码/胁迫码走 `VerifyPasscodeSheet`，验证通过才执行关闭。

---

## 3. P2（路由与页面）

| 页面/面板 | 路由/入口 | 实现 |
|---|---|---|
| DeviceInfoView | `Dest.deviceInfo`；Door 快捷入口、锁设置「更多」、设置搜索 | `Features/Door/DeviceInfoScreen.swift` —— cmd03 读数 / Boot·键盘版本 / 容量 / 电量采样图 / 链路验证 / 锁钟偏差 / 进页 >2s 自动校时 |
| UnlockGateView | `Dest.unlockGate`；Door 圆盘 30 秒内二次开锁自动弹 sheet | `Features/Door/UnlockGateScreen.swift` —— 本机密码 + 3 次失败冷却 30 秒 |
| moduleOrderSheet | `Dest.moduleOrder`；Door 芯片行「版面·模块」、设置门锁节 | `Features/Door/ModuleOrderSheet.swift` —— 三槽排序 `kf_dev_order`、模块显隐 `DevModuleStore`、快捷格勾选、恢复默认 |
| AlarmKindsSheet | `Dest.alarmKinds`；记录页「告警类型」 | `Features/Records/AlarmKindsSheet.swift` —— `StatsKit.alarmTypes` 多选，写 `RecordsRoute.alarmKinds` |

---

## 4. §7 八个伪实现

| 编号 | 修复 |
|---|---|
| B1 | 开锁偏好全部有读点：holdConfirm/gestureMode/fence/tapDirect/dbltapGuard/ax_hold/dialSize/autoRetry 都进入 `DoorScreen` 手势与 `AppModel` 重试链 |
| B2 | 删除设备接 `DB.removeDevice` |
| B3 | 向导临时码 cmd0A 落库 |
| B4 | 启动默认锁 + chosenPin 消费者 |
| B5 | 钥匙串页「手机钥匙」改跳 `.mobileKey` |
| B6 | otp/tailgate/safemode 三个快捷动作改对路由 |
| B7 | 固件升级行右侧改为当前锁固件版本（读不到写「未读到」，不留空） |
| B8 | 停用改本机可恢复状态，不删锁端 |

---

## 5. 闸门结果

```text
$ node Gates/allgates.js
swiftparse: OK — 148 个 Swift 文件无语法错误（已知语法盲区豁免 14 处）
types: 148 个文件，368 个顶层类型，SDK 白名单 332 项
swiftcheck: OK — 148 个文件括号/字符串/注释全部平衡
tokens: OK — 148 个 Swift 文件，0 处硬编码样式字面量（含 V7 字号/色板）
contrast: 解析到 11 个旧色令牌 × 2 模式 + 57 个 V7 色令牌
glass: 扫 148 个文件，自定义玻璃面 0 处
motion: 扫 148 个文件，.animation 调用 13 处
a11y: 扫 148 个文件
dynamictype: 148 个文件，800 处走令牌字号（其中 V7 800 处经 VFont/@ScaledMetric）
reducedmotion: 21 处已守卫
crosprivate: 检查 7 组 Screen+Parts 拆分
callsig: 跟踪 14 个组件，检查 0 处具名调用
lineage: OK — 148 个文件，0 处上一版设计系统残留
workflow: 检查 1 个文件
destmap: Dest 44 项，映射 44 项，已声明 View 147 个

allgates: 全部 15 道闸门通过
```

---

## 6. 剩余 / 已知边界（没有假装修好的部分）

1. **本机无 Swift/Xcode**：以上是静态闸门 + 代码级核对；当前工作树的真编译结论要等下一次 GitHub Actions build。CI 若报错，优先看本轮新增的 `DeviceInfoScreen / UnlockGateScreen / ModuleOrderSheet / AlarmKindsSheet / FingerprintReEnrollSheet / BackupDoc` 与 `DoorScreen` 手势段。
2. **开锁 PIN 的 Engine 优先级**：`LockService.unlock(mac:pinDec:)` 在 `kc.ekey` 非空时优先用 ekey（Engine 既有行为，本轮按约束未改）。`chosenPin` 已真实传入并消费；对 ekey 为空的锁才改变签名 PIN。若要让所有锁都强制用选中 PIN，需要改 Engine 的 `unlock` 优先级（本轮不允许）。
3. **30 秒二次开锁闸的计时**：`lastUnlockSuccessAt` 是进程内状态；杀进程后重开不会保留（原版也以本次会话为主）。冷启动本来就有本机密码闸。
4. **本机停用位不进备份包**：`kf_v7_disabled_<mac>` 是新增本机键，`BackupKit.collectAll` 未包含它；恢复备份后停用位不会跟着回来（凭证本身在）。要进备份需改 Engine 的 BackupBundle/BackupKit（本轮不允许）。
5. **告警类型范围**：按审计建议读 `StatsKit.alarmTypes`（4 静态电量 / 10 多次密码失败锁定）。`RecordsSource` 另有 7/13/224 的告警色映射，但那几类没有 `RecordVerbs` 文案，未放进多选面板。
6. **模块排序槽位**：`DevSlot` 只排「状态卡 / 快捷格 / 最近开门」三槽（与原版三个可排序槽一致）；`DevModule` 的显隐只有 groupChips/statusIcons/linkSense 三项（Engine 既有枚举），没有自行发明更多模块。
7. **文件导入格式**：`fileImporter` 接受 `.plainText / .json`；导入内容仍走原 `BackupStudio.parsePreview` 的 schema/checksum/口令校验，不绕过。

---

## 7. 本轮改动文件（新增 / 修改）

新增：
- `App/Features/Door/DeviceInfoScreen.swift`
- `App/Features/Door/UnlockGateScreen.swift`
- `App/Features/Door/ModuleOrderSheet.swift`
- `App/Features/Door/DoorLayout.swift`
- `App/Features/Records/AlarmKindsSheet.swift`

主要修改：
- `App/Shell/AppModel.swift`（addTempCode / 停用位 / 默认锁 / chosenPin / 重试链 / 倒计时）
- `App/Shell/Router.swift`、`App/Shell/Destinations.swift`、`App/Shell/Shell.swift`
- `App/Features/Door/DoorScreen.swift`（Hero / 异常 / 最近 / 重扫 / 空态 / 倒计时 / 失败链 / 手势 / 快捷格 / 模块排序）
- `App/Features/Door/LockSettingsScreen.swift`（锁信息名片入口）
- `App/Features/Keys/KeysScreen.swift`、`KeyDetailScreen.swift`、`ZotpScreen.swift`
- `App/Features/Settings/SettingsScreen.swift`、`SettingsParts.swift`、`SettingsModel.swift`、`AppearanceScreen.swift`、`SecurityScreen.swift`、`HardwareScreen.swift`、`BackupScreen.swift`
- `App/Features/Records/RecordsScreen.swift`、`RecordsModels.swift`
- `App/Features/Household/HouseholdScreen.swift`、`MemberDetailScreen.swift`、`MemberCreateScreen.swift`
- `App/Design/V7/V7Tokens.swift`、`V7Components.swift`
- `App/LockKeeperApp.swift`
- `docs/AUDIT-A-OMISSION.md`（逐行标注）

---

## 8. 复核命令

```powershell
cd D:\aapk\ios-app\ios27
node Gates/allgates.js
# 逐项定位：
Select-String -Path docs/AUDIT-A-OMISSION.md -Pattern '已修复'
```
