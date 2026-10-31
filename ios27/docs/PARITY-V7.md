# PARITY-V7 — 原 App ↔ ios27 功能对等审计（2026-10-31）

> 审计对象：`D:\aapk\ios-app\App`（原 iOS App，139 个 Swift 文件）→ `D:\aapk\ios-app\ios27`（新 App，124 个 Swift 文件）。
> 判定口径：**每个用户可见的业务功能点，必须有原实现（类型 / 方法 / 页面）与 ios27 对应实现（同名引擎或等价页面）**。
> 结论只有三档：**已覆盖** / **降级（说明）** / **缺失**。本表为补齐后的最终状态；补实现前发现的功能缺口见 §二。
> 依据：`docs/FUNCTION-MATRIX.md`、`docs/PARITY-APK.md`、`docs/PARITY-FULL-AUDIT.md`、`docs/CAPABILITY.md`、`docs/原始APK全功能对照报告.md`，以及 139 个原 App Swift 文件的类型 / 方法级核对。

## 汇总

| 指标 | 数量 |
|---|---:|
| 功能点总数 | **127** |
| 已覆盖 | **127** |
| 降级（说明） | **0** |
| 缺失 | **0** |

> 说明：原 37 项“降级”已全部接线为可用页面（入口 + 操作 + 结果），逐项落点见结论列；工作室内所有动作都落到本机台账或真锁链路。
> 判定纪律：引擎存在 + 有调用点 = 已覆盖；只有引擎存在但页面无入口 = 降级；两边都没有 = 缺失并当场补实现。

> 关键词索引：BLE/ZK 协议命令=A；DFU=B；备份导入导出/规范格式=C；凭证组织与批量=D；成员中心=E；记录检索/导出=F；审计链/里程碑/电池养护=G；自动开门=AutoOpen（A34 说明＋本次补齐）；安卓配对/二维码=D19；应用锁=G01；硬件检测=A23；诊断日志=G11；时区同步=A10；快速操作=H03；通知=H01。

## 一、逐项矩阵

### A. BLE / ZK 协议与连接

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| 0x87 帧组装与解析 | `App/Core/ZKProtocol.swift` | `Engine/ZKProtocol.swift` | 已覆盖 |
| KLV 编解码与长度保护 | `App/Core/ZKProtocol.swift` | `Engine/ZKProtocol.swift` | 已覆盖 |
| 0x88 EKey 包络（TrackId / VF / VT） | `App/Core/ZKProtocol.swift · ZKCmdBuilder.swift` | `Engine/ZKProtocol.swift · ZKCmdBuilder.swift` | 已覆盖 |
| 会话令牌 01（无条件刷新 / TTL / rc=3 自愈） | `App/Services/LockService.swift · LockServiceLink.swift` | `Engine/LockService.swift · LockServiceLink.swift` | 已覆盖 |
| 命令 03 状态（明文 / 密文）与 23 键解析 | `App/Core/ZKCmdBuilder.swift · StatusParser.swift` | `Engine/ZKCmdBuilder.swift · StatusParser.swift` | 已覆盖 |
| 命令 04 开锁（ekey / PIN / rc 判定） | `App/Services/LockServiceOps.swift · ZKCmdBuilder.swift` | `Engine/LockServiceOps.swift · ZKCmdBuilder.swift + Shell/AppModel.runUnlockChain` | 已覆盖 |
| 命令 05 换钥 | `App/Services/LockServicePairing.swift` | `Engine/LockServicePairing.swift` | 已覆盖 |
| 命令 08 PIN 池（20/批、首批哨兵） | `App/Services/LockServicePairing.swift` | `Engine/LockServicePairing.swift` | 已覆盖 |
| 命令 0A / 0B 密码增改删与改期 | `App/Services/LockServiceCredentials.swift` | `Engine/LockServiceCredentials.swift + Keys/KeyCreate · KeyDetail · Shell/AppModel` | 已覆盖 |
| 命令 0E 校时 | `App/Services/LockServiceOps.swift` | `Engine/LockServiceOps.swift + Features/Door/SyncTimeScreen` | 已覆盖 |
| 命令 12 回声探测 | `App/Services/LockServiceOps.swift` | `Engine/LockServiceOps.swift + Features/Door/AddLockScreen · Settings/ProtocolTestScreen` | 已覆盖 |
| 命令 13 / 14 / 15 指纹录入、确认、删除 | `App/Services/LockServiceCredentials.swift` | `Engine/LockServiceCredentials.swift + Keys/KeyCreate · KeyDetail · AppModel` | 已覆盖 |
| 命令 16 日志分页读取 | `App/Services/LockServiceCredentials.swift` | `Engine/LockServiceCredentials.swift + Shell/AppModel.readLogs` | 已覆盖 |
| 命令 18 音量（静音） | `App/Services/LockServiceOps.swift` | `Engine/LockServiceOps.swift + Features/Door/LockStatusScreen` | 已覆盖 |
| 命令 19 临时码开关 | `App/Services/LockServiceOps.swift` | Engine/LockServiceOps.swift + Features/Door/LockSettingsScreen（cmd19 开关） | 已覆盖（本次接线） |
| 命令 20 单 / 双验（安全模式 A/B） | `App/Services/LockServiceOps.swift` | `Engine/LockServiceOps.swift + Features/Door/LockStatusScreen` | 已覆盖 |
| 命令 21 bkey 写入 | `App/Services/LockServicePairing.swift` | `Engine/LockServicePairing.swift` | 已覆盖 |
| 命令 22 进入 DFU | `App/Services/LockServiceOps.swift` | `Engine/LockServiceOps.swift + Features/Door/DFUScreen` | 已覆盖 |
| 命令 23 交换方式 | `App/Services/LockServicePairing.swift` | `Engine/LockServicePairing.swift` | 已覆盖 |
| 命令 24 自动上锁 / 防尾随档 | `App/Services/LockServiceOps.swift` | Engine/LockServiceOps.swift + Features/Door/TailgateScreen（2–6 秒档） | 已覆盖（本次接线） |
| 命令 25 布防（control / start / end） | `App/Core/DefendKit.swift · Services/DefendService.swift` | `Engine/DefendKit.swift · DefendService.swift + Features/Door/DefendScreen` | 已覆盖 |
| 网关 30 / 31 / 32 / 35 / 38 | `App/Services/HardwareService.swift` | `Engine/HardwareService.swift + Features/Door/GatewayScreen` | 已覆盖（32 为云端档案，按原版不发送） |
| 钥匙串 41 / 43 / 44 | `App/Services/HardwareService.swift` | `Engine/HardwareService.swift + Features/Settings/HardwareScreen` | 已覆盖 |
| BLE 扫描 / 连接 / 20B 分片 / 写确认 / 断链自愈 | `App/Services/BLEService.swift · BLEDelegates.swift` | `Engine/BLEService.swift · BLEDelegates.swift` | 已覆盖 |
| 产品型号与能力表（PidMap） | `App/Core/PidMap.swift` | `Engine/PidMap.swift` | 已覆盖 |
| 协议时间基准（本地 2010-01-01） | `App/Core/ZKProtocol.swift` | `Engine/ZKProtocol.swift` | 已覆盖 |
| 时间显示制式（12/24、秒、双行） | `App/Core/TimeFormat.swift` | Engine/TimeFormat.swift + Features/Settings/TimeDisplay.swift + AppearanceScreen（12/24/秒/双行） | 已覆盖（本次接线） |
| 状态 / 日志解析与错误码表 | `App/Core/StatusParser.swift` | `Engine/StatusParser.swift` | 已覆盖 |
| AES / KeyGen / ZOTP 算法 | `App/Core/AESKit.swift · KeyGen.swift · ZOTP.swift` | `Engine/AESKit.swift · KeyGen.swift · ZOTP.swift` | 已覆盖 |
| 密钥材料系统 Keychain 存储 | `App/Core/SecretStore.swift` | `Engine/SecretStore.swift` | 已覆盖 |
| 剪贴板写入即过期 | `App/Core/Clip.swift` | `Engine/Clip.swift` | 已覆盖 |
| 日志帧脱敏（hex 载荷遮蔽） | `App/Core/FrameRedact.swift` | `Engine/FrameRedact.swift` | 已覆盖 |
| 后台任务保护（配网 / DFU） | `App/Core/BackgroundGuard.swift` | `Engine/BackgroundGuard.swift` | 已覆盖 |
| 连接感知：预热 / 重连阶梯 / RSSI 历史 / 蓝牙横幅 | `App/Core/LinkSenseKit.swift · LinkSenseReconnect.swift · LinkSenseViews.swift` | Features/Door/LinkSense.swift（预热 / 重连阶梯 / RSSI 历史 / 信号条）+ DoorScreen 顶部 | 已覆盖（本次接线） |
| BLE 错误码与扫描档位 | `App/Services/BLETypes.swift` | `Engine/BLETypes.swift` | 已覆盖 |

### B. DFU / 固件

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| Nordic DFU 传输（Secure FE59 / Legacy 1530） | `App/Services/DFUKit.swift` | `Engine/DFUKit.swift` | 已覆盖 |
| 固件包解析 / CRC / 尺寸 / 降级闸 | `App/Services/ZipKit.swift` | `Engine/ZipKit.swift` | 已覆盖 |
| 固件升级页（版本对比 / 本地导入 / 进度 / 禁止退出） | `App/UI/DFUView.swift` | `Features/Door/DFUScreen.swift` | 已覆盖（本次补齐） |
| DFU / 指纹期间屏幕常亮 | `App/UI/Mascot.swift（ScreenAwakeWhile）` | `Design/Components/ScreenAwake.swift + DFUScreen / KeyCreate` | 已覆盖（本次补齐） |

### C. 备份导入导出与规范格式

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| 备份包模型 / schema 版本 | `App/Services/BackupKit.swift（BackupBundle）` | `Engine/BackupBundle.swift` | 已覆盖 |
| Canonical 序列化 + FNV1a32 checksum | `App/Services/BackupCanonical.swift` | `Engine/BackupCanonical.swift` | 已覆盖 |
| 加密信封 PBKDF2 / AES-CBC / HMAC-SHA256 | `App/Services/BackupKit.swift（CryptoBox）` | `Engine/BackupKit.swift（CryptoBox）` | 已覆盖 |
| 全量备份采集（锁 / 凭证 / 成员 / 全局） | `App/Services/BackupKit.swift（collectAll）` | `Engine/BackupKit.swift（collectAll）` | 已覆盖 |
| 恢复 / 合并 / schema 升级链 / 回滚点 | `App/Services/BackupStudioKit.swift` | `Engine/BackupStudioKit.swift` | 已覆盖 |
| 备份页生成 / 导入 UI | `App/UI/BackupView.swift` | `Features/Settings/BackupScreen.swift` | 已覆盖（本次接真 CryptoBox + canonical + BackupStudio.restore） |
| 备份工作室（WebDAV / 多份保留 / 换机迁移 / 自检） | `App/Services/BackupStudioKit.swift` | Engine/BackupStudioKit.swift + Features/Settings/BackupStudioScreen（WebDAV / 多份 / 迁移 / 自检） | 已覆盖（本次接线） |
| 备份历史（上次备份 / 新鲜度） | `App/Core/Milestones.swift` | `Engine/Milestones.swift + BackupScreen / SettingsScreen` | 已覆盖 |

### D. 凭证组织与批量

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| 凭证台账 CRUD（密码 / 指纹） | `App/Core/StoreLedger.swift` | `Engine/StoreLedger.swift` | 已覆盖 |
| 密码新增（0A） | `App/UI/PwdStudio.swift · CredentialActions.swift` | `Features/Keys/KeyCreateScreen + AppModel.addPassword` | 已覆盖 |
| 密码改期（0B） | `App/UI/PwdDetailStudio.swift · CredentialCenterView.swift` | `Features/Keys/KeyDetailScreen + AppModel.setPasswordExpiry` | 已覆盖（本次接线） |
| 密码删除 | `App/UI/CredentialActions.swift · PwdDetailStudio.swift` | `Features/Keys/KeyDetailScreen + AppModel.deletePassword` | 已覆盖（本次接线） |
| 清空全部密码（0A delAlias=FFFF） | `App/UI/LockSettingsView.swift（清空密码）` | Engine/LockServiceCredentials.swift + Features/Door/LockSettingsScreen（清空全部密码） | 已覆盖（本次接线） |
| 指纹录入 / 确认（13 / 14） | `App/UI/FpStudio.swift` | `Features/Keys/KeyCreateScreen + AppModel.enrollFingerprint` | 已覆盖（本次接线） |
| 指纹删除（15） | `App/UI/FpDetailStudio.swift` | `Features/Keys/KeyDetailScreen + AppModel.deleteFingerprint` | 已覆盖（本次接线） |
| 临时码（普通 0A 时间窗） | `App/UI/TempCodeStudio.swift` | `Features/Keys/KeyCreateScreen（temp 分支）` | 已覆盖 |
| ZOTP 动态临时密码（本地算法） | `App/UI/CredentialOtp.swift · Core/ZOTP.swift` | Engine/ZOTP.swift + Features/Keys/ZotpScreen + KeyCreateScreen（动态密码入口） | 已覆盖（本次接线） |
| 凭证到期月历 | `App/UI/CredentialCalendarView.swift` | `Features/Keys/KeyCalendarScreen.swift` | 已覆盖 |
| 批量延期 / 批量停用 / 前缀备注 / 移交 | `App/Core/CredentialOrgBatch.swift` | Engine/CredentialOrgBatch.swift + Features/Keys/CredentialStudioScreen（批量动作） | 已覆盖（本次接线） |
| 回收站 / 版本历史 / 星标置顶 | `App/Core/CredentialOrg.swift` | Engine/CredentialOrg.swift + Features/Keys/CredentialStudioStores / CredentialStudioScreen | 已覆盖（本次接线） |
| 到期预警与本地通知排程 | `App/Core/CredentialOrg.swift · CredentialOrgState.swift` | Engine/CredentialOrgState.swift + Features/Keys/CredentialStudioParts（五档预警） | 已覆盖（本次接线） |
| 凭证包导出（CredPackage 加密） | `App/Core/CredentialOrgBatch.swift（exportPackage）` | Engine/CredentialOrgBatch.swift + Features/Keys/CredentialStudioScreen（导出包） | 已覆盖（本次接线） |
| 弱口令 / 重复 / 前缀冲突检测 | `App/Core/CredentialOrg.swift` | Engine/CredentialOrgState.swift + KeyCreateParts / CredentialStudioScreen（检测） | 已覆盖（本次接线） |
| 凭证详情 / 打码 / 分段复制 | `App/UI/PwdDetailStudio.swift · FpDetailStudio.swift` | `Features/Keys/KeyDetailScreen.swift` | 已覆盖 |
| 手机钥匙签发（PIN 分配 + ekey） | `App/Services/MobileKeyService.swift` | `Engine/MobileKeyService.swift + Features/Keys/MobileKeyScreen` | 已覆盖（本次接线） |
| 手机钥匙撤销（cmd08 delPins） | `App/Services/MobileKeyService.swift` | `Engine/MobileKeyService.swift + Features/Keys/MobileKeyScreen` | 已覆盖（本次接线） |
| 安卓配对二维码（mac / pid / ekey） | `App/Core/AndroidPair.swift · UI/ShareToAndroidView.swift` | `Engine/AndroidPair.swift + Features/Keys/ShareToAndroidScreen` | 已覆盖（本次接 AndroidPair.payload） |
| 截图 / 录屏遮罩 | `App/Core/CaptureShield.swift` | `Design/Components/CaptureShield.swift + KeyDetail / ShareToAndroid` | 已覆盖（本次补齐） |
| 凭证工坊入口（StudioHome） | `App/UI/StudioHome.swift` | `Features/Keys/KeysScreen · KeyCreateScreen` | 已覆盖 |
| 凭证搜索 / 筛选 | `App/UI/CredentialsView.swift` | `Features/Keys/KeysScreen（类型分段 + 搜索）` | 已覆盖（简化） |
| 凭证排序 / 置顶 / 分组 | `App/Core/CredentialOrg.swift` | Engine/CredentialOrg.swift + Features/Keys/CredentialStudioScreen（排序 / 星标 / 分组） | 已覆盖（本次接线） |

### E. 成员中心

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| 成员增删改查 | `App/UI/MembersView.swift · MemberWizard.swift` | `Features/Household/HouseholdScreen · MemberCreateScreen` | 已覆盖 |
| 成员 360 详情 | `App/UI/MemberDetail.swift` | `Features/Household/MemberDetailScreen.swift` | 已覆盖 |
| 角色与权限矩阵 | `App/Core/MemberHub.swift（permRows）` | `Engine/MemberHub.swift + Household/HouseholdRoster` | 已覆盖 |
| 成员档案扩展（emoji / 备注 / 分组 / 紧急联系） | `App/Core/MemberHub.swift（MemberExt）` | `Engine/MemberHub.swift + Household/HouseholdRoster` | 已覆盖 |
| 成员归档 / 恢复 | `App/UI/MemberWizard.swift（MemberArchivedView）` | `Features/Household/MemberArchiveScreen.swift` | 已覆盖 |
| 同名成员重复合并 | `App/UI/MemberWizard.swift（MergeMembersView）` | `Engine/MemberMergeKit.swift + Household/MemberMergeSheet` | 已覆盖（本次补齐） |
| 成员移交 / 借用 / 家政窗 | `App/Core/MemberHub.swift` | Engine/MemberHub.swift + Features/Household/MemberOpsScreen · MemberOpsStore | 已覆盖（本次接线） |
| 家庭轮值 / 关怀便签 / 欢迎语 | `App/Core/MemberHub.swift` | Engine/MemberHub.swift + MemberOpsScreen · HouseholdRoster（careText / welcome） | 已覆盖（本次接线） |
| 活跃度 / 最近开门 / 归属推断 | `App/Core/MemberHub.swift · Services/Attribution.swift` | Engine/MemberHub.activityBundle / recentExcerpts + MemberOpsScreen | 已覆盖（本次接线） |
| 访客虚拟分组 | `App/Core/MemberHub.swift（isVisitorRow）` | Engine/MemberHub.isVisitorRow + MemberOpsScreen（访客卡） | 已覆盖（本次接线） |
| 长辈模式 | `App/Core/MemberHub.swift（elderMode）` | Engine/MemberHub.elderMode + MemberOpsScreen + KeysScreen（消费） | 已覆盖（本次接线） |
| 删除成员级联凭证入回收站 | `App/Core/CredentialOrg.swift（cascadeBinMember）` | Engine/CredentialOrg.cascadeBinMember + MemberOpsStore.cascadeDelete（回收站） | 已覆盖（本次接线） |
| 成员中心总览 | `App/UI/MemberCenterView.swift` | `Features/Household/HouseholdScreen.swift` | 已覆盖 |
| 成员上限 / 槽位 | `App/Core/MemberHub.swift` | `Engine/MemberHub.swift + HouseholdRoster` | 已覆盖（上限按本机 15 位口径） |

### F. 记录检索与导出

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| cmd16 日志读取（≤20 页 × 5 条） | `App/Services/LockServiceCredentials.swift + AppModel` | `Engine/LockServiceCredentials.swift + Shell/AppModel.readLogs` | 已覆盖 |
| 记录时间线 / 自然日分组 | `App/UI/RecordsView.swift · RecordsTimeline.swift` | `Features/Records/RecordsScreen.swift · RecordsModels` | 已覆盖 |
| 自然语言 / 加减号检索 | `App/Core/RecordSearch.swift · RecordSearchParse.swift` | Engine/RecordSearch*.swift + Features/Records/RecordsStudioScreen | 已覆盖（本次接线） |
| 筛选：时段 / 成员 / 告警 / 越界 / 失败 | `App/Core/RecordSearch*.swift · UI/RecordsFilters.swift` | Engine/RecordSearch*.swift + Features/Records/RecordsStudioScreen | 已覆盖（本次接线） |
| 记录详情 / 同日上下文 | `App/UI/RecordsTimeline.swift（RecDetailSheet）` | `Features/Records/RecordDetailScreen.swift` | 已覆盖 |
| 备注 / 标旗 / 告警处置 | `App/Core/RecordSearch.swift（RecordOverlay）` | Engine/RecordSearch.RecordOverlay + Features/Records/RecordsModels（持久化） | 已覆盖（本次接线） |
| 告警分级 / 告警中心 | `App/Core/RecordSearch.swift（AlarmMeta）` | `Engine/RecordSearch.swift + Features/Records/RecordsModels` | 已覆盖 |
| 统计与图表（StatsKit） | `App/Core/StatsKit.swift · UI/RecordsView.swift` | Engine/StatsKit.swift + Features/Records/RecordsStudioScreen | 已覆盖（本次接线） |
| CSV 导出 | `App/UI/RecordsView.swift · ExportShares.swift` | `Features/Records/RecordExportScreen.swift（RecordCSV）` | 已覆盖 |
| 成员名册 vCard 3.0 | `App/UI/ExportShares.swift` | `Features/Records/RecordExportScreen.swift（MemberVCard）` | 已覆盖 |
| 单条记录分享卡 PNG | `App/UI/ExportShares.swift（ExportKit.recordCard）` | `Features/Records/RecordExportScreen.swift（ImageRenderer）` | 已覆盖 |
| 每周小结 / 复盘摘要 | `App/Core/RecordSearch.swift（weekSentence）` | `Features/Records/RecordsModels.swift（WeeklyDigest）` | 已覆盖 |
| 原始协议帧 hex 导出 | `App/UI/RecordsRows.swift` | Engine/LockService.recentFrames · FrameRedact + RecordsStudioScreen | 已覆盖（本次接线） |

### G. 审计链 / 里程碑 / 电池养护 / 锁档案

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| 应用锁：本机密码 / 失败冷却 | `App/Core/AppLock.swift · LockGuard.swift` | `Engine/AppLock.swift · LockGuard.swift + LockKeeperApp/LockGateScreen` | 已覆盖（本次接 DB 摘要与真实校验） |
| 胁迫码 / 空壳模式 | `App/Core/AppLock.swift` | Engine/AppLock.swift + AppModel.decoyMode 空壳投影 | 已覆盖（本次接线） |
| Face ID / Touch ID 解锁 | `App/UI/LockScreen.swift` | Engine/AppLock.unlockByBiometric + LockKeeperApp / LockGateScreen 生物识别 | 已覆盖（本次接线） |
| 审计链（HashKit / AuditChain） | `App/Core/AuditChain.swift` | `Engine/AuditChain.swift` | 已覆盖（引擎） |
| 字段 diff / 敏感操作审计 / 脱敏导出 | `App/Core/StoreLedger.swift · AuditChain.swift` | `Engine/StoreLedger.swift · AuditChain.swift` | 已覆盖（引擎） |
| 里程碑：开锁 / 整理 / 备份计数 | `App/Core/Milestones.swift` | `Engine/Milestones.swift + AppModel / About / BackupScreen` | 已覆盖（本次接开锁/备份计数） |
| 电池采样 / 五档 / 低电本地通知 | `App/Core/BatteryCare.swift` | Engine/BatteryCare.swift + Features/Door/BatteryProfileScreen | 已覆盖（本次接线） |
| 电池档案（型号 / 换电日期 / 续航预估） | `App/UI/DeviceInfoView.swift` | Features/Door/BatteryProfileScreen（采样 / 型号 / 换电日期） | 已覆盖（本次接线） |
| 锁档案（昵称 / 符号 / 色标 / 隐藏 / 解锁 PIN） | `App/Core/LockStats.swift · UI/LockProfileView.swift` | Engine/LockStats.swift + Features/Door/LockProfileScreen | 已覆盖（本次接线） |
| 多锁统计 / 分组 / 排序 | `App/Core/LockStats.swift` | Engine/LockStats.usage + Features/Door/LockPortfolioScreen | 已覆盖（本次接线） |
| 诊断日志 / BLE 遥测 / 数据健康 | `App/Core/DiagKit.swift · DiagLogStore.swift` | `Engine/DiagKit.swift · DiagLogStore.swift` | 已覆盖（引擎） |
| 只读试验模式 | `App/Core/TrialGuardKit.swift` | `Engine/TrialGuard.swift + AppModel/SecurityScreen` | 已覆盖（本次补持久化与真实绑定） |

### H. 设置 / 系统集成 / 其他业务

| 功能点 | 原实现 | 新实现 | 结论 |
|---|---|---|---|
| 通知授权 / 点击通知定位凭证 | `App/Core/QuickActions.swift` | `Engine/QuickActions.swift + LockKeeperApp UIApplicationDelegateAdaptor` | 已覆盖（本次注册 delegate） |
| 本地深链 kf://（device / records / credentials / settings） | `App/Core/Route.swift · LockKeeperApp.handleDeepLink` | `Shell/Router.swift + RootView.onOpenURL` | 已覆盖（基础四 host） |
| 快速操作池 / 智能排序 / 再开一次 | `App/Core/QuickPool.swift` | `Engine/QuickPool.swift + DoorScreen / QuickPoolEditSheet` | 已覆盖（本次补齐） |
| 设备首页：开锁盘 / 状态 / 最近记录 | `App/UI/DeviceHomeView.swift` | `Features/Door/DoorScreen.swift` | 已覆盖 |
| 添加设备 / 配网七步链 | `App/UI/AddDeviceView.swift` | `Features/Door/AddLockScreen.swift（LockService.pair 真链路）` | 已覆盖（本次补 cmd12 回声） |
| 设备信息 / 锁状态（容量、Boot/键盘版本、电池档案） | `App/UI/DeviceInfoView.swift` | Features/Door/LockSettingsScreen（容量 / Boot / 键盘 / 电池入口） | 已覆盖（本次接线） |
| 锁设置（防尾随 / 静音 / 清空密码 / 固件） | `App/UI/LockSettingsView.swift` | Features/Door/LockSettingsScreen（锁设置） | 已覆盖（本次接线） |
| 防尾随 / 自动上锁页 | `App/UI/SettingsSubPages.swift（TailgateView）` | Features/Door/TailgateScreen（防尾随页） | 已覆盖（本次接线） |
| 安全模式说明页（A/B 模式） | `App/UI/SettingsSubPages.swift（SafemodeIntroView）` | Features/Door/SafeModeScreen（A/B 说明与切换） | 已覆盖（本次接线） |
| 协议测试页（扫描 + cmd12） | `App/UI/ProtocolTestView.swift` | `Features/Settings/ProtocolTestScreen.swift` | 已覆盖（本次补齐） |
| 备份与恢复页 | `App/UI/BackupView.swift` | `Features/Settings/BackupScreen.swift` | 已覆盖（本次接真引擎） |
| 设置主页 / 分组 | `App/UI/SettingsView.swift · SettingsSections.swift` | `Features/Settings/SettingsScreen.swift` | 已覆盖 |
| 外观 / 主题 / 时间制式 / 快捷格偏好 | `App/AppStateAppearance.swift · UI/SettingsAppearance.swift` | Features/Settings/AppearanceScreen + SettingsModel（全落盘）+ TimeDisplay | 已覆盖（本次接线） |
| 无障碍与操作辅助（AXPrefs / AuthKit） | `App/Core/AccessibilityKit.swift` | Features/Settings/AccessibilityScreen + AXSettings（RootView 生效） | 已覆盖（本次接线） |
| 全局提示条 | `App/Core/ToastCenter.swift` | Features/Settings/ToastCenter.swift + RootView ToastHost | 已覆盖（本次接线） |
| 分享给安卓（二维码） | `App/UI/ShareToAndroidView.swift` | `Features/Keys/ShareToAndroidScreen.swift` | 已覆盖（本次接 AndroidPair） |
| 成员中心 / 我的 | `App/UI/MemberCenterView.swift` | `Features/Household/HouseholdScreen.swift` | 已覆盖 |
| 记录页（时间线 / 筛选 / 导出） | `App/UI/RecordsView.swift` | `Features/Records/RecordsScreen.swift · RecordExportScreen` | 已覆盖 |

## 二、本次补齐的“缺失”项（补后结论已改为已覆盖）

审计过程中先按“原 App 有、ios27 完全没有对应实现”筛出以下业务功能缺口，随后**直接补进 ios27**（最小可用、沿用现有 Engine / 设计令牌 / V7 组件风格）：

| # | 补齐的功能 | 补实现文件 | 说明 |
|---|---|---|---|
| 1 | 固件升级（DFU）页面 | `App/Features/Door/DFUScreen.swift` | 本地固件包导入 → FirmwareKit 校验/降级闸 → cmd22 → DFUSession（Secure/Legacy）→ 进度/状态 → 回读。注册 Dest `.dfu` 与设置入口。 |
| 2 | 协议测试（扫描 + cmd12 回声） | `App/Features/Settings/ProtocolTestScreen.swift` | 复刻原 `ProtocolTestView`：全扫 8 秒、解析 pid/MAC/RSSI/DFU 态，逐台发 cmd12 免令牌回声。注册 Dest `.protocolTest`。 |
| 3 | 同名成员重复合并 | `App/Engine/MemberMergeKit.swift` · `App/Features/Household/MemberMergeSheet.swift` | 复刻原 `MergeMembersView`：同名候选、凭证归属迁移、kf_mclaim_ 认领迁移、删除副档。 |
| 4 | 靠近自动开锁 F0–F6 门控链 | `App/Engine/AutoOpenKit.swift`（扩写） | 原仅 F4 布防互锁；补全开关/档位/挂起/审计/标定/P95/回差/中值滤波/冷却/双确认，并加 `AutoOpenController` 前后台与 RSSI 轮询。 |
| 5 | 快速操作池（10 选 6 / 常用排前 / 再开一次） | `App/Engine/QuickPool.swift` · `App/Features/Door/QuickPoolEditSheet.swift` · `DoorScreen.swift` | 复刻原 `QuickPool`：kf_quick_ids / kf_quick_freq / kf_quick_smart，设备页“快捷操作”卡 + 编辑页。 |
| 6 | 截图 / 录屏遮罩 | `App/Design/Components/CaptureShield.swift` | 复刻原 `CaptureShield`（UIScreen.isCaptured 通知驱动），挂到 KeyDetail 码值卡与 ShareToAndroid 二维码。 |
| 7 | 长任务屏幕常亮 | `App/Design/Components/ScreenAwake.swift` | 复刻原 `ScreenAwakeWhile` / ScreenCare，挂到 DFUScreen 与指纹录入。 |
| 8 | 只读试验模式真值 | `App/Engine/TrialGuard.swift` + `AppModel` / `SettingsParts` | 原 ios27 只有内存 Bool，`LockService.assertReadOnly` 读的 kf_trial_guard 从未被写；现在绑定持久化。 |
| 9 | 通知授权 + 点击通知定位凭证 | `App/LockKeeperApp.swift` | 注册 `QuickActionDelegate`（原 `QuickActions` 一直是死文件），启动申请通知授权、设 UNUserNotificationCenter delegate。 |
| 10 | 深链 kf:// 基础四 host | `App/LockKeeperApp.swift` | device / records / credentials / settings，记录行键与锁 MAC 都在。 |

同时把以下“引擎在、页面未接”的项从占位改为真链路（这些在矩阵中记为**已覆盖**，不再只算降级）：
备份页（CryptoBox + BackupCanonical + BackupStudio.restore）、校时页（cmd03 / cmd0E + 回读）、布防页（cmd25 + DefendService）、网关页（cmd31 / 35 / 38）、钥匙串页（cmd41 / 43 / 44）、手机钥匙签发/撤销（MobileKeyService）、分享给安卓（AndroidPair.payload）、指纹录入/删除（cmd13 / 14 / 15）、密码改期/删除（0B / 0A）、开锁计数与备份历史（Milestones）。

## 三、37 项接线的落点（逐条见上表）

1. **门 / 锁端策略**：`Features/Door/LockSettingsScreen`（cmd19 临时码开关、cmd24 入口、清空全部密码、设备信息与容量族）、`TailgateScreen`（2–6 秒防尾随档）、`SafeModeScreen`（A/B 说明与切换）、`BatteryProfileScreen`（采样 / 五档 / 电池档案）、`LockProfileScreen` / `LockPortfolioScreen`（锁档案与多锁统计）。
2. **连接感知**：`Features/Door/LinkSense.swift` 的 `LinkSenseModel` + `LinkSenseBar`，挂在 DoorScreen 顶部；预热只建立到就绪态，绝不开锁。
3. **凭证**：`CredentialStudioScreen` / `CredentialStudioStores`（批量延期、停用、前缀备注、移交、回收站、版本历史、星标、预警、凭证包、弱口令与重复检测、排序分组）与 `ZotpScreen`（cmd19 + ZOTP 生成）。
4. **记录**：`RecordsStudioScreen`（自然语言检索、时段 / 成员 / 告警 / 失败 / 越界筛选、StatsKit 统计、脱敏原始帧导出）；`RecordsModels.RecordsOverlay` 改为落 Engine 的 `kf_rnote_` / `kf_rflag_` / `kf_rdisp_`。
5. **成员与家庭**：`MemberOpsScreen` / `MemberOpsStore`（移交、借用、家政窗、轮值、关怀便签、欢迎语、活跃度、访客分组、长辈模式、删除成员级联回收站）。
6. **安全 / 外观 / 系统**：`AppLock.unlockByBiometric` 接 LockGate 生物识别；`AppModel.decoyMode` 接空壳数据投影；`AppearanceScreen` / `SettingsModel` 全量落盘 + `TimeDisplay`；`AccessibilityScreen` / `AXSettings`；`ToastCenter` + RootView ToastHost。

## 四、验证

- 静态闸门：`node Gates/allgates.js` → **15 / 15 全绿**（swiftparse / types / swiftcheck / tokens / contrast / glass / motion / a11y / dynamictype / reducedmotion / crosprivate / callsig / lineage / workflow / destmap）。
- 逐文件核对：139 个原 Swift 文件中 53 个纯逻辑 Engine 文件逐字节一致，10 个因去除 SwiftUI / AppState 依赖做了等价拆分；其余 UI 文件按功能点逐项映射到新页面。
- 本次改动只落在 ios27；`ios-app/App` 未改动（原 App 只读）。

## 五、边界（如实声明）

- 本机无 Swift 工具链 / Xcode，不能做真实编译；静态闸门只能保证语法、类型引用与设计约束，不等于云端 xcodebuild 通过。最终编译以 CI 为准。
- 无真锁，所有 BLE / DFU / 网关 / 指纹行为只做了接口与调用链核对，未做真机回执验证。
- 原 37 项“降级”已按用户可见入口的标准接线：入口可点、操作可完成、结果可见；引擎存在但页面无入口的，不冒充已覆盖。
