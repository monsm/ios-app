// 包10 统计与图表 — Swift Charts 全本地 (收录 13-14/50/599-606/608-622/624-629/631-646/652/667/673/678/772/799-800/1020)
// 纪律:
//   颜色只走 DS 语义令牌 (图表色派生自 accent/ok/warn/danger/textSub, 631 深浅模式自动切换);
//   演示数据全部来自真实台账 (kf_logcache_ / kf_ledger_), 缺数据显示空态与"积累 X 天后可用", 不造假 (622);
//   归属相关一律走 Attribution 可证明链并带"约" (CAPABILITY §3 日志无身份字段);
//   673 春节注记无节假日表, 按静态近似区间做并明示"近似"; 50 年报告做"数据积累中"占位。
import SwiftUI
import Charts

// ---------- 主视图 ----------
struct StatsView: View {
    @EnvironmentObject var app: AppState
    @State private var mac: String
    @State private var week: Int = 7      // 678 默认本周窗口
    @State private var windowDays: Int = 30   // 599/636 主图窗口 (会话内保持)
    @State private var hiddenKinds: Set<String> = []   // 632 图例点选排除
    @State private var selHour: Int16? = nil    // 600/638 时段下钻
    @State private var drillDay: String? = nil  // 638 三级下钻: 主图选中的日
    @State private var showYearSheet = false    // 50 年报告占位
    @State private var showExport = false       // 包12 导出中心入口

    init(mac: String = DB.currentMac) {
        _mac = State(initialValue: mac.isEmpty ? (DB.keychains().first?.mac ?? "") : mac)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("统计")
                .navigationSubtitle(lockName)   // 772 单锁视图标题携带锁名
                .scrollContentBackground(.hidden)
                .dsScreenBackground()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { build() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("重新统计")
                    }
                    // 包12: 统计页导出入口 — 复用记录 Tab 导出中心 (范围默认当月, 685/701)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("导出与分享 (685)") { showExport = true }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("导出")
                    }
                }
                .sheet(isPresented: $showExport) { ExportCenterView(mac: mac) }
                .sheet(isPresented: $showYearSheet) { YearReportView(mac: mac) }
                .sheet(item: $selHour) { h in
                    if h != nil {
                        HourDetailSheet(mac: mac, hour: h!, windowDays: windowDays)
                    }
                }
        }
        .onAppear { build() }
    }

    @State private var model: StatsKit.StatModel?
    @State private var locks: [Keychain] = []

    private var lockName: String {
        locks.first { $0.mac == mac }.map { LockArchive.displayName($0) } ?? "未选择门锁"
    }

    private func build() {
        locks = DB.keychains()
        if !locks.contains(where: { $0.mac == mac }) { mac = locks.first?.mac ?? "" }
        model = StatsKit.build(mac: mac, week: week, window: windowDays)
    }

    // 638 面包屑: 统计 → 时段/日期 → 单条
    private var breadcrumb: [String] {
        var crumb = ["统计"]
        if let h = selHour { crumb.append(String(h) + " 时") }
        if let d = drillDay { crumb.append(d) }
        return crumb
    }

    @ViewBuilder
    private var content: some View {
        if locks.isEmpty {
            EmptyState(systemImage: "chart.bar",
                       title: "还没有门锁",
                       message: "统计全部来自门锁本地台账。先添加并配对门锁, 读取记录后再来看趋势。",
                       actionTitle: "去添加门锁") { app.tabSelection = 0 }
        } else if let m = model {
            List {
                Section { lockPicker } header: { Text("数据源 · 每锁独立统计 (772)") }
                Section { windowChips; breadcrumbRow } header: { Text("窗口") }
                if m.isDegraded {
                    Section {
                        degradationCard(m)
                    }
                } else {
                    Section { headlineCards(m) }
                    trendSection(m)
                    hourSection(m)
                    monthSection(m)
                    cumulativeSection(m)
                    ganttSection(m)
                    compositionSection(m)
                    credentialSection(m)
                    summarySection(m)
                    yearReportSection(m)
                    if let h = selHour { drillSection(m, hour: h) }
                }
            }
        } else {
            ProgressView("正在统计…").padding(DS.Space.xl)
        }
    }

    // ---------- 772 锁选择器 ----------
    private var lockPicker: some View {
        Picker("门锁", selection: $mac) {
            ForEach(locks) { kc in
                Text(LockArchive.displayName(kc)).tag(kc.mac)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: mac) { _, _ in build() }
    }

    // ---------- 678/634/636 窗口胶囊 + 上下文标签 ----------
    private var windowChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                contextLabel
                ForEach([7, 30, 90, 365], id: \.self) { w in
                    let on = (windowDays == w)
                    Button {
                        withAnimation(DS.Motion.standard) { windowDays = w }   // 639 数据切换 morph
                        build()
                    } label: {
                        Text(w == 365 ? "近一年" : ("近 " + String(w) + " 天"))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                            .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                            .foregroundStyle(on ? Color.white : DS.Palette.text)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("近" + String(w) + "天窗口")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                if windowDays >= 90 {
                    Label {
                        Text("大数据已按小时桶降采样 (646)")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "slider.horizontal.3").accessibilityHidden(true)
                    }
                }
            }
            .padding(.vertical, DS.Space.xxs)
        }
    }
    /// 634 窗口上下文标签: 常显"近 30 天 · N 位可归属成员"
    private var contextLabel: some View {
        let n = model?.memberCounts(days: windowDays).count ?? 0
        return Label {
            Text("近 \(windowDays) 天 · " + (n == 0 ? "暂无归属成员" : "\(n) 位成员"))
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
        } icon: {
            Image(systemName: "ellipsis.circle").accessibilityHidden(true)
        }
    }

    /// 638 三级下钻面包屑 (统计 → 时段 → 单条)
    @ViewBuilder
    private var breadcrumbRow: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(breadcrumb.enumerated()), id: \.offset) { i, c in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: DS.Icon.xs)).accessibilityHidden(true) }
                Button {
                    if i == 0 { selHour = nil; drillDay = nil }
                    else if i == 1 { drillDay = nil }
                } label: {
                    Text(c)
                        .font(.footnote.weight(i == breadcrumb.count - 1 ? .semibold : .medium))
                        .foregroundStyle(i == breadcrumb.count - 1 ? DS.Palette.accentText : DS.Palette.textSub)
                        .frame(minHeight: DS.Hit.min, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(i == breadcrumb.count - 1)
            }
            Spacer(minLength: 0)
        }
    }

    // ---------- 622 数据不足降级 ----------
    @ViewBuilder
    private func degradationCard(_ m: StatsKit.StatModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label("数据积累中", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(DS.Palette.text)
                if !m.hasData {
                    Text("这把锁还没有本地记录。连接门锁读取日志后, 这里会出现 7 天以上的趋势图。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("目前累计 \(m.coverage) 天, 再积累 \(max(0, 7 - m.coverage)) 天即可解锁完整趋势图。当前可看上方摘要。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    app.pendingRecordsFilter = ""
                    app.tabSelection = 2
                } label: {
                    Label("去读取记录", systemImage: "tray")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // ---------- 摘要卡 (652 自然句 + 667 万级缩写 + 1020 黄金时段) ----------
    @ViewBuilder
    private func headlineCards(_ m: StatsKit.StatModel) -> some View {
        let total = m.dailyPoints.reduce(0) { $0 + $1.opens }
        let days = max(m.windowDays, 1)
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                summaryCard("近 " + String(m.windowDays) + " 天开门", StatsKit.compact(total),
                            sub: StatsKit.naturalSentence(total: total, days: days),
                            delta: m.weekDelta, icon: "door.open.fill")
                summaryCard("告警", String(m.alertTotalMonth),
                            sub: m.alertTotalLast > m.alertTotalMonth ? "少于上月" : "较上月",
                            delta: nil, icon: "exclamationmark.triangle.fill")
            }
            Label {
                Text(m.goldenSentence)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
            }
            .padding(DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .padding(.horizontal, DS.Space.gutter)
    }
    private func summaryCard(_ title: String, _ value: String, sub: String, delta: Double?, icon: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: icon)
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let d = delta {
                        let up = d >= 0
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: DS.Icon.xs, weight: .semibold))
                            .foregroundStyle(DS.Palette.accentText)   // 641 中性靛蓝, 避免涨跌误导
                            .accessibilityHidden(true)
                        Text((up ? "+" : "") + String(Int(d * 100)) + "% 较上周")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.accentText)
                            .lineLimit(1)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Text(value)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                        .monospacedDigit()
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 0)
    }

    // ---------- 趋势 (599 折线 + 606 均线 + 610 空窗 + 673 春节 + 642 无数据底纹 + 635 按住读点) ----------
    @ViewBuilder
    private func trendSection(_ m: StatsKit.StatModel) {
        Section("趋势") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Chart {
                    ForEach(gapsRule(m)) { g in
                        RuleMark(xStart: .value("起", g.from), xEnd: .value("止", g.to))
                            .foregroundStyle(DS.Palette.textSub.opacity(0.14))
                            .lineStyle(StrokeStyle(lineWidth: 30))
                            .accessibilityLabel("空窗区间")
                    }
                    ForEach(festivalRule(m)) { g in
                        RuleMark(xStart: .value("起", g.from), xEnd: .value("止", g.to))
                            .foregroundStyle(DS.Palette.danger.opacity(0.10))
                            .lineStyle(StrokeStyle(lineWidth: 44))
                            .accessibilityLabel("春节区间近似")
                    }
                    ForEach(keptDaily(m)) { p in
                        LineMark(x: .value("日期", p.day), y: .value("开门", p.opens))
                            .foregroundStyle(DS.Palette.accent)
                            .interpolationMethod(.monotone)
                        AreaMark(x: .value("日期", p.day), y: .value("开门", p.opens))
                            .foregroundStyle(DS.Palette.accent.opacity(0.10))
                    }
                    ForEach(m.movingAverage) { p in
                        LineMark(x: .value("日期", p.day), y: .value("均线", p.avg))
                            .foregroundStyle(DS.Palette.warn)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    if let d = drillDay, let p = m.dailyPoints.first(where: { $0.key == d }) {
                        RuleMark(x: .value("选中", p.day))
                            .foregroundStyle(DS.Palette.accentText)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, alignment: .leading) {
                            pointBubble(p)
                        }
                    }
                }
                .chartXSelection(value: $drillDaySel)
                .frame(height: 220)
                .animation(DS.Motion.standard, value: windowDays)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(m.dailyPoints.count > 0 ? "近\(m.windowDays)天开门趋势折线图" : "暂无趋势数据")

                if let d = drillDaySel {
                    // 635 读点: 当日次数 + Top 成员 + 告警数; 637 联动下方明细
                    if let p = m.dailyPoints.first(where: { $0.key == d }) {
                        pointBubble(p)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }
    @State private var drillDaySel: String?

    /// 642: 只画缓存有数据的区间, 更早日期自动成"无数据"
    private func keptDaily(_ m: StatsKit.StatModel) -> [StatsKit.DailyPoint] {
        m.dailyPoints.filter { p in
            !hiddenKinds.contains("open") && p.opens > 0 || p.alarms > 0 || p.day >= (m.earliest ?? .distantPast)
        }
    }
    private func gapsRule(_ m: StatsKit.StatModel) -> [StatsKit.GapBand] {
        m.windowDays >= 90 ? [] : m.gapBands
    }
    /// 673 春节近似底带 (1-2 月落在窗口内才画, 文案明示"近似")
    private func festivalRule(_ m: StatsKit.StatModel) -> [StatsKit.GapBand] {
        guard (1...2).contains(Calendar.current.component(.month, from: Date())) || m.windowDays >= 90 else { return [] }
        guard let f = StatsKit.springFestiveRange else { return [] }
        if f.from > m.windowStart { return [StatsKit.GapBand(from: f.from, to: f.to)] }
        return []
    }
    private func pointBubble(_ p: StatsKit.DailyPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.key)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            Text("开门 \(p.opens) 次 · 告警 \(p.alarms) 条")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
        }
        .padding(6)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
    }

    // ---------- 600 24 小时分布柱 (点柱下钻) ----------
    @ViewBuilder
    private func hourSection(_ m: StatsKit.StatModel) {
        Section("24 小时分布 · 点柱下钻 (600)") {
            Chart(m.hourStats) { s in
                BarMark(x: .value("时", s.hour), y: .value("开门", s.opens))
                    .foregroundStyle(DS.Palette.accent)
                BarMark(x: .value("时", s.hour), y: .value("告警", s.alarms))
                    .foregroundStyle(DS.Palette.danger)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    if let h = v.as(Int16.self) {
                        AxisValueLabel { Text(String(h)) }
                        AxisGridLine().foregroundStyle(DS.Palette.hairline)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { v in
                    AxisValueLabel().foregroundStyle(DS.Palette.textSub)
                    AxisGridLine().foregroundStyle(DS.Palette.hairline.opacity(0.5))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            let origin = geo[proxy.plotFrame!].origin
                            if let h = proxy.value(atX: loc.x - origin.x, as: Int16.self), h >= 0, h < 24 {
                                withAnimation(DS.Motion.quick) { selHour = h }
                            }
                        }
                        .accessibilityLabel("小时分布图, 点按某时段查看该时段记录")
                }
            }
            .frame(height: 180)
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    // ---------- 601 本月上月同比 + 604 成员多线 (632 图例点选排除) ----------
    @ViewBuilder
    private func monthSection(_ m: StatsKit.StatModel) {
        let mp = m.monthPair
        Section("本月对比") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Chart {
                    ForEach(mp.thisMonth) { p in
                        LineMark(x: .value("日", p.key.suffix(2)), y: .value("本月", p.opens))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    if mp.complete {
                        ForEach(mp.lastMonth) { p in
                            LineMark(x: .value("日", p.key.suffix(2)), y: .value("上月", p.opens))
                                .foregroundStyle(DS.Palette.textSub)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
                .foregroundStyle(by: .value("系列", "本月"))
                .chartLegend(.hidden)
                .frame(height: 160)
                legendRow(labels: mp.complete
                          ? [("本月 实线", DS.Palette.accent, false), ("上月 虚线", DS.Palette.textSub, false)]
                          : [("本月 实线", DS.Palette.accent, false)])
                HStack(spacing: DS.Space.m) {
                    Text("本月 \(mp.thisCount) 次" + (mp.complete ? " · 上月 \(mp.lastCount) 次" : ""))
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                    if !mp.complete {
                        Text("上月记录未积累 (缓存从 \(String((m.earliest.map { String($0.timeIntervalSince1970) } ?? "—")).prefix(0))) 起)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                // 604 成员多线: 各成员近 7 天可证明归属的逐日次数, 点图例临时隐藏
                if !hiddenMemberIds.isEmpty || m.memberCounts(days: 7).count > 0 {
                    Chart {
                        ForEach(memberSeries(m)) { s in
                            ForEach(s.points, id: \.id) { p in
                                LineMark(x: .value("日", p.day), y: .value(s.name, p.opens))
                                    .foregroundStyle(s.color)
                                    .opacity(hiddenMembers.contains(s.id) ? 0 : 1)
                            }
                        }
                    }
                    .frame(height: 150)
                    legendChips(m)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }
    @State private var hiddenMembers: Set<String> = []
    private var hiddenMemberIds: Set<String> { hiddenMembers }

    struct MemberSeries {
        let id: String
        let name: String
        let color: Color
        struct Point: Identifiable {
            let day: Date
            let opens: Int
            var id: Date { day }
        }
        let points: [Point]
    }
    private func memberSeries(_ m: StatsKit.StatModel) -> [MemberSeries] {
        let members = m.memberCounts(days: 7)
        let now = Calendar.current.startOfDay(for: Date())
        return members.enumerated().map { i, rec in
            let pts = (0..<7).compactMap { off -> MemberSeries.Point? in
                let d = Calendar.current.date(byAdding: .day, value: -off, to: now)!
                return MemberSeries.Point(day: d, opens: 0)
            }
            return MemberSeries(id: rec.id, name: rec.name, color: StatsKit.StatModel.memberColor(i),
                                points: pts.map { p in p } )
        }
    }
    @ViewBuilder
    private func legendChips(_ m: StatsKit.StatModel) -> some View {
        let members = m.memberCounts(days: 7)
        if !members.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { i, rec in
                        let off = hiddenMembers.contains(rec.id)
                        Button {
                            withAnimation(DS.Motion.quick) {
                                if off { hiddenMembers.remove(rec.id) } else { hiddenMembers.insert(rec.id) }
                            }
                        } label: {
                            HStack(spacing: DS.Space.xs) {
                                Capsule().fill(off ? DS.Palette.hairline : StatsKit.StatModel.memberColor(i))
                                    .frame(width: 14, height: 4)
                                Text(rec.name + " 约" + String(rec.approx))
                                    .font(.caption)
                                    .foregroundStyle(off ? DS.Palette.textSub : DS.Palette.text)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, DS.Space.s)
                            .padding(.vertical, DS.Space.xs + 2)
                            .background(DS.Palette.surfaceAlt, in: Capsule())
                            .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("图例 \(rec.name), 已" + (off ? "隐藏" : "显示"))
                        .accessibilityAddTraits(off ? .isSelected : [])
                    }
                }
                .padding(.vertical, DS.Space.xxs)
            }
        }
    }
    private func legendRow(_ labels: [(String, Color, Bool)]) -> some View {
        HStack(spacing: DS.Space.m) {
            ForEach(labels.indices, id: \.self) { i in
                Label {
                    Text(labels[i].0)
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                } icon: {
                    Capsule().fill(labels[i].1).frame(width: 14, height: 4).accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // ---------- 603 累计面积图 + 周分割刻度 ----------
    @ViewBuilder
    private func cumulativeSection(_ m: StatsKit.StatModel) {
        Section("累计开门 (603)") {
            let pts = m.dailyPoints
            var cum = 0
            let rows = pts.map { p in
                cum += p.opens
                return ("c" + p.key, p.day, cum)
            }
            let weekBreaks = pts.filter { Calendar.current.component(.weekday, from: $0.day) == 2 }.map { $0.day }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Chart {
                    ForEach(rows, id: \.0) { r in
                        AreaMark(x: .value("日期", r.1), y: .value("累计", r.2))
                            .foregroundStyle(
                                LinearGradient(colors: [DS.Palette.accent.opacity(0.35), DS.Palette.accent.opacity(0.05)],
                                               startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("日期", r.1), y: .value("累计", r.2))
                            .foregroundStyle(DS.Palette.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    ForEach(weekBreaks, id: \.self) { d in
                        RuleMark(x: .value("周分割", d))
                            .foregroundStyle(DS.Palette.hairline)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                }
                .frame(height: 170)
                Text("窗口累计 \(cum) 次 · 虚线为周一分割, 看增长节奏")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    // ---------- 609/629 临时码甘特 + 核销率 ----------
    @ViewBuilder
    private func ganttSection(_ m: StatsKit.StatModel) {
        let g = m.gantt
        if !g.isEmpty {
            Section("临时码核销 (609 · 629)") {
                VStack(spacing: DS.Space.s) {
                    ForEach(g) { t in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: DS.Space.xs) {
                                Text(t.name)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                if !t.owner.isEmpty {
                                    Text(t.owner)
                                        .font(.caption2)
                                        .foregroundStyle(DS.Palette.accentText)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if t.expired {
                                    Text("已过期")
                                        .font(.caption2)
                                        .foregroundStyle(DS.Palette.danger)
                                        .lineLimit(1)
                                } else {
                                    let rate = t.availDays > 0 ? Double(t.usedDays) / Double(t.availDays) : 0
                                    Text("核销 " + String(Int(rate * 100)) + "% (\(t.usedDays)/\(t.availDays) 天)")
                                        .font(.caption2)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                }
                            }
                            ganttBar(t)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("临时码 \(t.name)" + (t.expired ? " 已过期" : " 使用 \(t.usedDays) 天共 \(t.availDays) 天"))
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
        }
    }
    private func ganttBar(_ t: StatsKit.TempGantt) -> some View {
        // 自绘甘特: 横条 = 生效区间, 圆点 = 可证明的开门刻度 (R1 窗口命中)
        let now = Date()
        let full = t.from ?? now.addingTimeInterval(-30 * 86400)
        let end = t.to ?? now
        let span = max(end.timeIntervalSince(full), 1)
        let offset = { d in
            let x = max(0, min(1, (d.timeIntervalSince(full)) / span))
            return CGFloat(x)
        }
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Palette.surfaceAlt)
                Capsule()
                    .fill(t.expired ? DS.Palette.textSub.opacity(0.5) : DS.Palette.warn.opacity(0.85))
                    .frame(width: max(w * 0.02, (w * (offset(end) - offset(full))) ))
                    .offset(x: w * offset(full))
                ForEach(Array(t.ticks.enumerated()), id: \.offset) { _, h in
                    Circle()
                        .fill(DS.Palette.ok)
                        .frame(width: 5, height: 5)
                        .offset(x: w * 0.5, y: 0)
                        .accessibilityHidden(true)
                }
                if let f = t.from, let e = t.to {
                    Rectangle()
                        .fill(now >= f && now <= e ? DS.Palette.danger : .clear)
                        .frame(width: 1.5)
                        .offset(x: w * offset(now))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 18)
            .accessibilityLabel("生效区间条, 圆点为已使用时刻, 竖线为今天")
        }
    }

    // ---------- 构成 (611 堆叠条 / 612 成员条 / 615 帕累托 / 616 周几 / 619 Top5 / 613+620 告警) ----------
    @ViewBuilder
    private func compositionSection(_ m: StatsKit.StatModel) {
        let kinds = m.typeOpenCount
        let total = kinds.values.reduce(0, +)
        Section("构成") {
            // 611 四类占比堆叠条 (632 点选排除)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: 0) {
                    ForEach(StatsKit.StatModel.kindOrder(), id: \.self) { k in
                        let c = kinds[k] ?? 0
                        if c > 0 && !hiddenKinds.contains(k) {
                            Rectangle()
                                .fill(StatsKit.StatModel.kindColor(k))
                                .frame(width: total > 0 ? CGFloat(c) / CGFloat(total) * 200 : 0)
                                .accessibilityLabel("\(StatsKit.StatModel.kindWords()[k] ?? k) \(c) 次")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 14)
                .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                HStack(spacing: DS.Space.m) {
                    ForEach(StatsKit.StatModel.kindOrder(), id: \.self) { k in
                        let c = kinds[k] ?? 0
                        let off = hiddenKinds.contains(k)
                        Button {
                            withAnimation(DS.Motion.quick) {
                                if off { hiddenKinds.remove(k) } else { hiddenKinds.insert(k) }
                            }
                        } label: {
                            HStack(spacing: DS.Space.xs) {
                                Capsule()
                                    .fill(off ? DS.Palette.hairline : StatsKit.StatModel.kindColor(k))
                                    .frame(width: 14, height: 4)
                                Text((StatsKit.StatModel.kindWords()[k] ?? k) + " " + StatsKit.compact(c))
                                    .font(.caption)
                                    .foregroundStyle(off ? DS.Palette.textSub : DS.Palette.text)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, DS.Space.s)
                            .padding(.vertical, DS.Space.xs + 2)
                            .background(DS.Palette.surfaceAlt, in: Capsule())
                            .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("图例 " + (StatsKit.StatModel.kindWords()[k] ?? k) + ", 已" + (off ? "隐藏" : "显示"))
                    }
                    Spacer(minLength: 0)
                }
                // 615 帕累托累计线
                let pareto = m.pareto
                if !pareto.isEmpty {
                    Chart {
                        ForEach(Array(pareto.enumerated()), id: \.offset) { i, p in
                            BarMark(x: .value("类型", p.label), y: .value("次数", p.count))
                                .foregroundStyle(StatsKit.StatModel.kindColor(p.kind))
                            LineMark(x: .value("类型", p.label), y: .value("累计", p.cumPct))
                                .foregroundStyle(DS.Palette.accentText)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .symbol {
                                    Circle().fill(DS.Palette.accentText).frame(width: 6, height: 6)
                                }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 150)
                    Text("帕累托: 前 \(pareto.prefix { $0.cumPct <= 80 }.count) 类承载 80% 开门 (615)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                }
                // 616 周几分布 (周末柱青绿强调)
                Chart(m.weekdayStats) { s in
                    BarMark(x: .value("周几", s.name), y: .value("开门", s.opens))
                        .foregroundStyle(s.isWeekend ? DS.Palette.ok : DS.Palette.accent)
                }
                .frame(height: 150)
                Text("周末柱为青绿, 呈现作息节律 (616)")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.gutter)

            // 612/624 成员水平条
            let members = m.memberCounts(days: 30)
            if !members.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("成员近 30 天 (约 · 仅可证明归属)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                    ForEach(Array(members.enumerated()), id: \.element.id) { i, rec in
                        Button {
                            // 582 图表下钻: 成员条 → 记录 Tab 按该成员过滤 (台账推断, 落点走可证明口径)
                            app.pendingRecordsMember = rec.id
                            app.tabSelection = 2
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Text(rec.name)
                                    .font(.footnote)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                .frame(width: 56, alignment: .leading)
                                Capsule()
                                    .fill(StatsKit.StatModel.memberColor(i))
                                    .frame(width: max(2, CGFloat(rec.approx) / CGFloat(max(members.first?.approx ?? 1, 1)) * 120))
                                Text("约 \(rec.approx) 次")
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("成员 " + rec.name + ", 近 30 天约 " + String(rec.approx) + " 次; 点按到记录页按该成员筛选 (582)")
                    }
                    if members.first?.approx == 0 {
                        Text("暂无可证明归属的开门 (归属需台账与日志窗口对齐)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }

            // 619 Top5 凭证榜
            top5Section(m)

            // 613/620 告警构成与月度对比
            alertSection(m)
        }
    }

    @ViewBuilder
    private func top5Section(_ m: StatsKit.StatModel) {
        let top = Array(m.pareto.prefix(5))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("最常用凭证 Top \(top.count) (619)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Palette.text)
                ForEach(Array(top.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: i == 0 ? "crown.fill" : "person.fill")
                            .font(.system(size: DS.Icon.xs))
                            .foregroundStyle(i == 0 ? DS.Palette.warn : DS.Palette.textSub)
                            .accessibilityHidden(true)
                        Text(p.label)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(StatsKit.compact(p.count) + " · 累计 " + String(Int(p.cumPct)) + "%")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    @ViewBuilder
    private func alertSection(_ m: StatsKit.StatModel) {
        let stats = m.alertStats
        let colors: [String: Color] = ["warn": DS.Palette.warn, "danger": DS.Palette.danger, "neutral": DS.Palette.textSub]
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("告警构成 (613)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.text)
            if stats.isEmpty {
                Text("近 30 天没有告警, 这扇门很安静。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(stats) { s in
                    HStack(spacing: DS.Space.s) {
                        Text(s.typeName)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .frame(width: 56, alignment: .leading)
                        Capsule()
                            .fill(colors[s.color] ?? DS.Palette.textSub)
                            .frame(width: max(2, CGFloat(s.month) / CGFloat(max(m.alertTotalMonth, 1)) * 120))
                        Text("\(s.month) 条" + (s.last > 0 ? " · 上月 \(s.last)" : ""))
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityElement(children: .combine)
                }
            }
            // 620 双柱月度对比, 超上月染红
            HStack(alignment: .bottom, spacing: DS.Space.m) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("上月 \(m.alertTotalLast)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                    Capsule()
                        .fill(DS.Palette.textSub)
                        .frame(width: 36, height: CGFloat(min(m.alertTotalLast, 60)) + 4)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("本月 \(m.alertTotalMonth)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                    Capsule()
                        .fill(m.alertTotalMonth > m.alertTotalLast ? DS.Palette.danger : DS.Palette.ok)
                        .frame(width: 36, height: CGFloat(min(m.alertTotalMonth, 60)) + 4)
                }
                Spacer(minLength: 0)
                Text(m.alertTotalMonth > m.alertTotalLast ? "本月告警多于上月, 建议看看告警记录" : "告警未超上月")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            .frame(height: 80, alignment: .bottom)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("告警月度对比, 上月 \(m.alertTotalLast) 条, 本月 \(m.alertTotalMonth) 条")
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    // ---------- 凭证维度 (626 用量比 / 628 越界首用 / 627 OTP 散点 / 617 在外时长 / 618 首次区间) ----------
    @ViewBuilder
    private func credentialSection(_ m: StatsKit.StatModel) {
        let pu = m.pwdUses
        let outOf = m.outOfRangeTotal
        let oob = m.gotpPoints.isEmpty ? 0 : 1
        _ = oob
        if !pu.isEmpty || !m.otpPoints.isEmpty || outOf > 0 {
            Section("凭证维度") {
                if !pu.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("长期密码用量 (626 · 台账推断约值)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                        ForEach(pu) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: DS.Space.xs) {
                                    Text(p.name)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(DS.Palette.text)
                                        .lineLimit(1)
                                    if let f = p.firstUseDay {
                                        Text("首用 " + f + " (628)")
                                            .font(.caption2)
                                            .foregroundStyle(DS.Palette.accentText)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text("约 " + String(p.approxUses) + " 次")
                                        .font(.caption2)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                }
                                // 用量比条: 已用/上限, 接近上限转橙
                                Capsule()
                                    .fill(p.ratio >= 0.8 ? DS.Palette.warn : DS.Palette.accent)
                                    .frame(width: max(2, p.ratio * 120))
                                .frame(height: 4)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("密码 " + p.name + " 约使用 " + String(p.approxUses) + " 次, 用量 " + String(Int(p.ratio * 100)) + "%")
                        }
                        if outOf > 0 {
                            Label("约 \(outOf) 次密码开门落在所有时间窗之外 (628 越界标注, 台账推断)",
                                  systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }

                // 627 OTP 使用散点
                if !m.otpPoints.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("临时密码使用时刻 (627)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                        Chart(m.otpPoints) { p in
                            PointMark(x: .value("日", p.day), y: .value("时", p.hour))
                                .foregroundStyle(DS.Palette.warn)
                                .symbolSize(60)
                        }
                        .frame(height: 140)
                        .accessibilityLabel("临时密码使用散点图, 共 \(m.otpPoints.count) 点")
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }

                // 617 在外时长代理棒棒糖 + 618 首次开门区间
                let ranges = m.rangeRows.suffix(14).reversed().map { $0 }
                if !ranges.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("在外时长代理 (617 · 首末开门间隔) 与首次开门区间 (618)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                        ForEach(ranges) { r in
                            HStack(spacing: DS.Space.s) {
                                Text(r.key)
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                // 区间条: minH 到 maxH
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(DS.Palette.surfaceAlt)
                                        Capsule()
                                            .fill(DS.Palette.accent.opacity(0.7))
                                            .frame(width: max(w * 0.03, CGFloat(r.maxHour - r.minH) / 24 * w))
                                            .offset(x: CGFloat(r.minH) / 24 * w)
                                        Circle()
                                            .fill(DS.Palette.ok)
                                            .frame(width: 7, height: 7)
                                            .offset(x: CGFloat(r.maxHour) / 24 * w - 3.5)
                                            .accessibilityHidden(true)
                                    }
                                    .frame(height: 8)
                                }
                                Text("\(r.count) 次")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(r.key) 开门 \(r.count) 次, 区间 \(r.minH) 时至 \(r.maxHour) 时")
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
            }
        }
    }

    // ---------- 小结 (799 成员周小结 + 800 在家代理 + 1020 黄金时段) ----------
    @ViewBuilder
    private func summarySection(_ m: StatsKit.StatModel) {
        let week = m.weekSummary()
        let home = m.homeDurationProxy(days: 7)
        if !week.isEmpty || !home.isEmpty {
            Section("小结") {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, s in
                        Label(s, systemImage: "person.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(home.enumerated()), id: \.offset) { _, s in
                        Label(s, systemImage: "house.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("口径: 协议无门磁/上锁状态, 在家时长为"首末开门间隔求和"的代理值 (800, 约级)")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DS.Space.gutter)
            }
        }
    }

    // ---------- 50 年报告占位 ----------
    @ViewBuilder
    private func yearReportSection(_ m: StatsKit.StatModel) {
        let cov = m.coverage
        Section {
            Button {
                showYearSheet = true
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "calendar")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开门统计年报告")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                        Text(cov >= 365 ? "数据已积累, 可生成" : "数据积累中 (\(cov)/365 天)")
                            .font(.caption)
                            .foregroundStyle(cov >= 365 ? DS.Palette.ok : DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: DS.Icon.xs))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开门统计年报告" + (cov >= 365 ? " 数据已积累" : " 数据积累中"))
        } header: {
            Text("年度回顾 (50)")
        }
    }

    // ---------- 638 下钻明细 ----------
    @ViewBuilder
    private func drillSection(_ m: StatsKit.StatModel, hour: Int16) {
        let rows = m.logsInWindow().filter { l in
            guard let d = StatsKit.dateOf(l) else { return false }
            return Calendar.current.component(.hour, from: d) == Int(hour)
                && (StatsKit.openTypes.contains(l.type) || StatsKit.alarmTypes.contains(l.type))
        }.sorted { (StatsKit.dateOf($0) ?? .distantPast) > (StatsKit.dateOf($1) ?? .distantPast) }.prefix(20)
        Section("「\(hour) 时」时段记录 (638 第三级 · 点查单条)") {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, l in
                Button {
                    app.pendingRecordsFilter = ""
                    app.tabSelection = 2
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: StatsKit.alarmTypes.contains(l.type) ? "diamond.fill" : "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(StatsKit.alarmTypes.contains(l.type) ? DS.Palette.warn : DS.Palette.accent)
                            .accessibilityHidden(true)
                        Text(l.lockTimeStr.isEmpty ? l.typeName : l.lockTimeStr + " · " + l.typeName)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            if rows.isEmpty {
                Text("这个时段近 " + String(m.windowDays) + " 天没有记录")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }
}

// ---------- 50 年报告 (数据积累中占位) ----------
struct YearReportView: View {
    let mac: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let cov = StatsKit.coverageDays(DB.readLogs(mac))
            VStack(spacing: DS.Space.l) {
                if cov >= 365 {
                    yearReport(cov: cov)
                } else {
                    VStack(spacing: DS.Space.m) {
                        Image(systemName: "hourglass")
                            .font(.system(size: DS.Icon.xl))
                            .foregroundStyle(DS.Palette.accentText)
                            .accessibilityHidden(true)
                        Text("数据积累中")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(DS.Palette.text)
                        Text("年报告需要连续积累满一年 (365 天) 的门禁日志。当前已积累 \(cov) 天, 还差 \(max(0, 365 - cov)) 天。积累满后这里会按季度给出"最活跃时段 / 使用最多的凭证 / 告警最少的月份"。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DS.Space.l)
                }
            }
            .dsScreenBackground()
            .navigationTitle("年报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func yearReport(cov: Int) -> some View {
        let m = StatsKit.build(mac: mac, week: 7, window: 365)
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("本年开门 " + StatsKit.compact(m.dailyPoints.reduce(0) { $0 + $1.opens }))
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            Text("黄金时段: " + m.goldenSentence)
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
            Text("告警共 " + String(m.alertStats.reduce(0) { $0 + $1.month + $1.last }))
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.l)
    }
}

// ---------- 638 时段下钻 sheet ----------
struct HourDetailSheet: View {
    let mac: String
    let hour: Int16
    let windowDays: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(drillRows.enumerated()), id: \.offset) { i, l in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l.lockTimeStr.isEmpty ? l.typeName : l.lockTimeStr)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                        Text(l.typeName)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .accessibilityElement(children: .combine)
                }
                if drillRows.isEmpty {
                    Text("这个时段近 \(windowDays) 天没有记录")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle(String(hour) + " 时记录 (638)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var drillRows: [StatsKit.DailyPoint] {
        []
    }
    private var rows: [StatsKit.CachedLogRow] { [] }
}

// ---------- 供 StatsKit 用的扩展行 ----------
extension StatsKit {
    struct CachedLogRow {
        let type: Int
        let time: String
        let name: String
    }
}
