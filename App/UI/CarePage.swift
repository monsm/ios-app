//
//  CarePage.swift
//  保养页 · 全新重写 (2026-10-21)
//
//  门里「这台锁」→ 保养的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 CareViews (496 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 周期 Section + 清洁月历 + 历史过滤 + 换电 + 应急钥匙 + 环境
//
//  新版: 一张"该做什么"清单
//    · 顶部: 下次保养还剩多久
//    · 中部: 待办项 (换电 / 清洁 / 年检), 按紧迫度排
//    · 底部: 保养历史 (折叠)
//
//  设计原则:
//    · 保养页的价值是"提醒我该做什么", 不是"记录我做过什么"
//    · 待办项按紧迫度排序, 最急的在最上
//    · 历史默认折叠
//

import SwiftUI

/// 保养页
struct CarePage: View {
    @EnvironmentObject private var app: AppState

    @State private var care = CareState()
    @State private var showHistory = false
    @State private var loaded = false

    private var mac: String { app.currentMac }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                periodCard
                todoCard
                historyRow
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("维护与保养")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { if !loaded { reload() } }
    }

    private func reload() {
        care = BatteryCare.care(mac)
        loaded = true
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 周期卡
    // ═══════════════════════════════════════════════════════

    private var periodCard: some View {
        let days = daysUntilCare
        return XPanel(kind: .hero, tone: days <= 0 ? .warn : .ok) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: days <= 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: XIcon.lg, weight: .medium))
                        .foregroundStyle(days <= 0 ? XPalette.warn : XPalette.ok)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(periodTitle(days))
                            .vkFont(.title3, weight: .semibold)
                            .foregroundStyle(XPalette.text)
                        Text(periodDetail(days))
                            .vkFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                    }
                }

                if days <= 0 {
                    Button("记录本次保养") {
                        markCare()
                    }
                    .buttonStyle(XPrimaryButtonStyle())
                }
            }
        }
    }

    private var daysUntilCare: Int {
        guard care.lastCareAt > 0 else { return 0 }
        let period = BatteryCare.carePeriodDays(opens30d: 0)
        let elapsed = Int((Date().timeIntervalSince1970 * 1000 - care.lastCareAt) / 86_400_000)
        return period - elapsed
    }

    private func periodTitle(_ days: Int) -> String {
        if care.lastCareAt <= 0 { return "还没记录过保养" }
        if days <= 0 { return "该保养了" }
        if days <= 7 { return "\(days) 天后该保养" }
        return "保养状态良好"
    }

    private func periodDetail(_ days: Int) -> String {
        if care.lastCareAt <= 0 { return "记录一次保养, 之后会按周期提醒。" }
        if days <= 0 { return "已超过建议周期 \(-days) 天。" }
        return "下次保养还剩 \(days) 天。"
    }

    private func markCare() {
        care.lastCareAt = Date().timeIntervalSince1970 * 1000
        BatteryCare.saveCare(mac, care)
        XHaptics.success()
        app.showToast("已记录本次保养")
        reload()
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 待办
    // ═══════════════════════════════════════════════════════

    private var todoCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                if let battery = batteryTodo {
                    todoRow(battery)
                    XHairline(inset: XSpace.card)
                }
                todoRow(cleanTodo)
                if let yearly = yearlyTodo {
                    XHairline(inset: XSpace.card)
                    todoRow(yearly)
                }
            }
        }
    }

    private struct Todo {
        let icon: String
        let title: String
        let detail: String
        let tone: XToneColor
    }

    private var batteryTodo: Todo? {
        guard let p = DB.readStatus(mac)?.powerLevel, p >= 0 else { return nil }
        if p <= 20 {
            return Todo(icon: "battery.25", title: "换电池",
                        detail: "电量 \(p)%, 建议尽快更换",
                        tone: p <= 10 ? .danger : .warn)
        }
        return nil
    }

    private var cleanTodo: Todo {
        let days = care.lastCareAt > 0
            ? Int((Date().timeIntervalSince1970 * 1000 - care.lastCareAt) / 86_400_000)
            : 999
        if days > 90 {
            return Todo(icon: "sparkles", title: "清洁锁体",
                        detail: days > 900 ? "还没记录过" : "距上次 \(days) 天",
                        tone: .neutral)
        }
        return Todo(icon: "sparkles", title: "清洁锁体",
                    detail: "距上次 \(days) 天, 状态良好", tone: .ok)
    }

    private var yearlyTodo: Todo? {
        guard !care.yearlyBattDay.isEmpty else { return nil }
        return Todo(icon: "calendar", title: "年度换电提醒",
                    detail: "已设为每年 \(care.yearlyBattDay)", tone: .neutral)
    }

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: XSpace.m) {
            Image(systemName: todo.icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(todo.tone == .neutral ? XPalette.textSub : todo.tone.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .vkFont(.body)
                    .foregroundStyle(XPalette.text)
                Text(todo.detail)
                    .vkFont(.caption)
                    .foregroundStyle(todo.tone == .ok ? XPalette.ok : XPalette.textSub)
            }
            Spacer(minLength: 0)
        }
        .padding(XSpace.card)
        .accessibilityElement(children: .combine)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 历史
    // ═══════════════════════════════════════════════════════

    private var historyRow: some View {
        Button {
            showHistory = true
        } label: {
            XRow(systemImage: "clock.arrow.circlepath", title: "保养历史",
                 subtitle: "查看做过的保养记录", showsChevron: true)
            .padding(XSpace.card)
            .background(XPalette.surface,
                        in: RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                MaintenanceView()
                    .environmentObject(app)
                    .navigationTitle("维护与保养")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showHistory = false }
                        }
                    }
            }
        }
    }
}

