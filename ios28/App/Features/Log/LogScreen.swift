// LogScreen.swift —— 记录：一天的日光带，加上按天分组的台账。
import SwiftUI

@MainActor
struct LogScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var reading = false
    /// 「只看待查」—— 详情页里点「标记待查」写下的旗标，此前**没有任何界面显示它**，
    /// 用户点了只会看到一句「已标记」，别处找不到。这条筛选就是给旗标一个出口。
    @State private var onlyFlagged = false
    @State private var errorLine: String?
    /// 时间线的渲染窗口（真机审计 2026-11-07）：缓存现在可容整锁历史（~2000 条），
    /// 而 ScreenScroll 是急渲染的 VStack —— 一次摆几千行会卡。默认渲染最新 400 条，
    /// 「显示更早」按 400 递增；数据本身全在缓存里，搜索/洞察不受此窗口限制。
    @State private var timelineLimit = 400

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "记录", subtitle: summary) {
                AnyView(
                    Button { router.push(.insights) } label: {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 16))
                            .foregroundStyle(T.C.ink2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("洞察")
                )
            }

            DisplayLine(text: headline, size: 38)
                .padding(.top, 20)
            Text(detail)
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .padding(.top, 8)

            DayStrip(events: todayEvents)
                .padding(.top, 18)

            FieldInput(placeholder: "搜成员、类型、或「昨天」「最近 7 天」", text: $query, symbol: "magnifyingglass")
                .padding(.top, 18)

            flaggedChip

            if !query.isEmpty {
                Text("\(filtered.count) 条匹配")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            } else if onlyFlagged {
                Text("\(filtered.count) 条待查")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            }

            let groups = grouped
            if groups.isEmpty {
                EmptyNote(line: emptyTitle,
                          detail: emptyDetail,
                          action: (query.isEmpty && !onlyFlagged && !DB.isDecoy) ? "读取日志" : nil,
                          run: (query.isEmpty && !onlyFlagged && !DB.isDecoy) ? { Task { await read() } } : nil)
            } else {
                ForEach(groups) { group in
                    DayHead(time: group.time, title: group.title)
                    ForEach(group.items) { event in
                        Button {
                            router.openEvent(event.id)
                        } label: {
                            EventRow(event: event, showLock: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 渲染窗口之外还有更早的记录 —— 数据在缓存里，按需展开。
                if filtered.count > timelineLimit {
                    GhostButton(title: "显示更早的 \(min(400, filtered.count - timelineLimit)) 条",
                                symbol: "arrow.down.to.line") {
                        timelineLimit += 400
                    }
                    .padding(.top, 6)
                }
            }

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
            }

            // 空壳里不摆读取入口：读取会被数据层拦成空表，按钮等于点了没反应。
            if !DB.isDecoy {
                readCard
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var emptyTitle: String {
        if onlyFlagged { return "没有待查的记录。" }
        return query.isEmpty ? "还没有记录。" : "没有找到。"
    }

    private var emptyDetail: String {
        if onlyFlagged {
            return "在记录详情里点「标记待查」，这条记录就会出现在这里。"
        }
        if DB.isDecoy { return "锁里存着最近的开关门记录。" }
        return query.isEmpty
            ? "读一次锁内日志：谁在什么时候开过门，都会回到这里。"
            : "换个词试试，比如「妈妈」「指纹」「昨天」。"
    }

    private var flaggedChip: some View {
        let count = app.events.filter { $0.flagged }.count
        return ChoiceChip(title: onlyFlagged ? "只看待查" : "待查 \(count)",
                          symbol: onlyFlagged ? "flag.fill" : "flag",
                          on: onlyFlagged,
                          height: 32) {
            onlyFlagged.toggle()
        }
        .padding(.top, 12)
        .opacity(count == 0 && !onlyFlagged ? 0.45 : 1)
    }

    private var summary: String {
        let today = todayEvents
        let opens = today.filter { $0.isOpen }.count
        var parts = ["今天 \(opens) 次"]
        if let last = app.readLogsAt {
            parts.append("上次读取 \(When.ago(last))")
        } else {
            parts.append("还没读过锁")
        }
        return parts.joined(separator: " · ")
    }

    private var headline: String {
        if app.events.isEmpty { return "还没有\n任何记录。" }
        if todayEvents.isEmpty { return "今天\n很安静。" }
        if todayEvents.first(where: { $0.isAlarm }) != nil { return "今天有\n一声警报。" }
        // 「有人来过」只能由**真正的开门**推出。今天只有一条校时/状态广播时，
        // 标题说“有人来过”、正文却是“0 次开门”，自相矛盾。
        if todayEvents.filter({ $0.isOpen }).isEmpty { return "今天\n很安静。" }
        return "今天有人\n来过。"
    }

    private var detail: String {
        if app.events.isEmpty {
            return "锁里存着最近的开关门记录；读一次，它们就会出现在这里。"
        }
        let opened = todayEvents.filter { $0.isOpen }.count
        let people = Set(todayEvents.compactMap { $0.whoName }).count
        let alarms = todayEvents.filter { $0.isAlarm }.count
        var parts = ["\(opened) 次开门"]
        if people > 0 { parts.append("\(people) 位家人") }
        parts.append(alarms == 0 ? "没有异常" : "\(alarms) 条异常")
        return parts.joined(separator: " · ")
    }

    private var todayEvents: [EventItem] {
        let cal = Calendar.current
        return app.events.filter { $0.hasTime && cal.isDateInToday(When.unix($0.time)) }
    }

    private var filtered: [EventItem] {
        var list = app.events
        if onlyFlagged { list = list.filter { $0.flagged } }
        guard !query.isEmpty else { return list }
        let parsed = RecordSearch.parse(query)

        if let member = parsed.member, !member.isEmpty {
            list = list.filter { ($0.whoName ?? "").range(of: member) != nil }
        }
        if let range = parsed.range {
            let from = When.epochSeconds(range.from)
            let to = When.epochSeconds(range.to)
            // 上界是**开区间**：时间短语给的是「当天 00:00 → 次日 00:00」，
            // 用 `<=` 会把次日零点那一秒算进前一天。
            list = list.filter { $0.hasTime && $0.time >= from && $0.time < to }
        }
        if parsed.alarmOnly {
            list = list.filter { $0.isAlarm }
        }
        if let kind = parsed.credKind, !kind.isEmpty {
            // 按引擎的原始代号**精确**匹配（fp / pwd / temp / key）。
            // 原先拿中文说法去比对英文代号（`credential` 是「指纹」，
            // `credKind` 是「fp」），于是搜「指纹」永远 0 条 ——
            // 而输入框的占位符恰恰写着「搜成员、类型」。
            list = list.filter { $0.credKind == kind }
        }
        for term in parsed.must where !term.isEmpty {
            list = list.filter { face($0).range(of: term) != nil }
        }
        for term in parsed.not where !term.isEmpty {
            list = list.filter { face($0).range(of: term) == nil }
        }
        return list
    }

    private func face(_ event: EventItem) -> String {
        [event.typeName, event.lockName, event.whoName ?? "", event.credential, event.note ?? ""].joined(separator: " ")
    }

    private struct DayGroup: Identifiable {
        let id: String
        let time: Int64
        let title: String
        let items: [EventItem]
    }

    private var grouped: [DayGroup] {
        var order: [String] = []
        var map: [String: [EventItem]] = [:]
        var undated: [EventItem] = []
        // 只渲染窗口内的条目（见 timelineLimit 注释）；搜索计数等仍用完整的 filtered。
        for event in filtered.prefix(timelineLimit) {
            // 锁端没读到时钟的记录**没有日期** —— 它们单独成组，排在最后。
            guard event.hasTime else {
                undated.append(event)
                continue
            }
            let key = When.dayKey(event.time)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(event)
        }
        var out: [DayGroup] = order.compactMap { key in
            guard let items = map[key], let first = items.first else { return nil }
            return DayGroup(id: key, time: first.time, title: When.dayTitle(first.time), items: items)
        }
        if !undated.isEmpty {
            out.append(DayGroup(id: "无日期", time: 0, title: "没有日期", items: undated))
        }
        return out
    }

    private var readCard: some View {
        Button {
            Task { await read() }
        } label: {
            HStack(spacing: 12) {
                GlyphTile(symbol: "arrow.down.circle", kind: .cool, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading ? "正在读门锁记录…" : "从门锁读一次")
                        .type(T.F.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(T.C.ink)
                    Text(app.readLogsAt == nil ? "逐页读取，最多 100 条" : "上次 \(When.ago(app.readLogsAt))")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                Spacer()
                if reading { ProgressView().tint(T.C.brass) }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
    }

    private func read() async {
        guard !reading else { return }
        reading = true
        errorLine = nil
        let result = await app.readLogs()
        reading = false
        // 失败要说话：`readLogs()` 失败时只写 `app.lastError`，这一屏从不显示它 ——
        // 于是点「从门锁读一次」失败后，卡片只是回到原样，像是什么都没发生。
        if result == nil {
            errorLine = app.lastError ?? "没能读到门锁记录。"
        }
    }
}

// MARK: - 一天的日光带

@MainActor
struct DayStrip: View {
    var events: [EventItem]

    private var bins: [Int] {
        let cal = Calendar.current
        var out = [Int](repeating: 0, count: 24)
        for event in events where event.isOpen {
            let hour = cal.component(.hour, from: When.unix(event.time))
            if hour >= 0, hour < 24 { out[hour] += 1 }
        }
        return out
    }

    private var hasAlarm: [Bool] {
        let cal = Calendar.current
        var out = [Bool](repeating: false, count: 24)
        for event in events where event.isAlarm {
            let hour = cal.component(.hour, from: When.unix(event.time))
            if hour >= 0, hour < 24 { out[hour] = true }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(T.C.hairStrong)
                    .frame(height: 0.5)
                    .offset(y: -22)

                ForEach(bins.indices, id: \.self) { hour in
                    if bins[hour] > 0 || hasAlarm[hour] {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(hasAlarm[hour] ? T.C.danger : T.C.brass)
                            .frame(width: 2.5,
                                   height: bins[hour] > 0 ? CGFloat(min(42, 8 + bins[hour] * 9)) : 8)
                            .offset(x: width * (CGFloat(hour) + 0.5) / 24 - 1.25, y: -22)
                    }
                }

                HStack {
                    ForEach(["00", "06", "12", "18", "24"], id: \.self) { label in
                        Text(label)
                            .type(T.F.kicker)
                            .foregroundStyle(T.C.ink3)
                        if label != "24" { Spacer() }
                    }
                }
            }
        }
        .frame(height: 82)
        .accessibilityElement()
        .accessibilityLabel("今天的活动分布")
    }
}
