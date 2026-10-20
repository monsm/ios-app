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
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            return !RecordSearch.isFlagged(rec.mac, rec.key)
        }
    }

    /// 已处理告警
    private var handled: [Rec] {
        recs.filter { rec in
            guard rec.alarm else { return false }
            return RecordSearch.isFlagged(rec.mac, rec.key)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 视图
    // ═══════════════════════════════════════════════════════

    private var alarmList: some View {
        List {
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
                                .vkFont(.footnote)
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
                        .vkFont(.body, weight: handled ? .regular : .medium)
                        .foregroundStyle(handled ? XPalette.textSub : XPalette.text)
                        .lineLimit(1)
                }
                Text("\(shortTime(rec.timeStr)) · \(rec.lockName)")
                    .vkFont(.caption)
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
        VStack(spacing: XSpace.m) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: XIcon.xl, weight: .light))
                .foregroundStyle(XPalette.ok)
                .accessibilityHidden(true)
            Text("没有告警")
                .vkFont(.headline)
                .foregroundStyle(XPalette.text)
            Text("所有记录都正常")
                .vkFont(.subheadline)
                .foregroundStyle(XPalette.textSub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(XSpace.xl)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private func markHandled(_ rec: Rec) {
        _ = RecordSearch.toggleFlag(rec.mac, rec.key)
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
        let lvl = RecordSearch.level(rec.type)
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
