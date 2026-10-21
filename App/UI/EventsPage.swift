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
    /// 筛选视图（用户自己存下来的查询条件）与最近搜索。
    /// 这两份数据一直有读写 API，但全仓没有任何界面入口 —— 属于"功能存在、够不着"。
    @State private var namedViews: [RecordSearch.NamedView] = []
    @State private var recentSearches: [String] = []
    @State private var saveName = ""
    @State private var showSaveDialog = false

    private var mac: String { app.currentMac }

    var body: some View {
        VStack(spacing: 0) {
            if loaded && !(namedViews.isEmpty && recentSearches.isEmpty) {
                savedChips
            }
            Group {
            if !loaded {
                ScrollView {
                    XSkeleton(blocks: 3, blockHeight: 84)
                }
                .scrollDisabled(true)
            } else if filtered.isEmpty {
                emptyState
            } else {
                eventList
            }
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
                    XToggle("只看告警", isOn: $alarmOnly)
                    Divider().overlay(XPalette.hairline)
                    Button("刷新") { load() }
                    Divider().overlay(XPalette.hairline)
                    Button("存为筛选视图") {
                        saveName = search
                        showSaveDialog = true
                    }
                    .disabled(search.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !recentSearches.isEmpty {
                        Button("清空最近搜索", role: .destructive) {
                            RecordSearch.clearHistory()
                            recentSearches = []
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选")
            }
        }
        .onSubmit(of: .search) {
            RecordSearch.pushHistory(search)
            recentSearches = RecordSearch.history()
        }
        .alert("存为筛选视图", isPresented: $showSaveDialog) {
            TextField("名字，例如「本周指纹」", text: $saveName)
            Button("保存") { saveView() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("保存后可以一键回到这组筛选条件。")
        }
        .task { if !loaded { load() } }
        .refreshable { load() }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private func load() {
        let macs = mac.isEmpty ? DB.keychains().map { $0.mac } : [mac]
        recs = RecordSearch.buildRecs(macs: macs)
        namedViews = RecordSearch.namedViews()
        recentSearches = RecordSearch.history()
        loaded = true
    }

    private var filtered: [Rec] {
        var out = recs
        if alarmOnly { out = out.filter { $0.alarm } }
        let raw = search.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return out }
        // ═══ 用仓里已经写好的查询引擎，不再自己手搓 substring ═══
        //
        // RecordSearch.search 支持「+必须词 / -排除词 / 时间短语 / 成员 / 凭证维度」，
        // 但此前**零调用** —— 这一页用的是四字段 substring，把那些能力全浪费了。
        // 空查询时 Query.parse 产生空 must/not，search 直接返回全部，
        // 所以"搜索框一空就把记录隐藏"这种反向故障不会发生（已核对实现）。
        var filters = RecordSearch.QueryFilters()
        filters.alarmOnly = alarmOnly
        return RecordSearch.search(recs: out,
                                   query: RecordSearch.Query.parse(raw),
                                   filters: filters)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 筛选视图 / 最近搜索
    // ═══════════════════════════════════════════════════════

    /// 横向胶囊条：左边是用户存下来的筛选视图，右边是最近搜过的词。
    ///
    /// 为什么要做这一条：`RecordSearch` 里 saveNamedView / namedViews /
    /// pushHistory / history 一整套读写都在，但界面上从来没有入口 ——
    /// 用户每次都要重新敲一遍同样的条件。功能在，就是够不着。
    private var savedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XSpace.s) {
                ForEach(namedViews) { v in
                    Button {
                        search = v.text
                        alarmOnly = v.filters.alarmOnly
                        XHaptics.tick.impactOccurred()
                    } label: {
                        chipLabel(v.name, glyph: "bookmark.fill", tone: XPalette.accentText)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            RecordSearch.deleteNamedView(v.name)
                            namedViews = RecordSearch.namedViews()
                        } label: { Label("删除这个视图", systemImage: "trash") }
                    }
                    .accessibilityLabel("筛选视图 \(v.name)")
                }
                ForEach(recentSearches, id: \.self) { q in
                    Button {
                        search = q
                        XHaptics.tick.impactOccurred()
                    } label: {
                        chipLabel(q, glyph: "clock.arrow.circlepath", tone: XPalette.textSub)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            RecordSearch.removeHistory(q)
                            recentSearches = RecordSearch.history()
                        } label: { Label("从最近搜索里移除", systemImage: "trash") }
                    }
                    .accessibilityLabel("最近搜索 \(q)")
                }
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.s)
        }
        .scrollIndicators(.hidden)
    }

    private func chipLabel(_ text: String, glyph: String, tone: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: glyph)
                .font(.system(size: XIcon.xs, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .xFont(.system(.caption, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, XSpace.m)
        .padding(.vertical, 7)
        .xPlate(XPalette.surface, .capsule)
    }

    private func saveView() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var f = RecordSearch.QueryFilters()
        f.alarmOnly = alarmOnly
        RecordSearch.saveNamedView(name: name,
                                   text: search.trimmingCharacters(in: .whitespaces),
                                   filters: f,
                                   scopeAll: mac.isEmpty)
        namedViews = RecordSearch.namedViews()
        showSaveDialog = false
        XHaptics.success()
        app.showToast("已保存筛选视图「\(name)」")
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
        // 真时间轴 —— 不是卡片堆。
        //
        // 竖线由每组的 .overlay(alignment: .leading) 画一条通长线，
        // 这样组内所有节点共用一条线，节点之间不会断。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(grouped, id: \.day) { group in
                    daySection(group)
                }
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.top, XSpace.s)
            .padding(.bottom, XSpace.xxl)
        }
        .background(XPalette.canvas)
    }

    /// 一天一组：日期头 + 时间轴
    private func daySection(_ group: (day: String, items: [Rec])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader(group)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, rec in
                    timelineRow(rec)
                }
            }
            // 竖线：画在所有节点左侧，从第一个节点到最后一行
            // 位置 = 时间列宽 42 + 间距 12 + 圆点半径 4.5
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(XPalette.hairline)
                    .frame(width: 1)
                    .padding(.leading, 42 + XSpace.m + 4)
                    .padding(.top, 6)
                    .padding(.bottom, XSpace.l)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, XSpace.s)
    }

    /// 当日组头 —— 日期 + 条数 + 告警数
    ///
    /// 与原来 Section header 完全同口径，只是换了个容器。
    private func dayHeader(_ group: (day: String, items: [Rec])) -> some View {
        HStack(spacing: XSpace.xs) {
            Text(dayLabel(group.day))
                .xFont(.footnote, weight: .medium)
                .foregroundStyle(XPalette.textSub)
            Text("\(group.items.count) 条")
                .xFont(.caption2.monospacedDigit())
                .foregroundStyle(XPalette.textTertiary)
            let alarms = group.items.filter { $0.alarm }.count
            if alarms > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(alarms)")
                        .xFont(.caption2.monospacedDigit())
                }
                .foregroundStyle(XPalette.warn)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, XSpace.m)
        .padding(.bottom, XSpace.m)
    }

    /// 时间轴上的一个节点
    ///
    /// 与原来的卡片行不同 —— 这是**真时间轴**:
    ///   左侧: 时间（等宽数字，右对齐）
    ///   中间: 竖线 + 节点圆点（告警红 / 正常绿）
    ///   右侧: 事件内容
    ///
    /// 竖线由外层 VStack 的背景画，不在这里画 ——
    /// 否则每个节点各画一段，接缝处会断。
    /// 时间轴节点颜色 —— 与凭证类型色一致
    ///
    /// 告警优先（红），保养次之（青），其余按凭证类型：
    ///   fp 青 / pwd 紫 / temp 黄 / key 蓝 / 未知 绿
    private func nodeColor(_ rec: Rec) -> Color {
        if rec.alarm { return XPalette.danger }
        if rec.care { return XPalette.warn }
        switch rec.kind {
        case "fp": return XPalette.kindFp
        case "pwd": return XPalette.textSub
        case "temp": return XPalette.warn
        case "key": return XPalette.ok
        default: return XPalette.ok
        }
    }

    /// 事件类型短标签（时间轴右侧用）
    private func kindTag(_ rec: Rec) -> String? {
        if rec.alarm { return "告警" }
        if rec.care { return "保养" }
        switch rec.kind {
        case "fp": return "指纹"
        case "pwd": return "密码"
        case "temp": return "临时码"
        case "key": return "钥匙"
        default: return nil
        }
    }

    /// 归属可信度 —— Rec.provable 是 "temp"/"unique"
    ///
    /// 这个字段一直存在但时间轴没用。它说明"这条记录归属到某人"是靠什么推的:
    ///   unique → 唯一凭证，归属可信
    ///   temp   → 临时码，可能多人共用，只能"约"
    private func provableNote(_ rec: Rec) -> String? {
        guard let p = rec.provable, !p.isEmpty else { return nil }
        if p == "unique" { return nil }   // 可信就不打扰
        return "归属约"
    }

    private func timelineRow(_ rec: Rec) -> some View {
        HStack(alignment: .top, spacing: XSpace.m) {
            // 时间
            Text(shortTime(rec.timeStr))
                .xFont(.caption.monospacedDigit())
                .foregroundStyle(XPalette.textTertiary)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 3)

            // 节点圆点（竖线由父级画）
            //
            // 原来只有两色（告警红 / 正常绿），但事件有 5 类 ——
            // 时间轴上完全看不出"这是指纹开的还是密码开的"。
            // 现在按 kind 着色，与凭证页的类型色一致。
            Circle()
                .fill(nodeColor(rec))
                .frame(width: 9, height: 9)
                .overlay(
                    Circle().stroke(XPalette.canvas, lineWidth: 3)
                )
                .padding(.top, 6)
                .accessibilityHidden(true)

            // 内容
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: XSpace.xs) {
                    Text(verbText(rec))
                        .xFont(.body)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(2)
                    // 类型标签：现在所有事件都有，不只告警
                    if let tag = kindTag(rec) {
                        Text(tag)
                            .xFont(.caption2, weight: .semibold)
                            .foregroundStyle(nodeColor(rec))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(nodeColor(rec).opacity(0.16))
                            )
                    }
                    // 归属可信度：只有不可信时才提示
                    if let note = provableNote(rec) {
                        Text(note)
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textTertiary)
                    }
                }
                if let sub = subText(rec) {
                    Text(sub)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, XSpace.l)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(rec))
    }

    private var emptyState: some View {
        XEmptyState(systemImage: "list.bullet.rectangle",
                    title: search.isEmpty ? "还没有记录" : "没有匹配的事件",
                    message: search.isEmpty ? "连上锁后读取门锁日志。" : "换个关键词试试。")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
