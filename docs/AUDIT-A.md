# AUDIT-A — 创意 51–150 对抗式代码审计（段 51–150）

> 方法: 以 ROADMAP-DRAFT 包1/2/3/4/11「收录/舍弃/⚠」+ FEATURE-TRIAGE Part1 + DECISION-NEEDED + DEFERRED 为基准, 逐编号在 App/ 内 grep 实现证据 (创意号写在代码注释里), 三态判定: DONE(有实现且接线) / PART(未接线或有备案降级) / MISS(无代码无备案)。
> 审计日 2026-10-07。只信代码, 不信文档声称。本段属包1 (51-92) / 包2 (93-136) / 包3 (137-148 多锁) / 包4 (113-148 电量DFU) / 包11 (149-150 体检)。
> 纪律: 未触碰 AUDIT-B/C/D 已修的 git 工作区改动 (git status 中 15 个 M 文件保持原样)。

## 一、统计（段 51–150, 共 100 编号）

| 分类 | 数量 | 说明 |
|---|---|---|
| DONE | 73 | 有实现且接线 (含 P0-1 修复后 F6 门合规) |
| ⚠DONE (备案降级) | 7 | 70/86/94/111/115/124/144 按 DEFERRED 备案占位/保守口径 |
| PART | 6 | 未接线: 59/66/97/103/109/123 (无 DEFERRED 备案, 实为漏做或半做) |
| MISS | 3 | 无代码无备案 = 漏项: 104/107/108 |
| 舍弃 | 11 | 包1 52-55/57-58/77 (7) + 包4 117 + ❌119/122 + 141 (DECISION 替代=整包重传, 138/139/142 已落) |

合计: 73 + 7 + 6 + 3 + 11 = 100 ✓

**MISS 3 项**: 104 房间分组 / 107 多选批处理 / 108 手动隐藏锁 —— 均为包3「设备管理列表」组织类, 无 DEFERRED/ROADMAP 舍弃备案 (漏项, 非有意不做)。
**PART 6 项**: 59 (手势演练层未做)/ 66 (呼吸光晕有, 但 RSSI 驱动速率未接, 无备案)/ 97 (偏好记忆 UI 承诺"扫描强度"档位实未做)/ 103 (默认锁 271 位已占, 拖动排序交互未做)/ 109 (删除冷静期: 有后果预告, 缺输入锁名确认与 N/M 级联数)/ 123 (扫描强度三档未做, 97 同源)。

## 二、P0 已修清单（当场修复, 闸门已绿）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| P0-1 | App/Core/AutoOpen.swift makeContext (~L405) | 安全级 fail-closed 违规: F6 锁态门原写 `lockReady: !(snap?.rc == 25 \|\| snap?.rc == 26)` — 无 03 快照时 `snap?.rc == nil`, `!(nil)` = true → 快照缺失/从未读状态时 F6 误判绿, 七门链条在"锁态未知"场景整体放行, 违背 AUTOOPEN-PLAN §3.1"执行全 AND · 未知不放行"红线 (且 StatusSnapshotData.rc 默认 0, 新建快照结构即视为"rc 成功") | 改为 `snap != nil && snap?.rc != 25 && snap?.rc != 26` — 快照不存在 = F6 拒开 (.f6busy), 注释标注 AUDIT-A P0-1。修后无快照场景 rejectReason 返回 .f6busy 并审计落盘。swiftcheck/contrast/golden 三闸全绿 |

对抗复核（未改, 结论附后）:
- **RSSI 回差**: `rssiSample` 负值语义实为正确 (arm=-42 强于 disarm=-30, 越接近 0 越强; 武装需 `>=-42`, 保持需 `>-30`), 与 AUTOOPENTests:142-153 全边界一致 — 仅 AutoOpen.swift 内注释与 AutoCalView footer 文案方向写反 (P2-1)。
- **UnlockDial 手势围栏**: 61 insideFence (r=0.39·直径≈六成面积) 起手判定、62 armed 4s 超时复位、51 上滑阈值 -56/确认 -30、56 撤销轻点 (isBusy 分支 intercept 在 244/250 之前, 0.8s 窗口从 dispatchAt 起算) — 逻辑闭环未见反判。
- **BatteryCare 低电分级**: 滞回 0/1/2 三级 (≤20 武装 1, ≤10 武装 2, >30 复位) 单调不重复轰炸; 113 五档 tier 边界 0..10/11..35/36..60/61..80/81..100 无重叠漏档。
- **AutoOpen 跨午夜布防**: `defendActive` start>end 跨午夜、start==end fail-closed 不判布防 — 与注释一致。
- **F5 冷却**: 成功后 60s + `lastDispatch==0` 首开放行 — 无跨午夜问题 (epoch 时间戳)。

## 三、P1 清单（只列不修）

| 编号 | 问题 |
|---|---|
| AUTOOPEN-F1 | 严格档弹窗在途位恒 false: `makeContext` 传 `facePendingPrompt: false`, 但 `onForeground` 在严格档已 `face.promptFace()` — "从未刷脸+弹窗在途放行"路径 (AutoOpenKit.faceFresh 严格档分支) 永远走不到, 严格档实际退化为"60s 窗口内刷过"。需 Controller 跟踪 prompt 在途 + FaceService 结果回调注入 |
| 62 | 误触围栏 `armed` @State 随 View 消失丢失: DeviceHomeView 切走再回, 已解锁的围栏态重置, 用户需重拖一次 (4s 窗口本意内, 但 267 换锁二次确认与 112 向导同屏场景下体验断裂); 建议 armed 升 DB 键 + 时间戳 |
| 51 | 上滑阈值硬编码 -56/-30 不进 DS 令牌 (与 249 圆盘三档解耦: 200pt 档时 -56pt 仅占 28%, 160pt 档占 35%, 各档手感不一致, 建议随 dial 比例化) |
| 83 | `failStreak` 只在 runUnlock 失败路径 +1, 成功清零 (L422) — 87 排查清单"连续 3 次"口径含跨日累计, 未设 24h 过期, 重启不清零 (failStreak 在 AppState 内存, 重启即清, 与 87 文案"连续"口径略宽) |
| 109 | 删除冷静期缺输入锁名确认与 "N 条记录 / M 条凭证" 级联预告 (MISS 边界, 见上; 建议并入 104/107/108 一并补包3 列表组织) |
| 127 | ~~静默排查模式未暂停 135 回前台刷新 (refreshStatusQuietly 不经 DiagFlags), "干净复现"口径不完全~~ **第九十一批已修**：`AppState.refreshStatusQuietly` 加了 `manual` 参数，自动路径 (切锁 / 开锁后的复位定时器 / 进页 `.task`) 受 silent 管，用户主动的下拉、刷新按钮与 cmd20 回读传 `manual: true` 照常。原行里"暂停看门狗"那半已随零调用死码一起删除 (§101) |

## 四、P2 清单

| 位置 | 问题 |
|---|---|
| AutoOpen.swift rssiSample/ArmCalView | 注释方向写反: "RSSI 比解除线弱才解除" 与 "0.5×=-30" 实际为"比解除线强才保持"; 代码与测试均正确, 纯注释误导 (已列入对抗复核, 建议随下轮文档清理改) |
| DeviceHomeView L533 | 120 低电视觉降级 `.brightness(tier.severe ? -0.06 : 0)` 负亮度值在浅色模式下视觉近无, 深色才有效; 建议改 opacity 语义 |
| LinkPill tint | 已连接用 `Color(hex: 0xBBF7D0)` 白胶囊内绿字, 对比度经 contrast.js 111 断言通过, 但 0xBBF7D0 vs 白底 胶囊 background 组合在浅主题 hero 卡退化时为绿字绿底, 实测可读; 建议随主题化令牌收编 |
| UnlockDial swipeReady | `@State private var swipeReady` 声明在 L464 (拖选手势之后), 位置混乱但无功能影响 |

## 五、逐编号明细（段 51–150）

| 编号 | 名称 | 判定 | 证据 (文件:行) |
|---|---|---|---|
| 51 | 上滑开锁 | DONE | UnlockDial:440 上滑触发 / :410 手势层 |
| 52 | 旋钮充能 | 舍弃 | DEFERRED 包1 收敛 (与按住确认冲突) |
| 53 | 双击直开 | 舍弃 | DEFERRED 包1 收敛 |
| 54 | 摇一摇唤出 | 舍弃 | DEFERRED 包1 收敛 (与 372 打架) |
| 55 | 轻点背面 | 舍弃 | DEFERRED 包1 收敛 (系统能力) |
| 56 | 二次点按撤销 | DONE | LockKeeperApp:169 0.8s 撤销窗 / UnlockDial:409 |
| 57 | 方位手势 | 舍弃 | DEFERRED 包1 收敛 (上锁/门铃无命令) |
| 58 | 三连点防误开 | 舍弃 | DEFERRED 包1 收敛 |
| 59 | 手势演练层 | PART | 包14 收录; Onboarding 无圆盘跟滑演练, 832 一次性手势提示亦未做 |
| 60 | 单手下沉 | DONE | DesignSystem:243 / AccessibilityKit:197 AXPrefs.onehand |
| 61 | 起手围栏 | DONE | UnlockDial:131 insideFence 0.39·直径 |
| 62 | 误触围栏 | DONE | UnlockDial:118 armed / LockKeeperApp:339 kf_fence |
| 63 | RSSI 信号格 | DONE | LinkSenseKit:544 RSSIBars / DeviceHomeView:398 |
| 64 | 三态语义色 | DONE | LinkSenseKit:535 LinkPill 灰/白/绿 |
| 65 | 雷达波纹 | DONE | UnlockDial:8 UnlockPulseRing 握手扩散环 (ready 即停, 由 isBusy 门控) |
| 66 | 渐近呼吸 | PART | UnlockDial:202 呼吸光晕有, RSSI 驱动呼吸速率未接, 无 DEFERRED 备案 |
| 67 | 握手耗时标签 | DONE | LinkSenseKit:32/590 ConnectMsBadge 超 2s 标黄 |
| 68 | 拟人状态文案 | DONE | LinkSenseKit:570 三态文案 |
| 69 | 蓝牙直通条 | DONE | LockKeeperApp:531 / LinkSenseKit:698 |
| 70 | 连接成功率 | ⚠DONE | LinkSenseKit:356 successRateText 10 样本前"积累中" (DEFERRED 备案) |
| 71 | 列表信号预览 | DONE | LockOverviewView:219 / LinkSenseKit:390 |
| 72 | 断连原因行 | DONE | DiagnosticsView:50 BleTelemetry 流水 |
| 73 | 成功涟漪 | DONE | UnlockDial:224 shock 冲击波扩散 |
| 74 | 抖动报错 | DONE | UnlockDial:398 抖动 + 下方原因 |
| 75 | 待机流光 | DONE | UnlockDial:220 UnlockShimmer 仅 ready+idle |
| 76 | 成功提示音 | DONE | LockKeeperApp:428/429 kf_unlock_sound 默认震动 |
| 77 | 灵动岛播报 | 舍弃 | DEFERRED 包1 收敛 (归并包17 939) |
| 78 | 卡片翻面 | DONE | DeviceHomeView:325/539 |
| 79 | 心跳触感 | DONE | UnlockDial:360 |
| 80 | 三段进度细条 | DONE | UnlockDial:98/313 PhaseBar |
| 81 | 全屏专注开锁 | DONE | DeviceHomeView:89/421 入口收敛为按钮 (下拉与滚动冲突, 注释备案) |
| 82 | 对勾弹出 | DONE | DeviceHomeView:539 翻面背面 82 对勾 |
| 83 | 再试一次 | DONE | LockKeeperApp:268 前两次静默重试转手动 |
| 84 | 错误码翻译 | DONE | StatusParser:167 rcFriendly |
| 85 | 退避节奏文案 | DONE | LockKeeperApp:65-68 第 N 次·等 X 秒 |
| 86 | 失败快照 | ⚠DONE | DEFERRED 备案 (92 本地失败标记覆盖主诉求) |
| 87 | 排查清单 | DONE | DeviceHomeView:21/87 三勾 (蓝牙/走近/查电) |
| 88 | 临时码备援 | DONE | DeviceHomeView:753 |
| 89 | 超时变色 | DONE | UnlockDial:105/318 橙 + 取消 |
| 90 | 失败态符号 | DONE | UnlockDial:101/160 failStreak≥2 搜索符号循环 |
| 91 | 回连静默点 | DONE | DeviceHomeView:20/91/412 |
| 92 | 失败入时间线 | DONE | RecordSearch:30/64 kf_fevents_ 灰图标行 |
| 93 | 信号围栏预握手 | DONE | LinkSenseKit:70-100 kf_rssi_fence -70 |
| 94 | NFC 门贴 | ⚠DONE | DEFERRED 备案 (并入包17 957-963 能力探测) |
| 95 | 进页预热 | DONE | DeviceHomeView:138 / LinkSenseKit:457 |
| 96 | 只预热不执行 | DONE | LinkSenseKit:26/73/148 铁律注释三处 |
| 97 | 连接偏好记忆 | PART | LinkSenseKit:487 UI 承诺"扫描强度"档位未实现, 实为 95/100 开关复用 |
| 98 | 冷热连接标识 | DONE | LinkSenseKit:37/548 预热/即连 |
| 99 | 近场轻提醒 | DONE | LinkSenseKit:104 RSSI≥-55 toast (274 免扰静默) |
| 100 | 手动连接模式 | DONE | LinkSenseKit:72 kf_link_auto_ 关=手动 |
| 101 | 横滑换锁 | DONE | DeviceHomeView:222 pagedLocks 横滑 |
| 102 | 锁名胶囊 | DONE | DeviceHomeView:193/219 capsuleMenu |
| 103 | 拖动排序 | PART | LockStats:50 默认锁位 271/103 占位, 拖动交互未做 |
| 104 | 房间分组 | MISS | 无代码无备案 (LockArchive 无 group 字段) |
| 105 | 符号与色标 | DONE | LockStats:12-13/54 / Sheets:1030 LockProfileView |
| 106 | 昵称加备注 | DONE | LockStats:11 / Sheets:1083 |
| 107 | 多选批处理 | MISS | 无代码无备案 (设备管理无编辑模式) |
| 108 | 手动隐藏锁 | MISS | 无代码无备案 (沉睡 292 是自动判定, 非手动隐藏) |
| 109 | 删除冷静期 | PART | SettingsView:275 confirmDestructive 有后果预告, 缺输入锁名 + N/M 级联数 |
| 110 | 锁信息名片 | DONE | Sheets:779 DeviceInfoView |
| 111 | 续航预估 | ⚠DONE | DEFERRED 备案 (需长期电量采样, 45 采样已埋, 展示层未做) |
| 112 | 换机验证向导 | DONE | DeviceHomeView:848 kf_migrate_pending 逐锁验证 |
| 113 | 五档电量图标 | DONE | BatteryCare:55-72 tier 五档 |
| 114 | 低电置顶 | DONE | DeviceHomeView:176/204 橙描边 |
| 115 | 自耗电透视 | ⚠DONE | DEFERRED 备案 (系统不供 BLE 功耗, 降级本地自测未做) |
| 116 | 换电池引导 | DONE | CareViews:372 分步图文 + 1033 向导同页 |
| 117 | 电压走势线 | 舍弃 | 包4 收敛 (斜率估算族) |
| 118 | 换电复位 | DONE | BatteryCare:152 基线采样 + 1014 事件 |
| 119 | 充电状态显示 | ❌ | DECISION-NEEDED 替代"跳过" (协议无字段, 不做=合规) |
| 120 | 低电视觉降级 | DONE | DeviceHomeView:533/1174 触感分级 |
| 121 | 低温季提示 | DONE | BatteryCare:88 11-3 月本地规则 |
| 122 | 原始电压值 | ❌ | DECISION-NEEDED 替代"电量原值" (113 tier 已含档位说明, 不标毫伏) |
| 123 | 扫描强度三档 | PART | 包11 收录; LinkPrefsView 无省电/均衡/极速档位 (97 同源漏项) |
| 124 | 被占用提示 | ⚠DONE | LinkSenseKit:350 保守文案 (协议未确证, DEFERRED 备案) |
| 125 | 最后已知状态 | DONE | Store:395 statusTime 灰角标 |
| 126 | 回连节律点阵 | DONE | LinkSenseKit:199/603 5/15/30/60/90 梯度 |
| 127 | 静默排查模式 | DONE | LinkSenseKit 6 处消费点 (:75/:122/:150/:237/:309/:417) + 第九十一批补上的 `AppState.refreshStatusQuietly(manual:)` 一道；行号按 2026-10-10 现场数过。原行写的 `DiagKit:306` 是旧行号，且"暂停看门狗"那一支是零调用死码 (已删, 见 AUDIT-CODE §101) |
| 128 | 环境拥挤度 | DONE | LinkSenseKit:424 kf_link_env 三档结论 |
| 129 | 极限距离提示 | DONE | LinkSenseKit:438 weakSignalHint < -75 |
| 130 | 唤醒失败细分 | DONE | LinkSenseKit:326 三类归因 + 124 保守 |
| 131 | 会话重协商 | DONE | LinkSenseKit:280 275 假死巡检 久无会话重握手 |
| 132 | 回连短文案 | DONE | LinkSenseKit:253 toast "回到锁身边" |
| 133 | 蓝牙堆栈急救 | DONE | DiagnosticsView:62 分步指引 |
| 134 | 冷启动先扫描 | DONE | LockKeeperApp:587 / LinkSenseKit:401 |
| 135 | 回前台即刷新 | DONE | LockKeeperApp:589 scenePhase |
| 136 | 跨页状态细条 | DONE | LockKeeperApp:505/625 2pt 语义细线 |
| 137 | 升级前体检单 | DONE | Sheets:1225 battOk/bleSvc/双勾 checklist |
| 138 | 三段进度条 | DONE | Sheets:1672 准备/传输/校验 |
| 139 | 剩余时间估算 | DONE | Sheets:1698 EMA 速率 |
| 140 | 禁退保护 | DONE | Sheets:1275/1284 二次确认 + 禁下滑 |
| 141 | 断点续传 | 舍弃 | DECISION 替代"整包重传" (DFU 无断点定义; 138/139/142 压低重传成本已落) |
| 142 | 失败安抚页 | DONE | Sheets:1586 "锁未损坏" 双出口 |
| 143 | 版本并排对比 | DONE | Sheets:1243/1319 推荐/可选标签 |
| 144 | 批量排队升级 | ⚠DONE | DEFERRED 备案 (单锁 137-148 覆盖主诉求, 队列模式未做) |
| 145 | 本地固件导入 | DONE | BatteryCare:48/226 清单 + Sheets:1378 |
| 146 | 升级提醒 | DONE | BatteryCare:261/332 下次打开 App 提醒 |
| 147 | 升级历史列表 | DONE | BatteryCare:57/226 / Sheets:1550 |
| 148 | 完成自动校验 | DONE | Sheets:1533/1713 读回版本比对 |
| 149 | 一键体检 | DONE | DiagKit:539 8 项总分 |
| 150 | 分项报告 | DONE | DiagKit:560 分项 + DiagnosticsView |

## 六、统计复核（段 51–150, 100 编号）

| 分类 | 数量 | 编号 |
|---|---|---|
| DONE | 73 | 51/56/60-65/67-69/71-76/78-85/87-93/95/96/98-103 中 DONE 项… (逐见上表明细行, 全段 100 行均判定) |
| ⚠DONE (备案) | 7 | 70/86/94/111/115/124/144 |
| PART | 6 | 59/66/97/103/109/123 |
| MISS | 3 | 104/107/108 |
| 舍弃/❌ | 11 | 52/53/54/55/57/58/77 (包1收敛7) + 117 (包4估算族) + 119/122 (❌, 不做=合规) + 141 (DECISION 替代) |

合计: 73 + 7 + 6 + 3 + 11 = 100 ✓

## 七、闸门

- `node tools/swiftcheck.js` → 60 文件括号平衡 ✓
- `node tools/contrast.js` → 111 断言 0 不达标 ✓
- `node tools/golden.js` → 金标向量重生成 OK (与本次 F6 修复无交集)

P0 修复 1 处 (AutoOpen F6 fail-closed), 未触碰 AUDIT-B/C/D 已修的 15 个 M 文件。

## 八、逐编号明细（段 151–250）

| 编号 | 创意名 | 状态 | 证据 |
|---|---|---|---|
| （明细追加中, 每 25 编号一批） | | | |

## 九、统计（段 151–250, 共 100 编号）

| 分类 | 数量 | 编号 |
|---|---|---|
| （待明细完成后填写） | | |

## 十、本段 P0/P1/P2

- （待 P0 对抗扫描 CareViews/DiagKit/AccessibilityKit/Milestones 后填写）
| 151 | 权限自查 | PART | DiagKit:562 checkBLE(蓝牙权限项) 仅文本指引; 无未授权项深链跳转 UI |
| 152 | 存储构成条 | PART | DiagKit:389 composition() 三段已实现但 UI 未接(全库无调用); 舍弃备案 759 同此 |
| 153 | 日志分级过滤 | PART | DiagKit:123/156 台账含 level 三档+LockService:38 写入, 但日志页无按档分段过滤 UI(384 并入亦未做) |
| 154 | 关键词高亮 | PART | DiagKit:167/188 entities(in:) 实体识别在, 日志页无命中行高亮+计数展示 |
| 155 | 导出脱敏 | 舍弃 | ROADMAP 包11 舍弃(与 382 重复); 382 已落 AuditChain:152 脱敏导出+ExportCenter redact |
| 156 | 操作序列记录 | ⚠DONE | DiagKit:36/42 本会话采集开关+record 接线(LinkSenseKit 预握手/补发/冷启动), 跨会话降级 DEFERRED 备案 |
| 157 | 诊断包分享 | MISS | 无 zip 打包近7天日志+设备清单+体检结果的分享面板代码 (grep "诊断包/zip" 无) |
| 158 | 体检存档对比 | ⚠DONE | DiagKit:549-559 存档30条+历史"积累中"占位, DEFERRED 口径降级 |
| 159 | 错误码对照表 | PART | StatusParser:142 rcMsg 词表+rcFriendly 在, 但日志错误码可点跳转的对照表页无 UI |
| 160 | 单项复测 | PART | DiagKit:545 runItem 引擎在, UI 无"重测"按钮接线(全库 DiagHealth 无 UI 调用) |
| 161 | 应用锁秒进 | PART | DEFERRED:90 备案"配置键已就位", 接线点注释于 SecurityCenterView:203, AppLock 成功分支未改 |
| 162 | 握手可离开 | DONE | LockKeeperApp:506 注释+Tab 切换不取消 LinkSense 回连循环 |
| 163 | 横屏重排 | ⚠DONE | DEFERRED:169 降级说明文案: AccessibilityView:85/86 "横屏(163) 本项目锁定竖屏" |
| 164 | 键盘快捷键 | DONE | LockKeeperApp:504 Cmd 1-4 切 Tab+Cmd/R/N/F/Esc; AccessibilityView:188 说明行 |
| 165 | 手表伴侣 | MISS | DEFERRED:179 不建 watchOS target(重签负担), AppIntents:241 仅"路线图"展示, 无实现 |
| 166 | Siri 口令 | DONE | AppIntents.swift:30 UnlockIntent+参数名口语化 :176 |
| 167 | 读屏转子 | DONE | UnlockDial:120/274 VO 转子 状态/电量/连接 三维度切换 |
| 168 | 状态变化播报 | MISS | 无连接态变化即时朗读(announce 仅失败播报 852/转子 :282), 168 无代码无备案 |
| 169 | 快捷格自定义 | 舍弃 | ROADMAP 包3 舍弃(与 905 重复+无上锁/门铃命令) |
| 170 | 最近开门深链 | MISS | 收录(包9)但无"点最近开门行跳记录 Tab 高亮条目"代码, 无备案 |
| 171 | OTP 剩余秒数 | DONE | CredentialStudio:232 WindowBar(337 同族, 锁端分钟级/独立秒级+末5s转橙) |
| 172 | 大字临时码 | DONE | CredentialStudio:274 大字口述卡(可拍照/剪贴) |
| 173 | 密码生成器 | DONE | CredentialStudio:26 本地 CSPRNG 生成器:427/724 |
| 174 | 指纹命名联想 | DONE | CredentialOrg:899 命名建议轮播+CredentialStudio:2028 |
| 175 | 指纹利用率 | 舍弃 | DECISION 替代: 只统计 type3 总量 CredentialOrg:868 fpUseCount30d(不归属具体指纹), 不虚构协议 |
| 176 | 密码历史版本 | 舍弃 | ROADMAP 包6 舍弃(并入 487 版本历史); DEFERRED:74 备案, 487 kf_chist_ 快照已落 |
| 177 | 扇出新增 | DONE | CredentialStudio:403 四入口扇出 + CredentialsView:811 入口行 |
| 178 | 批量临时码 | DONE | CredentialStudio:1114 batchCount 批量临时码(走既有 0A 逐条, 不新增协议 :4) |
| 179 | 备注占位 | DONE | CredentialStudio:834 备注占位规范 + 130 五场景预设套占位 |
| 180 | 失效归档区 | DONE | CredentialsView:1056/775 已过期三态分组头(528)+360/180/364 过期即归档 |
| 181 | OTP 备份开关 | DONE | BackupStudioKit:217 默认排除, 显式勾选才追加 OTP 密钥段 |
| 182 | 凭证拖动排序 | DONE | CredentialsView:734/1172 kf_cseq_ 手动序优先+类型分组(182/352 长按菜单记序) |
| 183 | 成员色点 | DONE | RecordsView:992/1154 成员档案色 6pt 圆点(可证明归属才显) |
| 184 | 开门方式图标 | DONE | RecordsView:51/990/1135 fp/pwd/temp/key 行尾符号 |
| 185 | 左滑快捷操作 | MISS | 时间线行无左滑备注/标旗(swipeActions 仅凭证 :1016 与感谢清单 :1868), 无备案 |
| 186 | 记录备注 | DONE | 第四十四批落: RecordSearch.swift RecordOverlay (本机覆盖层 kf_rnote_<mac>, 键 = mac#idxRaw, 上限 60 字) + 详情卡编辑 RecordsTimeline.swift noteSection + 行下灰字 RecordsView.swift (186) ‖ 597 行级备注与 186 同一实现, 不再另建一份 ‖ 随删设备按族清 (Store.swift 族表) |
| 187 | 月份滚轮 | MISS | 时间线为天分组纵滚, 无月份快速跳滚轮 UI, 无备案 |
| 188 | 手动标旗 | DONE | 第四十四批落: RecordOverlay.toggleFlag/isFlagged (kf_rflag_<mac>) + 时间线行左侧 flag.fill 常显 (形状+颜色双通道, 不只靠颜色) + 详情卡开关 ‖ 关闭详情卡用 alarmTick 重算 (沿用 735 刷新机制) |
| 189 | 导出 CSV | 舍弃 | ROADMAP 包9 舍弃(并入 683 CSV 标准导出, 683 已落 ExportCenter:324) |
| 190 | 第一扇门纪念 | DONE | RecordsView:720 firstDayFooter 最早记录结语行 |
| 191 | 按锁切换 | MISS | 记录页仅"当前锁/全部锁" scope(561/770), 无左上新增锁下拉切换器, 无备案 |
| 192 | 过滤会话保留 | MISS | 过滤为 @State 临时态, 无 kf_ 会话保留键, 无备案 |
| 193 | 备份体积预估 | DONE | BackupStudioKit:584 预计体积+上次对比(193 近30天备份次数) |
| 194 | 自动命名 | 舍弃 | ROADMAP 包8 舍弃(与 409 重复); 409 自描述文件名已落 BackupStudioKit:30 |
| 195 | 恢复预演 | 舍弃 | ROADMAP 包8 舍弃(与 417 重复); 417 恢复预演已落 :419 |
| 196 | 校验和展示 | 舍弃 | ROADMAP 包8 舍弃(与 434 重复); 434 哈希短码 SHA256 前8位已落 :494 |
| 197 | WebDAV 连通测试 | DONE | BackupStudioKit:668 PROPFIND 回显服务器时间 |
| 198 | 备份节奏三档 | DONE | BackupStudioKit:41 手动/日/周三档+本地通知提醒 |
| 199 | 多份快照保留 | 舍弃 | ROADMAP 包8 舍弃(与 430 滚动保留重复); 430 已落 :742 |
| 200 | 角色标签说明 | 舍弃 | ROADMAP 包13 舍弃(与 458 角色三档重复); 458 已落 MemberHub:10/73 |
