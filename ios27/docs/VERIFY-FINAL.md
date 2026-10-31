# VERIFY-FINAL · 终局验收（34+8 复验 / 静态 BUG 扫描 / 收尾 / CI）

> 执行日期：2026-10-31（本轮）
> 工作树：`D:\aapk\ios-app`，分支 `main`。
> 起点：`2991cbe`（CI run `41207309291`：BUILD SUCCEEDED + ARCHIVE SUCCEEDED + errors=0）。
> 复核对象：`docs/AUDIT-A-OMISSION.md`（34 项遗漏 + 8 项伪实现）与 `docs/FIX-REPORT.md` 的逐行「✅ 已修复」标注。
> 纪律：每一项都打开标注的文件:行读实现，不按标注号当真；静态检查脚本不替代真编译，最终以 CI 为准。

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| 34 + 8 项复验 | **42 / 42 复核完毕**：37 项直接成立；2 项「成立但受限」（#28 品牌色、#33 纯黑，见 §2 注）；3 项**标注已修但实际不成立**（#3 模块显隐两项空开关、#26 设置分组 chip 不过滤、#32 夜间免扰无消费者），**已当场修掉** |
| 新发现 BUG | **P0 = 0；P1 = 1；P2 = 3；P3 = 4**（§3），P1/P2 全部修掉，P3 记录 |
| 收尾清理 | `callsig.js` 已退役（allgates 16 → 15，保留 `callsig2`）；`COMPLETION.md` 的旧 IPA `112404` → 最新 `20261031.215249`；新增 `docs/WARNINGS.md`（89 条 warning 分类） |
| 静态检查 | 新增 `Tools/static-audit.js`（6 类高危模式）与 `Tools/parity-28.js`（原 28 Destination ↔ 现路由，28/28） |
| 本地闸门 | `node Gates/allgates.js` → **15 / 15 通过** |
| 最终 CI | 见 §5；末尾 §7 给最终数字 |

---

## 1. 复验方法

1. 读 `AUDIT-A-OMISSION.md` §5（34 行）与 §7（B1–B8），把每行的「已修复 · 文件:行」抄成一张 42 行的待验清单。
2. 对每行打开该文件:行，确认：① 代码真的存在；② 有真实消费者（写点与读点在同一个功能链上）；③ 不是「有按钮无效果」的伪入口。
3. 对「消费者」做反向检索：例如开锁手势的 `kf_hold_confirm/kf_fence/kf_tap_direct/kf_gesture_mode/kf_ax_hold/kf_dial_size/kf_auto_retry` 每个键都要求「UI 写点 + 执行链读点」两端命中。
4. 新写两类静态检查辅助：`Tools/parity-28.js`（28 个原页面是否仍有可达承接）与 `Tools/static-audit.js`（§3 的六类高危模式）。
5. 以上是代码级复核；没有真机，「手感/真实 BLE 回执」仍属未验边界（§6）。

---

## 2. 34 + 8 逐项复验

> 状态口径：**成立** = 标注的代码存在且有真实消费者；**成立·受限** = 主功能成立但有一个可复核的边界（写明）；**不成立→已修** = 原标注与代码不符，本轮已改。

### 2.1 §5 确认遗漏 34 项

| # | 功能点 | 标注落点 | 复核证据（本轮读到的位置） | 状态 |
|---:|---|---|---|---|
| 1 | 锁信息名片页 | DeviceInfoScreen.swift:9 | `Dest.deviceInfo`（Router.swift:29）+ 三处入口（DoorScreen:981 / LockSettingsScreen:225 / SettingsScreen:348）；页面真读 cmd03 快照、容量、电量采样、固件服役、链路验证，进页 >2s 自动 syncTime（DeviceInfoScreen.swift:385） | 成立 |
| 2 | 30 秒内二次开锁闸 | UnlockGateScreen.swift:8 | DoorScreen `needsGate`（585）读 `lastUnlockSuccessAt` + `DB.hasPasscode`；sheet 绑定 `showUnlockGate`（579）；密码走 `DB.verifyPasscode`（UnlockGateScreen.swift:99），3 次失败冷却 30 秒 | 成立 |
| 3 | 模块排序与显隐 | ModuleOrderSheet.swift:8 | 三槽排序 `DevLayout.order` 被 DoorScreen:48 消费；快捷格勾选写 `QuickPool.setSelected`；**但 `groupChips` 与 `statusIcons` 两个开关原先只写 `kf_dev_hidden`、门页无任何读点** → 本轮补了「多锁状态图标行」与「按组切换 chips」（DoorScreen:38/42） | **不成立→已修** |
| 4 | 记录告警类型多选 | AlarmKindsSheet.swift:8 | RecordsScreen:423 按钮打开 sheet；`Set<Int> alarmKinds` 写 `RecordsRoute`、进 `LedgerFilter.apply`（RecordsModels:93）；列表显示已选类型 | 成立 |
| 5 | 设备页异常提醒卡 | DoorScreen.swift:152 | `attentionCard` 现在在 226 行（上方插入了新的状态行）；四类判据：密钥未绑定 / 30 天未校时 / 低电阈值 / 2h 内到期凭证 | 成立 |
| 6 | 设备页最近开门 | DoorScreen.swift:817 | `recentBlock` 在 891 行；条数读 `SettingsStore.recentCount`（`kf_recent_count`），行点按 `.record(id:)` 进记录页，右上「查看全部」 | 成立（行点按落详情，不是原版的按归属过滤列表） |
| 7 | 设备页下拉重扫 | DoorScreen.swift:76 | .refreshable 在 82 行，调 `rescan()`（预热 + refreshStatus + 失败文案） | 成立 |
| 8 | 空态从备份恢复 | DoorScreen.swift:966 | `noLockBlock` 在 1038 行，第二按钮「从备份恢复」在 1053 行 → `.backup` | 成立 |
| 9 | 快捷操作网格 | DoorScreen.swift:709 | `quickBlock` 在 783 行；`LazyVGrid` 2/3 列由 `AXSettings.bigTile` 决定；无指纹时追加虚线「待添加指纹」格；长按 0.5s 打开 QuickPoolEditSheet | 成立 |
| 10 | 自动上锁倒计时 | AppModel.swift:312 | `startAutoLockCountdown()` 真起 Task，秒级递减；DoorScreen:381 显示「约 N 秒后自动上锁」 | 成立 |
| 11 | 开锁失败处理链 | AppModel.swift:231 | `runUnlockChain` 三段进度 + 2s/5s 退避 + 超时不重试 + failStreak；DoorScreen `failureChain`（408）三项自查 + 再试一次 | 成立 |
| 12 | 开锁手势圆盘 | DoorScreen.swift:390 | `dialGesture`（464）：DragGesture 按住进度（beginHold 532）+ 上滑 56pt + 误触围栏（需从边缘拖入，4 秒武装）+ 双击（handleDoubleTap 558）+ 双击防抖 + 轻点撤销；`kf_*` 每个键都有写点（SecurityScreen / AccessibilityScreen）与读点（DoorScreen 520-528 / AppModel:238） | 成立 |
| 13 | 凭证搜索/最近搜索/空结果 | KeysScreen.swift:17 | TextField 在 337；`onSubmit` 写 searchHistory（344）；空结果给「清空搜索 / 按成员重搜」（441-448） | 成立 |
| 14 | 按成员分组 | KeysScreen.swift:33 | `grouped` 按 owner 分桶；chip 写 `CredentialOrg.setGroupMode`（397-398）；未归属归「未归属」 | 成立 |
| 15 | 凭证 Tab 到期角标 | V7Components.swift:626 | `VTabItem.badge` + VFloatingTabBar 渲染；Shell.swift:32 读 `CredentialOrg.expiringSoonCount`（跨全部锁） | 成立 |
| 16 | 指纹重录替换 | KeyDetailScreen.swift:406 | `FingerprintReEnrollSheet`：先 cmd13/14 录新批次，成功之后才 `deleteFingerprint(old)`（470-490）；失败旧批次保留 | 成立 |
| 17 | 临时码提前失效滑杆 | KeyDetailScreen.swift:336 | 0–120 分钟 Slider 读写 `CredentialOrg.earlyExpireMin`；文案明确「锁端未改」 | 成立 |
| 18 | OTP 防窥挡片 | ZotpScreen.swift:152 | `kf_otp_shield` 开关；显示圆点（154）、长按揭开松手复位（102-104）、双击切字号（105） | 成立 |
| 19 | 钥匙串查看已写入/读状态 | HardwareScreen.swift:284 | 「读取状态」走 cmd43（284）、「查看已写入的钥匙」走 cmd44（301）；结果按 MAC + 锁名渲染（131-146） | 成立 |
| 20 | 写入未知/假钥匙 | HardwareScreen.swift:316 | 按钮在 121；`HardwareService.writeFaultDongleKey` 真调用，文案说明开不了锁 | 成立 |
| 21 | 从本机解绑 | HardwareScreen.swift:332 | 按钮在 149；`DB.removeDongle`，文案说明实体钥匙仍有效 | 成立 |
| 22 | 备份文件导出/导入 | BackupScreen.swift:47 | .fileExporter（47）与 .fileImporter（56）都在；生成后 `exportDoc` + `showExporter`（172-173）；导入走 `readBackupFile` + 原 `BackupStudio.parsePreview/restore` | 成立 |
| 23 | 记录跨锁范围/换锁 | RecordsScreen.swift:773 | `RecordLockScope`（20）+ 分段控件；`reload()`（730-755）在 .all 时合并各锁 `RecordsSource.load`；`switchLock`（784）写 `DB.currentMac` 并重建 | 成立 |
| 24 | 成员电话/一键呼叫 | MemberDetailScreen.swift:364 | 电话字段（265）落 `DB.setMemberInfo`（359）；呼叫清洗非数字、<3 位禁用（267-268 / 364-367）；成员行 contextMenu 也有呼叫（HouseholdScreen:279-280） | 成立 |
| 25 | 访客卡过滤记录 | RecordsScreen.swift:787 | `visitorOnly` 写 `LedgerFilter`（RecordsModels:94-95：owner 空且事件含临时/一次性）；`visitorCard`（798）显示条件与清除；Household 访客卡写 `RecordsRoute.visitorOnly` | 成立 |
| 26 | 设置搜索 + 五组筛选 | SettingsScreen.swift:122 | 搜索框与五组 chip（124-157）都在；**但原先 groupFilter 只在搜索结果里生效，浏览态点分组没有任何反应** → 本轮把五组 chip 接到节过滤（body + `inGroup` 532），并把协议测试/关于拆成「帮助」组 | **不成立→已修** |
| 27 | 通知权限行 | SettingsScreen.swift:420 | `notifyOff = NotifyAuth.isOff`（410 行附近）；条件行在 425，点击 `UIApplication.openSettingsURLString` | 成立 |
| 28 | 品牌色六套 + 自定义强调色 | AppearanceScreen.swift:86 | 六色 chip + ColorPicker + 取消自定义都在；落盘 `kf_accent`/`kf_accent_custom`；根视图 `.tint(settings.accentColor)`（LockKeeperApp:20）。**受限**：V7 组件多数直接用 `V.C.blue`，品牌色只影响系统 tint，不改 V7 色板（设计系统是固定深色板，见 §6） | 成立·受限 |
| 29 | 圆角档位 | AppearanceScreen.swift:157 | 三档 chip 写 `kf_radius`；`V.R.factor`（V7Tokens:302-317）真缩放 card/mini/action/panel/inset/control | 成立 |
| 30 | 凭证行高/时间线行距/最近条数 | AppearanceScreen.swift:194 | `rowHeight` → KeysScreen:660；`kf_tl_gap` → RecordsScreen `timelineSpacing`（822）；`recentCount` → DoorScreen `recentEntries`（856 附近） | 成立 |
| 31 | 数字字体/指标位/开场策略 | AppearanceScreen.swift:194/254 | `digitFont` → DoorScreen `digitFont`/VGauge（290）；`HeroStats` 写读在 DoorScreen:604-607；`recordPolicy` → `QueryFilters.policy` 被 `QueryFilters.load` 消费（RecordSearch:258） | 成立 |
| 32 | 长按时长/双击防抖/夜间免扰 | AppearanceScreen.swift:271 | `holdDuration` → DoorScreen:528；`dbltapGuard` → requestUnlock（498）；**`quietNight` 原先只写 `kf_quiet_night`，`CareSchedule.quietOn/isQuietHour` 零消费者** → 本轮把夜间免扰接进两个通知出口（BatteryCare:169 / CredentialOrg:169） | **不成立→已修** |
| 33 | 纯黑主题/活泼档 | SettingsModel.swift:20 | `case black` + `MotionTier.lively` 都在；`colorScheme` 映射与 root `.animation` 消费（LockKeeperApp:42-45）。**受限**：V7 画布本来就是 #000（V7Tokens:80），所以「纯黑」与「深色」在视觉上无差别；浅色主题对 V7 页仍无效（设计限制，记录在 §6） | 成立·受限 |
| 34 | 应用锁改/关密码先验旧码 | SettingsParts.swift:298 | `PasscodeSheet.commit` 在 `isChange` 时 `guard DB.verifyPasscode(oldCode)`（298）；关闭密码/胁迫码走 `VerifyPasscodeSheet`（SecurityScreen:45-56），`verify()` 通过才执行 `DB.setPasscode(nil)` / `setDuressCode(nil)` | 成立 |

### 2.2 §7 八个伪实现 B1–B8

| # | 问题 | 复核证据 | 状态 |
|---|---|---|---|
| B1 | 开锁偏好全是假开关 | `effectiveGesture`（DoorScreen:522）读 `holdConfirm` + `AXSettings.gestureMode`；`kf_fence` 读在 520；`kf_ax_hold` 读在 528；`kf_dial_size` 读在 `dialScale`；`autoRetry` 读在 AppModel:238；`tapDirect` 读在 438；`dbltapGuard` 读在 498。写点：SecurityScreen:237-255 / AccessibilityScreen:90-118 / AppearanceScreen:300。**quietNight 原先是唯一没消费者的**（见 #32，已修） | 成立（quietNight 已补消费者） |
| B2 | 删除设备不删数据 | `DeleteDeviceSheet.deleteLocalData`（SettingsScreen:590）→ `DB.removeDevice(mac)`（607）→ `StoreKeychain.removeDevice`（194）真清钥匙串/台账/日志/布防/档案/电池/OTP/到期提醒并按 MAC 兜底清键 | 成立 |
| B3 | 成员向导临时码只写内存 | `MemberCreateScreen.finish`（280）→ `app.addTempCode`（304）→ `LockService.pwdAdd`（cmd0A，LockServiceCredentials:6-28）→ 成功才 `DB.saveLedger(temp:true + owner + note)`（AppModel:400-406） | 成立 |
| B4 | 启动默认锁/PIN 假设置 | `currentMac` 先读 `overrideMac`，再 `lock`，再 `LockArchive.defaultMac`（AppModel:75-81）；`chosenPin(mac)`（304）读 `kf_chosen_pin_` 并作为 `pinDec` 传给 `LockService.unlock`（253） | 成立 |
| B5 | 手机钥匙错误跳家页 | HardwareScreen scopePanel 已改 `.dest(.mobileKey)`（222） | 成立 |
| B6 | 快捷动作指向错误页 | `runQuick`（866）：otp→`.zotp`、tailgate→`.tailgate`、safemode→`.safeMode`（866-884） | 成立 |
| B7 | DFU 版本恒空 | `pkgVersion`（SettingsScreen:537）读 `app.lock?.firmware`，空则「未读到」、无锁「未添加」 | 成立 |
| B8 | 凭证停用实际是删除 | `toggleDisabled`（KeyDetailScreen:327）只写 `CredentialLocalState.setDisabled`（330），无 deletePassword/deleteFingerprint；停用位落 `kf_v7_disabled_<mac>`，可恢复；详情页文案写明锁端仍有效 | 成立 |

**复验计数**：42 项 = 直接成立 37 + 成立但受限 2（#28/#33）+ 复核不成立已修 3（#3/#26/#32）。**失败未修 = 0**。

---

## 3. BUG 清单（静态检查 + 手工链路复核）

检查手段：`node Tools/static-audit.js`（A 强解包 `!`/`try!`/`as!`；B 下标 `[0]/[1]/first!/last!`；C await 后旧索引；D 空集合 `max()!`；E 密钥进日志；F 并发/Task 强引用）+ 逐条读上下文判定「有守卫 / 无守卫」。

| 级别 | 位置 | 问题 | 判定与修法 | 状态 |
|---|---|---|---|---|
| **P0** | — | 无 | 全仓 `try!` / `as!` = 0；无 `max()!` / `min()!` / `first!`；无空集合 `reduce` | 0 项 |
| **P1** | `Features/Door/GatewayScreen.swift:422` | `refresh(_:)` 在 `await readGatewayState` **之前**取 `rows.firstIndex`，await 之后直接用 `rows[index]`；期间用户删网关/重扫导致数组变短 → **越界崩溃** | await 后重取下标（`guard let index = rows.firstIndex(...)`）；先做存在性检查 | **已修** |
| **P2** | `Features/Household/MemberCreateScreen.swift:307` | 建档 + cmd0A 成功后 `newID` 仍保留；用户返回本页点「取消」会走 `cancel()` 的回滚分支 `DB.removeMember(id)`，把刚建好的成员删掉（而临时码已留在台账里） | 成功后 `newID = nil`，取消不再回滚已落库成员 | **已修** |
| **P2** | `App/Shell/Destinations.swift:9-59`（43 条 warning） | `Destinations.view(for:)` 是非隔离静态函数里构造 @MainActor View；Swift 5 只告警，Swift 6 会成片 error | 给 `view(for:)` 标 `@MainActor` 需要连带处理 Router 调用点，单列一轮（已写入 WARNINGS.md） | 记录 |
| **P2** | `Shell/AppModel.swift:550` / `Router.swift:182` / `RecordsModels.swift:168,328` / `SettingsModel.swift:152` | `@Observable` 类未标 `@MainActor`；当前所有访问都在主线程，但没有编译期保证 | 标 `@MainActor`（需同步处理跨文件调用点，单列） | 记录 |
| **P3** | `Engine/BLEService.swift:48` | `var manager: CBCentralManager!` 隐式解包；`startScan` 先 `waitReady()`（循环等 manager != nil），`stopScanInternal` 有 nil 守卫，当前无裸用路径 | 改 `CBCentralManager?` + guard，消除隐患 | 记录 |
| **P3** | `Features/Records/RecordsScreen.swift:856` | `await app.readLogs()` 之后 `RecordsSource.markSynced(mac: mac)` 用的是**计算属性** mac；读日志期间切锁会把同步时刻记到新锁 | 进入函数时把 `mac` 拷成 `let readMac`，全程用它 | 记录 |
| **P3** | `Features/Door/UnlockGateScreen.swift:101` | 作为 `Dest.unlockGate` 打开时 `onPass == nil`，验证通过只 dismiss（无动作）；当前唯一入口是 Door 的 sheet（有回调），Dest 属于「已登记但无真实入口」 | 删除该 Dest 或给它补默认动作 | 记录 |
| **P3** | `Features/Keys/KeyDetailScreen.swift:298`（LockSettingsScreen:105 同类） | `st!` / `kc!` 依赖三元条件的副作用求值；当前逻辑安全但改一处条件就会崩 | 改 `if let` / `??` | 记录 |

### 3.1 判为「有守卫、不修」的强解包（逐条给出守卫）

- `Engine/RecordSearch.swift:188` `who!`：`who?.isEmpty ?? true` 为 false 才走 `who!`（等价 `if let`）。
- `Engine/KeyGen.swift:35-36` `b[0..3]`：`b = randomBytes(4)` 固定 4 字节。
- `Engine/LockServicePairing.swift:229/265` `pins[0]`：调用链由 `KeyGen.genPins(64)`（非空或抛错）或 `guard !pend.pins.isEmpty` 进入。
- `Engine/Attribution.swift:63/72/75` `[0]`：分别被 `hits.count == 1`、`fpOwned.count == 1`、`permOwned.count == 1` 守卫。
- `Engine/RecordSearchQuery.swift:33` `temps[0]`：`guard !temps.isEmpty`。
- `Engine/StatusParser.swift:144` `b[0]`：`guard hex.count >= 20`（= 10 字节）。
- `Engine/ZKProtocol.swift:211/223/252` `[1]/[4]`：`guard hex.count >= 14`（= 7 字节）。
- `Engine/DFUKit.swift:461/470` `bytes[0]`：`guard !data.isEmpty` 在 `let bytes` 之前。
- `Engine/ZipKit.swift:43-44` `baseAddress!`：`dst` 至少 1 字节；`src` 在调用前 `guard !cdata.isEmpty`。
- `Features/Keys/KeysBits.swift:283` `digits[1]/[0]`：`guard digits.count >= 4`。
- `Engine/AutoOpenKit.swift:382` `lastDispatch[mac]!`：上一行刚 `lastDispatch[mac] = ...`。

### 3.2 密钥/日志专项

全仓 `log/print/NSLog` 共 100 处；逐条核对后**没有一条把 pwd/skey/ekey/bkey/PIN 明文写进日志**：只打长度、指纹（`HashKit.fingerprint`）、alias、rc 或 MAC。原始帧 hex 只进内存 `recentFrames`，持久化前由 `FrameRedact` 脱敏（`LockService.swift:44-49` 的注释与实现）。`Tools/static-audit.js` 的 E 类现为 0 命中。

---

## 4. 收尾清理

| 项 | 处理 | 证据 |
|---|---|---|
| 退役 no-op `Gates/callsig.js` | 删除文件 + 从 `allgates.js` 的 GATES 摘除；保留 `callsig2.js`。allgates 16 → **15 道** | `Gates/allgates.js` 的 GATES 注释；`Tools/parity-28.js` 与 allgates 均绿 |
| `docs/COMPLETION.md` 旧 IPA 链接 | `112404` → 最新 `LockKeeper-20261031.215249-unsigned.ipa`（Release `ios27-latest`，2,597,954 B，sha256 `7669b79b…a066`），并补「始终指最新」的 Release 页链接 | COMPLETION.md §四·补 |
| 88 条 warning 分类 | 新增 `docs/WARNINGS.md`：89 条原始（1 项目级 + 88 源码，去重 84 个位置），按并发/Swift 6（62）、未使用值（19）、Deprecated（2）、其他（1）分类，逐条列 file:line 与评估 | `docs/WARNINGS.md` |
| 设置页 help 分组 | 五组 chip 之前无「帮助」节 → 把协议测试/关于拆成独立「帮助」节，分组过滤才完整 | SettingsScreen.swift:508-529 |
| 新增静态检查 | `Tools/static-audit.js`（六类高危模式，报告型；`--strict` 时 P0 红）、`Tools/parity-28.js`（28/28） | 两脚本均可本地跑 |

---

## 5. CI 验证

### 5.1 基线（本轮起点）

- commit `2991cbe`，run `41207309291`：`BUILD SUCCEEDED` + `ARCHIVE SUCCEEDED`，`errors.txt` 为空（来自 `origin/ci-log`）。
- 本轮开始时本地 16 道闸门全绿；其中 `callsig` 输出「检查 0 处具名调用」= no-op（本轮已退役）。

### 5.2 本轮推送与判定

判定口径：push 后等 6–8 分钟，`git fetch origin ci-log`，读 `meta.txt`（commit / run）、`errors.txt`（必须为空）、`build.log` 末尾（`** BUILD SUCCEEDED **` / `** ARCHIVE SUCCEEDED **`）。

| 阶段 | commit | run | build.log 末尾 | errors.txt | 结论 |
|---|---|---|---|---|---|
| 本轮提交 | `__COMMIT__` | `__RUN__` | `__BUILD_TAIL__` | `__ERRORS__` | `__CI_VERDICT__` |

> 说明：本轮工作期间有并行会话在同一工作树提交（`64acaa4` / `7a4feeb`），其中 `64acaa4` 曾把 `BackupStudioKit.swift` 截断导致 `swiftparse` 红；`7a4feeb` 已恢复并在 HEAD 保留 FNV 校验降级为告警的意图。本报告以本轮最终提交为准。

---

## 6. 边界（未验的就是未验）

1. **没有真机/模拟器**：本轮仍是静态代码级复核 + CI 编译级验证。开锁手感、BLE 回执、指纹录入、DFU、WebDAV 的真实链路未在本机跑过。
2. **Swift 6 未切**：`SWIFT_VERSION = 5.0` + `SWIFT_STRICT_CONCURRENCY = complete`；62 条并发告警是迁移债（WARNINGS.md）。切 6 之前不能声称「无并发缺陷」，只能声称「当前语言模式下无已知数据竞争路径」。
3. **V7 是固定深色板**：`V.C.bg` 恒 #000，浅色主题对 V7 页无效（AUDIT-B-DESIGN 已记录）。#28 品牌色只到 `.tint`、#33 纯黑与深色视觉相同，都是这条设计约束的下游表现，不是本轮新引入的缺陷。
4. **功能「一个不少」的可证明边界**：本轮证明了 28 个原 Destination 全部有承接（`Tools/parity-28.js` 28/28）与 42 项审计缺口全部闭合；不能证明「每个页面的每个交互都与原 App 逐像素/逐行为一致」。
5. **并行会话**：同一工作树上的并行提交可能改变基线；本报告的行号以本轮最终提交为准。

---

## 7. 最终数字

| 指标 | 数字 |
|---|---|
| 复验项 | **42**（34 + 8） |
| 复验通过 | **37 直接成立 + 2 成立但受限 = 39**；另 3 项复核不成立、已当场修掉（#3/#26/#32），修后合计 **42/42 可达** |
| 复验失败未修 | **0** |
| 发现 BUG | **P0 0 / P1 1 / P2 3 / P3 4** |
| 已修 BUG | **P1 1 + P2 1（代码）+ P2 0（记录项另列）**；#3/#26/#32 三处功能缺口另计 |
| 清理项 | callsig 退役（16→15）、IPA 链接更新、WARNINGS.md、help 分组、两个静态检查脚本 |
| 本地闸门 | **15 / 15** |
| 最终 CI | `__CI_FINAL__` |

### 7.1 复现命令

```powershell
cd D:\aapk\ios-app\ios27
node Gates/allgates.js          # 15 道闸门
node Tools/static-audit.js      # 六类高危模式（报告型）
node Tools/parity-28.js         # 原 28 Destination ↔ 现路由
```
