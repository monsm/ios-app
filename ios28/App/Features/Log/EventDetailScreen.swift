// EventDetailScreen.swift —— 一条记录就是一张回执。
import SwiftUI

@MainActor
struct EventDetailScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    /// 这段备注是**哪一条**记录的备注。原先只有一个 `loaded` 布尔，
    /// 于是「同一天」里点另一条记录时，页面实例没换（路由把同一条 path 换了个 id），
    /// 备注框里还留着上一条的字 —— 用户再动一下键盘，就把上一条的备注写到了新记录上。
    ///
    /// 顺带记下每条记录**当前**的备注：投影里的 `event.note` 是重载那一刻的快照，
    /// 用户刚敲的字不在里面；切走再切回来时若照投影重载，键盘上刚敲的字就消失了。
    @State private var notes: [String: String] = [:]
    @State private var toast: String?

    private var event: EventItem? {
        guard let id = router.pendingEventID else { return nil }
        return app.events.first { $0.id == id }
    }

    var body: some View {
        ScreenScroll {
            if let event {
                content(event)
            } else {
                EmptyNote(line: "这条记录不在了。", detail: "它可能来自另一把锁，或日志被重新读过。", action: "返回") { dismiss() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func content(_ event: EventItem) -> some View {
        NavRow(kicker: "记录 / 详情", back: { dismiss() })

        DaylightPane(height: 258, showSill: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Kicker(text: event.lockName, dot: true, tint: T.C.ink2)
                    Spacer()
                    if event.isAlarm {
                        Badge(text: "异常", kind: .danger)
                    } else if event.provable != nil {
                        Badge(text: "可证明归属", kind: .ok)
                    } else {
                        Badge(text: "已记录", kind: .calm)
                    }
                }
                Spacer()
                Text(event.hasTime ? When.clock(event.time) : "无日期")
                    .type(T.F.heroTime)
                    .tracking(-1)
                    .foregroundStyle(event.hasTime ? T.C.ink : T.C.ink3)
                Text(event.typeName)
                    .type(T.F.callout)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 6)
                Spacer().frame(height: 18)
            }
            .padding(24)
        }
        .padding(.top, 10)

        ReadingRow(items: [
            (label: "日期", value: event.hasTime ? When.dayTitle(event.time) : "锁端没有时钟", unit: nil),
            (label: "成员", value: event.whoName ?? "未归属", unit: nil),
            (label: "方式", value: event.credential.isEmpty ? "—" : event.credential, unit: nil),
        ])
        .padding(.top, 26)

        if let diff = event.diff, !diff.isEmpty {
            GlassSurface(radius: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("锁端明细")
                        .type(T.F.kicker)
                        .foregroundStyle(T.C.ink3)
                    Text(diff)
                        .type(T.F.mono)
                        .foregroundStyle(T.C.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 16)
        }

        SectionHead(index: "01", title: "备注")
        FieldInput(placeholder: "只写在本机，不同步到锁", text: $note)
            .onChange(of: note) { _, newValue in
                guard let event else { return }
                notes[event.id] = newValue
                RecordOverlay.setNote(event.mac, rowKey(event), String(newValue.prefix(60)))
            }
            .onAppear { loadNote() }
            .onChange(of: event.id) { _, _ in loadNote() }

        SectionHead(index: "02", title: "处置")
        HStack(spacing: 8) {
            dispositionButton(event, verdict: "已处理")
            dispositionButton(event, verdict: "误报")
            Button {
                // `toggleFlag` 返回的是**新的**状态。原先把这个返回值扔了，
                // toast 永远写「已标记」—— 取消标记时也这么说。
                let now = RecordOverlay.toggleFlag(event.mac, rowKey(event))
                toast = now ? "已标记为待查" : "已取消待查"
                app.reloadEvents()
            } label: {
                Text(event.flagged ? "取消待查" : "标记待查")
                    .type(T.F.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(event.flagged ? T.C.danger : T.C.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(T.C.glass, in: Capsule())
                    .overlay { Capsule().strokeBorder(T.C.glassEdge, lineWidth: 0.5) }
            }
            .buttonStyle(PressStyle())
        }

        if let verdict = currentVerdict(event) {
            Text("已标记为「\(verdict.verdict)」 · \(When.ago(Int64(verdict.at * 1000)))")
                .type(T.F.caption)
                .foregroundStyle(T.C.ok)
                .padding(.top, 10)
        }

        SectionHead(index: "03", title: "同一天")
        let sameDay = app.events.filter {
            $0.id != event.id && When.dayKey($0.time) == When.dayKey(event.time)
        }.prefix(4)
        if sameDay.isEmpty {
            Text("这一天没有别的记录。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.vertical, 8)
        } else {
            ForEach(Array(sameDay)) { other in
                Button { router.openEvent(other.id) } label: {
                    EventRow(event: other, showLock: false)
                }
                .buttonStyle(.plain)
            }
        }

        if let toast {
            Text(toast)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 10)
        }
    }

    private func rowKey(_ event: EventItem) -> String { String(event.id.split(separator: "#").last ?? "") }

    /// 把备注框对齐到当前这条记录。换了记录就换内容 ——
    /// 否则上一次的字会跟着下一次输入落到新记录上。
    private func loadNote() {
        guard let event else { return }
        if let cached = notes[event.id] {
            note = cached
            return
        }
        note = event.note ?? ""
        notes[event.id] = note
    }

    private func currentVerdict(_ event: EventItem) -> RecordSearch.Disposition? {
        RecordOverlay.dispositions(event.mac)[RecordOverlay.oid(mac: event.mac, rowKey: rowKey(event))]
    }

    private func dispositionButton(_ event: EventItem, verdict: String) -> some View {
        Button {
            RecordOverlay.setDisposition(event.mac, rowKey(event),
                                         RecordSearch.Disposition(at: Date().timeIntervalSince1970, verdict: verdict))
            toast = "已标记为「\(verdict)」"
            app.reloadEvents()
        } label: {
            Text(verdict)
                .type(T.F.caption)
                .fontWeight(.medium)
                .foregroundStyle(currentVerdict(event)?.verdict == verdict ? .white : T.C.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(currentVerdict(event)?.verdict == verdict ? T.C.brass : T.C.glass, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(currentVerdict(event)?.verdict == verdict ? .clear : T.C.glassEdge, lineWidth: 0.5)
                }
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - 洞察

@MainActor
struct InsightsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var month: [EventItem] {
        let cutoff = Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
        return app.events.filter { Double($0.time) >= cutoff }
    }

    private struct CountRow: Identifiable {
        let id: String
        let count: Int
    }

    private var byKind: [CountRow] {
        var map: [String: Int] = [:]
        for event in month where event.isOpen {
            map[event.typeName, default: 0] += 1
        }
        return map.sorted { $0.value > $1.value }.prefix(4).map { CountRow(id: $0.key, count: $0.value) }
    }

    private var people: [CountRow] {
        var map: [String: Int] = [:]
        for event in month where event.isOpen {
            guard let who = event.whoName, !who.isEmpty else { continue }
            map[who, default: 0] += 1
        }
        return map.sorted { $0.value > $1.value }.prefix(5).map { CountRow(id: $0.key, count: $0.value) }
    }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "记录 / 洞察", back: { dismiss() })

            DisplayLine(text: "这三十天，\n门开了 \(month.filter { $0.isOpen }.count) 次。", size: 34)
                .padding(.top, 16)
            Text("只统计有记录的部分；锁内日志按页读取，越久远越可能还没读回来。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)
                .lineSpacing(3)

            SectionHead(index: "01", title: "按方式")
            ForEach(byKind) { row in
                HStack {
                    Text(row.id)
                        .type(T.F.callout)
                        .foregroundStyle(T.C.ink)
                    Spacer()
                    Text("\(row.count)")
                        .type(T.F.monoBig)
                        .foregroundStyle(T.C.ink)
                    Text("次")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                .padding(.vertical, 11)
            }

            SectionHead(index: "02", title: "按成员")
            if people.isEmpty {
                Text("还没有可证明归属的开门。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.vertical, 8)
            } else {
                ForEach(people) { row in
                    HStack {
                        Text(row.id)
                            .type(T.F.callout)
                            .foregroundStyle(T.C.ink)
                        Spacer()
                        Text("\(row.count)")
                            .type(T.F.monoBig)
                            .foregroundStyle(T.C.ink)
                        Text("次")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                    }
                    .padding(.vertical, 11)
                }
            }

            SectionHead(index: "03", title: "异常")
            let alarms = month.filter { $0.isAlarm }
            if alarms.isEmpty {
                Text("这三十天没有异常记录。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ok)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(alarms.prefix(6))) { event in
                    EventRow(event: event, showLock: true)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
