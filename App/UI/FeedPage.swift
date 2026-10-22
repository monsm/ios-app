//
//  FeedPage.swift
//  动态消息 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 跨锁事件流, 告警用左侧光条竖穿行高
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + 小圆点 + 两行文字
//
//  新版: 一张卡片式事件流
//    · 每条一行高 72pt, 左侧 4pt 竖条 (告警橙/普通铜)
//    · 事件名 17pt, 副行是 时间 · 锁名
//    · 告警行: 左侧竖条发光 + 图标, 三通道
//    · 顶部一条"共 N 条动态"的统计条
//

import SwiftUI

/// 动态消息页
struct FeedPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddDevice = false
    @State private var filterAlarm = false

    struct FeedRow: Identifiable {
        var id: String
        var text: String
        var time: String
        var lockName: String
        var warn: Bool
    }

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            if rows.isEmpty {
                emptyState
            } else {
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("动态") {
                    headerBar.xScrollLift()
                    // 按天分组 —— 原来是一长条平铺，看不出"这是今天的还是上周的"。
                    // 动态页的核心是"最近发生了什么"，日期是最基本的坐标系。
                    LazyVStack(spacing: XSpace.m, pinnedViews: []) {
                        ForEach(groupedDays, id: \.day) { g in
                            VStack(alignment: .leading, spacing: XSpace.xs) {
                                dayHeader(g.day, count: g.rows.count, alarms: g.rows.filter { $0.warn }.count)
                                VStack(spacing: XSpace.s) {
                                    ForEach(g.rows) { r in
                                        feedRow(r)
                                    }
                                }
                            }
                        }
                    }
        }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    XToggle("只看告警", isOn: $filterAlarm)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选")
            }
        }
        .sheet(isPresented: $showAddDevice) {
            NavigationStack {
                AddLockPage()
                    .environmentObject(app)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 头部
    // ═══════════════════════════════════════════════════════

    private var headerBar: some View {
        let total = displayRows.count
        let alarmCount = displayRows.filter { $0.warn }.count
        let normalCount = total - alarmCount
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(alignment: .firstTextBaseline, spacing: XSpace.xs) {
                    Text("\(total)")
                        .xFont(.title2, weight: .semibold, design: .rounded)
                        .foregroundStyle(XPalette.text)
                    Text("条动态")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                    Spacer(minLength: 0)
                    if filterAlarm {
                        XStatusPill(text: "只看告警", tone: .warn, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                // 告警占比横条 —— 一眼看出这一屏里有多少是坏事
                if total > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            if normalCount > 0 {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(XPalette.accent.opacity(0.45))
                                    .frame(width: max(geo.size.width * CGFloat(normalCount) / CGFloat(total) - 2, 3))
                            }
                            if alarmCount > 0 {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(XPalette.warn)
                                    .frame(width: max(geo.size.width * CGFloat(alarmCount) / CGFloat(total) - 2, 3))
                            }
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)

                    HStack(spacing: XSpace.l) {
                        legend("常规", normalCount, XPalette.accent.opacity(0.45))
                        legend("告警", alarmCount, XPalette.warn)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(total) 条动态, 其中 \(alarmCount) 条告警")
    }

    private func legend(_ label: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: XSpace.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("\(label) \(n)")
                .xFont(.caption, weight: .medium)
                .foregroundStyle(n > 0 ? XPalette.text : XPalette.textSub)
                .monospacedDigit()
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 行
    // ═══════════════════════════════════════════════════════

    private func feedRow(_ r: FeedRow) -> some View {
        HStack(spacing: 0) {
            // 左侧竖条 (告警橙 / 普通铜)
            RoundedRectangle(cornerRadius: 2)
                .fill(r.warn ? XPalette.warn : XPalette.accent.opacity(0.6))
                .frame(width: 4)
                // 告警条的「亮」用**辉光**（径向渐变），不用投影 —— §6.3 注脚只允许两处阴影，
                // 而 §7.8 把指示物的发光明确成辉光。竖条外侧垫一层同色径向光。
                .background {
                    if r.warn {
                        Rectangle()
                            .fill(XGradient.glow(XPalette.warn))
                            .frame(width: 60)
                            .blur(radius: 12)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: XSpace.m) {
                VStack(alignment: .leading, spacing: XSpace.xxs) {
                    HStack(spacing: XSpace.xs) {
                        if r.warn {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: XIcon.xs, weight: .semibold))
                                .foregroundStyle(XPalette.warn)
                                .accessibilityHidden(true)
                        }
                        Text(r.text)
                            .xFont(.body, weight: r.warn ? .medium : .regular)
                            .foregroundStyle(XPalette.text)
                            .lineLimit(2)
                    }
                    HStack(spacing: XSpace.xs) {
                        Text(r.time)
                            .xFontExact(.caption.monospacedDigit())
                            .foregroundStyle(XPalette.textSub)
                        Text("·")
                            .foregroundStyle(XPalette.textSub)
                        Text(r.lockName)
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, XSpace.card)
            .padding(.vertical, XSpace.m)
        }
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                .fill(XPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                        .strokeBorder(r.warn ? XPalette.warn.opacity(0.3) : XPalette.hairline,
                                      lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(r.warn ? "告警: \(r.text), \(r.time), \(r.lockName)"
                                   : "\(r.text), \(r.time), \(r.lockName)")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 空态
    // ═══════════════════════════════════════════════════════

    private var emptyState: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "bell.slash")
                .font(.system(size: XMetric.decorIcon(64), weight: .ultraLight))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            Text("还没有动态")
                .xFont(.title3, weight: .semibold)
                .foregroundStyle(XPalette.text)
            Text("连接门锁读取记录后, 这里会汇总全部门锁的开门与告警事件。")
                .xFont(.subheadline)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, XSpace.xxl)
            Button("去添加门锁") { showAddDevice = true }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    /// 按天分组（保持 displayRows 的降序）
    private var groupedDays: [(day: String, rows: [FeedRow])] {
        var order: [String] = []
        var map: [String: [FeedRow]] = [:]
        for r in displayRows {
            let day = String(r.time.prefix(10))
            if map[day] == nil { order.append(day); map[day] = [] }
            map[day]?.append(r)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// 日期头：今天 / 昨天 / 具体日期 + 条数 + 告警数
    private func dayHeader(_ day: String, count: Int, alarms: Int) -> some View {
        HStack(spacing: XSpace.xs) {
            Text(dayLabel(day))
                .xFont(.footnote, weight: .semibold)
                .foregroundStyle(XPalette.textSub)
            Text(String(count) + " 条")
                .xFontExact(.caption2.monospacedDigit())
                .foregroundStyle(XPalette.textTertiary)
            if alarms > 0 {
                HStack(spacing: 2) {
                    // 规范 §10：图标最小 12pt（原 8pt 低于档位下限）。
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: XIcon.xs, weight: .semibold))
                    Text(String(alarms))
                        .xFontExact(.caption2.monospacedDigit())
                }
                .foregroundStyle(XPalette.warn)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dayLabel(day) + " " + String(count) + " 条, " + String(alarms) + " 条告警")
    }

    /// "yyyy-MM-dd" → 今天 / 昨天 / M 月 d 日
    private func dayLabel(_ day: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = WeekCal.gregorian
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: day) else { return day }
        let cal = WeekCal.gregorian
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.calendar = WeekCal.gregorian
        out.dateFormat = "M 月 d 日"
        return out.string(from: d)
    }

    private var displayRows: [FeedRow] {
        filterAlarm ? rows.filter { $0.warn } : rows
    }

    private var rows: [FeedRow] {
        var out = [FeedRow]()
        for kc in DB.keychains() {
            let devName = kc.name.isEmpty
                ? PidMap.productName(kc.pid) + " …" + kc.mac.suffix(4)
                : kc.name
            for l in HotCache.recent(kc.mac) {
                let warn = StatsKit.alarmTypes.contains(l.type)
                out.append(FeedRow(
                    id: kc.mac + "#\(l.idxRaw)",
                    text: l.typeName,
                    time: l.lockTimeStr,
                    lockName: devName,
                    warn: warn))
            }
        }
        return out.sorted { $0.time > $1.time }
    }
}
