//
//  AlarmsPage.swift
//  告警中心 · 全新重写 (2026-10-21)
//
//  门里「事件」→ 告警的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 AlarmCenterView (817 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 告警列表 + 分类筛选 + 处置动作 + 上下文 + 时间线。
//
//  新版: 一条按紧迫度排序的告警流
//    · 未处理在最上, 已处理折叠在底
//    · 每条: 级别色条 + 类型 + 时间 + 处置按钮
//    · 处置用滑动 (系统 swipeActions), 不弹菜单
//
//  设计原则:
//    · 告警三通道: 色 + 图标 + 文字 (不只靠颜色)
//    · 处置动作就地完成, 不跳页
//    · 已处理默认折叠, 减少噪音
//

import SwiftUI

/// 告警中心
struct AlarmsPage: View {
    @EnvironmentObject private var app: AppState

    @State private var recs: [Rec] = []
    @State private var loaded = false
    @State private var showHandled = false

    private var macs: [String] { DB.keychains().map { $0.mac } }

    var body: some View {
        Group {
            if !loaded {
                ScrollView {
                    XSkeleton(blocks: 3, blockHeight: 96)
                }
                .scrollDisabled(true)
            } else if alarms.isEmpty && handled.isEmpty {
                emptyState
            } else {
                alarmList
            }
        }
        .background(XPalette.canvas)
        .navigationTitle("告警")
        .navigationBarTitleDisplayMode(.large)
        .task { if !loaded { load() } }
        .refreshable { load() }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private func load() {
        recs = RecordSearch.buildRecs(macs: macs)
        loaded = true
    }

    /// 未处理告警
    private var alarms: [Rec] {
        recs.filter { rec in
            guard rec.alarm else { return false }
            return !RecordOverlay.isFlagged(rec.mac, rec.key)
        }
    }

    /// 已处理告警
    private var handled: [Rec] {
        recs.filter { rec in
            guard rec.alarm else { return false }
            return RecordOverlay.isFlagged(rec.mac, rec.key)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 视图
    // ═══════════════════════════════════════════════════════

    // ── 主告警卡（仅当有紧急级未处理告警）──
    //
    // M5 形态: 告警页的核心是**紧迫感**，不是清单。
    // 所以把最紧急的一条从列表里提出来，占整块，
    // 并显示"已持续多久"—— 时间压力是紧迫感的来源。
    @ViewBuilder
    private var primaryAlarm: some View {
        if let top = alarms.first(where: { AlarmMeta.level($0.type) == 3 }) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Text(AlarmMeta.levelName(top.type))
                        .xFont(.caption2, weight: .bold)
                        .foregroundStyle(XPalette.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(XPalette.danger))
                    if let dur = elapsedText(top) {
                        Text("已持续 \(dur)")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.danger)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(top.typeName.isEmpty ? "告警" : top.typeName)
                        .xFont(.title3, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                    Text("\(shortTime(top.timeStr)) · \(top.lockName) · 未处理")
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                }

                HStack(spacing: XSpace.s) {
                    Button {
                        markHandled(top)
                        XHaptics.trigger.impactOccurred()
                    } label: {
                        Text("知道了")
                            .xFont(.subheadline, weight: .semibold)
                            .foregroundStyle(XPalette.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                                .fill(XPalette.danger))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("标记已知悉")
                }
            }
            .padding(XSpace.card)
            .background {
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .fill(XPalette.danger.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                            .strokeBorder(XPalette.danger.opacity(0.35), lineWidth: 1)
                    )
            }
        }
    }

    /// 告警已持续多久
    ///
    /// 解析 timeStr 得到时刻，算到现在的差值。
    /// 解析失败返回 nil —— 不硬编造一个数字。
    /// 告警已持续多久
    ///
    /// 复用 RecordSearch.dateOf(Rec) —— 它已经把 timeStr 解析成 Date
    /// 并钉了公历 (WeekCal.gregorian)。
    /// 自己再写一遍 DateFormatter 会被 lint 拦下（我第一版就是这样）。
    /// 解析失败返回 nil —— 不硬编造一个数字。
    private func elapsedText(_ rec: Rec) -> String? {
        guard let d = RecordSearch.dateOf(rec) else { return nil }
        return humanize(Date().timeIntervalSince(d))
    }

    private func humanize(_ sec: TimeInterval) -> String? {
        guard sec > 60 else { return nil }
        let m = Int(sec / 60)
        if m < 60 { return "\(m) 分钟" }
        let h = m / 60
        if h < 24 { return "\(h) 小时 \(m % 60) 分" }
        return "\(h / 24) 天"
    }

    private var alarmList: some View {
        // M5 重做: List + Section → ScrollView + XPanel 卡片流
        //
        // 组头信息（"N 条待处理" / "已处理"）保留为卡内小标题 ——
        // 那是用户扫读时的锚点，不能丢。
        ScrollView {
            VStack(spacing: XSpace.l) {
                if !alarms.isEmpty {
                    severityOverview
                        .padding(.top, XSpace.s)
                }

                // 主告警：最高级未处理告警占整块 —— 紧迫感的核心
                primaryAlarm

                if !alarms.isEmpty {
                    XPanel(kind: .group, padding: 0) {
                        VStack(spacing: 0) {
                            groupHeader("\(alarms.count) 条待处理", tone: XPalette.warn)
                            ForEach(Array(alarms.enumerated()), id: \.element.id) { idx, rec in
                                alarmRow(rec, handled: false)
                                if idx < alarms.count - 1 {
                                    Divider().overlay(XPalette.hairline)
                                        .padding(.leading, XSpace.card + 28 + XSpace.s)
                                }
                            }
                        }
                    }
                }

                if !handled.isEmpty {
                    XPanel(kind: .group, padding: 0) {
                        VStack(spacing: 0) {
                            groupHeader("已处理 \(handled.count)", tone: XPalette.textSub)
                            if showHandled {
                                ForEach(Array(handled.enumerated()), id: \.element.id) { idx, rec in
                                    alarmRow(rec, handled: true)
                                    if idx < handled.count - 1 {
                                        Divider().overlay(XPalette.hairline)
                                            .padding(.leading, XSpace.card + 28 + XSpace.s)
                                    }
                                }
                            } else {
                                Button {
                                    withAnimation(XMotion.soft) { showHandled = true }
                                } label: {
                                    HStack {
                                        Text("显示 \(handled.count) 条已处理")
                                            .xFont(.footnote)
                                            .foregroundStyle(XPalette.textSub)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: XIcon.xs, weight: .semibold))
                                            .foregroundStyle(XPalette.textTertiary)
                                    }
                                    .padding(.horizontal, XSpace.card)
                                    .frame(minHeight: XHit.min)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.bottom, XSpace.xxl)
        }
        .background(XPalette.canvas)
    }

    /// 卡内组头 —— 取代原来 Section 的 header
    private func groupHeader(_ text: String, tone: Color) -> some View {
        HStack {
            Text(text)
                .xFont(.caption, weight: .medium)
                .foregroundStyle(tone)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XSpace.card)
        .padding(.top, XSpace.m)
        .padding(.bottom, XSpace.s)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 严重度概览
    // ═══════════════════════════════════════════════════════

    /// 待处理告警按三级严重度分布。
    ///
    /// 告警页最该先回答的是"有多严重", 而不是"有几条"。
    /// 原来只有每行左边一根 3pt 色条, 要一行行看才拼得出全貌;
    /// 这里用一条比例横条把三级一次说完, 数字跟在后面。
    private var severityOverview: some View {
        let lv3 = alarms.filter { AlarmMeta.level($0.type) == 3 }.count
        let lv2 = alarms.filter { AlarmMeta.level($0.type) == 2 }.count
        let lv1 = alarms.count - lv3 - lv2
        let total = max(alarms.count, 1)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                // 比例条
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if lv3 > 0 {
                            segment(width: geo.size.width * CGFloat(lv3) / CGFloat(total),
                                    color: XPalette.danger)
                        }
                        if lv2 > 0 {
                            segment(width: geo.size.width * CGFloat(lv2) / CGFloat(total),
                                    color: XPalette.warn)
                        }
                        if lv1 > 0 {
                            segment(width: geo.size.width * CGFloat(lv1) / CGFloat(total),
                                    color: XPalette.warn.opacity(0.55))
                        }
                    }
                }
                .frame(height: 8)
                .animation(XMotion.standard, value: alarms.count)   // 标记已处理后比例条平滑收缩
                .animation(XMotion.standard, value: alarms.count)   // 标记已处理后比例条平滑收缩
                .accessibilityHidden(true)

                // 三级读数
                HStack(spacing: XSpace.l) {
                    severityItem("严重", lv3, XPalette.danger)
                    severityItem("警告", lv2, XPalette.warn)
                    severityItem("提示", lv1, XPalette.warn.opacity(0.55))
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("待处理告警 \(alarms.count) 条, 严重 \(lv3), 警告 \(lv2), 提示 \(lv1)")
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: max(width - 2, 3))
    }

    private func severityItem(_ label: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: XSpace.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("\(label) \(n)")
                .xFont(.caption, weight: .medium)
                .foregroundStyle(n > 0 ? XPalette.text : XPalette.textTertiary)
                .monospacedDigit()
                .contentTransition(.numericText())   // 标记已处理后数字滚动
                .contentTransition(.numericText())   // 标记已处理后数字滚动
        }
    }

    private func alarmRow(_ rec: Rec, handled: Bool) -> some View {
        HStack(spacing: XSpace.m) {
            // 级别色条
            RoundedRectangle(cornerRadius: 2)
                .fill(levelColor(rec).opacity(handled ? 0.3 : 1))
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: XSpace.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: XIcon.xs, weight: .semibold))
                        .foregroundStyle(levelColor(rec).opacity(handled ? 0.5 : 1))
                        .accessibilityHidden(true)
                    Text(rec.typeName.isEmpty ? "告警" : rec.typeName)
                        .xFont(.body, weight: handled ? .regular : .medium)
                        .foregroundStyle(handled ? XPalette.textSub : XPalette.text)
                        .lineLimit(1)
                }
                Text("\(shortTime(rec.timeStr)) · \(rec.lockName)")
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
            }

            Spacer(minLength: 0)

            if !handled {
                Button {
                    markHandled(rec)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: XIcon.md, weight: .medium))
                        .foregroundStyle(XPalette.accent)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("标记已处理")
            }
        }
        .padding(.vertical, XSpace.xxs)
        .opacity(handled ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rec.typeName), \(shortTime(rec.timeStr)), \(handled ? "已处理" : "待处理")")
    }

    private var emptyState: some View {
        XEmptyState(systemImage: "checkmark.shield",
                    title: "没有告警",
                    message: "所有记录都正常。")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private func markHandled(_ rec: Rec) {
        _ = RecordOverlay.toggleFlag(rec.mac, rec.key)
        XHaptics.trigger.impactOccurred()
        withAnimation(XMotion.soft) {
            // 触发重算
            recs = recs
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 辅助
    // ═══════════════════════════════════════════════════════

    private func levelColor(_ rec: Rec) -> Color {
        let lvl = AlarmMeta.level(rec.type)
        switch lvl {
        case 3: return XPalette.danger
        case 2: return XPalette.warn
        default: return XPalette.warn.opacity(0.7)
        }
    }

    private func shortTime(_ full: String) -> String {
        guard full.count >= 16 else { return full }
        let start = full.index(full.startIndex, offsetBy: 11)
        let end = full.index(full.startIndex, offsetBy: 16)
        return String(full[start..<end])
    }
}
