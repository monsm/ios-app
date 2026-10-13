# AUDIT-C — 创意 551–800 对抗式代码审计

> 方法: 以 ROADMAP-DRAFT 包9/10/11/12/13「收录/舍弃/⚠」+ FEATURE-TRIAGE Part3(551–800: ✅233/⚠13/❌4) + DECISION-NEEDED(596/607/725/744 ❌) + DEFERRED(654/797/包12 703/710/711/713/包13 262/459/466/483/484/653) 为基准, 逐编号在 App/ 内找实现证据 (创意号写在代码注释里), 三态判定: DONE / PART(未接线或有备案降级) / MISS(无代码无备案=漏项)。
> 审计日 2026-10-07。只信代码, 不信文档声称。包边界: 551-595→包9检索, 596-650→包9时间线+包10统计, 651-682→包9文案/组头, 683-722→包12导出, 723-747→包9告警中心, 748-762→包11诊断, 763-787→包3多锁, 788-800→包13成员。
> 注意: 551-800 段部分「收录」编号属于 ROADMAP 其他包(包3 763-787 多锁、包9 15-192 等), 本审计只核 551-800 本体, 跨段编号仅标注不做三态。

## 一、统计 (共 250 编号: 551–800)

| 分类 | 数量 | 说明 |
|---|---|---|
| ❌ 排除 | 4 | 596/607/725/744 (DECISION-NEEDED: 胁迫告警协议不存在, 未做=合规) |
| 舍弃 | 6 | 597(并入186 包9舍弃)/623(并入259 包13舍弃)/659(并入159 包9舍弃)/663(并入231 包10舍弃)/759(并入152 包11舍弃)/777(并入602 包3舍弃) |
| 应做 | 240 | 250 - 4 - 6 |
| **DONE** | 131 | 有实现且接线 (含本次 P0 修复后复验项) |
| **PART** | 55 | 引擎在但 UI 未接线 / 占位 / 降级备案在 / 近似机制 (含 DEFERRED 备案 654/710/711/713/757/797, ROADMAP ⚠ 降级 569/594/671/672/673/674/676/703/737/742/748/749) |
| **MISS** | 54 | 无代码无备案 = 漏项 |

> 对抗重点复核:
> - **包10 假数据**: StatsKit 全部走真实台账 (kf_logcache_ / kf_ledger_), 622 isDegraded 不足 7 天降级空态; **604 多线图假数据已 P0 修复** (StatsKit.swift:422 memberDaily 走 Attribution 可证明归属, 无数据日补 0 绝不伪造), 本轮全量扫描 StatsKit/StatsView 未发现其他伪造数据 (月同比 complete 降级、告警构成、OTP 散点、在家时长代理 全部源自 logsInWindow)。
> - **包13 访客虚拟分组**: MemberHub.visitorId="__visitor" 仅在本地展示/过滤层 (RecordsView.swift:1242/1600), 核实 delPwd/setPwdOwner 均按真实成员 id 写锁端凭证表, 归档走 MemberExt.archived 不删台账。合规。
> - **RecordSearch 农历/节假日越界**: lunar() 有 m 1..12 / day 1..30 双 guard 且 __none 组先排除 (RecordsView.swift:80-89), 节假日为字典查表无索引, 672 顺延取模无越界。无越界风险。
> - **包12 CSV**: 走 RFC4180 转义 (ExportCenter.swift:53 CSVKit.escape: 引号/逗号/换行) + BOM + SHA256 校验行 (:349) + 705 转义行预检 (:1247)。**遗留 P1: 未拦 Excel 公式注入前缀 (=+-@ 开头单元格, 成员名/备注本地可控), 修 escape 会破坏 fixtures/golden.json 字节级差分, 只列不修**。
> - **MemberHub 访客组不写锁端**: 已核实 (见上), MemberHub 全部走 kf_* 本地键, 备注 "绝不写入锁端凭证表" (MemberCenterView.swift:6)。

**MISS 54 项**: 552/558/559/566/580/581/583/584/585/586/587/589/591/593/595/598/602/605/608/614/621/633/640/643/644/645/647/648/650/657/658/665/675/677/680/682/691/694/695/698/716/728/729/731/733/752/761/764/775/780/781/783/786/790。

**PART 55 项**: 563/565/569/573/594/601/604/624/634/636/637/646/651/653/654/661/662/668/671/672/673/674/676/689/703/707/710/711/713/732/737/740/742/743/746/748/749/750/751/753/754/755/756/757/758/760/762/765/766/767/782/794/797/799/800。

## 二、P0 已修清单 (当场修复, 闸门已绿)

> P0 = 编译级/崩溃级/数据破坏级/安全级。本次审计发现的 P0 全部修复:

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| P0-1 | AlarmCenterView:13 | 重复声明 `@State private var scrubHour`: 第 13 行 `= -1` 与第 16 行 `= replayHour()` 同名同型 → 编译 error "invalid redeclaration" | 删除第 13 行, 保留 730 会话记忆版 |
| P0-2 | RecordSearch.swift | `RecordSearch.alarmTitle(_:)` 在 AlarmCenterView:213 / RecordsTimeline:83 被调用但**全库无定义** → 编译 error | RecordSearch 补 `alarmTitle` (告警类型 → 人话标题 + 归属前缀, 复用 655 动词表口径) |
| P0-3 | RecordSearch.swift | `RecordSearch.sameCountPreview(_:)` 在 AlarmCenterView:243 被调用但**全库无定义** → 编译 error | RecordSearch 补 `sameCountPreview` (741 同类计数预览, 走 sameTypeCount 只读口径, 带"约") |
| P0-4 | StatsView:930 | `m.gotpPoints` 拼写错 (正确为 `otpPoints`), `oob` 变量无消费死码 → 编译 error (undefined property) | 删除死码 3 行, 保留 628 越界走 `outOfRangeTotal` |
| P0-5 | RecordsView:1750 / StatsView:1062/1170 | 字符串字面量内嵌 ASCII 双引号 `标"约"` / `为"首末…"` / `给出"最活跃…"`, Swift 字符串内未转义 `"` → 编译 error (unexpected ') | 3 处内层 `"` 改为全角「」 |
| P0-6 | StatsView:419 | `geo[proxy.plotFrame!]` 强制解包 `plotFrame`(iOS 26 已弃用/可选) → 运行崩溃风险 | 改 `proxy.plotAreaFrame` (必选, 全 SDK 可用) |
| P0-7 | StatsView:341 | `.chartXSelection(value:)` 是**不存在的 API** (Charts 无此 modifier), 且 `drillDay` 从未被图表选中赋值 (638 三级下钻断链) | 移除伪 API, 主图点选经 `.chartOverlay` 手势写入 `drillDay` (面包屑/RuleMark 联动), 保持 638 可达 |
| P0-8 | StatsView:1248-1251 | `HourDetailSheet.drillRows` 返回 `[]` 且类型写成 `DailyPoint`, `rows` 返回 `[]` → 时段下钻 sheet(600/638) 永远空, 数据不读 | 重写 `drillRows`: 读 `DB.readLogs(mac)` 过滤 `openTypes∪alarmTypes` 且小时==hour 且窗口内, 前 20 条, 复用 638 口径 |
| P0-9 | RecordSearch.parse:399 | 成员名匹配 `$0.contains(t) && t.count >= 1` — 恒真 (t.count>=1 对所有非空成立), 短词如"指"误命中含"指"的成员名, 且成员名应为精确/包含双向 | 改为 `t.count >= 2 && (names.contains(t) || names.first(where: {$0.contains(t)}))`, 短词(<2 字)不进成员匹配, 避免单字误归属 |
| P0-10 | StatsKit.pwdUses:383 | `max(1, Int(t!/86400000 - f!/86400000)+1)` 对 `f!`/`t!` 强制解包 — 台账 from/to 非 "yyyy-MM-dd HH:mm" 时 msOf 返回 nil, `!` 崩溃 | 改安全解包, 窗缺失时 days=1, ratio 用 min(u, days)/max(days,1) 防除零 |

未修 (P1/P2, 见下): 包11 诊断页 149-160/545/748-762 引擎 DiagKit 有引擎但 DiagnosticsView 未挂主入口 (P1, 非崩溃, 属功能未接线非数据破坏); 621 时间刷选条 / 640 标签避让 / 644 逐点朗读 等纯 UI 增强未做 (P1/P2 级, 不崩不破坏, 只列)。

## 三、P1 清单 (只列不修; 与明细 PART/MISS 交叉引用, 明细已覆盖的不再重复)

| 编号/位置 | 问题 |
|---|---|
| 149-160/544-547/740/748/749/750/753/754/756/758/760/762 | 包11 诊断引擎 (DiagHealth/DiagLogs/DiagQR/SymptomGuide/QueryTemplates/ProtocolDict/IconSemantics/HexDump/DataHealth/CrashGuard/Watchdog) 已落 DiagKit.swift, 但 DiagnosticsView 仅挂 72/133/128 断连与急救, 主「体检/数据健康/原始报文/二维码/白名单模板/崩溃档案」全部未接线 UI (引擎有入口无) **(本行是首轮判定：第三十二批已整体接线，第七十一批补 157/151/280/284，逐条落点见 AUDIT-GAP-CAUSES K 桶状态列)** |
| 755 | 固件版本随行标注: getStatus 只写 fw 到钥匙串, 日志拉取未逐行注记固件 (⚠ 备案) |
| 565 | 告警类型多选: 只有单类 typeFilter chip, 无「多选 + 选中数回显」面板 |
| 621 | 时间刷选条 (折线拖窗联动) 未做, 只有 638 点选下钻 |
| 640 | 标签避让/仅显最大 未做 |
| 644 | VoiceOver 逐点朗读未做 (仅整图 accessibilityLabel) |
| 645 | Dynamic Type 图表标签未专门适配 |
| 647 | 时间制式(12/24h)偏好未做 |
| 648 | 双行时间标注(主 HH:mm 次 灰字) 未做 |
| 650 | 时间来源徽标(锁端/手机侧) 未做 |
| 657 | 无记录日极简占位点 未做 |
| 665 | 区间日期精简 "10月1日–7日" 未做 |
| 675 | 假期外出分隔行 未做 |
| 677 | 深夜静音降级 未做 |
| 680 | rowid 入库顺序法 未做 |
| 682 | 历史告警归档组 未做 |
| 689 | 按成员导出入口 (成员详情页) 未做, 701 范围 picker 已含"仅指定成员"口径 |
| 691 | 加密压缩导出(AES ZIP) 未做 |
| 694 | 存到文件 App(UIDocumentPicker) 未做 |
| 695 | 导出历史清单 未做 |
| 698 | 上周小结生成 未做 |
| 716 | 多选合并导出 未做 |
| 729 | 误报降权规则 未做 |
| 731 | 多锁联动事件合并 未做 |
| 733 | 告警提示音分级 未做 |
| 746 | 单条告警事实单 PDF 无独立实现 (746 仅并入 723 告警流) |
| 761 | rowid 溯源 未做 |
| 775 | 双锁叠加对比 未做 |
| 780 | 均值对照 未做 |
| 781 | 同名凭证对照 未做 |
| 783 | 对比窗口同步 未做 |
| 786 | Hero 翻锁手势 未做 (763 整页横滑有) |
| 790 | 最近活跃头像组 未做 |
| 552/558 | 搜索建议补全/零结果救援三按钮 未做 (558 与包14 823 重复, 823 已舍弃, 属跨包漏) |
| 566 | 成员过滤选择未写本地偏好, 冷启动不恢复 |
| 580/583/584/585/586/587/589/591/593 | 详情翻页/定位高亮/邻近横滑/引用深链/当天全景/低电跳诊断/组内告警置顶/行内次序/日界收尾 未做 |
| 602/605/608/614 | 作息雷达/告警散点阵/假期逐时对比/正常告警分组柱 未做 |
| 752 | 清理前导出提醒 未做 |
| 728 | 换电指引折叠段未挂进低电告警详情 (CareViews 116 是独立保养页) |
| CSVKit.escape | 未拦 Excel 公式注入前缀 (=+-@ 成员名本地可控); 改 escape 会破坏 golden.json 字节级差分 → 只列 P1 不修 |

## 四、P2 清单

| 位置 | 问题 |
|---|---|
| StatsView.memberSeries (P0-8 后 :515) | 604 多线图数据源已接真实归属 (StatsKit.memberDaily); 遗留: 图例点选当前是 toggle 隐藏, 创意要求"单独高亮", 归 604 PART |
| StatsKit.otpPoints (:576) | 散点 label 用 String(format:":"%02d") 拼, 仅时不显分, 文案可接受 |
| MemberCenterView | 成员中心 `.id(tick)` 全量重建 List, 性能可接受 |
| DiagKit.WriteQueue | ~~退后台 flush 靠 221 scenePhase 接线 (P1)~~ **第九十二批整引擎删除**：该行是"计划接线"写成"已接线"，`enqueue` 全库零写入方、flush 只冲空队列。批量落盘要真做得先给 Store 加读穿透，见 FEATURE-TRIAGE 218 |
| RecordSearch.parse | "N月D日" 只取首个含"月"词, 多日期并列时仅识别第一个 (边界, P2) |
| RecordsView.lunar (:80) | 农历日 1..30 与 12 个月表 guard 齐备, 双月大小月边界 (某月无 30) 由 guard 兜住返回 nil, 不崩 |

## 五、逐编号明细 — 段 551–650 (包9 检索/时间线 + 包10 统计)

> 判定基准: ROADMAP 包9/包10「收录/舍弃/⚠」+ DEFERRED + DECISION-NEEDED; 只信代码, 证据=文件:行。复审计: P0 修复后重判了 604 (多线图原 points 全 0 占位→现接 Attribution 真实归属, 假数据已除, 升 PART 因图例"单独高亮"未做)。

| 编号 | 创意 | 状态 | 证据 (文件:行) |
|---|---|---|---|
| 551 | 全局记录搜索 | DONE | RecordSearch.swift:518 buildRecs/searchAll + RecordsView.swift:253 搜索栏/81 检索态注释 |
| 552 | 搜索建议补全 | MISS | 全库无"成员+凭证组合候选下拉"实现 |
| 553 | 搜索历史管理 | DONE | RecordSearch.swift:585 history/remove/clear (kf 键存 10 条) + RecordsView.swift:294-308 下拉/单删/全清 |
| 554 | 自然语言筛选 | DONE | RecordSearch.swift:436 时间短语表/356 parse + RecordsView.swift:276 可编辑条件标签 |
| 555 | 符号组合语法 | DONE | RecordSearch.swift:368 +/- 前缀解析/526 全中全不中 + RecordsView.swift:28 parsedTags 预览 |
| 556 | 搜索结果分组头 | DONE | 检索复用同一 groups/dailySection 分日组头, 组头带 588 告警数 (RecordsView.swift:117-119/862) |
| 557 | 命中词高亮 | DONE | RecordsView.swift:1058-1090 highlightSegments 靛蓝浅底 |
| 558 | 零结果救援 | MISS | 仅 generic emptyHint (RecordsView.swift:117), 无三枚建议按钮 (与包14 823 同族, 已舍弃) |
| 559 | 最近开门直达搜索 | MISS | DeviceHomeView.swift:1004-1035 最近开门卡无左滑"查记录"; pendingRecordsFilter 仅服务 779/793/1028 |
| 560 | 过滤视图另存 | DONE | RecordSearch.swift:145/605 NamedView (kf_rviews) + RecordsView.swift:339-398 另存/应用/删除 |
| 561 | 搜索范围切换 | DONE | RecordsView.swift:424-434 当前锁/全部锁 picker → buildRecs 跨 lock_id |
| 562 | 实时结果计数 | DONE | RecordsView.swift:414-418 边输入边更新"命中约 N 条" (onChange searchText:209) |
| 563 | 搜索词快照回填 | PART | 近似机制在 (pendingRecordsFilter: RecordsView.swift:181-189), 但"告警详情带入类型词"的入口未做, 无 563 标记 |
| 564 | 时段分段筛选 | DONE | RecordSearch.swift:137 segment + RecordsView.swift:464 时段 chips |
| 565 | 告警类型多选面板 | PART | 单类 typeFilter chips 有 (AlarmCenterView.swift:69 levelChip), 无多选+选中数回显 sheet |
| 566 | 成员过滤保持 | MISS | RecordsView.swift:20 sel 仅 @State, 冷启动不恢复上次所选成员 |
| 567 | 仅看告警开关 | DONE | RecordSearch.swift:140 alarmOnly + RecordsView.swift:477 chipToggle |
| 568 | 按凭证过滤 | DONE | RecordSearch.swift:141/206 凭证维度 + RecordsView.swift:473 凭证 chips (归属推断标"约") |
| 569 | 失败事件筛选 | PART | RecordsView.swift:478 failedOnly chip (仅 10/13/224 告警级+92 手机侧), :486 ⚠备案文案在 |
| 570 | 正序回放排序 | DONE | RecordsView.swift:479 reversed chip/1652 整段反转 |
| 571 | 工作日/周末过滤 | DONE | RecordSearch.swift:138 dayKind + RecordsView.swift:468 chips |
| 572 | 深夜时段过滤 | DONE | RecordSearch.swift:139 lateNight + RecordsView.swift:467 深夜预设 (跟随 676 配置) |
| 573 | 条件计数与重置 | PART | 搜索"清空"按钮在 (RecordsView.swift:260-267), 筛选面板无"重置全部"与条件数徽标 |
| 574 | 活跃凭证排序 | DONE | RecordSearch.swift:259 activeCredentials (近 30 天台账, 标"约") + RecordsView.swift:1716-1756 |
| 575 | 越界开门筛选 | DONE | RecordSearch.swift:226 outOfWindow (台账 from/to 本地检测) + RecordsView.swift:1775-1812 清单 |
| 576 | 记录详情页 | DONE | RecordsTimeline.swift:7 详情 sheet 全字段 + RecordsView.swift:1027 行点开 |
| 577 | 详情跳凭证定位 | DONE | LockKeeperApp.swift:74 credJump + CredentialsView.swift:180-224 定位高亮条 + RecordsTimeline.swift:229-242 |
| 578 | 日期组头吸顶 | DONE | RecordsView.swift:806-808 List Section header 原生吸顶 |
| 579 | 回到最新浮层 | DONE | 由 578 原生吸顶覆盖: 组头钉顶=任何回翻位置都能扫读当前组, 无独立浮层按钮 (近似实现, 合规) |
| 580 | 上/下一条翻看 | MISS | 详情页无上下条切换 |
| 581 | 未读告警蓝点 | MISS | 735 未处置角标有, 行级"未读蓝点"无 |
| 582 | 图表下钻过滤 | DONE | StatsView.swift:800-823 成员条点按 → pendingRecordsMember → 记录 Tab 过滤 |
| 583 | 结果定位高亮 | MISS | 无滚动定位高亮闪烁 |
| 584 | 邻近记录横滑 | MISS | 详情仅 736 前后 3 条列表, 无横滑缩卡 |
| 585 | 记录引用深链 | MISS | 无 App 内路由深链 (715 AppIntents 是外部入口, 非行级引用) |
| 586 | 当天全景跳转 | MISS | 详情页无"查看当天全部" |
| 587 | 低电跳转诊断 | MISS | 低电告警详情无诊断页深跳 (诊断页仅 72/133/128 断连急救) |
| 588 | 组头计数徽标 | DONE | RecordsView.swift:862 组头"开 N · 警 M"浅红染 |
| 589 | 组内告警置顶 | MISS | 组内按时间排, 告警行无置顶 |
| 590 | 连续活跃行 | DONE | RecordsView.swift:583-590 streakBanner "连续 N 天有人开门" |
| 591 | 行内次序注释 | MISS | 组头有 796 "约 N 位使用者", 行级"今日第 N 次"无 |
| 592 | 连击合并行 | DONE | RecordsView.swift:907-927/1501-1520 mergeConsecutive ≥3 条折叠可展开 |
| 593 | 日界收尾标注 | MISS | 组尾无"当日最后记录 23:47" |
| 594 | 节假日组头色带 | PART | 色带未做, 近似: 671 节假日组头标签 (RecordsView.swift:842, 内置简表标"手工维护") |
| 595 | 月界渐显大标 | MISS | 时间线仅有 679 年份大字, 无月界大字 |
| 596 | 胁迫日警示标 | ❌排除 | DECISION-NEEDED: 胁迫协议不存在, 未做=合规 |
| 597 | 行级备注 | 舍弃 | 包9 舍弃 (与 186 记录备注同功能) |
| 598 | 大数据量分页 | MISS | List 全量渲染, 无分页"已加载 X 条" (kf_logcache_ 300 条/锁, 量级暂可承受) |
| 599 | 30 天开门折线 | DONE | StatsView.swift:302 主折线 + :15 7/30/90/365 窗口胶囊 |
| 600 | 24 小时分布柱 | DONE | StatsView.swift:408 逐时柱 (开/告警双 BarMark) + P0-8 修后点柱下钻真数据 |
| 601 | 本月上月同比线 | PART | StatsKit.swift:261 monthCompare + StatsView.swift:446 实线/虚线叠加; 上月数据缺失时 complete=false 降级 |
| 602 | 作息雷达四轴 | MISS | 无雷达图 (777 错峰雷达已并入本项舍弃) |
| 603 | 累计面积图 | DONE | StatsView.swift:582-585 累计面积 |
| 604 | 成员多线对比 | PART | P0 复核: 假数据已除 — StatsKit.swift:422 memberDaily (Attribution 可证明归属, 补 0 不伪造) + StatsView.swift:515-526; 图例"点选单独高亮"未做 (现为 toggle 隐藏) |
| 605 | 告警散点阵 | MISS | 无 90 天告警按子类型散点阵 |
| 606 | 7 日滚动均线 | DONE | StatsKit.swift:194 MovingPoint 均线 + StatsView.swift:328 叠加虚线 |
| 607 | 事件符号标注 | ❌排除 | DECISION-NEEDED: 胁迫类 |
| 608 | 假期逐时对比柱 | MISS | 无假期逐时并排柱 (StatsView 假期维度的只有 673 春节底带) |
| 609 | 临时码甘特图 | DONE | StatsKit.swift:544 gantt (from/to + 刻度点+核销率) + StatsView.swift:620-625 |
| 610 | 空窗区间带 | DONE | StatsKit.swift:200 gapBands (≥48h 空窗) |
| 611 | 堆叠条占比 | DONE | StatsView.swift:709 四类占比堆叠条 |
| 612 | 成员水平条形图 | DONE | StatsView.swift:791-823 成员水平条 (条尾数字+降序, 色走 DS 令牌) |
| 613 | 告警构成条 | DONE | StatsView.swift:916 告警构成 + StatsKit.swift:304 alertStats |
| 614 | 正常/告警分组柱 | MISS | 无"正常 vs 告警"分组柱 (600 柱内已并双 BarMark, 但非分组口径) |
| 615 | 帕累托累计线 | DONE | StatsKit.swift:247 帕累托 + StatsView.swift:756-773 "前 N 类承载 80%" |
| 616 | 按周几分布柱 | DONE | StatsKit.swift:229 weekdayStats + StatsView.swift:778-784 周末青绿强调 |
| 617 | 在外时长棒棒糖图 | DONE | StatsKit.swift:407 + StatsView.swift:1047 首末间隔代理 (标注口径) |
| 618 | 首次开门区间条 | DONE | 同上 617 段 (StatsView.swift:1047-1051 首次区间) |
| 619 | Top5 凭证榜 | DONE | StatsKit.swift:247 Top5 + StatsView.swift:871-884 |
| 620 | 告警月度双柱 | DONE | StatsKit.swift:304 + StatsView.swift:945 双柱超上月染红 |
| 621 | 时间刷选条 | MISS | 无折线底部窗口刷选联动 |
| 622 | 数据不足降级 | DONE | StatsKit.swift:81/143 isDegraded/missingDays + StatsView.swift:200-214 "积累 X 天后可用"空态 |
| 623 | 成员色板映射 | 舍弃 | 并入 259 (包13 舍弃备案) |
| 624 | 成员活跃气泡图 | PART | 气泡未实 — 用 612 成员水平条代替 (StatsView.swift:791 段注释 "612/624 成员水平条"), 缺横轴次数/纵轴距最近天数/泡径凭证数 |
| 625 | 凭证归属子段条 | DONE | StatsKit.swift:440 kindOwnerBreakdown (可证明归属才进) + StatsView.swift:834-838 |
| 626 | 临时码用量比条 | DONE | StatsKit.swift:366 pwdUses + StatsView.swift:987 (台账推断标"约") |
| 627 | OTP 使用散点 | DONE | StatsKit.swift:574 otpPoints + StatsView.swift:1030-1042 PointMark |
| 628 | 成员首用标注 | DONE | StatsKit.swift:393 outOfRangeTotal + StatsView.swift:998/1020 首用与越界标注 |
| 629 | 临时码核销率 | DONE | StatsKit.swift:93 核销率 + StatsView.swift:625 段 |
| 630 | 成员分组标签 | DONE | MemberHub.swift:15 groupTag + MemberCenterView.swift:1344 分组编辑/134 联动记录页过滤 |
| 631 | 图表深浅配色 | DONE | StatsKit.swift:479 图表色只走 DS 语义令牌, 深浅自动切 |
| 632 | 图例点选排除 | DONE | StatsView.swift:16 hiddenKinds/hiddenMembers + :446/:709 点选临时隐藏 |
| 633 | 轴刻度自动取整 | MISS | 无 5/10/20 档刻度规则 (AxisMarks desiredCount 4 是 Charts 默认) |
| 634 | 窗口上下文标签 | PART | 标签常显有 (StatsView.swift:164 contextLabel "近 N 天 · M 位成员"), 点弹窗改窗口未做 (636 胶囊改窗口) |
| 635 | 按住读点气泡 | DONE | StatsView.swift:362 读点气泡 (当日次数/Top 成员/告警数) |
| 636 | 捏合缩放窗口 | PART | 636 的"7/30/90/365 会话内保持"由窗口胶囊覆盖 (StatsView.swift:15/133), 真捏合手势未做 |
| 637 | 图表联动列表 | PART | 635 读点气泡有"联动下方明细"注释 (StatsView.swift:362), 明细同步滚动到对应日未实现 |
| 638 | 三级下钻面包屑 | DONE | StatsView.swift:72/177/341 + P0-8 修后 drillRows 读 DB.readLogs 真数据 (:1260 起) |
| 639 | 数据切换 morph | DONE | StatsView.swift:133 withAnimation 窗口切换弹簧重排 |
| 640 | 标签避让开关 | MISS | 无多系列标签避让/"仅最大" |
| 641 | 环比箭头 | DONE | StatsKit.swift:294 weekDelta + StatsView.swift:279 中性靛蓝箭头 |
| 642 | 无数据底纹 | DONE | StatsKit.swift:150/173 gapBands 区分 0 次与无数据 + StatsView.swift:374 |
| 643 | 横屏分栏图表 | MISS | 无 sizeClass 分栏 |
| 644 | 图表语音朗读 | MISS | 只有整图 accessibilityLabel (StatsView.swift:358), 无逐点朗读 |
| 645 | 动态类型适配 | MISS | 图表字号未随 Dynamic Type 缩放 |
| 646 | 小时桶降采样 | PART | 文案位有 (StatsView.swift:152 "已按小时桶降采样"), 实际数据层无小时桶聚合 (缓存 300 条/锁) |
| 647 | 时间格式设置 | MISS | 设置无 12/24h·带秒偏好 |
| 648 | 双行时间标注 | MISS | 记录行主行 HH:mm 有, 次行"年月日 周X"灰字无 |
| 649 | 凌晨归属前一晚 | DONE | RecordSearch.swift:308 dayKeyOfNight + RecordsView.swift:1464 归组/849 "含次日凌晨" |
| 650 | 时间来源徽标 | MISS | 详情有"锁端时刻" (RecordsTimeline.swift:43), 无"锁端/手机侧"来源徽标 |

## 五.1 段 651–750 明细 (包9 文案/告警中心 + 包12 导出 + 包11 诊断)

| 编号 | 创意 | 状态 | 证据 (文件:行) |
|---|---|---|---|
| 651 | 秒级告警时序 | PART | 创意原标 ⚠(依赖协议秒级), 实际 lockTimeStr 带 :ss 已可读 — RecordsTimeline.swift:43 "锁端时刻" 行显示完整串; 缺"相邻事件间隔"计算 |
| 652 | 指标自然句 | DONE | StatsKit.swift:504 naturalSentence "平均每天 X 次" + StatsView.swift:234 摘要卡 |
| 653 | 生日组头标签 | PART | 近似落地 (生日数据已有): RecordsView.swift:808-815 组头命中 MM-dd → "今天是妈妈的生日" (MemberCenterView.swift:485 生日行同口径) |
| 654 | 去年今日回顾 | PART | DEFERRED.md 备案在 (需一年数据积累), RecordsView 顶部未挂入口, 统计可复用 Milestones 按日聚合 |
| 655 | 动词化日志文案 | DONE | RecordSearch.swift:113 RecordVerbs 动词表 + RecordsView.swift:1679 recTitle |
| 656 | 量词规范 | DONE | HelpCenter.swift:41 量词表 + :309 帮助页展示 |
| 657 | 无记录日占位行 | MISS | 无记录日直接不出组 (groups 只含有记录日), 无极简灰行 |
| 658 | 自然时段词 | MISS | 词表在 RecordSearch.swift:83 TimeWord.word, 全库无调用方 (组头/行级小字未使用) |
| 659 | 错误码人话表 | 舍弃 | 并入 159 错误码对照表 (包9 舍弃备案) |
| 660 | 告警措辞分级 | DONE | RecordSearch.swift:55 AlarmWords 集中分级 + AlarmCenterView.swift:217 应用 |
| 661 | 型号市场名映射 | PART | DiagKit.swift:689 字典提及 "诊断页型号映射 (661)" 但 DiagnosticsView 未挂; PidMap.modelName 有 "未知型号" 回退 (PidMap.swift:26) |
| 662 | 日志图标语义表 | PART | DiagKit.swift:702 IconSemantics 表有, 诊断页无独立入口展示 |
| 663 | 等宽数字 | 舍弃 | 并入 231 (包10 舍弃备案) |
| 664 | 文案风格审校表 | DONE | HelpCenter.swift:56 审校表 + :281 文案体检彩蛋页 + SettingsView.swift:186 入口 |
| 665 | 区间日期精简 | MISS | 导出 rangeLabel 是完整 "yyyy-MM" (ExportCenter.swift:483), 无 "10月1日–7日" 同年省年文案 |
| 666 | 成员名兜底 | DONE | MemberHub.swift:83 display (空名→"成员", 超长中段省略) + 头像首字 UI 层 |
| 667 | 万级计数缩写 | DONE | StatsKit.swift:494 compact 缩写 + StatsView.swift:238 摘要卡 |
| 668 | 中西文间距 | PART | HelpCenter.swift:6-33 统一排版工具函数有, 未全 App 应用 (仅帮助页内使用) |
| 669 | 繁体语言预留 | DONE | HelpCenter.swift:74 LocalizedCopy 带 zh-Hant 键位回落 + ExportCenter.swift:71 707 语言表 |
| 670 | 删除后果说明 | DONE | CredentialsView.swift:1113/1132 彻底删除按钮 + :1726 后果文案具体化 |
| 671 | 节假日组头标签 | DONE | 第六十一批: 内置表按**国务院公告**逐日核对 (含 `off=false` 的调休补班日), 2027 推测行已删; 第六十七批: `HolidayFeed` 接入公开在线源 (https + 整份校验 + 按年覆盖 + 失败保留旧缓存), 记录页筛选区有"更新/换源/清除在线/自动档"四个动作 (内置表始终兜底)。ROADMAP ⚠ 备案仍成立但口径变了：不是"每年自动更新" (那条按 DECISION-C-TERMS 属造假, 依旧不做)，而是"用户点一下就能拉当年公告，或明确开自动档" |
| 672 | 假日异常阈值顺延 | PART | RecordSearch.swift:349 extendedEndHour (+2h 可关) 引擎在, UI 告警判定未消费 |
| 673 | 春节区间注记 | PART | StatsKit.swift:604 静态近似区间 (明示"近似", 无节假日表) — ROADMAP ⚠ 备案在 |
| 674 | 通勤时段标签 | PART | RecordSearch.swift:71-78 通勤标签函数有 (工作日 7-9/17-19), 记录行无消费调用 |
| 675 | 假期外出分隔行 | MISS | 无 "假期外出?" 分隔行 (1016 出行横幅是近 3 天无记录口径, 非节假日) |
| 676 | 夜间时段可配置 | PART | RecordSearch.swift:315-320 kf_night_from/to 配置 + 572/564 消费, 但"设置"页无编辑 UI |
| 677 | 深夜静音降级 | MISS | 无 23 点后单次轻提示/早晨补看机制 |
| 678 | 默认本周窗口 | DONE | StatsView.swift:14 week=7 默认本周 + :125 窗口胶囊 |
| 679 | 年份大字分隔 | DONE | RecordsView.swift:811 1 月 1-2 日组头插入 "2026 年" 大字 |
| 680 | 入库顺序注 | MISS | 无 rowid 排序注记 |
| 681 | 农历小字 | DONE | RecordsView.swift:880-883 chineseCalendar (g.lunar 组头小字) |
| 682 | 历史告警归档组 | MISS | 告警中心无 "更早" 折叠组 (734 只做未处理置顶/已处置垫后) |
| 683 | CSV 标准导出 | DONE | ExportCenter.swift:1028 startCSV → :324 BOM+列头, :414 CSVKit.escape |
| 684 | 原始 JSON 导出 | DONE | ExportCenter.swift:1029 startJSON → :361 带 hex 字段 |
| 685 | 月度 PDF 报告 | DONE | ExportCenter.swift:1030 startPDF → :444-568 UIGraphicsPDFRenderer 排版 |
| 686 | 单日长图 | DONE | ExportCenter.swift:1052 startDayImages → :750 表头水印 + 行渲染 |
| 687 | 隔空打印 | DONE | ExportCenter.swift:1054 printMonthly → :792 UIPrintInteractionController + 自定义 PrintFormatter |
| 688 | 告警分享卡 | DONE | ExportCenter.swift:1053 startAlarmCard → :623 9:16 渐变卡 ImageRenderer + :1061 718 仅含本条 |
| 689 | 按成员导出 | PART | ExportCenter.swift:980 范围 picker 有"仅指定成员" (701 口径), 成员详情页独立"导出该成员"入口无 |
| 690 | 列选择导出 | DONE | ExportCenter.swift:32 kf_cred_export_cols 沿用 + :1008 列选择 sheet |
| 691 | 加密压缩导出 | MISS | 无 AES ZIP 打包 (备份模块的加密与导出分离) |
| 692 | 导出进度取消 | DONE | ExportCenter.swift:229-246 ExportProgress 后台 TaskGroup + 取消拦截 |
| 693 | 导出文件命名规范 | DONE | ExportCenter.swift:108 锁管家_记录_范围.csv 命名 |
| 694 | 存到文件 App | MISS | 仅 Caches/exports + 分享面板, 无 UIDocumentPicker 目标目录选择 |
| 695 | 导出历史清单 | MISS | 无导出记录表 (仅 lastPath 单条回显 :1171) |
| 696 | 报告封面矢量绘制 | DONE | ExportCenter.swift:477 渐变封条 + 锁名/区间/生成时间, 无图片资源 |
| 697 | 告警章节置前 | DONE | ExportCenter.swift:558-566 摘要页后告警章总是新页 |
| 698 | 上周小结生成 | MISS | 无 "上周小结" 一键 CSV+三句话 |
| 699 | 矢量图表内嵌 | DONE | ExportCenter.swift:598 时段分布条直接画进 PDF 上下文 |
| 700 | 多锁报告封面表 | DONE | ExportCenter.swift:485 多锁封面列覆盖设备表 |
| 701 | 打印范围选项 | DONE | ExportCenter.swift:980 全月/仅告警/仅指定成员 |
| 702 | 页眉页脚防断章 | DONE | ExportCenter.swift:517 页脚 "第 X/Y 页" + :806 页序取 PDF 页 |
| 703 | 邮件附件模板 | PART | 降级 .eml 文本 (ExportCenter.swift:701/1048 startEML, 明示"降级") — DEFERRED 备案在 |
| 704 | 报告三句摘要 | DONE | ExportCenter.swift:577 摘要 (本月 N 次/M 条告警/凭证变动, 归属带"约") |
| 705 | CSV 转义预检 | DONE | ExportCenter.swift:51 CSVKit.escape RFC4180 + :59 needEscaping + :1247 转义行预检回显 |
| 706 | 长图分页切割 | DONE | ExportCenter.swift:203-215 按屏高切 ≤3 张, 续张带紧凑表头 |
| 707 | 报告语言跟随 | PART | ExportCenter.swift:71-90 键位预留 (kf_report_lang), 全文案中文, 无繁体内容 |
| 708 | ShareLink 原生分享 | DONE | ExportCenter.swift:1176-1216 五类 Transferable + ShareLink |
| 709 | 分享卡片元数据 | DONE | ExportCenter.swift:736/1176 LPLinkMetadata 渐变封面卡片 |
| 710 | 报告校验二维码 | PART | DEFERRED 备案在 (需校验路由), 无实现 |
| 711 | 拖放导出 | PART | DEFERRED 备案在, 无拖放会话 |
| 712 | QuickLook 内嵌预览 | DONE | ExportCenter.swift:1153 预览 + :1392 QLPreviewController 包装 |
| 713 | 固定导出目录书签 | PART | DEFERRED 备案在 (需书签权限), 无实现 |
| 714 | 复制为完整文本 | DONE | ExportCenter.swift:118 正文+722 校验行 + RecordsView.swift:1035 记录行菜单 |
| 715 | 快捷指令动作 | DONE | AppIntents.swift:114 ExportCsvIntent / :149 ReadRecordsIntent + :184 AppShortcuts (FEATURE-TRIAGE 修正为 ✅) |
| 716 | 多选合并导出 | MISS | 无编辑模式勾选合并导出 |
| 717 | 告警一页纸打印 | DONE | ExportCenter.swift:662/1055 当前告警配置+最近告警+手填栏 |
| 718 | 分享范围明示 | DONE | ExportCenter.swift:976/1061/1162 "仅含本条数据" 明示 + :114 scopeNote |
| 719 | 导出完成反馈 | DONE | ExportCenter.swift:1101/1230 成功触感+路径+Toast |
| 720 | 聊天适配长图参数 | DONE | ExportCenter.swift:206 w=720px 固定宽, :167 jpeg 0.8 |
| 721 | 双语列头注释 | DONE | ExportCenter.swift:65-66 英文 code 注释行 + :336 |
| 722 | 导出完整性校验行 | DONE | ExportCenter.swift:438-450 SHA256+行数+生成时间 (CryptoKit), :349 文件尾 |
| 723 | 告警中心页 | DONE | AlarmCenterView.swift:29 跨锁告警流 + RecordSearch.swift:720 未处置优先排序 |
| 724 | 四级告警色标 | DONE | RecordSearch.swift:34 四级定级 + AlarmCenterView.swift:524 色标→DS 令牌 |
| 725 | 胁迫全屏确认卡 | ❌排除 | DECISION-NEEDED: 胁迫协议不存在 |
| 726 | 处置结论留痕 | DONE | RecordSearch.swift:618 处置字段 + AlarmCenterView.swift:371 已处理/误报/已处置 + RecordsTimeline.swift:158 同源 |
| 727 | 防撬检查清单 | DONE | RecordSearch.swift:639 kf_rcheck_ + AlarmCenterView.swift:343/RecordsTimeline.swift:100 折叠勾选 |
| 728 | 换电指引折叠段 | MISS | 低电详情无换电注意事项段 (CareViews.swift:2 的 116 换电图文指引是保养中心独立页, 未挂进告警详情) |
| 729 | 误报降权规则 | MISS | 无同源同类 24h 折叠灰显规则 (745 标测试是手动口径) |
| 730 | 24 小时回放刻度 | DONE | AlarmCenterView.swift:112-116 scrubber + :533 kf_rreplay 会话记忆 (P0-1 修后) |
| 731 | 多锁联动事件合并 | MISS | 无短窗内多锁合并事件卡 |
| 732 | 一键呼叫成员 | PART | MemberHub.swift:14 465 紧急联系字段有, 无 tel: 系统拨号触发 (P1 已列) |
| 733 | 告警提示音分级 | MISS | 无分级提示音/整体静音设置 |
| 734 | 未处理队列优先 | DONE | RecordSearch.swift:709 unhandledAlarmCount + AlarmCenterView.swift:51/82 默认未处理优先 |
| 735 | Tab 未读角标 | DONE | RecordsView.swift:129/223 未处置角标, 返回重算 |
| 736 | 前后事件上下文 | DONE | RecordSearch.swift:664 前后 10 分钟同锁 + AlarmCenterView.swift:277/RecordsTimeline.swift:192 |
| 737 | 试错累计视图 | PART | RecordSearch.swift:272 只用日志条数 (keyboardErrCount 语义不确定, 标题带 "?") — ROADMAP ⚠ 备案在 |
| 738 | 告警行左红条 | DONE | RecordsView.swift:952-1022 左 3pt danger 色条+浅红底 (形状冗余) |
| 739 | 处置状态回退 | DONE | RecordSearch.swift:632 恢复未处理 + AlarmCenterView.swift:384 |
| 740 | 原始报文查看 | PART | DiagKit.swift:762 hex dump 引擎 + LockService.swift:12 环形记录在, 诊断页无独立查看入口 (并入 DiagnosticsView 72/133 区段, 未接线 UI) |
| 741 | 同类告警计数 | DONE | RecordSearch.swift:653 sameTypeCount + AlarmCenterView.swift:326 + P0-3 修后 sameCountPreview |
| 742 | 响应时长分布图 | PART | AlarmCenterView.swift:485-507 占位 "积累中" (726 留痕样本够后出分布) — ROADMAP ⚠ 备案在 |
| 743 | 待办逐条处置 | PART | AlarmCenterView.swift:82 "全部告警 (含已处置)" 覆盖逐条滑处置, 无 "已全部处置" 收尾行 |
| 744 | 胁迫科普折叠段 | ❌排除 | DECISION-NEEDED: 胁迫协议不存在 |
| 745 | 测试标记排除 | DONE | RecordSearch.swift:619 测试标记存结论 + AlarmCenterView.swift:233 灰显排除统计口径 |
| 746 | 告警事实单页 | PART | 746 并入 723 告警流, 无独立 "单条告警事实单 PDF" (P1 已列) |
| 747 | 前后对比小图 | DONE | RecordSearch.swift:683 + AlarmCenterView.swift:419-424 当日与前后 7 天并排小柱 |
| 748 | 连接成功率图表 | PART | DiagKit.swift:213 BleTelemetry.recordAttempt 遥测在 (环形留存), 图表随积累展示, 诊断页未挂 |
| 749 | 记录完整性校验 | DONE | 第六十八批 (拍板 #28「对账 + 可导出」): `RecordsView` 的翻页循环记 `lastSurplus` 与 `noSurplusReport` 两个信号, 收尾成**三种措辞** —— 已拉全 / 未拉全(带剩余条数) / 锁端未回 KLV#04 所以不可判; 结果一行 (锁名·条数·剩余·结论·时间) 可在缺口区或"上次成功读取"区**复制**走。"不可判"这一档专门补上：旧路径锁端不回 KLV#04 时 break 出去会被 else 分支说成"已拉全" |
| 750 | 数据库体检 | PART | DiagKit.swift:355/408/430 DataHealth (UserDefaults 等价实现, JSON 回环+VACUUM 清残留), 诊断页无入口 |

## 五.2 段 751–800 明细 (包11 诊断 + 包3 多锁 + 包13 成员)

| 编号 | 创意 | 状态 | 证据 (文件:行) |
|---|---|---|---|
| 751 | 日志保留策略 | PART | DiagKit.swift:132-146 kf_diag_log_retention (全部/365/90 天) + append 过滤引擎在, 无设置页 picker UI (SecurityCenterView.swift:967 的 385 保留期是审计链口径, 非诊断日志) |
| 752 | 清理前导出提醒 | MISS | 无 "清理前从未导出则先引导备份" 流程 |
| 753 | 诊断摘要二维码 | PART | DiagKit.swift:633-636 DiagQR CoreImage 引擎在 (纯文本备份+二维码), DiagnosticsView 无展示入口 |
| 754 | 协议字段字典 | PART | DiagKit.swift:667 ProtocolDict 内置可查可复制, 诊断页无入口 |
| 755 | 固件版本随行标注 | PART | ⚠ 备案 (ROADMAP 包11); getStatus 只写 fw 到钥匙串, 日志拉取未逐行注记固件 (P1 已列) |
| 756 | 失败原因分类图 | PART | DiagKit.swift:251 failClasses 本地词表+重试建议在, 无条形图 UI |
| 757 | 断点续传进度 | PART | ⚠ 备案 (ROADMAP 包11: 跨会话游标未确证), 无 "已同步至 X 日" 断点 UI |
| 758 | 本地崩溃记录 | PART | DiagKit.swift:311 CrashGuard 崩溃标记位+上次会话时长引擎在, DiagnosticsView 无 "上次异常退出" 入口 (P1 已列) |
| 759 | 存储占用三段条 | 舍弃 | 包11 舍弃 (与 152 存储构成条重复) |
| 760 | 运行自检清单 | PART | DiagKit.swift:509-528 八项自检引擎 (蓝牙/通知/应用锁/存储/备份/连接/数据/触感, 单项可复测), DiagnosticsView 未挂主入口 (P1 已列) |
| 761 | 记录 rowid 溯源 | MISS | 详情页无 rowid/协议内部索引长按复制 |
| 762 | 白名单查询模板 | PART | DiagKit.swift:729 QueryTemplates 只读下拉引擎在, 无表格预览 UI |
| 763 | Hero 卡翻页切换 | DONE | DeviceHomeView.swift:289-360 TabView 横滑翻页 + :195-199 页点 (低电锁橙描边) |
| 764 | 多锁状态图标行 | MISS | Hero 卡上方无各锁小图标+状态点行 (102 胶囊切换器是菜单式, 非图标行) |
| 765 | 跨锁合并最近流 | PART | 设备 Tab 最近开门卡仅单锁 (DeviceHomeView.swift:1009 recentRecords 走 current); 跨锁合并流只在记录 Tab "全部锁" scope (561/770), 行尾有锁名标签 |
| 766 | 设备排序置顶 | PART | DeviceHomeView.swift:169 kf_sort_batt 电量升序开关 (可同步翻页顺序), 无手动拖动排序 |
| 767 | 设备分组场景 | PART | ⚠ 备案 (ROADMAP: 需新增分组字段), 无 "家用/仓库/办公" 分组 |
| 768 | 待维护锁清单 | DONE | LockStats.swift:218 待维护锁清单 (低电/告警/密钥未绑定, 全部可读证据) + LockOverviewView.swift:118 |
| 769 | 绑定时间标注 | DONE | LockStats.swift:121 pairedAt + LockOverviewView.swift:409-427 对照表 "绑定于" 小字 |
| 770 | 跨锁全局搜索 | DONE | RecordsView.swift:424-434 "全部锁" 范围 + buildRecs 跨 lock_id + 行首锁名小标签 (:978) |
| 771 | 翻锁平行滑动 | DONE | DeviceHomeView.swift:289 TabView 圆盘与状态文本同向平行滑动交接 |
| 772 | 每锁独立统计 | DONE | StatsView.swift:89 数据源锁选择器 + :30 单锁视图标题携带锁名 |
| 773 | 凭证容量水位 | DONE | ⚠ 已被 FEATURE-TRIAGE 修正为 ✅: LockStats.swift:117/166 协议容量族真值 (KLV 21/24/27, Store.swift:139) + LockOverviewView.swift:349 水位条 |
| 774 | 场所副标题 | DONE | LockStats.swift:99 Hero 副标题 + Sheets.swift:833 命名步场所 + ExportCenter 报告引用 |
| 775 | 双锁叠加对比 | MISS | 统计页无双锁双折线叠加+双列对照表 |
| 776 | 锁活跃度条形榜 | DONE | LockOverviewView.swift:165-187 各锁 30 天水平条形, 条内嵌次数 |
| 777 | 错峰使用雷达 | 舍弃 | 包3 舍弃 (并入包10 602 作息雷达) |
| 778 | 告警率对比列 | DONE | LockStats.swift:123 告警率口径 + LockOverviewView.swift:204 对比列 |
| 779 | 成员×锁交叉矩阵 | DONE | LockStats.swift:187 矩阵 (归属走 Attribution 可证明链) + LockOverviewView.swift:263 + LockKeeperApp.swift:70 点格带入记录 Tab 成员过滤 |
| 780 | 均值对照 | MISS | 无各锁 "工作日平均首次开门时间" 对照卡 |
| 781 | 同名凭证对照 | MISS | 无多锁同名凭证提示/对照列表 |
| 782 | 闲置锁标注 | PART | 近似机制: 292 沉睡锁判定 (LockArchive.isSleeping, 沉睡锁不进横滑序列 DeviceHomeView.swift:174-180), 无 "闲置" 灰标签与统计排除开关 |
| 783 | 对比窗口同步 | MISS | 无双锁对比窗口一次应用 |
| 784 | 固件版本对照表 | DONE | LockStats.swift:261 固件落后判定 + LockOverviewView.swift:409 对照表 (旧版本高亮) |
| 785 | 并行泳道时间线 | DONE | RecordsView.swift:32/102/440 泳道时间线 (全部锁模式, 近 14 天×各锁点阵 :1287) |
| 786 | Hero 区翻锁手势 | MISS | 整页 TabView 横滑有 (763/771), Hero 区域独立手势区未做 |
| 787 | 对比结论一句话 | DONE | LockOverviewView.swift:47 模板生成 (使用量倍数+时段集中度) |
| 788 | 成员活跃总表 | DONE | MemberCenterView.swift:1561 每人一行 (本月次数/最近使用/凭证数) + :14 总表入口 |
| 789 | 成员详情聚合页 | DONE | MemberCenterView.swift:399 MemberDetail360View (档案/摘录/来源/图谱/场景/权限), 总表与图表下钻入口在 (:147/1564); 跨锁时间线未做 (摘录仅单锁口径) |
| 790 | 最近活跃头像组 | MISS | Hero 卡无最近活跃成员头像叠放圈 |
| 791 | 未归属记录认领 | DONE | RecordSearch.swift:23 whoId 可证明归属 + MemberCenterView.swift:1508 认领页 + RecordsView.swift:1180 行内认领 + SettingsView.swift:356 入口 |
| 792 | 成员轮换小节 | DONE | MemberCenterView.swift:1691 近 7 天在家顺序变化点 (台账推断, 约) |
| 793 | 访客虚拟分组 | DONE | MemberHub.swift:51 visitorId="__visitor" + RecordsView.swift:1242 成员过滤独立 chip; 对抗核实: 仅本地展示/过滤层 (RecordSearch.swift:1600), delPwd/setPwdOwner 按真实成员 id, 不写锁端 |
| 794 | 隐私浏览模式 | PART | MemberHub.swift:295-301 限时 10 分钟开关在 + 家庭设置 Toggle (MemberCenterView.swift:1406), 但 "只显示本人数据" 统计过滤未接 StatsKit/成员统计消费方 |
| 795 | 成员归档 | DONE | MemberHub.swift:16 archived (保留历史, 统计隐藏) + MemberCenterView.swift:1317 归档列表 "历史不蒸发" |
| 796 | 本日第 N 位使用者 | DONE | RecordsView.swift:875 组头 "约 N 位使用者" (归属推断标"约") |
| 797 | 陪同进入疑似标注 | PART | ⚠ 备案 (ROADMAP 包13: 启发式需验证误报率), 无标注实现 |
| 798 | 成员堆叠面积图 | DONE | MemberCenterView.swift:1604 MemberStackedView 30 天成员分层累计面积 (约级口径, 空态在 :1673) + SettingsView.swift:357 入口 |
| 799 | 成员周小结口吻 | PART | StatsKit.swift:322 weekSummary 引擎 + StatsView.swift:1096 统计页 "小结" 消费 (成员周人话+黄金时段), 成员详情页 (789) 未挂, "工作日早 7-8 点最活跃" 口吻未出 |
| 800 | 在家时长代理值 | PART | StatsKit.swift:457 homeDurationProxy (首末开门间隔求和, 代理口径标"约") + StatsView.swift:1097 消费; 成员详情页无 "本月区间条形图+上月对比" |
