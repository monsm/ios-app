//
//  EventsPage.swift
//  记录页 · 全新重写 (2026-10-21)
//
//  门里「事件」域的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 RecordsView (3351 行) 的根本区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 检索态 + 筛选 chip 行 + 情绪行 + 状态条 + 时间线(组头吸顶/
//        连击合并/动词/年份/农历/凌晨) + 成员过滤 + 详情翻页 + 告警多选面板
//        —— 一个"数据浏览器"。
//
//  新版: 一条按天分组的流
//    · 今天在最上, 日期做组头 (吸顶)
//    · 每行: 时间 + 动词 + 谁 (可证才署名)
//    · 告警行用左侧色条, 不换行样式
//    · 筛选收进 toolbar 的 Menu
//    · 无情绪行、无农历、无连击合并
//
//  设计原则:
//    · 时间在左, 事件在右 —— 符合阅读顺序
//    · 可证明才署名, 否则"未署名" (F4: Attribution 多数不可证)
//    · 告警不靠颜色单一通道: 色条 + 图标 + 文字
//

import SwiftUI

/// 记录页 —— 门里「事件」
struct EventsPage: View {
    @EnvironmentObject private var app: AppState

    @State private var recs: [Rec] = []
    @State private var loaded = false
    @State private var search = ""
    @State private var searchActive = false
    @State private var alarmOnly = false

    private var mac: String { app.currentMac }

    var body: some View {
        Group {
            if !loaded {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .background(XPalette.canvas)
        .navigationTitle("事件")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, isPresented: $searchActive, prompt: "搜索事件")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { StatsPage().environmentObject(app) } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("统计")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AlarmsPage().environmentObject(app) } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .accessibilityLabel("告警")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    VariantToggle("只看告警", isOn: $alarmOnly)
                    Divider()
                    Button("刷新") { load() }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选")
            }
        }
        .task { if !loaded { load() } }
        .refreshable { load() }
        .destined(.records)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private func load() {
        let macs = mac.isEmpty ? DB.keychains().map { $0.mac } : [mac]
        recs = RecordSearch.buildRecs(macs: macs)
        loaded = true
    }

    private var filtered: [Rec] {
        var out = recs
        if alarmOnly { out = out.filter { $0.alarm } }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            out = out.filter { r in
                r.typeName.localizedCaseInsensitiveContains(q)
                    || (r.whoName ?? "").localizedCaseInsensitiveContains(q)
                    || r.cred.localizedCaseInsensitiveContains(q)
                    || r.timeStr.localizedCaseInsensitiveContains(q)
            }
        }
        return out
    }

    /// 按天分组 (今天在最上)
    private var grouped: [(day: String, items: [Rec])] {
        var order: [String] = []
        var map: [String: [Rec]] = [:]
        for r in filtered {
            let day = String(r.timeStr.prefix(10))
            if map[day] == nil { order.append(day); map[day] = [] }
            map[day]?.append(r)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 视图
    // ═══════════════════════════════════════════════════════

    private var eventList: some View {
        List {
            ForEach(grouped, id: \.day) { group in
                Section {
                    ForEach(group.items) { rec in
                        eventRow(rec)
                    }
                } header: {
                    Text(dayLabel(group.day))
                        .vkFont(.footnote, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(XPalette.canvas)
    }

    private func eventRow(_ rec: Rec) -> some View {
        HStack(spacing: XSpace.m) {
            // 告警色条 (色 + 图标双通道, 不只靠颜色)
            RoundedRectangle(cornerRadius: 2)
                .fill(rec.alarm ? XPalette.warn : Color.clear)
                .frame(width: 3)
                .accessibilityHidden(true)

            // 时间
            Text(shortTime(rec.timeStr))
                .vkFont(.caption.monospacedDigit())
                .foregroundStyle(XPalette.textSub)
                .frame(width: 46, alignment: .trailing)

            // 事件
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: XSpace.xs) {
                    if rec.alarm {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(XPalette.warn)
                            .accessibilityHidden(true)
                    }
                    Text(verbText(rec))
                        .vkFont(.body)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(2)
                }
                if let sub = subText(rec) {
                    Text(sub)
                        .vkFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, XSpace.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(rec))
    }

    private var emptyState: some View {
        VStack(spacing: XSpace.m) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: XIcon.xl, weight: .light))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            Text(search.isEmpty ? "还没有记录" : "没有匹配的事件")
                .vkFont(.headline)
                .foregroundStyle(XPalette.text)
            Text(search.isEmpty ? "连上锁后读取门锁日志" : "换个关键词试试")
                .vkFont(.subheadline)
                .foregroundStyle(XPalette.textSub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(XSpace.xl)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 文案
    // ═══════════════════════════════════════════════════════

    /// 动词短语 —— 可证署名才写"谁", 否则只写动作 (F4)
    private func verbText(_ rec: Rec) -> String {
        let action = actionWord(rec)
        if let who = rec.whoName, !who.isEmpty {
            return "\(who) \(action)"
        }
        return action
    }

    private func actionWord(_ rec: Rec) -> String {
        if !rec.failMsg.isEmpty { return rec.failMsg }
        if rec.care { return rec.typeName }
        if rec.alarm { return rec.typeName }
        switch rec.kind {
        case "fp": return "用指纹开门"
        case "pwd": return "用密码开门"
        case "temp": return "用临时码开门"
        case "key": return "用数字钥匙开门"
        default: return rec.typeName.isEmpty ? "操作" : rec.typeName
        }
    }

    private func subText(_ rec: Rec) -> String? {
        var parts: [String] = []
        if !rec.cred.isEmpty { parts.append(rec.cred) }
        if !rec.lockName.isEmpty { parts.append(rec.lockName) }
        if rec.whoId == nil && rec.kind != nil { parts.append("未署名") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func accessibilityText(_ rec: Rec) -> String {
        var s = shortTime(rec.timeStr) + " " + verbText(rec)
        if let sub = subText(rec) { s += ", " + sub }
        if rec.alarm { s = "告警, " + s }
        return s
    }

    private func shortTime(_ full: String) -> String {
        // "yyyy-MM-dd HH:mm:ss" -> "HH:mm"
        guard full.count >= 16 else { return full }
        let start = full.index(full.startIndex, offsetBy: 11)
        let end = full.index(full.startIndex, offsetBy: 16)
        return String(full[start..<end])
    }

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
        out.dateFormat = "M 月 d 日 EEEE"
        return out.string(from: d)
    }
}
