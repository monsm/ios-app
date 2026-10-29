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
    @State var groups: [DayGroup] = []
    @State var damageDays: Set<String> = []  // 596 含防撬/试错锁定/键盘锁定的自然日
    @State var rows: [RowVM] = []
    @State var allRows: [RowVM] = []
    @State var running = false
    @State var offline = false
    // 18/187 日期快速滚动锚 = 按月跳转 (同一实现，两编号别再各做一个): 筛除式而不是滚动锚定 ——
    // 把 List 包进 ScrollViewReader 要移动整条修饰符链，本机没有编译器时那条重构的代价大于收益。
    @State var monthJump = ""
    @State var pullGap: String?   // 749 本次会话未拉全的如实标注
    @State var reconLine = ""     // 749 对账结果一行 (可复制, 供发给管理员/记进工单)
    @State var sel = "" // '' 全部 / 成员id / __unknown
    // 716 选区导出: 按天整组勾选 (行级多选不做 —— 一页上千行, 逐行勾选的手势成本远高于按天勾)
    @State var showRangePick = false
    @State var rangeSel: Set<String> = []
    // ---------- 包9 检索态 (551/553/554/555/557/560/562) ----------
    @State var scope = 0             // 561/770: 0 当前锁 / 1 全部锁
    @State var searchText = ""
    @State var parsedTags: [String] = []    // 555 解析预览标签
    @State var highlightTokens: [String] = []  // 557 命中高亮词
    @State var filters = QueryFilters.load(mac: DB.preferredMac())   // 192 会话保留
    /// 2026-10-18 记录页重构: 筛选面板是否展开。默认 false = 只显示一行摘要。
    @State var filtersExpanded = false
    /// 2026-10-18: 低频区是否展开。默认收起。
    @State var secondaryRowsExpanded = false
    @State var reversed = false       // 570 正序回放
    @State var detailRec: Rec?        // 576 记录详情 sheet
    // 586 当天全景 / 583 结果定位高亮 —— 两个都是"从别处跳进时间线"的落点，用完即清。
    // dayFocus 是**显示范围**的收窄而不是筛选条件: 它不进 QueryFilters、不进 192 会话保留，
    // 否则会把你"点了一次跳转"写成"你设了一个过滤"。
    @State var dayFocus = ""
    @State var flashKey = ""
    /// 598 大数据量分页: 一次参与渲染的行数上限与"是否还有下一批"。
    /// 1200 不是凑数: 一天最忙的家也有几十条，1200 条够铺满几十个日组，
    /// 再往下滚就已经越过"人能在一次会话里读完"的量。
    /// 598 截断上限: 0 = "还没定首页" (applyFilter 第一次跑时按行池量定)。旧写法初始 1200 + 每次 +1200
    /// 看着像分页, 实际上单锁行池 ≤ ~300 条 (kf_logcache_ 上限)、全锁也远够不到 1200 ⇒ 那排「继续加载」
    /// 是永远按不到的死 UI。改成"池量分档": ≤600 全显; >600 先显 600、每按一次 +600。
    @State var shownCap = 0
    @State var capped = false
    @State var filteredTotal = 0
    /// 583 的一个真缺陷 (自己写完才看到): 深链落地时详情卡是**开着**的，
    /// 当场 flashRow 等于在一层不透明的 sheet 后面闪完 1.2 秒 —— 用户关掉时什么都看不到。
    /// 所以落地时只**记下待闪的行**，等 sheet 关闭再闪。
    @State var flashOnClose = ""
    @State var scrolledRow: String? = nil
    // 185/597 左滑(前缘/后缘两个方向)共用的行备注弹窗目标 + 草稿
    @State var noteDraft = ""
    @State var showActiveCreds = false  // 574 活跃凭证排序
    @State var showOutWin = false      // 575 越界开门清单
    @State var showAlarmKinds = false // 565 告警类型多选面板
    @State var recPool: [Rec] = []    // 跨锁/单锁 Rec 池 (576 详情查找 + 770 行映射 + 580/584 翻页源)
    /// 593 组尾「全天 N 条 / 当日最晚」的可核口径: 取本次**过滤与分页截断之前**的行池按归属日算一次。
    /// 原先这两个数取自 g.rows —— 那是筛过、截过的显示集, 于是每设一次过滤就在谎报"今天只有 3 条"。
    @State var dayFullCount: [String: Int] = [:]
    @State var dayLatest: [String: String] = [:]

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
    var noLockPlaceholder: some View {
        EmptyState(systemImage: "list.bullet.rectangle",
                   title: "还没有添加门锁",
                   message: "开门与操作记录存在门锁内。请先添加并配对门锁，再回到这里读取。",
                   actionTitle: "去添加门锁") { goAddDevice() }
    }


    /// 749 完整性对账行 —— 本次拉取多少条、锁端报剩余多少、是否拉全。
    /// 可复制（发给管理员/记进工单）。
    /// 2026-10-27 新增（AUDIT-B 2.5）：原先 `reconLine` 算完就丢，用户永远看不到。
    @ViewBuilder
    var reconRow: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(reconLine)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .textSelection(.enabled)
                if let gap = pullGap {
                    Label(gap, systemImage: "exclamationmark.triangle")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                }
            }
            Button {
                Clip.set(reconLine)
                app.showToast("对账结果已复制")
            } label: {
                Label("复制对账结果", systemImage: "doc.on.doc")
            }
            .vkFont(.caption)
            .frame(minHeight: DS.Hit.min)
        } header: {
            Text("本次拉取对账")
        }
    }

    /// 记录页主体列表 —— 2026-10-13 run 63 从 body 的 Group else 分支抽出:
    /// 整个 body 表达式报 type-check 超时。
    @ViewBuilder
    var mainList: some View {
        List {
            if offline { jumpBackRow }
            // 2026-10-28 修复：`cachedHint` 全仓零调用 —— 文案写好了但从不显示，
            // 于是用户看到的是「未连接」+ 一堆记录，却不知道这些是本机缓存、更不知道读取时间。
            if offline {
                Section {
                    Text(cachedHint)
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
            // 2026-10-27 审核修复 (AUDIT-B 2.5)：749 完整性对账**算完就丢** ——
            // `reconLine` / `pullGap` 各 3 处写、0 处读，用户永远看不到对账结果。
            // 而这段文字是「本次拉了多少条 / 锁端还报剩余多少 / 是否拉全」的唯一如实说明，
            // 正是防「把未拉全说成已拉全」那个假安慰的。现在接上显示。
            if !reconLine.isEmpty { reconRow }
            // 187 按月跳转 (等价实现): 选月即只看该月, 顶部有清除口。
            // 原设计的"月份滚轮 + scrollTo"需把 List 包进 ScrollViewReader 并移动整条修饰符链,
            // 在这个从未编译过的工程里做结构性改动的风险不对等 → 记入需编译器清单, 这里先给可用能力。
            // 2026-10-27 截图核对修复：**空态从未接线** —— `emptyHint` 定义在 1295 行，
            // 但全仓 0 处调用。于是「全部记录」展开后一条都没有时，屏幕上一片空白，
            // 用户分不清「这台锁没记录」和「读取失败/还在加载」。
            // 现在按 groups 是否为空接上（emptyHint 内部已区分"被过滤掉"与"真没记录"）。
            if groups.isEmpty { emptyHint }
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
    var macs: [String] { scope == 1 ? DB.keychains().map { $0.mac } : [mac] }
    var activeFilters: Bool {
        filters.segment != 0 || filters.dayKind != 0 || filters.lateNight || filters.alarmOnly
    }

    /// 749 对账结果导出一行 (拍板 #28)。只说本次会话内的事实, 而且**三种结论都要有对应措辞**:
    /// 拉全 / 未拉全 (带剩余条数) / 锁端没报告剩余所以不可判 —— 最后一种最容易被写成"已拉全"。
    /// 复制走 UIPasteboard 的普通文本路径 (不含口令等敏感值)。

    /// 573 生效条件数。**不含 scope**: 单锁↔全部锁是"看哪本台账"而不是过滤条件，
    /// 算进去等于让重置按钮谎报它把范围也清掉了 (它不会，也不该)。
    var activeFilterCount: Int {
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
    func copyRangeCSV() {
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
    func copyLastWeekDigest() {
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
    var lastYearTodayRow: some View {
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
    var lastYearTodayCount: Int {
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

    var firstLogDay: String? {
        DB.readLogs(mac).compactMap { $0.lockTimeStr.isEmpty ? nil : String($0.lockTimeStr.prefix(10)) }.min()
    }

    var mac: String { app.current?.mac ?? "" }
    var syncStampKey: String { "kf_logsync_" + mac }
    var totalCount: Int { allRows.count }
    var todayKey: String { Self.dayKey(Date()) }

    // ---------- 顶部状态条 ----------
    var cachedHint: String {
        if let at = lastSyncAt() {
            return "未连接门锁 — 以下为本地缓存（读取于 " + Self.stamp.string(from: at) + "）。连接锁后点「重新读取」刷新。"
        }
        return "未连接门锁 — 以下为本地缓存，读取时间未知。连接锁后点「重新读取」刷新。"
    }
    /// 136 补充 跨页跳回: 记录/告警页一键跳回设备页定位该锁
    @ViewBuilder
    var jumpBackRow: some View {
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
    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    func lastSyncAt() -> Date? {
        let raw = DB.store.getString(syncStampKey)
        guard let t = Double(raw), t > 0 else { return nil }
        return Date(timeIntervalSince1970: t / 1000)
    }
    /// 行级时刻 (554 时间短语判定): 组头日 + 时分
    func rowDate(_ r: RowVM) -> Date? {
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
    static func rowParts(_ full: String, todayKey: String) -> (dayKey: String, time: String, hour: Int) {
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
    static func isClockish(_ t: String) -> Bool {
        t.count >= 5 && t.prefix(2).allSatisfy { $0.isNumber }
    }

    /// 551 Rec → 655 动词化文案 (告警/操作/关怀各用各的动词)
    static func recTitle(_ r: Rec) -> String {
        if r.alarm || r.care || !r.failMsg.isEmpty { return r.typeName }
        let kindWord = StatsKit.openTypes.contains(r.type) ? (Attribution.words[r.kind ?? ""] ?? nil) : nil
        // 461: 与列表行同口径 — 有可证明归属时显示"称呼（备注）" (919: 别名开关开时关系称呼顶替)
        let whoShow = MemberHub.aliasName(r.whoId)
            ?? r.whoId.flatMap { DB.member($0).map(MemberHub.doubleLine) } ?? r.whoName
        return RecordVerbs.line(type: r.type, who: whoShow, kindWord: kindWord, typeName: r.typeName)
    }
    /// 577 全部锁模式下 Rec → 凭证深链 (各锁台账独立)
    static func recCredNav(_ r: Rec) -> String {
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
    var monthJumpRow: some View {
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
    var visibleRowCount: Int {
        groups.filter { monthJump.isEmpty || $0.key.hasPrefix(monthJump) }.reduce(0) { $0 + $1.rows.count }
    }

    func dayLabel(_ key: String) -> String {
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

    /// 2026-10-29 入口去重：添加设备只在设备页右上角「+」，这里只做跳转 + 指路。
    func goAddDevice() {
        app.requestRoute(.device)
        app.showToast("在设备页右上角点「+」添加门锁")
    }
}
