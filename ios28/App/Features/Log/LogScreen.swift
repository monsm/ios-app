// LogScreen.swift —— 记录：一天的日光带，加上按天分组的台账。
import SwiftUI

@MainActor
struct LogScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var reading = false

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "记录", subtitle: summary) {
                AnyView(
                    Button { router.push(.insights) } label: {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 16))
                            .foregroundStyle(T.C.ink2)
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

            if !query.isEmpty {
                Text("\(filtered.count) 条匹配")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            }

            let groups = grouped
            if groups.isEmpty {
                EmptyNote(line: query.isEmpty ? "还没有记录。" : "没有找到。",
                          detail: query.isEmpty
                            ? "读一次锁内日志：谁在什么时候开过门，都会回到这里。"
                            : "换个词试试，比如「妈妈」「指纹」「昨天」。",
                          action: query.isEmpty ? "读取日志" : nil,
                          run: query.isEmpty ? { Task { await read() } } : nil)
            } else {
                ForEach(groups) { group in
                    DayHead(time: group.time)
                    ForEach(group.items) { event in
                        Button {
                            router.openEvent(event.id)
                        } label: {
                            EventRow(event: event, showLock: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            readCard
        }
        .toolbar(.hidden, for: .navigationBar)
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
        return app.events.filter { cal.isDateInToday(When.unix($0.time)) }
    }

    private var filtered: [EventItem] {
        guard !query.isEmpty else { return app.events }
        let parsed = RecordSearch.parse(query)
        var list = app.events

        if let member = parsed.member, !member.isEmpty {
            list = list.filter { ($0.whoName ?? "").range(of: member) != nil }
        }
        if let range = parsed.range {
            let from = Int64(range.from.timeIntervalSince1970)
            let to = Int64(range.to.timeIntervalSince1970)
            list = list.filter { $0.time >= from && $0.time <= to }
        }
        if parsed.alarmOnly {
            list = list.filter { $0.isAlarm }
        }
        if let kind = parsed.credKind, !kind.isEmpty {
            list = list.filter { $0.credential.range(of: kind) != nil || $0.typeName.range(of: kind) != nil }
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
        let items: [EventItem]
    }

    private var grouped: [DayGroup] {
        var order: [String] = []
        var map: [String: [EventItem]] = [:]
        for event in filtered {
            let key = When.dayKey(event.time)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(event)
        }
        return order.compactMap { key in
            guard let items = map[key], let first = items.first else { return nil }
            return DayGroup(id: key, time: first.time, items: items)
        }
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
        _ = await app.readLogs()
        reading = false
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
