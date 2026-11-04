// RecordsScreen.swift —— 记录（Tab 3）。v7 结构重写，参考 R3-records.html / TOKENS.md 参考 C。
//
// 实测来源：头部标题 22pt/600 left 21、日期 11.5pt #8E8E93、头像 Ø34；
// 今日活动卡 352×196.7 r16；三环外径 133.7、环宽 14、间隙 1.2、12 点起圆头；
// 微卡 170.7×178 r16 #1C1C1E；24 格柱图网格高 57、柱宽 1.8 r0.9；微卡大数字 30pt/600。
// 数据绑定保持原口径：RecordsSource / LedgerFilter / RecordsRoute / RecordsOverlay / Router 不变。
import SwiftUI

struct RecordsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 头像圆的 Dynamic Type 缩放因子（见 body 里头像那段注释）。
    @ScaledMetric(relativeTo: .body) private var avatarScale: CGFloat = 1
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
                        // 2026-11-03（整页截图实测）：一条记录都没有时，这张卡里仍然摊着
                        // 搜索框 + 4 枚类型芯片 + 2 枚范围芯片 + 换锁 + 「0 条」——
                        // 7 个控件全都没有可作用的对象，下面紧接着又是「还没有台账记录」大空态。
                        // 没数据就只给空态和那一个 CTA。
                        if !entries.isEmpty { searchCard }
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
                // 2026-11-03（真机截图）：同门页 —— 系统大标题自带视觉头部。
                .padding(.bottom, V.S.gapL)
            }
            .background(V.C.bg.ignoresSafeArea())
            .modifier(UITestScrollBottom())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("记录")
        .toolbar {
            profileToolbarItem
            // 2026-11-03：页面动作收进 ⋯ 菜单（系统给工具项原生玻璃）。
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        RecordsRoute.shared.alarmKinds = alarmKinds
                        showAlarmKinds = true
                    } label: {
                        Label("告警类型筛选", systemImage: "exclamationmark.triangle")
                    }
                    Button { router.request(.dest(.recordsStudio)) } label: {
                        Label("记录工作室", systemImage: "magnifyingglass")
                    }
                    Button { router.request(.dest(.recordExport)) } label: {
                        Label("导出记录", systemImage: "square.and.arrow.up")
                    }
                    Button { Task { await read() } } label: {
                        Label("读取锁内日志", systemImage: "arrow.clockwise")
                    }
                    .disabled(reading)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(V.F.icon18Medium)
                }
                .accessibilityLabel("记录页操作")
            }
        }
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                reload()
                consume()
            }
            .onChange(of: router.pending) { _, _ in consume() }
            // 2026-11-04（真缺陷 · 冷启动落在记录 Tab）：`reload()` 在 `mac` 为空时清空并早退，
            // 而冷启动时 `app.lock` 是异步加载的 —— 原来只监听 `router.pending`，
            // 于是「锁加载完了」这个事件没人接：记录页一直显示「还没有记录」，直到用户手动切页。
            // 现在锁身份一变就重载。
            .onChange(of: app.lock?.id) { _, _ in reload() }
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
        .task { await app.reload(refreshStatus: false) }
        .sheet(isPresented: $showAlarmKinds) { AlarmKindsSheet() }
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
                // 2026-11-02：标题改由系统导航栏承担（见 body 上的 .navigationTitle）。
                Text(dateLine)
                    .font(V.F.bedLabel)
                    .foregroundStyle(V.C.text3)
            }
            Spacer(minLength: 0)
        }
    }

    /// 2026-11-03（用户："原生液态玻璃质感太少"）：头像从内容头部移到**导航栏工具位** ——
    /// 系统会给工具项原生玻璃材质（功能层），且账号入口在任何滚动位置都在右上角（HIG 惯例）。
    @ToolbarContentBuilder
    private var profileToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ZStack {
                Circle().fill(V.C.rewardGreen.opacity(0.22))
                Text("我")
                    .font(V.F.rowDetailStrong)
                    .foregroundStyle(V.C.text1)
            }
            .frame(width: V.Metric.avatar * avatarScale, height: V.Metric.avatar * avatarScale)
            .accessibilityLabel("我的档案")
        }
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
                        // 2026-11-03（表现方式）：原来写「0/24」「0/12」「0/4」—— 三个分母是**编的**：
                        // 既不是锁端数据，也没有任何设置项，却长得像配额/目标。而且三类之间是**重叠**的
                        // （家人的临时码同时计入"开锁"和"临时"），分母更没有意义。
                        // 改成只报真实条数；三环改为**相对最大项**的比例 —— 用来横向比较今天三类活动的多少。
                        legendRow(title: "开锁", value: "\(todayOpenCount)", unit: "次", color: V.C.red)
                        legendRow(title: "家庭", value: "\(todayFamilyCount)", unit: "次", color: V.C.green)
                        legendRow(title: "临时", value: "\(todayTempCount)", unit: "次", color: V.C.cyan)
                    }
                }
                .padding(.top, V.S.gapS)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var activityRings: [(Double, Color)] {
        // 环长 = 今日条数 / 今日最多的那一类。全为 0 时三环皆空（不画满，也不画假比例）。
        let peak = max(1, max(todayOpenCount, max(todayFamilyCount, todayTempCount)))
        return [
            (Double(todayOpenCount) / Double(peak), V.C.red),
            (Double(todayFamilyCount) / Double(peak), V.C.green),
            (Double(todayTempCount) / Double(peak), V.C.cyan)
        ]
    }

    private func legendRow(title: String, value: String, unit: String, color: Color) -> some View {
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
                    // 2026-11-03（交互 QA）：这里原来画了 chevron.right —— 而这三张微卡
                    // **整体不可点**（无 Button / 无 onTapGesture）。箭头在 iOS 上是
                    // "点进去还有下一页"的固定语义，画在这里就是假 affordance。
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
                    // 2026-11-03（交互 QA）：同 miniCard —— 本卡整体不可点，箭头是假 affordance。
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
                // 2026-11-03：有内容时才拉齐到奖章卡高度；空态按内容收，不留空白。
                if entries.first != nil { Spacer(minLength: 0) }
            }
            .frame(minHeight: entries.first == nil ? nil : V.Metric.miniCardH - 2 * V.S.miniPad,
                   alignment: .top)
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
                    // 2026-11-03（交互 QA）：同 miniCard —— 本卡整体不可点，箭头是假 affordance。
                }
                ZStack {
                    Circle()
                        .fill(
                            // 2026-11-03（整页截图暴露）：环原来**写死红粉渐变** —— 连续 0 天、
                            // 今日无异常时也一片红，读起来像告警。改成语义色：
                            //   有异常 → 警示色；连续 ≥3 天 → 奖励绿；其余（含 0 天）→ 中性蓝。
                            AngularGradient(
                                gradient: Gradient(colors: medalColors),
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
                // 2026-11-02（原设计版的真 bug）：这行原来写死「无异常」，
                // 不管当天实际有没有告警都这么显示 —— 一个永远说"没事"的假读数。
                // 现在跟真实计数走：0 次才说无异常，否则报次数并转告警色。
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

    /// 奖章环的语义色：只有真的值得注意时才用警示色。
    private var medalColors: [Color] {
        if todayAlarmCount > 0 { return [V.C.warning, V.C.coral, V.C.warning] }
        if streakDays >= 3 { return [V.C.rewardGreen, V.C.blue, V.C.rewardGreen] }
        return [V.C.blue.opacity(0.55), V.C.blue.opacity(0.25), V.C.blue.opacity(0.55)]
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
                    // 2026-11-03（控件逻辑）：四个文字链接从卡头移到**导航栏 ⋯ 菜单** ——
                    // 它们是页面动作（HIG 归工具栏），留在卡里既挤又抢检索标题的注意力。
                    if alarmKinds.isEmpty == false {
                        Text("已筛 \(alarmKinds.count) 类告警")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.warning)
                    }
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
                                .accessibilityHidden(true)
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

    /// 2026-11-03：筛选芯片统一走 `GlassChip`（功能层控制件用 Liquid Glass）——
    /// 台账页所有筛选（全部/开锁/告警/失败、成员、当前锁/全部锁）一处改动全部生效。
    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        GlassChip(title: title, selected: selected, action: action)
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
                // 2026-11-04（对比度回访）：coral 在白卡上 2.92:1 —— readNote 是用户必读的
                // 操作反馈（未连接/切范围/失败），与工作室的警告行同一达标口径（critical 7.18）。
                .foregroundStyle(note.hasPrefix("已") ? V.C.rewardGreen : V.C.critical)
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
        // 2026-11-04（取证定位 · 真缺陷在这里）：这条 guard 在 `mac` 为空时**清空并早退** ——
        // 而冷启动直接落到记录 Tab（`-kfTab 2` 或用户上次停在台账）时，`app.lock` 可能还没
        // 加载完，`mac` 就是空的。于是记录页显示「还没有记录」，**而且不会自己恢复**：
        // 下面只监听了 `router.pending`，没监听 `app.lock?.id` 的变化。
        // 取证先落一行，保证"空"这一支也能被看见。
        if ProcessInfo.processInfo.arguments.contains("-kfSeed"),
           let dd = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let line = "records-tab mac=\(mac) scope=\(lockScope.rawValue) earlyReturn=\(lockScope != .all && mac.isEmpty)\n"
            let url = dd.appendingPathComponent("kf-records-diag.txt")
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
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
        // 进入函数时把锁 MAC 固定下来：读日志是 await 长任务，期间用户可能切锁，
        // 后面的 markSynced 必须记在这次真正读取的那把锁上（旧实现用计算属性 mac，会记到新锁）。
        let readMac = mac
        guard !readMac.isEmpty else {
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
            // 2026-11-03（信息架构 QA）：外观设置里的「记录行加第二行完整日期」此前**没有任何消费者** ——
            // `TimeDisplay.dayLine` 全仓只在「外观」页自己的样例里被调用，台账行从不读它。
            // 开关是真的、说明写着"台账行在时刻下面补一行 MM-DD"，而台账行从来不变。
            // 这里接上：开启时时刻下面补一行 MM-DD。
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeDisplay.clock(entry.at))
                    .font(V.F.rowDetailStrong)
                    .foregroundStyle(V.C.text1)
                    .monospacedDigit()
                if let dayLine = TimeDisplay.dayLine(entry.at) {
                    Text(dayLine)
                        .font(V.F.micro)
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
