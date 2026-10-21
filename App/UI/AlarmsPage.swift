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

    private var alarmList: some View {
        List {
            if !alarms.isEmpty {
                Section {
                    severityOverview
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: XSpace.s, trailing: 0))
            }

            if !alarms.isEmpty {
                Section {
                    ForEach(alarms) { rec in
                        alarmRow(rec, handled: false)
                    }
                } header: {
                    Text("\(alarms.count) 条待处理")
                }
            }

            if !handled.isEmpty {
                Section {
                    if showHandled {
                        ForEach(handled) { rec in
                            alarmRow(rec, handled: true)
                        }
                    } else {
                        Button {
                            withAnimation(XMotion.soft) { showHandled = true }
                        } label: {
                            Text("显示 \(handled.count) 条已处理")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                        }
                    }
                } header: {
                    Text("已处理")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(XPalette.canvas)
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
