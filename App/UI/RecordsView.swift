// 记录 Tab (records 页) — 门锁日志 (cmd16 翻页) + 成员过滤 + 归属推断 + 离线缓存
// 离线横幅只在"确实没有一次成功的实时读取"时出现, 不再每次进页都误报未连接。
// 包9 增量: 时间线升级 (578 组头吸顶 / 738 告警行红条+浅红底 / 592 连击合并 /
//           183 成员色点 / 184 开门方式图标 / 655 动词化文案 / 681 农历小字 /
//           679 年份分隔 / 649 凌晨归属 / 590 连续活跃 / 796 第N位使用者 /
//           1016 出行观察 / )+
//           检索 (551/553/554/555/557/562/560/564/571/572/567/568/569/570/574/575/561/770) +
//           告警中心入口 (735 未处置角标) + 详情 (576/577/727/736/737/742, 见 RecordsTimeline.swift)。
// 本批 (第一百八十九批·记录族默认路径):
//   · 576/583/585/586 在「当前锁」视图打通 —— Rec 池原先只在「全部锁」分支赋值, 默认路径恒空,
//     点时间线行永远打不开详情; 行身份从此只经一份算术 (RecordOverlay.oid, RecordSearch.swift:21)。
//   · 582 统计页成员条下钻补上消费点 (pendingRecordsMember 原先全仓零读取方)。
//   · 551 搜索面补进 186 备注与 568 凭证标签, 与搜索框占位文案的承诺对齐。
//   · 593 组尾「全天 N 条」改成**过滤与分页截断之前**的行池口径。
//   · 808 记录空态按原句铺 3 条灰阶示例条目 + 点按弹「真实数据从这里开始」引导卡。
// 纪律: 颜色只经 DS 令牌; 归属类统计一律标"约"; 告警类型只用真实 5 种 (6/7/10/13/224)。
import SwiftUI
import UIKit

struct RecordsView: View {
    @EnvironmentObject var app: AppState
    @State private var groups: [DayGroup] = []
    @State private var damageDays: Set<String> = []  // 596 含防撬/试错锁定/键盘锁定的自然日
    @State private var rows: [RowVM] = []
    @State private var allRows: [RowVM] = []
    @State private var running = false
    @State private var offline = false
    // 18/187 日期快速滚动锚 = 按月跳转 (同一实现，两编号别再各做一个): 筛除式而不是滚动锚定 ——
    // 把 List 包进 ScrollViewReader 要移动整条修饰符链，本机没有编译器时那条重构的代价大于收益。
    @State private var monthJump = ""
    @State private var pullGap: String?   // 749 本次会话未拉全的如实标注
    @State private var reconLine = ""     // 749 对账结果一行 (可复制, 供发给管理员/记进工单)
    @State private var sel = "" // '' 全部 / 成员id / __unknown
    @State private var showAdd = false
    // 716 选区导出: 按天整组勾选 (行级多选不做 —— 一页上千行, 逐行勾选的手势成本远高于按天勾)
    @State private var showRangePick = false
    @State private var rangeSel: Set<String> = []
    // ---------- 包9 检索态 (551/553/554/555/557/560/562) ----------
    @State private var scope = 0             // 561/770: 0 当前锁 / 1 全部锁
    @State private var searchText = ""
    @State private var parsedTags: [String] = []    // 555 解析预览标签
    @State private var highlightTokens: [String] = []  // 557 命中高亮词
    @State private var filters = QueryFilters.load(mac: DB.preferredMac())   // 192 会话保留
    /// 2026-10-18 记录页重构: 筛选面板是否展开。默认 false = 只显示一行摘要。
    @State private var filtersExpanded = false
    /// 2026-10-18: 低频区是否展开。默认收起。
    @State private var secondaryRowsExpanded = false
    @State private var reversed = false       // 570 正序回放
    @State private var detailRec: Rec?        // 576 记录详情 sheet
    // 586 当天全景 / 583 结果定位高亮 —— 两个都是"从别处跳进时间线"的落点，用完即清。
    // dayFocus 是**显示范围**的收窄而不是筛选条件: 它不进 QueryFilters、不进 192 会话保留，
    // 否则会把你"点了一次跳转"写成"你设了一个过滤"。
    @State private var dayFocus = ""
    @State private var flashKey = ""
    /// 598 大数据量分页: 一次参与渲染的行数上限与"是否还有下一批"。
    /// 1200 不是凑数: 一天最忙的家也有几十条，1200 条够铺满几十个日组，
    /// 再往下滚就已经越过"人能在一次会话里读完"的量。
    /// 598 截断上限: 0 = "还没定首页" (applyFilter 第一次跑时按行池量定)。旧写法初始 1200 + 每次 +1200
    /// 看着像分页, 实际上单锁行池 ≤ ~300 条 (kf_logcache_ 上限)、全锁也远够不到 1200 ⇒ 那排「继续加载」
    /// 是永远按不到的死 UI。改成"池量分档": ≤600 全显; >600 先显 600、每按一次 +600。
    @State private var shownCap = 0
    @State private var capped = false
    @State private var filteredTotal = 0
    /// 583 的一个真缺陷 (自己写完才看到): 深链落地时详情卡是**开着**的，
    /// 当场 flashRow 等于在一层不透明的 sheet 后面闪完 1.2 秒 —— 用户关掉时什么都看不到。
    /// 所以落地时只**记下待闪的行**，等 sheet 关闭再闪。
    @State private var flashOnClose = ""
    @State private var scrolledRow: String? = nil
    // 185/597 左滑(前缘/后缘两个方向)共用的行备注弹窗目标 + 草稿
    @State private var noteTarget: RowVM? = nil
    @State private var noteDraft = ""
    @State private var showActiveCreds = false  // 574 活跃凭证排序
    @State private var showOutWin = false      // 575 越界开门清单
    @State private var showAlarmKinds = false // 565 告警类型多选面板
    @State private var recPool: [Rec] = []    // 跨锁/单锁 Rec 池 (576 详情查找 + 770 行映射 + 580/584 翻页源)
    /// 593 组尾「全天 N 条 / 当日最晚」的可核口径: 取本次**过滤与分页截断之前**的行池按归属日算一次。
    /// 原先这两个数取自 g.rows —— 那是筛过、截过的显示集, 于是每设一次过滤就在谎报"今天只有 3 条"。
    @State private var dayFullCount: [String: Int] = [:]
    @State private var dayLatest: [String: String] = [:]

    struct RowVM: Identifiable {
        var key: String
        var time: String      // 左侧时间轴显示 (今天只显示 HH:mm)
        var dayKey: String    // 分组键 (yyyy-MM-dd, 649 凌晨已归前一晚)
        var hour: Int = -1    // 实际时刻的小时 (564/572 时段判定, -1 = 未知)
        var type: Int = 0     // 锁日志类型 (569 失败口径: 10/13/224)
        var title: String     // 主文案 (655 动词化)
        var whoId: String?
        var whoKind: String? = nil   // 793 访客虚拟分组判定 (temp 且 whoId 为空)
        var kind: String? = nil       // 184 开门方式图标 (fp/pwd/temp/key)
        var lockName: String = ""     // 770 全部锁时行首小标签
        var rowMac: String = ""       // 归属锁 (577 跨锁跳凭证)
        var credKey: String = ""      // 577 来源凭证深链 (pwd:N / fp:N)
        var winText: String = ""      // 575 越界窗口小字 (约)
        var warn: Bool
        var claim: Bool = false      // 791 可认领 (未归属且认领表还没有它)
        var care: Bool = false       // 1028: 保养/换电手机侧事件行
        /// 行的身份 = 「哪把锁的哪一行」, 与 186/585/583 用的是同一份算术 (`RecordOverlay.oid`, 全仓只这一处拼接)。
        /// 原先等于 `key`: 单锁路径的 key 不带 mac 前缀, 而深链与定位带回来的都是 oid ⇒
        /// 583 的滚动锚与闪框、585 的落点在默认视图 (scope == 0) 里永远对不上任何一行。
        var id: String { RecordOverlay.oid(mac: rowMac, rowKey: key) }
    }

    /// 按天分组, 让"最近开门"从平铺列表变成可扫读的时间线
    struct DayGroup: Identifiable {
        var key: String
        var rows: [RowVM]
        // 657 无记录日 / 675 假期外出分隔行: 这不是"一天的组"而是**缺口的描述**。
        // 键刻意加 "gap-" 前缀保证 Identifiable 不撞车; 也因此故意让 date/holiday 这些派生量取不到 ——
        // 缺口行不该被当成某天有档案。渲染只走 gapRow()，不进 daySection()。
        var isGap = false
        var gapDays = 0
        var gapHoliday: String? = nil
        var id: String { key }
        var date: Date? { RecordSearch.dateFromKey(key) }
        var isNone: Bool { key == "__none" }
        var hasNight: Bool { rows.contains { $0.hour >= 0 && $0.hour < 5 } }   // 649 含次日凌晨
        var holiday: String? { isNone ? nil : RecordSearch.holidayName(key) }
        /// 594 日型: 节假日橙 / 周末青绿 / 工作日靛蓝。补班日按工作日算 —— 它是"休息的日子却要上班",
        /// 与放假日共用同一份数据源但语义相反 (掺进橙档会把"这天开门多是正常的"读反)。
        enum DayKind {
            case workday, weekend, holiday
            var color: Color {
                switch self {
                case .holiday: return DS.Palette.warn
                case .weekend: return DS.Palette.dayKindWeekend
                case .workday: return DS.Palette.dayKindWorkday
                }
            }
            var ax: String {
                switch self {
                case .holiday: return "节假日"
                case .weekend: return "周末"
                case .workday: return "工作日"
                }
            }
        }
        var dayKind: DayKind? {
            guard !isNone, let d = date else { return nil }
            if holiday != nil { return .holiday }
            if RecordSearch.isMakeupWorkday(key) { return .workday }
            let wk = WeekCal.gregorian.component(.weekday, from: d)
            return (wk == 1 || wk == 7) ? .weekend : .workday
        }
        var lunarLabel: String? { isNone ? nil : Self.lunar(key) }
        var distinctUsers: Int { Set(rows.compactMap(\.whoId)).count }
        static func lunar(_ key: String) -> String? {
            guard let d = RecordSearch.dateFromKey(key) else { return nil }
            var c = Calendar(identifier: .chinese)
            c.timeZone = TimeZone.current
            let m = c.component(.month, from: d)
            let day = c.component(.day, from: d)
            guard m >= 1, m <= 12, day >= 1, day <= 30 else { return nil }
            let mn = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "腊"]
            let dn = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                      "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                      "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
            return mn[m - 1] + "月" + dn[day - 1]
        }
    }

    /// 无锁占位 —— 2026-10-13 run 63 从 body 的 Group 分支抽出 (该表达式报 type-check 超时)
    @ViewBuilder
    private var noLockPlaceholder: some View {
        EmptyState(systemImage: "list.bullet.rectangle",
                   title: "还没有添加门锁",
                   message: "开门与操作记录存在门锁内。请先添加并配对门锁，再回到这里读取。",
                   actionTitle: "去添加门锁") { showAdd = true }
    }

    /// 记录页主体列表 —— 2026-10-13 run 63 从 body 的 Group else 分支抽出:
    /// 整个 body 表达式报 type-check 超时。
    @ViewBuilder
    private var mainList: some View {
        List {
            if offline { jumpBackRow }
            // ─────────────────────────────────────────────────────────────
            // 2026-10-18 重构: 列表前方原来叠了 **14 个区** ——
            //   scopeRow / searchBar / monthJumpRow /
            //   dayFocusBanner / resultCount / filterChips / memberChips / doorGods /
            //   emptyHint / runningRow / dropWatchSection / lastYearTodayRow
            // 记录列表被推到屏幕外, 这就是"记录页很乱"的真正来源。
            //
            // 现在按三条判据收敛 (不是删功能, 是分级):
            //   · **常驻 3 个**: 今日摘要 / 范围(当前锁·全部锁) / 搜索
            //   · **按需 2 个**: 日期跳转(选了月才显示) / 结果计数(有筛选才显示)
            //   · 其余全部**收进"更多"或移到列表之后**: 生日条 / 成员 chip / 门神 / 掉电观察 / 去年今日
            // ─────────────────────────────────────────────────────────────
            scopeRow
            searchBar
            monthJumpRow
            dayFocusBanner   // 586 只看某天时必须给"看全部日子"的退出入口
            if !searchText.isEmpty || activeFilters { resultCount }
            filterChips          // 已折叠为一行摘要 + 可展开面板 (见 filterChips 注释)
            // 低频区: 收进一行"更多"之后, 不再占首屏
            secondaryRowsDisclosure
            // 187 按月跳转 (等价实现): 选月即只看该月, 顶部有清除口。
            // 原设计的"月份滚轮 + scrollTo"需把 List 包进 ScrollViewReader 并移动整条修饰符链,
            // 在这个从未编译过的工程里做结构性改动的风险不对等 → 记入需编译器清单, 这里先给可用能力。
            ForEach(groups.filter { g in (monthJump.isEmpty || g.key.hasPrefix(monthJump)) && (dayFocus.isEmpty || g.key == dayFocus) }) { g in
                // 657: 缺口行走独立的极简一行，不冒充一天的组头 (它没有"当天 N 条"可说)
                if g.isGap { gapRow(g) } else { daySection(g) }
            }
        }
        // 583 定位滚动: iOS 18+ 的 List 行锚位。绑的是**行 id** (oid = mac#行键)，
        // 所以"滚到那一天的附近"与"滚到那一行"在 API 层面不是同一件事 ——
        // 闪一下的高亮 (flashKey) 才是保证用户认得出"是这条"的那一半; 滚动本身若落在
        // 相邻行 (组头高度/回收布局都会影响)，验收单里写明那不算数据缺陷。
        .scrollPosition(id: $scrolledRow)
    }

    /// 记录页右上角工具栏 (从 body 内联的 .toolbar 里抽出: 该表达式报 type-check 超时)。
    /// 工具栏内容是 ToolbarContent ⇒ 用 @ToolbarContentBuilder。
    @ToolbarContentBuilder
    private var recordsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            // 读取中把刷新按钮换成进度圈, 状态一目了然
            if running {
                ProgressView()
                    .accessibilityLabel("正在读取门锁记录")
            } else {
                Button { Task { await fetch() } } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("重新读取门锁记录")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                if app.current != nil {
                    Button { copyLastWeekDigest() } label: { Label("复制上周小结", systemImage: "doc.on.clipboard") }   // 698 复制上周小结
                    Button { showRangePick = true } label: { Label("选区导出", systemImage: "checklist") }   // 716 选区导出
                    Button { showActiveCreds = true } label: { Label("活跃凭证排序 (约)", systemImage: "list.number") }
                    Button { showOutWin = true } label: { Label("越界开门清单 (约)", systemImage: "clock.badge.exclamationmark") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多")
        }
    }

    var body: some View { vkBody.destined(.records) }
    var vkBody: some View {
        recordsChrome
    }

    /// 记录页二选一 (无锁占位 / 主体列表) —— 从 recordsCore 拆出: 该表达式报 type-check 超时
    @ViewBuilder
    private var recordsGroup: some View {
        if app.current == nil {
            noLockPlaceholder
        } else {
            mainList
        }
    }

    /// 记录页核心内容 (Group + 页面级修饰符) —— 从巨型 body 拆出: 原表达式报 type-check 超时
    @ViewBuilder
    private var recordsCore: some View {
        // 2026-10-13 run 69: 原来这里是 `Group { if… }` —— Group 包一层再叠修饰符仍报 type-check 超时;
        // 改成 @ViewBuilder 计算属性 (无 Group 包装), 分支类型由构建器收成 _ConditionalContent。
        recordsGroup
        .navigationTitle("记录")
        // 192: 过滤组合按锁留存 (清空全部过滤时自动删键, 不留脏值)
        // 2026-10-15 走查: 只存"与开场值不同"的组合。唯一的理由是 onRecordsAppear 里那次
        // **按 908 策略的重取** —— fresh/alarm 两档下 load() 返回的是**派生值** (空白 / 仅告警),
        // 原样存回去会把用户真存着的那份覆盖掉, fresh 档更会直接删键
        // (save 里 `self == QueryFilters()` 走 remove)。
        // 换锁那一路不必在这里补: 父层的 `RecordsView().id(app.currentMac)` 会让整页重建,
        // @State 连同 filters 一起重读 (见 LockKeeperApp 里 credentialsTabContent 那段注释)。
        .onChange(of: filters) { _, new in
            let mac = DB.preferredMac()
            guard !mac.isEmpty, new != QueryFilters.load(mac: mac) else { return }
            new.save(mac: mac)
        }
        .variantList()
        .dsScreenBackground()
        .toolbar {
            recordsToolbar
        }
        .onAppear { onRecordsAppear() }
        // 从设备页/矩阵点另一把锁回来时 allRows 还是旧锁的、recPool 已是新锁的
        // ⇒ 点行命中"这条记录不在当前显示范围里"的兜底 toast，看起来像数据丢了。
        .onChange(of: app.currentMac) { _, _ in
        }
        .onChange(of: app.pendingSearch) { _, q in
            guard let q else { return }
            landSearch(q)
        }
        .onChange(of: app.pendingRecordKey) { _, k in
            guard let k else { return }
            landRecordKey(k)
        }
        .onChange(of: app.pendingRecordsDay) { _, d in
            guard let d else { return }
            landDay(d)
        }
        .onChange(of: app.pendingFlashKey) { _, k in
            guard let k else { return }
            landFlash(k)
        }
        .onChange(of: app.pendingRecordsFilter) { _, f in
            guard let f else { return }
            sel = f
            applyFilter()
        }
        .onChange(of: app.pendingRecordsMember) { _, m in
            // 582 图表下钻: 统计页已随本轮删减移除, 这条落点保留给其它来源。
            // 所以点成员条跳过来什么也没发生。落点在 landMember —— 与点成员 chip 走同一条过滤链。
            guard let m else { return }
            landMember(m)
        }
        .onChange(of: scope) { _, s in
            sel = ""
            searchText = ""
            parsedTags = []
            highlightTokens = []
            filters = QueryFilters()
            reversed = false
            applyFilter()
        }
        .onChange(of: filters) { applyFilter() }
        .onChange(of: reversed) { applyFilter() }
        .onChange(of: searchText) { _, t in
            let q = RecordSearch.parse(t)
            parsedTags = q.parsedTags
            highlightTokens = q.must
            applyFilter()   // 562 边输入边更新
        }
    }

    /// 记录页外层 (导航栈 + 弹窗/弹框) —— 同上, 继续拆
    @ViewBuilder
    private var recordsChrome: some View {
        NavigationStack {
            recordsCore
        }
        .sheet(isPresented: $showAdd) { AddDeviceView() }
        // 185/597 行备注弹窗: 前缘(597)与后缘(185)两个滑出都把目标装进 noteTarget, 共用这一只
        .alert("行备注 (最多 60 字)", isPresented: Binding(
            get: { noteTarget != nil },
            set: { if !$0 { noteTarget = nil } }
        )) {
            TextField("只存这台手机", text: $noteDraft)
            Button("取消", role: .cancel) { noteTarget = nil }
        } message: {
            Text("备注跟着这一行 (锁 + 行标识) 走, 不写进锁端日志; 详情页里也能改。")   // 576 备注跟着这一行
        }
        .sheet(isPresented: $showRangePick) { rangePickSheet }
        .sheet(isPresented: $showActiveCreds) { ActiveCredsSheet() }
        // 565 告警类型多选: 选中集直接写回 filters (走既有 onChange(of: filters) → applyFilter)
        .sheet(isPresented: $showAlarmKinds) { AlarmKindsSheet(sel: $filters.alarmKinds) }
        .sheet(isPresented: $showOutWin) { OutWinSheet() }
        .sheet(item: $detailRec) { rec in
            // 186/188 备注与标旗在详情卡里改, 关闭时要让时间线重算 (沿用 735 的 alarmTick 刷新机制)
            // 580/584: 把**当前显示顺序**交给详情卡，上下条与邻近横滑才走在用户刚才看到的那份结果里
            RecDetailSheet(rec: rec, siblings: displayedRecs, scopeAll: scope == 1)
                .onDisappear {
                    // 583: 详情关了才滚+闪 (见 flashOnClose)
                    if !flashOnClose.isEmpty {
                        let k = flashOnClose
                        flashOnClose = ""
                        flashRow(k)
                    }
                }
        }
    }

    private var macs: [String] { scope == 1 ? DB.keychains().map { $0.mac } : [mac] }
    private var activeFilters: Bool {
        filters.segment != 0 || filters.dayKind != 0 || filters.lateNight || filters.alarmOnly
    }

    /// 749 对账结果导出一行 (拍板 #28)。只说本次会话内的事实, 而且**三种结论都要有对应措辞**:
    /// 拉全 / 未拉全 (带剩余条数) / 锁端没报告剩余所以不可判 —— 最后一种最容易被写成"已拉全"。
    /// 复制走 UIPasteboard 的普通文本路径 (不含口令等敏感值)。
    @ViewBuilder
    private var searchBar: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                    // 551: 这句占位文案承诺的三段 (成员 / 凭证 / 备注) 由 `RecordSearch.searchFace`
                    // 一处定义、在 applyFilter 的检索块里落地 —— 少一段就是让用户搜一个搜不到的热区。
                    TextField("搜索: 成员 / 凭证 / 昨晚 告警 / +指纹 -临时码", text: $searchText)   // 551/554/555 搜索
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            parsedTags = []
                            highlightTokens = []
                            applyFilter()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .accessibilityLabel("清空搜索")
                        .frame(minWidth: DS.Hit.min, minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    }
                }
                .padding(DS.Space.s)
                // 2026-10-14 材质统一批次: 搜索框**保持实底**。它在 Section 里 (这一页是 List),
                // 行组本身已经是一层玻璃面 —— 再给行里的控件上玻璃就是玻璃叠玻璃, 接缝全在字底下。
                // @layout-allow 面板实底
                // @layout-allow VK豁免 控件可识别性: 带 hairline 的输入框底衬，同上
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))

                // 554/555 解析出的条件标签 (时间短语 / 加减词 / 告警 / 失败)
                if !parsedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.xs) {
                            ForEach(Array(parsedTags.enumerated()), id: \.offset) { _, tag in
                                Text(tag)
                                    .vkFont(.caption2, weight: .medium)
                                    .lineLimit(1)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .padding(.horizontal, DS.Space.xs + 2)
                                    .padding(.vertical, 2)
                                    .variantPlate(DS.Palette.accentText.opacity(0.10), .capsule)
                                    .frame(maxWidth: 160)
                            }
                        }
                        .padding(.vertical, DS.Space.xxs)
                    }
                }
                // 2026-10-26 精简：「我的过滤」（命名视图）已删（用户确认）。
            }
        } header: {
            HStack(spacing: DS.Space.s) {
                Text("搜索")   // 551 搜索
                Spacer(minLength: DS.Space.s)
            }
        }
    }
    // 2026-10-26 精简：命名视图保存（saveAsView）已删（用户确认）。

    /// 562 实时计数 "约 N 条" (归属口径标"约", 边输入边更新)
    @ViewBuilder
    private var resultCount: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                // 2026-10-13 run 63: 原来把三段拼接 + 两个三元全内联进 Text, 报 type-check 超时。
                // 先算好再拼。
                let head = searchText.isEmpty ? "筛选后约 " : "命中约 "
                let tail = searchText.isEmpty ? "" : " · 实时"   // 562 实时
                let cap = capped ? " · 本页已加载 \(rows.count)" : ""
                Text(head + String(filteredTotal) + " 条" + tail + cap)
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer(minLength: DS.Space.s)
                // 573 条件计数与重置: 叠了几层过滤要说得出来，并一键回到空白起点。
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount) 项条件")
                        .vkFont(.caption2.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(DS.Palette.accentText)
                    Button("重置") {
                        sel = ""
                        searchText = ""
                        filters = QueryFilters()      // 其余联动靠既有 onChange(of: searchText/filters) 重算，不另起一次 applyFilter
                    }
                    .vkFont(.caption2, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                }
            }
                // 2026-10-26 精简：搜索建议下拉已删（suggestions 已移除）。
        }
    }

    /// 573 生效条件数。**不含 scope**: 单锁↔全部锁是"看哪本台账"而不是过滤条件，
    /// 算进去等于让重置按钮谎报它把范围也清掉了 (它不会，也不该)。
    private var activeFilterCount: Int {
        var n = 0
        if filters.segment != 0 { n += 1 }
        if filters.dayKind != 0 { n += 1 }
        if filters.lateNight { n += 1 }
        if filters.alarmOnly { n += 1 }
        if !filters.alarmKinds.isEmpty { n += 1 }
        if !filters.kind.isEmpty { n += 1 }
            // 2026-10-26 精简：「失败筛选」说明与「清空本机失败标记」已删（用户确认）。
        if !sel.isEmpty { n += 1 }
        if !searchText.isEmpty { n += 1 }
        return n
    }

    // 2026-10-26 精简：搜索建议补全（suggestions）已删（用户确认）。

    /// 561/770 跨锁范围切换: 单锁/全部锁; 全部锁时行首带锁名小标签 (770)
    @ViewBuilder
    private var scopeRow: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                Text("范围")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                Picker("搜索范围", selection: $scope) {   // 561 搜索范围
                    Text("当前锁").tag(0)
                    Text("全部锁").tag(1)   // 770 全部锁
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if scope == 0, DB.keychains().count > 1 {
                    // 191 按锁切换: 走 AppState.select (清实时状态 + 重读快照), 不自己改 currentMac
                    Menu {
                        ForEach(DB.keychains()) { kc in
                            Button { app.select(kc.mac) } label: {
                                Label(LockArchive.displayName(kc) + (kc.mac == mac ? " · 当前" : ""),
                                      systemImage: kc.mac == mac ? "checkmark.circle.fill" : "lock")
                            }
                        }
                    } label: {
                        Label("换锁", systemImage: "arrow.left.arrow.right.circle")   // 191 换锁
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                    .accessibilityLabel("切换当前锁，当前为 \(app.displayName)")
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
        }
    }

    // 17 筛选 chips (原句"Spotify 式筛选 chips") = 下面这一整行 chip，与 564/571/572/567/568/569/570 同一处。
    // 不另建一套"chips 组件": 同一页两种筛选外观，用户会以为它们是两个功能、两套状态。
    // ---------- 包9: 筛选 chip 行 (564/571/572/567/568/569/570) ----------
    private static let kindOptions: [(String, String)] = [("全部凭证", ""), ("指纹", "fp"), ("密码", "pwd"), ("临时码", "temp"), ("数字钥匙", "key")]

    /// 筛选区 —— 2026-10-18 按 PageGrammar 规则 3 重构。
    ///
    /// 重构前: **5 行筛选片全部常驻展开** (时段 / 工作日周末 / 凭证类型 / 告警四连 / 说明),
    /// 首屏被筛选占掉大半, 用户要看的"记录"被推到下面 —— 这就是截图里那堆 chip 的来源。
    ///
    /// 重构后:
    ///   · 默认只留**一行摘要**: 「全部记录」或「时段·工作日·密码·仅告警 (4)」+ 调整入口
    ///   · 点摘要才展开完整筛选面板 (原来那 5 行原样保留在里面, 判据一点没改)
    ///   · 有意向筛选时摘要会显示已启用项数, 不让人忘了自己筛过什么
    ///
    /// 为什么不是删掉低频筛选项: 它们是真功能 (567/565/570 都是拍板过的),
    /// 问题从来不是"有这些筛选", 而是"它们一直摊在首屏"。
    @ViewBuilder
    private var filterChips: some View {
        Section {
            Button {
                withAnimation(DS.Motion.quick) { filtersExpanded.toggle() }
                DS.Haptics.tick.impactOccurred()
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .accessibilityHidden(true)
                    Text(filterSummary)
                        .vkFont(.subheadline, weight: activeFilterCount > 0 ? .semibold : .regular)
                        .lineLimit(1)
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .vkFont(.caption2, weight: .semibold)
                            .foregroundStyle(DS.Palette.onAccent)
                            .padding(.horizontal, DS.Space.xs)
                            .frame(minHeight: 18)
                            .background(DS.Palette.accentText, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSub)
                }
                .foregroundStyle(activeFilterCount > 0 ? DS.Palette.accentText : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("筛选: \(filterSummary), 点按\(filtersExpanded ? "收起" : "展开")全部筛选项")

            if filtersExpanded {
            // 2026-10-26 精简：仅告警 / 告警类型多选 / 失败筛选 / 正序回放 四枚 chip 已删（用户确认）。
            // 2026-10-26 精简：「失败筛选」整块（含清空失败标记）已删（用户确认）。
            // 676/672: 深夜区间的"可调"此前只写在注释里, 界面上没有任何入口 (两个键只有读没有写)。
            // 只在选了"深夜预设"这一档时出现 —— 它是这档的定义, 不该常驻在筛选行里。
            if filters.segment == 4 {
                HStack(spacing: DS.Space.s) {
                    Text("深夜区间").vkFont(.caption).foregroundStyle(DS.Palette.textSub)   // 676 深夜区间
                    Spacer(minLength: DS.Space.s)
                    Picker("起点", selection: Binding(get: { RecordSearch.nightFrom },
                                                      set: { RecordSearch.setNightFrom($0) })) {
                        ForEach(0..<24, id: \.self) { Text("\($0) 时").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 96)
                    Text("→").vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    Picker("终点", selection: Binding(get: { RecordSearch.nightTo },
                                                     set: { RecordSearch.setNightTo($0) })) {
                        ForEach(0..<24, id: \.self) { Text("\($0) 时").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 96)
                }
                .frame(minHeight: DS.Hit.min)
                if RecordSearch.nightWindowDegenerate {
                    Text("起点与终点相同 = 空区间, 这一档筛不出任何记录。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VariantToggle("节假日当日顺延 2 小时", isOn: Binding(get: { RecordSearch.holidayExtendOn },   // 672 节假日当日顺延
                                                                   set: { RecordSearch.setHolidayExtend($0) }))
                    .vkFont(.caption)
                    .frame(minHeight: DS.Hit.min)
                Text("顺延只影响深夜档的判定, 不改记录的归属日 (凌晨仍归前一晚)。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 复位按钮: 原来是 section header 里的附属品, 现在面板展开时放在顶部一行
            if activeFilters {
                HStack(spacing: DS.Space.s) {
                    Text("筛选")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Spacer(minLength: DS.Space.s)
                    Button("复位") {
                        filters = QueryFilters()
                        reversed = false
                    }
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            }
        }
        }
    }

    /// 一行摘要: 没筛选时是「全部记录」, 有筛选时列出已启用项。
    private var filterSummary: String {
        var parts: [String] = []
        if filters.segment != 0 {
            let names = ["全部", "早 6-9", "午 10-14", "晚 15-21", "深夜"]
            parts.append(names.indices.contains(filters.segment) ? names[filters.segment] : "时段")
        }
        if filters.dayKind != 0 { parts.append(filters.dayKind == 1 ? "工作日" : "周末") }
        if !filters.kind.isEmpty {
            parts.append(Self.kindOptions.first { $0.1 == filters.kind }?.0 ?? "类型")
        }
        if filters.alarmOnly { parts.append("仅告警") }
        if !filters.alarmKinds.isEmpty { parts.append("告警 \(filters.alarmKinds.count) 类") }
        if reversed { parts.append("最早在前") }
        return parts.isEmpty ? "全部记录" : parts.joined(separator: " · ")
    }

    /// 低频区折叠入口 —— 2026-10-18 记录页重构新增。
    ///
    /// 生日条 / 成员筛选 chip / 门神 / 掉电观察 / 去年今日 这五块不是不重要,
    /// 而是不是每次进记录页都要看。原来全部常驻在列表前, 首屏被它们占满。
    /// 现在收进一个可展开区: 默认收起, 展开后与原来逐字一致。
    @ViewBuilder
    private var secondaryRowsDisclosure: some View {
        Section {
            Button {
                withAnimation(DS.Motion.quick) { secondaryRowsExpanded.toggle() }
                DS.Haptics.tick.impactOccurred()
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .accessibilityHidden(true)
                    Text(secondaryRowsSummary)
                        .vkFont(.footnote)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: secondaryRowsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                }
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多记录视图")

            if secondaryRowsExpanded {
                memberChips
                lastYearTodayRow
            }
        }
    }

    /// 折叠行上的一行说明: 只列现在真有内容的那几块, 空的不占字。
    private var secondaryRowsSummary: String {
        var parts: [String] = []
        if !DB.members().isEmpty { parts.append("成员筛选") }
        return parts.isEmpty ? "更多视图" : parts.joined(separator: " · ")
    }

    private func chipRowSection(_ title: String, selected: Int, items: [(String, Int)], pick: @escaping (_ name: String, _ i: Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        miniChip(item.0, on: selected == item.1) { pick(item.0, item.1) }
                    }
                }
                .padding(.vertical, DS.Space.xxs)
            }
        }
    }
    private func miniChip(_ name: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.tick.impactOccurred()
            tap()
        } label: {
            Text(name)
                .vkFont(.footnote, weight: .medium)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, DS.Space.m)
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
    private func chipToggle(_ title: String, on: Binding<Bool>) -> some View {
        Button {
            DS.Haptics.tick.impactOccurred()
            on.wrappedValue.toggle()
        } label: {
            Text(title)
                .vkFont(.footnote, weight: .medium)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, DS.Space.m)
                .background(on.wrappedValue ? DS.Palette.danger.opacity(0.12) : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(on.wrappedValue ? DS.Palette.danger.opacity(0.4) : DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on.wrappedValue ? DS.Palette.danger : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    @ViewBuilder   // 编译级修正: 这块是"顶层 if 而没有 else/return", 不加 builder 就是一句 "function declares some View…" 的编译错误
    /// 716 选区导出: 按**天**整组勾选 → 合并成一份 CSV (进剪贴板, 与 698 同一通路)。
    /// 行级多选刻意不做: 时间线一页上千行, 逐行勾选的手势成本远高于"按天勾"这种整组选择 (原句的"整组"正是这一档);
    /// 凭证 Tab 那套多选 (1518) 是"列表行 + 批量动作", 与这里"导出选区"不是同一件事, 不硬搬。
    private var rangePickSheet: some View {
        NavigationStack {
            List {
                Section {
                    let days = Array(Set(allRows.map { $0.dayKey })).sorted(by: >)
                    if days.isEmpty {
                        Text("当前没有可导出的记录行。")
                            .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(days, id: \.self) { d in
                        let n = allRows.filter { $0.dayKey == d }.count
                        VariantToggle("\(d) · \(n) 条", isOn: Binding(
                            get: { rangeSel.contains(d) },
                            set: { on in if on { rangeSel.insert(d) } else { rangeSel.remove(d) } }))
                            .frame(minHeight: DS.Hit.min)
                    }
                } header: {
                    Text("按天勾选")   // 716 按天勾选
                } footer: {
                    Text("只导出勾选那些天的行; CSV 走剪贴板, 不上传、不落盘。")
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                }
                Section {
                    Button("全选") { rangeSel = Set(allRows.map { $0.dayKey }) }
                    Button("清空") { rangeSel = [] }
                }
            }
            .navigationTitle("选区导出")   // 716 选区导出
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("复制 CSV") { copyRangeCSV() }.disabled(rangeSel.isEmpty)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { showRangePick = false }
                }
            }
        }
    }
    private func copyRangeCSV() {
        func esc(_ s: String) -> String {
            s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        let rows = allRows.filter { rangeSel.contains($0.dayKey) }
        guard !rows.isEmpty else { app.showToast("选中的天里没有记录行"); return }
        var out = ["日期,时间,内容,成员,锁"]
        for r in rows.sorted(by: { ($0.dayKey, $0.time) < ($1.dayKey, $1.time) }) {
            let who = r.whoId.flatMap { DB.member($0)?.name } ?? "未归属"
            out.append([esc(r.dayKey), esc(r.time), esc(r.title), esc(who), esc(r.lockName)].joined(separator: ","))
        }
        Clip.set(out.joined(separator: "\n"))
        app.showToast("已复制 \(rows.count) 行 CSV")   // 716 已复制
    }

    /// 698 上周小结: 上一个完整自然周 (周一–周日) 的 CSV + 三句话摘要, 一起进剪贴板。
    /// 归属口径与 799 同源 (Attribution 可证明才计成员, 带"约"); 缓存只留 300 条, 拿不到就如实说。
    private func copyLastWeekDigest() {
        let m = StatsKit.build(mac: app.currentMac)
        let d = m.lastWeekDigest()
        let text = d.lines.joined(separator: "\n") + "\n\n" + d.csv
        Clip.set(text)
        let rows = max(d.csv.split(separator: "\n").count - 1, 0)
        app.showToast("已复制上周小结: \(d.lines.count) 句摘要 + \(rows) 行 CSV")   // 698 已复制上周小结
    }

    /// 1040 掉电观察行: 采样表里"同一本地日掉电 > 20 个百分点"的日子, 在时间线顶部插一行提示。
    /// 数据只有采样表 (读 03 时落点), 口径 = 本机量到的两个点之差, 不拟合不外推; 无命中时整块不出现。
    // 2026-10-27 二轮精简：dropWatchSection（掉电观察行）已删（bigDropDays 移除）。

    /// 654 去年今日: 时间线顶部的偶发入口 —— 同一月日在去年有开门记录时出一行。
    /// 数据源就是本机日志缓存 (≤300 条), 所以只有"这一年里本机读到过"才可能出现; 没读到就不出现, 不假装。
    @ViewBuilder
    private var lastYearTodayRow: some View {
        let n = lastYearTodayCount
        if n > 0 {
            Section {
                Label {
                    Text("去年今日: \(n) 条开门记录")   // 654 去年今日
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "calendar.badge.clock").accessibilityHidden(true)
                }
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.accentText)
            }
        }
    }
    private var lastYearTodayCount: Int {
        let cal = WeekCal.gregorian
        guard let last = cal.date(byAdding: .year, value: -1, to: Date()) else { return 0 }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MM-dd"
        let key = fmt.string(from: last)
        return DB.readLogs(mac).filter { l in
            l.lockTimeStr.count >= 10 && String(l.lockTimeStr.dropFirst(5).prefix(5)) == key
        }.count
    }

    private var firstLogDay: String? {
        DB.readLogs(mac).compactMap { $0.lockTimeStr.isEmpty ? nil : String($0.lockTimeStr.prefix(10)) }.min()
    }
    private func chineseDay(_ key: String) -> String {
        let p = key.split(separator: "-")
        return p.count == 3 ? "\(p[0])年\(Int(p[1]) ?? 0)月\(Int(p[2]) ?? 0)日" : key
    }

    private var mac: String { app.current?.mac ?? "" }
    private var syncStampKey: String { "kf_logsync_" + mac }
    private var totalCount: Int { allRows.count }
    private var todayKey: String { Self.dayKey(Date()) }

    // ---------- 顶部状态条 ----------
    private var cachedHint: String {
        if let at = lastSyncAt() {
            return "未连接门锁 — 以下为本地缓存（读取于 " + Self.stamp.string(from: at) + "）。连接锁后点「重新读取」刷新。"
        }
        return "未连接门锁 — 以下为本地缓存，读取时间未知。连接锁后点「重新读取」刷新。"
    }
    /// 136 补充 跨页跳回: 记录/告警页一键跳回设备页定位该锁
    @ViewBuilder
    private var jumpBackRow: some View {
        Section {
            Button {
                app.pendingJumpLock = mac
                app.requestRoute(.device)
            } label: {
                Label("跳回设备页定位「" + LockArchive.displayName(app.devices.first { $0.mac == mac } ?? Keychain(mac: mac, skey: "")) + "」", systemImage: "lock.rotation")
            }
            .vkFont(.footnote)
            .foregroundStyle(DS.Palette.accentText)
        }
    }
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private func lastSyncAt() -> Date? {
        let raw = DB.store.getString(syncStampKey)
        guard let t = Double(raw), t > 0 else { return nil }
        return Date(timeIntervalSince1970: t / 1000)
    }

    // ---------- 时间线 (包9 升级: 578 组头吸顶 / 738 告警行 / 592 连击 / 655 动词 / 679 年份 / 681 农历 / 649 凌晨) ----------
    /// 578 List Section header 即原生吸顶 — 滚动时组头钉在顶部, 跨组自动交接
    /// 579 回到最新浮层按钮 = 由这条吸顶覆盖 (拍板口径，不是漏做): 无论回翻到哪里，
    /// 当前属于哪一天始终钉在屏幕顶部可读，再放一枚"回到最新"的浮层按钮只是把列表往回弹，
    /// 而它换来的信息组头已经在告诉用户了。真要按钮得连 ScrollViewReader 一起改 (见 §130 那条风险记录)。
    private func daySection(_ g: DayGroup) -> some View {
        // 653 生日组头: 该成员生日日 (MM-dd 命中组头日期) → "今日是妈妈的生日"标签
        let bday = g.key.count == 10 ? String(g.key.suffix(5)) : ""
        let hasAlarm = g.rows.contains(where: \.warn)
        let openN = g.rows.filter { StatsKit.openTypes.contains($0.type) || $0.kind != nil }.count
        let alarmN = g.rows.filter(\.warn).count
        // 589 组内告警置顶: 有告警的日子把告警行提到组首，其余保持它原来的顺序。
        // 为什么不用 `sorted(by:)`: Swift 的比较排序**不保证稳定**，而"其余按原时间随后"这条要的是稳定性 ——
        // 拆成两段再拼是确定性的，还省掉整组比较。
        let ordered = g.rows.filter(\.warn) + g.rows.filter { !$0.warn }
        // 593 日界收尾: 最晚时刻与全天条数都取自 applyFilter 里**过滤与分页截断之前**的行池
        // (`dayLatest` / `dayFullCount`), 因为组尾那句「全天 N 条」说的是这一天, 不是"这一天还剩几行给我看"。
        // 为什么不用 `ordered.last`: 589 刚把告警行提到组首，"显示上的末条"与"一天里最晚的一条"从此不是一回事，
        // 拿前者当后者会在每个有告警的日子说错话。
        // 为什么不用 `g.rows`: 那是筛过、又被 598 截过的一页 —— 原来这句文案写的正是 g.rows.count,
        // 于是每设一次过滤, "全天"就被改小一次 (筛出 3 条却写着"全天 3 条")。
        let dayEnd = dayLatest[g.key]
        // 与「全天」同单位的显示数: 592 一行能装几条, 所以把折起来的尾行摊开再比。
        // 不摊开会写出"全天 5 条 · 当前显示 1 条"这种看着像少读了 4 条的话, 而那 4 条就在那一行里。
        let shownEvents = g.rows.count
        let dayFull = dayFullCount[g.key] ?? shownEvents
            // 2026-10-27 八轮精简：行内注记六张表已删（对应 UI 块一并移除）。
        return Section {
            ForEach(ordered) { r in
                // 583: 整行包一层 Group 才能挂 listRowBackground (ViewBuilder 的 if/else 分支不是同一个类型)。
                Group {
                    timelineRow(r)
                }
                .listRowBackground(FlashWash(on: flashKey == r.id))
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.s) {
                    Text(dayLabel(g.key))
                        .vkFont(.headline)
                    // 581 未处置告警蓝点: 该日有未处置告警才出现, 口径与 735 角标同一条 (不另存"已读"位)
                    // 596 替代: 原句是组头红字"含胁迫" —— 胁迫类协议不存在 (§5), 改挂真实存在的三类
                    // (防撬 7 / 试错锁定 10 / 键盘锁定 224)。点按落 586 既有的"当天全景"(landDay),
                    // 与"直接过滤到当日"同一件事; 与上面那枚蓝点**不互相替代**: 蓝点看未处置, 这条看这一天出过事。
                    if damageDays.contains(g.key) {
                        Button {
                            landDay(g.key)
                        } label: {
                            Text("含防撬/试错")   // 596 含防撬
                                .vkFont(.caption2, weight: .semibold)
                                .foregroundStyle(DS.Palette.danger)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("该日有防撬、试错锁定或键盘锁定告警, 点按只看这一天")   // 596 该日有防撬
                    }
                    // 594 日型色带 (4pt 竖条): 工作日靛蓝 / 周末青绿 / 法定节假日橙 (判据见 DayGroup.dayKind)。
                    // 每天都出现 —— 三档互比才有"哪天不是平常日"的读法; 原先只在节假日给 3pt 橙条。
                    if let k = g.dayKind {
                        Capsule()
                            .fill(k.color.opacity(0.9))
                            .frame(width: 4)
                            .accessibilityLabel(k.ax)
                    }
                    // 671 节假日组头标签 (内置表按国务院公告逐日核对) + 594 色带同一数据源, 不另造判定
                    if let h = g.holiday {
                        Text(h)
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.warn)
                            .lineLimit(1)
                    }
                    // 671 调休补班日: 与"放假日"共用同一数据源但分开标记 —— 补班是上班日。
                    // 给它同一条橙色色带，会让人把"这天开门多是正常的"读成"这天放假"。
                    if RecordSearch.isMakeupWorkday(g.key) {
                        Text("补班")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .accessibilityLabel("该日是调休补班日，不是假期")
                    }
                    // 649 凌晨归属: 组内含 0:00-4:59 事件时注明
                    if g.hasNight {
                        Text("含次日凌晨")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: DS.Space.s)
                    // 588 组头计数徽标: 开门 N · 告警 M (含告警日染浅红)
                    HStack(spacing: DS.Space.xs) {
                        Text("\(openN) 开")
                            .vkFont(.caption2, weight: .medium)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                        // 556 组头右侧的"该日命中告警数" (系统相册精选分组那一形态)：搜索/筛选后的结果
                        // 用的就是这一个组头 —— 不另开一套"搜索结果专用头"，那会多出第二份口径。
                        if alarmN > 0 {
                            Text("\(alarmN) 警")
                                .vkFont(.caption2, weight: .semibold)
                                .lineLimit(1)
                                .foregroundStyle(DS.Palette.danger)
                        }
                    }
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, 2)
                    .background(hasAlarm ? DS.Palette.danger.opacity(0.10) : DS.Palette.surfaceAlt, in: Capsule())
                }
                HStack(spacing: DS.Space.s) {
                    // 681 农历小字 (中国历法直接支持, 失败静默隐藏)
                    if let lunar = g.lunarLabel {
                        Text(lunar)
                            .vkFont(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    // 796 本日使用者 (组头小字, 归属推断标"约")
                    if g.key == todayKey, g.distinctUsers > 0 {
                        Text("约 \(g.distinctUsers) 位使用者")
                            .vkFont(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    Text("\(g.rows.count) 条")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.xs)
            .background(hasAlarm ? DS.Palette.danger.opacity(0.04) : Color.clear)
        } footer: {
            // 593 日界收尾标注: 交代"这一天的边界在哪"，核对当天有没有拉漏时不用再自己数末条。
            // 只在 ≥2 条的日子出现 —— 单条日子的"最晚"就是那条，写出来是噪音不是信息。
            // 显示数与全天数不一致时把「当前显示」也写出来: 同一句话里的两个口径要各归各的名字,
            // 否则筛完再看组尾, 那句"全天"就又变成一次谎 (598 分页截断时同样会分叉)。
            if let end = dayEnd, dayFull > 1 {
                Text("当日最晚 \(end) · 全天 \(dayFull) 条"
                     + (shownEvents == dayFull ? "" : " · 当前显示 \(shownEvents) 条")
                    )   // 593 界面文案
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(.horizontal, DS.Space.l)
            }
        }
    }

    /// 592 合并行的标签 (从 mergedRow 的 Button label 抽出: 该表达式报 type-check 超时)
    @ViewBuilder


    /// 单条: 左时间列 + 时间轴(圆点与连线) + 事件文案
    /// 738 告警行: 左侧 3pt danger 色条 + danger 8% 浅底 (菱形警示点形状冗余);
    /// 184 开门方式图标 / 183 成员色点 (可证明归属才显) / 770 锁名小标签 / 557 命中高亮
    private func timelineRow(_ r: RowVM) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            // 911/647: 主时间线行也必须走 TimeFormat.clock 这一个出口。此前只有合并行 (:1612) 走了,
            // 这一行是裸切片 (rowParts 的 "yyyy-MM-dd HH:mm:ss" 中段), 于是选了"12 小时"后
            // 同一页普通行仍显 24 小时、合并行显 12 小时 —— 一句注释承诺的"全部时间字段"就是这么破的。
            Text(TimeFormat.clock(r.time))
                .vkFont(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 2)

            ZStack(alignment: .top) {
                // 连接线: 留半格让线自然收在圆点上下 (592 展开态内也保持贯通)
                Rectangle()
                    .fill(DS.Palette.hairline)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                // 告警用菱形警示点, 普通用圆点 — 形状本身即第二信息通道, 不只靠颜色
                Image(systemName: r.warn ? "diamond.fill" : "circle.fill")
                    .font(.system(size: r.warn ? 10 : 8))
                    .foregroundStyle(r.warn ? DS.Palette.danger : DS.Palette.accent)
                    .padding(.top, 5)
            }
            .frame(width: 12)
            .accessibilityHidden(true)

            HStack(spacing: DS.Space.s) {
                // 188 手动标旗: 旗标行左侧常显 (形状+颜色双通道, 不只靠颜色)
                if RecordOverlay.isFlagged(r.rowMac.isEmpty ? mac : r.rowMac, r.key) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(DS.Palette.danger)
                        .accessibilityLabel("已标旗")
                }
                // 184 开门方式图标: fp 指纹 / pwd 数字 / temp 一次性 / key 钥匙
                rowTitle(r)
                    .padding(.top, 1)
                Spacer(minLength: 0)
            }
            // 907 时间线行距三档 (kf_tl_gap, 叠在 kf_density 之上): 竖列越密越难扫,
            // 这一档分别照顾"一眼看完一整天"与"一屏塞更多条"。
            .padding(.bottom, DS.Metric.tlGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 738 告警行: 左侧 3pt 色条 + 浅红底 (danger 派生, 形状冗余)
        .background(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.l, bottom: 0, trailing: DS.Space.l))
        .contentShape(Rectangle())
        // 576 行点开进详情 sheet (全字段 + 告警 727 清单 + 736 前后 3 条)。
        // 判据是 `lookupRec` 那一条 oid: 单锁与全部锁同一个口, 不再依赖"这次是哪种范围"。
        .onTapGesture {
            if let rec = lookupRec(r) {
                detailRec = rec
            } else {
                // 打不开要说得出为什么。原先这里 `detailRec = lookupRec(r)` 拿到 nil 就什么都不发生 ——
                // 那正是 576 在默认「当前锁」视图里坏掉两个版本时用户看到的形状: 行能点, 点了没反应。
                app.showToast("本机台账里没有这一行对应的记录数据 — 点右上角重新读取后再试")   // 576 本机台账里没有这一行
            }
        }
        // 185 左滑快捷操作: 只暴露行本来就有能力 (714 复制 / 577 跳凭证 / 186 备注 / 188 标旗)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !r.credKey.isEmpty {
                Button("看凭证") {
                    app.pendingCredNav = r.credKey
                    app.pendingCredNavMac = r.rowMac.isEmpty ? mac : r.rowMac
                    app.requestRoute(.credentials)   // 2026-10-14 走查: 原直写 tabSelection, 访客态绕过 377 门禁
                    // 收摊口径：换页一律走 requestRoute 这个唯一漏斗（先过访客闸再切 Tab），
                    // 而本页是 Tab 根、没有 sheet 盖着，所以这里不需要 dismiss()。
                }
                .tint(DS.Palette.warn)
            }
            Button("复制") {
                Clip.set("[" + (r.lockName.isEmpty ? app.displayName : r.lockName) + "] " + r.time + " " + r.title)
                app.showToast("已复制本条记录")
            }
            .tint(DS.Palette.accent)
        }
        .contextMenu {
            // 714 复制为完整文本: 粘贴即有锁名+时间+归属的完整上下文
            Button {
                Clip.set("[" + (r.lockName.isEmpty ? app.displayName : r.lockName) + "] " + r.time + " " + r.title)
                app.showToast("已复制本条记录")
            } label: {
                Label("复制为文本", systemImage: "doc.on.doc")   // 714 复制为文本
            }
            // 761 溯源: 复制本机缓存行标识 (锁日志序号 idx, 或手机侧事件的 f_/c_ 前缀键) + 日期 + 锁 MAC,
            // 便于和诊断包里的日志逐条对上。不假装能查锁端数据库。
            Button {
                let idLine = "row=" + r.key + " · day=" + r.dayKey + " · mac=" + (r.rowMac.isEmpty ? mac : r.rowMac)
                Clip.set(idLine)
                app.showToast("已复制行标识")   // 761 已复制行标识
            } label: {
                Label("复制行标识", systemImage: "number")   // 761 复制行标识
            }
            if !r.credKey.isEmpty {
                Button {
                    app.pendingCredNav = r.credKey
                    app.pendingCredNavMac = r.rowMac.isEmpty ? mac : r.rowMac
                    app.requestRoute(.credentials)   // 2026-10-14 走查: 原直写 tabSelection, 访客态绕过 377 门禁
                    // 收摊口径：换页一律走 requestRoute 这个唯一漏斗（先过访客闸再切 Tab），
                    // 而本页是 Tab 根、没有 sheet 盖着，所以这里不需要 dismiss()。
                    app.showToast("已定位到来源凭证")   // 577 已定位到来源凭证
                } label: {
                    Label("定位来源凭证", systemImage: "key.horizontal")   // 577 定位来源凭证
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(r.title + ", " + r.time)
        .accessibilityAddTraits([.isButton])
    }



    /// 557 命中词高亮: 搜索词在行文案中染 accentText 浅底 (分段 Text, 换行跟随整体流)
    @ViewBuilder
    private func rowTitle(_ r: RowVM) -> some View {
        if highlightTokens.isEmpty {
            Text(r.title)
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 0) {
                // 2026-10-13 run 63: 原写 `ForEach(highlightSegments(r.title), id: \.offset)` ——
                // HlSeg 没有 `offset` 成员 (它自带 `id`), id: 键路径推不出来 ⇒ 报
                // "cannot infer key path type from context" 并连带一串重载误判。HlSeg 本就 Identifiable,
                // 直接用它的 id。
                ForEach(highlightSegments(r.title)) { seg in
                    if seg.hit {
                        Text(seg.text)
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.vertical, DS.Space.xxs)
                            // @layout-allow VK豁免 刻度点: 时间轴上的命中段，是刻度不是容器
                            .background(DS.Palette.accentText.opacity(0.18), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else {
                        Text(seg.text)
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    struct HlSeg: Identifiable {
        var text: String
        var hit: Bool
        var id: Int
    }
    /// 557 高亮分段: 命中的词切出独立段 (贪心首匹配, 大小写不敏感)
    private func highlightSegments(_ text: String) -> [HlSeg] {
        guard !highlightTokens.isEmpty else { return [HlSeg(text: text, hit: false, id: 0)] }
        var segs = [HlSeg]()
        var rest = Substring(text)
        var idx = 0
        while !rest.isEmpty {
            var bestOff = -1
            var bestTok = ""
            for tok in highlightTokens where tok.count >= 1 {
                if let rng = rest.range(of: tok, options: .caseInsensitive) {
                    let off = rest.distance(from: rest.startIndex, to: rng.lowerBound)
                    if bestOff < 0 || off < bestOff {
                        bestOff = off
                        bestTok = tok
                    }
                }
            }
            if bestOff < 0 {
                segs.append(HlSeg(text: String(rest), hit: false, id: idx)); idx += 1
                break
            }
            let pre = String(rest.prefix(bestOff))
            let hitTxt = String(rest.dropFirst(bestOff).prefix(bestTok.count))
            if !pre.isEmpty {
                segs.append(HlSeg(text: pre, hit: false, id: idx)); idx += 1
            }
            segs.append(HlSeg(text: hitTxt, hit: true, id: idx)); idx += 1
            rest = rest.dropFirst(bestOff + hitTxt.count)
        }
        return segs
    }
    /// 183 成员色点: 可证明归属才显示 (成员档案色, 6pt 圆点)
    /// 183 成员色 (走成员档案 hex, 与安全中心同一纪律（该页已删，纪律沿用）)
    private func memberColor(_ m: Member) -> Color {
        var s = m.color
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16)
        return v == nil ? DS.Palette.accent : Color(hex: v!)
    }
    /// 576 行 → Rec: 单锁与全部锁**同一条判据**, 键的算术只有 `RecordOverlay.oid` 一份
    /// (行侧就是 `RowVM.id` 那一个 oid, Rec 侧在这里现算, 不再各自拼 "mac#key")。
    /// 旧写法先问 `$0.id == r.key`: Rec.id 恒带 mac 前缀, 而单锁路径的 r.key 不带 ⇒ 那一问永远不中;
    /// 第二问又只有在 recPool 非空时才可能命中, 而 recPool 原先只在 scope == 1 分支赋值
    /// ⇒ 默认「当前锁」视图里点行恒得 nil, 576/583/585/586 整条断供。
    private func lookupRec(_ r: RowVM) -> Rec? {
        recPool.first { RecordOverlay.oid(mac: $0.mac, rowKey: $0.key) == r.id }
    }


    private var emptyHint: some View {
        Section {
            // 558 零结果救援 —— 顺带堵住一条**说谎的空态**: 这里原来无脑显示"还没有记录，去重新读取"，
            // 而把上千条筛成 0 条时同样走到这一支 —— 那句话是在骗用户去重连一把好端端的锁。
            if activeFilterCount > 0 {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("当前条件下 0 条 —— 是过滤把它们挡掉了，不是这台锁没记录 (本机共 \(allRows.count) 行可读)。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.xs) {
                        // 原句三枚: 成员名 / 类型词 / 日期。全部取**真实存在**的值，不造示例词。
                        if let first = DB.members().first {
                            Button("试试成员「\(first.name)」") { sel = first.id; searchText = "" }
                                .vkFont(.caption)
                        }
                        Button("试试类型词「指纹」") { searchText = Attribution.words["fp"] ?? "指纹" }
                            .vkFont(.caption)
                        // 558 日期那枚: 只在今天真有行时才给 (时间短语经 554 成窗, must 摘除修在 RecordSearch.parse)
                        if allRows.contains(where: { $0.dayKey == Self.dayKey(Date()) }) {
                            Button("试试「今天」") { sel = ""; searchText = "今天" }
                                .vkFont(.caption)
                        }
                    }
                    .foregroundStyle(DS.Palette.accentText)
                    Button("清掉全部过滤") { sel = ""; searchText = ""; filters = QueryFilters() }   // 573 清掉全部过滤
                        .vkFont(.caption, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                }
                .padding(.vertical, DS.Space.m)
            } else {
                // 808 示例记录铺底 (Apple Wallet 那条原句): 空态原先只有一枚托盘图标 + 一句话,
                // 读完不知道"记录长什么样、要读多少条进来"。这里按原句铺 3 条**灰阶示例条目**,
                // 点任意一条弹「真实数据从这里开始」引导卡。
                // 三条示例是画出来的形状, 不是 RowVM/Rec ⇒ 不参与过滤、计数、统计、导出与深链,
                // 每条都写明"示例"且整体压在灰阶 (textSub / hairline) 上, 不会冒充真记录。
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Image(systemName: "tray")
                            .font(.system(size: DS.Icon.lg))
                            .foregroundStyle(DS.Palette.accentText)
                            .accessibilityHidden(true)
                        Text("还没有记录。点右上角「重新读取」从锁内拉取最近 100 条开门/操作记录。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        // 1044 家庭公告板
                    }
                    .accessibilityElement(children: .combine)
                    // 815 空态两个真出路: 记录是锁里拉出来的, 先连设备; 不知道这里记什么就看示例说明。
                    // 旧空态只有一行字 + 右上角一个入口, 用户读完了也不知道下一步点什么。
                    HStack(spacing: DS.Space.s) {
                        Button("连接设备") { app.requestRoute(.device) }
                            .buttonStyle(PrimaryActionStyle())
                            .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    }
                    .vkFont(.footnote)
                }
                .padding(.vertical, DS.Space.m)
            }
        }
    }


    // ---------- 成员过滤 (保留既有 793 访客虚拟分组 / 791 可认领 / 1028 保养) ----------
    private var memberChips: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip("", "全部")
                    ForEach(DB.members().filter { !MemberHub.ext($0.id).archived }) { m in   // 795: 归档成员不排 chip
                        if rows.contains(where: { $0.whoId == m.id }) { chip(m.id, MemberHub.aliasName(m.id) ?? m.name) }   // 919: chip 同走别名开关
                    }
                    if rows.contains(where: { $0.whoId == nil && $0.whoKind == "temp" }) {
                        chip(MemberHub.visitorId, "访客")   // 793 访客
                    }
                    if rows.contains(where: { $0.whoId == nil && $0.whoKind != "temp" }) {
                        chip("__unknown", "无法识别 · 可认领")
                    }
                    if allRows.contains(where: { $0.care }) { chip("__care", "保养") }   // 1028
                }
                .padding(.vertical, DS.Space.xxs)
            }
        } header: {
            HStack(spacing: DS.Space.s) {
                Text("按成员筛选")
                Spacer(minLength: DS.Space.s)
                Text(totalCount == rows.count ? "共 \(totalCount) 条" : "\(rows.count)/\(totalCount) 条")
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }
    private func chip(_ id: String, _ name: String) -> some View {
        let on = (sel == id)
        return Button {
            sel = id
            // 566: 同步写进会话保留的那一份 (见 QueryFilters.member) —— 点"全部"时 member 归空,
            // 不需要额外分支
            filters.member = id
            applyFilter()
        } label: {
            Text(name)
                // 字重固定: 改字重会改变字形宽度, 胶囊随之跳变
                .vkFont(.subheadline, weight: .medium)
                .lineLimit(1)
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, 12)   // 撑到 ≥44pt 触达
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }



    // ---------- 数据 ----------
    /// 进页收尾 —— 2026-10-13 run 63 从 body 内联的 .onAppear 闭包里抽出 (巨型 body 里那段报 type-check 超时)。
    private func onRecordsAppear() {
        // 2026-10-15 走查: 908 的开场过滤策略原先**只在视图构造时生效一次** —— 本页在 TabView 里
        // 长期存活, `filters` 是构造时读的 @State, 之后每次进记录页都不会重读, 于是
        // 「每次都从全部开始 / 每次默认只看告警」这两档从第二次进场起就形同虚设
        // (设置页那句"只改变进入记录页时的起点"落了空)。进场就按策略重取一次, 来源与构造时一致。
        filters = QueryFilters.load(mac: DB.preferredMac())
        // 566 开场恢复成员选择。908 的策略**不在这里重复判**: 策略是 QueryFilters.load 负责的
        // (选"每次空白"时它返回的就是空对象, member 自然为空) —— 这里再判一次就是两套规则。
        // 恢复后必须自己 applyFilter(): loadFromCache 已经跑过一次过滤，那一次还不知道有成员要恢复。
        if sel.isEmpty, !filters.member.isEmpty {
            sel = filters.member
            applyFilter()
        }
        // 包3/779: 多锁矩阵点格带入的成员过滤 (消费后清空, 不影响手动切换)
        if let f = app.pendingRecordsFilter {
            sel = f
            app.pendingRecordsFilter = nil
        }
        // 582 统计页成员条下钻带过来的成员 id (同样消费后清空, 落点走下面那条既有的成员过滤链)
        if let m = app.pendingRecordsMember { landMember(m) }
        // 585 记录引用深链落地 (进页时查一次)
        if let k = app.pendingRecordKey { landRecordKey(k) }
        // 586 当天全景落地
        if let d = app.pendingRecordsDay { landDay(d) }
        // 563 搜索词回填落地 (进页时一次性)
        if let q = app.pendingSearch { landSearch(q) }
    }
    // 2026-10-27 二轮精简：loadFromCache 已删（HotCache 移除后无缓存可读）。

    private func fetch() async {
        guard !running, let kc = app.current else { return }
        running = true
        offline = false
        var events = [LogEntry]()
        do {
            // 分页拉日志走的是**无 mac 参数**的 getLogs，它成帧用服务层 curMac、发链用当前 GATT 连接。
            // 原来这里只有 `getStatus(mac:)`（try? 吞失败）：curMac 被绑到 B 锁、链路却还挂在 A 锁上，
            // 等于把"给 B 的帧"从 A 的链路发出去。先 ensureConnected(kc.mac) 才把链和键都对上。
            try await app.lock.ensureConnected(mac: kc.mac)
            // 现场 03 背书 (R2 唯一规则), 失败不阻断
            if let st = try? await app.lock.getStatus(mac: kc.mac) { app.status = st }
            var startIdx: UInt32 = 0xFFFFFFFF
            var page = 0
            var seen = Set<UInt32>()
            // 749 会话内完整性对账: 记住锁端最后一次报告的"剩余条数", 循环结束仍 > 0 就是本次没拉全
            var lastSurplus: Int?
            var noSurplusReport = false      // 锁端没回 KLV#04 时"拉全/未拉全"都无从判定, 不能当成拉全
            while page < 20 && events.count < 100 {
                let r = try await app.lock.getLogs(orderType: 0, startIdx: startIdx, pageSize: 5)
                guard !r.logs.isEmpty else { break }
                let fresh = r.logs.filter { !seen.contains($0.idxRaw) }
                // 游标回绕防护: 旧实现 startIdx = r.logs.last!.idxRaw &- 1, 在 idxRaw == 0 时回绕成
                // 0xFFFFFFFF → 反复重读最新页 (最多 20 轮), events 出现重复行 (ForEach 重复 id、门神榜与统计虚高)。
                // 现按"本页最小序号"前进, 且无新增即判定到表尾。
                guard !fresh.isEmpty else { break }
                fresh.forEach { seen.insert($0.idxRaw) }
                events.append(contentsOf: fresh)
                DB.writeLogs(kc.mac, fresh)
                let lowest = fresh.map { $0.idxRaw }.min() ?? 0
                guard lowest > 0 else { break }
                startIdx = lowest - 1
                page += 1
                guard let surplus = r.surplus else {
                    // 锁端未回 KLV#04: 只读到本页, 如实告知而非假装"已拉全"
                    noSurplusReport = true
                    app.showToast("锁端未报告剩余条数, 已读 \(events.count) 条")
                    break
                }
                if surplus <= 0 { break }
                lastSurplus = surplus
            }
            // 749 完整性对账 (仅声明本次会话内的事实, 不宣称"锁内日志已全"):
            // 循环因翻页上限退出时 lastSurplus 仍 > 0 → 如实标出缺口。
            if noSurplusReport {
                // 锁端没报告剩余条数 → 对账**不可判**; 这一种最容易被写成"已拉全", 那是假安慰
                pullGap = "锁端未报告剩余条数 (KLV#04)，本次只读到 \(events.count) 条 — 无法判断是否拉全"
                reconLine = "锁 \(app.displayName) · 本次拉取 \(events.count) 条 · 锁端未报告剩余 · 对账不可判 · \(Self.stamp.string(from: Date()))"   // 749 本次拉取
            } else if let gap = lastSurplus, gap > 0 {
                pullGap = "锁端仍报剩余 \(gap) 条，本次取 \(events.count) 条（翻页上限 20 页 / 100 条）— 属未拉全，不是记录缺失"
                reconLine = "锁 \(app.displayName) · 本次拉取 \(events.count) 条 · 锁端报告剩余 \(gap) 条 · 未拉全 · \(Self.stamp.string(from: Date()))"   // 749 本次拉取
            } else {
                pullGap = nil
                reconLine = "锁 \(app.displayName) · 本次拉取 \(events.count) 条 · 锁端报告无剩余 · 本次会话内已拉全 · \(Self.stamp.string(from: Date()))"   // 749 本次拉取
            }
            // 存取必须同型: set(Int) 落 JSON 数字, getString 解 String 必失败 → lastSyncAt 恒 nil,
            // 刚读完也会误报"未连接·读取时间未知"
            DB.store.set(syncStampKey, String(Int(Date().timeIntervalSince1970 * 1000)))
            render(events, offline: false)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // 852 读取失败主动播报 (VoiceOver 运行时即时朗读, 含"离门太远"人话原因)
            AXTools.announceConnectFail(error.localizedDescription)
            let cached = DB.readLogs(kc.mac)
            if !cached.isEmpty {
                render(cached.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") }, offline: true)
            } else {
                app.showToast("读取失败: \(error.localizedDescription)")
            }
        }
        running = false
        // 876 新条目双震: 本次读取有新增记录时两段 success 触感 (听障确认通道, 设置可关)
        if !events.isEmpty { AXTools.newEntryHaptic() }
    }

    private func render(_ logs: [LogEntry], offline: Bool) {
        self.offline = offline
        // 92 (包1): 本地开锁失败标记合入时间线 — 手机侧记录 (DB.kf_fevents_), 绝不混入锁日志缓存;
        // type 0 非任何锁端日志类型, 归属推断自然回落"未归属", 行样式走普通灰图标
        var merged = logs
        // 手机侧行 (92 失败 / 1028 保养) 的**行身份**: 与 `RecordSearch.buildRecs` 给同一族事件用的键并成一份
        // ("f_" + Unix 秒 / "c_" + Unix 毫秒)。原先这两族行在单锁路径拿的是 `String(idxRaw)`,
        // 而那个 idxRaw 是 `Int(ts*1000) + 数组下标` 现编的派生数 —— 于是同一条记录在两种范围下行身份不同:
        // 单锁模式里 576 详情打不开、186 备注与 188 标旗写了不显示 (详情卡按 Rec 的键写, 行按派生数读),
        // 而 761 那行"复制行标识 (f_/c_ 前缀键)"的说明一直是假的。
        // 表键就是派生出来的那个 idxRaw: 它只在本机这一份合并数组里唯一, 不参与任何持久化。
        var sideKey = [UInt32: String]()
        let cls = Attribution.classify(
            logs: merged,
            pwds: DB.listPwds(mac), fps: DB.listFps(mac),
            status: app.status.map { ($0.fpStock, $0.pwdStock, $0.lockTime ?? 0) })
        // 791 认领覆盖层: 本机认领结果直接改写 whoId (不改锁端数据)
        let claims = MemberHub.claims(mac)
        var out = [RowVM]()
        let pwds = DB.listPwds(mac)
        let fps = DB.listFps(mac)
        for (i, e) in merged.enumerated() {
            guard i < cls.count else { continue }
            let c = cls[i]
            // 行身份只有一个来源: 锁日志 = idxRaw 字符串; 手机侧行 (type 0) = 上面算好的 f_/c_ 前缀键。
            // 791 认领的读写、186 备注、188 标旗、576 详情都从这里起, 不再各拿一份派生数。
            let rowKey = e.type == 0 ? (sideKey[e.idxRaw] ?? String(e.idxRaw)) : String(e.idxRaw)
            let p = Self.rowParts(e.lockTimeStr, todayKey: todayKey)   // 归属日 (649 凌晨归前一晚) + 显示时刻
            var whoId = c.who
            if let claimed = claims[rowKey] { whoId = claimed }   // 791 认领优先
            let whoName = whoId.flatMap { DB.member($0)?.name }
            // 655 动词化日志文案: "张三 用 指纹 开了门" (保留 791 认领与 1028 关怀行)
            let care = e.type == 0 && (e.typeName.hasPrefix("保养") || e.typeName.hasPrefix("更换电池"))
            let title: String
            if care || e.type == 0 {
                title = e.typeName   // 关怀/失败手机侧行保留原貌
            } else {
                let kindWord = StatsKit.openTypes.contains(e.type) ? (Attribution.words[c.kind ?? ""] ?? nil) : nil
                // 461: 条目显示"称呼（备注）"; whoName 留裸名给 credNav/筛选匹配 (919: 别名开关开时关系称呼顶替)
                let whoShow = MemberHub.aliasName(whoId)
                    ?? whoId.flatMap { DB.member($0).map(MemberHub.doubleLine) } ?? whoName
                title = RecordVerbs.line(type: e.type, who: whoShow, kindWord: kindWord, typeName: e.typeName)
            }
            let warn = StatsKit.alarmTypes.contains(e.type)
            // 791 可认领: 未归属且还没有认领记录 (temp 类进 793 访客虚拟分组, 不认领)
            let claimable = whoId == nil && c.kind != "temp" && !claims.keys.contains(rowKey)
            out.append(RowVM(key: rowKey, time: p.time,
                             dayKey: p.dayKey,
                             hour: p.hour, type: e.type,
                             title: title, whoId: whoId, whoKind: c.kind,
                             kind: c.kind, lockName: "", rowMac: mac,
                             credKey: Self.credNav(kind: c.kind, who: whoName, pwds: pwds, fps: fps),
                             warn: warn, claim: claimable, care: care))
        }
        allRows = out
        applyFilter()
    }
    /// 577 凭证深链: kind+归属 → pwd:<alias> / fp:<batch>; 台账无命中留空 (不深跳)
    private static func credNav(kind: String?, who: String?, pwds: [LedgerPwd], fps: [LedgerFp]) -> String {
        switch kind {
        case "pwd":
            if let p = pwds.first(where: { !$0.temp && (who == nil || $0.owner == who) }) { return "pwd:" + String(p.alias) }
        case "temp":
            if let p = pwds.first(where: { $0.temp && (who == nil || $0.owner == who) }) { return "pwd:" + String(p.alias) }
        case "fp":
            if let f = fps.first(where: { (who == nil) || ($0.owner == who) || (!who!.isEmpty && $0.name.contains(who!)) }) { return "fp:" + String(f.batch) }
        default:
            break
        }
        return ""
    }

    /// 这一处原本自建 DateFormatter 且**没钉 `en_US_POSIX`**：用户在「设置 → 语言与地区 → 历法」
    /// 里选佛历/和历等非公历时，`yyyy` 会输出 2569 这类异 era 年份，与锁端日志的公历日 key 永不相等
    /// (§10.30)。归到 `StatsKit.dayKey` 一并解决。
    private static func dayKey(_ d: Date) -> String { StatsKit.dayKey(d) }

    /// 92: 手机侧失败时刻 → 与锁日志同格式的 "yyyy-MM-dd HH:mm:ss" (可排序)
    private func failTimeStr(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    // ---------- 580/584/585 详情翻页与引用深链的数据源 ----------
    // 551/554/555/564/571/572/567/568/569/570/770: 行**内容**两种范围两条来源 (单锁 = 本地行池 allRows,
    // 全部锁 = 跨锁 Rec 现建的行池), 但 576/580/585 的判据池 `recPool` 两种范围喂的是同一份 ——
    // 详情卡认的是「哪把锁的哪一行」, 不是「你现在看着哪种范围」。
    /// 当前**显示顺序**里的记录 (月份跳转生效时同样收窄)。
    /// 为什么不用原始日志顺序: 详情卡的"上一条/下一条"要复现用户刚才扫读的那份结果，
    /// 被他筛掉的记录不该被翻页翻出来 —— 那等于悄悄改了筛选条件。
    /// 池子直接取 `recPool` (applyFilter 两种范围都会喂): 原先这里再调一次 buildRecs, 于是
    /// "点行开详情用的池"与"详情翻页用的池"是两次独立拉取 —— 同一次进页里它们可以不是同一份数据。
    var displayedRecs: [Rec] {
        var byOid = [String: Rec]()
        // 不用 Dictionary(uniqueKeysWithValues:): 本仓跨锁行键理论上能撞，撞了就是一次启动崩溃
        for r in recPool { byOid[RecordOverlay.oid(mac: r.mac, rowKey: r.key)] = r }
        return groups
            .filter { monthJump.isEmpty || $0.key.hasPrefix(monthJump) }
            .flatMap { $0.rows }
            .compactMap { byOid[$0.id] }   // RowVM.id 就是同一个 oid (键的算术只有一份)
    }

    /// 582 落地 (统计页成员条 → 记录 Tab): 把带过来的成员 id 写进**既有的**成员选择变量 `sel`,
    /// 再走既有的过滤链 (applyFilter)。`filters.member` 一起写是刻意的 —— 那是 566/192 会话保留里的
    /// 同一份成员过滤状态, 只改 `sel` 会出现"屏幕上在筛、下次进页又没筛上"的半截行为 (点成员 chip 的 `chip()`
    /// 写的就是这两个, 这里必须一致, 否则同一个功能两套状态)。
    /// id 认不出来时如实说一句并留在原范围, **不静默回落"全部"**: 静默回落等于告诉用户"这人没有记录"。
    /// 原句后半条"滚动到其最近一条"在本页默认倒序下就是列表首行, 不需要第二条滚动实现;
    /// 只有开了 570 正序回放或 187 月份收窄时首行不是它 —— 那半条要 ScrollViewReader, 与 18/187、579
    /// 记在同一张"需要编译器才动得了"的清单上 (§130), 这里不假装做了。
    private func landMember(_ id: String) {
        app.pendingRecordsMember = nil
        guard !id.isEmpty else { return }
        guard DB.member(id) != nil else {
            app.showToast("那位成员已不在本机档案里 — 记录过滤没有改变")   // 582 那位成员已不在本机档
            return
        }
        sel = id
        filters.member = id
        applyFilter()
    }

    /// 563 落地: 把词填进搜索框。走 `searchText` 的既有 onChange ⇒ 边输入边更新的同一条链 (562)，
    /// 因此这里**不自己调 applyFilter** —— 两处都调会跑两遍过滤，第二遍才是最终结果，看着一样但白烧一次。
    private func landSearch(_ q: String) {
        app.pendingSearch = nil
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        searchText = t
        app.showToast("已带入「\(t)」，可继续编辑")   // 563 已带入
    }

    /// 585 深链落地: 按 `mac#行键` 精确找那一条并开详情。
    /// 找不到就如实说"被筛选挡掉/缓存重整/锁已删除"三种可能，**绝不**打开相邻的一条凑数。
    private func landRecordKey(_ k: String) {
        app.pendingRecordKey = nil
        guard !k.isEmpty else { return }
        if let hit = displayedRecs.first(where: { RecordOverlay.oid(mac: $0.mac, rowKey: $0.key) == k }) {
            detailRec = hit
            // 583: 闪与滚**等详情卡关闭后**再做 (见 flashOnClose 的说明)
            flashOnClose = RecordOverlay.oid(mac: hit.mac, rowKey: hit.key)
        } else {
            app.showToast("这条记录不在当前显示范围里 — 可能被筛选挡掉、缓存已重整，或锁已删除")   // 585 这条记录不在当前显示
        }
    }

    /// 657 无记录日占位行 / 675 假期外出分隔行 —— 时间轴的"连续感"由这一行负责，而不是补一堆空天。
    /// 两种写法是刻意的:
    ///   · 缺口 ≤7 天 ⇒ 逐日一行 "当日无开门记录" (几天而已，铺得开，也确实在说每一天);
    ///   · 缺口 >7 天 ⇒ **只给一行** "其间 N 天无记录"。30 天补 29 行灰条比缺口本身更吵，
    ///     而且没人能从那 29 行看出"哪些天真的没人出门"vs"哪些天只是没读到日志"。
    /// 含节假日的那一档才升级成 675 的"假期外出？"问句 (非警告样式 —— 它不是异常，只是一个猜测,
    /// 所以行里带问号也带"约"味, 不写成"假期外出"这种断定)。
    /// 586 当天全景的顶部条: 说明"现在只看这一天"并给出**唯一的退出入口**。
    ///
    /// 少了这条，从统计页/时间线点某天跳进来后，用户看到的是一天孤零零的列表，
    /// 会以为别的记录没了；而且**没有任何回到全部日子的入口**（只能绕去"按月份跳转→清除"）。
    /// 收窄显示范围必须同时告诉用户范围被收窄了 —— 与 657 那行"这不是没记录是筛掉了"同一个原则。
    @ViewBuilder
    private var dayFocusBanner: some View {
        if !dayFocus.isEmpty {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "calendar.day.timeline.left").accessibilityHidden(true)
                Text("只看 \(dayFocus) 这一天")   // 586 只看
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.text)
                Spacer(minLength: DS.Space.s)
                Button("看全部日子") { dayFocus = "" }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            .padding(.vertical, DS.Space.xs)
            .accessibilityElement(children: .combine)
        }
    }

    /// 583 闪一下: 高亮 1.2 秒后自动撤。为什么不做成常亮:
    /// 常亮的"你在这里"会在用户继续往下读时变成"这条特殊"的误导，而它特殊的地方只是刚才被点过。
    private func flashRow(_ oid: String) {
        flashKey = oid
        scrolledRow = oid
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if flashKey == oid { flashKey = "" }
        }
    }

    /// 583 的一次性高亮底。做成小视图而不是三元: `listRowBackground` 只吃一个 View 类型，
    /// 而 `on ? 有色 : Color.clear` 在 `Rectangle().fill()` 里面就同类型了 —— 不用 AnyView。
    private struct FlashWash: View {
        let on: Bool
        var body: some View {
            Rectangle()
                .fill(on ? DS.Palette.accent.opacity(0.14) : Color.clear)
                .transaction { $0.animation = nil }
        }
    }

    /// 583 的页内入口: 详情卡点"在时间线里定位这条"⇒ 关详情、滚过去、闪一下。
    private func landFlash(_ oid: String) {
        app.pendingFlashKey = nil
        guard !oid.isEmpty else { return }
        flashRow(oid)
    }

    /// 586 落地: 把显示范围收到那一天。
    /// **先确认那一天在当前数据里真有行**才收窄 —— 跳进一个空白日子比不跳更让人以为数据丢了。
    private func landDay(_ key: String) {
        app.pendingRecordsDay = nil
        guard !key.isEmpty else { return }
        if groups.contains(where: { $0.key == key && !$0.isGap }) {
            dayFocus = key
        } else {
            app.showToast("那一天在本机台账里没有行 — 未拉取、已过缓存上限，或日期写错")   // 586 那一天在本机台账里没
        }
    }

    private func gapRow(_ g: DayGroup) -> some View {
        // 一行话先算清楚再上屏: 原来这里塞了两层三元 + Optional.map，读的人要同时记住"缺口长度"和
        // "有没有节假日"两件事才能确定它到底说什么 —— 那是把分支藏在字面量里。
        let line: String
        if g.gapDays > 7 {
            line = "其间 \(g.gapDays) 天无记录"   // 657 其间
        } else {
            line = "当日无开门记录"   // 657 当日无开门记录
        }
        let withHoliday = g.gapHoliday.map { line + " · 含\($0)，假期外出？" } ?? line   // 675 假期外出
        return HStack(spacing: DS.Space.s) {
            Capsule()
                .fill(DS.Palette.hairline)
                .frame(width: 3)
                .frame(maxHeight: 14)
                .accessibilityHidden(true)
            Text(withHoliday)
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private func applyFilter() {
        // 576/580/583/585 —— Rec 池是「点行开详情、详情上下翻页、引用深链定位」唯一的判据来源,
        // **两种范围都要喂**。原先只有 scope == 1 分支赋值 ⇒ 默认「当前锁」视图里 recPool 恒空,
        // lookupRec 恒 nil, 时间线行点下去没有反应 (第一百八十九批核出的默认路径断供)。
        // `macs` 自己就按范围给出 [当前锁] / [全部锁], 所以这里不需要分支: 一次拉取, 两路共用。
        let recs = RecordSearch.buildRecs(macs: macs, includeFails: true, includeCare: true)
        recPool = recs
        // `var` 不是风格问题: 全部锁分支建行后还要过一次 592 合并, 那是同一分支内的第二次赋值,
        // 写成 `let` 在 Swift 里是"给已初始化的常量再赋值", 编译错误。
        var pool: [RowVM]
        if scope == 0 {
            pool = allRows
        } else {
            // 770 全部锁: Rec 池 → RowVM (行首带锁名小标签, 575 越界窗口小字)
            let outWins = RecordSearch.outOfWindow(macs: macs)
            var winMap = [String: String]()
            for w in outWins { winMap[RecordOverlay.oid(mac: w.rec.mac, rowKey: w.rec.key)] = w.window }
            pool = recs.map { r in
                let p = Self.rowParts(r.timeStr, todayKey: todayKey)
                return RowVM(key: RecordOverlay.oid(mac: r.mac, rowKey: r.key), time: p.time, dayKey: p.dayKey,
                             hour: p.hour, type: r.type,
                             title: Self.recTitle(r), whoId: r.whoId, whoKind: r.kind,
                             kind: r.kind, lockName: r.lockName, rowMac: r.mac,
                             credKey: Self.recCredNav(r),
                             winText: winMap[RecordOverlay.oid(mac: r.mac, rowKey: r.key)] ?? "",
                             warn: r.alarm, claim: false, care: r.care)
            }
        }
        // 593 日界收尾的可核口径: 一天的**条数**与**最晚时刻**都取自上面这份还没被筛选、没被 598 截断的行池。
        // 组尾那句原文是「当日最晚 23:47 · 全天 N 条」—— 它说的是这一天, 不是"这一天还剩几行给我看"。
        // 原先两个数都来自 g.rows (筛过 + 截过), 于是每次过滤、每页分页都会把"全天"改小一次。
        var dayCount: [String: Int] = [:]
        var dayEndBy: [String: String] = [:]
        for r in pool {
            // 592 折起来的尾行也属于这一天: 条数连尾一起数。
            dayCount[r.dayKey, default: 0] += 1
            // 最晚时刻 = 这一天在池里**第一次出现**的那一行 —— 行池本身就是按锁端时刻倒序排好的
            // (render 与 buildRecs 各排一次, 用的都是 "yyyy-MM-dd HH:mm:ss" 串序 = 时间序, 跨年也成立;
            //  下面"按天分组: 日志本身已是时间倒序, 保持首现顺序即可"吃的是同一条前提)。
            // 刻意不用"把显示时刻串取字典序最大"当最晚 (旧写法): 日组是按 649 归过属的, 12-31 那一组里
            // 会混进元旦凌晨 00:xx 的行, 而 "12-31 …" 的字典序大于 "01-01 …" ⇒ 旧写法会在每个跨年日组
            // 把"当日最晚"说成前一晚的 23:47。倒序首现不需要比较, 也就不吃这个亏。
            if dayEndBy[r.dayKey] == nil, Self.isClockish(r.time) { dayEndBy[r.dayKey] = r.time }
        }
        dayFullCount = dayCount
        dayLatest = dayEndBy
        // 成员/未知/访客/保养 过滤 (保留既有 793/791/1028 语义)
        var filtered = pool
        switch sel {
        case "": break
        case "__unknown": filtered = pool.filter { $0.whoId == nil && $0.whoKind != "temp" }
        case MemberHub.visitorId: filtered = pool.filter { $0.whoId == nil && $0.whoKind == "temp" }
        case "__care": filtered = pool.filter { $0.care }
        default: filtered = pool.filter { $0.whoId == sel }
        }
        // 551/554/555 文本检索: 正词全中 + 负词全不中 + 时间短语窗 + 告警/凭证类词
        if !searchText.isEmpty {
            let q = RecordSearch.parse(searchText)
            // 551 搜索面补齐: 占位文案写着「成员 / 凭证 / 备注」, 而拼接只有 title + 锁名 + 成员名 ——
            // 186 备注与 568 凭证标签压根不在搜索面上, 等于界面承诺了一个检索不到东西的热区。
            //   · 备注的存储键本身就是 mac#行键 (RecordOverlay.setNote 写进去的就是 `oid`), 所以直接并表,
            //     不在这里二次换算;
            //   · 凭证标签 (含 310 别名) 只有 Rec 带得动, 出处就是刚喂好的 recPool —— 单锁模式现在也有池子,
            //     这正是本批补的那一条。
            // 两张表都在筛选循环**外面**各建一次: RecordOverlay.notes 每次调用都要解一遍 JSON,
            // 放进逐行判据里就是一千行解一千次。
            var noteByOid: [String: String] = [:]
            for m in macs { noteByOid.merge(RecordOverlay.notes(m)) { _, newest in newest } }
            var credByOid: [String: String] = [:]
            for x in recPool { credByOid[RecordOverlay.oid(mac: x.mac, rowKey: x.key)] = x.cred }
            filtered = filtered.filter { r in
                let whoStr = r.whoId.flatMap { DB.member($0)?.name ?? "" } ?? ""
                let txt = RecordSearch.searchFace(title: r.title, lockName: r.lockName, whoName: whoStr,
                                                  cred: credByOid[r.id] ?? "", note: noteByOid[r.id] ?? "")
                let memberHit = q.member.map { txt.localizedCaseInsensitiveContains($0) } ?? false
                let mustHit = q.must.isEmpty || q.must.allSatisfy { txt.localizedCaseInsensitiveContains($0) } || memberHit
                let notHit = q.not.allSatisfy { !txt.localizedCaseInsensitiveContains($0) }
                guard mustHit, notHit else { return false }
                if q.alarmOnly, !r.warn { return false }
                if let k = q.credKind, r.kind != k { return false }
                // 554 时间短语: 按 562 口径落在窗内 (行级时刻近似: 日 + 时分)
                if let rng = q.range, let d = rowDate(r) {
                    if d < rng.from || d > rng.to { return false }
                }
                return true
            }
        }
        // 564/571/572/567/568/569 过滤条件 (单锁与全部锁同一口径)
        if activeFilters {
            filtered = filtered.filter { r in
                let hour = r.hour >= 0 ? r.hour : -1
                if hour >= 0 {
                    // 672: 传行的归属日键 (与 RecordSearch 内部判定同一口径, 凌晨已归前一晚)
                    if filters.lateNight && !RecordSearch.isLateNight(hour, dayKey: r.dayKey) { return false }
                    switch filters.segment {
                    case 1: if !(6...9).contains(hour) { return false }
                    case 2: if !(10...14).contains(hour) { return false }
                    case 3: if !(15...21).contains(hour) { return false }
                    case 4: if !RecordSearch.isLateNight(hour, dayKey: r.dayKey) { return false }
                    default: break
                    }
                    if let d = RecordSearch.dateFromKey(r.dayKey) {
                        let wk = WeekCal.gregorian.component(.weekday, from: d)
                        let isWeekend = wk == 1 || wk == 7
                        if filters.dayKind == 1 && isWeekend { return false }
                        if filters.dayKind == 2 && !isWeekend { return false }
                    }
                } else if filters.segment != 0 || filters.lateNight || filters.dayKind != 0 {
                    return false   // 时刻未知行不进时段/周末口径
                }
                if filters.alarmOnly && !r.warn { return false }
                // 565 类型多选: 只留选中的告警类型 (选中集全是告警类, 天然只出告警行; 与 567 可叠加取交集)
                if !filters.alarmKinds.isEmpty, !filters.alarmKinds.contains(r.type) { return false }
                // ⚠569: 锁端仅记录告警级 (10/13/224) + 手机侧失败行, 无逐次失败明细
                if !filters.kind.isEmpty, r.kind != filters.kind { return false }
                return true
            }
        }
        // 570 正序回放: 整段反转 (时间线从最早逐条回放)
        if reversed { filtered = filtered.reversed() }
        // 598: 在**分组之前**截断 —— 分组本身是 O(n)，一次挂上千个 Section 才是滚动掉帧的主因。
        // 同时留下截断前的总数: resultCount 报的必须是"筛掉多少"而不是"这次渲染了多少"，
        // 否则一次分页就把统计口径悄悄改小了 (那是最难发现的错法: 数字看着都对)。
        filteredTotal = filtered.count
        // 598 分档截断: 上限没定过 (首页) → 池 ≤600 全显、>600 显 600; 已定 → 用户按过「继续加载」,
        // 只在还没显完时保留 capped。写死 1200 的旧判据在 300 条级数据层上永远不触发, 等于把 598 判成"做了"。
        if shownCap <= 0 {
            shownCap = filtered.count > 600 ? 600 : filtered.count
        }
        capped = filtered.count > shownCap
        if capped { filtered = Array(filtered.prefix(shownCap)) }
        rows = filtered
        // 按天分组: 日志本身已是时间倒序, 保持首现顺序即可
        var order: [String] = []
        var buckets: [String: [RowVM]] = [:]
        for r in filtered {
            if buckets[r.dayKey] == nil { order.append(r.dayKey) }
            buckets[r.dayKey, default: []].append(r)
        }
        groups = order.map { key in
            DayGroup(key: key, rows: buckets[key] ?? [])
        }
        // 657/675 补缺口行。三个前提都是"别把筛掉的痕迹说成空档":
        //   · 未筛选 (activeFilterCount == 0) —— 用户过滤掉周末后再补"周六无记录"是在指责日历;
        //   · 非正序回放 —— 570 的回放是从最早逐条读，插空行会打断那条叙事线;
        //   · 时间未知行 "__none" 不参与推算 (它没有相邻日的概念)。
        if !reversed, activeFilterCount == 0, groups.count >= 2 {
            var filled: [DayGroup] = []
            for i in 0..<groups.count {
                filled.append(groups[i])
                guard i + 1 < groups.count,
                      !groups[i].isNone, !groups[i + 1].isNone,
                      let newer = RecordSearch.dateFromKey(groups[i].key),
                      let older = RecordSearch.dateFromKey(groups[i + 1].key) else { continue }
                // 相隔天数要**就近取整**而不是截断：原本写的是 `(elapsed - 43_200) / 86_400`，
                // 减半天再截断 = 比"向下取整"还早一格 ⇒ 相隔 N 天算出 N-1，于是
                //   · 只缺一天时 gap = 1，被 `gap >= 2` 挡掉 ⇒ **空了一整天从来不补** (675 那行"缺口"永远少一段)；
                //   · 缺 N 天的那条汇总行报 `missing = N-1` ⇒ 「N 天无记录」恒定少说一天。
                // 改成 + 半天再截断：N=1 相邻 ⇒ 1、N=2 ⇒ 2 (missing 1) …；有夏令时的日子两天可能只差 23 小时，
                // 就近取整同样落对 (减半天那版会把 23 小时当成一天、把 47 小时当成两天)。见 §10.33。
                let gap = Int((newer.timeIntervalSince(older) + 43_200) / 86_400)
                guard gap >= 2 else { continue }
                let missing = gap - 1
                if missing > 7 {
                    var hol: String? = nil
                    for k in 1...min(missing, 45) where hol == nil {
                        hol = RecordSearch.holidayName(RecordSearch.dayKeyOf(WeekCal.shifted(older, days: k)))
                    }
                    filled.append(DayGroup(key: "gap-" + groups[i + 1].key, rows: [],
                                           isGap: true, gapDays: missing, gapHoliday: hol))
                } else {
                    for k in 1...missing {
                        let dk = RecordSearch.dayKeyOf(WeekCal.shifted(older, days: k))
                        filled.append(DayGroup(key: "gap-" + dk, rows: [],
                                               isGap: true, gapDays: 1, gapHoliday: RecordSearch.holidayName(dk)))
                    }
                }
            }
            groups = filled
        }
        // 596 同日一并算一次 (同一次 applyFilter 内的同一份日志缓存, 不另起一遍 IO)
        damageDays = RecordSearch.damageDays(macs: macs)
    }
    /// 行级时刻 (554 时间短语判定): 组头日 + 时分
    private func rowDate(_ r: RowVM) -> Date? {
        guard let d0 = RecordSearch.dateFromKey(r.dayKey) else { return nil }
        var comps = DateComponents()
        comps.year = 0
        var d = d0
        if r.time.count >= 5, let h = Int(r.time.prefix(2)) {
            let m = r.time.count >= 4 ? (Int(r.time.dropFirst(3).prefix(2)) ?? 0) : 0
            d = d.addingTimeInterval(TimeInterval(h * 3600 + m * 60))
        }
        _ = comps
        return d
    }
    /// 锁端时刻串 ("yyyy-MM-dd HH:mm:ss") → (归属日键, 左侧显示时刻, 小时)。
    /// 单锁路径 (render) 与全部锁路径 (applyFilter) 原先各抄一遍这套换算, 连 649 的「凌晨归前一晚」
    /// 也是两份 —— 分组键是 593 全天口径与 586 当天全景的锚, 两处漂一格就会各自成立、合起来对不上。
    /// 现在只有这一份: 时刻串不足 16 位 (手机侧事件或锁端未回时刻) 一律显示 "--:--", 日键不足 10 位记 "__none"。
    private static func rowParts(_ full: String, todayKey: String) -> (dayKey: String, time: String, hour: Int) {
        let hh = full.count >= 13 ? (Int(full.dropFirst(11).prefix(2)) ?? -1) : -1
        var day = full.count >= 10 ? String(full.prefix(10)) : "__none"
        if day.count == 10, hh >= 0, hh < 5, let d0 = RecordSearch.dateFromKey(day) {
            day = RecordSearch.dayKeyOf(WeekCal.shifted(d0, days: -1))   // 649 凌晨归前一晚 (组头注明)
        }
        let time = full.count >= 16
            ? (day == todayKey ? String(full.dropFirst(11).prefix(5)) : String(full.dropFirst(5).prefix(11)))
            : "--:--"
        return (day, time, hh)
    }

    /// 593「当日最晚」的时刻判据: 至少 5 位、且前两位是数字 —— "HH:mm" (今天) 与 "MM-dd HH:mm" (跨天)
    /// 两种显示写法都以小时开头。"--:--" (时刻未知: 手机侧行没带时刻、或锁端未回) 不参与 ——
    /// 它连这一天的边界都说不成, 写进组尾只会变成一句没有数的空话。
    /// (旧写法是拿它配"时刻串字典序取最大"来定最晚, 跨年日组会说错, 见 applyFilter 里 593 那段。)
    private static func isClockish(_ t: String) -> Bool {
        t.count >= 5 && t.prefix(2).allSatisfy { $0.isNumber }
    }

    /// 551 Rec → 655 动词化文案 (告警/操作/关怀各用各的动词)
    private static func recTitle(_ r: Rec) -> String {
        if r.alarm || r.care || !r.failMsg.isEmpty { return r.typeName }
        let kindWord = StatsKit.openTypes.contains(r.type) ? (Attribution.words[r.kind ?? ""] ?? nil) : nil
        // 461: 与列表行同口径 — 有可证明归属时显示"称呼（备注）" (919: 别名开关开时关系称呼顶替)
        let whoShow = MemberHub.aliasName(r.whoId)
            ?? r.whoId.flatMap { DB.member($0).map(MemberHub.doubleLine) } ?? r.whoName
        return RecordVerbs.line(type: r.type, who: whoShow, kindWord: kindWord, typeName: r.typeName)
    }
    /// 577 全部锁模式下 Rec → 凭证深链 (各锁台账独立)
    private static func recCredNav(_ r: Rec) -> String {
        let pws = DB.listPwds(r.mac)
        let fps = DB.listFps(r.mac)
        switch r.kind {
        case "pwd":
            if let p = pws.first(where: { !$0.temp && (r.whoName == nil || $0.owner == r.whoName) }) { return "pwd:" + String(p.alias) }
        case "temp":
            if let p = pws.first(where: { $0.temp && (r.whoName == nil || $0.owner == r.whoName) }) { return "pwd:" + String(p.alias) }
        case "fp":
            // 2026-10-13 run 63: 原写 `r.whoName.map { $0.name.contains($0) }` —— whoName 是 String?,
            // map 里的 $0 是解包后的 String, 它没有 .name ⇒ "value of type 'String' has no member 'name'";
            // 且内层 $0 与外层 $0 撞名。改成命名外层 fp、内层用解包后的成员名去匹配 fp.name。
            if let f = fps.first(where: { fp in
                (r.whoName == nil) || (fp.owner == r.whoName) || (r.whoName.map { fp.name.contains($0) } ?? false)
            }) { return "fp:" + String(f.batch) }
        default:
            break
        }
        return ""
    }

    /// 187 按月跳转: 只列本机已有记录的月份 (不造空月), 选中即筛, 再点一次清除
    @ViewBuilder
    private var monthJumpRow: some View {
        // 657 补缺口行之后，月份列表必须跳过 gap-* 键 —— 否则月份选择器里会多出 "gap-2026" 这种假月份。
        // (这是补空日时最容易漏的一处: 它不影响时间线本身，只在点开月份弹层时才现形。)
        let months = Array(Set(groups.filter { !$0.isGap }.map { String($0.key.prefix(7)) })).sorted(by: >)
        if months.count > 1 {
            HStack(spacing: DS.Space.xs) {
                Menu {
                    Button(monthJump.isEmpty ? "全部月份" : "清除 · 全部月份") { monthJump = "" }
                    ForEach(months, id: \.self) { m in
                        Button(m) { monthJump = m }
                    }
                } label: {
                    Label(monthJump.isEmpty ? "按月份跳转" : "只看 \(monthJump)",   // 187 按月份跳转
                          systemImage: "calendar")
                        .vkFont(.caption, weight: .medium)
                }
                .accessibilityLabel(monthJump.isEmpty ? "按月份跳转" : "当前只看 \(monthJump) 月")
                Spacer(minLength: 0)
                if !monthJump.isEmpty {
                    Text("\(visibleRowCount) 条")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                    Button("清除") { monthJump = "" }
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.accentText)
                }
            }
            .frame(minHeight: DS.Hit.min - DS.Space.s)
        }
    }
    private var visibleRowCount: Int {
        groups.filter { monthJump.isEmpty || $0.key.hasPrefix(monthJump) }.reduce(0) { $0 + $1.rows.count }
    }

    private func dayLabel(_ key: String) -> String {
        if key == "__none" { return "时间未知" }
        let today = Self.dayKey(Date())
        if key == today { return "今天" }
        if let yesterday = WeekCal.gregorian.date(byAdding: .day, value: -1, to: Date()) {
            if key == Self.dayKey(yesterday) { return "昨天" }
        }
        // "yyyy-MM-dd" → "M月d日"
        let parts = key.split(separator: "-")
        if parts.count == 3 { return "\(Int(parts[1]) ?? 0)月\(Int(parts[2]) ?? 0)日" }
        return key
    }
}

// ---------- 565 告警类型多选面板 ----------
/// 对勾列表按库里**实际**告警类型渲染 (StatsKit.alarmTypes 五类)。原句列了"胁迫", 但协议日志
/// 类型表没有胁迫类 (与 725 判 ❌ 同一理由) —— 不虚构一个查不到的类型, 也在面板里把这件事写明。
/// 选中集直接绑定 filters.alarmKinds (空 = 不限类型; 选中数回显在打开的 chip 上)。
struct AlarmKindsSheet: View {
    @Binding var sel: Set<Int>
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StatsKit.alarmTypes.sorted(), id: \.self) { t in
                        Button {
                            DS.Haptics.tick.impactOccurred()
                            if sel.contains(t) { sel.remove(t) } else { sel.insert(t) }
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Text(RecordVerbs.alarmVerb[t] ?? String(t))
                                    .vkFont(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                Spacer(minLength: 0)
                                Image(systemName: sel.contains(t) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: DS.Icon.sm))
                                    .foregroundStyle(sel.contains(t) ? DS.Palette.accentText : DS.Palette.textSub)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(RecordVerbs.alarmVerb[t] ?? String(t))
                        .accessibilityAddTraits(sel.contains(t) ? .isSelected : [])
                    }
                } header: {
                    Text("只看选中的类型 · 已选 \(sel.count) 项")   // 565 只看选中的类型
                } footer: {
                    Text("不选 = 不限类型。列表按锁端日志实际有的告警类型给出; 协议无「胁迫」类告警, 不列。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("告警类型")   // 565 告警类型
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { sel.removeAll() }
                        .disabled(sel.isEmpty)
                }
            }
        }
    }
}

// ---------- 包9/574 活跃凭证排序 (台账近 30 天推断, 一律标"约") ----------
struct ActiveCredsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if app.current == nil {
                        Text("还没有添加门锁。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    } else {
                        ForEach(Array(RecordSearch.activeCredentials(mac: app.current!.mac).enumerated()), id: \.offset) { i, c in
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: Self.icon(c.kind))
                                    .font(.system(size: DS.Icon.sm))
                                    .foregroundStyle(DS.Palette.accentText)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.word + " (约)")
                                        .vkFont(.subheadline, weight: .medium)
                                        .foregroundStyle(DS.Palette.text)
                                    Text("近 30 天约 " + String(c.count) + " 次开门")
                                        .vkFont(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                                Spacer(minLength: 0)
                                Text("#" + String(i + 1))
                                    .vkFont(.caption.monospacedDigit())
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("口径: 近 30 天开门日志按凭证类计次 (台账推断, 标「约」)。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("活跃凭证排序")   // 574 活跃凭证排序
                }
            }
            .navigationTitle("活跃凭证")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
    }
    private static func icon(_ kind: String) -> String {
        switch kind {
        case "fp": return "fingerprint"
        case "pwd": return "number"
        case "temp": return "timer"
        default: return "key"
        }
    }
}

// ---------- 包9/575 越界开门清单 (本地检测, 窗口为台账 from/to, 一律标"约") ----------
struct OutWinSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    let wins = RecordSearch.outOfWindow(macs: DB.keychains().map { $0.mac })
                    if wins.isEmpty {
                        Text("没有越界开门 — 临时码都在窗口内使用 (约)。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(wins, id: \.rec.id) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: DS.Space.s) {
                                Text(w.rec.lockName)
                                    .vkFont(.caption2, weight: .medium)
                                    .lineLimit(1)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .padding(.horizontal, DS.Space.s)
                                    .padding(.vertical, 2)
                                    .variantPlate(DS.Palette.accentText.opacity(0.10), .capsule)
                                Text(w.rec.timeStr)
                                    .vkFont(.footnote.monospacedDigit())
                                    .foregroundStyle(DS.Palette.text)
                            }
                            Text("临时码窗口 " + w.window + " 外仍产生开门 — 约越界")   // 575 外仍产生开门
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("越界开门清单 (约)")
                } footer: {
                    Text("口径: 临时码台账生效区间之外仍出现一次性密码开门 (本地检测, 时刻为锁端时间)。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("越界开门")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
    }
}

