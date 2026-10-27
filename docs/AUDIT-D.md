# AUDIT-D — 创意 801–1050 对抗式代码审计


> ⚠ **本档是历史台账，不是当前代码的说明书。**
> 里面的 `文件:行号` 指针记录的是**写档当时**的位置；后续精简/重构后部分文件已删或行号已移，
> 那些失效指针是台账的**正常内容**（它记的就是"某批删了什么"），不是错误。
> 想知道某个功能现在还在不在，请看 `docs/feature-web/features.json`（那份由工具从 inventory 重算）。

> 方法: 以 ROADMAP-DRAFT 包14/15/16/17/18「收录/舍弃/⚠」+ FEATURE-TRIAGE Part4(801–1050) + DECISION-NEEDED + DEFERRED(包15/17 节) 为基准, 逐编号在 App/ 内 grep 实现证据 (创意号写在代码注释里), 三态判定: DONE / PART(未接线或备案降级) / MISS(无代码无备案)。
> 审计日 2026-10-07。只信代码, 不信文档声称。
> 扫描口径: 创意号作为 token 在 App/*.swift 全量匹配 (tools/_scan_ids.py, 命中 156 个); 未命中的 95 个逐条核文件名佐证, 排除 ❌/舍弃/备案后为 MISS/PART 候选。

## 一、统计 (801–1050, 共 250 编号)

| 分类 | 数量 | 说明 |
|---|---|---|
| 应做 (✅收录+⚠收录, 排除❌/舍弃/脱纲) | 221 | |
| DONE | 129 | 有实现且接线 |
| ⚠DONE (合规降级/备案) | 25 | 869/875/877 + 包17 Widget/NFC/Watch 备案族 + 1022 |
| PART (未接线/组件零消费/半成品) | 21 | 见下 |
| MISS (无代码无备案) | 46 | 集中在包14 空态情境(816-833 区段)与包16 外观细节(887-912 区段) |
| ❌ 排除 | 15 | 924/925/926/928/929/930/931/932/934/935/936/938/940/944/1009 (DECISION-NEEDED 未做=合规) |
| 舍弃 | 13 | 823/848/867/888/906/911/913 (ROADMAP) + 915/920 (DEFERRED 包3) + 923/1029/1032/1040 (DEFERRED 包6/包4) |
| 脱纲 | 1 | 917 连开合并: 不在任何包收录/舍弃清单 (ROADMAP 覆盖校验缺口), 592 连击合并已做承担主要价值 |

**MISS 46 项**: 806/807/808/810/816/817/818/819/820/822/824/825/826/827/828/829/830/832/833/843/853/860/874/884/887/889/890/892/893/894/895/898/899/900/901/902/903/904/905/907/908/909/912/973/990/1047 (另 812 判 PART)。
**PART 21 项**: 812/814/834/839/841/842/859/868/871/872/886/897/927/933/949/950/951/955/989/995/998。
> 这行是**首轮 triage 快照**，不代表现状：927/933 已于第七十批按哑按钮口径落地、949 已按拍板划掉，
> 其余条目的当前状态以下面那张表为准（本行不改数字，免得又造一份一刷新就过期的硬计数）。

## 二、P0 已修清单 (当场修复, 闸门已绿)

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| P0-1 | DemoKit.demoDevice | 演示锁 pairedAt 写原始毫秒秒数, 而真实锁为 ISO8601 文本 (LockService:498) — Milestones.bootstrap 结缘日解析对 demo 锁误读 (数据一致性) | demo 锁同口径写 ISO8601 文本 |
| P0-2 | Milestones.bootstrap | 结缘日只读 `.first` 且按 ISO8601 前缀解析, 兼容不了旧 demo 锁遗留秒数格式 | 改最早 pairedAt + 双格式容错 (ISO8601 / 毫秒秒数) |
| P0-3 | AppIntents.OtpIntent | 周期写死 60s, 与锁端 zotpPeriod 默认 30 分钟窗错位 → 生成的临时码锁端校验必失败 (P0 功能级 bug) | 改 periodSec: 30 (与 CredentialsView:1512 本地生成器同口径) |
| P0-4 | AppIntents.UnlockIntent | ① 冷却判定在查锁之后 (拦截路径多查一次库且冷却时间戳被误消耗); ② 演示锁可被意图定位 (演示数据混入真实开锁动线); ③ 参数缺失/空名直接走"没找到" | 冷却先判; 名/型号/子串容错匹配; 空名护栏; 演示锁明确拒绝; 审计记 kc.name |
| P0-5 | AppIntents.OtpIntent | 只按精确 name 匹配 (说"KX"查不到型号名锁) + 演示锁可生成码 | 名/型号匹配 + 演示锁护栏 + skey 复核 |
| P0-6 | AppIntents.LockStatusIntent | 匹配口径与上两意图不一致 + 无快照时空行输出 | 名/型号对齐 + "尚无缓存读数"提示 |
| P0-7 | Onboarding:490 | 811 自检清单蓝牙项: @State btStatus 快照 + refreshBtStatus 空写死代码, 详情永不随系统蓝牙变化 | 删 @State 快照与 refreshBtStatus, 计算属性每帧求值 |
| P0-8 | CareReminders.reschedule | 每次开关生日/纪念日提醒都无条件 requestAuthorization — 已授权时重复弹系统授权框, 被拒后 reschedule 静默失败难排查 | notificationSettings() 先判: notDetermined 才请求, .authorized 直接放行 |
| P0-9 | LockKeeperApp.onLaunch | RootView .task 重入 (场景重建) 时跨年烟花/周年卡/成就补结算重复执行, 时刻卡重复入队 | didLaunchSettle 幂等护栏 |

未修 (P1/P2 见下)。闸门: swiftcheck ✓ / contrast 111 断言 ✓ / dynamictype ✓ / golden ✓。

## 三、P1 清单 (只列不修)

| 编号 | 问题 |
|---|---|
| 814/834/841 | GuidedEmptyView (进度点/双按钮/演示链接/小管家一体组件) 定义后全库零调用点, 各页空态各写各的 EmptyState — 组件悬空 |
| 839 | 839 示例过滤器只有 DemoKit.setDrillFilter/clearDrillFilter, 记录页无"示例筛选"芯片入口, 开关不可达 |
| 842 | kf_demo_drill_on 只有清位 (SettingsView:167 转正式), 全库无置位点 — "首次备份标演练"永不发生 |
| 859 | axStackLayout 定义后零消费 — "字号≥1.5 指标纵向堆叠/圆盘缩 128pt" 文案声称自动启用, 实际无布局分支 |
| 871 | axHit60 定义后零调用 (UnlockDial 自带 10pt 余量; 时间线次级按钮 60pt 未接) |
| 872 | 防连点开关 (kf_dbltap_guard) 有 UI 无消费点 — 开关形同虚设 |
| 868 | 切换控制"三个扫描组"仅 DeviceHomeView:718 一处注释, 状态卡/快捷格无 accessibilityActionDiscovery 分组实装 |
| 927/933 | Widget 渲染跟随/交互 Widget 与 DEFERRED "4/943 不建 Widget target" 同根因, 但 DEFERRED 未写 927/933 编号 — 备案覆盖不到, 建议补录 **(第七十批已补录并落地哑按钮)** |
| 949 | UI 治理区声称"焦点期执行意图需 App 内确认 (949)" 但无 FocusKit 代码, 承诺未兑现 |
| 950 | ExportCsvIntent 只回行数与"去导出中心取走"提示, 意图本身不产出 CSV 文件, 与"导出 CSV 意图"语义有落差 |
| 951 | IntegrationCenterView 声称"设备/成员名称已入系统搜索 (293/951)" — 无 AppIntents 索引 (AppShortcutsProvider/AppEntity) 落地 |
| 955 | 成员查询意图只答档案 (关系/电话), 原意"妈妈今天开了几次门"日志统计未做 |
| 998 | badgeAnniversaryToday() 定义后零 UI 消费, "徽章周年回忆小卡"未上屏 |
| 989 | 成员称号体系未做, 仅 994 头像角标 (徽章) 落地 |
| 995 | "完成点亮入伙徽章" — 入伙徽章不在 Milestones.definitions, 欢迎 toast (Sheets:2296) 后无徽章结算 |
| 886 | 六色渐变色板实做 3 套 (indigo/forest/amber, 31 口径), 缺石墨/玫瑰/极光 |

## 四、P2 清单

| 位置 | 问题 |
|---|---|
| AuditChain SensitiveLedger.record | id=毫秒时间戳, 同毫秒两条审计重叠键 (与 AUDIT-B P0-2 同款根因, 意图审计 953 受益但不阻断) |
| AppIntents.UnlockIntent | 原文"参数带 Face ID 确认开关"未实现 (945 ⚠ 备案允许前台衔接, 可接受) |
| AppIntents.OtpIntent | 原文"有效期参数化"未实现, 固定 30 分钟窗 |
| Onboarding stepDots | "第 N/7 步"文案与实际 814 进度点 1-6 口径不一致 (视觉文案) |
| Milestones.capsuleIsOpen | 字符串比较 dayKey() >= openOn 只在同格合法 (openOn 恒为 yyyy-MM-dd, 现态正确, 但依赖格式约定) |

## 五、逐编号明细 (801–900)

| 编号 | 创意名 | 状态 | 证据 (文件:行) |
|---|---|---|---|
| 801 | 三卡首启导览 | DONE | App/UI/Onboarding.swift:251 tourPages 三卡横滑 + 末卡"去连接真锁" |
| 802 | 权限前置说明 | DONE | Onboarding.swift:374 permissionPage + :201 requestSystemPermissions |
| 803 | 演示锁试玩 | DONE | Onboarding.swift:428 demoPage demoDial 假数据走三阶段 |
| 804 | 引导进度存档 | DONE | Onboarding.swift:12 kf_onb_ 逐步打点 + nextStep 续接 |
| 805 | 跳过与重看 | DONE | Onboarding.swift:578 replayAll + :121 跳过 + SettingsView 805 入口 |
| 806 | 凭证首录分流 | MISS |  |
| 807 | 信号格配对引导 | MISS |  |
| 808 | 示例记录铺底 | MISS | 808 仅在 DesignSystem:526 注释, 无灰阶示例条目消费 |
| 809 | 角色化引导 | DONE | Onboarding.swift:54 applyRoleDefaults 角色建档 |
| 810 | 朗读式引导 | MISS |  |
| 811 | 首启自检清单 | DONE | Onboarding.swift:484 checklistPage (P0-7 修 btStatus) |
| 812 | 延迟添加指纹 | PART | DeviceHomeView:969 快捷格"录指纹"入口承担; 虚线预留格形态未做 |
| 813 | 管家就任证书 | DONE | Onboarding.swift:531 certificatePage + HelpCenter:371 ButlerCertificateView |
| 814 | 空态进度点 | PART | 组件在 DesignSystem:528 GuidedEmptyView, 零调用点; Onboarding:99 步骤点非空态 |
| 815 | 空态双按钮 | DONE | App/UI/CredentialsView.swift:1527 主"添加第一条密码"+次"看看它如何工作" |
| 816 | WebDAV 引导空态 | MISS | WebDAVStudioView 只有表单, 无"三行收益说明"未配置空态 |
| 817 | 成员示例头像 | MISS |  |
| 818 | 日志来源说明空态 | MISS |  |
| 819 | 诊断首跑按钮 | MISS |  |
| 820 | OTP 科普空态 | MISS |  |
| 821 | 临时码零库存 | DONE | CredentialsView:1544 酒店门卡比喻 + 发第一张按钮 |
| 822 | 从未备份信封 | MISS |  |
| 823 | 搜索无结果引导 | 舍弃 | ROADMAP 包14 舍弃(与 558/532 重复) |
| 824 | 重新开始空态 | MISS |  |
| 825 | 固件首检引导 | MISS |  |
| 826 | 聚光教练标 | MISS |  |
| 827 | 顺序揭幕提示 | MISS |  |
| 828 | 字段旁问号 | MISS |  |
| 829 | 失败原因折叠 | MISS |  |
| 830 | TipKit 情境条 | MISS | 全库无 TipKit import |
| 831 | NEW 角标 | DONE | App/UI/SettingsView.swift:29 kf_seen_ 角标 |
| 832 | 一次性手势提示 | MISS |  |
| 833 | 撤销教学 Toast | MISS |  |
| 834 | 30 秒演示链接 | PART | CredentialsView:1532 "看看它如何工作"承担; 通用组件零调用 |
| 835 | 本地使用手册 | DONE | App/UI/HelpCenter.swift:246 ManualPage + :132 未读章 |
| 836 | 演示模式总开关 | DONE | App/Core/DemoKit.swift:15 + DemoBanner 常驻横幅 |
| 837 | 样例备份包 | DONE | DemoKit:139 sampleBackupText + HelpCenter:429 演练场 |
| 838 | 录前预习动画 | DONE | HelpCenter:477 预习开关 30s 分步 |
| 839 | 示例过滤器 | PART | DemoKit:115 setDrillFilter, 无 UI 入口 |
| 840 | 成就预览卡 | DONE | App/UI/AchievementsView.swift:280 未达成灰卡 |
| 841 | 小管家形象 | PART | HelpCenter:332 DemoMascot/EmptyMascotHeader, 仅悬空组件消费 |
| 842 | 演练备份 | PART | DemoKit:134 标记与摘除在 (SettingsView:167), 无置位点 |
| 843 | 权限示例内嵌 | MISS |  |
| 844 | 锁死演练 | DONE | HelpCenter:520 runLockoutDrill 三步不写真日志 |
| 845 | 7 天样例生成器 | DONE | DemoKit:83 generateSevenDaySamples demo_ 前缀 + 横幅清除 |
| 846 | 圆盘转子调节 | DONE | App/UI/UnlockDial.swift:274 846/167 VO 转子 状态/电量/连接 |
| 847 | 状态卡合并播报 | DONE | UnlockDial:565 + DeviceHomeView hero 合并 label |
| 848 | 成败提示音 | 舍弃 | DEFERRED 包15: 并入 76 声效开关 |
| 849 | 凭证朗读顺序 | DONE | CredentialsView 行 名称-类型-状态 顺序 |
| 850 | 时间线自然语朗读 | DONE | AccessibilityKit:92 AXTerms.rowSentence |
| 851 | VoiceOver 练习场 | DONE | App/UI/AccessibilityView.swift:232 VOPracticeField |
| 852 | 错误主动播报 | DONE | AccessibilityKit:114 AXTools.announce + 开关 |
| 853 | 语音版引导串讲 | MISS |  |
| 854 | 全键盘导航 | DONE | LockKeeperApp.swift:504 Tab keyboardShortcut 1-4 |
| 855 | 焦点顺序巡检 | DONE | AccessibilityKit:142 runFocusAudit + AccessibilityView 巡检区 |
| 856 | 盲文简写标签 | DONE | AccessibilityKit:100 AXTerms.br + DeviceHomeView:536 消费 |
| 857 | 静音开关尊重 | DONE | DesignSystem:236 systemSound 策略注释 + 说明行 |
| 858 | App 内字号五档 | DONE | AccessibilityKit:26 + AccessibilityView:60 Picker + RootView:615 |
| 859 | AX 档降级布局 | PART | AccessibilityKit:51 axStackLayout 定义零消费 |
| 860 | 等宽日志开关 | MISS | monospacedDigit 已有 (231), SF Mono 切换开关无 |
| 861 | 加粗文本跟随 | DONE | 系统级原生尊重, AccessibilityView:93 说明 |
| 862 | 增强对比映射 | DONE | DesignSystem:129 hairlineStrong/textSubStrong |
| 863 | 智能反转保护 | DONE | AccessibilityKit:66 heroGradientSafe 反转幂等色 |
| 864 | 外观三选预览 | DONE | SettingsView:463 主题 Picker (跟随/浅/深/纯黑) |
| 865 | 数字防跳 | DONE | monospacedDigit 全库消费 |
| 866 | 极限字号自检 | DONE | AccessibilityKit:53 bigPreview + RootView:615 200% 预览 |
| 867 | 降低透明度映射 | 舍弃 | DEFERRED 包15: 与 226 重复 |
| 868 | 切换控制扫描组 | PART | DeviceHomeView:718 仅圆盘注释, 无扫描组实装 |
| 869 | 眼动停留兼容 | ⚠DONE | AccessibilityKit:189 kf_ax_dwell 滑杆 (DEFERRED 备案) |
| 870 | 底部对齐表单 | DONE | AccessibilityKit:208 axBottomAnchor + 开关 |
| 871 | 命中域扩容 | PART | axHit60 定义零调用; 圆盘 UnlockDial:257 自带余量 |
| 872 | 防连点开关 | PART | 开关在 (AccessibilityView:118), 全库无 300ms 去抖消费点 |
| 873 | 圆盘热区偏移 | DONE | DesignSystem:244 axOnehand 单手下沉 |
| 874 | 辅助触控说明页 | MISS |  |
| 875 | 按住时长跟随 | ⚠DONE | AccessibilityKit:183 kf_ax_hold 滑杆 + UnlockDial:130 消费 |
| 876 | 新条目双震 | DONE | AccessibilityKit:124 newEntryHaptic |
| 877 | 验证降级大键 | ⚠DONE | AccessibilityKit:215 AuthKit 生物门控 + AppLockView:740 大字键 |
| 878 | 形状冗余三态 | DONE | AccessibilityView:75 shapeChip 三态双通道 |
| 879 | 灰度预览自检 | DONE | AccessibilityKit:55 grayPreview + RootView:617 saturation |
| 880 | 朗读词表统一 | DONE | AccessibilityKit:78 AXTerms |
| 881 | 字幕式过程条 | DONE | AccessibilityView:345 CaptionStepBar 消费于 DeviceHomeView |
| 882 | 闪烁安全线 | DONE | docs/A11Y-FREQUENCY.md 核查表 + ≤3Hz 注释 |
| 883 | 对比度计算器 | DONE | AccessibilityKit:150 contrastRatio + DevContrastSection |
| 884 | 公共场合音量提示 | MISS |  |
| 885 | 凭证大字模式 | DONE | CredentialsView:1467 kf_ax_bigotp 双击切大字 |
| 886 | 六色渐变色板 | PART | DesignSystem:141 themeTable 仅 3 套 (idea 31 口径), 缺石墨/玫瑰/极光 |
| 887 | 跟随系统着色 | MISS | 无图标染色资产管线 |
| 888 | 一锁一色 | 舍弃 | ROADMAP 包16 舍弃(与 105 重复) |
| 889 | Hero 纹理三档 | MISS | HeroCard 仅渐变, 无噪点/网格档 |
| 890 | 节日限定色 | MISS |  |
| 891 | 深浅双端点 | DONE | DesignSystem:141 themeTable light/dark 双端点 + contrast.js 机检 |
| 892 | 自定义强调色 | MISS | 无 ColorPicker 管线 |
| 893 | 高对比皮肤 | MISS |  |
| 894 | 主题随备份走 | MISS | 备份 globals 无 kf_theme/kf_accent |
| 895 | 儿童主题 | MISS |  |
| 896 | 备用图标 | DONE | project.yml:41 AppIcon-Ring/Key/Shield + SettingsView:517 iconPickerRow |
| 897 | 四季图标 | PART | 4 款图标已生成; "春夏秋冬自动切换/手动固定" 日历逻辑无 |
| 898 | 启动一句话 | MISS |  |
| 899 | Tab 动效三档 | MISS |  |
| 900 | 全局圆角档位 | MISS |  |

## 六、逐编号明细 (901–1050)

| 编号 | 创意名 | 状态 | 证据 (文件:行) |
|---|---|---|---|
| 901 | 凭证行高两档 | MISS |  |
| 902 | 数字字体两套 | MISS |  |
| 903 | 空态插画密度 | MISS |  |
| 904 | 设备页模块排序 | MISS |  |
| 905 | 快捷格四选十 | MISS |  |
| 906 | 分段计数徽标 | 舍弃 | 并入 524 |
| 907 | 时间线密度三档 | MISS |  |
| 908 | 过滤默认策略 | MISS |  |
| 909 | 指标位显隐 | MISS |  |
| 910 | 最近开门条数 | DONE | 见上 (SettingsView:525) |
| 911 | 时间制式覆盖 | 舍弃 | ROADMAP 包16 舍弃(与 647 重复) |
| 912 | 周起始日 | MISS | Milestones.weekDone 固定 weekOfYear, 无周一/周日偏好 |
| 913 | 电量表述切换 | 舍弃 | ROADMAP 包16 舍弃(与 111 重复) |
| 914 | 凭证排序器 | DONE | CredentialOrg:90 四维排序 + kf_ccred_prefs 持久化 |
| 915 | 置顶凭证 | 舍弃 | DEFERRED 包3: 与 526 置顶星标重复 |
| 916 | 成员 emoji 代号 | DONE | MemberHub emoji 头像 |
| 917 | 连开合并 | 脱纲 | 无包收录/舍弃记录; 592 连击合并 (RecordsView:1501) 承担主价值 |
| 918 | 命名模板 | DONE | CredentialOrg/CredentialStudio 命名模板 (918 注释) |
| 919 | 别名显示切换 | DONE | CredentialOrg 别名切换 (919) |
| 920 | 安装位置字段 | 舍弃 | DEFERRED 包3: 与 774 重复, 收敛 LockMeta.place |
| 921 | 常用星标 | DONE | CredentialsView:5 526/921 置顶星标 |
| 922 | 批量整理 | DONE | CredentialsView 347/356/357 编辑模式 + 批量 |
| 923 | 凭证回收站 | 舍弃 | DEFERRED 包6: 与 497-506 回收站重复 |
| 924 | 状态中号 Widget | ❌ | DECISION-NEEDED 替代(943 承担), 未做=合规 |
| 925 | 多锁横滑 Widget | ❌ | 同上 |
| 926 | 下一场到期 Widget | ❌ | 同上 |
| 927 | 交互开锁 Widget | **DONE (降级口径)** | 第七十批: 拍板 #30 选 B —— 哑按钮 Widget 已建 (`Widget/LockWidget.swift`)，经 `kf://device` 拉起 App 到设备页；组件内**不执行开锁**、不显示状态/电量 (无 App Groups)。DEFERRED 已补录 927/933 编号 |
| 928 | 速览记录 Widget | ❌ |  |
| 929 | 连续天数 Widget | ❌ | 975 已常驻时间线 |
| 930 | 到期凭证 Widget | ❌ |  |
| 931 | 全锁电量 Widget | ❌ | 1041 电量升序替代 |
| 932 | 应用锁联动 Widget | ❌ | DECISION 跳过 |
| 933 | 渲染模式跟随 | **DONE (口径降级)** | 第七十批: 组件只用系统语义色 (`Widget/LockWidget.swift` 的 `.containerBackground(.fill.tertiary, for: .widget)`)，因此**跟随系统浅色/深色**；App 内主题 (`kf_theme`) 跨不过 target 边界 (无 App Groups)，不宣称跟随 |
| 934 | 字段自配 Widget | ❌ |  |
| 935 | 早晚两点 Widget | ❌ |  |
| 936 | 省电静态模式 | ❌ |  |
| 937 | 控制中心开锁控件 | ⚠DONE | AppIntents:209 降级说明 (DEFERRED 备案) |
| 938 | 只读状态控件 | ❌ | 双重缺口 |
| 939 | 灵动岛过程条 | ⚠DONE | DEFERRED 包17: 不做 Live Activity target |
| 940 | StandBy 床头模式 | ❌ | DECISION 跳过 |
| 941 | 临时码实况 | ⚠DONE | DEFERRED 包17 |
| 942 | Siri 时刻建议 | ⚠DONE | AppIntents:176 at8 口令 + DEFERRED (不建 target) |
| 943 | 主屏快速操作 | ⚠DONE | DEFERRED 包17: 不建 Widget/快捷 target, 备案口径 |
| 944 | 多锁控件组 | ❌ |  |
| 945 | 开锁意图 | DONE | AppIntents:30 UnlockIntent foreground + 60s 冷却 + 演示锁护栏 (P0-4) |
| 946 | 状态问答 | DONE | AppIntents:74 LockStatusIntent 只答电量/固件/锁钟 (P0-6) |
| 947 | 临时码意图 | DONE | AppIntents:56 OtpIntent 纯本地 ZOTP 30s 窗 (P0-3/P0-5) |
| 948 | 示例指令包 | DONE | AppIntents:168 AppShortcuts.phrases 画廊 |
| 949 | 焦点确认加严 | **划掉 (拍板 组3 #31)** | 第六十二批: 承诺文案已删, 现写"不提供 (949 已划掉): 意图执行不判定焦点状态, 也不申请 FocusKit 授权" (AppIntents.swift:278)。FocusKit 在免费账号侧载下的可用面未实测 → 按拍板不接，也不再声称提供 |
| 950 | 导出 CSV 意图 | PART | ExportCsvIntent 只回行数, 不产出文件 |
| 951 | Spotlight 直达 | PART | UI 声称入索引, 无 AppEntity/Provider 代码 |
| 952 | 执行冷却 | DONE | IntentGovernance:16 60s |
| 953 | 意图审计日志 | DONE | IntentGovernance:24 SensitiveLedger |
| 954 | 主屏图标教程 | DONE | AppIntents:231 教程段 |
| 955 | 成员查询意图 | PART | MemberQueryIntent 只答档案, 日志统计未做 |
| 956 | 语音读记录 | DONE | ReadRecordsIntent TTS |
| 957 | NFC 标签中心 | ⚠DONE | AppIntents:215 登记页 + 能力探测文案 (DEFERRED) |
| 958 | 贴标即确认 | ⚠DONE | DEFERRED 包17 (写卡未做) |
| 959 | 到家打卡标签 | ⚠DONE | DEFERRED 包17 |
| 960 | 钥匙扣写卡向导 | ⚠DONE | DEFERRED 包17 |
| 961 | 对准波纹提示 | ⚠DONE | DEFERRED 包17 |
| 962 | 前台限制 | ⚠DONE | DEFERRED 包17 |
| 963 | 定时状态确认 | ⚠DONE | DEFERRED 包17 |
| 964 | 触发来源标记 | DONE | IntentGovernance.audit 意图名即来源 |
| 965 | 手表状态表盘 | ⚠DONE | AppIntents:225 路线图文案 (DEFERRED) |
| 966 | 表端开锁 | ⚠DONE | DEFERRED 包17 |
| 967 | 表端告警 | ⚠DONE | DEFERRED 包17 |
| 968 | 表端临时码 | ⚠DONE | DEFERRED 包17 |
| 969 | 表端电量 | ⚠DONE | DEFERRED 包17 |
| 970 | 表端广播监听 | ⚠DONE | DEFERRED 包17 |
| 971 | 表端开门 | ⚠DONE | DEFERRED 包17 |
| 972 | 表端已上锁 | ⚠DONE | DEFERRED 包17 |
| 973 | 配对图文教程 | MISS |  |
| 974 | 表端离线码 | ⚠DONE | DEFERRED 包17 |
| 975 | 管家连续天数 | DONE | RecordsView:180 markRecordsViewed + streak() 跨月容错 (dayKey 本地时区) |
| 976 | 安心夜月历 | DONE | AchievementsView:395 NightCalendarCard |
| 977 | 四类成就墙 | DONE | AchievementsView:166 四类分组 |
| 978 | 隐藏成就 | DONE | Badge.hidden + "???" 瓷片 |
| 979 | 稀有度分级 | DONE | BadgeRarity 三档边色 |
| 980 | 备份卫士 | DONE | BackupView:60/188 recordBackup 接线 + 徽章 |
| 981 | 周目标星 | DONE | AchievementsView:110 周目标卡 |
| 982 | 开门里程碑 | DONE | DeviceHomeView:446 Hero 卡角标 |
| 983 | 本月门神榜 | DONE | RecordsView:673 doorGods 排名 |
| 984 | 成就分享卡 | DONE | AchievementsView:95 ImageRenderer 存相册 + NSPhotoLibraryAddUsageDescription |
| 985 | 补签卡 | DONE | Milestones:161 每月 1 张 + NightCalendarCard 补签钮 |
| 986 | 成就本地通知 | DONE | Milestones:533 notifyAchievement (P0-8 授权修正) |
| 987 | 悬念进度 | DONE | AchievementsView:316 徽章详情"还差一点点" |
| 988 | 徽章陈列架 | DONE | AchievementsView:64 最近 3 枚 |
| 989 | 成员称号 | PART | 仅 994 角标 (kf_member_badge), 称号体系无 |
| 990 | 开门附言 | MISS |  |
| 991 | 生日撒花 | DONE | RecordsView daySection 组头 (DEFERRED 653 口径) + CareReminders.bdayOn |
| 992 | 百次彩蛋 | DONE | LockKeeperApp:437 m18.100 时刻卡 |
| 993 | 夜猫守护徽章 | DONE | definitions "owl" 隐藏徽章 |
| 994 | 头像角标 | DONE | RecordsView:673 memberBadges 角标 |
| 995 | 入伙欢迎卡 | ~~PART~~ → 2026-10-15 复核**已闭合** (MemberWelcomeCard 三步指路已落: Sheets:2748/2571/2675; join1=joinedWithCred 已修) | Sheets:2296 欢迎 toast; "入伙"徽章不在 definitions |
| 996 | 收集音效 | DONE | Milestones:528 playCollectSound + 开关 |
| 997 | 家庭共创目标 | DONE | Sheets:2159 本月全家备份进度 |
| 998 | 徽章周年回忆 | PART | Milestones:446 badgeAnniversaryToday 零 UI 消费 |
| 999 | 流光赛季边 | DONE | DesignSystem:468 HeroFlairBorder + Milestones:353 7 天窗口 |
| 1000 | 晚归欢迎语 | DONE | LockKeeperApp:450 22 点后 publishHomeMoment |
| 1001 | 节气问候 | DONE | Milestones:379 solarTermToday + DeviceHomeView:1158 |
| 1002 | 凌晨静默态 | DONE | LockKeeperApp:430 hour>=6 才播时刻 |
| 1003 | 安慰式报错 | DONE | DeviceHomeView:761 一次失败安慰, 三次转排查清单 |
| 1004 | 喂电提醒 | DONE | BatteryCare:86/131 滞回低电本地通知 |
| 1005 | 千次心跳 | DONE | Milestones:200 heartbeatHaptic + m18.1000 |
| 1006 | 机械计数器 | DONE | SettingsView:635 关于页机械计数样式 |
| 1007 | 维护致谢 | DONE | Milestones:256 recordOrganize 每 10 次 |
| 1008 | 指纹入家天数 | DONE | CredentialsView:1080 陪伴天数 "入家 N 天" |
| 1009 | 涟漪结界 | ❌ | DECISION-NEEDED 建议改挂确证事件, 未做=合规 |
| 1010 | 结缘日 | DONE | Milestones.bootstrap (P0-1/P0-2 修正) + 周年彩带 |
| 1011 | 凭证陪伴天数 | DONE | Milestones:362 companionText + CredentialsView:1072 |
| 1012 | 自定义保养日 | DONE | App/UI/CareViews.swift |
| 1013 | 90 天保养周期 | DONE | CareViews + CareSchedule.refreshOnLaunch |
| 1014 | 换电池事件 | DONE | BatteryCare events + 记录分类 |
| 1015 | 保养五项清单 | DONE | CareViews:1015 勾选存本地 |
| 1016 | 出行观察模式 | DONE | RecordsView:615 静默观察横幅 |
| 1017 | 成员生日提醒 | DONE | CareReminders:607 提前一天 + 1017 复用 |
| 1018 | 月度备份日 | DONE | BackupStudio.scheduleMonthlyBackup + LockKeeperApp:408 |
| 1019 | 固件服役天数 | DONE | BatteryCare/Sheets 服役天数 |
| 1020 | 黄金时段洞察 | DONE | StatsKit:355 golden hour 一句话 |
| 1021 | 跨年烟花 | DONE | LockKeeperApp:385 ny\(year) 一次性 + P0-9 幂等 |
| 1022 | 频次自适应保养 | ⚠DONE | CareViews:20 近 30 天 ≥60 次缩短周期 |
| 1023 | 指纹头清洁提醒 | DONE | type13 三连失败提醒 |
| 1024 | 潮湿位关怀 | DONE | CareViews 季节防潮 |
| 1025 | 应急钥匙半年检 | DONE | CareViews 半年打卡 |
| 1026 | 低温电池关怀 | DONE | CareViews:1026 气候表 |
| 1027 | DFU 前三勾 | DONE | Sheets:1209 preflightSection 137/1027/1035 |
| 1028 | 保养历史过滤 | DONE | CareViews 专属分类过滤 |
| 1029 | 换电池倒推表 | 舍弃 | DEFERRED 包4 收敛舍弃 |
| 1030 | 清洁月历 | DONE | BatteryCare careStreakMonths + clean3 徽章 |
| 1031 | 夜间免扰 | DONE | CareViews 22-8 免扰 |
| 1032 | 续航斜率 | 舍弃 | DEFERRED 包4 收敛舍弃 |
| 1033 | 换电池向导 | DONE | CareViews:1033 分步+cmd0E 校时 |
| 1034 | 充电记录字段 | DONE | CareViews 充电日期时长 |
| 1035 | 升级前快照 | DONE | Sheets:1209 tickBackup 升级前备份勾选 |
| 1036 | 固件已知问题清单 | DONE | Sheets:1361 已知问题清单 |
| 1037 | 失败排查四项 | DONE | Sheets:142/1037 失败安抚 + 四项排查 |
| 1038 | 通知时间窗 | DONE | CareViews 通知时间窗 |
| 1039 | 续航管家徽章 | DONE | definitions batt2 (1039) |
| 1040 | 掉电观察行 | 舍弃 | DEFERRED 包4 收敛舍弃 |
| 1041 | 电量升序 | DONE | DeviceHomeView:169 kf_sort_batt + LockOverview 条带 |
| 1042 | 季度小报 | DONE | Milestones:548 quarterSummary + 季度卡 |
| 1043 | 时光胶囊 | DONE | AchievementsView:531 CapsuleComposeView |
| 1044 | 家庭公告板 | DONE | DeviceHomeView:43 空态便签 |
| 1045 | 感谢清单 | DONE | RecordsView:1827 感谢清单按月 |
| 1046 | 素颜模式 | DONE | Milestones:92 kf_plain + SettingsView Toggle |
| 1047 | 常用动作首格推荐 | MISS |  |
| 1048 | 管家交接包 | DONE | BackupStudio 备份+说明合并导出 |
| 1049 | VoiceOver 致意 | DONE | Milestones:342 markVoiceOver + SettingsView:670 |
| 1050 | 周年纪念卡 | DONE | LockKeeperApp:391 appann\(year) 周年时刻卡 |
