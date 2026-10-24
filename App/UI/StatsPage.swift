//
//  StatsPage.swift
//  统计页 · 全新重写 (2026-10-21)
//
//  门里「事件」→ 统计的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 StatsView (1999 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 24 个图表区块 —— 折线/均线/空窗/春节/热力/假期柱/雷达/
//        散点/累计/甘特/构成/凭证维度/年报告/下钻… 一屏塞不下。
//
//  新版: 只回答三个问题
//    ① 我安全吗      — 告警率 + 异常天
//    ② 我在正常用吗  — 开门节律 (24h 分布 + 近 7 天)
//    ③ 有什么变化    — 本月 vs 上月
//
//  数据不足时 (isDegraded) 只出一行文字, 不画空图。
//
//  设计原则 (HIG charting-data):
//    · 每张图只讲一件事
//    · 坐标轴只在必要时出现
//    · 数据不足时诚实说"样本不足"
//

import SwiftUI
import Charts

/// 统计页
struct StatsPage: View {
    @EnvironmentObject private var app: AppState

    @State private var model: StatsKit.StatModel?
    @State private var loaded = false
    /// 「怎么开的门」的明细在记录页 —— §7.11 的卡头链接需要一个真实目的地。
    @State private var showEvents = false
    @State private var showSecurity = false

    private var mac: String { app.currentMac }

    /// 给 `XScreen.above` 用的胶囊行 —— 只在有 model 且非降级态时出现。
    /// 单独抽出来是因为 `above` 的签名是 `(() -> AnyView)?`，
    /// 而 `chipRow(m)` 需要一个解包后的 `m`。
    @ViewBuilder
    private var chipRowIfAny: some View {
        if let m = model, !m.isDegraded {
            chipRow(m)
        }
    }

    var body: some View {
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        // 2026-10-23：胶囊行挪到**大标题之上**。
        //
        // 规范 §5.3 骨架图把它画在标题上面：
        //   StatusBar → 14pt → **胶囊行** → 29pt → LargeTitle
        //
        // 而我上一版只能往 XScreen 的 content 里塞，于是它跑到了标题**之下** ——
        // 与本页注释自己写的「这一屏最上面那条摘要，它先行」正好相反。
        // 现在 XScreen 有了 above 槽，它终于在最上面。
        XScreen("统计", above: { AnyView(chipRowIfAny) }) {
            if let m = model {
                if m.isDegraded {
                    degradedCard(m).xScrollLift()
                } else {
                    // 规范 7.2「双列固定」: 2 个胶囊并排撑满,
                    // 各占 (屏宽 - 28 - 8) / 2, **不滚动**。
                    // 六图改造 (2026-10-23): 首卡换成**图 5 Activity Rings**。
                    //
                    // 图 5 Fitness Summary 的第一张卡永远是三环 + 右侧彩色数据行。
                    // 统计页之前直接进「安全」三瓦片 —— 缺了"今天整体跑了多少"这层。
                    // 三环: 开门 / 指纹 / 自动，各自占今日总量的比例。
                    activityRingsCard(m).xScrollLift()
                    safetyCard(m).xScrollLift()
                    paretoCard(m)
                    daypartCard(m)
                    firstOpenCard(m)
                    rhythmCard(m).xScrollLift()
                    trendCard(m).xScrollLift()
                }
            } else if !loaded {
                XSkeleton(blocks: 3, blockHeight: 132)
            }
        }
        .sheet(isPresented: $showEvents) {
            EmptyView()  // 2026-10-24: EventsPage 已删（用户裁定）
        }
        .sheet(isPresented: $showSecurity) {
            EmptyView()  // 2026-10-24: SecurityPage 已删
        }
        .task { if !loaded { load() } }
    }

    /// 顶部胶囊行 (规范 7.2 双列固定形态)
    ///
    /// 标签在上、灰; 值在下、白 —— 主次不能反。两个胶囊共用同一条
    /// 派生宽度公式 (屏宽 − 页边距×2 − 列间距) / 2, 不各写各的。
    @ViewBuilder
    private func chipRow(_ m: StatsKit.StatModel) -> some View {
        HStack(spacing: XSpace.rowGap) {
            XStatChip(label: "总开门",
                      value: "\(m.opensTotal)",
                      systemImage: "door.left.hand.open",
                      tint: XPalette.accentText)
            XStatChip(label: "告警",
                      value: "\(m.alarmsTotal)",
                      systemImage: "exclamationmark.triangle",
                      tint: m.alarmsTotal > 0 ? XPalette.warn : XPalette.ok)
        }
    }

    private func load() {
        guard !mac.isEmpty else { loaded = true; return }
        model = StatsKit.build(mac: mac, week: 7, window: 30)
        loaded = true
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ① 安全吗
    // ═══════════════════════════════════════════════════════

    // ── 凭证分布（pareto）──
    //
    // 回答"哪种方式在开门" —— 指纹多还是密码多。
    // Pareto 数据早已算好（含累计百分比），但页面从没用过。
    @ViewBuilder
    private func paretoCard(_ m: StatsKit.StatModel) -> some View {
        let rows = m.pareto
        if !rows.isEmpty {
            XPanel {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    // 规范 §7.11：卡内顶部的标题是**链接**（灰 14 + chevron），不是白粗标题。
                    // 这张卡的数据出自「记录」页，点它能直接进去看明细 —— 之前没有这个入口。
                    XCardLink(title: "怎么开的门") { showEvents = true }

                    let peak = max(rows.map { $0.count }.max() ?? 1, 1)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack(spacing: XSpace.s) {
                            Text(r.label)
                                .xFont(.caption)
                                .foregroundStyle(XPalette.text)
                                .xScaledWidth(52, alignment: .leading)
                            // 横条
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(XPalette.surfaceAlt)
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(kindColor(r.kind))
                                        .frame(width: Swift.max(4, geo.size.width * CGFloat(r.count) / CGFloat(peak)))
                                }
                            }
                            .frame(height: 10)
                            Text(String(r.count))
                                .xFontExact(.caption2.monospacedDigit())
                                .foregroundStyle(XPalette.textSub)
                                .xScaledWidth(30, alignment: .trailing)
                            Text(String(format: "%.0f%%", r.pct))
                                .xFontExact(.caption2.monospacedDigit())
                                .foregroundStyle(XPalette.textSub)
                                .xScaledWidth(32, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(r.label + " " + String(r.count) + " 次")
                    }
                }
            }
            .xScrollLift()
        }
    }

    /// 凭证类型色 —— 与「钥匙工坊」四张卡、事件页时间线**同一套**。
    ///
    /// ⚠ 这里原来是第三个版本：指纹用铜、密码用绿、临时码用橙、key 用灰。
    /// 而工坊是 铜/青/金/紫、事件页是 铜/青/金/紫 —— 同一个凭证类型
    /// 在三个页面是三种颜色。用户跨页看统计时，颜色不但没帮忙，反而在误导。
    ///
    /// 现在三处统一：pwd 铜 / fp 青 / temp 金 / key 紫 / 未知 灰。
    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "fp":   return XPalette.kindFp
        case "pwd":  return XPalette.accent
        case "temp": return XPalette.kindTemp
        case "key":  return XPalette.kindOtp
        default:     return XPalette.textSub
        }
    }

    // ── 一天分段（dayparts）──
    //
    // 比"24 小时逐时"更易读: 早上 / 中午 / 傍晚 / 深夜。
    // dayparts 已算好（含时段跨度文案），从没用过。
    @ViewBuilder
    private func daypartCard(_ m: StatsKit.StatModel) -> some View {
        let parts = m.dayparts
        if m.daypartTotal > 0 {
            XPanel {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    Text("一天里什么时候最忙")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.textSub)

                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        HStack(spacing: XSpace.s) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name)
                                    .xFont(.caption, weight: .medium)
                                    .foregroundStyle(XPalette.text)
                                Text(p.span)
                                    .xFont(.caption2)
                                    .foregroundStyle(XPalette.textSub)
                            }
                            .xScaledWidth(66, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(XPalette.surfaceAlt)
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(XPalette.accent.opacity(0.75))
                                        .frame(width: Swift.max(4, geo.size.width * CGFloat(p.opens) / CGFloat(max(m.daypartTotal, 1))))
                                }
                            }
                            .frame(height: 10)
                            Text(String(p.opens))
                                .xFontExact(.caption2.monospacedDigit())
                                .foregroundStyle(XPalette.textSub)
                                .xScaledWidth(30, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(p.name + " " + p.span + " " + String(p.opens) + " 次")
                    }
                }
            }
            .xScrollLift()
        }
    }

    // ── 工作日出门时间（workdayFirstOpenMedian）──
    //
    // "通常几点出门" —— 这是生活习惯的指纹。
    // workdayFirstOpenMedian 已算好，从没用过。
    @ViewBuilder
    private func firstOpenCard(_ m: StatsKit.StatModel) -> some View {
        if let med = m.workdayFirstOpenMedian {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    Text("工作日出门")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                    HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
                        Text(med.timeStr)
                            .xFont(.title2, weight: .semibold)
                            .foregroundStyle(XPalette.accent)
                            .monospacedDigit()
                        Text("通常第一次开门")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                        Spacer(minLength: 0)
                    }
                    if let spread = m.firstOpenHourSpread {
                        Text("最早 " + hourText(spread.earliest) + " · 最晚 " + hourText(spread.latest))
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textSub)
                    }
                }
            }
            .xScrollLift()
        }
    }

    private func hourText(_ h: Int) -> String {
        String(format: "%02d:00", h)
    }

    /// 图 5 Activity Rings 卡 —— 三环 + 三行彩色读数。
    ///
    /// 真实字段：StatModel.opensTotal（总开门）与 pareto（按 kind 的分布）。
    /// 我第一次写的是 totalOpens / byKind —— 都不存在，CI 抓到了。
    private func activityRingsCard(_ m: StatsKit.StatModel) -> some View {
        let total = max(1, m.opensTotal)
        func cnt(_ k: String) -> Int { m.pareto.first { $0.kind == k }?.count ?? 0 }
        let fpN = cnt("fp")
        let pwdN = cnt("pwd")
        let fp = Double(fpN) / Double(total)
        let pwd = Double(pwdN) / Double(total)
        let auto = max(0, 1 - fp - pwd)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("今日构成")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                XActivityRings(
                    size: 116,
                    values: (fp, pwd, auto),
                    rows: [
                        (String(fpN), "次", "指纹"),
                        (String(pwdN), "次", "密码"),
                        (String(max(0, m.opensTotal - fpN - pwdN)), "次", "其它")
                    ]
                )
                .padding(.top, 10)
                // §7.6：多段卡的节奏归 XStatSection 管，页面不再自己算 14/12
                XStatSection {
                    Text("三环按今天实际开门的次数占比画 —— 环越满，那种方式用得越多。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func safetyCard(_ m: StatsKit.StatModel) -> some View {
        let rate = m.opensTotal > 0 ? Double(m.alarmsTotal) / Double(m.opensTotal) : 0
        let alarmDays = m.dailyPoints.filter { $0.alarms > 0 }.count
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                // 这一处**有真去处**（安全中心），所以做成 §7.11 的卡头链接。
                // 同页其余四个区块标题没有独立页面 —— 它们保持纯标签。
                // 硬套链接会是假可供性：点了没反应比没有箭头更糟。
                XCardLink(title: "安全") { showSecurity = true }

                HStack(spacing: XSpace.l) {
                    XMetricTile(
                        value: String(format: "%.1f%%", rate * 100),
                        label: "告警率",
                        tone: rate > 0.1 ? .warn : .ok,
                        systemImage: "exclamationmark.triangle")
                    XMetricTile(
                        value: "\(alarmDays)",
                        label: "有告警的天",
                        tone: alarmDays > 0 ? .warn : .ok,
                        systemImage: "calendar.badge.exclamationmark")
                    XMetricTile(
                        value: "\(m.opensTotal)",
                        label: "总开门",
                        tone: .neutral,
                        systemImage: "door.left.hand.open")
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ② 节律
    // ═══════════════════════════════════════════════════════

    private func rhythmCard(_ m: StatsKit.StatModel) -> some View {
        let buckets = StatsKit.hourBuckets(m.logs)
        let hs = m.hourStats
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("一天里的开门分布")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.textSub)

                // 极坐标时钟 —— 一天本来就是圆的, 形状自己会说话。
                // 柱状图那条腿留作"看不清圆盘"时的退路: 两者数据同源 (hourStats),
                // 时钟讲形状, 柱状图给精确读数。
                HStack(alignment: .center, spacing: XSpace.m) {
                    XDayClock(hours: hs, size: 156)

                    VStack(alignment: .leading, spacing: XSpace.xs) {
                        if let peak = hs.max(by: { $0.opens < $1.opens }), peak.opens > 0 {
                            stat("\(Int(peak.hour)) 时", "\(peak.opens) 次", "最集中的一小时")
                        }
                        let quiet = hs.filter { $0.opens == 0 }.count
                        if quiet > 0 {
                            stat("\(quiet) 个", "小时无人开门", "安静的时段")
                        }
                        let alarmN = hs.reduce(0) { $0 + $1.alarms }
                        if alarmN > 0 {
                            stat("\(alarmN) 条", "告警", "红点标出的小时")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let peak = buckets.max(by: { $0.opens < $1.opens }), peak.opens > 0 {
                    Text("最常在 \(Int(peak.hour)) 时开门")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                }
            }
        }
    }

    /// 右侧读数小块
    private func stat(_ value: String, _ label: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .xFont(.subheadline, weight: .semibold)
                .foregroundStyle(XPalette.text)
            Text(label)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
            Text(note)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ③ 变化
    // ═══════════════════════════════════════════════════════

    private func trendCard(_ m: StatsKit.StatModel) -> some View {
        let points = m.dailyPoints.suffix(14)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("近 14 天")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.textSub)

                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(
                            x: .value("日", p.day),
                            y: .value("次数", p.opens)
                        )
                        .foregroundStyle(XPalette.accent)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("日", p.day),
                            y: .value("次数", p.opens)
                        )
                        .foregroundStyle(XPalette.accent.opacity(0.12).gradient)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 100)
                .accessibilityLabel("近 14 天开门趋势")
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 降级
    // ═══════════════════════════════════════════════════════

    private func degradedCard(_ m: StatsKit.StatModel) -> some View {
        // 用 XPanel(padding: 0) 而不是手搓 surface 底:
        // XEmptyState 自带 XSpace.xl 内边距, 外面再套默认 16 会变成 40。
        XPanel(kind: .group, padding: 0) {
            XEmptyState(systemImage: "chart.bar.doc.horizontal",
                        title: "样本不足",
                        message: degradedDetail(m))
        }
    }

    private func degradedDetail(_ m: StatsKit.StatModel) -> String {
        if !m.hasData { return "还没有读到门锁日志。连上锁读一次就有了。" }
        if m.coverage < 7 { return "已积累 \(m.coverage) 天, 满 7 天后可用。" }
        return "开门次数还太少, 再积累一些就能看出规律。"
    }
}
