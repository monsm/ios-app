// RecordsScreen.swift —— 记录（Tab 3）。v7 结构重写，参考 R3-records.html / TOKENS.md 参考 C。
//
// 实测来源：头部标题 22pt/600 left 21、日期 11.5pt #8E8E93、头像 Ø34；
// 今日活动卡 352×196.7 r16；三环外径 133.7、环宽 14、间隙 1.2、12 点起圆头；
// 微卡 170.7×178 r16 #1C1C1E；24 格柱图网格高 57、柱宽 1.8 r0.9；微卡大数字 30pt/600。
// 数据绑定保持原口径：RecordsSource / LedgerFilter / RecordsRoute / RecordsOverlay / Router 不变。
import SwiftUI

struct RecordsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private let overlay = RecordsOverlay.shared
    private let route = RecordsRoute.shared

    @State private var query = ""
    @State private var scope: LedgerScope = .all
    @State private var member = ""
    @State private var lockScope: RecordLockScope = .current
    @State private var selectedMac = ""
    @State private var alarmKinds: Set<Int> = []
    @State private var visitorOnly = false
    @State private var showAlarmKinds = false
    @State private var hydrated = false
    @State private var entries: [LedgerEntry] = []
    @State private var untimed = 0
    @State private var readAt: Int64?
    @State private var reading = false
    @State private var readNote: String?
    /// 「全部锁」模式下读取会被早退 —— 给一个直接切到当前锁并读取的出口，而不是只留一句话。
    @State private var offerCurrentLockRead = false
    @State private var flash: String?

    // MARK: - 派生（全部是 RecordsModels 的纯函数）

    private var filtered: [LedgerEntry] {
        LedgerFilter.apply(entries,
                           scope: scope,
                           member: member,
                           query: LedgerQuery(query),
                           dayFocus: route.dayFocus,
                           alarmKinds: alarmKinds,
                           visitorOnly: visitorOnly)
    }

    private var mac: String {
        if lockScope == .all { return "" }
        return selectedMac.isEmpty ? (app.lock?.id ?? "") : selectedMac
    }
    private var groups: [LedgerDayGroup] { LedgerDayGroup.make(LedgerGrouping.group(filtered)) }
    private var lockName: String { app.lock?.name ?? "门锁" }

    private var conditions: Int {
        var count = 0
        if scope != .all { count += 1 }
        if !member.isEmpty { count += 1 }
        if !LedgerQuery(query).isEmpty { count += 1 }
        if !alarmKinds.isEmpty { count += 1 }
        if visitorOnly { count += 1 }
        return count
    }

    private var memberOptions: [String] {
        [""] + LedgerFilter.members(in: entries)
    }

    private var todayEntries: [LedgerEntry] {
        let start = TimeFormat.calendar.startOfDay(for: Date())
        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        return entries.filter { $0.at >= startMillis }
    }

    private var todayOpenCount: Int {
        todayEntries.filter { $0.tone == .ok || $0.tone == .live }.count
    }

    private var todayAlarmCount: Int {
        todayEntries.filter { $0.tone == .attention || $0.tone == .critical }.count
    }

    private var todayFamilyCount: Int {
        todayEntries.filter { ($0.owner ?? "").isEmpty == false }.count
    }

    private var todayTempCount: Int {
        todayEntries.filter { $0.event.contains("临时") || $0.event.contains("一次性") }.count
    }

    // MARK: - 页

    var body: some View {
        ScrollViewReader { proxy in
            // 2026-11-02（R2 全换系统）：页面容器从 ScrollView + VStack 换成系统 List。
            // 台账时间线必须是 `Section(header:)` 的一天一段，而 List 不能嵌在 ScrollView 里
            // （内层会自成滚动区）—— 所以整页统一进 List，其余卡片作为"整块行"放进来，
            // 行内边距/底色/分隔线由 ledgerCardRow() 清掉，卡片外观保持不变。
            List {
                Section {
                    header.ledgerCardRow()
                    if app.lock == nil {
                        noLockCard.ledgerCardRow()
                    } else {
                        activityCard.ledgerCardRow()
                        miniGrid.ledgerCardRow()
                        secondGrid.ledgerCardRow()
                        searchCard.ledgerCardRow()
                        if visitorOnly { visitorCard.ledgerCardRow() }
                        if let day = route.dayFocus { dayFocusCard(day).ledgerCardRow() }
                        if reading {
                            busyCard.ledgerCardRow()
                        } else if entries.isEmpty {
                            emptyLedgerCard.ledgerCardRow()
                        } else if filtered.isEmpty {
                            emptyFilteredCard.ledgerCardRow()
                        }
                    }
                }
                if app.lock != nil, !reading, !entries.isEmpty, !filtered.isEmpty {
                    timelineSections
                }
                if app.lock != nil {
                    Section {
                        if let note = readNote { noteCard(note).ledgerCardRow() }
                        overlayCard.ledgerCardRow()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, V.S.gapM, for: .scrollContent)
            .background(V.C.bg.ignoresSafeArea())
            .onAppear {
                reload()
                consume()
            }
            .onChange(of: router.pending) { _, _ in consume() }
            // 2026-11-01（Round 273）：**切锁后必须重新水合筛选。**
            // `hydrateFilters()` 用 `guard !hydrated` 只跑一次，而 TabView 会保活这个视图 ——
            // 于是 A 锁的筛选（分段/成员/告警类型/只看失败）会原样套到 B 锁上；
            // 更糟的是随后任何一次改筛选都会把这份「继承来的状态」写进 **B 锁**的存储（`kf_rflt_<B>`），
            // 污染 B 锁自己记住的那份。切锁即重置并重新水合。
            .onChange(of: app.currentMac) { _, _ in
                hydrated = false
                consume()
            }
            .onChange(of: route.flashID) { _, new in
                guard let new else { return }
                flash = new
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .task(id: flash) {
                guard flash != nil else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { flash = nil }
                route.flashID = nil
            }
        }
        .navigationTitle("台账")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: Text("成员 / 凭证 / +指纹 -临时码"))
        .task { await app.reload(refreshStatus: false) }
        .sheet(isPresented: $showAlarmKinds) {
            AlarmKindsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // 换锁范围后，"切到当前锁并读取"这条出口就过期了 —— 先收起，避免留一个点不动的按钮。
        .onChange(of: lockScope) { _, _ in
            offerCurrentLockRead = false
            reload()          // 换范围要重新装配 entries（原来是 chip 的点击闭包里调的）
        }
        .onChange(of: scope) { _, _ in saveFilters() }
        .onChange(of: member) { _, _ in saveFilters() }
        .onChange(of: alarmKinds) { _, _ in
            RecordsRoute.shared.alarmKinds = alarmKinds
            saveFilters()
        }
        .onChange(of: route.alarmKinds) { _, new in
            if new != alarmKinds { alarmKinds = new }
        }
    }

    // MARK: - 头部（R3：标题 22/600 + 日期 11.5 + 头像 Ø34）

    private var header: some View {
        HStack(alignment: .top, spacing: V.S.gapM) {
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                // 页面标题由系统大标题（.navigationTitle("台账")）承担；页内只留日期与本人头像。
                Text(dateLine)
                    .font(V.F.bedLabel)
                    .foregroundStyle(V.C.text3)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(V.C.rewardGreen.opacity(0.22))
                Text("我")
                    .font(V.F.rowDetailStrong)
                    .foregroundStyle(V.C.text1)
            }
            .frame(width: V.Metric.avatar, height: V.Metric.avatar)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var dateLine: String {
        let parts = TimeFormat.calendar.dateComponents([.month, .day, .weekday], from: Date())
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let index = max(0, min(6, (parts.weekday ?? 1) - 1))
        return "\(parts.month ?? 1) 月 \(parts.day ?? 1) 日 星期\(names[index])"
    }

    // MARK: - 今日活动（R3 三环卡）

    private var activityCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                Text("今日活动")
                    .font(V.F.miniTitle)
                    .foregroundStyle(V.C.text1)
                HStack(alignment: .center, spacing: V.S.gapL) {
                    VRingStack(rings: activityRings, size: V.Ring.referenceOuter)
                    VStack(alignment: .leading, spacing: V.S.gapM) {
                        // 分母不再是编造的 24/12/4：三环都是「该类占今日总记录的比例」，
                        // 图例只报真实条数（旧实现把常数当上限，等于每天固定显示 24 次开锁额度）。
                        legendRow(title: "开锁", value: "\(todayOpenCount)", share: activityShare(todayOpenCount), unit: "次", color: V.C.red)
                        legendRow(title: "家庭", value: "\(todayFamilyCount)", share: activityShare(todayFamilyCount), unit: "次", color: V.C.green)
                        legendRow(title: "临时", value: "\(todayTempCount)", share: activityShare(todayTempCount), unit: "次", color: V.C.cyan)
                    }
                }
                .padding(.top, V.S.gapS)
            }
        }
    }

    /// 今日记录总条数：三环与图例共用的唯一分母。
    private var todayTotal: Int { max(todayEntries.count, 0) }

    private func activityShare(_ count: Int) -> Double {
        guard todayTotal > 0 else { return 0 }
        return min(1, Double(count) / Double(todayTotal))
    }

    private var activityRings: [(Double, Color)] {
        [
            (activityShare(todayOpenCount), V.C.red),
            (activityShare(todayFamilyCount), V.C.green),
            (activityShare(todayTempCount), V.C.cyan)
        ]
    }

    private func legendRow(title: String, value: String, share: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text(title)
                .font(V.F.legendLabel)
                .foregroundStyle(V.C.text1)
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapXS) {
                Text(value)
                    .font(V.F.legendValue)
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(unit)
                    .font(V.F.legendLabel)
                    .foregroundStyle(V.C.text7)
                Text("\(Int((share * 100).rounded()))%")
                    .font(V.F.legendLabel)
                    .foregroundStyle(V.C.text3)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) \(unit)，占今日 \(Int((share * 100).rounded()))%")
    }

    // MARK: - 2×2 微卡（R3）

    /// R7（ui-ia §4.1）：原来这里还有一张「开锁次数」微卡，与上面三环卡的「开锁」图例（`:232`）
    /// 是同一份数据、同一页出现两次 —— 已删微卡那处，只留三环图例（它带占比，信息量更大）。
    private var miniGrid: some View {
        HStack(alignment: .top, spacing: V.S.gapM) {
            miniCard(title: "异常尝试", value: "\(todayAlarmCount)", tint: V.C.miniBlue, bars: alarmBins)
        }
    }

    private func miniCard(title: String, value: String, tint: Color, bars: [Double]) -> some View {
        VCard(style: .mini) {
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                HStack {
                    Text(title)
                        .font(V.F.miniTitle)
                        .foregroundStyle(V.C.text1)
                    Spacer(minLength: 0)
                }
                Text("今天")
                    .font(V.F.legendLabel)
                    .foregroundStyle(V.C.text3)
                    .padding(.top, V.S.gapS)
                Text(value)
                    .font(V.F.miniBig)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                VMiniBars(values: bars, tint: tint)
                    .padding(.top, V.S.gapS)
            }
            .frame(minHeight: V.Metric.miniCardH - 2 * V.S.miniPad, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    // R7：`todayBins` 随「开锁次数」微卡一起删（那张卡是它唯一的消费者，留着就是死代码）。
    private var alarmBins: [Double] {
        bins(for: todayEntries.filter { $0.tone == .attention || $0.tone == .critical })
    }

    private func bins(for list: [LedgerEntry]) -> [Double] {
        var out = Array(repeating: 0.0, count: V.Mini.gridCount)
        let calendar = TimeFormat.calendar
        for entry in list {
            let hour = calendar.component(.hour, from: TimeFormat.date(entry.at))
            let index = min(V.Mini.gridCount - 1, max(0, hour))
            out[index] += 1
        }
        return out
    }

    private var secondGrid: some View {
        HStack(alignment: .top, spacing: V.S.gapM) {
            recentEventCard
            streakCard
        }
    }

    private var recentEventCard: some View {
        VCard(style: .mini) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack {
                    Text("最近事件")
                        .font(V.F.miniTitle)
                        .foregroundStyle(V.C.text1)
                    Spacer(minLength: 0)
                }
                if let latest = entries.first {
                    ZStack {
                        Circle()
                            .fill(V.C.rewardGreen.opacity(0.16))
                        Image(systemName: "figure.walk")
                            .font(V.F.bodyMedium)
                            .foregroundStyle(V.C.rewardGreen)
                            .accessibilityHidden(true)
                    }
                    .frame(width: V.Metric.eventIcon, height: V.Metric.eventIcon)
                    .padding(.top, V.S.gapS)
                    Text(latest.event)
                        .font(V.F.bodySmall)
                        .foregroundStyle(V.C.text7)
                        .lineLimit(1)
                    Text(TimeDisplay.clock(latest.at))
                        .font(V.F.displayESemibold)
                        .foregroundStyle(V.C.lime)
                        .monospacedDigit()
                    Text(TimeFormat.dayTitle(TimeFormat.dayKey(latest.at)))
                        .font(V.F.legendLabel)
                        .foregroundStyle(V.C.text3)
                } else {
                    Text("还没有记录")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: V.Metric.miniCardH - 2 * V.S.miniPad, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    private var streakCard: some View {
        VCard(style: .mini) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack {
                    Text("连续记录")
                        .font(V.F.miniTitle)
                        .foregroundStyle(V.C.text1)
                    Spacer(minLength: 0)
                }
                // Z2（ui-ia §4.4）：原三层同心圆奖牌是纯装饰 —— 没有数据源，只是「看起来像成绩」。
                // 已删圆环，把「连续 N 天」升为这张微卡的主读数：真数、可读，占位不再靠圆。
                Text("\(streakDays)")
                    .font(V.F.miniBig)
                    .foregroundStyle(V.C.text1)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, V.S.gapXS)
                Text("连续天数")
                    .font(V.F.microMedium)
                    .foregroundStyle(V.C.text4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(todayAlarmCount == 0 ? "今日无异常" : "今日异常 \(todayAlarmCount) 次")
                    .font(V.F.microSmall)
                    .foregroundStyle(todayAlarmCount == 0 ? V.C.text3 : V.C.warning)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .frame(minHeight: V.Metric.miniCardH - 2 * V.S.miniPad, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    private var streakDays: Int {
        guard !entries.isEmpty else { return 0 }
        let keys = Set(entries.map { TimeFormat.dayKey($0.at) })
        let calendar = TimeFormat.calendar
        var day = calendar.startOfDay(for: Date())
        var count = 0
        while count < 3650 {
            let key = TimeFormat.dayKey(Int64(day.timeIntervalSince1970 * 1000))
            guard keys.contains(key) else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: - 检索（保留全部原筛选能力）

    private var searchCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                    Text("检索")
                        .font(V.F.cardTitle)
                        .foregroundStyle(V.C.text6)
                    Spacer(minLength: 0)
                    Button("告警类型") {
                        RecordsRoute.shared.alarmKinds = alarmKinds
                        showAlarmKinds = true
                    }
                        .font(V.F.footnote)
                        .foregroundStyle(alarmKinds.isEmpty ? V.C.blue : V.C.warning)
                        .accessibilityLabel(alarmKinds.isEmpty ? "告警类型筛选" : "告警类型已选 \(alarmKinds.count) 项")
                    Button("工作室") { router.request(.dest(.recordsStudio)) }
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.blue)
                        .accessibilityLabel("记录工作室")
                    Button("导出") { router.request(.dest(.recordExport)) }
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.blue)
                    Button("读取") { Task { await read() } }
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.blue)
                        .disabled(reading)
                }
                // 2026-11-01：**把"台账是手动拉的"这件事写出来。**
                // `readAt` 一直有值（`reload()` 从 `RecordsSource.lastSync` 取），但**从未显示过** ——
                // 于是用户既不知道记录需要手动读，也不知道上一次读到什么时候，
                // 只会觉得"记录怎么一直是旧的/怎么没有刷新按钮"。
                HStack(spacing: V.S.gapXS) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .accessibilityHidden(true)
                    Text(readAt.map { "上次读取 · " + TimeFormat.ago($0) } ?? "还没读取过锁内日志")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                // 输入框已交给系统搜索栏（.searchable）——这里只留筛选与读数。
                Divider()
                // 范围档（4 档固定）→ 系统分段控件（原来是自绘 chip 行）。
                Picker("范围", selection: $scope) {
                    ForEach(LedgerScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack(spacing: V.S.gapS) {
                    // 锁范围（2 档固定）→ 系统分段控件；换锁仍走右侧 Menu。
                    Picker("锁范围", selection: $lockScope) {
                        ForEach(RecordLockScope.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Menu {
                        ForEach(DB.keychains()) { kc in
                            Button(LockArchive.displayName(kc) + (DB.normalizeMac(kc.mac) == DB.normalizeMac(mac) ? " ✓" : "")) {
                                switchLock(kc)
                            }
                        }
                    } label: {
                        HStack(spacing: V.S.gapXS) {
                            Text("换锁")
                                .font(V.F.footnote)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(V.F.chevron)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(V.C.blue)
                        .frame(minHeight: V.Hit.min)
                        .contentShape(.rect)
                    }
                    .accessibilityLabel("切换当前锁")
                }
                if memberOptions.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: V.S.gapS) {
                            ForEach(memberOptions, id: \.self) { name in
                                chip(title: name.isEmpty ? "全部成员" : name, selected: member == name) { member = name }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                if !alarmKinds.isEmpty {
                    Text("告警类型 " + alarmKinds.sorted().map { RecordVerbs.alarmVerb[$0] ?? "#\($0)" }.joined(separator: " / "))
                        .font(V.F.unit)
                        .foregroundStyle(V.C.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                    Text("\(filtered.count)")
                        .font(V.F.number22)
                        .foregroundStyle(V.C.text1)
                        .monospacedDigit()
                    Text("条")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                    Spacer(minLength: 0)
                    if conditions > 0 {
                        Text("\(conditions) 项条件")
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text3)
                        Button("重置") { reset() }
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.blue)
                    }
                }
            }
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V.F.footnote)
                .foregroundStyle(selected ? V.C.text1 : V.C.text3)
                .padding(.horizontal, V.S.gapM)
                .padding(.vertical, V.S.gapS)
                .background(selected ? V.C.card : Color.clear, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(selected ? V.C.tabEdge : V.C.hairline, lineWidth: V.S.hair)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 时间线（按自然日分组 → List 的一天一段）

    /// 一天一段 `Section`，段头是日期 + 条数；行保留原点击行为与 flash 高亮。
    @ViewBuilder
    private var timelineSections: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.items) { entry in
                    entryRow(entry)
                }
            } header: {
                dayHeader(group)
            }
        }
    }

    private func dayHeader(_ group: LedgerDayGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
            Text(TimeFormat.dayTitle(group.dayKey))
                .font(V.F.cardTitle)
                .foregroundStyle(V.C.text1)
            Spacer(minLength: 0)
            Text("\(group.items.count) 条")
                .font(V.F.footnote)
                .foregroundStyle(V.C.text3)
                .monospacedDigit()
        }
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }

    /// 一行台账。滑动动作（本机标注，全部只改本机、不写门锁）：
    /// 左滑出「标旗」；右滑出「处置 / 删除本机标注」。
    /// 之前 `.swipeActions` 全仓 0 处 —— 本机标注只能在详情页逐条改，时间线上没有入口。
    private func entryRow(_ entry: LedgerEntry) -> some View {
        Button {
            open(entry)
        } label: {
            V7RecordRow(entry: entry)
                .background(flash == entry.id ? V.C.blue.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardGutter, bottom: 0, trailing: V.S.cardGutter))
        .listRowBackground(V.C.card)
        .id(entry.id)
        .accessibilityHint("打开这条记录的详情")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                overlay.toggleFlag(entry.id)
                AppToast.shared.show(overlay.isFlagged(entry.id) ? "已标旗" : "已取消标旗", tone: .ok)
            } label: {
                Label(overlay.isFlagged(entry.id) ? "取消标旗" : "标旗", systemImage: "flag.fill")
            }
            .tint(V.C.coral)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleDispose(entry)
            } label: {
                Label(overlay.isDisposed(entry.id) ? "撤销处置" : "已处置", systemImage: "checkmark.circle.fill")
            }
            .tint(V.C.rewardGreen)
            Button(role: .destructive) {
                clearAnnotations(entry)
            } label: {
                Label("删除本机标注", systemImage: "trash")
            }
        }
    }

    /// 处置来回切（与详情页同一份 overlay，口径一致）。
    private func toggleDispose(_ entry: LedgerEntry) {
        if overlay.isDisposed(entry.id) {
            overlay.undoDispose(entry.id)
            AppToast.shared.show("已撤销处置", tone: .ok)
        } else {
            overlay.dispose(entry.id, at: Int64(Date().timeIntervalSince1970 * 1000))
            AppToast.shared.show("已标记为已处置", tone: .ok)
        }
    }

    /// 删除这条记录的**全部本机标注**（备注 / 标旗 / 处置）；锁内日志一条都不动。
    private func clearAnnotations(_ entry: LedgerEntry) {
        let hasNote = !overlay.note(for: entry.id).isEmpty
        let hasFlag = overlay.isFlagged(entry.id)
        let hasDisp = overlay.isDisposed(entry.id)
        if hasNote { overlay.setNote("", for: entry.id) }
        if hasFlag { overlay.toggleFlag(entry.id) }
        if hasDisp { overlay.undoDispose(entry.id) }
        AppToast.shared.show(hasNote || hasFlag || hasDisp ? "已删除这条记录的本机标注" : "这条记录没有本机标注",
                             tone: hasNote || hasFlag || hasDisp ? .ok : .info)
    }

    private func dayFocusCard(_ day: String) -> some View {
        VCard {
            HStack(spacing: V.S.gapS) {
                Image(systemName: "calendar")
                    .font(V.F.cardBody)
                    .foregroundStyle(V.C.text3)
                    .accessibilityHidden(true)
                Text("只看 " + TimeFormat.dayTitle(day))
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: 0)
                Button("看全部日子") { route.dayFocus = nil }
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.blue)
            }
        }
    }

    // MARK: - 空态 / 加载 / 提示

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有添加门锁")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("开门与操作记录存在门锁内。先添加并配对门锁，再回到这里读取。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
            }
        }
    }

    private var emptyLedgerCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有台账记录")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("台账是锁内日志读出来的。先把门锁连上，再到「门」页开一次门，记录就会落在这里。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "读取锁内日志", systemImage: "arrow.clockwise") {
                    Task { await read() }
                }
            }
        }
    }

    private var emptyFilteredCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("这些条件下没有记录")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("检索词或筛选把这一段时间的记录都筛掉了。放宽条件就能回到台账。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "清除条件", systemImage: "line.3.horizontal.decrease.circle") {
                    reset()
                }
            }
        }
    }

    private var busyCard: some View {
        VCard {
            HStack(spacing: V.S.gapS) {
                ProgressView().controlSize(.small).tint(V.C.blue)
                Text("正在从锁内翻页读取日志…")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                Spacer(minLength: 0)
            }
        }
    }

    private func noteCard(_ note: String) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                Text(note)
                    .font(V.F.footnote)
                    .foregroundStyle(note.hasPrefix("已") ? V.C.rewardGreen : V.C.coral)
                    .fixedSize(horizontal: false, vertical: true)
                if offerCurrentLockRead {
                    VOutlineButton(title: "切到当前锁并读取", systemImage: "arrow.clockwise") {
                        offerCurrentLockRead = false
                        lockScope = .current
                        selectedMac = ""
                        Task { @MainActor in
                            await Task.yield()
                            await read()
                        }
                    }
                }
            }
        }
    }

    private var overlayCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                Text("本机标注")
                    .font(V.F.cardTitle)
                    .foregroundStyle(V.C.text6)
                VStatPair(items: [
                    ("备注", "\(overlay.notes.count) 条"),
                    ("标旗", "\(overlay.flagged.count) 条"),
                    ("已处置", "\(overlay.disposed.count) 条")
                ])
                Text("备注、标旗与处置只落在本机，不写入门锁。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
            }
        }
    }

    // MARK: - 动作（全部真改状态或真跳转）

    private func open(_ entry: LedgerEntry) {
        route.focusID = entry.id
        router.request(.dest(.recordDetail))
    }

    private func reset() {
        query = ""
        scope = .all
        member = ""
        alarmKinds = []
        RecordsRoute.shared.alarmKinds = []
        visitorOnly = false
        route.dayFocus = nil
    }

    private func reload() {
        // 2026-11-01（Round 281）：**选中的锁可能已经被删掉**（在设置页删锁后回到记录页）。
        // 此时 `selectedMac` 仍指向那个 mac ⇒ 记录页会一直筛一个不存在的锁（恒空），
        // 而 `readLogs()` 每次都会把 `DB.currentMac` 指回那把已删的锁（再靠 preferredMac 兜回来）。
        // 这里回落到「跟随当前锁」：删锁后记录页应当自动跟到剩下的那把。
        if !selectedMac.isEmpty, DB.keychain(selectedMac) == nil {
            selectedMac = ""
        }
        guard lockScope == .all || !mac.isEmpty else {
            entries = []
            untimed = 0
            readAt = nil
            return
        }
        let targets: [Keychain] = lockScope == .all
            ? DB.keychains()
            : DB.keychains().filter { DB.normalizeMac($0.mac) == DB.normalizeMac(mac) }
        // 2026-11-01（Round 285）：水合**全部目标锁**并整份重建内存镜像 ——
        // 「全部锁」模式下别的锁的备注/标旗此前根本不显示，切锁后计数还会把两把锁加在一起。
        overlay.hydrate(macs: targets.map(\.mac))
        var merged: [LedgerEntry] = []
        var untimedTotal = 0
        var synced: Int64?
        for kc in targets {
            let load = RecordsSource.load(mac: kc.mac,
                                          lockName: LockArchive.displayName(kc),
                                          members: app.members)
            merged.append(contentsOf: load.entries)
            untimedTotal += load.untimed
            if lockScope == .current { synced = RecordsSource.lastSync(mac: kc.mac) }
        }
        entries = merged.sorted { $0.at > $1.at }
        untimed = untimedTotal
        readAt = synced
    }

    /// 开场策略：QueryFilters.load 已按 kf_filter_default 裁决「记住上次 / 每次空白 / 每次只看告警」。
    private func hydrateFilters() {
        guard !hydrated else { return }
        hydrated = true
        let m = mac.isEmpty ? app.currentMac : mac
        guard !m.isEmpty else { return }
        let saved = QueryFilters.load(mac: m)
        if saved.failedOnly { scope = .failed }
        else if saved.alarmOnly { scope = .alarm }
        else { scope = .all }
        member = saved.member
        alarmKinds = saved.alarmKinds
        RecordsRoute.shared.alarmKinds = saved.alarmKinds
    }

    /// 过滤组合按锁记住（kf_rflt_<mac>），切回「记住上次」时用户设过的那份还在。
    private func saveFilters() {
        let m = mac.isEmpty ? app.currentMac : mac
        guard !m.isEmpty, hydrated else { return }
        var f = QueryFilters()
        f.alarmOnly = scope == .alarm
        f.failedOnly = scope == .failed
        f.member = member
        f.alarmKinds = alarmKinds
        f.save(mac: m)
    }

    private func switchLock(_ kc: Keychain) {
        selectedMac = kc.mac
        DB.currentMac = kc.mac
        app.overrideMac = kc.mac
        lockScope = .current
        // AppModel.currentMac 先读 app.lock，再回落默认锁/偏好锁；换锁要先把旧投影清掉，
        // 否则 reload 仍会按旧锁重建（DB.currentMac 只在 app.lock == nil 时参与解析）。
        app.lock = nil
        Task { @MainActor in
            await app.reload(refreshStatus: false)
            reload()
        }
    }

    private var visitorCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack(spacing: V.S.gapS) {
                    VStateDot(tone: .attention, word: "访客过滤")
                    Text("只看访客 · 临时码未归属")
                        .font(V.F.bodyStrong)
                        .foregroundStyle(V.C.text1)
                    Spacer(minLength: 0)
                    Button("清除") { visitorOnly = false }
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.blue)
                        .frame(minHeight: V.Hit.min)
                        .accessibilityLabel("清除访客过滤")
                }
                Text("这里只显示临时码 / 一次性密码且没有归属人的开门记录 —— 与「家」页访客卡的口径一致。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 外观页「时间线行距」（kf_tl_gap）的真实消费点：
    /// 原来是 LazyVStack 的 spacing；换 List 后落到 `.listSectionSpacing`（一天一段之间的节奏）。
    private var sectionSpacing: CGFloat {
        switch DB.store.getString("kf_tl_gap") {
        case "tight": return V.S.gapS
        case "loose": return V.S.gapL
        default: return V.S.gapM
        }
    }

    @MainActor
    private func read() async {
        guard !reading else { return }
        // 进入函数时把锁 MAC 固定下来：读日志是 await 长任务，期间用户可能切锁，
        // 后面的 markSynced 必须记在这次真正读取的那把锁上（旧实现用计算属性 mac，会记到新锁）。
        let readMac = mac
        guard !readMac.isEmpty else {
            readNote = "还没有门锁，没有可读的台账"
            return
        }
        if lockScope == .all {
            readNote = "全部锁模式只展示已缓存记录；要读锁内日志，先切到具体一把锁。"
            offerCurrentLockRead = true
            return
        }
        offerCurrentLockRead = false
        if !selectedMac.isEmpty, selectedMac != app.lock?.id {
            DB.currentMac = selectedMac
            app.overrideMac = selectedMac
            app.lock = nil
            await app.reload(refreshStatus: false)
        }
        reading = true
        readNote = nil
        // 2026-11-01：拿下"锁端还剩多少条更早的记录"（协议 KLV#04 的 surplus）。
        // 此前这个字段解析出来却没人用，20 页封顶后静默停止 —— 用户看到"已读取 100 条"
        // 会以为读全了，而锁里可能还有几百条。现在如实说明还剩多少。
        let fetched = await app.readLogs()
        // 本次**实际**读到的条数（不是合并后的缓存总数 —— 后者在「全部锁」范围下还是多把锁之和）。
        let readCount = fetched?.read ?? 0
        let remaining = fetched?.remaining
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let err = app.lastError {
            reload()
            readNote = "读取失败 · " + err + "（下面是上次读到的那一份）"
            app.lastError = nil
        } else if app.lock?.isConnected == true {
            RecordsSource.markSynced(mac: readMac, at: now)
            reload()
            let more = (remaining ?? 0) > 0 ? "；锁端还有 \(remaining ?? 0) 条更早的记录未读（点「读取」可继续）" : ""
            // 「本次读取」与「记录页共多少条」分开说：两者常常不等（缓存是合并的、还可能跨多把锁）。
            let cacheNote = entries.count == readCount ? "" : "（记录页共 \(entries.count) 条）"
            readNote = untimed > 0
                ? "本次读取 \(readCount) 条" + cacheNote + "（另 \(untimed) 条锁端未回时刻，无法定位到某一天）" + more
                : "本次读取 \(readCount) 条" + cacheNote + " · \(TimeDisplay.clock(now))" + more
        } else {
            reload()
            readNote = "门锁未连接 · 下面是上次读到的那一份"
        }
        reading = false
    }

    private func consume() {
        hydrateFilters()
        if route.alarmKinds != alarmKinds { alarmKinds = route.alarmKinds }
        if route.visitorOnly {
            visitorOnly = true
            route.visitorOnly = false
        }
        reload()
        // 只取 `.record` / `.day` —— 别的一律留给对的人（`consume` 不再无条件清空）。
        // **不能 early-return**：下面 `searchSeed` 的处理与路由无关，每次 consume 都要跑。
        if let context = router.consume(if: { if case .record = $0 { return true }; if case .day = $0 { return true }; return false }) {
            switch context {
            case .record(let id):
                route.focusID = id
                route.flashID = id
                route.dayFocus = nil
            case .day(let key):
                route.dayFocus = key
                route.focusID = nil
            default:
                break
            }
        }
        if let seed = route.searchSeed {
            query = seed
            route.searchSeed = nil
        }
    }
}

// MARK: - List 行辅助

private extension View {
    /// List 里的「整块卡片」行。修饰符组合只写在 `V7Extras.plainRow()` 一处，
    /// 这里只补「占满宽度、左对齐」—— 三份同样的 listRowInsets/背景/分隔线不再各写一遍。
    func ledgerCardRow() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).plainRow()
    }
}

// MARK: - v7 台账行（保留 LedgerEntry 的语义色）

private struct V7RecordRow: View {
    let entry: LedgerEntry

    private var tint: Color {
        switch entry.tone {
        case .ok, .live: return V.C.rewardGreen
        case .attention: return V.C.coral
        case .critical: return V.C.red
        case .neutral: return V.C.text3
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapM) {
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeDisplay.clock(entry.at))
                    .font(V.F.rowDetailStrong)
                    .foregroundStyle(V.C.text1)
                    .monospacedDigit()
                // 「记录行加第二行完整日期」开关（kf_two_line_date）的真实消费点：
                // 旧实现只有外观页自己的样例在调 TimeDisplay.dayLine，全仓没有第二个消费点。
                if let dayLine = TimeDisplay.dayLine(entry.at) {
                    Text(dayLine)
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .monospacedDigit()
                }
            }
                // 2026-11-01：`width: 48` → `minWidth: 48`。时间串用 `V.F.rowDetailStrong`
                // （13pt，随 `.footnote` 缩放）—— 大字号下「23:59」会超过 48pt 被裁。
                // `minWidth` 保住了默认档的对齐列宽，字号大时列随之变宽。
                .frame(minWidth: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(entry.event)
                    .font(V.F.rowTitle)
                    .foregroundStyle(V.C.text1)
                    .lineLimit(1)
                // 通勤时段标签（`CommuteLabel.tag`，674 一直零调用）：
                // 工作日 7-9 / 17-19 的开门是"规律性行为"，与随机开门在排查上意义不同，
                // 标出来能让用户一眼分辨"这是我上班那次"还是"别的什么"。
                if let commute = CommuteLabel.tag(date: TimeFormat.date(entry.at),
                                                  hour: TimeFormat.calendar.component(.hour, from: TimeFormat.date(entry.at))) {
                    Text(commute)
                        .font(V.F.chipLabel)
                        .foregroundStyle(V.C.blue)
                }
                if let owner = entry.owner, !owner.isEmpty {
                    Text(owner)
                        .font(V.F.rowDetail)
                        .foregroundStyle(V.C.text3)
                }
            }
            Spacer(minLength: V.S.gapS)
            Circle()
                .fill(tint)
                .frame(width: V.List.dotSize, height: V.List.dotSize)
        }
        .frame(minHeight: V.List.rowMinHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(TimeDisplay.clock(entry.at)) \(entry.event)")
    }
}

#Preview("RecordsScreen") {
    NavigationStack {
        RecordsScreen()
    }
    .environment(AppModel())
    .environment(Router())
}
