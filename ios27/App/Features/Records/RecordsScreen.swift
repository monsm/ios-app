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
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gapM) {
                    header
                    if app.lock == nil {
                        noLockCard
                    } else {
                        activityCard
                        miniGrid
                        secondGrid
                        searchCard
                        if visitorOnly { visitorCard }
                        if let day = route.dayFocus { dayFocusCard(day) }
                        if reading {
                            busyCard
                        } else if entries.isEmpty {
                            emptyLedgerCard
                        } else if filtered.isEmpty {
                            emptyFilteredCard
                        } else {
                            timeline
                        }
                        if let note = readNote { noteCard(note) }
                        overlayCard
                    }
                }
                .padding(.top, V.Page.topSpace)
                .padding(.bottom, V.S.gapL)
            }
            .background(V.C.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                reload()
                consume()
            }
            .onChange(of: router.pending) { _, _ in consume() }
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
        .task { await app.reload(refreshStatus: false) }
        .sheet(isPresented: $showAlarmKinds) { AlarmKindsSheet() }
        .onChange(of: scope) { _, _ in saveFilters() }
        .onChange(of: member) { _, _ in saveFilters() }
        .onChange(of: alarmKinds) { _, _ in saveFilters() }
    }

    // MARK: - 头部（R3：标题 22/600 + 日期 11.5 + 头像 Ø34）

    private var header: some View {
        HStack(alignment: .top, spacing: V.S.gapM) {
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text("记录")
                    .font(V.F.titleC)
                    .foregroundStyle(V.C.text1)
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
        .padding(.horizontal, V.S.pageGutterC)
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
                        legendRow(title: "开锁", value: "\(todayOpenCount)", total: 24, unit: "次", color: V.C.red)
                        legendRow(title: "家庭", value: "\(todayFamilyCount)", total: 12, unit: "次", color: V.C.green)
                        legendRow(title: "临时", value: "\(todayTempCount)", total: 4, unit: "次", color: V.C.cyan)
                    }
                }
                .padding(.top, V.S.gapS)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var activityRings: [(Double, Color)] {
        [
            (min(1, Double(todayOpenCount) / 24), V.C.red),
            (min(1, Double(todayFamilyCount) / 12), V.C.green),
            (min(1, Double(todayTempCount) / 4), V.C.cyan)
        ]
    }

    private func legendRow(title: String, value: String, total: Int, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text(title)
                .font(V.F.legendLabel)
                .foregroundStyle(V.C.text1)
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapXS) {
                Text("\(value)/\(String(total))")
                    .font(V.F.legendValue)
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(unit)
                    .font(V.F.legendLabel)
                    .foregroundStyle(V.C.text7)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2×2 微卡（R3）

    private var miniGrid: some View {
        HStack(alignment: .top, spacing: V.S.gapM) {
            miniCard(title: "开锁次数", value: "\(todayOpenCount)", tint: V.C.purple, bars: todayBins)
            miniCard(title: "异常尝试", value: "\(todayAlarmCount)", tint: V.C.miniBlue, bars: alarmBins)
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func miniCard(title: String, value: String, tint: Color, bars: [Double]) -> some View {
        VCard(style: .mini) {
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                HStack {
                    Text(title)
                        .font(V.F.miniTitle)
                        .foregroundStyle(V.C.text1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(V.F.chipLabelStrong)
                        .foregroundStyle(V.C.text3)
                        .accessibilityHidden(true)
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

    private var todayBins: [Double] {
        bins(for: todayEntries)
    }

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
        .padding(.horizontal, V.S.cardGutter)
    }

    private var recentEventCard: some View {
        VCard(style: .mini) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack {
                    Text("最近事件")
                        .font(V.F.miniTitle)
                        .foregroundStyle(V.C.text1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(V.F.chipLabelStrong)
                        .foregroundStyle(V.C.text3)
                        .accessibilityHidden(true)
                }
                if let latest = entries.first {
                    ZStack {
                        Circle()
                            .fill(V.C.rewardGreen.opacity(0.16))
                        Image(systemName: "figure.walk")
                            .font(V.F.bodyMedium)
                            .foregroundStyle(V.C.rewardGreen)
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
                    Image(systemName: "chevron.right")
                        .font(V.F.chipLabelStrong)
                        .foregroundStyle(V.C.text3)
                        .accessibilityHidden(true)
                }
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [V.C.red, V.C.pink, V.C.red]),
                                center: .center
                            )
                        )
                    Circle()
                        .fill(V.C.cardAlt)
                        .padding(V.S.gapS)
                    Circle()
                        .fill(V.C.text3.opacity(0.35))
                        .padding(V.S.gapXL)
                }
                .frame(width: V.Metric.medal, height: V.Metric.medal)
                .frame(maxWidth: .infinity)
                .padding(.top, V.S.gapS)
                Text("连续 \(streakDays) 天")
                    .font(V.F.microMedium)
                    .foregroundStyle(V.C.text7)
                    .frame(maxWidth: .infinity)
                Text("无异常")
                    .font(V.F.microSmall)
                    .foregroundStyle(V.C.text3)
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
                    Button("告警类型") { showAlarmKinds = true }
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
                HStack(spacing: V.S.gapS) {
                    Image(systemName: "magnifyingglass")
                        .font(V.F.cardBody)
                        .foregroundStyle(V.C.text3)
                        .accessibilityHidden(true)
                    TextField("成员 / 凭证 / +指纹 -临时码", text: $query)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .tint(V.C.blue)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(V.F.cardBody)
                                .foregroundStyle(V.C.text3)
                        }
                        .accessibilityLabel("清空检索")
                    }
                }
                .frame(minHeight: V.Metric.searchRow)
                Rectangle()
                    .fill(V.C.hairline)
                    .frame(height: V.S.hair)
                ScrollView(.horizontal) {
                    HStack(spacing: V.S.gapS) {
                        ForEach(LedgerScope.allCases) { item in
                            chip(title: item.rawValue, selected: item == scope) { scope = item }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(spacing: V.S.gapS) {
                    ForEach(RecordLockScope.allCases) { item in
                        chip(title: item.rawValue, selected: item == lockScope) {
                            lockScope = item
                            reload()
                        }
                    }
                    Spacer(minLength: 0)
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
        .padding(.horizontal, V.S.cardGutter)
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

    // MARK: - 时间线（按自然日分组）

    private var timeline: some View {
        LazyVStack(alignment: .leading, spacing: timelineSpacing) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: V.S.gapS) {
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
                    VCard {
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.offset) { pair in
                                if pair.offset > 0 { VDivider() }
                                Button {
                                    open(pair.element)
                                } label: {
                                    V7RecordRow(entry: pair.element)
                                        .background(flash == pair.element.id ? V.C.blue.opacity(0.12) : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .id(pair.element.id)
                                .accessibilityHint("打开这条记录的详情")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
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
        .padding(.horizontal, V.S.cardGutter)
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
        .padding(.horizontal, V.S.cardGutter)
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
        .padding(.horizontal, V.S.cardGutter)
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
        .padding(.horizontal, V.S.cardGutter)
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
        .padding(.horizontal, V.S.cardGutter)
    }

    private func noteCard(_ note: String) -> some View {
        VCard {
            Text(note)
                .font(V.F.footnote)
                .foregroundStyle(note.hasPrefix("已") ? V.C.rewardGreen : V.C.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.cardGutter)
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
        .padding(.horizontal, V.S.cardGutter)
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
        visitorOnly = false
        route.dayFocus = nil
    }

    private func reload() {
        guard lockScope == .all || !mac.isEmpty else {
            entries = []
            untimed = 0
            readAt = nil
            return
        }
        overlay.hydrate(mac: mac.isEmpty ? app.currentMac : mac)
        let targets: [Keychain] = lockScope == .all
            ? DB.keychains()
            : DB.keychains().filter { DB.normalizeMac($0.mac) == DB.normalizeMac(mac) }
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
        .padding(.horizontal, V.S.cardGutter)
    }

    private var timelineSpacing: CGFloat {
        switch DB.store.getString("kf_tl_gap") {
        case "tight": return V.S.gapS
        case "loose": return V.S.gapL
        default: return V.S.gapM
        }
    }

    @MainActor
    private func read() async {
        guard !reading else { return }
        guard !mac.isEmpty else {
            readNote = "还没有门锁，没有可读的台账"
            return
        }
        if lockScope == .all {
            readNote = "全部锁模式只展示已缓存记录；要读锁内日志，先切到具体一把锁。"
            return
        }
        if !selectedMac.isEmpty, selectedMac != app.lock?.id {
            DB.currentMac = selectedMac
            app.overrideMac = selectedMac
            app.lock = nil
            await app.reload(refreshStatus: false)
        }
        reading = true
        readNote = nil
        await app.readLogs()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let err = app.lastError {
            reload()
            readNote = "读取失败 · " + err + "（下面是上次读到的那一份）"
            app.lastError = nil
        } else if app.lock?.isConnected == true {
            RecordsSource.markSynced(mac: mac, at: now)
            reload()
            readNote = untimed > 0
                ? "已读取 \(entries.count) 条（另 \(untimed) 条锁端未回时刻，无法定位到某一天）"
                : "已读取 \(entries.count) 条 · \(TimeFormat.clock(now))"
        } else {
            reload()
            readNote = "门锁未连接 · 下面是上次读到的那一份"
        }
        reading = false
    }

    private func consume() {
        hydrateFilters()
        if route.visitorOnly {
            visitorOnly = true
            route.visitorOnly = false
        }
        reload()
        let context = router.consume()
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
        if let seed = route.searchSeed {
            query = seed
            route.searchSeed = nil
        }
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
            Text(TimeDisplay.clock(entry.at))
                .font(V.F.rowDetailStrong)
                .foregroundStyle(V.C.text1)
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(entry.event)
                    .font(V.F.rowTitle)
                    .foregroundStyle(V.C.text1)
                    .lineLimit(1)
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
