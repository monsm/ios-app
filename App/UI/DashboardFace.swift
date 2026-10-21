import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - F 仪表（锁的数据 + 人的数据）
// ═══════════════════════════════════════════════════════════════════════
//
// 顶部液态玻璃分段切换两个视角:
//   「这把锁」 hourStats / dailyPoints / weekDelta / coverage / alarms
//   「这些人」 memberCounts / memberBubbles / memberDaily / kindOwnerBreakdown
//
// ═══ 数据来源全部核实过签名 ═══
//
// 锁侧（StatModel 属性）:
//   hourStats        [HourStat]        每小时开门数
//   dailyPoints      [DailyPoint]      逐日
//   weekDelta        Double?           本周 vs 上周变化
//   coverage         Int               数据覆盖天数
//   opensTotal       Int               总开门
//   alarmsTotal      Int               总告警
//   isDegraded       Bool              数据不足
//
// 人侧（StatModel 实例方法）:
//   memberCounts(days:)   [(id,name,approx)]
//   memberBubbles(days:)  [MemberBubble]   有 count/daysAgo/creds
//   memberTodayCount(id:) Int
//   kindOwnerBreakdown()  [String:[(id,name,n)]]
//
// ═══ 海量数据处理 ═══
//
// 时间窗口按数据量动态降级: 90天 → 30天 → 7天。
// 超过阈值时按小时/按日聚合，不逐条画。
struct DashboardFace: View {
    @EnvironmentObject private var app: AppState
    @State private var lens: Lens = .lock

    enum Lens: String, CaseIterable, Identifiable {
        case lock = "这把锁"
        case people = "这些人"
        var id: String { rawValue }
    }

    private var mac: String { app.currentMac }

    /// 按数据量选窗口
    private var window: Int {
        let total = DB.readLogs(mac).count
        if total > 800 { return 7 }
        if total > 200 { return 30 }
        return 90
    }

    private var model: StatsKit.StatModel? {
        guard !mac.isEmpty else { return nil }
        return StatsKit.build(mac: mac, week: 7, window: window)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: XSpace.l) {
                    lensPicker

                    if let m = model, m.hasData {
                        switch lens {
                        case .lock: LockLens(model: m)
                        case .people: PeopleLens(model: m)
                        }
                    } else {
                        XEmptyState(systemImage: "chart.xyaxis.line",
                                    title: "还没有数据",
                                    message: "开门几次之后，这里会出现统计。")
                    }
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.bottom, XSpace.xxl)
            }
            .background(XPalette.canvas)
            .navigationTitle("仪表")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ── 顶部液态玻璃分段 ──
    private var lensPicker: some View {
        HStack(spacing: 0) {
            ForEach(Lens.allCases) { l in
                Button {
                    withAnimation(XMotion.soft) { lens = l }
                    XHaptics.tick.impactOccurred()
                } label: {
                    Text(l.rawValue)
                        .xFont(.subheadline, weight: lens == l ? .semibold : .regular)
                        .foregroundStyle(lens == l ? XPalette.text : XPalette.textSub)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if lens == l {
                                Capsule().fill(XPalette.accent.opacity(XOpacity.badge))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(lens == l ? [.isSelected] : [])
            }
        }
        .padding(4)
        // 用 axGlassCapsule() 而不是 axGlass(19):
        //   · 内部选中态是 Capsule()，外层若用圆角矩形，形状不一致
        //   · 19 < 23（总高 46 的一半），画出来是圆角矩形而非胶囊
        //   · AccessibilityKit 里胶囊与圆角是两个通道，形状族只在一处枚举
        .axGlassCapsule()
        .padding(.top, XSpace.s)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 「这把锁」
// ═══════════════════════════════════════════════════════════════════════
private struct LockLens: View {
    let model: StatsKit.StatModel
    /// StatsPage 依赖 AppState —— 这里必须显式接，
    /// LockLens 是独立 struct，不继承 DashboardFace 的环境。
    /// （第一版我直接写 .environmentObject(app)，CI 报 cannot find 'app' in scope）
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: XSpace.l) {
            headline
            hourRing
            weekCompare
        }
    }

    // 三个大数字
    private var headline: some View {
        HStack(spacing: XSpace.m) {
            metric("总开门", "\(model.opensTotal)", tone: XPalette.accent, icon: "door.left.hand.open")
            metric("告警", "\(model.alarmsTotal)", tone: model.alarmsTotal > 0 ? XPalette.warn : XPalette.ok, icon: "exclamationmark.triangle")
            metric("覆盖", "\(model.coverage)天", tone: XPalette.textSub, icon: "calendar")
        }
        .padding(.top, XSpace.s)
    }

    private func metric(_ label: String, _ value: String, tone: Color, icon: String) -> some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.xs) {
                Image(systemName: icon)
                    .font(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(tone)
                Text(value)
                    .xFont(.title2, weight: .semibold)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    // 24 小时环
    /// 小时分布（门面版）—— 比 StatsPage 的小，因为这里只是速览
    ///
    /// 与 StatsPage.rhythmCard 的关系:
    ///   · 那一页有 156pt 时钟 + 柱状图读数 + 告警率 + 14 天折线（深度分析）
    ///   · 这里只给 176pt 时钟 + 「看完整数据」入口（快速浏览）
    ///
    /// 两个页面各司其职，不重复实现同一份深度内容。
    private var hourRing: some View {
        XPanel {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("一天里什么时候在用")
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.textSub)

                // XDayClock 内部用固定 size 画（默认 240），
                // 外面再套 .frame(height:) 会让内容溢出 —— 直接传 size。
                XDayClock(hours: model.hourStats, size: 176)
                    .frame(maxWidth: .infinity)

                NavigationLink {
                    // StatsPage 依赖 AppState（读 app.currentMac）
                    StatsPage().environmentObject(app)
                } label: {
                    HStack(spacing: 4) {
                        Text("告警率 · 14 天趋势 · 完整分析")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(XPalette.accent)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: XHit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看完整统计")
            }
        }
    }

    // 本周 vs 上周
    @ViewBuilder
    private var weekCompare: some View {
        if let delta = model.weekDelta {
            XPanel {
                HStack(spacing: XSpace.m) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: XIcon.md, weight: .semibold))
                        .foregroundStyle(delta >= 0 ? XPalette.ok : XPalette.textSub)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(delta >= 0 ? "比上周多 \(Int(abs(delta) * 100))%" : "比上周少 \(Int(abs(delta) * 100))%")
                            .xFont(.body, weight: .medium)
                            .foregroundStyle(XPalette.text)
                        Text("近 7 天对比前 7 天")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 「这些人」
// ═══════════════════════════════════════════════════════════════════════
private struct PeopleLens: View {
    let model: StatsKit.StatModel

    private var counts: [(id: String, name: String, approx: Int)] {
        model.memberCounts(days: 30)
    }
    private var bubbles: [StatsKit.MemberBubble] {
        model.memberBubbles(days: 30)
    }

    /// 每人逐日次数 —— 用来画活跃热力条
    private var daily: [(id: String, name: String, perDay: [String: Int])] {
        model.memberDaily(days: 30)
    }

    /// 近 30 天在家时长代理（首末开门间隔求和）
    private var homeHours30: Int {
        let now = Date()
        return model.homeProxyHours(from: now.addingTimeInterval(-30 * 86400), to: now)
    }

    var body: some View {
        VStack(spacing: XSpace.l) {
            today
            homeHoursCard
            ranking
            if !daily.isEmpty { activityStrip }
            kindOwnerCard
            if !bubbles.isEmpty { bubbleRow }
        }
    }

    // 今日在场
    @ViewBuilder
    private var today: some View {
        let present = counts.filter { model.memberTodayCount(id: $0.id) > 0 }
        if !present.isEmpty {
            XPanel {
                VStack(alignment: .leading, spacing: XSpace.s) {
                    Text("今天来过")
                        .xFont(.footnote, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                    HStack(spacing: XSpace.s) {
                        ForEach(present, id: \.id) { p in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(memberColor(p.id))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Text(String(p.name.prefix(1)))
                                            .xFont(.caption, weight: .semibold)
                                            .foregroundStyle(XPalette.onAccent)
                                    )
                                Text("\(model.memberTodayCount(id: p.id))")
                                    .xFont(.caption2)
                                    .foregroundStyle(XPalette.textSub)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(p.name) 今天 \(model.memberTodayCount(id: p.id)) 次")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // 30 天排行
    // ── 近 30 天在家时长（StatModel.homeProxyHours）──
    //
    // 这是「人的数据」里唯一带**时间累积**语义的指标:
    // 逐日首末开门间隔求和 —— 有人开门到有人再开门之间的跨度，
    // 作为"家里有人"的代理。协议没有在场传感器（CAPABILITY §5），
    // 所以只能代理，不能声称是真实在家时长。
    private var homeHoursCard: some View {
        XPanel(kind: .group) {
            HStack(spacing: XSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("近 30 天")
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(homeHours30))
                            .xFont(.title2, weight: .semibold)
                            .foregroundStyle(XPalette.accent)
                            .monospacedDigit()
                        Text("小时")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                    }
                    Text("家里有人的时间（代理值）")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "house.fill")
                    .font(.system(size: XIcon.lg, weight: .medium))
                    .foregroundStyle(XPalette.accent.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("近 30 天家里有人的时间约 " + String(homeHours30) + " 小时")
    }

    // ── 成员活跃热力条（StatModel.memberDaily）──
    //
    // 每人一行 30 格，格子越亮表示当天开门越多。
    // 比"总次数排行"多一层信息: 能看出**节奏**（天天来 vs 集中几天）。
    private var activityStrip: some View {
        XPanel {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("近 30 天 · 谁哪天来过")
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.textSub)

                ForEach(daily, id: \.id) { row in
                    let days = sortedDays
                    let peak = max(1, row.perDay.values.max() ?? 1)
                    HStack(spacing: XSpace.s) {
                        Text(row.name)
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textSub)
                            .frame(width: 46, alignment: .leading)
                            .lineLimit(1)
                        HStack(spacing: 1.5) {
                            ForEach(days, id: \.self) { d in
                                let n = row.perDay[d] ?? 0
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(n == 0
                                          ? XPalette.surfaceAlt
                                          : memberColor(row.id).opacity(0.25 + 0.75 * Double(n) / Double(peak)))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 14)
                            }
                        }
                        .frame(height: 14)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name + " 近 30 天活跃热力")
                }
            }
        }
    }

    /// 30 个日键（升序），热力条的横轴
    private var sortedDays: [String] {
        var keys = Set<String>()
        for row in daily { keys.formUnion(row.perDay.keys) }
        return Array(keys.sorted().suffix(30))
    }

    // ── 凭证类型 × 成员（StatModel.kindOwnerBreakdown）──
    //
    // 回答"谁在用哪种方式开门": 指纹 / 密码 / 临时码 / 钥匙。
    // 这与 memberCounts 的正交信息: 那个是"谁开得多"，这个是"用什么开"。
    private var kindOwnerCard: some View {
        let breakdown = model.kindOwnerBreakdown()
        let kinds = ["fp", "pwd", "temp", "key"].filter { !(breakdown[$0] ?? []).isEmpty }
        return Group {
            if !kinds.isEmpty {
                XPanel {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        Text("谁用什么开门")
                            .xFont(.footnote, weight: .medium)
                            .foregroundStyle(XPalette.textSub)

                        ForEach(kinds, id: \.self) { kind in
                            let rows = breakdown[kind] ?? []
                            HStack(spacing: XSpace.s) {
                                Text(kindWord(kind))
                                    .xFont(.caption2)
                                    .foregroundStyle(XPalette.textTertiary)
                                    .frame(width: 40, alignment: .leading)
                                Text(topNames(rows))
                                    .xFont(.caption)
                                    .foregroundStyle(XPalette.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(String(rows.reduce(0) { $0 + $1.n }))
                                    .xFont(.caption2.monospacedDigit())
                                    .foregroundStyle(XPalette.textSub)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(kindWord(kind) + " " + topNames(rows))
                        }
                    }
                }
            }
        }
    }

    /// 凭证类型的中文名
    ///
    /// 键来自 StatsKit.kindOrder() = ["fp", "pwd", "temp", "key"]，
    /// 中文映射走 StatsKit.kindWords() —— 不在这里另写一套。
    private func kindWord(_ k: String) -> String {
        StatsKit.kindWords()[k] ?? k
    }

    /// 前两位成员的名字，多于两人时加"等"
    private func topNames(_ rows: [(id: String, name: String, n: Int)]) -> String {
        let top = rows.prefix(2).map { $0.name }
        if rows.count > 2 { return top.joined(separator: "、") + " 等" }
        return top.joined(separator: "、")
    }

    private var ranking: some View {
        XPanel {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("近 30 天 · 谁开得多")
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.textSub)
                let maxN = max(1, counts.map(\.approx).max() ?? 1)
                ForEach(counts, id: \.id) { c in
                    HStack(spacing: XSpace.s) {
                        Text(c.name)
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.text)
                            .frame(width: 52, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(XPalette.surfaceAlt)
                                Capsule()
                                    .fill(memberColor(c.id).opacity(0.85))
                                    .frame(width: max(6, geo.size.width * CGFloat(c.approx) / CGFloat(maxN)))
                            }
                        }
                        .frame(height: 8)
                        Text("\(c.approx)")
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textSub)
                            .frame(width: 26, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(c.name) 约 \(c.approx) 次")
                }
            }
        }
    }

    // 成员气泡
    private var bubbleRow: some View {
        XPanel {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("谁最近比较活跃")
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.textSub)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: XSpace.m) {
                        ForEach(bubbles.prefix(12)) { b in
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(memberColor(b.id).opacity(0.20))
                                        .frame(width: bubbleSize(b), height: bubbleSize(b))
                                    Text("\(b.count)")
                                        .xFont(.caption, weight: .semibold)
                                        .foregroundStyle(memberColor(b.id))
                                }
                                Text(b.name)
                                    .xFont(.caption2)
                                    .foregroundStyle(XPalette.textSub)
                                    .lineLimit(1)
                            }
                            .frame(width: 60)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(b.name) 最近 \(b.count) 次")
                        }
                    }
                }
            }
        }
    }

    private func bubbleSize(_ b: StatsKit.MemberBubble) -> CGFloat {
        let mx = max(1, bubbles.map(\.count).max() ?? 1)
        return 34 + 26 * CGFloat(b.count) / CGFloat(mx)
    }

    /// 成员色 —— 与 MembersPage.memberColor 同一口径
    ///
    /// Member.color 是 "#RRGGBB" 字符串，要转成 UInt32 再交给 Color(hex:)。
    /// （第一版我写了 Color(hex: m.color) —— 那个 init 收的是 UInt32，不是 String。）
    private func memberColor(_ id: String) -> Color {
        guard let m = DB.member(id) else { return XPalette.accent }
        if m.color.hasPrefix("#"), let v = UInt32(m.color.dropFirst(), radix: 16) {
            return Color(hex: v)
        }
        return XPalette.accent
    }
}
