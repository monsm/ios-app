# DEFERRED — 暂缓项清单

> 记录各功能包中判定为 ⚠（需新本地数据积累 / 系统能力不确定 / 平台限制）而暂缓实现的创意。
> 判定规则见 docs/CONSTRAINTS.md「Triage 判定规则」；❌ 项见 docs/DECISION-NEEDED.md（一律不实现）。

| 编号 | 名称 | 来源包 | ⚠ 原因 | 复活条件 |
|---|---|---|---|---|
| 654 | 去年今日回顾（照片"一年前的今天"）→ 时间线顶部偶发入口"去年今日：N 条开门记录" | 包18 游戏化·情感化·纪念 | 需满一年的本地日志数据积累，当前 kf_logcache_ 上限 300 条/锁且随使用逐步填充，上线首年无数据可回顾 | 当任一锁的本地缓存首次出现"去年今日"的日志（kf_logsync_ 存续满一年）后，在 RecordsView 顶部挂入口即可，统计逻辑可直接复用 Milestones.swift 的按日聚合 |
| 86 | 失败快照（Sentry 事件捕获）→ 每次失败自动记录 RSSI/电量/错误码快照供诊断回看 | 包1 开锁圆盘与手势反馈 | 需新增失败快照数据表（RSSI/电量需在失败瞬间取实时 03 快照，跨服务取数与留存策略未定） | 诊断页新增 kf_fsnap_ 快照表后落地；当前已有 idea 92 的本地失败标记（kf_fevents_，含原因与手机侧时刻）覆盖"回溯失败原因"的主诉求 |
| 246 | 凭证选择胶囊（支付方式选择器）→ 多条可用凭证时圆盘上方胶囊选择本次用哪条发指令 | 包1 开锁圆盘与手势反馈 | 协议 cmd 04 无"指定凭证"参数（ekey 由 pin 自签发），锁端无法按选择定向校验；仅临时码场景可做且依赖 19 开通态 | 若实测确证锁端按 TrackId/凭证区分校验日志，可为临时码场景做本地选码胶囊 |
| 111 | 续航预估（iPad 电池用量页）→ 按历史电量斜率估算"约还能开 N 次门" | 包3 设备档案与多锁总览 | 协议仅实时电量百分比（03#11，无电压无历史），需长期电量采样积累斜率数据；当前只有 kf_snap_ 单点快照 | 待 kf_snap_ 演进为按日多点的电量采样序列（需新增采样调度与留存策略）后，按最小二乘斜率估算即可，Hero 卡电量字段挂"约还能开 N 次" |
| 254 | 广播自动识别（关于本机自动识别）→ 从广播数据自动回填型号与固件版本，命名步只需输入昵称 | 包3 设备档案与多锁总览 | 广播可解析 pid（型号可回填），但固件版本需连接后读 03#31——广播数据不含固件；且添加时锁处于重置态、固件读取必须先完成配网 | 若实测广播厂商段存在固件偏移位（对齐固件更新表）则命名步回填；现状已在命名步回填型号（pid），添加完成页引导首连验证时顺带读取 03 刷新快照固件 |

| 45 | 电量趋势 sparkline（Robinhood）→ Hero 卡电量字段下挂近 30 天电量走势迷你折线 | 包4 电量·维护·固件关怀 | 协议仅实时电量百分比（03#11，无电压无历史），需每日多次采样积累；**采样埋点已落**（kf_batt_ 表，读 03 即追加、90 天截断，LockService.getStatus 埋点），但上线初期采样点稀疏，画曲线只会是孤立散点 | **采样已埋，展示待数据**：本轮 ⚠ 跳过 sparkline 展示层，各展示位保留"曲线待数据"诚实占位；数据源统一走 BatteryCare.displayPct（采样最新值 vs 快照取新）。复活条件：任一锁 kf_batt_ 采样点 ≥14 且跨度 ≥7 天后，在 DeviceInfoView 电池档案节 / 总览电量条带挂 sparkline（复用 SwiftUI Path 画折线，数据源 BatteryCare.samples） |
| 115 | 自耗电透视（系统电池用量页）→ 诊断页显示本 App 近 24 小时 BLE 活跃时长用于自查功耗 | 包4 电量·维护·固件关怀 | 系统不提供按 App 的 BLE 功耗/活跃时长 API，iOS 无法自测；降级案"本地自测统计"也需新增 BLE 会话计时埋点并跨会话留存，价值不成比例 | 若后续引入 BLE 会话时长埋点（connect→disconnect 累计），诊断页加一行"近 24h 蓝牙活跃 N 分钟"即可 |
| 144 | 批量排队升级（iOS 多设备更新队列）→ 设备管理勾选多把同型号锁排队逐把升级 | 包4 电量·维护·固件关怀 | DFU 本身无断点续传（DECISION 141），批量队列 = N 倍的中断重传状态机 + 每把锁需人到场靠近的现场编排，且触发前提是多把同型号锁同批待升级的低频场景；单锁升级全流程（137-148）已覆盖固件关怀主诉求 | FirmwareView 增加队列模式（勾选同 pid 待升级锁 → 逐把跑 DFURunner.runUpgrade，每把独立记录 kf_dfu_hist）即可复活 |

## 包4 收敛舍弃（ROADMAP 包4「舍弃」备案，非 ⚠，无复活预期）

> 按 ROADMAP 包4「舍弃（5）」执行：46/117/1029/1032/1040 不实现。五种电量估算互相重复，且协议只有电量百分比（无电压、无历史），保留 111（包3）+45 两项已覆盖价值。

| 编号 | 名称 | 舍弃理由 |
|---|---|---|
| 46 | 电池健康估算 | 与 117/1029/1032/1040 同为"从百分比序列反推健康度"的估算族，协议无电压/循环次数，全部依赖同一种稀疏采样 |
| 117 | 电压走势线 | 协议无电压字段（CAPABILITY §2），❌ 122 已定不虚构毫伏 |
| 1029 | 换电池倒推表 | 按日均耗电倒推剩余天数 — 斜率估算族，与 45 采样共用数据但结论不可靠（电量%非线性） |
| 1032 | 续航斜率 | "约还能用 5 周"一句话 — 同 1029，斜率在电量平台期无意义 |
| 1040 | 掉电观察行 | 单日掉电 >20% 需当日多次快照，采样成本与误报率不成比例 |

## 手势变体收敛（ROADMAP 包1「舍弃」备案，非 ⚠，无复活预期）

> 与主案「按住确认 (1)」语义冲突或依赖不存在/不确证的系统能力，按 ROADMAP 包1 收敛为双主交互（按住确认 + 上滑触发，配起手围栏 61 与误触围栏 62）。

| 编号 | 名称 | 舍弃理由 |
|---|---|---|
| 52 | 旋钮充能 | 与按住确认语义重复且训练成本高；旋转一圈的时长显著拉长 10 秒开锁动线 |
| 53 | 双击直开 | 跳过确认直接发指令，与"按住确认"防误触主案语义冲突 |
| 54 | 摇一摇唤出 | 与 372 摇一摇遁走（包7）手势打架 |
| 55 | 轻点背面 | 依赖系统"轻点背面"绑定能力，App 无法保证入口存在 |
| 57 | 方位手势 | 依赖不存在的上锁/门铃命令（CAPABILITY §5），仅查看日志方向成立，价值不成比例 |
| 58 | 三连点防误开 | 与按住确认语义冲突，且比按住更难被老人/儿童理解 |
| 77 | 灵动岛播报 | 与包17 的 939 重复，归并到包17 落地 |

统计：⚠ 8 项（包1 三项 + 包3 两项 + 包4 三项：45 采样已埋待展示 / 115 / 144）；手势收敛舍弃 7 项另有 ROADMAP 包1「舍弃」清单背书，包3 舍弃 3 项、包4 舍弃 5 项另有各自 ROADMAP「舍弃」清单背书。

## 包3 收敛舍弃（ROADMAP 包3「舍弃」备案，非 ⚠，无复活预期）

> 按 ROADMAP 包3「舍弃（3）」执行：252/777/920 不实现。

| 编号 | 名称 | 舍弃理由 |
|---|---|---|
| 252 | 按键配对确认 | 换钥 05 执行即擦旧钥、按键激活配对态的语义未确证，风险大；现有"重置态+确认弹窗"已防误配 |
| 777 | 错峰使用雷达 | 与包10 的 602 作息雷达重复，避免同一份日志做两套相近可视化 |
| 920 | 安装位置字段 | 与 774 场所副标题同字段重复，收敛为 LockMeta.place 单字段（锁档案/名片/添加命名步共用） |

## 包6 收敛备案（ROADMAP 包6「⚠(2)」+ 推断项备案，展示层已简化落地，未全量实现）

> 按 ROADMAP 包6「⚠」备案：365 / 487-488 / 529 三项做"简化版 + 明确标注推断口径"落地，
> 未做全量；复活条件见各行。数据层新增表 kf_chist_ / kf_cbin_ / kf_cqueue_ / kf_cstar_ /
> kf_calert_ / kf_clists_ / kf_cseq_ / kf_ccred_quota / kf_cbin_reclaim_days / kf_calias_display
> / kf_csearch_hist / kf_ccred_prefs / kf_ccred_sort（App/Core/CredentialOrg.swift），
> 不进备份包 schema（492 版本历史分区勾选留包8 导出向导）。

| 编号 | 简化口径 | 复活条件 |
|---|---|---|
| 365 | 下发状态步条做"本地容错态"：kf_cqueue_ 队列 + 待下发/已下发/锁端确认(rc@#03) 三步步条，重试走既有 0A/0B/15 命令；失败态可重试，无后台补发 | 锁端确认已有（rc@#03 成功即已下发）；若要"后台自动补发"需 BGTask 调度评估后再做 |
| 487/488 | 版本历史新表 kf_chist_ 已落：保存自动快照（改值/改期/备注/归属/新增/删除前）、491 配额滚动淘汰、495 星标豁免、496 恢复即新版本、489 逐字段 diff 着色；488 自动还原点仅"批量统一延期"自动打点（auto 置顶 2 席），备份还原/锁重连前打点留包8 接线 | 包8 恢复向导落地后在 restoreAll 前调 CredentialOrg.snapshot(auto:) 打全量自动还原点 |
| 529 | 组尾统计"近 30 天使用约 Y 次"按台账推断：临时密码按时间窗命中 type2/4 开门日志计数；长期密码仅在锁内唯一且有归属时计，UI 强制带"约"字 | 锁端提供逐次凭证使用计数（当前无，CAPABILITY §3 日志无身份字段）后改为真值 |

## 包6 收敛舍弃（ROADMAP 包6「舍弃」备案，非 ⚠，无复活预期）

| 编号 | 舍弃理由 |
|---|---|
| 176 | 与 487 版本历史同一机制，已并入 kf_chist_ 快照 |
| 915 | 与 526 置顶星标重复 |
| 923 | 与 497-506 整套回收站重复 |


## 包7 暂缓/降级备案

> 包7（安全·隐私·审计）落地于 App/UI/SecurityCenterView.swift + App/Core/AuditChain.swift。⚠ 降级与接线下列备案。

| 编号 | 名称 | 状态 | 原因 / 接线点 |
|---|---|---|---|
| 378 | 截图加扰水印 | ⚠ 降级为页面常驻水印层 | 系统不可拦截截图（iOS 无 API），实现为 SecurityWatermark 常驻对角重复层（App 名+日期），kf_swmark_on 可关；导出水印 239 并入本层 |
| 374 | 录屏遮罩 | 暂缓 | UIScreen.isCaptured 轮询可用但录屏场景低频，且占位文案需在凭证详情页落地；待包8 备份/凭证接线时并入 |
| 372 | 摇一摇遁走 | 暂缓 | UIAccessibility.shakeNotification 可用但手势与既有快捷键包（54 已舍）冲突面待实测；落点为记录/凭证 Tab 全局手势，待接线 |
| 370 | 贴近复蔽 | 暂缓 | 距离传感器无 App 级 API（仅通话场景系统占用），无法本地实现 |
| 296 | 安全模式 | 降级为手动应急位 | 系统级异常钩子不存在；kf_sdest_safemode 开关已就位，启动路径接线由包11 诊断包落地 |
| 161 | 应用锁秒进 | 配置键已就位 | 验证成功后直达上次 Tab 的落点需改 LockKeeperApp（AppLockView 成功分支），接线点已注释于 SecurityCenterView 会话区 |
| 391 | 胁迫码打标 | 会话打标键已就位 | AppLockView 识别胁迫码入口（对比 kf_sduress_code）需改 LockKeeperApp，本包提供 kf_sduress_at 打标时刻与审计橙边 |

## 包7 收敛舍弃（ROADMAP 包7「舍弃（8）」备案，非 ⚠，无复活预期）

| 编号 | 舍弃理由 |
|---|---|
| 38 | 与 369 遮蔽样式自选重复（默认打码并入 369） |
| 204 | 与 393 锁定时机四档重复 |
| 233 | 与 371 切后台即糊重复 |
| 235/236 | 面容降级与 877 重复 / 访客模式与 377 重复 |
| 238/239 | 剪贴板自清与 405 重复 / 导出水印并入 378 水印层 |
| 384 | 三档计数过滤与 153 日志分级过滤重复 |

## 包12 暂缓/降级备案

> 包12（导出·打印·分享）落地于 App/UI/ExportCenter.swift（ExportKit/ExportCenterView/QLPreviewView），
> 入口挂 RecordsView 右上菜单「导出与分享」。新增 Info 键仅 UTExportedTypeDeclarations（708/709 卡片 UTType），
> 打印/QuickLook 无额外权限。SHA256 校验行复用 CryptoKit（包7 HashKit 同款口径，722）。

| 编号 | 名称 | 状态 | 原因 / 接线点 |
|---|---|---|---|
| 703 | 邮件附件模板 | ⚠ 降级为本地 .eml 文本 | 系统邮件账户(MailCompose)依赖设备已配置的发件账户，无法本地保证；降级为生成完整 MIME .eml（主题预填 + CSV base64 附件 + SHA256），ExportKit.emailTemplate 落地，用户手动粘贴进系统邮件发送。"离开本机"口径与 718 一致 |
| 710 | 报告校验二维码 | 暂缓 | 需 App 内扫码路由 + 二维码生成库；722 的 SHA256 校验行已随文件尾/报告尾页输出，接收方文本核对即可覆盖"完整性"主诉求。复活条件：引入 QR 生成（如 CoreImage CIQRCodeGenerator）+ 新增「校验」路由页后，把 722 的摘要画成码即可 |
| 711 | 拖放导出 | 暂缓 | iPad 拖出会话需 .dropDestination/.onDrag + 分屏目标 App 联调；685 PDF 报告已可经 ShareLink 分享到备忘录/其他 App，"拖出片段"为交互增强非主诉求。复活条件：主战场景确为 iPad 分屏时补 dropDestination |
| 713 | 固定导出目录书签 | 暂缓 | 安全作用域书签 (NSFileCoordinator) 需"存到文件"目录选定的持久授权，首启无目录可选；现有 writeLocal 落 Caches/exports + ShareLink 系统"存储到…"已覆盖。复活条件：备份向导(包8)接入 UIDocumentPicker 保存目录后，把导出默认目录挂同一书签 |

统计：本包 ⚠4 项 = 703 降级已落 + 710/711/713 暂缓（710 已有 722 文本校验兜底）；舍弃 203 不做。


## 包8 暂缓/降级备案

> 包8（备份·恢复·换机迁移）落地于 App/UI/BackupStudio.swift + App/Services/BackupStudioKit.swift，
> 入口：设置-备份与恢复 内「备份工作室」行 (BackupView studioSection)。
> 数据层新增键：kf_bk_cadence / kf_bk_keep / kf_bk_month_day / kf_bk_otp / kf_bk_bgtask /
> kf_webdav_root / kf_mig_session / kf_mig_lockact_<mac> / kf_mig_checks / kf_mig_retire /
> kf_bk_rollback / kf_bk_dbhash / kf_bk_selfwarn / kf_bk_events / kf_bk_last_import。
> 纪律：备份文件只去用户自配 WebDAV (Basic Auth 运行时输入), 口令不出本机内存;
> CryptoBox 加密语义不动, 仅外围策略/ UI。新增 Info 键: BGTaskSchedulerPermittedIdentifiers
> (428 BGTask) + NSCameraUsageDescription (411 相机扫码)。

| 编号 | 名称 | 状态 | 原因 / 接线点 |
|---|---|---|---|
| 428 | 充电自动备份 | ⚠ BGTask 注册 + 文案降级 | BGTaskScheduler 可用但执行时机由系统择机调度, 不承诺"接电即备"。已做: kf_bk_bgtask 开关 → BackupStudio.registerChargeBackup (com.kf.chargebackup BGAppRefreshTask, 命中即打本机回滚快照), 备份页文案"由系统择机执行" (chargeBackupNote); Info.plist 已加 BGTaskSchedulerPermittedIdentifiers。复活条件: 实测系统择机频率稳定且用户接受"不接电即备"语义后, 再接锁端 03 快照 |
统计: 本包 ⚠1 项 (428) 备案如上; 舍弃 194-196/199/201 不做 (ROADMAP 包8「舍弃（5）」备案)。


## 包13 暂缓/降级备案

> 包13（成员·家庭协作）落地于 App/Core/MemberHub.swift + App/UI/MemberCenterView.swift，
> 入口：设置-成员管理 右上「成员中心」(MembersView toolbar) + 设置-家人与钥匙 新增行。
> 数据层新增键：kf_member_ext（角色/emoji/备注/常用锁/紧急联系/分组/归档/代管/紧急管理员/关怀语/欢迎语/便签）、
> kf_mtransfer（467 待确认移交）、kf_mborrow_<mac>（472 借用）、kf_house_win_<mac>（483 家政窗）、
> kf_duty_week（481 轮值）、kf_mclaim_<mac>（791 认领覆盖层，绝不改锁端数据）、
> kf_privacy_until（794 隐私浏览 10 分钟限时）、kf_elder_mode（479/486 长辈模式）。
> 纪律：「访客」虚拟分组（793）只在本地展示层与过滤逻辑，不写锁端凭证表；
> 活跃度/摘录一律台账推断（Attribution 可证明链），UI 强制带「约」。

| 编号 | 名称 | 状态 | 原因 / 接线点 |
|---|---|---|---|
| 262/459/466 | 活跃度与最近开门摘录 | ⚠ 降级台账推断 | 锁端日志无身份字段（CAPABILITY §3），靠 Attribution 可证明归属（临时码窗口/唯一凭证）积累；统计与摘录全带「约」，久未用行置灰判据 = 30 天无可证明归属（MemberHub.activity.stale） |
| 483 | 家政周期预设 | ⚠ 降级整段起止窗 | 协议无循环时段（工作日 8:00-18:00 每日循环需锁端支持），降级为一整段 from/to 窗：HouseCleaningPresetView 只本地登记 kf_house_win_ + 入台账临时码，UI 明示「无循环」 |
| 484 | 访客欢迎语 | ⚠ 归属靠时间推断 | 临时码首用回执归属只能按时间窗推断（R1 唯一命中才算），展示语带「约」；欢迎语文本存 kf_member_ext.welcome，归属未证明时不外显 |
| 653 | 生日组头标签 | 已接线 RecordsView | 组头按组日 MM-dd 命中 kf_member_bday → 「今天是 X 的生日」标签（RecordsView.daySection）；数据与提前一天通知复用 1017 既有 Milestones.memberBirthdays / CareReminders，未重做 |
| 797 | 陪同进入疑似标注 | 暂缓（跳过） | 启发式（同临时码短窗内多成员记录）误报率高：短窗阈值无历史数据可回归验证，误标会向家人谎报「有人跟着进家门」。复活条件：用 799 周小结积累 4 周以上真实台账后，离线回放校验假阳性率 <10% 再接展示层 |

统计：⚠ 6 项中 459 并入 262/466 口径、483/484/653/797 备案如上；舍弃 200（并入 458）/623（并入 259）不实现。

## 包15 暂缓/降级备案

> 包15（无障碍与操作辅助）落地于 App/Core/AccessibilityKit.swift + App/UI/AccessibilityView.swift
> (设置-辅助功能入口: SettingsView a11ySection)，全 App 关键视图补 accessibility/keyboardShortcut 修饰器，
> 系统旗标降级集中在 AXFlags/AXPrefs 读点 (增强对比映射 862 经 DS.Palette.hairlineStrong/textSubStrong)。

| 编号 | 名称 | 状态 | 原因 / 接线点 |
|---|---|---|---|
| 869 | 眼动停留兼容 | ⚠ 降级为自定滑杆 | iOS 无公开 API 读取系统"停留时长/眼动停留"设置；kf_ax_dwell 滑杆 (0.5–4s, 默认 2s) 作为 868 扫描组聚焦停留基准与 851 练习场演示参数，落地 AccessibilityView 运动区 |
| 875 | 按住时长跟随 | ⚠ 降级为自定滑杆 | 系统"按住持续时间"无读取 API；kf_ax_hold 滑杆 (0.4–1.6s, 默认 0.9s 与包1 对齐) 由 AXPrefs.holdDuration 供 UnlockDial.beginHold 消费，设置-辅助可滑调 |
| 877 | 验证降级大键 | ⚠ 设备生物识别门控 | 仅当 LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics) 可用时出现 (AuthKit.biometricAvailable)；AppLock 连败 3 次后大字 Face ID/Touch ID 替代键，无生物硬件设备显示不可用文案 |
| 163 | 横屏重排 | 降级为说明文案 | TARGETED_DEVICE_FAMILY=1 仅竖屏，系统不出现横屏，不做横屏布局；"横屏锁定"说明挂 设置-辅助 视觉区 |
| 228/848/867 | 色觉冗余/成败提示音/降低透明度映射 | 舍弃 | 按 ROADMAP 包15「舍弃（3）」：228 并入 878 形状冗余三态；848 并入 76 声效开关 (不另加失败音)；867 与 226 重复 |

## 包17 系统集成 · 降级/暂缓备案
| 编号 | 名称 | 处理 | 复活条件 |
|---|---|---|---|
| 4/943/942 | 锁屏·主屏哑 Widget / 时刻建议 | 不建 Widget target (免费账号无 App Groups, 只能做哑按钮, 暂不值得为此每周多签一个 target) | 用户付费 (App Groups) 或接受纯哑 Widget 再开 |
| 937/938/944 | 控制中心深链控件 | 同上, 随 Widget target 一并暂缓; ❌ 状态色点本就不做 | 同上 |
| 939/941 | 灵动岛 / 临时码实况 | 不做 LiveActivity target (侧载 ActivityKit 需实测, 控制规模) | 真机实测 ActivityKit 侧载可行再开 |
| 957-963 | NFC 标签中心/写卡 | IntegrationCenterView 已做登记页+能力探测文案; CoreNFC 写卡未实现 (免费账号 capability 不确定) | 真机探测 capability 通过后实现写卡 |
| 965-974 | Apple Watch 伴侣 | 不建 watchOS target (共享每周重签负担); 路线图页已写 | 用户愿意承担 Watch 侧载维护 |
| 49 | 自动化模板库 | 舍弃 (与 295/948 重复) | — |

## 包2 连接感知与离线同步 · 暂缓/降级备案

> 包2（连接感知与离线同步）落地于 App/Core/LinkSenseKit.swift（连接管理包装层 LinkSense：
> 预握手 95/93/96/134、回连节律 126、假死巡检 275/131、失败三分类 536、补发回执 535）+
> DeviceHomeView（63/64/67/68/98/125/130 UI 区）+ RootView（135 scenePhase 刷新 / 136 跨页细条 /
> 162 握手可离开 / 69 蓝牙直通条）+ LockOverviewView（71 信号预览）+ SettingsView LinkPrefsView
> （70/97/100）+ CredentialsView/CredQueueView（510/533/538）。
> 数据层新增键：kf_link_auto_<mac>（100 单锁关自动预握手）、kf_rssi_fence（93 信号围栏, 默认 -70）、
> kf_linkrssi_<mac>（71 最近扫描 RSSI）。96 铁律：预握手/回连只到就绪态, 绝不自动开锁;
> 自动补发只针对既有 kf_cqueue_ 队列（534 降级口径：有待下发才触发, 前台检测, 不做后台扫描）。

| 编号 | 名称 | 状态 | 原因 / 接线点 |
|---|---|---|---|
| 94 | NFC 门贴碰一碰 | 暂缓 | NFC 写卡/标签动作需 CoreNFC capability 实测（免费账号不确定），与包17 的 957-963 同源；App 内不做 NFC 门贴引导，待 capability 通过随包17 一并落 |
| 70 | 连接成功率 | 降级为"积累中"占位 | 需 ≥10 次握手样本（BleTelemetry.recordAttempt 已随包2 各路径埋点），冷启动显示"积累中 (N/10)"；满 10 次后出百分比（LinkSense.successRateText） |
| 124 | 占用类错误细分 | 标注"协议未确证"保守文案 | GATT/协议层占用 rc 未确证，一律走 LinkSense.occupationHint 保守句（"可能正被另一台手机使用, 稍候再试"），不虚构错误码语义；协议确证后替换 |
| 534 | 就近提示 | 降级为前台检测 | 后台 BLE 扫描受系统限制不做；改为"前台 + 有待下发队列 + 回连成功"即自动补发（LinkSense.autoReconnectTick / onPreconnectDone） |
| 539 | 高成功率时段 | 占位 | 需下发成败按小时段的历史（现 kf_conn_attempts 只到分钟级时间戳），LinkSense.bestHourHint 占位文案；满 7 天数据后可聚合 |
| 540 | RSSI 锁卡角标 | 舍弃 | 与 63（Hero 卡）/71（总览信号卡）重复，ROADMAP 包2「舍弃（1）」备案 |

统计：本包 ⚠5 项备案如上；94 并入包17 能力探测；540 舍弃不做。

## 包5 凭证工坊 · 8 ⚠ 降级/占位备案

> 包5 落地于 App/UI/CredentialStudio.swift（StudioHome 扇出 177 / PwdStudio 515 分步 / TempCodeStudio 325 五场景 /
> FpStudio 41 沉浸录入 / OtpStudio 343 独立口令组）+ CredentialsView（CredStudioEntryView 入口、密码/指纹详情 sheet、
> 322 缺失提醒行、324 冗余横条）+ CredentialOrg 包5 辅助段（重复/前缀/老旧/diff/重叠/双签/命名建议/TOTP/静态码/草稿）。
> 数据层新键：kf_cotp_t_<mac>（独立 TOTP）、kf_cotp_s_<mac>（静态备份码）、kf_cestudy_earlyexp_<mac>_<alias>（331 提前失效）、
> kf_cdraft_<mac>（518 草稿）— 全部向后兼容。舍弃 302/318/321 不实现（ROADMAP 包5「舍弃」备案）。
> 新 Info.plist 键 NSCameraUsageDescription（522 相机取号, project.yml info.properties）。

| 编号 | 名称 | 状态 | 降级口径 |
|---|---|---|---|
| 311 | 同码引用卡 | 占位"约" | 日志无 alias 字段, 按时间窗推断开窗次数（CredentialOrg.openCountInWindow, type2/4）, 无数据不编造 |
| 316 | 指纹档案统计 | 占位"约" | 日志无指纹身份字段, 用 type3 整锁 30 天计数（fpUseCount30d）替代逐指纹, 标"日志无指纹身份字段, 整锁推断" |
| 320 | 误识档案 | 占位"约" | type13 语义待实测, 只展示本地指纹告警日志计数（fpAlarmLogCount）, 标"语义待实测" |
| 326/335 | 计次退役/用量刻度 | 降级本地计次 | 锁端无计次字段, 详情页用量刻度用 type4 本地计数, 标"锁端无计次, 约"; 退役组未做 |
| 332 | 原码续期 | 降级"约" | 过期码锁端留存未确证, 本地沿用原值改期 7 天走既有 0A 原位改写, 失败入 kf_cqueue_; 文案标"锁端留存未确证, 约" |
| 333 | 首用回执 | 降级"约" | 无 alias 字段, 完成页用 firstUse（时间窗内最早开门日志）推断, 未命中显示"等待首次使用" |
| 337 | 秒刻度细条 | 仅独立 TOTP 秒级 | 锁端 ZOTP 为 30 分钟时窗, WindowBar 用于锁端时只按 1800s 显示"约"; 秒级细条 + 末 5 秒转橙轻震仅独立口令组 |
| 331 | 提前失效滑杆 | 本地意图 | 滑杆只写 kf_cestudy_earlyexp_, 不改协议; 到点由详情页/列表提示停用（不自动下发） |

统计：本包 ⚠8 项全部按上表降级/占位（"约"级或本地计次）; 舍弃 302/318/321 另有 ROADMAP 包5「舍弃（3）」备案。

## 靠近自动开锁 (AUTOOPEN-PLAN) 暂缓/保守备案

> 落地于 App/Core/AutoOpen.swift + LinkSenseKit (RSSI 喂入) + RootView (F0/F1 scenePhase) +
> SettingsView (设置-靠近自动开锁 Section, 含标定页 AutoCalView) + DiagnosticsView (上次拒开原因行)。
> 数据层新增键: kf_autoopen / kf_autoopen_face / kf_autoopen_audit_<mac> (尾段 500, 永不记密钥明文) /
> kf_autoopen_suspend_until_<mac> (rc=26 防拆 24h 挂起) / kf_autocal_<mac> (F3 RSSI P95 标定)。

| 编号 | 名称 | 状态 | 原因 / 接线点 |
|---|---|---|---|
| AUTOOPEN-7 | Siri/Widget 入口 | 暂缓 (方案 §6 第 7 项) | §3.5 定位"只做带到就绪态"——免费账号无 App Groups (Widget target 需每周重签, 见包17 4/943 同源), Intent 10s 窗口 vs BLE 3-5s+命令 2-3s 不承诺"远程开门"; 全门绿判定 AutoOpenGate.rejectReason 可被 Intent 复用, 接线点 AutoOpenController.attempt |
| AUTOOPEN-G3 | ekey 滚动 (times 语义) | 保守不自动重签 | G3 times 字段语义未确证 (可能非剩余次数), 前置真机矩阵 (times=0/1/8 × 连开/断电/锁侧重置) 未跑; 实验通过前 rc=5 仅提示"请联系主人换钥" (AutoOpenController.dispatch case 5), 不自动重签 |
