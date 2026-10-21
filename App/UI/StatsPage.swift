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

    private var mac: String { app.currentMac }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                if let m = model {
                    if m.isDegraded {
                        degradedCard(m).xScrollLift()
                    } else {
                        safetyCard(m).xScrollLift()
                        rhythmCard(m).xScrollLift()
                        trendCard(m).xScrollLift()
                    }
                } else if !loaded {
                    ProgressView().controlSize(.large)
                        .padding(XSpace.xxl)
                }
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.large)
        .task { if !loaded { load() } }
    }

    private func load() {
        guard !mac.isEmpty else { loaded = true; return }
        model = StatsKit.build(mac: mac, week: 7, window: 30)
        loaded = true
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ① 安全吗
    // ═══════════════════════════════════════════════════════

    private func safetyCard(_ m: StatsKit.StatModel) -> some View {
        let rate = m.opensTotal > 0 ? Double(m.alarmsTotal) / Double(m.opensTotal) : 0
        let alarmDays = m.dailyPoints.filter { $0.alarms > 0 }.count
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("安全")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.textSub)

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
                        .xFont(.caption)
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
                .foregroundStyle(XPalette.textTertiary)
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
        XEmptyState(systemImage: "chart.bar.doc.horizontal",
                    title: "样本不足",
                    message: degradedDetail(m))
            .background(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .fill(XPalette.surface)
            )
    }

    private func degradedDetail(_ m: StatsKit.StatModel) -> String {
        if !m.hasData { return "还没有读到门锁日志。连上锁读一次就有了。" }
        if m.coverage < 7 { return "已积累 \(m.coverage) 天, 满 7 天后可用。" }
        return "开门次数还太少, 再积累一些就能看出规律。"
    }
}
