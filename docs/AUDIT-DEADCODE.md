# AUDIT-DEADCODE —— 零引用声明清单（现在是闸门，不是一次性报告）


> ⚠ **本档是历史台账，不是当前代码的说明书。**
> 里面的 `文件:行号` 指针记录的是**写档当时**的位置；后续精简/重构后部分文件已删或行号已移，
> 那些失效指针是台账的**正常内容**（它记的就是"某批删了什么"），不是错误。
> 想知道某个功能现在还在不在，请看 `docs/feature-web/features.json`（那份由工具从 inventory 重算）。

> 生成方式：`node tools/deadscan.js`（第六道闸门，第三十八批起入仓）。
> 口径：扫 `App/` 下所有顶层 `enum/struct/actor/protocol` 与 `func` 声明，按标识符全仓计数（含 `Type.member` 限定调用形式）；计数 ≤ 1 = 只有声明自身。
>
> **这是线索，不是判决**：每条最终要么接线、要么删除、要么写清为什么留着。名单只豁免真正的系统回调（`makeCoordinator` / `userNotificationCenter` 等由系统按名调用，源码里天然没有调用点）。
>
> 一条踩过的坑：`userNotificationCenter` 这种协议方法若不加名单，`didReceive` 与 `willPresent` 两个同名声明会让计数变成 2，**假通过**。所以协议成员一律走名单，不靠计数。

## 当前清单（7 条，全部已有判定）

| 种类 | 名称 | 位置 | 判定 |
|---|---|---|---|
| func | `stopReconnectLoop` | App/Core/LinkSenseKit.swift:220 | 留着不接 · 该 2s tick 同时驱动 AUTOOPEN 停留判定, 停它=悄悄关掉自动开锁 (代码内已写明) |
| func | `stopDeadWatch` | App/Core/LinkSenseKit.swift:299 | 留着不接 · 未连接时判校本就惰性 return, 停它无收益, 重启需绑连接事件=节拍改造 |
| func | `addTransfer` | App/Core/MemberHub.swift:223 | 留着待拍板 · 队列读侧与接受/拒绝 UI 都在, 但没人发起移交 (移交走 batchTransfer 直接改台账) → NEXT-DECISIONS 组5 |
| type | `CommuteLabel` | App/Core/RecordSearch.swift:86 | 留着待落点 · 674 词表就绪; 加进行内小字还是详情卡属界面密度决定, 由你拍 |
| type | `TimeWord` | App/Core/RecordSearch.swift:98 | 留着待落点 · 658 同上一条 |
| func | `clearFailEvents` | App/Core/Store.swift:665 | 留着待拍板 · 清空=抹掉记录时间线里用户看得见的行 → NEXT-DECISIONS 组5 |
| func | `recordCard` | App/UI/ExportCenter.swift:641 | 留着待落点 · 718 单条分享卡渲染器就绪, 分享出口形态待定 |


## 第三十八批已处置（54 → 37）

**接线（有真实消费方，且已核对该消费方不是空跑）**
- `DiagTime.hhmmss` → 它此前零调用，而 `LockService.log` 里手写了一份一模一样的 `%02d:%02d:%02d`。收归一处，删重复实现。
- `DiagLogs.entities` + `EntityRef.isCredential` → 接进诊断页运行日志行（543 实体跳转）。**先验证再接**：旧识别器匹配 `pwd:` / `fp:`，而全仓没有任何日志生产者写过这两个前缀（grep 只命中 Swift 属性声明 `var pwd:`），直接接上去就是个永远返回空数组的空跑。改成匹配真实词表 `凭证#N` / `指纹#N` / `MAC=<12hex>`，并在 `LockService` 的 0A/0B/14/15 落地处补写这些标记。裸 `[0-9a-f]{12}` 会从 debugRaw 的长 hex dump 里任意截一段当 MAC，已改成只认 `MAC=` 后的整串。
- `DataHealth.gapDays`(451) / `archivedCount`(223) → 存储与数据区：空洞日期只报两侧都有数据的天，归档条数在按按钮之外常驻可见。
- `ProtocolDict.copyable`(754) → 「诊断查阅」页字段字典区加"复制全表"。
- `SymptomGuide`(282) → 新增 `SymptomGuideView`（三棵判断树 + 已答轨迹 + 结论页）。树里 id 拼错时走"这一步在判断树里找不到"分支，不静默白屏。
- `FAQPage`(514) → 设置-帮助区加真入口。此前入口按钮文案写着"使用手册与**常见问题**"，但 FAQPage 全仓没有任何 NavigationLink —— 承诺与实现不符。
- `CopyTable` / `LocalizedCopy`(669) → 文案体检页加"关键文案键位"区，逐键显示实际值并如实标 `简`/`繁`。文案明确写"这一版没有翻译内容，只保证将来加译不动结构"，不假称支持繁中。
- `CredentialOrg.binPwd` / `binFp` → 作为 543 详情卡的第二级查找（台账没有、回收站有 → 指路"凭证中心 → 回收站"）。
- `CredentialOrg.handleNotificationAction`(366/1013) → 见下面单列，这条改动最大。

**通知分派（本批最大的一条真缺陷）**
- 旧 `handleNotificationAction` 分派的 `c6.expired` / `c6.center` / `c6.queue` / `c6.restore.*` **全仓没有任何生产者**（grep 只命中函数自身），而真正排期过的 `c6.alert.<mac>.p<alias>.d7|.h24` 和 `c6.monthly` 它一个都不认。按真实标识重写为 `.locatePwd` / `.panel`，删掉不存在的分支。
- `UNDelegate` 此前只在"排月度备份提醒"那条路径里被赋值 (`delegate = UNDelegate.shared`) → 没开月备的用户点任何本地通知都没反应。改到 `AppState.init()` 无条件安装。
- 补 `willPresent`：不实现它 = 前台完全静默，用户正拿着手机反而看不到"密码临期"。免扰时段 (1031) 仍返回 `[]`。
- 落地只走两条既有跳法：`pendingCredNav`（577 单条定位）与新增 `pendingCredPanel`（打开 回收站/队列/整理 三个已有 sheet）。应用锁没解开时凭证 Tab 根本不在层级树里，值一直挂着，解锁后 `onAppear` 才消费 —— 通知不得绕过门禁。

**顺带抓到的显示错误**
- `EntityRef.text` 的 `.member` 分支返回的是内部 id 不是名字（kind 存 `m.id`），已改查 `DB.member(id)?.name`。
- `entities` 里 `s` 声明成 `var` 却从不修改；`fp:` 分支 `dropFirst(4)` 会把批次首位数字吃掉（旧注释已发现同类问题但只修了一半）。

## 第三十九批已处置（37 → 32）

- `CredGroupMode`(355) → **让枚举成为唯一口径**：`groupMode` 原来对外是裸 `Int`，UI 写 `== 1`，枚举没人用。
  现在 `groupMode: CredGroupMode` / `setGroupMode(_ v: CredGroupMode)`，`kf_ccred_prefs` 仍是 bit0 掩码写法不变。
- `smartListLabel`(527) → 智能列表菜单行与"删除「…」"确认行改用全标签（名称 · 属主 · 状态）。
  胶囊按钮**故意不用**：那里 `lineLimit(1)`，长标签会被截断——用户要读的字不该被截。
- `duplicatePwdValuesAnyLock`(304) → 两处 UI 都写着"全库重复拦截"，实际只查了当前这把锁。
  重写为 `duplicatePwdLockNames(_:excludingMac:)` 并接进新增/批量两处。**旧签名返回 `[LedgerPwd]` 却不带 mac**，
  调用方拿到条目也说不出是哪把锁；还把当前锁的其它别名一起算进来，与同锁检查重复计数。
  同锁那条的文案同时改成"本锁已有 N 条"，不再冒充全库。
- `inferredLastUse`(316) → 排序项"最近使用"此前按 `at`（**录入时间**）排，名不副实。
  改接 `inferredLastUseMap`：临时凭证按自身时间窗归属；长期凭证锁端日志不记凭证身份，
  只能给锁级参考（同值 → 实际退化成录入时间序），标签按本仓纪律改标"最近使用(约)"。
  批量版一次读日志，逐条调用会让每帧重解一遍。
- `totpRemaining`(337/171) → **删除**，不是接线。`WindowBar.remaining`（CredentialStudio.swift:238）
  是同一公式 `per - epoch % per` 且正在用；留两份等于让人以为有两套时窗口径。倒计时在 `剩约 N 秒` 处本来就有显示。

## 这一批顺带清掉的一类型错误（新闸门规则）
`ZKProtocol.protoSecondsToMs` 返回 **Int64**，而比较的另一侧几乎都是 Double（`timeIntervalSince1970` / `nowSec`）。
Swift 不做隐式数值转换 → `CredentialOrg` 里一次抓到 **7 处硬编译错误**（其中一处 `inWindow(p, at: t)` 把 Int64
传给形参 `Double`），全部按仓库里已有的正确写法改成 `Double(...) / 1000`。这批之前从没编译过，所以一直存在。
`tools/swiftlint.js` 加了检查 3（Int64/Double 混比），并用临时文件**验证它会开火**：
注入 `let t = protoSecondsToMs(...)/1000` + `t >= Date().timeIntervalSince1970` → 命中；
`StatsKit:16` 的 `Double(ms)` 正确写法不误报（第一版会报，已修）。


## 第四十批已处置（29 → 20）

**安全洞（本批最重要）**：`IntentLockGate.blockedMessage()` 写好了"锁屏可达时不得产出凭证/PII"的门禁，
但**六个 AppIntent 没有一个调用它**。其中 `OtpIntent.perform()` 直接把可用临时码放进 Siri 的应答文本 ——
设了应用锁的用户，锁屏喊一句"生成临时码"就能拿到能开门的码。已在六个 `perform()` 的第一行统一加
`if let block = IntentLockGate.blockedMessage() { return .result(dialog: block) }`（门禁在冷却之前，
不然的小写：`passCooldown()` 会写冷却键，被锁拒掉时不该消耗冷却槽）。顺带修 `ReadRecordsIntent`
里 `recs.map{...}.enumerated().map { i in recs[i] ... }` —— `i` 是元组却当下标用，又是一处编译不过的代码。

- `LockGuard.traces`(392) → 留痕**写侧一直在写，读侧界面自己摸 key**，函数反而零调用。改成读走 `traces()`，
  清写走新增的 `clearTraces()`，键位归 LockGuard 一处。
- `FirmwareHistory.observations`(755) → 「诊断查阅」页加"本机固件观测点"区，明写"只是这台手机读到过的
  日期与版本，不是门锁完整固件历史"。`ForEach` 先把元组数组转成字符串再 `id: \.self`（元组取不到 keypath）。
- `CredSortKey`/`smartListLabel` 等见第三十九批。
- `newBadgeRow`(831) → 接给本轮新建的 282 向导页。同时修它原来的写法：`DB.store.set` 写在
  `NavigationLink` 的 destination ViewBuilder 里 = 构造视图时改数据，改到 `.onAppear`。
- `LinkSenseKit.stopReconnectLoop` / `stopDeadWatch` → **判定"留着不接"并写明理由**：这个 2s tick 同时是
  AUTOOPEN 的停留判定驱动器（`tickDwell` 在"是否自动回连"偏好判断**之前**执行），关掉自动回连就停循环
  等于悄悄把"靠近自动开锁"也停了，副作用比省电严重；看门狗在未连接时本就惰性 return。
- `Store.autoOpenAudit` / `autoOpenSuspendUntil` → **删**。前者用 `getDict` 取一个存 `[AuditEntry]` JSON 的键，
  类型就不对，取回来必然为空；后者与 `AutoOpen.suspendUntil` 逐字重复。审计族口径全归 AutoOpen。
- `Store.clearFailEvents` → 留着待产品口径：这些标记以 type 0 混进记录时间线（RecordsView 92），
  清空=抹掉用户看得见的历史行，不替用户决定加破坏性按钮。自然出口已有（每锁 50 条滚动 + 删设备按族清）。
- `PidMap.canDeviceInfo` → 删（`canClearPwd` 的同义别名，零调用；同一判断留两个名字会让人以为
  "设备信息"有独立能力口径）。
- `BLEService.advDevice` → 删（连接走 CB 的 `retrievePeripherals(withIdentifiers:)`，不查这个表）。
- `BLEService.peripheralIsReady(toSendWriteWithoutResponse:)` → 空的协议桩，删。
  **我第一版给它写的注释是错的**（写"本 App 只走 withResponse"），实际 291–294 行确有 `.withoutResponse`
  分支（特征不支持写响应时 + 20ms 盲限速）。那个回调本来是该路径的正解（用就绪信号替代固定 sleep），
  但落在 BLE 写时序上，没有编译+真机基线不盲改 → 注释按事实改正并列进待办，不留空桩装作已实现。
- `LinkSenseKit.wakeFailureReason`(130) → 删：同一份"错误文本 → 人话"表已经在用的有两处
  （`classifyFailure` 536 管日志分类，`DiagnosticsView.friendlyFailReason` 133 管界面提示且覆盖面更大）。
  留第三份只会三处漂移。
- `LockService.setValidationMode`(cmd 20) → 留着并记待拍板（要不要给 A/B 模式切换入口）。
  同时修文案矛盾：安全模式说明页写"即可查看并**进行切换**"，而锁信息名片页写"切换请在门锁键盘或联系管理员"，
  实际全仓没有切换入口 → 说明页改成与实现一致的"只显示不切换"。


## 第四十一批已处置（20 → 7，且这 7 条都已写明判定）

**先修工具**：扫描器只数 `App/`，把**只被金标向量测试引用**的协议构建函数误报成死码 ——
`cmd12Echo` / `cmd30GWDeviceName` / `cmd32GWSetIot` 三条在 `Tests/GoldenDiffTests.swift:80/94/108/110` 都有引用，
且 `fixtures/golden.json` 的 `cmds` 里就有这三个键。改成"声明只从 App/ 收集，计数算上 Tests/"，一次去掉 3 条假阳性。

- `isLateNight` ← **672 假日顺延此前整条链空转**：`holidayExtendOn` 只被 `extendedEndHour` 读，
  而 `extendedEndHour` 没人调用 → 顺延从不生效。现把 dayKey 传进判定（三个调用点：RecordSearch 内部一处 +
  记录页两处筛子），并统一用 **649 的归属日键**（凌晨归前一晚），免得两条路径判出两种结果。
- `nightFrom/nightTo` ← 注释写"676 设置可调"，实际**只有读没有写**，全仓没有任何界面能改。补上深夜档下的
  起/止选择器 + 起==止 的"空区间"提示；三个 setter 一律夹到 0...23（UserDefaults 是外部可写面，判定侧不做静默纠错）。
- `pushHistory` ← **"最近搜索 (553)" 区此前永远是空的**：读侧 `history()`/`clearHistory()` 都接好了，
  写侧零调用。接到键盘"搜索"提交 (`.onSubmit`) 与再次选中历史条目时；不随击键写，避免"昨/昨晚"半截词污染。
- `archivedIDs` ← 成员列表原来每个成员调两次 `ext()`，每次整体重解一遍 ext 字典；改成一次取归档集
  （groupTag 那步仍按成员取值，至少砍掉一半重复解码）。
- `houseWin` ← **只有写没有读**：483 页提交后自己看不到登记结果。加"当前已登记"区回显；
  同时修一处过度承诺的注释与 toast —— 原写"凭证 Tab 359 三档预警会自动盯上"，
  而 359 只按凭证 from/to 排通知，从不读 `kf_house_win_` → 改成明写"不参与凭证到期预警"。
- `demoLogsCount`(845) → 演练场样例区加"当前样例条数"。
- `GuidedEmptyView`(包14) → 整族此前零调用，而且**它的自定义 init 只收 3 个必填参数，把合成的 memberwise init
  顶掉了**，于是 step/双按钮/演示链/小管家全族传不进去 = 参数是装饰。删掉该 init 用合成的，
  接进诊断页"暂无日志"空态（主动作=跑一键体检，次动作=去设备页，带 841 小管家）。
  顺手核实：同文件 `EmptyState` 有 3 参与 5 参两个 init，没有同类问题（差点又写错一条注释）。
- `badgeAnniversaryToday`(998) → 接进 `onLaunch`：徽章恰好满一年弹一次时刻卡，onceDone 键带年份防重。
- `setDrillFilter` / `clearDrillFilter` / `wakeFailureReason` / `autoOpenAudit` / `autoOpenSuspendUntil` /
  `canDeviceInfo` / `advDevice` / `peripheralIsReady` / `axHit60` → 删。
  `axHit60` 是 871 的第二份实现（认领行内联写了同样的 `DS.Hit.min + 16`），且它把 contentShape 写死 Rectangle
  而那里要 Capsule；它自己的注释还写着"再留 10pt 余量"而代码是 +16 —— 又一处注释与实现不符。
  `setDrillFilter/clearDrillFilter` 只写 `kf_demo_drillfilter` 一个旗子而全仓无人读 → 接上等于给没人看的旗子加按钮。

**留给你的三条落点/语义**（已进 `NEXT-DECISIONS.md` 组 5）：674 通勤标签与 658 时段词往哪儿放（行内小字会加密度）、
718 单条记录分享卡的分享出口形态、467 移交要不要改成"先挂待接受"。

## 判定口径（后续批次沿用）
1. 接之前必须证明**消费方不是空跑**：识别器/谓词要先有生产者。
2. 分派/查找类代码不得处理不存在的标识；没有生产者的分支删掉并在台账记一句，而不是留着装作能跳。
3. 结构性改动（要改导航持有、要换写路径）在没有编译基线前不盲做，判 PART 并写清缺什么。
4. 同一公式/同一判断只留一处实现；发现零调用的那份与在用的那份重复时**删零调用那份**，不要为了消清单而接线。
5. 文案里的范围承诺必须与检查范围一致（"全库"就得跨锁查，只查本锁就写"本锁"；写"可切换"就得真有切换入口）。
