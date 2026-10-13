# 临时交接（交给下一个 AI）— 2026-10-11 17:30 会话进行中

这份只写**当场可复算的事实**。每条都给复算命令。别信任何一条没有命令支撑的话。

---

## 1. 仓库现在在哪

- 分支 `main`（**本仓唯一分支**），`git log --oneline -2 | cat` 前两行应为：纯文档对齐提交（本文件最新版）与 `eaf7dfd`（批25 try/await 覆盖扫描）。
- **领先 `origin/main` 177 个提交，未推送**：`git rev-list --count origin/main..main` ⇒ 177
  （本批 `2aa0f5f` 再加一；对齐前实测 177）
  （含本对齐提交自身；对齐前实测 175）。
- 复算本会话做了什么：`git log --oneline -30 | cat`。

### 1a. 工作树干净，全部改动都已提交

`git status --short` 应为空（`state/` 是 gitignore 的跑批草稿区，不算）。

- `aa94d02` = 安全族接线合批（377 访客通道 / 383 销毁 sudo / 296 只读闸 / 502 门槛统一 +
  A1 收尾 guardedPurge 接线 + A2 措辞），8 文件。
- `1f15ec2` = A3 消费点合批（376/486/331/469/468/779/902），9 文件。
- `a4b9826` = PART-b A 类 17 条（369/391/545/612/388/373/375/378/754/845/543/385/1043/1022/1023/164/245），12 文件。
- `a635d52` = cherry-pick -x 320df35：换机迁移 438-446 真流程（BackupStudio.swift / BackupStudioKit.swift）。
- `45a11c3` = 194+409 备份文件名加时分 + 387 充电备份记账。
- `94ead63` = PART-a A 类 22 条（含 460/262/261/474/761/63/812/471/185/597/815/274/942/861
  + 16/735/712/693/795/817/351），13 文件；444/433/440 复核后确认已被迁移真实现，未重复施工。
- `06ecec5` = 交接书对齐 94ead63：A 类三批全闭，剩余主战场 = 三工单 B 类。
- `3d9e661` = FAKE 工作单 B 类 10 条落地（964 审计来源图标 / 269 就绪轻震 / 517 立即清除 /
  55 轻点背面分步指引 / 212 交错入场 / 636 捏合缩放窗口 / 11 复制形变 / 14 月度热力格 /
  23 滚动视差 / 995 入伙欢迎卡），12 文件；419/446 复核后确认已被迁移真实现，未重复施工。
- `6244135` = PART-b B 类首批六条（259 成员建档色板 / 822 备份到期建议 / 665 导出页眉区间 /
  781 全库同名扫描 / 109 删锁记录计数预告 / 650 时间来源色点），6 文件。
- `82d1f2d` = PART-b B 类第二批五条（400 备份闸毫秒换算 / 223 归档开关+启动归档 /
  666 成员 N 兜底 / 44 更新说明落点按钮 / 480 关怀卡成员色），7 文件。
- `a8bc4b4` = PART-b B 类第三批五条（128 拥挤度量首台耗时 / 782 排除闲置锁口径 /
  758 启动异常卡+档案导出 / 159 日志 rc 跳对照表 / 147 DFU 耗时），9 文件。
- `a922960` = 交接书对齐 a8bc4b4（纯文档）。
- `ec10e6f` = PART-b B 类第四批五条（105 记录行锁符号色标 / 45 电量 sparkline /
  658 时段词轴标×2 图+面包屑+下钻标题+峰值行 / 587 pendingDiag 真路由 / 987 悬念行），7 文件；
  917 复核为 `docs/DEFERRED.md:254` 已拍板「不改行」，未重复施工。
- `68cbc0c` = 交接书对齐 ec10e6f（纯文档）。
- `8c09c5b` = PART-b B 类第五批四条（726 导出报告含处置历史（ExportRecord.key + 报告文本段/PDF 章/告警一页纸行内标注）/
  737 试错逐次事件 trialEventsToday + 键盘冻结行 + 涉事凭证明写「无法归属」/
  743 告警行 swipeActions（已处理/误报）+「已全部处置」收尾口径 /
  745 testMarkedKeys 移入 Core 并被 StatsKit.build 与 LockStats.usage 消费，测试标记真排除统计），6 文件。
- `b9f0761` = 交接书对齐 8c09c5b（纯文档）。
- `9c49ccb` = PART-b B 类第六批三条（609 甘特刻度按真实时刻（TempGantt.ticks [Int16]→[Date]，
  圆点按 w*offset(d) 真实定位并夹在条内，替换硬编码 w*0.5 叠堆）/
  629 过期侧同样给核销率 + 每行 4pt 核销比率条（过期转灰 / ≥0.8 转橙）/
  625 成员色子段下挂图例（色点+名字+约 N 次，按次数降序超 4 位折叠，a11y 同步带折叠位数）），2 文件。
- `24a278e` = 交接书对齐 9c49ccb（纯文档）。
- `bc16cf0` = PART-b B 类第七批四条（844 锁死演练第 3 步改真冷却倒计时界面（镜像锁屏 389 读秒，
  演示压缩 12 秒 + 结束句停留 2 秒）/ 1038 notifyNow 增 dayDeliver（夜间不丢 → 挂下一 08:00 白天送达）+
  固件提醒「只此一次」改 30 天复提醒（kf_fw_notify_at_<v> 毫秒戳）/ 550 首启承诺页三处文案对齐
  WebDAV 实装（默认离线 + 联网仅自配通道）/ 905 设备页快捷格 contextMenu「编辑快捷操作格」→
  QuickTileEditorSheet（QuickPool 同数据源即时生效）+ 设置页互相指路），6 文件。
- `dda5647` = PART-b B 类第八批三条（768 总览待维护行由 select+切设备页改本地 sheet 直达该锁告警流
  （AlarmCenterView 加 lockMac 可选参数, 单锁标题带锁名）/ 778 活跃度榜告警占比 ≥20% 整体上浮 +
  行内「偏高」标签 + 行可点下钻, 阈值收 alarmHighCut 一处 / 769 设备管理行加「绑定于 …」小字
  （LockArchive.boundLabel 统一口径）+「按添加时间排序」按钮（persist 出口, tag 参数）），4 文件。
- `27ecd33` = PART-b B 类第九批五条 + 顺带口径修复（1011 陪伴天数唯一算术 companionDays/FullYear,
  凭证行满年同判据胶囊 / 151 体检面容项补系统设置指引（无深链不摆假按钮）+ 本地网络如实脚注 /
  955 成员意图补今日门次（startOfDay 起算, 同一 Attribution 口径）/ 162 握手在别 Tab 走到 success
  → 设备 Tab ✓ 角标回页即清 / 226 令牌层 HeroSurface.resolve(in:) 降透明退纯色+描边覆盖 12 消费点
  / 体检总分收进 DiagHealth.percent——原先 runAll raw/10 与视图 raw/2 各算各的, /100 是假数），10 文件。
- `4835970` = PART-b B 类第十批五条（952 意图冷却按意图分键、六条意图全接入（原先仅两条且共用一个键）/
  953 审计流水「快捷指令执行」独立分区（SensitiveLedger.intentItems；388 视图默认不混排）/
  676 统计深夜轴读「夜间时段」配置（每时只进一轴；雷达页脚跟随）/ 594 记录组头日型色带 4pt 每天出现
  （工作日/周末/节假日三档固定语义色, 补班日按工作日, 带 VoiceOver 标签）/ 158 体检历次分数回看
  （最新在前 8 条, 差值只与上一次比）），8 文件。
- `b019b3b` = PART-b B 类第十一批五条（392 面容失败/中断回调留痕带「方式」（取消不计连败）/
  449 信封魔数加宽全键 + 声明长度校验（点名"文件头损坏"）/ 224 启动预热三项读取并发（如实注明无 SQLite）/
  751 切档先报将删条数 → 二次确认 → 立即裁剪 / 206 圆盘外沿磨砂环双层材质），8 文件。
- `f314d63` = 第十二批（侦察补丁单应用，20 文件）：452 孤儿日志缓存转 `kf_logpark_` 停放不真删（删锁≠烧证据）/
  760 体检第 10 项「备份文件可读性」（信封/明文 checksum/损坏三判）/ 574 活跃凭证按「类型 #槽位」计次挂台账备注 /
  50 年度报告加季度拆行 + 最常用凭证 + 告警最少月 / 498 批量停用已过期项标「过期」/ 945 UnlockIntent 可选
  「Face ID 确认」（fail-closed + AuthKit.verifyBiometricAsync）/ 947 StatusSnapshotData 增 Optional zotpPeriod
  （03#05 单位分钟；OtpIntent 按锁端周期生成 + 落剪贴板）/ 954 集成中心换快捷指令上主屏真教程 /
  799 成员页周小结（近 7 天可证明归属 + 工作日最活跃段）/ 801 引导末卡直达添加设备弹层 / 805 重看引导行带
  已完成步数 / 811 首启自检改真探测（蓝牙/存储/AES 回环，撤假打点）/ 838 录前预习改 30 秒 + 真录入入口 +
  可取消 / 1013 保养到期通知 m4.care.<mac> 切锁推维护页（与 587 同构）/ 248 HeroCard 夜间光源降峰 /
  83 圆盘终态失败「再试一次」/ 461 记录行「称呼（备注）」/ 232+883 无障碍名与 15 对对比值清单 /
  855 runFocusAudit 优先实屏读序 / 1026 城市本地气候表冷季提醒。
- `01bdfec` = 批13+14（两段侦察报告补丁单串行应用，28 文件）：
  379/380 台账写入唯一漏斗 saveLedger 前后字段级 diff 入管理流水（口令只记指纹前 4 位，明文不落审计链）/
  402 离职清除改走回收站 `kf_cbin_`（365/504 可取回；旧 `kf_offboard_` 归档族无取回入口 = 黑洞）/
  448 自检基线挪到备份发生点（markBackupBaseline 由 Milestones.recordBackup 尾调用，自检只比不改）/
  1018 备份通知点按 → 本机还原点 + 指路备份工作室（冷启动 10×200ms 等待）/ 198 节奏三档 manual/weekly/monthly
  换档重排通知 / 430 滚动保留按月保 1 份（AuditLog 记清）/ 422 WebDAV 下载先预演再确认入库（确认对话框）/
  423 清单 etag HEAD 先行 / 436 抽样数 parsePreview 实算 / 193 体积对比行（markExportSize 三入口）/
  346 静态码建档带备注 noteDraft / 518 草稿四口留稿
  （关闭/侧滑 onDisappear/提交后 submitted 不再回存/restoreDraft 口径）/ 317 无成员直达建完成交回 pendingFpOwner /
  319 详情重录（prefillOwner + prefillReplace + 旧枚进回收站）/ 322 缺指纹直达预填 / 329 一句话口令 ShareLink /
  304 同值查看到详情跳转（两处）/ 552 搜索组合候选 / 558 时间词 must 摘除 + 「今天」候选 + 清过滤独立行 /
  577 jumpBarOn 活过 consumeCredJump / 590 连续活跃行 + 近 7 天断档灰点 / 796 本日第 N 位使用者 /
  862 高对比玻璃降实底（含 kf_hc）/ 270 RSSI 骤降检测（prevRssi 统一入口）/ 131 会话重协商旗标行 /
  919 成员别名显示族（Home/Alarm/Records chip/RecDetail/两处 RecordVerbs）/ 462 合并/离职迁移认领 /
  921「再开一次」快捷格（QuickPool.repeatTarget）/ 905 十一选六 / 366 月度清理任务行 / 511 数据事件段 /
  866 极限字号自检（如实标目检）/ 740 帧字段解析（FrameFields 名源 = 754 协议字典）/ 157 报告补近 7 天留档 /
  724 告警级别入导出（levelName 四路）/ 457 头像读建档色 / 463 建档流程内直达录指纹 / 789/792/798 成员栈三修 /
  395 救援码未点「已手抄」不生效 + 无应用锁禁用。
  侦验收尾：batch12-13 与 PART-a batch01-02 两份报告已全部消化；PART-a batch03-06 报告已在
  `state/recon/PARTa-03-06.md` 落盘（35 条：已闭 4 / 降级 5 / 开放 26），首批三条已随下方 07af81b 消费。
- `07af81b` = 批15（A1 收尾七条 + PART-a b03-06 首批三条，10 文件）：
  236/377 访客通道标注合流（DEFERRED 舍弃表口径）+ recentRecords 带出可证明成员 id /
  559 首页最近开门行长按 → 查该成员记录（卡片区不是 List，swipeActions 拉不出，替代口径注释写明）/
  565 记录页告警类型多选面板（按协议实际五类渲染，不虚构「胁迫」，与 725 同口径）/
  790 Hero 卡最近活跃头像圈（借合并流同一刷新时机，不每帧现算全量日志）/
  829 配网失败常见原因三折叠（默认收起）/
  830 WebDAV 首次连通加密说明条（原句 3 秒自动收起与 HintOnce 全仓纪律冲突，替代=用户手关+一次记档）/
  887 备选图标与 Widget 染色核读确认（4 套图标集全含 dark/tinted 变体；Widget 零图资产系统自染）/
  112 换机验证向导去多锁门槛 / 692 导出取消语义补齐（detached 生成体存引用，取消后不写回）/
  704 导出摘要最活跃补「占比约 X%」。
- `9848301` = 批16（PART-a b03-06 ExportCenter 族八条，1 文件）：
  685 明细章按日分节（dayKey 变点插小标题）/ 686 单日长图「导出哪一天」选择器（选项=有记录近 14 天）+
  首张补完整表头 / 697 封面本期告警数 + 章节目录行 / 699 摘要页成员占比横条（只计可证明归属）/
  701 范围 Picker 暴露既有 .day 档 / 702 PDF 两遍渲染写「第 N / M 页」（顺修 pageIdx 初值使首个正文页
  与摘要页同印「第 2 页」）/ 703 MFMailCompose 系统邮件直发（未配置邮箱回退 .eml）/
  719 失败重试（重放上次起点闭包；取消不重试）+ 成功对勾动效。
- `63eb885` = 批17（PART-a b03-06 Stats 族四条，1 文件）：
  604 成员窗口显式 7/30 双档（weekChips；week 此前无赋值方、恒 7 无入口，678 未拍板默认仍 7；
  memberSeries/legendChips/多线读屏标签统一从 week 取一份）/ 628 成员多线起点插旗（每成员首枚可证明归属点，
  读屏报首次记录日）+ 长期密码行归属可证明时整行点按 → 记录页按该成员过滤（582 同路由）+ 指纹无独立
  首用数据落一行口径实话 / 635 读点气泡补「成员最多: 约 X（n 次）」行（memberDaily 同一归属链，归属不出不出现）/
  644 趋势折线逐点 .accessibilityLabel/.accessibilityValue + 面积图读屏隐藏防双念。
- `8594645` = 批18（PART-a b03-06 凭证族八条，7 文件）：
  358 整理建议行带预勾选回列表多选（pendingCredSelect 会话态深链, 复用 editMode/selPwds 状态机,
  落地后整张凭证中心收起直达列表；过期/重复值/无归属三支与建议生成同源取集）/
  359 2 小时档提醒行改可点（跳**最近到期**一条详情, 与行内计数同源 dueSoonPwds）+
  详情页三档预警开关（同键 kf_calert_, 读写都经 alert/saveAlert 防双源漂移; 无到期点显"不适用"）/
  527 智能列表加属主输入（成员 id 或姓名解析成 id, 解析不中退回重填; 顺修旧写法每勾一项
  整条向导重启、勾选与名称全丢的缺陷）/ 529 段尾统计抽 segStatRow + 指纹段尾
  「本段 N 枚 · 近 30 天指纹开门约 M 次 [· 告警约 K 条]」(type3/type13, 标约, 与密码段不是一个读数)/
  821 临时码零库存块从 emptyHint 提出挂列表固定位（有密码但没发过临时码时原先永不出现）/
  849 双击拷贝明文（MaskedDigits 每位 simultaneous 双击 + 容器兜缝; credRow 非编辑态双击;
  对 VoiceOver 走转子动作, 不拿"双击"假承诺）/ 901 紧凑档隐藏副行只留名称与状态
  （kf_row_h ""/tall 两档语义补全, 设置页标签改紧凑/舒适; 44 触达不变）/
  922 批量删除（锁内直删 + 回收站留档, 中断如实报已删数）+ 批量置顶（setStar 同键补写点）;
  batchBar 拆两排（整理类 / 破坏性）。
  PART-a b03-06 剩余开放 800/120/1047 与降级五条 617/684/700/707/820 —— 已由批19/20 全闭（见下）。
- `db06a19` = 批19（电量族 120 + 快捷格 1047 全闭，5 文件）：
  120 低电降级扩至 ≤20%（BatteryCare 11...20 档 severe + DesignSystem `Motion.tier` 低电分支 calm +
  `appLowBattery` 内存缓存）/ 1047 快捷格静默学习满 30 天首格自动推荐（kf_quick_since / kf_quick_smart_set；
  手动关 = 停止记录并清空计数，与设置页文案一致）。
- `d212898` = 批20（354 归档三面收口 + 235 面容落键盘 + 审计实弹修复 + 601/统计双重开窗 + 七项拍板定案，13 文件）：
  354 归档只在「看得到/选得中/直达得到」三面收起（正常列表 + 按成员视图 + 批量选择器 + 921 快捷直达 lookup
  全接 isArchived；搜索路径仍可见 = 收起不是失效；全归档不再谎报台账空；归档区卡片 = 唯一还原落点含全部还原）/
  800 统计三处「近 N 天」（weekSummary/memberCounts/memberDaily）改读原始 logs 不被主图窗口叠短 +
  601 月对比半开区间 [月起, 次月 1 日) 不丢上月尾日 /
  235 面容连败 2 次自动落回密码键盘（faceFailStreak/faceHint；清 failed 防陈旧错误行把提示挡在 !failed 之外）/
  审计实弹：821 首张临时码死按钮+假回执（genOtp 改 Bool 回执 + genFirstOtp 归还 busyKey 占用）与
  120 低电分支 DB.lastDevice→DB.preferredMac（lastDevice 是 BLE 外设 UUID，恒 false 的死路）/
  拍板定案七条入账（235 做已落地；276/278/297/416/447/990 判 ❌）+ featuremap 常驻断言重钉 15 条；
  五条降级追认：617 横条=替代形态已论证 / 684 行级 hex 帧属新数据面且 JSON 已明示 / 700 封面设备表已覆盖 /
  707 无第二语言词表（与 297 判 ❌ 同理）/ 820 otpExplainer 已按 30 分钟锁端轮换论证 —— 均为「替代口径已落地、
  照原句改=重复推翻既有拍板」，不作返工。
- 批20 后 5 路只读审计军团全部回报并消费（docs-verdicts 拍板入账 / audit-354-consumers / verify-b17-stats /
  verify-b18-cred / verify-b1920-new）：17 条判定 + 6 条置顶实弹（821 首张码 / 120 低电 / 601 月尾 / 235 提示遮挡 /
  统计双重开窗 / 注释越界族）—— 修复并入批19/20，无遗留。
- `d63a529` = 批21（全量语法级扫描 9 处编译阻断修复 + 第 26 道闸门 `tools/swiftsyn.js`，14 文件）：
  B 档 38 条复核完（坐实无条件可动项）后换问法"全绿与能编译之间还差什么"——tree-sitter 扫 79 个 Swift
  文件报 46 ERROR + 3 MISSING，逐条用编译器源码（ParseStmt.cpp:2489 / ParseExpr.cpp:1189,3445）与
  probe 复现分类，**9 处是真语法错误**：for-in where 逗号 ×3（AuditChain:448 / CredentialOrg:806 /
  DiagKit:238）、带标签尾随闭包后接非花括号 ×3（RecordsView:841/845/849）、裸 `$` ×1（AuditChain:377）、
  参数缺冒号 ×1（BackupStudioKit:1462）、插值里闭包缺 `}` ×1（AlarmCenterView:211，全体闸门盲区）；
  残余 31 处全为已分类文法误报（try? await / cb?() / struct 内 #if / 序列尾随闭包 / #if 成员）。
  新闸门 swiftsyn：S1-S4 判失败 + fixtures/swiftsyn 正反控 + `--selftest`；**HEAD 旧码探针 8/8 全抓**
  （第 9 处不属四类，工具头注明写边界）。CI 加步骤；详见 `docs/AUDIT-CODE.md` §10.52。
- `1fbbe75` = 验收单补批21 真机项（9 处语法阻断修复站点的行为恢复六验 ㉑ a-f，纯文档）。
- `6759496` = 批22（限定名存在性全仓扫描抓出 2 处编译阻断并修复，4 文件）：
  接 §10.52 结尾"限定名类只能等 CI"—— 用 tree-sitter 仓外工具（`D:\aapk\_swiftparse\qualref.js`）
  把"有实体声明类型"的成员存在性做成全仓扫描，净化梯度 7170（属性成员全丢）→ 32（框架混合类型）
  → 2（真实命中）→ 修复后 **0**；2 处真错：`DiagnosticsView:990` `LockStats.displayName` →
  `LockArchive.displayName`、`ExportCenter:620` `LockStats.meta` → `LockArchive.meta`（同行 2 次）——
  均属 A1 限定名类第 10、11 处，修复前整仓编译必红、对应行为从未存在过。**不加常驻闸门**
  （判据靠 tree-sitter 非零依赖，同批21 口径：一次性取证 + 工具留仓外可复跑）；含三次自我证伪
  （两条扫描器缺陷 + 一处批史归因未过正控已改写），详见 `docs/AUDIT-CODE.md` §10.53。
- `2aa3e16` = 批23（调用参数标签全仓核对抓出 2 处编译阻断并修复，4 文件）：
  仓外 tree-sitter 工具 `D:\aapk\_swiftparse\callcheck.js` 核对全仓调用侧标签顺序/未知标签/缺必需/
  缺省跳过/变参/尾随闭包，净化梯度 447（初版）→ 12（顶层类型限注/遮蔽保护/memberwise 不可信传播/
  尾随闭包软化）→ 2（注释、下标、嵌套类型构造 `Outer.Name` 键）→ 修复后 **0**；
  2 处真错同为 `LedgerPwd` 缺必需参数 `note:`（非可选、无缺省、全仓无自定义 init ⇒ memberwise 必传）：
  `CredentialOrg.swift:579` 批量延期入队载荷补 `note: p.note`、`CredentialCenterView.swift:416`
  历史页标题回退占位补 `note: ""` —— 修复前整仓编译必红。判据四次实证含一次回归自证
  （首版按 `type === 'comment'` 跳过，正控补的 `/* */` 夹参用例立刻暴露白名单必要性）；
  正控 probe_repo2 19 条 10/10 全抓 0 误报。**不加常驻闸门**（同批21/22 口径）；验收单补 ㉓ 两条。
  详见 `docs/AUDIT-CODE.md` §10.54。
- `059c5fd` = 批23 附带清账（2 文件）：deadscan A 档中途新现的两条零引用包装器删除
  （`CredentialOrg.groupCount` / `dueSoonCount`——批18/20 后遗留，计数均在消费点内联同源计算），
  A 档回到 3 条已知项。
- `e2b2016` = 批24（重声明扫描，纯文档，无源码修复）：tree-sitter 仓外工具 `D:\aapk\_swiftparse\redecl.js`
  全仓核对同作用域重复声明（类型互撞 / 同作用域名互撞 / 成员桶 / 签名键并入重载维度 / 重复遵循五类判据）
  —— **0 组真错**，本仓第一份经正控与覆盖度对账的"验证式否定"；判据形状探针实证 5 条（`#if` 为平铺
  directive 兄弟 / 类型体内 `#if` 致损与 DiagnosticsView 反例 / MISSING 为未命名子节点 / 参数与缺省值
  形状 / 继承与 modifiers 形状）；正控 `probe_repo2` 10 BAD 全抓 + 9 OK 零误报 + R2 结构致损排除；
  `dup_groups=0`、`overloadedNames=8`（BPLE 回调 ×4/×5、HexKit.hex ×2 已核合法 —— 见证机制看见重载
  并放行）；覆盖度对账 584 vs 585 差 1 = DebugBreak 整文件 `#if DEBUG` 保守跳过。详见 `docs/AUDIT-CODE.md` §10.55。
- `eaf7dfd` = 批25（try/await 覆盖扫描，纯文档，无源码修复）：tree-sitter 仓外工具 `D:\aapk\_swiftparse\tryawait.js`
  全仓核对"调 throws 缺 try / 调 async 缺 await"（编译必拒）—— **0 处**，本仓第二份"验证式否定"
  （证据门槛同批24）；判据形状探针实证 6 条（包装节点 `namedChild(0)` / 尾随闭包 hoist 四变体 /
  if 体吸附 / async let 首子 token / `_ =` 不触发 hoist / **node-tree-sitter 包装对象 `===` 不可靠**
  —— hoist 摘回初版因此静默失效，一度出现"探针复刻触发、主工具不触发"的分裂假象，定式一律按 `.id` 比）；
  正控 `probe_repo3` BAD1-15 全抓 + GOK1-26 零误报；精度闸收敛 7→2→0（真仓 7 处命中全为末段名撞库 FP：
  NSLock.unlock / Combine.send / CBCentralManager.connect / UNUserNotificationCenter.requestAuthorization，
  varTypes 按文件分组后归零）；对账恒等式 `resolved = skips + checked` 两仓自洽；13 条跳过见证逐条审计；
  hoist×2（`LockService.swift:348` / `BackupStudio.swift:2203`）修复后转 positive 人工核实。详见 `docs/AUDIT-CODE.md` §10.56。

- `2aa0f5f` = 四项拍板落地（13 文件，见 §4 A5）：**D-36** 全量备份包新增 `globals.deviceOrg`
  （顺序 / 分组 / 分组折叠 / 隐藏；typed + 四项全可选 + 缺字段=不动本机 + 落地逐项白名单；
  进 canonical 校验和；**刻意不升 schema** —— bundle.js 的 `schema > SCHEMA_VERSION` 闸会把 v6 整包拒收）；
  **D-137** ZOTP 参数名保留并在两份 vendor 副本补历史原因注释；
  **D-150a** 829 失败面改「常驻横幅 + 直达症状树」，页内硬编码三行删除；
  **D-152a** 两处「删除成员」弹窗改三按钮（只移除档案 / 连锁端一起收回），
  `cascadeBinMember(revokeLocks:)` 走 629/353 同一条队列。真机项 ㉔/㉕/㉖；闸门 26/26 rc=0；
  本批**同样不含编译器证据**。

### 1b. 隔离工作树 / 只读工单代理：已全部回收（2026-10-11 枝干已物理清理）

- **本地只剩 `main` 一个分支**（现场：`git branch` 仅 main；`git worktree list` 仅主目录；
  `ls .qoder/worktrees` 为空；`git stash list` 为空）。
- 10 个 agent 工作树与对应分支已全部移除。删前逐支验证：6 个等价补丁已合入 main
  （`git cherry main <branch>` 全 `-`）、3 个已完全合入（`main..branch` 为空）、
  2 个例外头留 tag 保险：`stale-backup-history-42`（→ 42bd014）、`stale-a965b67`（→ a965b67，
  即 HANDOFF §6 已认定"作废、不可合"的那条）。
- 清理前 4 个脏工作树的未提交残留已导出到 `state/stale-worktrees-20261011/*.patch`
  （三份非空；`599808c0` 是空 diff = 时间戳假改动），需要时可从 patch 找回。

| 工作树 | 状态 | 内容 |
|---|---|---|
| `.qoder/worktrees/agent-general-purpose-2bbd6998` | 已合（a635d52），已清理 | 换机迁移 438-446 |
| 只读工单代理（FAKE / PART-a / PART-b） | 全部完成 | 产出在 `state/workorders/`（FAKE.md / PART-a.md / PART-b.md / 376.md） |

合并办法（已照做）：
```bash
git cherry-pick -x <该分支头/该提交>
for t in swiftcheck swiftlint swiftshape featuremap keydead deadscan delsweep lockpair changelogcheck bundleshadow; do node tools/$t.js >/dev/null 2>&1; echo "$t=$?"; done
git --no-pager diff --stat HEAD~1 | cat     # 逐行读 diff 是本仓铁律
```
迁移件只碰 `BackupStudio.swift` / `BackupStudioKit.swift`，与上面几批文件不相交（已核对）。

---

## 2. 这台机器的验证天花板（每一句"全绿"都必须带上这句）

- **没有 Xcode / 模拟器 / swift / swiftc / xcodebuild / docker**。只有 `tools/` 下 **26 个 node 脚本**
  （25→26 = 批21 的 `swiftsyn`，语法级四类；**类型级仍无闸门** —— 见下行）。
- **XCTest 从未执行过一次**；CI 只 `build-for-testing`，且**自 run 43 (2026-10-07) 之后连红**，本会话所有新写的 Swift **同样一行没进过编译器**。 ⇒ 今天要有能装的成品，唯一路径是**推一次让 `build-for-testing` 打类型错误**。要不要推需要用户点头（用户本日已拍板：**暂不推**）。
- 闸门里**没有任何一道**能判"限定名对不对得上声明它的类型"（批21 的 swiftsyn 是语法级，不管类型；
  批22 的 `qualref.js` 是仓外一次性扫描、非常驻闸门）。本会话人读出来的四处编译器必拒属这一类
  （见 §4 A1，已修）；批22 又扫出同类两处（`LockStats.displayName/meta`，已修，扫后全仓 0 处）；
  批23 再扫"调用参数标签"类两处（`LedgerPwd` 缺 `note:`，已修，扫后全仓 0 处）；
  批24 再扫"同作用域重复声明"类 —— **0 组**（验证式否定，证据门槛见 §10.55 文末）；
  批25 再扫"调 throws 缺 try / 调 async 缺 await"类 —— **0 处**（验证式否定，证据门槛见 §10.56 文末）。
- 一键复算（全应退 0；2026-10-11 17:25 实跑 26/26 rc=0，本批 `2aa0f5f` 13 文件落地后）：
```bash
for f in tools/*.js; do node --check "$f"; done
fail=0; for f in tools/*.js; do case "$f" in tools/golden.js) a=--check;; *) a=;; esac; node "$f" $a >/dev/null 2>&1 || { echo "FAIL $f"; fail=1; }; done; echo $fail
```
⚠ `node tools/golden.js` **必须带 `--check`**：裸跑会重写 `fixtures/golden.json`。
⚠ 循环里一个 `for ... && echo PASS` 只给最后一个的 exit code，必须像上面那样逐脚本收 rc。

---

## 3. 台账现状（唯一权威 = `node tools/featuremap.js` 现场输出，别手工数）

- 07:38 现场：**实现证据 949 条 (948 代码标注 + 1 仅台账 file:line) / 1050**（批22 未动标注，数字不变）；
  **F 档"有标注"仍为 0**（A2 目标保持）；
  D 档 0（台账与代码不打架）；A0-t 本轮施工面 0 条；A0-x「不要重做」24 条（拍板后六条新进：276/278/297/416/447/990）、
  A0-w 9 条（15/32/34/35/40/48/595/643/826 —— 真编译/真机条件不在本机）。
- 另有**独立判定表**（不依赖 featuremap）：`node state/mx_agg.js` → 已判 844 条：
  **REAL 430 · PART 338 · FAKE 64 · NOC 11 · DEAD 2**，另有 48+ 处"界面文案承诺代码没有的能力"。
  结论：**真做到位的约 482/934**（历史快照），原始判定行号在 `state/verdict/batchNN.tsv`。
- 判定表缺 `batch16.tsv`（派发的那个只读代理可能已停/未落盘）。补跑：
  `state/brief/batch16.md` → 判 REAL/PART/FAKE/DEAD/NOC 写 `state/verdict/batch16.tsv`（6 列，见 §7 的口径）。
- `node tools/deadscan.js` 08:03 现场：A 档（确证零引用）3 条，都与本次无关：
  `LinkSense.stopReconnectLoop` / `LinkSense.stopDeadWatch` / `ExportItem.linkMetadata`；B 档 1 条 `DS.slow`。
  批23 清掉中途新现的两条（`CredentialOrg.groupCount` / `dueSoonCount`，059c5fd）；
  376 接线后 `SecurityPolicy.halfMasked` 已从 A 档消失；`guardedPurge` 已从 A 档消失（接线在 aa94d02）。
- featuremap 自带 **15 条常驻分档断言**（含反控 #299 必须"已落"；2026-10-11 拍板后重钉：235→改判要做，276/278/297/416/447/990→舍弃）。
  改 DEFERRED 措辞别把这 15 条碰翻 —— 本会话已碰翻过一次（措辞一改六条先红），修复 = 台账措辞与断言表同步改到同一个现实。

---

## 4. 队列

### A1 编译器必拒 — **已全部闭环（aa94d02；批22 追加同类两处）**
- 已修：`r.minH`→`minHour`（StatsView）；9 处 `RecordSearch.oid`→`RecordOverlay.oid`；
  `LinkSense.WakeReason`→已在用的 `LinkSense.FailKind`；裸 `CustomAccent`→`DS.CustomAccent`；
  两处不存在的 `Dictionary(uniqueKeysAndValues:)` 初始化器 —— 凭证族那批。
- 批22 追加（限定名类第 10、11 处，全仓扫描所得）：`DiagnosticsView:990` `LockStats.displayName`→
  `LockArchive.displayName`、`ExportCenter:620` `LockStats.meta`→`LockArchive.meta`（同行 2 次）。
- 批23 追加（调用参数标签类，全仓扫描所得）：`CredentialOrg.swift:579` / `CredentialCenterView.swift:416`
  两处 `LedgerPwd(...)` 缺必需参数 `note:`（memberwise 必传），分别补 `note: p.note` / `note: ""`。
- 批24 再核"同作用域重复声明"类：**0 组**（扫描覆盖五类判据，正控与覆盖度对账见 §10.55）——该类
  当前无待修项。
- 批25 再核"调 throws 缺 try / 调 async 缺 await"类：**0 处**（正控 BAD1-15 全抓 / GOK1-26 零误报 /
  13 条跳过见证逐条审计，见 §10.56）——该类当前无待修项。
- `CredentialCenterView.swift` 两条彻底删除路径（单条左滑 + `purgeAll()`）都改走
  `CredentialOrg.guardedPurge(_:ids:reason:onDeniedPresentFallback:)`（:296 / :333），
  `deadscan` A 档已不再报它。注意 `CredentialsView.swift` 里"彻底删除 (670)"那两枚是**活凭证**删除汇点
  （`DB.delPwd/delFp` + `addToBin`），不是回收站 purge（本会话已按此处理且提交）。
- **可疑，别凭记忆改**：`CredentialStudio.swift` 的 `DataScannerView { session in session.supportedDataTypes = [.qr, .dataMatrix] } results:` ——
  Apple 文档 JSON 撞不到（404）、VisionKit 模块页成员清单里没有任何 Scanner 符号、公开检索只指向 UIKit 的
  `DataScannerViewController`。已记进 `docs/API-VERIFY.md` 末行：**等 CI 的 `error:` 定位，不要猜改**。522 与 411 都走它。

### A2 台账措辞 — **已完成（aa94d02）**
- `DiagKit.swift` / `ExportCenter.swift` 头部措辞已换含 `已删`/`未做` 的说法（featuremap 跳词表在 `tools/featuremap.js:145`）。
- 复算命：`node tools/featuremap.js | grep '^【F'` ⇒ 有标注 0（03:30 现场）。

### A3 各族落地后剩下的消费点 — **已完成（1f15ec2，九文件）**
- 902 `resetAppearance()` 补 `DB.store.remove("kf_digit_font")`（并改写"做过又撤掉"的过时注释 —— 键其实在役，圈定 MetricTile/HeroStat）。
- 331 列表侧：`CredentialOrg.listCountdown(_:_:_:)` 新增，`CredentialsView` 行状态胶囊「提前失效」+ 副行读数 + 播报三处同帧同判据。
- 469 `SecurityCenterView.rescueCustodyLine` 读 `MemberHub.emergencyAdmins()`（空名单指路点名，不装没事）。
- 468 `batchTransfer` 快照按**改动前**属主补「管理员代操作 (468)」；批量停用便签按条拆分（`CredentialCenterView:1179+`）。
- 486 `TempCodeStudio.doneCard` 读 `MemberHub.elderMode`：完成页收成 口述卡 + 大「完成」，329/333/再发一张 收起并在原地说明。
- 779 `LockOverviewView` 矩阵格 n>0 变按钮（`pendingRecordsFilter` + 记录页，与"看最高格"同路）。
- 798 早已改真堆叠（`db304f7`）。
- 235 已落地（批20，面容落键盘）、276/278/297/416/447/990 已判 ❌ 定案（2026-10-11）—— 原先"等拍板"那档清空；
  554/559/826/829/904/595/643 等仍在"等真机 / 已合并 / 观感窗口"档，别当施工面。

### A4 未做完的大件 — **迁移已合（a635d52）；工单已产出，A 类全闭，B 类在身**

- **换机迁移 438-446**：已从 `2bbd6998` cherry-pick 为 `a635d52`（三通道真分流、439 真进度、445 真事务、
  440 真增量补传与分区对账、441 restore 入参、419 逐条裁决、411 扫码接收侧）。DataScannerView 那套写法
  留待 CI 编译复核（口径见 `docs/API-VERIFY.md` 与 `e078b33` 的"禁止凭记忆重写"记录）。
- 工单已落盘：`state/workorders/FAKE.md`（A3 三条已闭：942/861 落文案、440 复核为迁移真实现）、
  `PART-a.md`（A 类 22 条已闭 = `94ead63`）、`PART-b.md`（A 类 17 条已闭 = `a4b9826`）。
- **剩余主战场 = 两份工单的 B 类**（PART-b 142 条已落 50 = `6244135` 六条 + `82d1f2d` 五条 + `a8bc4b4` 五条 + `ec10e6f` 五条 + `8c09c5b` 四条 + `9c49ccb` 三条 + `bc16cf0` 四条 + `dda5647` 三条 + `27ecd33` 五条 + `4835970` 五条 + `b019b3b` 五条；另有 917 复核为 DEFERRED 已拍板 / PART-a 110 条）+ C 类待拍板表；
  FAKE 12 条已全闭（10 条落 = `3d9e661`，419/446 复核为迁移真实现）；
  挑的时候先看 `docs/FEATURE-TRIAGE.md` 判定格里有没有"替代已接线 @file:行" —— 有就是已拍板的替代口径，不是漏做。

---

### A5 四项拍板（2026-10-11 第二轮拍板，用户逐条点选）— **已全部落地（`2aa0f5f`）**

- **D-36 同意进包**：`globals.deviceOrg` = 顺序 / 分组 / 分组折叠 / 隐藏（typed、四项全可选、缺字段=不动本机、
  落地逐项白名单）；进 canonical 校验和（内层字母序、groups 按 mac 排、顶层在 appearance 与 gatewayList 之间）。
  **没有升 schema，这是有意的**：小程序端仍是 v5，`bundle.js` 的 `schema > SCHEMA_VERSION` 会让它整包拒收；
  而 globals 可选增量段没有键位迁移要做（与 894 appearance 同先例）。两处旧文案与 LockStats 头注释已同步改口。
- **D-137 保留现名**：`periodSec` 不改名，vendor 两份副本（`vendor/app/utils/zotp.js` 与
  `miniprogram-app/utils/zotp.js`，逐字一致）补「单位是分钟 + 为什么保留」。
- **D-150a 方案①**：829 = 页内常驻横幅 + 「看三步排查」直达 `SymptomGuideView(initial: "bleConnect")`；
  原先抄在扫描页里的三行删除（单一来源仍是 `DiagKit.SymptomGuide.bleConnect`）。
- **D-152a 方案③**：两处「删除成员」弹窗当场选「只移除档案 / 连锁端一起收回」（默认第一项）；
  `CredentialOrg.cascadeBinMember(_:_:revokeLocks:)` 返回排入条数，走 629/353 同一条 365 队列；
  指纹不可远程补录的代价写在同一屏。

### A6b B 类复核第二片 + A 类复核 — **已知 19+4 闭 · 真正开放的只剩 592/598**

- **A 类（PART-b 优先表 20 条）复核完毕**：**19 已闭 + 1 待提问**（612 的「status 快照」措辞过时，
  实为 Attribution 直读 readStatus，不另存快照）。证据 = `state/recon/A-class-workorder-recheck.md`
  （逐条 file:line）。**照工单开工 = 全部白做 —— 工单 A 类别再当施工面。**
- **batch02 抽检 4 条（173/305/522/519）全部确证已闭**（不是只看标注）：抽检报告 =
  `state/recon/B-class-recheck2.md`。522 有一个已知编译风险挂 docs/API-VERIFY.md。
- **785 泳道**：判定改「已闭（简化案）」—— laneView 日级对齐 + 告警行红底 + 读屏齐；「点格子跳当天」
  那半刻意不搬（585 已有同一条路）。
- **749 对账**：判定改「降级备档」—— 会话内三支结论（拉全/未拉全/不可判）+ reconLine 可复制，
  比原句"逐段核对"更硬；别照原句再造一套。
- **598 已按「让那排 UI 真工作」落地**（第一百七十八批）：`shownCap` 写死 1200 改为**池量分档**
  （`RecordsView.swift:61/2886-2890`：池 ≤600 全显，>600 先显 600、每按「继续加载」+600）。
  原判据在 300 条级数据层上永远不触发 —— 截断排是死 UI 等于把 598 虚报成"做了"。**单锁 300 条
  缓存上限本身没动**：那是另一件数据层改造（锁端真分页），且 654（去年今日）也备档等它，不夹带。
- **1016 结案**（第一百七十八批复核）：出行日期段入口已在 —— `markTravel` 写 dayKey（`RecordsView.swift:1123`）、
  横幅上「标记出行」按钮 + confirmationDialog 三档时长（7/14/30 天）、出行中随时点 × 结束（:1164）。
  到此 **batch01 全表无开放项**；B 类复核的真开放面收敛为「PART-a batch03–11 / PART-b batch13–22 的
  未复核条目」，方法仍是先筛后读。`592` 更正为**已闭**——当前折叠键本来就带凭证维度（credKey）+ 同一分钟窗口
  （`RecordsView.swift:2550-2577`），首片引的是更早的旧口径；917 照旧不折行（拍板已定）。
- **工作树自愈记录**：本轮一次误写把首片报告覆盖成了补丁脚本，已当场还原（顺带确认 `state/` 整目录
  在 .gitignore 里，这类事故不影响版本库，但复核产物只有本地一份 —— 重要的判定结论都已抄进本文件）。

- **B 类 110 条全量机器筛跑完**（PART-a batch02–11 全部 id）：**零标注 0 条**，抽检 25 条实读改判 ——
  真缺半件只剩 **522 的 `.text` 识别类型**（连同 411 共用 DataScannerView，挂 docs/API-VERIFY
  「不许凭记忆改」门禁，等 CI error 定位）；其余全部已闭 / 诚实降级 / 判不做。
  全表 = `state/recon/PARTa-Brecheck-full.md`。**加上此前 PART-b 的 A 类 19 条 + B 类抽检：
  两份工单的可本地施工面, 到本轮为止已经清完。**
- **C 类 31 条复核完毕**（`state/recon/PARTa-Crecheck.md`）：**无一漏做** —— 16 条已随后续拍板
  落地或半闭（137/18·187/325/335/342/347/356/504/599·634/615·619/639/678/81/973 等），
  15 条是协议无字段 / 无数据源 / 拍板冲突层面的**真 X**，文档与代码注释双方认账。
- **PART-a A 类 18 条复核完毕**：**18/18 已闭**（16 分钟级文案 / 735 角标 / 712 预览 / 795 排归档 /
  351 分享 / 262 与 175 同判 / 761 idxRaw / 693 锁名文件名 / 460 展示层过滤 / 444 打勾 / 433 按名排序 /
  63 dBm 展开 / 261 名下清单 / 471 advice 卡 / 185·597 双向左滑 / 812 直开表单 / 474 处置向导）。
  证据 = `state/recon/PARTa-batch03-recheck.md`。**两份工单的 A 类均已整体过时，别照着开工**。

### A7 ❌ 替代两族落地 — **本轮落了六条（第一百七十六批）**

- 依据 = `docs/DECISION-NEEDED.md` 的「⏳ 替代仍未建」清单（拍板口径早已是"按替代落地"）。
  挑法沿用 A6 的**先筛后读**：`node state/bcheck.js <id>` 命中 0 标注的才动手（有标注的先读码再决定）。
- 落地：**926/930** 到期提醒三档→五档 + 新增「到期时」通知 + 凭证 Tab 角标（`CredentialOrg.swift:775`,
  `LockKeeperApp.swift:923`）· **935** 时间线顶部「今日概要」行（`RecordsView.swift:1080`）·
  **744** 告警中心科普折叠段（`AlarmCenterView.swift:122`）· **286** 蓝牙广播静态科普进帮助手册
  （`HelpCenter.swift:140`）· **6** 复核为已由 39 承担, 只改判定行。
  另 **924/925/928/929/931** 复核为已由 943 / 975 / 1041+1004 / 锁切换纵览承担, 判定行改口、不写代码。
- 一处**得说明的口径变更**：原 359 把 2 小时档做成"只插列表提醒行、不排通知"，详情页卡片上写着这句话；
  926/930 的替代栏原话是"到期前 2 小时与到期时各发本地通知"，本轮按替代执行 —— 排程扩到六条
  （d7/d3/d1/h24/h2/t0），列表提醒行**保留**。两处界面文案已同步改口。
- **数据格式只动了 `CredAlert`**：新增 d3/d1 两个开关位，并补显式 `init(from:)`（老包缺键 = 该档关），
  避免合成解码器遇缺键抛错后被 `?? CredAlert()` 吞成"三档全关"。**没动备份包 schema**。
- 第一百七十七批（同日）接着落了协议族三条：**596** 记录页组头红字「含防撬/试错」(判据 = 防撬 7 /
  试错锁定 10 / 键盘锁定 224，看"这一天出过事"而不是"有没有人处置过") · **607** 趋势图给防撬/低电量
  告警日打三角符号 (点按复用 638 读点气泡) · **541** 下发前如实提示"本机台账里上次成功下发于 X"
  (365 队列派生，文案明写不是锁端真值)。**175** 复核为已由 529 段尾统计承担，其中"闲置三月置灰"那半
  明确判不做（按录入时间灰显会把天天在用的指纹标成闲置）。
- 仍然未建：**725**（高危告警全屏确认卡 —— 失败面形状的改动，动之前要定它何时弹、弹几次）；
  **938/944** 卡在 ControlWidget 写法（DEFERRED，等首次编译 + 真机）。
- 天花板照旧：`node tools/*.js` 26/26 rc=0（`golden --check` 无漂移），但**整仓仍未过编译器**，
  本轮全部 UI 改动同样没有编译证据 —— 真机观感仍只有你能定。

## 5. 已经落进 main 的东西（一句话一条，细节在 `docs/AUDIT-CODE.md` §10.50/§10.51/§10.52/§10.53/§10.54/§10.55/§10.56）

- 186 批（批25）：try/await 覆盖扫描（仓外 tree-sitter，`tryawait.js`）—— **0 处**，本仓第二份"验证式否定"
  （证据门槛 = 判据形状探针实证 6 条 + 正控 15 BAD 全抓 + 26 GOK 零误报 + 对账恒等式 `resolved = skips + checked`
  + 13 条跳过见证逐条审计 + hoist×2 转 positive 人工核实）；新定式：**tree-sitter Node 一律按 `.id` 比，禁用
  `===`**（node-tree-sitter 包装对象身份不稳定，本批踩坑实证）；**不加常驻闸门**（同批21-24 口径，一次性取证）。
  见 §1a 与 §10.56。

- 185 批（批24）：重声明扫描（仓外 tree-sitter，`redecl.js`）—— **0 组真错**，本仓第一份"验证式否定"
  （证据门槛 = 判据形状探针实证 5 条 + 正控 10/10 + 覆盖度独立计数对账 + 合法重载见证）；`dup_groups=0`、
  `overloadedNames=8`；**不加常驻闸门**（同批21/22/23 口径，一次性取证）；盲区已定性（`CredentialStudio.swift:2595`
  提升成因 = 2581 行 for-in 序列尾随闭包，批21 已定性的文法误报类）。见 §1a 与 §10.55。

- 184 批（批23）：调用参数标签全仓核对（仓外 tree-sitter，`callcheck.js`）抓出 **2 处编译阻断**修复
  （`LedgerPwd` 缺必需参数 `note:` ×2）；净化梯度 447→12→2→0 可复算；正控 probe_repo2 19 条 10/10；
  **不加常驻闸门**（同批21/22 口径，一次性取证）；判据四次实证含一次回归自证；见 §1a 与 §10.54。
  附带清账：deadscan A 档两条零引用包装器删除（059c5fd）。

- 183 批（批22）：限定名存在性全仓扫描（仓外 tree-sitter，`qualref.js`）抓出 **2 处编译阻断**并修复
  （`LockStats.displayName/meta` → `LockArchive.*`）；净化梯度 7170→32→2→0 可复算；**不加常驻闸门**
  （同批21 口径，一次性取证）；见 §1a 与 §10.53。
- 182 批：全量语法级扫描（仓外 tree-sitter，79 文件 46 ERROR + 3 MISSING）抓出 **9 处编译阻断**并修复
  （for-in where 逗号 ×3 / 带标签尾随闭包后非花括号 ×3 / 裸 `$` ×1 / 参数缺冒号 ×1 / 插值括号 ×1）；
  新增第 26 道闸门 `tools/swiftsyn.js`（S1-S4 判失败，fixtures 正反控，`--selftest`，HEAD 旧码探针 8/8）——
  此前"闸门全绿仍可能编译不过"的语法级缺口被堵上；残余 31 处经 probe + 编译器源码分类全为文法误报。
- 178 批：读码判 599 条；修 4 处编译器必拒；**备份包 checksum 改回与小程序同语义** + 新增第 25 道闸门
  `tools/bundleshadow.js` + `fixtures/canonical.json`（18 条向量烘自真 JS，四道正控开火，反控=旧语义只中 3/18）；
  复原三份被吃掉换行的台账。
- 179 批：690 导出列选择修成真生效；42/268 假长按提示改指真热区；告警中心"拖动"改"点选"；55 轻点背面文案对齐 `UnlockIntent` 真行为。
- 181-190 批：设计系统族（`bd8b370`）、记录族（`32016fe`）、统计族（`be66c9c`/`e0d6345`）、凭证列表+成员族（`108cca5`）
  合并进来；另落 539 时段真分桶、229 左手模式接消费者、156 补真开关、842 补唯一写点、576 换锁重取、
  798 真堆叠、774 场所进报告、722 校验行画进 PDF、137 写明门磁做不了、`NSFaceIDUsageDescription`（缺它四处面容弹窗弹不出来）、
  582 收成一条路由、642 删恒真空壳。
- `8fe3da7`/`d3aae50`：包5/6 八条口径重做 + 凭证工坊族合入 + 交接书对齐。
- `aa94d02`：安全族接线合批 —— 377 访客通道真收起两页、383 销毁 sudo 门槛、296 只读闸、502 彻底删除统一 `guardedPurge`
  （含 A1 两条清理路径接线、A2 措辞使 F 档归零）。
- `1f15ec2`：A3 消费点合批 —— 376 半遮默认遮码卡（revealed 状态，复制/分享跟随）、486 长辈完成页口述卡、
  331 列表提前尺（胶囊+副行+播报）、469 救援码保管人声明、468 批量代管补记、779 矩阵格可点、902 重置补键。
- `a4b9826`：PART-b A 类 17 条（369 三档遮码 / 391 胁迫参数 / 612 状态快照 / 388 敏感台账 / 373 剪贴板自清 /
  375 玻璃按压 / 378 访客水印 / 754 参考项手动勾 / 845 空态生成器 / 543 诊断跳凭证 / 385 启动清过期 / 1043/1022/1023/164/245）。
- `a635d52` + `45a11c3`：换机迁移 438-446 合入；备份文件名加时分（194/409/387 同族收口）。
- `94ead63`：PART-a A 类 22 条（460 归档成员挡展示 / 262 久未用压暗 / 261 凭证清单 / 474 移交接选择 /
  761 行身份 / 63 dBm / 812 虚线格直开表单 / 471 过期码真停用 / 185+597 备注标旗滑出 / 815 空态两出路 /
  274 免扰静默 / 16 摘要分档 / 735 Tab 角标 / 712 CSV 预览 / 693 文件名带锁名 / 795+817 成员示例位 / 351 分享面板）。
- `3d9e661`：FAKE B 类 10 条（964 审计 intent· 来源图标 / 269 就绪轻震 / 517 粘贴条立即清除 /
  55 轻点背面分步指引 / 212 三处列表交错入场 / 636 捏合缩放窗口 / 11 复制按钮形变 /
  14 月度热力格 / 23 HeroCard 滚动视差 / 995 入伙欢迎卡 + 「入伙」徽章）。
- `6244135`：PART-b B 类首批六条（259 新成员建档色板 / 822 建议备份时间读 kf_bk_cadence /
  665 导出页眉走 TimeFormat.range / 781 全库同名锁扫描 / 109 删锁预告记录条数 / 650 时间来源色点）。
- `82d1f2d`：PART-b B 类第二批五条（400 kf_backup_hist 毫秒→秒换算, 销毁闸/752 提醒/日期显示三处同修 /
  223 启动自动归档开关 kf_diag_autoarchive + onLaunch 接线 / 666 未命名成员按名册序号兜底「成员 N」/
  44 ChangeBatchView 按原文页面名给真切 Tab 按钮 / 480 MemberAvatar 加 tint, 关怀卡+生日卡用成员建档色）。
- `a8bc4b4`：PART-b B 类第三批五条（128 coldStartScan 等满扫描窗测「首台可见耗时」kf_link_envms /
  782 StatsKit.isIdleLock 统一闲置判据 + 统计页「排除闲置锁」开关 / 758 启动发现异常退出档案弹一次性卡 +
  对照表页档案全文导出 / 159 指令流水行可点进对照表高亮 rc 行 / 147 DFURecord 可选 ms 字段记升级耗时）。
- `ec10e6f`：PART-b B 类第四批五条（105 记录行锁名标签挂档案符号+色标 / 45 电量采样 Canvas sparkline +
  点数·跨度·最低最高行 / 658 两处小时图轴标改 8 时段词+面包屑+下钻标题+两处峰值行 / 587 新增 AppState.pendingDiag,
  设置 Tab 切锁后 sheet 推诊断页（设置搜索同路由）/ 987 非隐藏未达成徽章详情加「还差一点点」悬念行）。
- `8c09c5b`：PART-b B 类第五批四条（726 ExportRecord 增 key + 月度报告纯文本段/PDF 章「处置历史 (本机留痕)」+
  告警行内联结论 + 717 告警一页纸逐条标注（此前导出侧零引用 dispositions）/
  737 trialRowsToday 唯一判据 + trialEventsToday 逐次事件（最多列 5 条）+ trialCard 键盘冻结行 +
  涉事凭证明写「锁定级日志无槽位 ⇒ 无法归属」（RecordsTimeline 同口径一行）/
  743 告警行 swipeActions 已处理/误报（与行内胶囊同一 markDone 落点）+ 未处理清零判「已全部处置」收尾 /
  745 testMarkedKeys 移入 RecordSearch 核心，StatsKit.build 入口 + LockStats.usage 同口径过滤，测试标记真排除统计）。
- `9c49ccb`：PART-b B 类第六批三条（609 TempGantt.ticks 改存全时刻 [Date]，甘特圆点按真实位置定位（替掉硬编码
  w*0.5 叠堆）；629 过期侧也给核销率 + 每行 4pt 核销比率条；625 成员色子段下挂「色点+名字+约 N 次」图例）。
- `bc16cf0`：PART-b B 类第七批四条（844 演练冷却倒计时界面；1038 升级提醒白天补送 + 固件提醒 30 天复提醒；
  550 承诺页明写 WebDAV 自配通道；905 长按快捷格进编辑面板）。
- `dda5647`：PART-b B 类第八批三条（768 待维护行直达该锁告警流（lockMac 单锁形态）；778 告警偏高
  上浮 + 行内标签 + 行可点下钻；769 设备管理「绑定于 …」小字 + 按添加时间排序）。
- `27ecd33`：PART-b B 类第九批五条 + 顺带口径修复（1011 满年徽章同判据 companionFullYear；151 体检面容项
  补系统设置录入指引 + 本地网络如实脚注；955 成员意图带今日门次（startOfDay 起算约级）；162 握手在别 Tab
  完成 → 设备 Tab ✓ 角标；226 降透明 hero 面退纯色 + 描边（HeroSurface.resolve 覆盖 12 消费点）；
  体检总分收进 DiagHealth.percent 修掉 /100 假数）。
- `4835970`：PART-b B 类第十批五条（952 意图冷却按意图分键全族接入；953 审计流水「快捷指令执行」
  独立分区；676 统计深夜轴读「夜间时段」配置、每小时只进一轴；594 记录组头日型色带 4pt 每天出现
  （工作日靛蓝/周末青绿/节假日橙，补班日按工作日）；158 体检历次分数回看（差值只与上一次比））。
- `b019b3b`：PART-b B 类第十一批五条（392 面容失败/中断回调与「方式」留痕；449 信封全键魔数 +
  声明长度校验；224 启动预热并行；751 保留策略将删条数二次确认 + 立即裁剪；206 圆盘外沿磨砂环）。
- `f314d63`：第十二批＝只读侦察补丁单收回后串行应用（452 隔离停放 / 760 备份可读 / 574 槽位备注 /
  50 年报季度 / 945 意图面容门槛 / 947 临时码周期管道 / 799 周小结 / 801 直达添加 / 811 真探测 /
  838 30 秒预习 / 1013 保养通知落点 等 24 处，详见 §1a）。
- 另有 6 名**只读侦察子代理**在后台分区核对 PART-b 剩余 B/C 类条目（batch12-22 全量），
  产出「已闭证据 / 最小补丁单」；补丁由主代理串行应用，子代理不写任何文件。
- 验收单 `docs/VERIFY-CHECKLIST.md` 末尾按批追加真机项（①-⑫ 起，后经批17-20、批21 ㉑、批22 ㉒、批23 ㉓ 续补），
  **发布前该照着走一遍的是那一份**（批22 新增 ㉒：诊断页设备清单真锁名 + 导出封面场所副标题；
  批23 新增 ㉓：批量延期真入队 + 历史页回退标题）。

---

## 6. 动手规矩（本会话又踩出来/证实的，违反就要返工）

- **并行代理必须先自检基线**：`.qoder/worktrees/` 里的副本有 3 个停在 `31df7a6`（落后 97 个提交、`tools/` 只有 4 个脚本）。
  在过期副本上做出来的 `a965b67` 已作废、不可合。派活动作里写死：
  `git merge --ff-only main` + 自检 `git log --oneline -1` 与 `ls tools/*.js | wc -l` ≥ 25，不过就停手回报。
  （10 个陈旧工作树已于 2026-10-11 全部清理，见 §1b；此规则对将来再派代理仍适用。）
- **有代理在主工作区写的时候，绝对不要 `git add -A`**：曾把 7 个 `.qoder/worktrees/agent-*` 当嵌入仓库记进索引，
  只能再补 `git rm -r --cached .qoder` + `.gitignore` 收拾（`14636da`）。一律 `git add <自己的文件>`。
- `git commit -m` 里**不要放反引号**：会被 bash 当命令替换（`993a518` 的提交消息就被吃掉一段）。要么用 heredoc，要么用「」。
- 改完必须逐行读 `git diff`。临时探针用 Edit 精确改回，别用 `git checkout -- <file>`（会抹掉同文件其它未提交改动）。
- UI 文案禁 ASCII 双引号与 markdown 星号（swiftlint ⑤）；「更新说明」每条要带覆盖表认账的编号，没有就不写。
  本仓惯例：功能批次**不**逐条补 ChangelogView 条目（377/383/502 那批也没补，changelogcheck 通过）。
- 数字一律现场取：`featuremap` / `git rev-list --count origin/main..main` / `tr -cd '\n' < 文件 | wc -c`（判行尾要用 `tr`，Git Bash 里 `grep -c $'\r'` 会吞成空）。
- `state/` 是跑批草稿目录（`.gitignore` 已含），取证器在里面：
  `mx_ledger.js`（独立台账）→ `mx_brief.js`（切批任务单）→ `mx_agg.js`（判定汇总）；
  另有 `mx_retcheck/mx_island/mx_sym/mx_symA2/mx_typo/mx_member/mx_nestscan/mx_promise/mx_theater/mx_selfread/mx_mkfixture.js`。
  **其中 regex 型"编译器替代物"已被证明不可靠**（孤岛/成员/嵌套类型三套都产噪音，唯一命中是人读出来的）——别拿它们的 0 命中当"没问题"。
- **tree-sitter 型（真解析）是可复算的那一档**：批21 语法级（swiftsyn 已成常驻闸门）、批22 限定名存在性
  （仓外 `D:\aapk\_swiftparse\qualref.js`）、批23 调用参数标签（仓外 `D:\aapk\_swiftparse\callcheck.js`，
  正控 `probe_repo2`，复跑命令见 §10.54）、批24 重声明（仓外 `D:\aapk\_swiftparse\redecl.js`，
  同正控仓，复跑命令见 §10.55）都属它。用它的产物也要守同一条：**自己的归因同样要过正控**
  —— 批22 里"`===` 恒 false"的说法没过探针，提交前被自己证伪并改写（教训写入 §10.53）；
  批23 里"注释只需跳过 `comment` 类型"的说法被正控新用例当场证伪（`/* */` 不是 `comment`，
  改为白名单只收 `value_argument`，教训写入 §10.54）。
  批24 又实证两条形状：`#if` 是平铺 `directive` 兄弟（不是嵌套节点）、MISSING token 是**未命名**子节点
  （走 namedChildren 全漏、走 childCount 才抓到）；且"`hasError && /#if/`"整文件排除判据被
  DiagnosticsView 反例证伪，收紧为 `&& missing > 0`（教训写入 §10.55）。
  批25 再证 try/await 覆盖类（仓外 `tryawait.js`，正控 `probe_repo3`，复跑命令见 §10.56），并给
  批22 遗下的"`===` 之争"落了定论：**node-tree-sitter 包装对象同一性不稳定**（同进程内实测 `objEq=true`
  与 `objEq=false` 并存，而 `.id` 恒等；hoist 摘回初版因此静默失效）—— 比对一律按 `.id`，禁用 `===`
  （教训写入 §10.56）；批25 还实证三条形状：尾随闭包 hoist 四变体、if 体吸附、包装节点取 `namedChild(0)`。
  并且：**否定结论（0 命中）有证据门槛** —— 判据形状实证 + 正控 + 覆盖度对账 + 合法者见证，
  缺一项只按"未知"记（§10.55 文末"验证式否定"的构成）。
- `tools/golden.js:94` 那条重复 KLV 0x04 维持现状；`.gitignore` 里 `state/` 保留。
- git：**新建 commit，绝不 amend/squash 已发布提交；不推送**（用户 2026-10-11 当面拍板"暂不推"；要推要先让 CI 替全仓过一遍类型检查，这是唯一路径，见 §2）。

---

## 7. 判定表口径（补 batch16 或再拆施工单时照抄）

任务单 `state/brief/batchNN.md`，行格式 `id | TRIAGE可行性 | IDEA-BANK 原句 | 全仓标注位置`。
判定五档：REAL / PART / FAKE（只有注释或文案，代码没行为）/ DEAD（实现了但零使用点，须自己 grep 确认）/
NOC（必须真锁、真机眼睛或编译器，代码确实写了）。
输出 `state/verdict/batchNN.tsv`（6 列，无表头）：
`id ⇥ 判定 ⇥ 依据文件:行 ⇥ 一句话依据 ⇥ 欺骗文案Y/N ⇥ 摘句`。
要求：整文件读完；行号必须是你实际读到的；注释里有编号**不算**证据；名字相像**不算**证据。

### A6 B 类状态复核（进行中 · 首片已出）

- 工具：`state/bcheck.js <id...>` —— 打印每个 id 在当前代码里的标注位置（C=注释/K=代码）+ 上下文片段。
  **只用来定位要读的代码**，标注存在 ≠ 缺的那半已补。
- 首片报告：`state/recon/B-class-refresh.md`（method + 逐条判定 + file:line 依据）。
- 关键结论：**工单快照会系统性高估剩余量** —— PART-a batch01 实读 13 条里**确证已闭 7**（183/551/552/558/577/590/796）、
  降级 1（581，与既有「不另造已读位」口径冲突）、开放或待读 5（592 / 598 / 749 / 785 / 1016）；
  batch02 的 22 条机器筛下来几乎全带口径论证的标注（173/174/178/303/305/306/327/330/333/341/343/519/522/523…），按疑似已闭记账。
  ⇒ 后续请**先筛后读**：先把「无标注 / 标注只在文件头清单里」的筛出来，再只读该件声称的落点。
- 真开放的那几条都不是一行接线：592（折叠键要加凭证维度 + 60s 窗口，且牵动 917 的「+2」口径）、
  598（行池受 `Store.readLogs` 每锁 300 条缓存约束，是数据层的事，不是调常数）、
  749（缺逐段核对 / 待补拉日期段）、1016（缺出行日期段写入入口）—— 进队列时按 B 类份额估。
