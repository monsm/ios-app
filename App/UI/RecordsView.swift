// 记录 Tab (records 页) — 门锁日志 (cmd16 翻页) + 成员过滤 + 归属推断 + 离线缓存
// 离线横幅只在"确实没有一次成功的实时读取"时出现, 不再每次进页都误报未连接。
// 包9 增量: 时间线升级 (578 组头吸顶 / 738 告警行红条+浅红底 / 592 连击合并 /
//           183 成员色点 / 184 开门方式图标 / 655 动词化文案 / 681 农历小字 /
//           679 年份分隔 / 649 凌晨归属 / 590 连续活跃 / 796 第N位使用者 /
//           1016 出行观察 / 785 泳道时间线) +
//           检索 (551/553/554/555/557/562/560/564/571/572/567/568/569/570/574/575/561/770) +
//           告警中心入口 (735 未处置角标) + 详情 (576/577/727/736/737/742, 见 RecordsTimeline.swift)。
// 纪律: 颜色只经 DS 令牌; 归属类统计一律标"约"; 告警类型只用真实 5 种 (6/7/10/13/224)。
import SwiftUI
import UIKit

struct RecordsView: View {
    @EnvironmentObject var app: AppState
    @State private var groups: [DayGroup] = []
    @State private var rows: [RowVM] = []
    @State private var allRows: [RowVM] = []
    @State private var running = false
    @State private var offline = false
    @State private var sel = "" // '' 全部 / 成员id / __unknown
    @State private var showAdd = false
    @State private var showGratitude = false   // 1045 感谢清单
    @State private var showExport = false      // 包12 导出中心
    @State private var showStats = false       // 包10 统计
    // ---------- 包9 检索态 (551/553/554/555/557/560/562) ----------
    @State private var scope = 0             // 561/770: 0 当前锁 / 1 全部锁
    @State private var searchText = ""
    @State private var parsedTags: [String] = []    // 555 解析预览标签
    @State private var highlightTokens: [String] = []  // 557 命中高亮词
    @State private var filters = QueryFilters()
    @State private var reversed = false       // 570 正序回放
    @State private var laneMode = false       // 785 泳道时间线 (全部锁模式)
    @State private var detailRec: Rec?        // 576 记录详情 sheet
    @State private var showActiveCreds = false  // 574 活跃凭证排序
    @State private var showOutWin = false      // 575 越界开门清单
    @State private var travelDismissed = false // 1016 出行观察横幅 (会话内可关)
    @State private var showAlarmCenter = false // 735 告警中心
    @State private var alarmTick = 0          // 735 角标刷新 (从告警中心返回时重算)
    @State private var expandedMerged: Set<String> = []  // 592 连击合并展开态
    @State private var recPool: [Rec] = []    // 跨锁/单锁 Rec 池 (576 详情查找 + 770 行映射)

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
        var mergedTail: [RowVM] = [] // 592 连击合并被折叠的后续行
        var id: String { key }
    }

    /// 按天分组, 让"最近开门"从平铺列表变成可扫读的时间线
    struct DayGroup: Identifiable {
        var key: String
        var rows: [RowVM]
        var id: String { key }
        var date: Date? { RecordSearch.dateFromKey(key) }
        var isNone: Bool { key == "__none" }
        var hasNight: Bool { rows.contains { $0.hour >= 0 && $0.hour < 5 } }   // 649 含次日凌晨
        var holiday: String? { isNone ? nil : RecordSearch.holidayName(key) }
        var lunarLabel: String? { isNone ? nil : Self.lunar(key) }
        var yearSeparate: Bool {
            guard let d = date else { return false }
            return Calendar.current.component(.month, from: d) == 1 && Calendar.current.component(.day, from: d) <= 2
        }
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

    var body: some View {
        NavigationStack {
            Group {
                if app.current == nil {
                    EmptyState(systemImage: "list.bullet.rectangle",
                               title: "还没有添加门锁",
                               message: "开门与操作记录存在门锁内。请先添加并配对门锁，再回到这里读取。",
                               actionTitle: "去添加门锁") { showAdd = true }
                } else if laneMode && scope == 1 {
                    laneView   // 785 泳道时间线 (全部锁模式简化案)
                } else {
                    List {
                        statusBanner
                        if offline { jumpBackRow }
                        travelBanner
                        streakBanner
                        activeLine
                        birthdayBanner
                        scopeRow
                        searchBar
                        if !searchText.isEmpty || activeFilters { resultCount }
                        filterChips
                        memberChips
                        doorGods
                        if groups.isEmpty && !running { emptyHint }
                        if running { runningRow }
                        ForEach(groups) { g in daySection(g) }
                        firstDayFooter
                    }
                }
            }
            .navigationTitle("记录")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // 735 告警中心入口 + 未处置角标 (口径 = RecordSearch.unhandledAlarmCount, 与告警中心 734 队列同源)
                    Button { showAlarmCenter = true } label: {
                        Image(systemName: "bell.badge.exclamationmark")
                            .overlay(alignment: .topTrailing) {
                                let n = RecordSearch.unhandledAlarmCount(DB.keychains().map { $0.mac })
                                if n > 0 {
                                    Text("\(n)")
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(DS.Palette.danger, in: Capsule())
                                        .offset(x: 12, y: -9)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .accessibilityLabel("告警中心, \(RecordSearch.unhandledAlarmCount(DB.keychains().map { $0.mac })) 条未处置")
                }
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
                        Button { showGratitude = true } label: { Label("感谢清单", systemImage: "heart.text.square") }
                        if app.current != nil {
                            Button { showExport = true } label: { Label("导出与分享 (包12)", systemImage: "square.and.arrow.up.on.square") }
                            Button { showStats = true } label: { Label("统计与图表 (包10)", systemImage: "chart.bar") }
                            Button { showActiveCreds = true } label: { Label("活跃凭证排序 (约, 574)", systemImage: "list.number") }
                            Button { showOutWin = true } label: { Label("越界开门清单 (约, 575)", systemImage: "clock.badge.exclamationmark") }
                            if scope == 1 {
                                Toggle("泳道时间线 (785)", isOn: $laneMode)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多")
                }
            }
            .onAppear {
                loadFromCache()
                Milestones.markRecordsViewed()   // 975 管家连续天数
                // 包3/779: 多锁矩阵点格带入的成员过滤 (消费后清空, 不影响手动切换)
                if let f = app.pendingRecordsFilter {
                    sel = f
                    app.pendingRecordsFilter = nil
                }
            }
            .onChange(of: app.pendingRecordsFilter) { _, f in
                guard let f else { return }
                sel = f
                applyFilter()
            }
            .onChange(of: scope) { _, s in
                sel = ""
                searchText = ""
                parsedTags = []
                highlightTokens = []
                filters = QueryFilters()
                reversed = false
                expandedMerged = []
                if s == 0 { laneMode = false }
                applyFilter()
            }
            .onChange(of: filters) { applyFilter() }
            .onChange(of: reversed) { applyFilter() }
            .onChange(of: searchText) { t in
                let q = RecordSearch.parse(t)
                parsedTags = q.parsedTags
                highlightTokens = q.must
                applyFilter()   // 562 边输入边更新
            }
        }
        .sheet(isPresented: $showAdd) { AddDeviceView() }
        .sheet(isPresented: $showGratitude) { GratitudeView() }
        .sheet(isPresented: $showExport) {
            if app.current != nil { ExportCenterView(mac: app.current!.mac) }
        }
        .sheet(isPresented: $showStats) {
            if app.current != nil { StatsView(mac: app.current!.mac) }
        }
        .sheet(isPresented: $showActiveCreds) { ActiveCredsSheet() }
        .sheet(isPresented: $showOutWin) { OutWinSheet() }
        .sheet(isPresented: $showAlarmCenter) {
            // 735 未处置角标: 从告警中心处置回来重算角标
            AlarmCenterView().onDisappear { alarmTick += 1 }
        }
        .sheet(item: $detailRec) { rec in
            RecDetailSheet(rec: rec, scopeAll: scope == 1)
        }
    }

    // ---------- 735 角标刷新 (处置状态在告警中心内变化, 返回时重算) ----------
    private var unhandledCount: Int {
        _ = alarmTick
        return RecordSearch.unhandledAlarmCount(DB.keychains().map { $0.mac })
    }

    private var macs: [String] { scope == 1 ? DB.keychains().map { $0.mac } : [mac] }
    private var activeFilters: Bool {
        filters.segment != 0 || filters.dayKind != 0 || filters.lateNight || filters.alarmOnly
            || filters.failedOnly || !filters.kind.isEmpty
    }

    // ---------- 包9: 检索 (551/553/554/555/557/560/562) ----------
    @ViewBuilder
    private var searchBar: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                    TextField("搜索: 成员 / 凭证 / 昨晚 告警 / +指纹 -临时码 (551/554/555)", text: $searchText)
                        .font(.subheadline)
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
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))

                // 554/555 解析出的条件标签 (时间短语 / 加减词 / 告警 / 失败)
                if !parsedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.xs) {
                            ForEach(Array(parsedTags.enumerated()), id: \.offset) { _, tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .padding(.horizontal, DS.Space.xs + 2)
                                    .padding(.vertical, 2)
                                    .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                                    .frame(maxWidth: 160)
                            }
                        }
                        .padding(.vertical, DS.Space.xxs)
                    }
                }
                // 553 搜索历史下拉 (kf 键存最近 10 条, 可单删 / 全清)
                if !RecordSearch.history().isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: DS.Space.s) {
                            Text("最近搜索 (553)")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                            Spacer(minLength: 0)
                            Button("全部清空") { RecordSearch.clearHistory() }
                                .font(.caption)
                                .foregroundStyle(DS.Palette.danger)
                                .frame(minWidth: 88, minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        ForEach(Array(RecordSearch.history().prefix(10)), id: \.self) { h in
                            HStack(spacing: DS.Space.s) {
                                Button {
                                    searchText = h
                                    parsedTags = RecordSearch.parse(h).parsedTags
                                    highlightTokens = RecordSearch.parse(h).must
                                    applyFilter()
                                } label: {
                                    Text(h)
                                        .font(.footnote)
                                        .lineLimit(1)
                                        .foregroundStyle(DS.Palette.text)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                                .accessibilityLabel("搜索 " + h)
                                Button { RecordSearch.removeHistory(h) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: DS.Icon.xs))
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                                .accessibilityLabel("删除这条历史")
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.top, DS.Space.xs)
                }
                // 560 命名过滤视图: 应用 / 删除 (kf_rviews, 与当前组合同源)
                if !RecordSearch.namedViews().isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("我的过滤 (560)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        ForEach(RecordSearch.namedViews()) { v in
                            HStack(spacing: DS.Space.s) {
                                Button {
                                    searchText = v.text
                                    parsedTags = RecordSearch.parse(v.text).parsedTags
                                    highlightTokens = RecordSearch.parse(v.text).must
                                    filters = v.filters
                                    scope = v.scopeAll ? 1 : 0
                                    reversed = false
                                    applyFilter()
                                } label: {
                                    Label(v.name, systemImage: "bookmark")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(DS.Palette.accentText)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                                .accessibilityLabel("应用过滤 " + v.name)
                                Button { RecordSearch.deleteNamedView(v.name) } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: DS.Icon.xs))
                                        .foregroundStyle(DS.Palette.danger)
                                }
                                .accessibilityLabel("删除过滤 " + v.name)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.top, DS.Space.xs)
                }
            }
        } header: {
            HStack {
                Text("搜索 (551)")
                Spacer(minLength: DS.Space.s)
                Menu {
                    Button { saveAsView() } label: { Label("另存当前组合 (560)", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.accentText)
                }
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
                .accessibilityLabel("另存过滤视图")
            }
        }
    }
    /// 560 把当前 文本+过滤+范围 另存为命名过滤视图 (长期复用)
    private func saveAsView() {
        let alert = UIAlertController(title: "另存过滤视图 (560)",
                                      message: "把当前搜索词与筛选组合存为命名视图, 收进「我的过滤」长期复用。",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "名称, 例如: 晚间的告警"
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let name = alert.textFields?.first?.value ?? ""
            guard !name.isEmpty else { return }
            RecordSearch.saveNamedView(name: name, text: searchText, filters: filters, scopeAll: scope == 1)
            app.showToast("已保存过滤视图「" + name + "」")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 562 实时计数 "约 N 条" (归属口径标"约", 边输入边更新)
    @ViewBuilder
    private var resultCount: some View {
        Section {
            Text(searchText.isEmpty ? "筛选后约 \(rows.count) 条" : "命中约 \(rows.count) 条 · 实时 (562)")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
        }
    }

    /// 561/770 跨锁范围切换: 单锁/全部锁; 全部锁时行首带锁名小标签 (770)
    @ViewBuilder
    private var scopeRow: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                Text("范围")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                Picker("搜索范围 (561)", selection: $scope) {
                    Text("当前锁").tag(0)
                    Text("全部锁 (770)").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if scope == 1 {
                    Button { laneMode.toggle() } label: {
                        Label(laneMode ? "看时间线" : "泳道 (785)", systemImage: "rectangle.split.3x1")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.horizontal, DS.Space.s)
                            .padding(.vertical, DS.Space.xs)
                            .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(laneMode ? "切回时间线" : "打开泳道时间线")
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
        }
    }

    // ---------- 包9: 筛选 chip 行 (564/571/572/567/568/569/570) ----------
    private static let kindOptions: [(String, String)] = [("全部凭证", ""), ("指纹", "fp"), ("密码", "pwd"), ("临时码", "temp"), ("数字钥匙", "key")]

    @ViewBuilder
    private var filterChips: some View {
        Section {
            chipRowSection("时段 (564)", selected: filters.segment) { name, i in
                _ = name
                filters.segment = i
            } items: [("全部", 0), ("早 6-9", 1), ("午 10-14", 2), ("晚 15-21", 3), ("深夜预设 (572)", 4)]
            chipRowSection("工作日/周末 (571)", selected: filters.dayKind) { name, i in
                _ = name
                filters.dayKind = i
            } items: [("全部", 0), ("仅工作日", 1), ("仅周末", 2)]
            let kindIdx = Self.kindOptions.firstIndex(where: { $0.1 == filters.kind }) ?? 0
            chipRowSection("凭证 (约, 568)", selected: kindIdx) { name, _ in
                filters.kind = Self.kindOptions.first(where: { $0.0 == name })?.1 ?? ""
            } items: Self.kindOptions.enumerated().map { i, t in (t.0, i) }
            HStack(spacing: DS.Space.s) {
                chipToggle("仅告警 (567)", on: $filters.alarmOnly)
                chipToggle("失败 (锁端仅告警级, 569)", on: $filters.failedOnly)
                chipToggle(reversed ? "最早在前" : "正序回放 (570)", on: $reversed)
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
            if filters.failedOnly {
                // ⚠569: 锁端仅记录告警级 (10/13/224), 无逐次失败明细 — 文案已标注
                Text("注: 失败筛选只收录告警级锁定/指纹告警与手机侧开锁失败, 锁端不上报逐次失败 (569 ⚠)")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            HStack {
                Text("筛选 (564/571/572/567/568/569)")
                Spacer(minLength: DS.Space.s)
                if activeFilters {
                    Button("复位") {
                        filters = QueryFilters()
                        reversed = false
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            }
        }
    }
    private func chipRowSection(_ title: String, selected: Int, items: [(String, Int)], pick: @escaping (_ name: String, _ i: Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .font(.caption)
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
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on ? Color.white : DS.Palette.text)
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
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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

    // ---------- 顶部情绪行 ----------
    /// 975 管家连续天数
    @ViewBuilder
    private var streakBanner: some View {
        let s = Milestones.streak()
        if s.cur >= 1 {
            Section {
                Label {
                    Text(s.cur > 1 ? "管家连续 \(s.cur) 天 · 最佳 \(s.best) 天" : "管家第 1 天, 明天也要来")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "flame.fill").accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.accentText)
            }
        }
    }

    /// 590 连续活跃行: "连续 N 天有人开门" (口径 = 有开门类事件的自然日, 断档即止)
    @ViewBuilder
    private var activeLine: some View {
        let n = openStreakDays
        if n >= 2 {
            Section {
                Label {
                    Text("连续 \(n) 天有人开门 · 这个家一直在 (590)")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "flame").accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.ok)
            }
        }
    }
    private var openStreakDays: Int {
        let daySet = Set(rows.filter { $0.kind != nil || StatsKit.openTypes.contains($0.type) }.map(\.dayKey))
        guard daySet.contains(Self.dayKey(Date())) else { return 0 }
        var n = 0
        var d = Calendar.current.startOfDay(for: Date())
        while daySet.contains(Self.dayKey(d)) {
            n += 1
            d = Calendar.current.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }

    /// 1016 出行观察横幅: 连续 3 天无开门 "近期没人回家?" (静默观察, 可关闭)
    @ViewBuilder
    private var travelBanner: some View {
        if !travelDismissed, let last = lastOpenDate, Date().timeIntervalSince(last) >= 3 * 86400 {
            Section {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "airplane")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("近期没人回家? (1016)")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.text)
                        Text("已连续 " + String(Int(Date().timeIntervalSince(last) / 86400)) + " 天没有开门记录 — 出行观察中, 一切正常可忽略。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { travelDismissed = true } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .frame(minWidth: DS.Hit.min, minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                    .accessibilityLabel("关闭出行观察横幅")
                }
                .padding(.vertical, DS.Space.xs)
            }
        }
    }
    private var lastOpenDate: Date? {
        var last: Date? = nil
        for m in macs {
            for l in DB.readLogs(m) where StatsKit.openTypes.contains(l.type) {
                if let d = StatsKit.dateOf(l) { last = max(last ?? d, d) }
            }
        }
        return last
    }

    /// 991 生日撒花: 当天寿星横幅
    @ViewBuilder
    private var birthdayBanner: some View {
        if let m = Milestones.birthdayCelebrantToday {
            Section {
                Label {
                    Text("今天是\(m.name)的生日, 替我们说声生日快乐")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "party.popper").accessibilityHidden(true)
                }
                .font(.footnote)
                .foregroundStyle(DS.Palette.accentText)
            }
        }
    }

    /// 983 本月门神榜 + 989/994 成员徽章角标
    @ViewBuilder
    private var doorGods: some View {
        let rank = doorRank
        if let top = rank.first, top.count > 0 {
            Section("本月门神榜") {
                ForEach(Array(rank.enumerated()), id: \.element.id) { i, r in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: i == 0 ? "crown.fill" : "person.fill")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(i == 0 ? DS.Palette.warn : DS.Palette.textSub)
                            .accessibilityHidden(true)
                        Text(r.name)
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        if let bid = Milestones.memberBadges()[r.id], let b = Milestones.badge(bid) {
                            Image(systemName: b.icon)
                                .font(.system(size: DS.Icon.xs))
                                .foregroundStyle(DS.Palette.accentText)
                                .accessibilityLabel("徽章 " + b.title)
                        }
                        Spacer(minLength: 0)
                        if i == 0 {
                            Text("本月门神")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(DS.Palette.accentText)
                        }
                        Text("\(r.count) 次")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
    private var doorRank: [(id: String, name: String, count: Int)] {
        let mk = Milestones.monthKey()
        var counts: [String: Int] = [:]
        for r in allRows where r.whoId != nil && r.dayKey.hasPrefix(mk) {
            counts[r.whoId!, default: 0] += 1
        }
        return counts.map { (id: $0.key, name: DB.member($0.key)?.name ?? "成员", count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// 190 第一扇门纪念: 滚到最早记录的结语行
    @ViewBuilder
    private var firstDayFooter: some View {
        if let first = firstLogDay, !groups.isEmpty {
            Section {
                Text("—— 这里是与这把锁的第一天 · \(chineseDay(first)) ——")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DS.Space.m)
                    .accessibilityLabel("这里是与这把锁的第一天, " + chineseDay(first))
            }
        }
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
    @ViewBuilder
    private var statusBanner: some View {
        if offline {
            Section {
                Label {
                    Text(cachedHint)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "wifi.slash").accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.warn)
            }
        } else if let at = lastSyncAt() {
            Section {
                Label {
                    Text("上次成功读取：" + Self.stamp.string(from: at))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath").accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
            }
        }
    }
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
                app.tabSelection = 0
            } label: {
                Label("跳回设备页定位「" + LockArchive.displayName(app.devices.first { $0.mac == mac } ?? Keychain(mac: mac, skey: "")) + "」", systemImage: "lock.rotation")
            }
            .font(.footnote)
            .foregroundStyle(DS.Palette.accentText)
        }
    }
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
    private func lastSyncAt() -> Date? {
        let raw = DB.store.getString(syncStampKey)
        guard let t = Double(raw), t > 0 else { return nil }
        return Date(timeIntervalSince1970: t / 1000)
    }

    // ---------- 时间线 (包9 升级: 578 组头吸顶 / 738 告警行 / 592 连击 / 655 动词 / 679 年份 / 681 农历 / 649 凌晨) ----------
    /// 578 List Section header 即原生吸顶 — 滚动时组头钉在顶部, 跨组自动交接
    private func daySection(_ g: DayGroup) -> some View {
        // 653 生日组头: 该成员生日日 (MM-dd 命中组头日期) → "今日是妈妈的生日"标签
        let bday = g.key.count == 10 ? String(g.key.suffix(5)) : ""
        let celebrant = bday.isEmpty ? nil : (Milestones.memberBirthdays().first { $0.value == bday }.map { DB.member($0.key) }.flatMap { $0 })
        let showYear = g.yearSeparate   // 679 年份大字分隔 (1 月 1-2 日组头)
        let hasAlarm = g.rows.contains(\.warn)
        let openN = g.rows.filter { StatsKit.openTypes.contains($0.type) || $0.kind != nil }.count
        let alarmN = g.rows.filter(\.warn).count
        return Section {
            ForEach(g.rows) { r in
                if r.mergedTail.isEmpty {
                    timelineRow(r)
                } else if expandedMerged.contains(r.key) {
                    // 592 展开态: 首行 + 被折叠的明细逐条列出
                    timelineRow(r)
                    ForEach(r.mergedTail) { t in
                        timelineRow(t)
                    }
                } else {
                    mergedRow(r)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                if showYear {
                    if let y = g.date {
                        Text(String(Calendar.current.component(.year, from: y)) + " 年")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                HStack(spacing: DS.Space.s) {
                    Text(dayLabel(g.key))
                        .font(.headline)
                    // 671 节假日组头标签 (内置 2026-2027 简表, 手工维护)
                    if let h = g.holiday {
                        Text(h)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.warn)
                    }
                    // 649 凌晨归属: 组内含 0:00-4:59 事件时注明
                    if g.hasNight {
                        Text("含次日凌晨")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    if let c = celebrant {
                        Text("今天是" + c.name + "的生日")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.warn)
                    }
                    Spacer(minLength: DS.Space.s)
                    // 588 组头计数徽标: 开门 N · 告警 M (含告警日染浅红)
                    HStack(spacing: DS.Space.xs) {
                        Text("\(openN) 开")
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                        if alarmN > 0 {
                            Text("\(alarmN) 警")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(DS.Palette.danger)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(hasAlarm ? DS.Palette.danger.opacity(0.10) : DS.Palette.surfaceAlt, in: Capsule())
                }
                HStack(spacing: DS.Space.s) {
                    // 681 农历小字 (中国历法直接支持, 失败静默隐藏)
                    if let lunar = g.lunarLabel {
                        Text(lunar)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    // 796 本日使用者 (组头小字, 归属推断标"约")
                    if g.key == todayKey, g.distinctUsers > 0 {
                        Text("约 \(g.distinctUsers) 位使用者")
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    Text("\(g.rows.count) 条")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.xs)
            .background(hasAlarm ? DS.Palette.danger.opacity(0.04) : Color.clear)
        }
    }

    /// 592 连击合并行: 同日同类型连续 ≥3 条折叠为 "连续 N 次" 单行, 点按展开明细
    private func mergedRow(_ r: RowVM) -> some View {
        let total = r.mergedTail.count + 1
        return Button {
            withAnimation(DS.Motion.quick) { expandedMerged.insert(r.key) }
        } label: {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Text(r.time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(width: 42, alignment: .trailing)
                    .padding(.top, 2)
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 12)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                HStack(spacing: DS.Space.s) {
                    kindIcon(r)
                    Text(r.title + " · 连续 " + String(total) + " 次 (592)")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: DS.Icon.xs))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, DS.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .frame(minHeight: DS.Hit.min)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.l, bottom: 0, trailing: DS.Space.l))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("连续 " + String(total) + " 次: " + r.title + ", 点按展开")
        .accessibilityHint("点按展开这 " + String(total) + " 条")
    }

    /// 单条: 左时间列 + 时间轴(圆点与连线) + 事件文案
    /// 738 告警行: 左侧 3pt danger 色条 + danger 8% 浅底 (菱形警示点形状冗余);
    /// 184 开门方式图标 / 183 成员色点 (可证明归属才显) / 770 锁名小标签 / 557 命中高亮
    private func timelineRow(_ r: RowVM) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Text(r.time)
                .font(.caption.monospacedDigit())
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
                // 770 全部锁时行首带锁名小标签
                if !r.lockName.isEmpty {
                    Text(r.lockName)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(DS.Palette.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                        .frame(maxWidth: 110)
                        .accessibilityLabel("锁 " + r.lockName)
                }
                // 184 开门方式图标: fp 指纹 / pwd 数字 / temp 一次性 / key 钥匙
                kindIcon(r)
                // 183 成员色点: 可证明归属才显示 (成员档案色, 6pt 圆点)
                memberDot(r)
                rowTitle(r)
                    .padding(.top, 1)
                if r.claim {
                    // 791 未归属记录认领: 行内直达, 写入本机覆盖层 (不改锁端数据)
                    Button { claimRow(r) } label: {
                        Text("认领")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.horizontal, DS.Space.s)
                            .padding(.vertical, DS.Space.xs)
                            .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                            .frame(minHeight: DS.Hit.min + 16)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                // 575 越界小字 (约): 临时码窗口外仍开门
                if !r.winText.isEmpty {
                    Text(r.winText)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(DS.Palette.warn)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 738 告警行: 左侧 3pt 色条 + 浅红底 (danger 派生, 形状冗余)
        .background(alarmBG(r))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.l, bottom: 0, trailing: DS.Space.l))
        .contentShape(Rectangle())
        // 576 行点开进详情 sheet (全字段 + 告警 727 清单 + 736 前后 3 条)
        .onTapGesture { detailRec = lookupRec(r) }
        .contextMenu {
            // 714 复制为完整文本: 粘贴即有锁名+时间+归属的完整上下文
            Button {
                UIPasteboard.general.string = "[" + (r.lockName.isEmpty ? app.displayName : r.lockName) + "] " + r.time + " " + r.title
                app.showToast("已复制本条记录")
            } label: {
                Label("复制为文本 (714)", systemImage: "doc.on.doc")
            }
            if !r.credKey.isEmpty {
                Button {
                    app.pendingCredNav = r.credKey
                    app.pendingCredNavMac = r.rowMac.isEmpty ? mac : r.rowMac
                    app.tabSelection = 1
                    app.showToast("已定位到来源凭证 (577)")
                } label: {
                    Label("定位来源凭证 (577)", systemImage: "key.horizontal")
                }
            }
        }
        .accessibilityElement(children: .combine)
        // 850 时间线自然语朗读: "今天 14:02, 张三用指纹开了门" 而非字段堆叠
        .accessibilityLabel(AXTerms.rowSentence(dayKey: r.dayKey,
                                                 time: r.time,
                                                 title: r.title,
                                                 warn: r.warn,
                                                 isToday: r.dayKey == todayKey,
                                                 dayLabel: dayLabel(r.dayKey)))
        .accessibilityAddTraits([.isButton])
    }
    /// 557 命中词高亮: 搜索词在行文案中染 accentText 浅底 (分段 Text, 换行跟随整体流)
    @ViewBuilder
    private func rowTitle(_ r: RowVM) -> some View {
        if highlightTokens.isEmpty {
            Text(r.title)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 0) {
                ForEach(highlightSegments(r.title), id: \.offset) { seg in
                    if seg.hit {
                        Text(seg.text)
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.vertical, 1)
                            .background(DS.Palette.accentText.opacity(0.18), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else {
                        Text(seg.text)
                            .font(.subheadline)
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
    /// 738 告警行背景: danger 8% 浅底 + 左侧 3pt 色条
    private func alarmBG(_ r: RowVM) -> some View {
        Rectangle()
            .fill(r.warn ? DS.Palette.danger.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) {
                if r.warn {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Palette.danger)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
            }
    }
    /// 184 开门方式图标: kind → SF 符号 (fp 指纹 / pwd 数字键盘 / temp 一次性 / key 钥匙)
    @ViewBuilder
    private func kindIcon(_ r: RowVM) -> some View {
        let sym: String
        switch r.kind {
        case "fp": sym = "fingerprint"
        case "pwd": sym = "number"
        case "temp": sym = "timer"
        case "key": sym = "key"
        default: sym = ""
        }
        if !sym.isEmpty {
            Image(systemName: sym)
                .font(.system(size: DS.Icon.xs))
                .foregroundStyle(DS.Palette.accentText)
                .padding(.top, 3)
                .accessibilityHidden(true)
        }
    }
    /// 183 成员色点: 可证明归属才显示 (成员档案色, 6pt 圆点)
    @ViewBuilder
    private func memberDot(_ r: RowVM) -> some View {
        if let id = r.whoId, !id.isEmpty, let m = DB.member(id) {
            Circle()
                .fill(memberColor(m))
                .frame(width: 6, height: 6)
                .padding(.top, 12)
                .accessibilityLabel("成员 " + m.name + " 的色点")
        }
    }
    /// 183 成员色 (走成员档案 hex, 与 SecurityCenterView 同一纪律)
    private func memberColor(_ m: Member) -> Color {
        var s = m.color
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16)
        return v == nil ? DS.Palette.accent : Color(hex: v!)
    }
    /// 576 行 key → Rec (单锁池 key = idxRaw/f_x/c_x; 全部锁池 key = mac#idxRaw)
    private func lookupRec(_ r: RowVM) -> Rec? {
        recPool.first { $0.id == r.key } ?? recPool.first { $0.key == r.key && $0.mac == (r.rowMac.isEmpty ? mac : r.rowMac) }
    }

    /// 791 认领: 列成员选择, 写入 MemberHub.claims 覆盖层 (本机, 锁端数据不动)
    private func claimRow(_ r: RowVM) {
        let kindWord = r.whoKind.map { Attribution.words[$0] ?? "记录" } ?? "记录"
        let alert = UIAlertController(title: "认领未归属记录 (791)",
                                      message: "台账推断这条「" + kindWord + "开门」发生在 " + r.time
                                              + ", 认领给哪位成员?",
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        for m in DB.members().filter({ !MemberHub.ext($0.id).archived }) {
            alert.addAction(UIAlertAction(title: m.name, style: .default) { _ in
                MemberHub.claim(mac, logKey: r.key, memberId: m.id)
                app.showToast("已认领给「" + m.name + "」(本机覆盖层)")
                loadFromCache()
            })
        }
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    private var emptyHint: some View {
        Section {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Image(systemName: "tray")
                    .font(.system(size: DS.Icon.lg))
                    .foregroundStyle(DS.Palette.accentText)
                    .accessibilityHidden(true)
                Text("还没有记录。点右上角「重新读取」从锁内拉取最近 100 条开门/操作记录。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 1044 家庭公告板
                if !Milestones.bulletin.isEmpty {
                    Text("公告: " + Milestones.bulletin)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, DS.Space.m)
            .accessibilityElement(children: .combine)
        }
    }
    private var runningRow: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                ProgressView()
                Text("正在读取锁内记录…")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
            .padding(.vertical, DS.Space.s)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在读取锁内记录")
        }
    }

    // ---------- 成员过滤 (保留既有 793 访客虚拟分组 / 791 可认领 / 1028 保养) ----------
    private var memberChips: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip("", "全部")
                    ForEach(DB.members()) { m in
                        if rows.contains(where: { $0.whoId == m.id }) { chip(m.id, m.name) }
                    }
                    if rows.contains(where: { $0.whoId == nil && $0.whoKind == "temp" }) {
                        chip(MemberHub.visitorId, "访客 (793)")
                    }
                    if rows.contains(where: { $0.whoId == nil && $0.whoKind != "temp" }) {
                        chip("__unknown", "无法识别 · 可认领")
                    }
                    if allRows.contains(where: { $0.care }) { chip("__care", "保养") }   // 1028
                }
                .padding(.vertical, DS.Space.xxs)
            }
        } header: {
            HStack {
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
            applyFilter()
        } label: {
            Text(name)
                // 字重固定: 改字重会改变字形宽度, 胶囊随之跳变
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)   // 撑到 ≥44pt 触达
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on ? Color.white : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // ---------- 785 泳道时间线 (全部锁简化案): 按锁分组的平行小点阵, 同日水平对齐 ----------
    private var laneView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("泳道时间线 (785): 最近 14 天 × 各锁的开门量, 点阵越密越热闹")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(laneDays) { day in
                    laneRow(day)
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
        }
        .dsScreenBackground()
    }
    struct LaneDay: Identifiable {
        var key: String
        var cells: [(name: String, count: Int, alarm: Bool)]
        var id: String { key }
    }
    private var laneDays: [LaneDay] {
        let allMacs = DB.keychains().map { $0.mac }
        var names: [String: String] = [:]
        for kc in DB.keychains() { names[kc.mac] = LockArchive.displayName(kc) }
        var byDay: [String: [String: (n: Int, a: Int)]] = [:]
        for m in allMacs {
            for l in DB.readLogs(m) {
                guard let d = StatsKit.dateOf(l) else { continue }
                let k = Self.dayKey(d)
                var dict = byDay[k] ?? [:]
                var e = dict[m] ?? (n: 0, a: 0)
                if StatsKit.openTypes.contains(l.type) { e.n += 1 }
                if StatsKit.alarmTypes.contains(l.type) { e.a += 1 }
                dict[m] = e
                byDay[k] = dict
            }
        }
        var out: [LaneDay] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in 0..<14 {
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            let k = Self.dayKey(d)
            let cells = allMacs.map { m -> (name: String, count: Int, alarm: Bool) in
                (names[m] ?? m, byDay[k]?[m]?.n ?? 0, (byDay[k]?[m]?.a ?? 0) > 0)
            }
            out.append(LaneDay(key: k, cells: cells))
        }
        return out
    }
    private func laneRow(_ day: LaneDay) -> some View {
        let hasAlarm = day.cells.contains { $0.alarm }
        return HStack(spacing: DS.Space.s) {
            Text(dayLabel(day.key))
                .font(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 64, alignment: .trailing)
            HStack(spacing: DS.Space.xs + 2) {
                ForEach(Array(day.cells.enumerated()), id: \.offset) { _, c in
                    let dots = min(c.count / 2, 8)
                    HStack(spacing: 3) {
                        ForEach(0..<max(dots, 0), id: \.self) { _ in
                            Circle()
                                .fill(c.alarm ? DS.Palette.danger : DS.Palette.accent)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                        if c.count > 0 {
                            Text("×" + String(c.count))
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(c.alarm ? DS.Palette.danger : DS.Palette.textSub)
                        }
                    }
                    .frame(minWidth: 52, alignment: .leading)
                    .accessibilityLabel(c.name + " 当日 " + String(c.count) + " 次开门" + (c.alarm ? ", 含告警" : ""))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Space.xs)
        .background(hasAlarm ? DS.Palette.danger.opacity(0.05) : Color.clear,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    // ---------- 数据 ----------
    private func loadFromCache() {
        let cached = DB.readLogs(mac)
        guard !cached.isEmpty else { return }
        // 有过成功读取记录 = 缓存可信, 不再报"未连接"; 从没成功读过才算离线
        render(cached.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
               offline: lastSyncAt() == nil)
    }

    private func fetch() async {
        guard !running, let kc = app.current else { return }
        running = true
        offline = false
        var events = [LogEntry]()
        do {
            // 现场 03 背书 (R2 唯一规则), 失败不阻断
            if let st = try? await app.lock.getStatus(mac: kc.mac) { app.status = st }
            var startIdx: UInt32 = 0xFFFFFFFF
            var page = 0
            while page < 20 && events.count < 100 {
                let r = try await app.lock.getLogs(orderType: 0, startIdx: startIdx, pageSize: 5)
                guard !r.logs.isEmpty else { break }
                events.append(contentsOf: r.logs)
                DB.writeLogs(kc.mac, r.logs)
                if (r.surplus ?? 0) > 0 {
                    startIdx = r.logs.last!.idxRaw &- 1
                    page += 1
                } else { break }
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
        let fails = DB.failEvents(mac)
        if !fails.isEmpty {
            merged.append(contentsOf: fails.enumerated().map { i, e in
                LogEntry(type: 0, typeName: e.msg.isEmpty ? "开锁失败" : "开锁失败 · " + e.msg,
                         idx: 0,
                         idxRaw: UInt32(truncatingIfNeeded: Int(e.ts * 1000) + i),
                         lockTime: 0,
                         lockTimeStr: failTimeStr(e.ts),
                         body: "")
            })
            merged.sort { $0.lockTimeStr > $1.lockTimeStr }
        }
        // 1014/1028 (包4): 保养/换电手机侧维护事件合入时间线 (kf_mevents_, 与锁日志严格分开)
        let cares = BatteryCare.events(mac)
        if !cares.isEmpty {
            merged.append(contentsOf: cares.enumerated().map { i, e in
                LogEntry(type: 0,
                         typeName: e.kind == "battery" ? "更换电池" : "保养完成 · " + e.note,
                         idx: 0,
                         idxRaw: UInt32(truncatingIfNeeded: Int(e.ts) + i),
                         lockTime: 0,
                         lockTimeStr: failTimeStr(e.ts / 1000),
                         body: "")
            })
            merged.sort { $0.lockTimeStr > $1.lockTimeStr }
        }
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
            let full = e.lockTimeStr                       // "yyyy-MM-dd HH:mm:ss"
            let hh = full.count >= 13 ? (Int(full.dropFirst(11).prefix(2)) ?? -1) : -1
            // 649 凌晨归属前一晚: 0:00-4:59 归前一天分组 (组头注明"含次日凌晨")
            var dayKey = full.count >= 10 ? String(full.prefix(10)) : ""
            if dayKey.count == 10, hh >= 0, hh < 5, let d0 = RecordSearch.dateFromKey(dayKey) {
                dayKey = RecordSearch.dayKeyOf(d0.addingTimeInterval(-86400))
            }
            var whoId = c.who
            if let claimed = claims[String(e.idxRaw)] { whoId = claimed }   // 791 认领优先
            let whoName = whoId.flatMap { DB.member($0)?.name }
            // 655 动词化日志文案: "张三 用 指纹 开了门" (保留 791 认领与 1028 关怀行)
            let care = e.type == 0 && (e.typeName.hasPrefix("保养") || e.typeName.hasPrefix("更换电池"))
            let title: String
            if care || e.type == 0 {
                title = e.typeName   // 关怀/失败手机侧行保留原貌
            } else {
                let kindWord = StatsKit.openTypes.contains(e.type) ? (Attribution.words[c.kind ?? ""] ?? nil) : nil
                title = RecordVerbs.line(type: e.type, who: whoName, kindWord: kindWord, typeName: e.typeName)
            }
            // 今天只显示时分, 跨天显示日期+时分
            let time: String
            if full.count >= 16 {
                time = (dayKey == todayKey)
                    ? String(full.dropFirst(11).prefix(5))
                    : String(full.dropFirst(5).prefix(11))
            } else {
                time = "--:--"
            }
            let warn = StatsKit.alarmTypes.contains(e.type)
            // 791 可认领: 未归属且还没有认领记录 (temp 类进 793 访客虚拟分组, 不认领)
            let claimable = whoId == nil && c.kind != "temp" && !claims.keys.contains(String(e.idxRaw))
            out.append(RowVM(key: String(e.idxRaw), time: time,
                             dayKey: dayKey.isEmpty ? "__none" : dayKey,
                             hour: hh, type: e.type,
                             title: title, whoId: whoId, whoKind: c.kind,
                             kind: c.kind, lockName: "", rowMac: mac,
                             credKey: Self.credNav(kind: c.kind, who: whoName, pwds: pwds, fps: fps),
                             warn: warn, claim: claimable, care: care))
        }
        // 592 连击合并: 同日同类型连续 ≥3 条折叠为 "连续 N 次"
        out = mergeConsecutive(out)
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
    /// 592 连击合并: 同 dayKey 同 kind 非告警 连续 ≥3 条 → 首行挂 mergedTail, 可点展开
    private func mergeConsecutive(_ list: [RowVM]) -> [RowVM] {
        var out = [RowVM]()
        var run = [RowVM]()
        func flush() {
            if run.count >= 3, let f = run.first, f.kind != nil, !f.warn,
               run.allSatisfy({ $0.dayKey == f.dayKey && $0.kind == f.kind && !$0.warn }) {
                var head = f
                head.mergedTail = Array(run.dropFirst())
                out.append(head)
            } else {
                out.append(contentsOf: run)
            }
            run = []
        }
        for r in list {
            if let f = run.last, r.kind == f.kind, r.dayKey == f.dayKey, !r.warn, !f.warn, r.key != f.key {
                run.append(r)
            } else {
                flush()
                run = [r]
            }
        }
        flush()
        return out
    }

    private static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }

    /// 92: 手机侧失败时刻 → 与锁日志同格式的 "yyyy-MM-dd HH:mm:ss" (可排序)
    private func failTimeStr(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    /// 551/554/555/564/571/572/567/568/569/570/770: 单锁 = 本地池; 全部锁 = 跨锁 Rec 池
    private func applyFilter() {
        let pool: [RowVM]
        if scope == 0 {
            pool = allRows
        } else {
            // 770 全部锁: Rec 池 → RowVM (行首带锁名小标签, 575 越界窗口小字)
            let recs = RecordSearch.buildRecs(macs: macs, includeFails: true, includeCare: true)
            let outWins = RecordSearch.outOfWindow(macs: macs)
            var winMap = [String: String]()
            for w in outWins { winMap[w.rec.mac + "#" + w.rec.key] = w.window }
            pool = recs.map { r -> RowVM in
                let full = r.timeStr
                let hh = full.count >= 13 ? (Int(full.dropFirst(11).prefix(2)) ?? -1) : -1
                var dayKey = full.count >= 10 ? String(full.prefix(10)) : "__none"
                if dayKey.count == 10, hh >= 0, hh < 5, let d0 = RecordSearch.dateFromKey(dayKey) {
                    dayKey = RecordSearch.dayKeyOf(d0.addingTimeInterval(-86400))
                }
                let timeStr: String
                if full.count >= 16 {
                    timeStr = (dayKey == todayKey) ? String(full.dropFirst(11).prefix(5)) : String(full.dropFirst(5).prefix(11))
                } else {
                    timeStr = "--:--"
                }
                return RowVM(key: r.mac + "#" + r.key, time: timeStr, dayKey: dayKey, hour: hh, type: r.type,
                             title: Self.recTitle(r), whoId: r.whoId, whoKind: r.kind,
                             kind: r.kind, lockName: r.lockName, rowMac: r.mac,
                             credKey: Self.recCredNav(r), winText: winMap[r.mac + "#" + r.key] ?? "",
                             warn: r.alarm, claim: false, care: r.care)
            }
            pool = mergeConsecutive(pool)
            recPool = recs
        }
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
            filtered = filtered.filter { r in
                let whoStr = r.whoId.flatMap { DB.member($0)?.name ?? "" } ?? ""
                let txt = r.title + " " + r.lockName + " " + whoStr
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
                    if filters.lateNight && !RecordSearch.isLateNight(hour) { return false }
                    switch filters.segment {
                    case 1: if !(6...9).contains(hour) { return false }
                    case 2: if !(10...14).contains(hour) { return false }
                    case 3: if !(15...21).contains(hour) { return false }
                    case 4: if !RecordSearch.isLateNight(hour) { return false }
                    default: break
                    }
                    if let d = RecordSearch.dateFromKey(r.dayKey) {
                        let wk = Calendar.current.component(.weekday, from: d)
                        let isWeekend = wk == 1 || wk == 7
                        if filters.dayKind == 1 && isWeekend { return false }
                        if filters.dayKind == 2 && !isWeekend { return false }
                    }
                } else if filters.segment != 0 || filters.lateNight || filters.dayKind != 0 {
                    return false   // 时刻未知行不进时段/周末口径 (594 节假日色带见 DEFERRED)
                }
                if filters.alarmOnly && !r.warn { return false }
                // ⚠569: 锁端仅记录告警级 (10/13/224) + 手机侧失败行, 无逐次失败明细
                if filters.failedOnly, !([10, 13, 224].contains(r.type) || (r.type == 0 && !r.care)) { return false }
                if !filters.kind.isEmpty, r.kind != filters.kind { return false }
                return true
            }
        }
        // 570 正序回放: 整段反转 (时间线从最早逐条回放)
        if reversed { filtered = filtered.reversed() }
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
    /// 551 Rec → 655 动词化文案 (告警/操作/关怀各用各的动词)
    private static func recTitle(_ r: Rec) -> String {
        if r.alarm || r.care || !r.failMsg.isEmpty { return r.typeName }
        let kindWord = StatsKit.openTypes.contains(r.type) ? (Attribution.words[r.kind ?? ""] ?? nil) : nil
        return RecordVerbs.line(type: r.type, who: r.whoName, kindWord: kindWord, typeName: r.typeName)
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
            if let f = fps.first(where: { (r.whoName == nil) || ($0.owner == r.whoName) || (r.whoName.map { $0.name.contains($0) } ?? false) }) { return "fp:" + String(f.batch) }
        default:
            break
        }
        return ""
    }

    private func dayLabel(_ key: String) -> String {
        if key == "__none" { return "时间未知" }
        let today = Self.dayKey(Date())
        if key == today { return "今天" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            if key == Self.dayKey(yesterday) { return "昨天" }
        }
        // "yyyy-MM-dd" → "M月d日"
        let parts = key.split(separator: "-")
        if parts.count == 3 { return "\(Int(parts[1]) ?? 0)月\(Int(parts[2]) ?? 0)日" }
        return key
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
                            .font(.footnote)
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
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(DS.Palette.text)
                                    Text("近 30 天约 " + String(c.count) + " 次开门")
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                                Spacer(minLength: 0)
                                Text("#" + String(i + 1))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("口径: 近 30 天开门日志按凭证类计次 (台账推断, 标"约")。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("活跃凭证排序 (574)")
                }
            }
            .navigationTitle("活跃凭证")
            .scrollContentBackground(.hidden)
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
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(wins, id: \.rec.id) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: DS.Space.s) {
                                Text(w.rec.lockName)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                                Text(w.rec.timeStr)
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(DS.Palette.text)
                            }
                            Text("临时码窗口 " + w.window + " 外仍产生开门 — 约越界 (575)")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("越界开门清单 (575, 约)")
                } footer: {
                    Text("口径: 临时码台账生效区间之外仍出现一次性密码开门 (本地检测, 时刻为锁端时间)。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("越界开门")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
    }
}

// ---------- 1045 感谢清单 (本地按月留存, 可生成感谢卡文本) ----------
struct GratitudeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String] = []
    @State private var input = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: DS.Space.m) {
                        TextField("本月想感谢谁?", text: $input)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("添加", action: add)
                            .buttonStyle(SecondaryActionStyle(fullWidth: false))
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("本月感谢清单")
                } footer: {
                    Text("记下这个月为这扇门出过力的人, 全部只存在本机。")
                }
                Section {
                    if names.isEmpty {
                        Text("还没有记录, 从一句谢谢开始。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(names, id: \.self) { n in
                        HStack {
                            Image(systemName: "heart.fill")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(DS.Palette.danger)
                                .accessibilityHidden(true)
                            Text(n)
                                .font(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                            Spacer(minLength: 0)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Milestones.removeGratitude(n)
                                reload()
                            } label: { Label("移除", systemImage: "trash") }
                        }
                    }
                }
                if !names.isEmpty {
                    Section {
                        Button {
                            UIPasteboard.general.string = "本月想感谢: " + names.joined(separator: "、")
                                + "。谢谢你, 把家管得有人情味。"
                            app.showToast("感谢卡已复制")
                        } label: {
                            Label("生成感谢卡 (复制文本)", systemImage: "doc.on.doc")
                                .frame(minHeight: DS.Hit.min)
                        }
                    }
                }
            }
            .navigationTitle("感谢清单")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .onAppear(perform: reload)
        }
    }
    private func add() {
        Milestones.addGratitude(input)
        input = ""
        reload()
    }
    private func reload() { names = Milestones.gratitude() }
}
