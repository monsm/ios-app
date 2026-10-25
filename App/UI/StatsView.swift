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
    // 2026-10-15 走查: 这一页全仓只有一个呈现点 —— 记录页里的 sheet。sheet 浮在最上层时改
    // tabSelection, 切的是**被盖住的那层 TabView**: 用户点了"去读取记录/去添加门锁"只看见屏幕
    // 没反应, 等他下拉甩掉这张 sheet 才发现自己站在别的 Tab 上。同锁同页的既有正解见
    // 跳到别的 Tab 之后紧跟一句 dismiss —— 全仓统一这一套, 不另造第二套。
    @Environment(\.dismiss) private var dismiss
    // 643 横屏分栏的档位读数。形状先例: @Environment 这一族本文件已有 (:2179 年报告与 :2265 时段 sheet 的 \.dismiss),
    // size class 这一路在本条落地前的 App/ 全量 grep 里零命中。
    // ⚠ API-VERIFY: @Environment(\.horizontalSizeClass) 本仓无先例, 未编译、未证实。
    //   官方页 SwiftUI/EnvironmentValues/horizontalSizeClass 命中: 类型 UserInterfaceSizeClass?, iOS 13 起,
    //   无 deprecated / unavailable 标记; 写法逐字 `@Environment(\.horizontalSizeClass) private var horizontalSizeClass`。
    // 档位事实面 (本仓配置, 只读证据): project.yml:65 TARGETED_DEVICE_FAMILY "1" (只 iPhone) +
    //   project.yml:38-39 UISupportedInterfaceOrientations 只有 UIInterfaceOrientationPortrait (只竖屏)
    //   ⇒ 当前设备族下这一档取到的都是 compact, regular 那条分支要等 iPad/横屏放开才走得到。
    //   这一档判据与 599-646 的数据口径无关: 它只决定容器形状。
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var mac: String
    @State private var week: Int = 7      // 678/604 周族窗口天数 (成员多线 604 与周小结 799 共用这一份; 604 起有 weekChips 显式双档, 678 未拍板默认仍 7; 主图窗口是 599/636 的 30 天默认档)
    @State private var windowDays: Int = 30   // 599/636 主图窗口 (会话内保持)
    @State private var hiddenKinds: Set<String> = []   // 632 图例点选排除
    @State private var selHour: Int16? = nil    // 600/638 时段下钻
    @State private var drillDay: String? = nil  // 638 三级下钻: 主图选中的日
    @State private var brush: ClosedRange<String>? = nil   // 621 刷选区间 (日 key, 只在本次会话)
    @State private var labelMode: Int                     // 640 数值标签 0 避让 / 1 仅最大值 / 2 不标 (存本机)
    @State private var showYearSheet = false    // 50 年报告占位
    @State private var showExport = false       // 包12 导出中心入口
    @State private var excludeIdle = DB.store.getBool("kf_stats_excl_idle")   // 782 排除闲置锁口径

    init(mac: String = DB.currentMac) {
        _mac = State(initialValue: mac.isEmpty ? (DB.keychains().first?.mac ?? "") : mac)
        _labelMode = State(initialValue: DB.store.getInt("kf_stat_labels", 0))
    }

    /// 625 凭证归属子段条的一类 —— 从 body 内联的 ForEach 里抽出: 该表达式报 type-check 超时
    @ViewBuilder
    private func kindBreakdownRow(_ k: String, _ segs: [(id: String, name: String, n: Int)]) -> some View {
        let total = segs.reduce(0) { $0 + $1.n }
        // 2026-10-13 run 69: a11y 串 (三段拼接含 map) 先算好 —— 内联时该行仍报 type-check 超时。
        let a11y = (StatsKit.StatModel.kindWords()[k] ?? k) + " 归属构成, 共约 \(total) 次; "
            + segs.prefix(4).map { $0.name + " 约 " + String($0.n) + " 次" }.joined(separator: ", ")
            + (segs.count > 4 ? "; 另 \(segs.count - 4) 位" : "")
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            kindBreakdownBar(k: k, segs: segs, total: total)
            kindBreakdownLegend(segs)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
    }

    /// 625 子段条 (色段) —— 从 kindBreakdownRow 抽出: 该表达式报 type-check 超时
    @ViewBuilder
    private func kindBreakdownBar(k: String, segs: [(id: String, name: String, n: Int)], total: Int) -> some View {
        HStack(spacing: 2) {
            Text(StatsKit.StatModel.kindWords()[k] ?? k)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
            GeometryReader { geo in
                HStack(spacing: DS.Space.xxs) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { idx, sg in
                        Capsule()
                            .fill(StatsKit.StatModel.memberColor(idx % 6))
                            .frame(width: max(3, CGFloat(sg.n) / CGFloat(max(total, 1)) * geo.size.width))
                    }
                }
            }
            .frame(height: 6)
            Text("约 \(total) 次")
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
        }
    }

    /// 625 子段图例 (成员名 + 次数, 超 4 位折叠) —— 同上
    @ViewBuilder
    private func kindBreakdownLegend(_ segs: [(id: String, name: String, n: Int)]) -> some View {
        HStack(spacing: DS.Space.s) {
            ForEach(Array(segs.prefix(4).enumerated()), id: \.offset) { idx, sg in
                HStack(spacing: DS.Space.xs) {
                    Circle()
                        .fill(StatsKit.StatModel.memberColor(idx % 6))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(sg.name + " 约 " + String(sg.n) + " 次")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                }
            }
            if segs.count > 4 {
                Text("+" + String(segs.count - 4) + " 位")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }

    var body: some View { vkBody.destined(.stats) }
    var vkBody: some View {
        NavigationStack {
            content
                .navigationTitle("统计")
                .navigationSubtitle(lockName)   // 772 单锁视图标题携带锁名
                .variantList()
                .dsScreenBackground()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { build() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("重新统计")
                    }
                    // 包12: 统计页导出入口 — 复用记录 Tab 导出中心 (范围默认当月, 685/701)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("导出与分享") { showExport = true }   // 685 导出与分享
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("导出")
                    }
                }
                .sheet(isPresented: $showExport) { ExportCenterView(mac: mac) }
                .sheet(isPresented: $showYearSheet) { YearReportView(mac: mac) }
                .sheet(item: $selHour) { h in
                    HourDetailSheet(mac: mac, hour: h, windowDays: windowDays)
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
        // 621 换锁、换窗口、手动重算都让刷选作废: 旧日 key 可能已落在新窗口之外，
        // 留着它下面的明细会显示一段"标题看着对、数据其实空"的区间。
        brush = nil
    }

    // 638 面包屑: 统计 → 时段/日期 → 单条
    private var breadcrumb: [String] {
        var crumb = ["统计"]
        // 658: 时段词跟进制式 — 面包屑里的"时"也先说清晨/上午/深夜, 与图表轴标同一份词表
        if let h = selHour { crumb.append(TimeWord.word(Int(h)) + " " + String(h) + " 时") }
        if let d = drillDay { crumb.append(d) }
        return crumb
    }

    @ViewBuilder
    private var content: some View {
        if locks.isEmpty {
            EmptyState(systemImage: "chart.bar",
                       title: "还没有门锁",
                       message: "统计全部来自门锁本地台账。先添加并配对门锁, 读取记录后再来看趋势。",
                       actionTitle: "去添加门锁") { app.requestRoute(.device); dismiss() }
        } else if let m = model {
            List {
                Section {
                    lockPicker
                    // 782 口径开关: 原句要求统计页可选择"排除闲置锁" —— 落点就是这处数据源选择列表
                    VariantToggle("排除闲置锁", isOn: Binding(   // 782 排除闲置锁
                        get: { excludeIdle },
                        set: { DB.store.set("kf_stats_excl_idle", $0); excludeIdle = $0 }))
                    Text("闲置 = 本机日志里超 30 天无开门行 (说的是「没读到」不是「没人开」, 与对照页同判据)。开关只收起选择列表, 已在看的锁不受影响。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } header: { Text("数据源 · 每锁独立统计") }   // 772/782 数据源
                Section { windowChips; breadcrumbRow } header: { Text("窗口") }
                if m.isDegraded {
                    Section {
                        degradationCard(m)
                    }
                } else {
                    Section { headlineCards(m) }
                    trendSection(m)
                    brushSection(m)   // 621 刷选区间联动刷新下方明细 (643: regular 档这份明细挪到上方主图右侧那一格, 由 trendSection 内的 brushDetailSide 上屏; compact 档照旧在这一位)
                    hourSection(m)
                    weekBarsSection(m)
                    heatmapSection(m)   // 14 月度热力格 (GitHub 形态)
                    holidayBarsSection(m)   // 608 假期最后 3 天逐时柱
                    radarSection(m)          // 602 作息雷达 (四轴)
                    alarmScatterSection(m)
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
        // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
        // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
        Picker("门锁", selection: $mac) {
            ForEach(pickerLocks) { kc in
                Text(LockArchive.displayName(kc)).tag(kc.mac)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: mac) { _, _ in build() }
    }

    /// 782 口径开关: 排除闲置锁只收菜单里的闲置项; 已在看的锁即使闲置也留一行
    /// (它是当前数据源, 收掉会变成"选着一个列表里看不见的锁")
    private var pickerLocks: [Keychain] {
        guard excludeIdle else { return locks }
        return locks.filter { $0.mac == mac || !StatsKit.isIdleLock($0.mac) }
    }

    /// 775 一族 (775/783/781/782) 的入口。只有一把锁时**不出现**，
    /// 而不是进来看到一句"请再添加一把锁" —— 对比这个动作在单锁设备上根本不存在。
    @ViewBuilder

    // ---------- 678/634/636 窗口胶囊 + 上下文标签 ----------
    /// 636 在这里落地的是原句的后半 (7/30/90/365 四档窗口 + 窗口状态在本次会话内保持, 见 `windowDays` 那枚 @State)。
    /// 636 的前半"捏合缩放窗口"已落地: 趋势图容器上挂了 MagnifyGesture (捏开进更长窗口 / 捏合退一档, 见 trendSection)。
    /// 胶囊仍可切换, 两条入口共用同一份四档数组与同一枚 windowDays 状态。
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
                            .vkFont(.subheadline, weight: .medium)
                            .padding(.horizontal, DS.Space.l)
                            .padding(.vertical, 12)
                            .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                            .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.text)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("近" + String(w) + "天窗口")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                // 646 的小时桶折叠只在**下方 621 那条明细列表**上真发生, 那句话也跟着搬去那里 (同一张列表自己说)。
                // 这一排胶囊里原先挂着"大数据已按小时桶降采样"一行常驻文案, 而当时全仓没有小时桶聚合
                // (StatsKit 只做逐日聚合, 日志缓存每锁只有 300 条) —— 挂在窗口行上等于替一个不存在的处理背书。
            }
            .padding(.vertical, DS.Space.xxs)
        }
    }
    /// 634 窗口上下文标签: 常显"近 30 天 · N 位可归属成员"
    private var contextLabel: some View {
        let n = model?.memberCounts(days: windowDays).count ?? 0
        // 665 区间精简: 把"近 N 天"落到**具体日子**。跨年时"近 365 天"到底含不含今年，
        // 只看天数说不清；同年/同月的省略写法又不会把它压成一行长数字。
        let toD = Date()
        let fromD = WeekCal.shifted(toD, days: -max(windowDays - 1, 0))
        let span = TimeFormat.range(fromDay: RecordSearch.dayKeyOf(fromD), toDay: RecordSearch.dayKeyOf(toD))
        return Label {
            Text("近 \(windowDays) 天 · " + span + " · " + (n == 0 ? "暂无归属成员" : "\(n) 位成员"))
                .vkFont(.caption)
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
                        .vkFont(.footnote.weight(i == breadcrumb.count - 1 ? .semibold : .medium))
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
                    .vkFont(.headline)
                    .foregroundStyle(DS.Palette.text)
                if !m.hasData {
                    Text("这把锁还没有本地记录。连接门锁读取日志后, 这里会出现 7 天以上的趋势图。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("目前累计 \(m.coverage) 天, 再积累 \(max(0, 7 - m.coverage)) 天即可解锁完整趋势图。当前可看上方摘要。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    app.pendingRecordsFilter = ""
                    app.requestRoute(.records)
                    dismiss()
                } label: {
                    Label("去读取记录", systemImage: "tray")
                        .vkFont(.subheadline, weight: .medium)
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
        // 开门总量只认 `opensTotal` 那一个定义 (StatsKit 里那条注释就是冲着"别在视图里再 reduce 一遍"写的)
        let total = m.opensTotal
        let days = max(m.windowDays, 1)
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                summaryCard("近 " + String(m.windowDays) + " 天开门", StatsKit.StatModel.compact(total),
                            sub: StatsKit.StatModel.naturalSentence(total: total, days: days),
                            delta: m.weekDelta, icon: "door.open.fill")
                summaryCard("告警", String(m.alertTotalMonth),
                            sub: m.alertTotalLast > m.alertTotalMonth ? "少于上月" : "较上月",
                            delta: nil, icon: "exclamationmark.triangle.fill")
            }
            Label {
                Text(m.goldenSentence)
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
            }
            .padding(DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 2026-10-14 材质统一: 它左右两块 summaryCard 走的是 Card (已玻璃), 这条黄金时段句
            // 是同排第三块面板, 独留实底 ⇒ 一行三种层感。
            .axGlass(DS.Radius.card)
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
                        .vkFont(.caption)
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
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.accentText)
                            .lineLimit(1)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Text(value)
                        .vkFont(.title2, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                        .monospacedDigit()
                    Text(sub)
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 0)
    }

    // ---------- 趋势 (599 折线 + 606 均线 + 610 空窗 + 673 春节 + 642 无数据底纹 + 635 按住读点 + 607 告警日三角) ----------
    /// 643 分栏成立判据: 水平尺寸档取到 regular 且已有 621 刷选区间 —— 这两件事齐了才有
    /// 「主图 + 它自己驱动的那份区间明细」一对可并排。621 那份明细本来就只在有区间时存在
    /// (判据仍是改前那一个 `if let b = brush`), 所以这一档与它同步出现; compact 档整页保持改前的单列顺序。
    private var wideSplitTrend: Bool { hSize == .regular && brush != nil }

    @ViewBuilder
    private func trendSection(_ m: StatsKit.StatModel) -> some View {
        Section("趋势") {
            if wideSplitTrend, let b = brush {
                // 643 regular 档: 主图与它驱动的 621 区间明细左右并排 —— 主图列取容器的 3/5 (≈60%), 明细列取 2/5 (≈40%)。
                // 两列的内容各自调 compact 档同一份实现 (trendMainColumn / brushDetailBody), 这一档动的是容器。
                // ⚠ API-VERIFY: containerRelativeFrame 本仓无先例 (本条落地前的 App/ 全量 grep 零命中), 未编译、未证实。
                //   官方页 SwiftUI/View/containerrelativeframe(_:count:span:spacing:alignment:) 命中, 签名逐字
                //   `(_ axes: Axis.Set, count: Int, span: Int = 1, spacing: CGFloat, alignment: Alignment = .center)`,
                //   iOS 17 起、无 deprecated / unavailable 标记 (本仓部署目标 iOS 26.5, project.yml:6-7)。
                //   选它而非 GeometryReader 的理由: 本仓 GeometryReader 的先例 (:454 主图 overlay、:598 刷选轨道、
                //   :1511 甘特条、:2009 逐日区间条) 全部挂在 `.frame(height:)` 定高容器上, 而这一列的高由图表 + 轨道 +
                //   635 气泡动态撑开, 给它写死高度就会裁内容; containerRelativeFrame 只定横向比例, 纵向仍交给内容自己算。
                //   比例算法: 每列宽 = (容器宽 - spacing×4)/5 × span ⇒ 两列合计 (容器宽 - spacing×4),
                //   与 HStack 的栏间距 spacing 相加后仍在容器之内 (两种 span 语义解释下都不溢出), 所以这一档的水平留白
                //   由两列自身与 List 行边距承担; 整宽档那句 `.padding(.horizontal, DS.Space.gutter)` 原样留在 else 分支。
                HStack(alignment: .top, spacing: DS.Space.m) {
                    trendMainColumn(m)
                        .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: DS.Space.m, alignment: .topLeading)
                    brushDetailSide(m, b)
                        .containerRelativeFrame(.horizontal, count: 5, span: 2, spacing: DS.Space.m, alignment: .topLeading)
                }
                // 643 并排容器的 grouping 照抄本文件既有写法 (.accessibilityElement(children: .contain) 带一句 label,
                // 见 :483 主图自己那条与 :987 608 那族): 两列内部的元素与读屏先后照旧, 外层补的是一句"这是一对"的话。
                .accessibilityElement(children: .contain)
                .accessibilityLabel("趋势主图与其区间明细并排")
            } else {
                trendMainColumn(m)
                    .padding(.horizontal, DS.Space.gutter)
            }
        }
    }

    /// 643: 主图那一列 —— 整段从改前的 trendSection 原样搬进这一个函数出口 (Mark 顺序与取值、638 点选 overlay 的
    /// 取日判据、`.frame(height: 220)`、636 捏合窗口手势、动画、读屏标签、621 轨道、635 气泡逐字照旧),
    /// compact 档与 643 分栏档共用它 ⇒ 图表实现只有一个出处; 搬过来的那段仅整体少缩进 4 空格。
    @ViewBuilder
    private func trendMainColumn(_ m: StatsKit.StatModel) -> some View {
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
                    // 644 逐点朗读: 每个点自带日期与"开门 N 次 · 告警 M 条" (照 614 小时柱的逐柱写法)。
                    // 面积是同一组数的视觉底子, 藏给读屏 —— 不藏的话同一个点会被念两遍。
                    LineMark(x: .value("日期", p.day), y: .value("开门", p.opens))
                        .foregroundStyle(DS.Palette.accent)
                        .interpolationMethod(.monotone)
                        .accessibilityLabel(p.key)
                        .accessibilityValue("开门 " + String(p.opens) + " 次 · 告警 " + String(p.alarms) + " 条")
                    AreaMark(x: .value("日期", p.day), y: .value("开门", p.opens))
                        .foregroundStyle(DS.Palette.accent.opacity(0.10))
                        .accessibilityHidden(true)
                }
                ForEach(m.movingAverage) { p in
                    LineMark(x: .value("日期", p.day), y: .value("均线", p.avg))
                        .foregroundStyle(DS.Palette.warn)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                // 607 替代: 防撬 / 低电量告警日的三角符号 (点按走上面的 638 读点气泡)
                ForEach(damageMarks(m)) { p in
                    PointMark(x: .value("日期", p.day), y: .value("开门", p.opens))
                        .symbol(.triangle)
                        .symbolSize(70)
                        .foregroundStyle(DS.Palette.danger)
                        .accessibilityLabel(p.ax)
                        .accessibilityValue("开门 " + String(p.opens) + " 次")
                }
                if let d = drillDay, let p = m.dailyPoints.first(where: { $0.key == d }) {
                    RuleMark(x: .value("选中", p.day))
                        .foregroundStyle(DS.Palette.accentText)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading) {
                        pointBubble(p, top: topMember(p.key, m))
                    }
                }
            }
            // 638 点选下钻: 点按主图某天 → 选中日 RuleMark + 读点气泡 + 面包屑 (chartXSelection 对 Date 轴需绑定 Date?, 走 overlay 自管)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            let origin = plotRect(proxy, geo).origin
                            if let d = proxy.value(atX: loc.x - origin.x, as: Date.self) {
                                let key = StatsKit.dayKey(d)
                                drillDaySel = (drillDaySel == key) ? nil : key
                                drillDay = drillDaySel
                            }
                        }
                        .accessibilityLabel("点按选中日期下钻")
                }
            }
            .frame(height: 220)
            // 636 捏合缩放窗口: 捏开 (放大手势) 换下一档更长窗口, 捏合换上一档; 阈值 1.15/0.85 防误触。
            // 复用 windowChips 同一份四档数组与 build(), 窗口状态仍是那枚 windowDays @State —— 不造第二套。
            // 用 MagnifyGesture (iOS 17+ 现行 API; 老的 MagnificationGesture 同 SDK 已弃用)。
            .gesture(
                MagnifyGesture().onEnded { v in
                    let all = [7, 30, 90, 365]
                    guard let i = all.firstIndex(of: windowDays) else { return }
                    if v.magnification > 1.15, i < all.count - 1 {
                        withAnimation(DS.Motion.standard) { windowDays = all[i + 1] }; build()
                    } else if v.magnification < 0.85, i > 0 {
                        withAnimation(DS.Motion.standard) { windowDays = all[i - 1] }; build()
                    }
                }
            )
            .animation(DS.Motion.standard, value: windowDays)
            .accessibilityElement(children: .contain)
            // 644: 逐点 label/value 已有, 整图再补一句"总量 + 峰值日期" —— 原句要求"读出趋势与峰值日期"
            .accessibilityLabel(m.dailyPoints.count > 0
                ? "近\(m.windowDays)天开门趋势折线图。" + peakSummary(m)
                : "暂无趋势数据")
            // 711 拖放导出: iPad 分屏下长按图表可直接拖出 —— 载荷是**文本片段** (窗口摘要)。
            // 原句点名的"拖出 PDF 片段"要先有片段渲染器 (全仓 PDF 都是整份走 ShareLink/OneShotFormatter),
            // 这里给文本这一档, 拖进备忘录就是一段可读摘要, 不假装是 PDF。
            .draggable(m.dailyPoints.count > 0 ? "近\(m.windowDays)天开门趋势: " + peakSummary(m) : "暂无趋势数据")

            brushStrip(m)

            if let d = drillDaySel {
                // 635 读点: 当日开门次数 + 当日 Top 成员 (可证明归属, "约") + 当日告警条数。
                // 637 原句是"拖动指示线时下方明细列表同步滚动到对应日期组"—— 这一半没落地, 也不在这页凭空写:
                // ① 这一页没有"按日期分组的明细列表"可滚 (明细只有刷选出区间才成节, 见 621; 时段那节按小时不按日);
                // ② 全仓没有 ScrollViewReader/scrollTo, 把 List 包进 ScrollViewReader 要移动整条修饰符链,
                //    RecordsView 顶部为同一件事算过账并撤掉, 这里照旧不冒那个编译风险。
                // 所以"联动"只做到**数据换范围**那一半 (621 轨道改动的是下面那份明细), 滚动位置不动。
                if let p = m.dailyPoints.first(where: { $0.key == d }) {
                    pointBubble(p, top: topMember(p.key, m))
                        .accessibilityElement(children: .combine)
                }
            }
        }
    }
    /// 644: 折线图的读屏摘要 (总量 + 峰值日期)。逐点朗读在 LineMark 的 label/value 上,
    /// 这里给整图一句趋势结论 —— 两者并存, 不互相顶掉。
    private func peakSummary(_ m: StatsKit.StatModel) -> String {
        let pts = m.dailyPoints
        guard let top = pts.max(by: { $0.opens < $1.opens }), top.opens > 0 else { return "窗口内暂无开门记录" }
        let total = pts.reduce(0) { $0 + $1.opens }
        return "共 \(total) 次开门, 峰值在 " + top.day.formatted(date: .long, time: .omitted) + ", \(top.opens) 次"
    }

    @State private var drillDaySel: String?

    /// 642: 只画缓存有数据的区间, 更早日期自动成"无数据"
    /// 607 替代: 原句是"趋势图用三角符号标记胁迫告警日, 点击弹当日摘要气泡" —— 胁迫类协议没有 (§5),
    /// 改标**真实存在**的两类: 防撬 (7) 与低电量 (6)。数据取模型里那份窗口内缓存日志 (与 dailyPoints
    /// 同一份源, 不额外读盘), 纵值用该日开门次数 ⇒ 三角正好落在那一天的折线上;
    /// 点按走 638 既有的读点气泡 (气泡里已经有"开门 N 次 · 告警 M 条"), 不另造第二个气泡。
    private struct DamageMark: Identifiable {
        let id: String        // dayKey
        let day: Date
        let opens: Int
        let ax: String        // 读屏用: "防撬告警日" / "低电量告警日" / "防撬/低电量告警日"
    }
    private func damageMarks(_ m: StatsKit.StatModel) -> [DamageMark] {
        var kinds: [String: Set<Int>] = [:]
        for l in m.logsInWindow() where l.type == 7 || l.type == 6 {
            guard let d = StatsKit.dateOf(l) else { continue }
            kinds[StatsKit.dayKey(d), default: []].insert(l.type)
        }
        return kinds.compactMap { k, ts in
            guard let p = m.dailyPoints.first(where: { $0.key == k }) else { return nil }
            let names = ts.sorted().map { $0 == 7 ? "防撬" : "低电量" }.joined(separator: "/")
            return DamageMark(id: k, day: p.day, opens: p.opens, ax: names + "告警日")
        }.sorted { $0.day < $1.day }
    }

    private func keptDaily(_ m: StatsKit.StatModel) -> [StatsKit.DailyPoint] {
        // 642「只画有数据的区间」真实判据是后面那三项。原式子开头还挂着
        // `!hiddenKinds.contains("open")` —— 图例点选 (632) 的键全部来自 StatModel.kindOrder()
        // (凭证类别那四类)，集合里根本没有 "open" 这个键，那半句恒为真、是个空壳；
        // 而且 hiddenKinds 管的是构成条的四类，与折线的"开门/告警"两系列不是同一套轴，
        // 硬把它接过来会变成"点凭证类别，趋势线跟着少一天"。故删壳、留真判据 (真值表不变)。
        m.dailyPoints.filter { p in
            p.opens > 0 || p.alarms > 0 || p.day >= (m.earliest ?? .distantPast)
        }
    }
    /// 610 空窗带: 长窗口 (≥90 天档) 里一天挤一条带会把轴糊住, 这一档收起不画。
    /// 天数读 `m.longWindowDays` —— 与 646 折叠判据同一个出处, 不各写一遍 90。
    private func gapsRule(_ m: StatsKit.StatModel) -> [StatsKit.GapBand] {
        m.windowDays >= m.longWindowDays ? [] : m.gapBands
    }
    /// 673 春节底带: 区间 = 671 表里该年春节"放假日"的首末日 (不再前后推算, 补班日不计入);
    /// 窗口与假期不相交就不画, 表里没这一年 (公告未发布) 也不猜。
    private func festivalRule(_ m: StatsKit.StatModel) -> [StatsKit.GapBand] {
        guard let f = StatsKit.springFestiveRange(around: m.windowStart) else { return [] }
        let end = min(f.to, Date())   // f.to 是末日次日 0 点：不越过今天，免得在轴右端画出一条零宽带
        if end <= m.windowStart { return [] }
        return [StatsKit.GapBand(from: max(f.from, m.windowStart), to: end)]
    }
    /// 635 读点气泡: 当日次数 + Top 成员 + 告警数 (三项齐, 对齐原句"当日次数、Top 成员、告警数")。
    private func pointBubble(_ p: StatsKit.DailyPoint, top: (name: String, n: Int)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.key)
                .vkFont(.caption2, weight: .semibold)
                .foregroundStyle(DS.Palette.text)
            Text("开门 \(p.opens) 次 · 告警 \(p.alarms) 条")
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
            if let t = top {
                Text("成员最多: 约 " + t.name + "（" + String(t.n) + " 次）")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
        }
        .padding(DS.Space.s)
        // 2026-10-14 材质统一批次: 读数气泡**保持实底**。它浮在折线图元之上, 存在的理由就是
        // 把被点的那一天从图里"盖出来"读清 —— 换成玻璃, 被指的那段线会从字底下透上来。
        // @layout-allow 面板实底
        // @layout-allow VK豁免 面板实底: 读数气泡：它浮在折线图元之上，存在的理由就是把那一天从图里盖出来可读
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
    }
    /// 635 当日 Top 成员: 与 604/612 同一套 Attribution 归属链 (memberDaily), 带"约";
    /// 一个可证明归属的成员都没有时返回 nil, 那行整行不出现 (不造话)。drillDay 只由主图点选写入,
    /// 取窗就是 windowDays, 所以 memberDaily(days: m.windowDays) 必覆盖选中日, 不新增数据面。
    private func topMember(_ dayKey: String, _ m: StatsKit.StatModel) -> (name: String, n: Int)? {
        var bestName: String?
        var bestN = 0
        for rec in m.memberDaily(days: m.windowDays) {
            let n = rec.perDay[dayKey] ?? 0
            if n > bestN { bestN = n; bestName = rec.name }
        }
        guard let b = bestName, bestN > 0 else { return nil }
        return (b, bestN)
    }

    // ---------- 621 时间刷选条 + 联动明细 ----------
    /// 主图下面那根缩略轨道: 整窗逐日迷你柱 + 一个拖出来的窗口 (股票 App 范围选择器那一形态)。
    /// 它**只改下方明细列表的数据范围，不改主图窗口** —— 主图窗口只归 636/678 那一排窗口胶囊管，
    /// 两套手势抢同一根 x 轴，拖一下顺手把窗口改了，是这类控件最容易挨骂的地方。
    /// 轨道只在 ≥3 天时出现: 只有今天/昨天那种跨度里"选一段区间"没有可读的意义，画一根轨道是装样子。
    /// 近一年 (365 天) 那档是这一形态的压力面 —— 一天一根 1pt 宽的柱，真机上要看它拖不拖慢这张卡 (VERIFY 148 ⑦)。
    @ViewBuilder
    private func brushStrip(_ m: StatsKit.StatModel) -> some View {
        let days = m.dailyPoints
        if days.count >= 3 {
            let maxV = max(1, days.map { $0.opens }.max() ?? 1)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                GeometryReader { geo in
                    let step = geo.size.width / CGFloat(days.count)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(days.enumerated()), id: \.offset) { i, p in
                            Capsule()
                                .fill(brushContains(p.key) ? DS.Palette.accent : DS.Palette.accent.opacity(0.28))
                                .frame(width: max(1, step - 1), height: 2 + CGFloat(p.opens) / CGFloat(maxV) * 20)
                                .offset(x: CGFloat(i) * step)
                        }
                        if let sel = brushRect(days: days, step: step) {
                            Rectangle()
                                .fill(DS.Palette.accent.opacity(0.10))
                                .frame(width: sel.w, height: 24)
                                .overlay(Rectangle().strokeBorder(DS.Palette.accent, lineWidth: 1))
                                .offset(x: sel.x)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                let a = Self.brushIndex(g.startLocation.x, step: step, n: days.count)
                                let b = Self.brushIndex(g.location.x, step: step, n: days.count)
                                withAnimation(DS.Motion.quick) {
                                    brush = days[min(a, b)].key ... days[max(a, b)].key
                                }
                            }
                    )
                }
                .frame(height: 26)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("区间刷选轨道")
                // 拖动是纯手势，VoiceOver 拿不到它 —— 指回 638 那条真正能操作的路，而不是假装有替代。
                .accessibilityHint("本轨道靠左右拖动选择区间，读屏用不了。要单日下钻请点上方趋势图")   // 638 本轨道靠左右拖动选择
                HStack(spacing: DS.Space.s) {
                    Text(brush.map { "刷选 " + $0.lowerBound + " ~ " + $0.upperBound }
                         ?? "在轨道上左右拖动选一段区间，下面的明细跟着换")   // 621 在轨道上左右拖动选一
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if brush != nil {
                        Button {
                            withAnimation(DS.Motion.quick) { brush = nil }
                        } label: {
                            Text("清除")
                                .vkFont(.caption, weight: .medium)
                                .padding(.horizontal, DS.Space.m)
                                .padding(.vertical, DS.Space.s)
                                .variantPlate(DS.Palette.surfaceAlt, .capsule, edge: DS.Palette.hairline)
                                .foregroundStyle(DS.Palette.text)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("清除刷选区间")
                    }
                }
            }
        }
    }

    /// 621 手指 x → 日索引。拖出轨道外夹回两端：手指越界是常态，不是错误。
    private static func brushIndex(_ x: CGFloat, step: CGFloat, n: Int) -> Int {
        guard step > 0, n > 0 else { return 0 }
        return min(max(0, Int(x / step)), n - 1)
    }
    private func brushContains(_ key: String) -> Bool {
        guard let b = brush else { return false }
        return key >= b.lowerBound && key <= b.upperBound
    }
    /// 刷选窗口在轨道上的像素矩形。key 是 yyyy-MM-dd ⇒ 字符串序就是时间序 (与全仓排序口径一致)；
    /// 区间整个落在窗口外 (换了窗口) 时返回 nil，轨道就不画框而不是画一个错的框。
    private func brushRect(days: [StatsKit.DailyPoint], step: CGFloat) -> (x: CGFloat, w: CGFloat)? {
        guard let b = brush,
              let lo = days.firstIndex(where: { $0.key >= b.lowerBound }),
              let hi = days.lastIndex(where: { $0.key <= b.upperBound }),
              hi >= lo else { return nil }
        return (CGFloat(lo) * step, CGFloat(hi - lo + 1) * step)
    }

    /// 621 的「下方明细列表」：数据范围 = 刷选区间 ∩ 当前窗口 (窗口外的日子自动夹掉)。
    /// 计数按**全量**算，列表只列最近 cap 条并把「还有多少条」写在同一行 ——
    /// 否则刷出一屏 40 行就会把「列了 40 条」读成「共 40 次」，那是假总数。
    /// 646: 窗口 ≥90 天这一档 (`m.isHourFolded`, 判据在 StatsKit 与那句文案同一个出处) 先把逐条日志折成
    /// (日, 时) 小时桶再上屏; 折不动 (桶数不比行数少) 就照旧逐条列, 那句"已折叠"也不出现 —— 文案只跟着数据走。
    /// 643: 621 明细的一份数据 —— 整宽 Section 与分栏侧列两条布局共用这一个出口。
    /// 里面那串 let (hit / openN / alarmN / cap / shown / buckets / detail) 逐字照改前, 取区间的判据仍只有
    /// `brush` 这一份状态; 行数、桶数、两条求和与折叠标志都是同一次算出来的同一份数, 两条布局各取一次。
    private struct BrushDetailData {
        let hitCount: Int
        let openN: Int
        let alarmN: Int
        let bucketCount: Int
        let rows: [(log: CachedLog, label: String, alarm: Bool)]
        let folded: Bool
        let isEmpty: Bool
    }

    private func brushData(_ m: StatsKit.StatModel, _ b: ClosedRange<String>) -> BrushDetailData {
        let hit = m.logsInWindow().filter { l in
            guard let d = StatsKit.dateOf(l) else { return false }
            let k = StatsKit.dayKey(d)
            return k >= b.lowerBound && k <= b.upperBound
                && (StatsKit.openTypes.contains(l.type) || StatsKit.alarmTypes.contains(l.type))
        }
        let openN = hit.reduce(0) { $0 + (StatsKit.openTypes.contains($1.type) ? 1 : 0) }
        let alarmN = hit.reduce(0) { $0 + (StatsKit.alarmTypes.contains($1.type) ? 1 : 0) }
        let cap = 40
        let shown = Array(hit.sorted { (StatsKit.dateOf($0) ?? .distantPast) > (StatsKit.dateOf($1) ?? .distantPast) }
            .prefix(cap))
        let buckets = m.isHourFolded ? StatsKit.hourBuckets(hit) : []
        let detail = brushDetail(buckets: buckets, shown: shown, cap: cap)
        return BrushDetailData(hitCount: hit.count, openN: openN, alarmN: alarmN, bucketCount: buckets.count,
                               rows: detail.rows, folded: detail.folded, isEmpty: hit.isEmpty)
    }

    /// 643: 621 明细的**一份**内容 (整宽 Section 与 643 分栏侧列都调这里 —— 行内跳转、折叠那句与空档那句同样一个出处)。
    /// 内容与改前逐字一致, 只有 `hit.count` / `buckets.count` / `detail.folded` / `rows` / `hit.isEmpty`
    /// 换成从同一份 BrushDetailData 上取的等价读数。
    @ViewBuilder
    private func brushDetailBody(_ m: StatsKit.StatModel, _ d: BrushDetailData) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("\(d.hitCount) 条 · 开门 \(d.openN) 次 · 告警 \(d.alarmN) 条"
                 + ((d.folded ? d.bucketCount : d.hitCount) > d.rows.count
                    ? " · 下面列最近 \(d.rows.count) " + (d.folded ? "桶" : "条") : ""))
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)
            if d.folded {
                Text("这一档窗口 ≥\(m.longWindowDays) 天: 逐条 \(d.hitCount) 条已按 (日, 时) 折成 \(d.bucketCount) 个小时桶")   // 646 这一档窗口
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(d.rows.enumerated()), id: \.offset) { _, r in
                Button {
                    app.pendingRecordKey = RecordOverlay.oid(mac: mac, rowKey: String(r.log.idxRaw))
                    app.requestRoute(.records)
                    dismiss()
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: r.alarm ? "diamond.fill" : "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(r.alarm ? DS.Palette.warn : DS.Palette.accent)
                            .accessibilityHidden(true)
                        Text(r.label)
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.textSub)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(d.folded ? "点按跳到该小时桶最近一条并高亮"   // 170 点按跳到该小时桶最近
                                            : "点按跳到记录页这条并高亮")   // 170 点按跳到记录页这条并
            }
            if d.isEmpty {
                Text("这段区间里没有开门或告警记录 —— 把轨道拖宽，或看上方趋势的空窗带")   // 610 这段区间里没有开门或
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }

    /// 621 明细的整宽那一档 (计数的全量口径与 646 折叠判据的说明在上面 brushData 那一段, 讲的是同一件事)。
    /// 643 分栏成立时这一档让位给侧列 —— 两条布局由 `wideSplitTrend` 同一个判据二选一, 同一段区间在同一帧只上一次屏。
    @ViewBuilder
    private func brushSection(_ m: StatsKit.StatModel) -> some View {
        if let b = brush, !wideSplitTrend {
            Section("「" + b.lowerBound + " ~ " + b.upperBound + "」区间明细") {   // 621 区间明细
                brushDetailBody(m, brushData(m, b))
                    .padding(.horizontal, DS.Space.gutter)
            }
        }
    }

    /// 643 分栏侧列: 621 区间明细搬到主图右边那一格 (容器的 2/5)。
    /// 列里那份内容调的还是 brushDetailBody 同一个出口 —— 行内跳转 (170 那条路由)、646 折叠那句、
    /// 空档那句、逐行 `.frame(minHeight: DS.Hit.min)` 的触达全都与整宽档共用, 这一档动的是容器。
    /// 整宽档由 Section 头说区间名, 侧列这一档把同一串字放在列顶, 说的还是那句「「起 ~ 止」区间明细 (621)」。
    @ViewBuilder
    private func brushDetailSide(_ m: StatsKit.StatModel, _ b: ClosedRange<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("「" + b.lowerBound + " ~ " + b.upperBound + "」区间明细")   // 621 区间明细
                .vkFont(.caption, weight: .semibold)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            brushDetailBody(m, brushData(m, b))
        }
    }

    /// 646 + 621: 把"折叠档的小时桶行"和"逐条档的原始行"汇成**同一种行** (样本日志 / 一行标签 / 是否带告警),
    /// 下面 ForEach 里的 HStack 因此只有一份 —— 同一件事写两遍是 956 那一族的教训。
    /// 桶行的样本 = 该桶**最近一条**真日志 ⇒ 点按仍落到记录页一个真实行上, 折叠不丢跳转 (170)。
    /// 只有真少一些行时才折 (`buckets.count < shown.count`): 折不动 (整段区间只落在一两个小时里) 就照旧逐条列,
    /// 那句"已折叠"也不出现 —— 为了一个编号把行数说小, 是本仓反复拒绝的那种假。
    /// `buckets` 为空 = 这一档不折 (`m.isHourFolded` 为假时传进来的就是空表)。
    private func brushDetail(buckets: [StatsKit.HourBucket], shown: [CachedLog], cap: Int)
        -> (rows: [(log: CachedLog, label: String, alarm: Bool)], folded: Bool) {
        if buckets.count > 0 && buckets.count < shown.count {
            return (buckets.prefix(cap).map { b in
                (b.sample,
                 "\(b.day) \(b.hour) 时 · 开门 \(b.opens) 次" + (b.alarms > 0 ? " · 告警 \(b.alarms) 条" : ""),
                 b.alarms > 0)
            }, true)
        }
        return (shown.map { l in
            (l, l.lockTimeStr.isEmpty ? l.typeName : l.lockTimeStr + " · " + l.typeName,
             StatsKit.alarmTypes.contains(l.type))
        }, false)
    }

    // ---------- 600 24 小时分布柱 (点柱下钻) / 614 正常与告警分组柱 / 633 轴刻度取整 / 644 逐点朗读 ----------
    @ViewBuilder
    private func hourSection(_ m: StatsKit.StatModel) -> some View {
        let peak = m.hourStats.max(by: { $0.opens < $1.opens })
        // 633: 步长按窗口内最大值挑整数档 (5/10/20/50)。"次数"是整数指标，
        // 让它出现 12.5 这种刻度是**假精度** —— 读数的人会以为中间真有个半次。
        let topVal = m.hourStats.reduce(0) { max($0, max($1.opens, $1.alarms)) }
        let step = topVal <= 20 ? 5 : (topVal <= 60 ? 10 : (topVal <= 200 ? 20 : 50))
        Section("24 小时分布 · 点柱下钻") {   // 600 小时分布
            Chart(m.hourStats) { s in
                // 614: 同一小时内"正常开门"与"告警"各自成柱**并排**。
                // 原写法只有两条 BarMark 画在同一个 x 上、谁都没带 `position(by:)`, 而注释当时写着
                // "Charts 按标记顺序自动并排"—— 没有这条规则: 同一格的两条柱是**叠着画**的, 后一条把前一条盖住,
                // 深夜告警高发那种形状正好被压在"开门"那根柱底下读不出来 (原句要的正是这个形状)。
                // 现在两条各带自己的系列标签去做 dodging; 颜色仍写死在 DS 令牌上 (不挂 foregroundStyle(by:),
                // 免得 Charts 换掉 631 那一族深浅档自动色), 名字由下面那行图例给出。
                BarMark(x: .value("时", s.hour), y: .value("开门", s.opens))
                    .position(by: .value("系列", "开门"))
                    .foregroundStyle(DS.Palette.accent)
                    .accessibilityLabel("\(s.hour) 时")
                    .accessibilityValue("开门 \(s.opens) 次")
                BarMark(x: .value("时", s.hour), y: .value("告警", s.alarms))
                    .position(by: .value("系列", "告警"))
                    .foregroundStyle(DS.Palette.danger)
                    .accessibilityValue("告警 \(s.alarms) 次")
            }
            .chartYScale(domain: 0...(topVal + step))
            .chartXAxis {
                // 658: 时段词轴标 — 在 8 个时段的首小时放"清晨/上午/午前/午间/下午/傍晚/晚间/深夜",
                // 替代裸小时数 (词与词之间都是真实时段边界, 0/5/9/11/13/17/19/23 取自 TimeWord 同一份词表)
                AxisMarks(values: [0, 5, 9, 11, 13, 17, 19, 23]) { v in
                    if let h = v.as(Int16.self) {
                        AxisValueLabel { Text(TimeWord.word(Int(h))) }
                        AxisGridLine().foregroundStyle(DS.Palette.hairline)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .stride(by: Double(step))) { _ in
                    AxisValueLabel().foregroundStyle(DS.Palette.textSub)
                    AxisGridLine().foregroundStyle(DS.Palette.hairline.opacity(0.5))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            let origin = plotRect(proxy, geo).origin
                            if let h = proxy.value(atX: loc.x - origin.x, as: Int16.self), h >= 0, h < 24 {
                                withAnimation(DS.Motion.quick) { selHour = h }
                            }
                        }
                        .accessibilityLabel("小时分布图, 点按某时段查看该时段记录")
                }
            }
            .frame(height: 180)
            .padding(.horizontal, DS.Space.gutter)
            // 614 并排之后两根柱各自的颜色要有名字: 这一行图例与本文件 601 那行共用 legendRow 一个出口
            legendRow(labels: [("开门", DS.Palette.accent, false), ("告警", DS.Palette.danger, false)])
            // 644: 逐柱点读之外再给一句整段摘要 —— 听柱形图要一柱一柱点，
            // "峰值在哪一小时"是听读者最想要的那一个结论，不该让他自己点数。
            if let p = peak {
                Text("峰值在 \(TimeWord.word(Int(p.hour))) \(p.hour) 时，开门 \(p.opens) 次；逐柱可用 VoiceOver 点读")   // 644 峰值在
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 13 周柱状图 (近 7 天逐日开门柱, Apple Health 式) ----------
    /// 与 616 星期几分布刻意分开: 这张看的是"具体哪七天" (有日期，能对上某件事)，
    /// 那张把量按周一~周日聚合 (看的是规律而不是日子)。两张图共用一个 Section 壳、不共用数据。
    @ViewBuilder
    private func weekBarsSection(_ m: StatsKit.StatModel) -> some View {
        let barDays = m.recentBarDays          // 13 固定 7 天 (不跟 678 周族档), 标题那句与 suffix 的参数同一个出处
        let days = Array(m.dailyPoints.suffix(barDays))
        if days.count >= 2 {
            Section("近 \(barDays) 天 · 逐日柱") {   // 13 逐日柱
                Chart(days) { p in
                    BarMark(x: .value("日", p.day, unit: .day), y: .value("开门", p.opens))
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityLabel(p.day.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue("开门 \(p.opens) 次")
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine().foregroundStyle(DS.Palette.hairline.opacity(0.5))
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .frame(height: 120)
                .padding(.horizontal, DS.Space.gutter)
                Text("只统计本机读到的日子；少于两天时整节不出现 —— 一根柱子谈不上「形状」。")   // 13 只统计本机读到的日子
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 14 月度热力格 (GitHub 形态) ----------
    /// 逐日开门次数 → 7 行 × 周列的灰阶格。
    /// 数据源复用 m.dailyPoints (StatsKit.swift 逐日补齐) —— 不新增聚合、不新增表。
    /// 窗口小就画小 (7 天档只有一周格子), 如实画少, 不用相邻日凑数。
    @ViewBuilder
    private func heatmapSection(_ m: StatsKit.StatModel) -> some View {
        let days = m.dailyPoints
        if !days.isEmpty {
            Section("月度热力格") {   // 14 月度热力格
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(10), spacing: 2), count: 7),
                              spacing: 2) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                            let lv = min(4, d.opens)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(lv == 0 ? DS.Palette.surfaceAlt
                                              : DS.Palette.accent.opacity(0.2 + Double(lv) * 0.2))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .padding(.vertical, DS.Space.xxs)
                }
                .accessibilityLabel("近 \(days.count) 天逐日开门热力格, 颜色越深次数越多")
            }
        }
    }

    // ---------- 608 假期最后 3 天逐时开门柱 (系统电池用量图那一形态) ----------
    /// 一天一张小图上下并排，而不是把 24×3 根柱子挤进同一根轴：手机宽度下放得下 24 根，
    /// 放不下"三天各 24 根还分得清"。这里要看的是"初四比初二晚几点开始有人回家"，逐时形状比高低差更重要。
    /// 假日本身只认本机已收录的公告 (holiday-cn 缓存 + 内置表, 走 RecordSearch.holidayName 一个出口)；
    /// 没收录时整节不出现 —— 猜哪天放假是把推断当事实。
    @ViewBuilder
    private func holidayBarsSection(_ m: StatsKit.StatModel) -> some View {
        let days = m.holidayTailDays
        if !days.isEmpty {
            Section {
                ForEach(days) { d in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.xs) {
                            Text(String(d.day.suffix(5)) + (d.name.isEmpty ? "" : " · " + d.name))
                                .vkFont(.caption, weight: .semibold)
                                .foregroundStyle(DS.Palette.text)
                            Text("共 \(d.total) 次 · 峰值 \(TimeWord.word(Int(d.peakHour))) \(d.peakHour) 时")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                            Spacer(minLength: 0)
                        }
                        Chart(d.hours) { h in
                            BarMark(x: .value("时", h.hour), y: .value("开门", h.opens))
                                .foregroundStyle(DS.Palette.accent)
                                .accessibilityLabel("\(h.hour) 时")
                                .accessibilityValue("开门 \(h.opens) 次")
                        }
                        .chartXAxis {
                            // 658: 与 24 小时分布图共用同一组时段词轴标 (两处小时图一个出口, 不各写一份)
                            AxisMarks(values: [0, 5, 9, 11, 13, 17, 19, 23]) { v in
                                if let hh = v.as(Int16.self) {
                                    AxisValueLabel { Text(TimeWord.word(Int(hh))) }
                                    AxisGridLine().foregroundStyle(DS.Palette.hairline)
                                }
                            }
                        }
                        // 刻意不写 .chartYAxis(.hidden)：那是本文件里没用过的形式，而按 docs/API-VERIFY.md 的
                        // 手法撞不到它的官方页 (Charts 那棵树的 slug 规律没摸清)。撞不到 ≠ 不存在，
                        // 但在一台连编译器都没有的机器上，"不确定就别写"是唯一稳的取向 —— 小数轴留着反而更有信息量。
                        .frame(height: 62)
                    }
                    .accessibilityElement(children: .contain)
                }
            } header: {
                Text("假期最后 \(days.count) 天 · 逐时开门")   // 608 假期最后
            } footer: {
                Text("放假日按本机已收录的公告判定；峰值只到「时」这一档 (日志只到分)。"
                     + "只统计窗口内读到的日志 —— 没读到的日子不算没开门。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 602 作息雷达 (早/午/晚/深夜四轴开门密度) ----------
    /// Canvas 只画几何 (Path + 两圈底格)，**段名与次数写在图下方的标签行**：
    /// 本仓没有 `ctx.draw(Text…)` 的先例，而雷达没有标签就是五个点连成的一个形状 —— 让人猜哪根轴是深夜，
    /// 正是"看起来在工作其实是缺省值"的那类显示。标签行同时是 VoiceOver 的读数来源。
    /// 只在窗口内真有 ≥5 次开门时出现 (622 护栏的另一面)：三根 0 轴的雷达是个空圈，
    /// 空圈会被读成"作息很规律"，而那其实是没数据。
    @ViewBuilder
    private func radarSection(_ m: StatsKit.StatModel) -> some View {
        let parts = m.dayparts
        if m.daypartTotal >= 5 {
            Section {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = max(20, min(size.width, size.height) / 2 - 12)
                    let maxV = max(1, parts.map { $0.opens }.max() ?? 1)
                    func vertex(_ i: Int, _ k: CGFloat) -> CGPoint {
                        let ang = -Double.pi / 2 + Double(i) * Double.pi / 2
                        return CGPoint(x: c.x + cos(ang) * r * k, y: c.y + sin(ang) * r * k)
                    }
                    for k in [0.5, 1.0] {
                        var ring = Path()
                        for i in 0..<4 {
                            let p = vertex(i, CGFloat(k))
                            if i == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
                        }
                        ring.closeSubpath()
                        ctx.stroke(ring, with: .color(DS.Palette.hairline), lineWidth: 0.8)
                    }
                    var poly = Path()
                    for (i, p) in parts.enumerated() {
                        let v = CGFloat(p.opens) / CGFloat(maxV)
                        let pt = vertex(i, max(0.02, v))
                        if i == 0 { poly.move(to: pt) } else { poly.addLine(to: pt) }
                    }
                    poly.closeSubpath()
                    ctx.fill(poly, with: .color(DS.Palette.accent.opacity(0.22)))
                    ctx.stroke(poly, with: .color(DS.Palette.accent), lineWidth: 2)
                }
                .frame(height: 168)
                .padding(.horizontal, DS.Space.gutter)
                .accessibilityHidden(true)   // 图形本身不给 VoiceOver 念，念下面那行标签
                HStack(spacing: DS.Space.xs) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(p.name).vkFont(.caption, weight: .semibold).foregroundStyle(DS.Palette.text)
                            Text(p.span + " · " + String(p.opens) + " 次")
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, DS.Space.xs)
                        .variantPlate(DS.Palette.surfaceAlt, .control)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("作息雷达：" + parts.map { $0.name + " " + $0.span + " 时 " + String($0.opens) + " 次" }.joined(separator: "，"))
            } header: {
                Text("作息雷达 · 早/午/晚/深夜")   // 602 作息雷达
            } footer: {
                // 676: 深夜轴跟随「夜间时段」设置 (与 572 深夜预设同一份配置), 不再写死 22–04 ——
                // 页脚原先钉着一句"深夜算 22:00–04:59", 用户把配置改成 22–6 后它就成了假话。
                Text("每根轴按最忙那一段归一 (所以外圈永远顶格)，段边界写在标签里：深夜跟随「夜间时段」设置"
                     + " (当前 \(String(format: "%02d:00", RecordSearch.nightFrom)) 起、\(String(format: "%02d:00", RecordSearch.nightTo)) 前)。"
                     + "只统计本机读到的窗口 —— 没读过的时段不算没开门。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 605 告警散点阵 (近 90 天 × 告警子类型) ----------
    /// 与 627 OTP 散点同一种点图，但纵轴是**类型**不是时刻: 看的是"哪几天集中爆发哪一类"。
    /// 空的时候整节不出现 (没有告警是好消息，不该用一张空网格占住页面，也不该写"暂无数据"占位)。
    @ViewBuilder
    private func alarmScatterSection(_ m: StatsKit.StatModel) -> some View {
        let pts = m.alarmScatter
        if !pts.isEmpty {
            Section("告警散点 · 近 \(m.alarmScatterDays) 天") {   // 605 告警散点
                Chart(pts) { p in
                    PointMark(
                        x: .value("日", p.day, unit: .day),
                        y: .value("子类型", p.typeName)
                    )
                    .foregroundStyle(by: .value("子类型", p.typeName))
                    .symbolSize(48)
                    .accessibilityLabel(p.typeName)
                    .accessibilityValue(p.day.formatted(date: .abbreviated, time: .omitted))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine().foregroundStyle(DS.Palette.hairline.opacity(0.5))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 190)
                .padding(.horizontal, DS.Space.gutter)
                Text("\(pts.count) 条告警逐点上屏；纵轴是告警子类型，横向密集处即集中爆发的日子。")   // 605 条告警逐点上屏
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 601 本月上月同比 + 604 成员多线 (632 图例点选排除) ----------
    @ViewBuilder
    private func monthSection(_ m: StatsKit.StatModel) -> some View {
        let mp = m.monthPair
        Section("本月对比") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Chart {
                    ForEach(mp.thisMonth) { p in
                        LineMark(x: .value("日", String(p.key.suffix(2))), y: .value("本月", p.opens))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    if mp.complete {
                        ForEach(mp.lastMonth) { p in
                            LineMark(x: .value("日", String(p.key.suffix(2))), y: .value("上月", p.opens))
                                .foregroundStyle(DS.Palette.textSub)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 160)
                legendRow(labels: mp.complete
                          ? [("本月 实线", DS.Palette.accent, false), ("上月 虚线", DS.Palette.textSub, false)]
                          : [("本月 实线", DS.Palette.accent, false)])
                HStack(spacing: DS.Space.m) {
                    Text("本月 \(mp.thisCount) 次" + (mp.complete ? " · 上月 \(mp.lastCount) 次" : ""))
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                    if !mp.complete {
                        Text("上月记录未积累, 缓存最早从 " + (m.earliest.map { StatsKit.dayKey($0) } ?? "—") + " 起, 上月曲线暂缺")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                // 604 成员多线: 各成员近 N 天可证明归属的逐日次数, 点图例临时隐藏。
                // N 只从本视图 `week` 取一份 (678/604) —— 界面用语、多线图读屏标签、图例查询与 799 周小结
                // 以前各写一遍 7, 改档就会漂成"图上写 7 天、数据其实 14 天"。
                // 604 起 week 有赋值方了 (下面 weekChips 双档); 678 未拍板, 默认值仍 7 不动。
                if !hiddenMemberIds.isEmpty || m.memberCounts(days: week).count > 0 {
                    weekChips
                    memberLines(m)
                    legendChips(m)
                    labelModeChips     // 640 数值标签三档: 避让 / 仅最大值 / 不标
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }
    @State private var hiddenMembers: Set<String> = []
    private var hiddenMemberIds: Set<String> { hiddenMembers }

    /// 604 显式双档: 成员多线窗口 7/30 天。此前 `week` 无赋值方、恒 7 且无入口;
    /// 678「默认本周 vs 默认 30 天」未拍板 —— 只加入口, 默认值仍 7。换档走 build(),
    /// `m.weekWindowDays` 随模型同步 (799 周小结读的就是它), 不造第二套窗口状态。
    private var weekChips: some View {
        HStack(spacing: DS.Space.s) {
            Text("成员窗口")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            ForEach([7, 30], id: \.self) { w in
                let on = (week == w)
                Button {
                    withAnimation(DS.Motion.standard) { week = w }
                    build()
                } label: {
                    Text(String(w) + " 天")
                        .vkFont(.caption)
                        .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.text)
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, DS.Space.xs + 2)
                        .background(on ? DS.Palette.accent.opacity(0.22) : DS.Palette.surfaceAlt, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? DS.Palette.accent : DS.Palette.hairline, lineWidth: 0.5))
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("成员窗口 " + String(w) + " 天")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

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
        let days = week      // 604/678 同一份读数: 逐日桶的个数与下面查询的天数都是本视图 week (build() 后 m.weekWindowDays 同值)
        let members = m.memberDaily(days: days)
        let now = WeekCal.gregorian.startOfDay(for: Date())
        let totalDays = (0..<days).map { off in
            RecordSearch.dayKeyOf(WeekCal.gregorian.date(byAdding: .day, value: -off, to: now)!)
        }
        return members.enumerated().map { i, rec in
            let pts = totalDays.compactMap { dk -> MemberSeries.Point? in
                RecordSearch.dateFromKey(dk).map { MemberSeries.Point(day: $0, opens: rec.perDay[dk] ?? 0) }
            }
            return MemberSeries(id: rec.id, name: rec.name, color: StatsKit.StatModel.memberColor(i),
                                points: pts.filter { $0.opens > 0 })
        }
    }

    // ---------- 640 多系列数值标签: 末点标数 + 重叠自动错开 ----------
    private struct SeriesEnd {
        let id: String
        let color: Color
        let day: Date
        let opens: Int
    }
    private struct PlacedLabel: Identifiable {
        let id: String
        let text: String
        let color: Color
        let x: CGFloat
        let y: CGFloat
    }
    /// 640 的三档只在这一个地方定义, 落盘只有一个 key (kf_stat_labels)。
    /// 640 的三档: Identifiable 结构体 (元组不能遵循 Identifiable, 单参 ForEach 用不了; 与 key path 无关)。
    private struct LabelMode: Identifiable {
        let tag: Int
        let name: String
        var id: Int { tag }
    }
    private static let labelModes: [LabelMode] = [LabelMode(tag: 0, name: "避让"), LabelMode(tag: 1, name: "仅最大值"), LabelMode(tag: 2, name: "不标")]

    // @ViewBuilder 不是装饰: 体内先一条 let 绑定点数组, 再接一条 Chart{}.chartOverlay{}.frame(...) 的尾随表达式,
    // 已是多语句 body 且没有 return —— 少了这个属性编译器报 "function declares an opaque return type,
    // but has no return statements" (swiftshape R1b 现在盯这个)。
    /// 628 曲线起点旗标 —— 2026-10-13 run 63 从 memberLines 的内联 Chart 内容里抽出:
    /// 该表达式报 type-check 超时。(Chart 内容用 @ChartContentBuilder, 不是 @ViewBuilder)
    @ChartContentBuilder
    private func flagMark(_ s: MemberSeries, _ first: MemberSeries.Point, weekWindowDays: Int) -> some ChartContent {
        PointMark(x: .value("日", first.day), y: .value(s.name, first.opens))
            .foregroundStyle(s.color)
            .symbol { Image(systemName: "flag.fill").font(.system(size: 7)) }
            .opacity(hiddenMembers.contains(s.id) ? 0 : 1)
            .accessibilityLabel(s.name + " 近 " + String(weekWindowDays) + " 天首次记录")
            .accessibilityValue(RecordSearch.dayKeyOf(first.day))
    }

    /// 626/628 长期密码用量行 (从 body 内联的 ForEach 里抽出: 该表达式报 type-check 超时)
    @ViewBuilder
    private func pwdUsageRow(_ p: StatsKit.PwdUse) -> some View {
        // 628 跳转: 该密码归属的成员在成员表里能证明存在时, 整行可点 → 记录页按该成员过滤
        // (582/612 同一条 pendingRecordsMember 路由; 不造"跳到首条"的第二套深链 —— 落点就是该成员
        // 全部记录, 排序在记录页自己管)。归属不明 (owner 空/查无此人) 时保持纯文字, 不挂死按钮。
        let jumpId = (p.owner.isEmpty || DB.member(p.owner) == nil) ? nil : p.owner
        // 2026-10-13 run 68: 颜色/条宽/a11y 串先算好 —— 内联时整个 pwdUsageRow 报 type-check 超时。
        let barColor: Color = p.ratio >= 0.8 ? DS.Palette.warn : DS.Palette.accent
        let barWidth = max(2, p.ratio * 120)
        let a11y = "密码 " + p.name + " 约使用 " + String(p.approxUses) + " 次, 用量 " + String(Int(p.ratio * 100)) + "%"
            + (p.firstUseDay.map { ", 首用 " + $0 } ?? "")
            + (jumpId == nil ? "" : "; 点按到记录页按该成员筛选")   // 628 点按到记录页按该成员
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Space.xs) {
                Text(p.name)
                    .vkFont(.footnote, weight: .medium)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                if let f = p.firstUseDay {
                    Text("首用 " + f)   // 628 首用
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.accentText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("约 " + String(p.approxUses) + " 次")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            // 用量比条: 已用/上限, 接近上限转橙
            Capsule()
                .fill(barColor)
                .frame(width: barWidth)
                .frame(height: 4)
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        .onTapGesture {
            if let jid = jumpId {
                app.pendingRecordsMember = jid
                app.requestRoute(.records)
                dismiss()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(jumpId == nil ? [] : .isButton)
    }

    /// 612/624 成员水平条的一行 (从 body 内联的 ForEach 里抽出: 该表达式报 type-check 超时)
    @ViewBuilder
    private func memberBarRow(id: String, name: String, approx: Int, index: Int,
                              barDays: Int, maxApprox: Int) -> some View {
        // 2026-10-13 run 68: a11y 串先算好 (内联时 memberBarRow 报 type-check 超时)
        let a11y = "成员 " + name + ", 近 " + String(barDays) + " 天约 " + String(approx) + " 次; 点按到记录页按该成员筛选"   // 582 点按到记录页按该成员
        Button {
            // 582 图表下钻: 成员条 → 记录 Tab 按该成员过滤 (台账推断, 落点走可证明口径)。
            // 记录页的 landMember() 会把 sel 与 filters.member 一起写、再走同一条 applyFilter 链并消费后清空旗标,
            // 这里只写 pendingRecordsMember 一个键 (两处都写 sel 会变成"谁后跑谁赢")。
            app.pendingRecordsMember = id
            app.requestRoute(.records)
            dismiss()
        } label: {
            memberBarLabel(name: name, approx: approx, index: index, maxApprox: maxApprox)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(a11y)
    }

    /// 成员条宽度 (抽出: 内联那条 `max(2, CGFloat(approx) / CGFloat(max(maxApprox, 1)) * 120)`
    /// 参与把 memberBarLabel 拖进 type-check 超时)
    private func barWidth(_ approx: Int, _ maxApprox: Int) -> CGFloat {
        max(2, CGFloat(approx) / CGFloat(max(maxApprox, 1)) * 120)
    }

    /// 成员条行的标签 (从 memberBarRow 里再抽一层: 该表达式报 type-check 超时)
    private func memberBarLabel(name: String, approx: Int, index: Int, maxApprox: Int) -> some View {
        HStack(spacing: DS.Space.s) {
            Text(name)
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
            Capsule()
                .fill(StatsKit.StatModel.memberColor(index))
                .frame(width: barWidth(approx, maxApprox))
            Text("约 \(approx) 次")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func memberLines(_ m: StatsKit.StatModel) -> some View {
        // 628: 折线与起点插旗共用这一份 memberSeries —— Attribution 全链不便宜, 不各算一遍
        let series = memberSeries(m)
        Chart {
            ForEach(series, id: \.id) { s in
                ForEach(s.points, id: \.id) { p in
                    LineMark(x: .value("日", p.day), y: .value(s.name, p.opens))
                        .foregroundStyle(s.color)
                        .opacity(hiddenMembers.contains(s.id) ? 0 : 1)
                }
                // 628 曲线起点插旗: 每成员**窗口内**第一枚可证明归属点插小旗, 读屏报"窗内首次记录 日期"。
                // 旗子不挂点按 —— "跳该成员首条记录"那条路在记录页的按成员过滤 (582 pendingRecordsMember),
                // 这里只做标记, 不承诺旗能跳 (曾写成"落在同一条路由上", 读的人会以为旗可点)。
                if let first = s.points.min(by: { $0.day < $1.day }) {
                    flagMark(s, first, weekWindowDays: m.weekWindowDays)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ForEach(Self.placedLabels(seriesEnds(m), proxy: proxy, geo: geo, mode: labelMode)) { t in
                    Text(t.text)
                        .vkFont(.caption2, weight: .semibold)
                        .foregroundStyle(t.color)
                        .position(x: t.x, y: t.y)
                        .accessibilityHidden(true)   // 数字把图例和曲线已经说过的话再说一遍
                }
            }
        }
        .frame(height: 150)
        .accessibilityLabel("成员近 \(week) 天逐日开门多线图")
    }

    /// 可见系列的末点。隐藏系列整条都不画, 它的标签也不该留下 (632 的点选排除管这个)。
    private func seriesEnds(_ m: StatsKit.StatModel) -> [SeriesEnd] {
        memberSeries(m).compactMap { s in
            guard !hiddenMembers.contains(s.id), let last = s.points.max(by: { $0.day < $1.day }) else { return nil }
            return SeriesEnd(id: s.id, color: s.color, day: last.day, opens: last.opens)
        }
    }

    /// 640 的核心: 先把每枚标签换算成**像素**，再按真实行高往下错开重叠的那些。
    /// 为什么不按数据单位判重叠: y 轴比例尺是 Charts 自己定的，"差 1 次"在峰值 3 和峰值 30 的图里
    /// 是两种距离 —— 按数据单位写死的避让，换个窗口就翻脸。
    /// proxy 拿不到比例尺时返回空表：这一帧没标签，比叠成一团糊字诚实。
    private static func placedLabels(_ ends: [SeriesEnd], proxy: ChartProxy, geo: GeometryProxy, mode: Int) -> [PlacedLabel] {
        if mode == 2 { return [] }
        let plot = plotRect(proxy, geo)
        var cands: [(id: String, text: String, color: Color, x: CGFloat, y: CGFloat)] = []
        for e in ends {
            guard let px = proxy.position(forX: e.day), let py = proxy.position(forY: e.opens) else { continue }
            cands.append((e.id, String(e.opens), e.color, plot.minX + px, plot.minY + py))
        }
        if mode == 1 {
            // 只标最大那一枚: 峰值一个数就够定位"今天谁最多"，其余系列读图例胶囊 (632) 上的约数
            let top = ends.max { $0.opens < $1.opens }?.id
            cands = cands.filter { $0.id == top }
        }
        let minGap: CGFloat = 13        // caption2 一行约 11pt + 2pt 呼吸
        let labelW: CGFloat = 24        // 一枚数字标签的估宽 (最多三位数 + 留白)。估错了只会多翻/少翻一边，不会标错数
        var out: [PlacedLabel] = []
        for c in cands.sorted(by: { $0.y < $1.y }) {
            let y = out.isEmpty ? c.y : max(c.y, out[out.count - 1].y + minGap)
            let right = c.x + 6
            let x = (right + labelW / 2 > plot.maxX) ? c.x - 6 - labelW / 2 : right + labelW / 2
            out.append(PlacedLabel(id: c.id, text: c.text, color: c.color, x: x, y: y))
        }
        // 一路往下错开可能顶出底边: 整串一起往上收，收不进门就贴着底边排 (宁可贴边也不叠字)
        let over = (out.last?.y ?? 0) - (plot.maxY - 9)
        if over > 0 {
            out = out.map { PlacedLabel(id: $0.id, text: $0.text, color: $0.color, x: $0.x, y: max(plot.minY + 9, $0.y - over)) }
        }
        return out
    }

    /// 640 的开关本体 (三档只此一处，别处不再藏第二个入口)
    @ViewBuilder
    private var labelModeChips: some View {
        HStack(spacing: DS.Space.s) {
            Text("数值标签")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            ForEach(Self.labelModes) { mo in
                let on = (labelMode == mo.tag)
                Button {
                    labelMode = mo.tag
                    DB.store.set("kf_stat_labels", mo.tag)
                } label: {
                    Text(mo.name)
                        .vkFont(.caption)
                        .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.text)
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, DS.Space.xs + 2)
                        .background(on ? DS.Palette.accent.opacity(0.22) : DS.Palette.surfaceAlt, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? DS.Palette.accent : DS.Palette.hairline, lineWidth: 0.5))
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("数值标签 " + mo.name)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder
    private func legendChips(_ m: StatsKit.StatModel) -> some View {
        // 632 图例胶囊的"约 N"与上方多线 (604) 同一份天数 (本视图 week)、同一次归属推断 —— 两处各算一遍就会各说一套
        let members = m.memberCounts(days: week)
        if !members.isEmpty {
            // 645 特大字号下图例改纵向堆叠: 横滑条在字号 ≥1.5 档 (AXFlags.axStackLayout) 下会把每枚胶囊
            // 撑到接近半屏宽，一屏只看得见一个 —— 那时"把成员列全"才是可扫读的。
            // 两种容器共用同一个 chips()，图例的逻辑只有一份 (它本来就在 Button 里，不在容器里)。
            if AXFlags.axStackLayout {
                VStack(alignment: .leading, spacing: DS.Space.xs) { chips(members) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s) { chips(members) }
                        .padding(.vertical, DS.Space.xxs)
                }
            }
        }
    }

    /// 632 图例点选排除的**单枚胶囊** (645 的两种容器共用这里，避免改一处忘另一处)
    @ViewBuilder
    private func chips(_ members: [(id: String, name: String, approx: Int)]) -> some View {
        ForEach(Array(members.enumerated()), id: \.offset) { i, rec in
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
                        .vkFont(.caption)
                        .foregroundStyle(off ? DS.Palette.textSub : DS.Palette.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs + 2)
                .variantPlate(DS.Palette.surfaceAlt, .capsule, edge: DS.Palette.hairline)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("图例 \(rec.name), 已" + (off ? "隐藏" : "显示"))
            .accessibilityAddTraits(off ? .isSelected : [])
        }
    }
    private func legendRow(labels: [(String, Color, Bool)]) -> some View {
        HStack(spacing: DS.Space.m) {
            ForEach(labels.indices, id: \.self) { i in
                Label {
                    Text(labels[i].0)
                        .vkFont(.caption2)
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
    private func cumulativeSection(_ m: StatsKit.StatModel) -> some View {
        Section("累计开门") {   // 603 累计开门
            let pts = m.dailyPoints
            var cum = 0
            let rows = pts.map { p in
                cum += p.opens
                return ("c" + p.key, p.day, cum)
            }
            let weekBreaks = pts.filter { WeekCal.gregorian.component(.weekday, from: $0.day) == 2 }.map { $0.day }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Chart {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
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
                Text("窗口累计 \(m.opensTotal) 次 · 虚线为周一分割, 看增长节奏")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    // 2026-10-14 布局审计 R2: 估宽 428pt > 343pt, 而 lineLimit(1) 切掉的正好是后半句
                    // "虚线为周一分割" —— 图上那条虚线就没有解释了。允许两行。
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    // ---------- 609/629 临时码甘特 + 核销率 ----------
    @ViewBuilder
    private func ganttSection(_ m: StatsKit.StatModel) -> some View {
        let g = m.gantt
        if !g.isEmpty {
            Section("临时码核销") {   // 609 临时码甘特   // 629 核销率
                VStack(spacing: DS.Space.s) {
                    ForEach(g) { t in
                        let rate = t.availDays > 0 ? Double(t.usedDays) / Double(t.availDays) : 0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: DS.Space.xs) {
                                Text(t.name)
                                    .vkFont(.footnote, weight: .medium)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                if !t.owner.isEmpty {
                                    Text(t.owner)
                                        .vkFont(.caption2)
                                        .foregroundStyle(DS.Palette.accentText)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                // 629: 已过期那侧同样给核销率
                                Text((t.expired ? "已过期 · " : "") + "核销 " + String(Int(rate * 100)) + "% (\(t.usedDays)/\(t.availDays) 天)")
                                    .vkFont(.caption2)
                                    .foregroundStyle(t.expired ? DS.Palette.danger : DS.Palette.textSub)
                                    .lineLimit(1)
                            }
                            ganttBar(t)
                            // 629: 核销率比率条 (过期转灰, ≥0.8 转橙)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(DS.Palette.surfaceAlt)
                                    Capsule()
                                        .fill(t.expired ? DS.Palette.textSub.opacity(0.6) : (rate >= 0.8 ? DS.Palette.warn : DS.Palette.ok))
                                        .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, rate)))))
                                }
                            }
                            .frame(height: 4)
                            .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("临时码 \(t.name)" + (t.expired ? " 已过期" : "") + " 核销 \(t.usedDays)/\(t.availDays) 天, 约 \(Int(rate * 100))%")
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
        let offset = { (d: Date) in
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
                ForEach(Array(t.ticks.enumerated()), id: \.offset) { _, d in
                    Circle()
                        .fill(DS.Palette.ok)
                        .frame(width: 5, height: 5)
                        .offset(x: max(0, min(w - 5, w * offset(d) - 2.5)), y: 0)
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

    // ---------- 构成 (611 堆叠条 / 612 成员条 / 615 帕累托 / 616 周几 / 619 凭证类榜 / 613+620 告警) ----------
    @ViewBuilder
    private func compositionSection(_ m: StatsKit.StatModel) -> some View {
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
                // @layout-allow VK豁免 刻度点: 刻度/条，不是容器
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
                                Text((StatsKit.StatModel.kindWords()[k] ?? k) + " " + StatsKit.StatModel.compact(c))
                                    .vkFont(.caption)
                                    .foregroundStyle(off ? DS.Palette.textSub : DS.Palette.text)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, DS.Space.s)
                            .padding(.vertical, DS.Space.xs + 2)
                            .variantPlate(DS.Palette.surfaceAlt, .capsule, edge: DS.Palette.hairline)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("图例 " + (StatsKit.StatModel.kindWords()[k] ?? k) + ", 已" + (off ? "隐藏" : "显示"))
                    }
                    Spacer(minLength: 0)
                }
                // 615 帕累托: 柱 = 该类**占比 %**, 线 = **累计占比 %** —— 一根 y 轴一个单位。
                // 原来柱画的是"次数", 却与累计线共用 chartYScale(0...100): 满 100 次那一档柱子被轴裁掉,
                // 画出来的高度就不再是它自己的次数了。次数没丢 —— 它在下行 619 那排里逐类给数字。
                // 口径也钉死: 这里折的是**凭证类** (fp/pwd/temp/key 四类), 不是逐条凭证 (锁端不给逐凭证次数, CAPABILITY §3)。
                let pareto = m.pareto
                if !pareto.isEmpty {
                    Chart {
                        ForEach(Array(pareto.enumerated()), id: \.offset) { _, p in
                            BarMark(x: .value("类型", p.label), y: .value("占比", p.pct))
                                .foregroundStyle(StatsKit.StatModel.kindColor(p.kind))
                                .accessibilityLabel(p.label)
                                .accessibilityValue("占比 \(Int(p.pct))%, 共 \(p.count) 次")
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
                    // 旧句写的是 `prefix { $0.cumPct <= 80 }.count` —— 那是"累计**还没**到 80% 的类数",
                    // 跨过 80% 的那一类被漏计: 60/85/95/100 四档只会数出 1, 界面就说"前 1 类承载 80%",
                    // 而那一类其实只有 60%。现在数够线的那一类, 并把**真实累计**一起念出来 (不拿 80 这个整数档冒充实际值)。
                    if let cov = m.paretoCover {
                        Text("帕累托: 前 \(cov.kinds) 类累计 \(Int(cov.cumPct))% 开门 (折到凭证类, 类内不分条)")   // 615 开门
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            // 2026-10-14 布局审计 R2: 这条最长 (估宽 599pt vs 343pt)，lineLimit(1) 会把
                            // "折到凭证类, 类内不分条"整个口径切掉 —— 那正是这句话存在的理由 (数的是类不是条)。
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 616 周几分布 (周末柱青绿强调)
                Chart(m.weekdayStats) { s in
                    BarMark(x: .value("周几", s.name), y: .value("开门", s.opens))
                        .foregroundStyle(s.isWeekend ? DS.Palette.ok : DS.Palette.accent)
                }
                .frame(height: 150)
                Text("周末柱为青绿, 呈现作息节律")   // 616 周末柱为青绿
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.gutter)

            // 624 成员活跃气泡图 (自选股气泡): x = 窗口内次数, y = 距最近一次开门的天数, 泡径 = 名下凭证数。
            // 与 612 同一份归属口径 (Attribution 可证明才计, "约"); 左上角 = 次数少但很久没开。
            let bubbles = m.memberBubbles(days: m.memberBarDays)
            if !bubbles.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("成员活跃气泡 (近 \(m.memberBarDays) 天 · 约)")   // 624 成员活跃气泡
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Palette.text)
                    Chart(bubbles) { b in
                        PointMark(x: .value("次数", b.count), y: .value("距最近使用 (天)", b.daysAgo))
                            .symbolSize(CGFloat(min(420, 40 + b.creds * 30)))
                            .foregroundStyle(by: .value("成员", b.name))
                            .accessibilityLabel("\(b.name): \(b.count) 次, 距最近一次 \(b.daysAgo) 天, 名下 \(b.creds) 条凭证")
                    }
                    .frame(height: 180)
                    .chartXAxisLabel("窗口内开门次数")
                    .chartYAxisLabel("距最近一次开门 (天)")
                    Text("泡越大 = 名下凭证越多; 左上角 = 次数少但很久没开 (值得看一眼)。归属与凭证数都是本机台账口径 (约)。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            // 612/624 成员水平条: 天数只从 `m.memberBarDays` 取**一份** —— 上面那句"近 N 天"、条长用的数、
            // 下面查询用的数以前是三处各写一遍 30, 哪天改档就会漂成"文案 30 天、数据 14 天"。
            let barDays = m.memberBarDays
            let members = m.memberCounts(days: barDays)
            if !members.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("成员近 \(barDays) 天 (约 · 仅可证明归属)")
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Palette.text)
                    ForEach(Array(members.enumerated()), id: \.offset) { i, rec in
                        // 2026-10-13 run 66: 整行 (Button + 两个修饰符) 抽出 —— 该表达式报 type-check 超时。
                        memberBarRow(id: rec.id, name: rec.name, approx: rec.approx, index: i,
                                     barDays: barDays, maxApprox: members.first?.approx ?? 1)
                    }
                    if members.first?.approx == 0 {
                        Text("暂无可证明归属的开门 (归属需台账与日志窗口对齐)")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }

            // 625 凭证归属子段条: 各凭证类内嵌成员色子段 (台账推断"约", 无归属不画)
            let breakdown = m.kindOwnerBreakdown()
            if !breakdown.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("凭证归属构成 (约 · 仅可证明归属)")   // 625 凭证归属构成
                        .vkFont(.caption, weight: .medium)
                        .foregroundStyle(DS.Palette.textSub)
                    ForEach(StatsKit.StatModel.kindOrder(), id: \.self) { k in
                        if let segs = breakdown[k], !segs.isEmpty {
                            kindBreakdownRow(k, segs)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }

            // 619 凭证类使用榜 (排的是类, 不是逐条凭证 —— 口径写在 top5Section 上方)
            top5Section(m)

            // 613/620 告警构成与月度对比
            alertSection(m)
        }
    }

    /// 619 榜: 原句是"本月最常用凭证 Top5 条形榜, 前三名金/银/铜强调, 点击跳该凭证历史"。
    /// 这三样本仓都给不出, 所以界面改说得出证据的话, 而不是留三个假承诺:
    ///   · 排的是**凭证类** (pareto 那一份, 最多 4 类), 不是逐条凭证 —— 锁端不给逐凭证次数 (CAPABILITY §3);
    ///     只有 626 那条长期密码的台账推断是逐条的, 覆盖面撑不出一条逐条榜。
    ///   · "Top 5"这个数在四类的事实上永远到不了 5, 标题改报**真实行数** (top.count)。
    ///   · 前三名金/银/铜: DS 令牌里没有金银铜, 拿别的语义色冒充就是给颜色编假语义 —— 改成老老实实的名次数。
    ///   · 点击跳该凭证历史: 记录页没有"按单条凭证过滤"这个入口 (成员过滤是 pendingRecordsFilter 那一条, 不是一回事),
    ///     所以这一排不是按钮、不给 chevron、读屏也不提点按 —— 不承诺不存在的热区。
    /// 窗口天数与统计同一个出处 (`m.windowDays`), 不写死"本月" (算的是窗口 ∩ 缓存, 不是自然月)。
    @ViewBuilder
    private func top5Section(_ m: StatsKit.StatModel) -> some View {
        let top = Array(m.pareto.prefix(5))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("凭证类使用榜 · 近 \(m.windowDays) 天")   // 619 凭证类使用榜
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.text)
                ForEach(Array(top.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: DS.Space.s) {
                        Text(String(i + 1))
                            .vkFont(.caption2, weight: .semibold)
                            .foregroundStyle(DS.Palette.textSub)
                            .monospacedDigit()
                            .frame(width: 18, alignment: .leading)
                            .accessibilityLabel("第 \(i + 1) 名")
                        Text(p.label)
                            .vkFont(.footnote, weight: .medium)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(StatsKit.StatModel.compact(p.count) + " · 累计 " + String(Int(p.cumPct)) + "%")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityElement(children: .combine)
                }
                Text("排的是凭证类 (窗口内共 \(top.count) 类上榜), 类内不逐条; 名次按窗口内开门次数排。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    @ViewBuilder
    private func alertSection(_ m: StatsKit.StatModel) -> some View {
        let stats = m.alertStats
        let colors: [String: Color] = ["warn": DS.Palette.warn, "danger": DS.Palette.danger, "neutral": DS.Palette.textSub]
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("告警构成")   // 613 告警构成
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.text)
            if stats.isEmpty {
                Text("本月还没有告警记录, 这扇门很安静。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(stats) { s in
                    HStack(spacing: DS.Space.s) {
                        Text(s.typeName)
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .frame(width: 56, alignment: .leading)
                        Capsule()
                            .fill(colors[s.color] ?? DS.Palette.textSub)
                            .frame(width: max(2, CGFloat(s.month) / CGFloat(max(m.alertTotalMonth, 1)) * 120))
                        Text("\(s.month) 条" + (s.last > 0 ? " · 上月 \(s.last)" : ""))
                            .vkFont(.caption)
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
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                    Capsule()
                        .fill(DS.Palette.textSub)
                        .frame(width: 36, height: CGFloat(min(m.alertTotalLast, 60)) + 4)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("本月 \(m.alertTotalMonth)")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                    Capsule()
                        .fill(m.alertTotalMonth > m.alertTotalLast ? DS.Palette.danger : DS.Palette.ok)
                        .frame(width: 36, height: CGFloat(min(m.alertTotalMonth, 60)) + 4)
                }
                Spacer(minLength: 0)
                Text(m.alertTotalMonth > m.alertTotalLast ? "本月告警多于上月, 建议看看告警记录" : "告警未超上月")
                    .vkFont(.caption2)
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
    private func credentialSection(_ m: StatsKit.StatModel) -> some View {
        let pu = m.pwdUses
        let outOf = m.outOfRangeTotal
        if !pu.isEmpty || !m.otpPoints.isEmpty || outOf > 0 {
            Section("凭证维度") {
                if !pu.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("长期密码用量 (台账推断约值)")   // 626 长期密码用量
                            .vkFont(.subheadline, weight: .medium)
                            .foregroundStyle(DS.Palette.text)
                        ForEach(pu, id: \.alias) { p in
                            pwdUsageRow(p)
                        }
                        // 628 数据面实话: 首用只从密码时间窗推断 (锁端无逐凭证计数); 指纹侧没有等价的
                        // 逐指纹用量/首用可算 (attribution 只给"谁开的", 给不了"哪枚指纹开的"), 所以不列。
                        Text("口径: 「首用」= 生效期内唯一时间窗命中的最早一次开门 (台账推断); 指纹凭证无独立首用数据, 不列。")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        if outOf > 0 {
                            Label("约 \(outOf) 次密码开门落在所有时间窗之外 (台账推断",
                                  systemImage: "exclamationmark.circle")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }

                // 627 OTP 使用散点
                if !m.otpPoints.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("临时密码使用时刻")   // 627 临时密码使用时刻
                            .vkFont(.subheadline, weight: .medium)
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

                // 617 逐日首末开门区间 + 618 窗口内逐日首次开门的最早/中位/最晚
                let ranges = m.rangeRows.suffix(14).reversed().map { $0 }
                if !ranges.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("逐日首末开门区间")   // 617 逐日首末开门区间
                            .vkFont(.subheadline, weight: .medium)
                            .foregroundStyle(DS.Palette.text)
                        // 618 一行: 三个数来自 `m.firstOpenHourSpread` —— 它就是下面那排逐日条的 minHour 排出来的
                        // 最早/中位/最晚, 同一个出处, 不在别处再算第二套"首次开门"。中位取**下中位数** (理由同 780)。
                        if let sp = m.firstOpenHourSpread {
                            HStack(spacing: DS.Space.s) {
                                Text("窗口首开")
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(DS.Palette.surfaceAlt)
                                        Capsule()
                                            .fill(DS.Palette.accent.opacity(0.30))
                                            .frame(width: max(w * 0.03, CGFloat(sp.latest - sp.earliest) / 24 * w))
                                            .offset(x: CGFloat(sp.earliest) / 24 * w)
                                        // 中位那一根竖标: 落在真实发生过的下中位上, 不是两端插出来的时刻
                                        Rectangle()
                                            .fill(DS.Palette.warn)
                                            .frame(width: 2, height: 12)
                                            .offset(x: CGFloat(sp.median) / 24 * w - 1)
                                            .accessibilityHidden(true)
                                    }
                                    .frame(height: 12)
                                }
                                Text("最早 \(sp.earliest) · 中位 \(sp.median) · 最晚 \(sp.latest) 时")
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("窗口内逐日首次开门: 最早 \(sp.earliest) 时, 中位 \(sp.median) 时, 最晚 \(sp.latest) 时")   // 618 窗口内逐日首次开门
                        }
                        // 617 竖棒形态 (原句: 每日一根竖棒 = 当日首末开门区间, 顶端圆点标当日次数):
                        // 横轴是日 (最多 14 天), 纵轴是 0–24 时。旧写法是横条 + 右端圆点标"末次开门那一小时"
                        // + 行末文字报次数 —— 与"竖棒 / 顶端圆点标次数"两处都不符。
                        // 圆点半径随次数增大 (3–9pt) 只作视觉量级; 精确次数在日标签行的读屏标签里。
                        // ForEach 用 id: \.offset: enumerated 的元素是元组, 不能遵循 Identifiable。
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            let step = w / CGFloat(max(ranges.count, 1))
                            ZStack(alignment: .topLeading) {
                                ForEach(Array(ranges.enumerated()), id: \.offset) { i, r in
                                    let x = step * (CGFloat(i) + 0.5)
                                    let yTop = CGFloat(r.minHour) / 24 * h
                                    let stickH = max(3, CGFloat(max(r.maxHour - r.minHour, 0)) / 24 * h)
                                    let dot = min(9, 3 + CGFloat(r.count))
                                    Capsule()
                                        .fill(DS.Palette.accent.opacity(0.7))
                                        .frame(width: 4, height: stickH)
                                        .offset(x: x - 2, y: yTop)
                                    Circle()
                                        .fill(DS.Palette.ok)
                                        .frame(width: dot, height: dot)
                                        .offset(x: x - dot / 2, y: max(0, yTop - dot / 2))
                                }
                            }
                        }
                        .frame(height: 132)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("逐日首末开门竖棒图, 纵轴 0 到 24 时。"
                            + ranges.map { "\($0.key) \($0.minHour) 时至 \($0.maxHour) 时, \($0.count) 次" }.joined(separator: "; "))
                        // 日标签行: 与上面横轴同一份等宽分格 (单元格中心对齐竖棒); 超过 7 天隔一天标一个, 免得挤成一团
                        HStack(spacing: 0) {
                            ForEach(Array(ranges.enumerated()), id: \.offset) { i, r in
                                Text((ranges.count <= 7 || i % 2 == 0) ? String(r.key.suffix(5)) : "")
                                    .vkFont(.caption2)   // 语义字号: 9pt 固定值不参与 Dynamic Type
                                    .foregroundStyle(DS.Palette.textSub)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .accessibilityHidden(true)
                        // 这一族画的到底是什么, 写在图下面而不是靠标题猜 (形态与口径一起写清):
                        Text("竖棒 = 当日最早与最晚开门之间 (分辨率到「时」, 纵轴 0–24 时), 棒顶圆点大小 = 当日开门次数"
                             + " (精确值走读屏标签; 超过 7 天时隔一天标一个日期)。协议没有门磁与上锁状态, 这条只是首末开门夹出来的代理值。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
            }
        }
    }

    // ---------- 小结 (799 成员周小结 + 800 在家代理 + 1020 黄金时段) ----------
    @ViewBuilder
    private func summarySection(_ m: StatsKit.StatModel) -> some View {
        let week = m.weekSummary()
        let home = m.homeDurationProxy(days: 7)
        // 800 月对比: 与 601 同比同一种月窗 —— 半开 [月起, 次月1日), 上月整月不丢尾日; 数值走 homeProxyHours 同一出处
        let cal = WeekCal.gregorian
        let now = Date()
        let tStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let lStart = cal.date(byAdding: .month, value: -1, to: tStart)!
        let thisM = m.homeProxyHours(from: tStart, to: now)
        let lastM = m.homeProxyHours(from: lStart, to: tStart)
        // 门控带上两个"月窗有数": 上月开过门而近 7 天没有时, 月对比恰是该看的一行, 不能整段隐掉
        if !week.isEmpty || !home.isEmpty || thisM > 0 || lastM > 0 {
            Section("小结") {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, s in
                        Label(s, systemImage: "person.fill")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(home.enumerated()), id: \.offset) { _, s in
                        Label(s, systemImage: "house.fill")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Label("本月至今约 \(thisM) 小时 · 上月全月约 \(lastM) 小时 (天数不等只看量级)",
                          systemImage: "calendar")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("口径: 协议无门磁/上锁状态, 在家时长为「首末开门间隔求和」的代理值")   // 800 口径
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DS.Space.gutter)
            }
        }
    }

    // ---------- 50 年报告占位 ----------
    @ViewBuilder
    private func yearReportSection(_ m: StatsKit.StatModel) -> some View {
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
                            .vkFont(.subheadline, weight: .medium)
                            .foregroundStyle(DS.Palette.text)
                        Text(cov >= 365 ? "数据已积累, 可生成" : "数据积累中 (\(cov)/365 天)")
                            .vkFont(.caption)
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
            Text("年度回顾")   // 50 年度回顾
        }
    }

    // ---------- 638 下钻明细 ----------
    // 与同批 15 个 xxxSection 统一: 显式写 -> some View (带 @ViewBuilder 却缺返回类型的形状
    // 本机无编译器证不了, 按 R6 头注释的取舍一律补齐; 且它 body 以 let 起头, 正是 R1b 的雷区)。
    @ViewBuilder
    private func drillSection(_ m: StatsKit.StatModel, hour: Int16) -> some View {
        let rows = m.logsInWindow().filter { l in
            guard let d = StatsKit.dateOf(l) else { return false }
            return WeekCal.gregorian.component(.hour, from: d) == Int(hour)
                && (StatsKit.openTypes.contains(l.type) || StatsKit.alarmTypes.contains(l.type))
        }.sorted { (StatsKit.dateOf($0) ?? .distantPast) > (StatsKit.dateOf($1) ?? .distantPast) }.prefix(20)
        Section("「\(hour) 时」时段记录 (点查单条)") {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, l in
                Button {
                    // 638 第三级那句"点查单条"要落地就得给记录页这一条的行身份 (与 621 明细行、170 同一个出口):
                    // 只切 Tab 不交键, 标题承诺的"单条"其实到不了 —— 那是给一个不存在的热区写文案。
                    // 先清掉成员过滤再交键: 记录页若正被某个成员过滤挡着, 这一条可能不在当前显示范围里,
                    // 那种情形记录页自己会弹一句"这条记录不在当前显示范围里 (585)", 不静默换一把锁念。
                    app.pendingRecordsFilter = ""
                    app.pendingRecordKey = RecordOverlay.oid(mac: mac, rowKey: String(l.idxRaw))
                    app.requestRoute(.records)
                    dismiss()
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: StatsKit.alarmTypes.contains(l.type) ? "diamond.fill" : "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(StatsKit.alarmTypes.contains(l.type) ? DS.Palette.warn : DS.Palette.accent)
                            .accessibilityHidden(true)
                        Text(l.lockTimeStr.isEmpty ? l.typeName : l.lockTimeStr + " · " + l.typeName)
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("点按跳到记录页这条并高亮")   // 170 点按跳到记录页这条并
            }
            if rows.isEmpty {
                Text("这个时段近 " + String(m.windowDays) + " 天没有记录")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }
}

// ---------- 50 年报告 (数据积累中占位) ----------
struct YearReportView: View {
    let mac: String
    @Environment(\.dismiss) private var dismiss

    var body: some View { vkBody.destined(.yearReport) }
    var vkBody: some View {
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
                            .vkFont(.title3, weight: .semibold)
                            .foregroundStyle(DS.Palette.text)
                        Text("年报告需要连续积累满一年 (365 天) 的门禁日志。当前已积累 \(cov) 天, 还差 \(max(0, 365 - cov)) 天。积累满后这里会按季度给出「最活跃时段 / 使用最多的凭证 / 告警最少的月份」。")
                            .vkFont(.footnote)
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

    /// 50 年报表的季度/月度聚合 —— 2026-10-13 run 63 从 @ViewBuilder 的 yearReport 里拆出
    /// (ViewBuilder 里的 for 循环只做累加不产视图会报 "closure containing control flow statement …")。
    private func yearReportBuckets(_ pts: [StatsKit.DailyPoint])
        -> (qO: [Int: Int], qA: [Int: Int], moA: [Int: Int]) {
        let cal = WeekCal.gregorian
        var qO = [Int: Int](), qA = [Int: Int](), moA = [Int: Int]()
        for p in pts {
            let mo = cal.component(.month, from: p.day)
            qO[(mo - 1) / 3, default: 0] += p.opens
            qA[(mo - 1) / 3, default: 0] += p.alarms
            moA[mo, default: 0] += p.alarms
        }
        return (qO, qA, moA)
    }
    @ViewBuilder
    private func yearReport(cov: Int) -> some View {
        let m = StatsKit.build(mac: mac, week: 7, window: 365)
        // 2026-10-13 run 63: 原来在 @ViewBuilder 里直接 `for p in m.dailyPoints { 累加字典 }` ——
        // 循环体不产视图 (只累加), ViewBuilder 报 "closure containing control flow statement cannot be
        // used with result builder 'ViewBuilder'"。聚合拆成纯函数 yearReportBuckets。
        let buckets = yearReportBuckets(m.dailyPoints)
        let qO = buckets.qO, qA = buckets.qA, moA = buckets.moA
        let top = m.pwdUses.max { $0.approxUses < $1.approxUses }
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("本年开门 " + StatsKit.StatModel.compact(m.opensTotal))
                .vkFont(.title3, weight: .semibold)
                .foregroundStyle(DS.Palette.text)
            // 50: 季度拆行 + 最常用凭证 + 最少告警月 (数据全取自既有 365 天模型)
            ForEach(0..<4, id: \.self) { i in
                Text("Q\(i + 1): 开门 \(qO[i] ?? 0) 次 · 告警 \(qA[i] ?? 0) 条")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
            Text("黄金时段: " + m.goldenSentence)
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)
            if let t = top, t.approxUses > 0 {
                Text("最常用凭证: " + t.name + " 约 " + String(t.approxUses) + " 次 (台账推断)")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
            if let c = moA.min(by: { $0.value < $1.value }) {
                Text("告警最少月: \(c.key) 月 (\(c.value) 条)")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
            Text("告警共 " + String(m.alertStats.reduce(0) { $0 + $1.month + $1.last }))
                .vkFont(.footnote)
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
                            .vkFont(.subheadline, weight: .medium)
                            .foregroundStyle(DS.Palette.text)
                        Text(l.typeName)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .accessibilityElement(children: .combine)
                }
                if drillRows.isEmpty {
                    Text("这个时段近 \(windowDays) 天没有记录")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle(TimeWord.word(Int(hour)) + " " + String(hour) + " 时记录")   // 638 时记录
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var drillRows: [CachedLog] {
        // 638 时段下钻: 窗口内该小时的 开门/告警 记录 (真实台账, 无数据出空态)
        let logs = DB.readLogs(mac)
        let s = WeekCal.shifted(WeekCal.gregorian.startOfDay(for: Date()), days: -max(0, windowDays - 1))
        var out: [CachedLog] = []
        for l in logs {
            guard let d = StatsKit.dateOf(l) else { continue }
            guard d >= s, WeekCal.gregorian.component(.hour, from: d) == Int(hour) else { continue }
            if StatsKit.openTypes.contains(l.type) || StatsKit.alarmTypes.contains(l.type) { out.append(l) }
        }
        return Array(out.sorted { (StatsKit.dateOf($0) ?? .distantPast) > (StatsKit.dateOf($1) ?? .distantPast) }.prefix(20))
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

// 时段下钻 sheet(item:) 要求 item 为 Identifiable；Int16 此前不满足 (原写法 h != nil / h! 亦对非可选值非法)
extension Int16: @retroactive Identifiable { public var id: Int16 { self } }

// ---------- ChartProxy.plotFrame 的可选性收口 ----------
/// `ChartProxy.plotFrame` 是 `Anchor<CGRect>?`（iOS 17 的 `plotAreaFrame` 不是可选）, 取不到时按 .zero 兜底。
/// 为什么收成函数而不是在每个调用点写 `map { } ?? .zero`: 那三处都在 Chart 的构建闭包里,
/// 多塞一个泛型闭包会把类型求解推过时限 —— 2026-10-17 CI 实测报的就是
/// "the compiler is unable to type-check this expression in reasonable time"。
private func plotRect(_ proxy: ChartProxy, _ geo: GeometryProxy) -> CGRect {
    guard let anchor = proxy.plotFrame else { return .zero }
    return geo[anchor]
}
