// RecordDetailHomeScreen.swift —— 记录详情（V8 设计语言）
//
// 与 RecordDetailScreen 的能力对齐：全字段面（时刻/日期/归属/距今/说明）、告警处置留痕、
// 备注（写本机覆盖层）、同一天的其他记录、三个回到时间线的出口、找不到时的空态。
import SwiftUI

struct RecordDetailHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let overlay = RecordsOverlay.shared
    private let route = RecordsRoute.shared

    @State private var noteDraft = ""
    @State private var savedNote = ""
    @State private var entries: [LedgerEntry] = []
    @State private var showDisposeUndo = false

    private var entry: LedgerEntry? {
        guard let id = route.focusID else { return entries.first }
        return entries.first { $0.id == id }
    }

    private var lockName: String { app.lock?.name ?? "门锁" }
    private var mac: String { app.lock?.id ?? "" }

    var body: some View {
        VPage(title: entry?.event ?? "记录详情", lead: entry.map { statusLine($0) } ?? "没有定位到这条记录。") {
            EmptyView()
        } content: {
            if let entry {
                momentCard(entry)
                if isAlarm(entry) { alarmCard(entry) }
                noteCard(entry)
                contextCard(entry)
                jumpCard(entry)
            } else {
                VEmpty(
                    title: "没有定位到这条记录",
                    reason: "它可能已经被新的读取覆盖掉了。回台账重新选一条就能看到详情。",
                    actionTitle: "回到台账"
                ) { router.recordsPath = [] }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload(); load() }
        .onChange(of: route.focusID) { _, _ in reload(); load() }
    }

    private func statusLine(_ entry: LedgerEntry) -> String {
        let owner = entry.owner ?? "未归属"
        return lockName + " · " + owner + " · " + TimeFormat.ago(entry.at)
    }

    private func toneWord(_ tone: Tone) -> String {
        switch tone {
        case .ok, .live: return "正常"
        case .attention: return "注意"
        case .critical: return "危险"
        case .neutral: return "记录"
        }
    }

    /// 与记录页同一个映射（V8.D 数据色），同一条记录在两页同一个颜色。
    private func toneTint(_ tone: Tone) -> Color {
        switch tone {
        case .ok, .live: return V8.D.openEvent
        case .attention: return V8.D.failure
        case .critical: return V8.D.alarm
        case .neutral: return V8.D.system
        }
    }

    /// 这条记录所在那一天，0–23 点各有多少条。
    /// 2026-11-05（图形化 · 最小切片）：只做一件事，不排序、不拼字符串，
    /// 把可能出错的面缩到最小。
    private func dayBuckets(_ entry: LedgerEntry) -> [Double] {
        let cal = WeekCal.gregorian
        // LedgerEntry.at 是毫秒 epoch（Int64），不是 Date —— 必须走 TimeFormat.date 转换。
        let day = cal.startOfDay(for: TimeFormat.date(entry.at))
        var out = [Double](repeating: 0, count: 24)
        for item in entries {
            let when = TimeFormat.date(item.at)
            guard cal.startOfDay(for: when) == day else { continue }
            let hour = cal.component(.hour, from: when)
            if hour >= 0, hour < 24 { out[hour] += 1 }
        }
        return out
    }

    private func momentCard(_ entry: LedgerEntry) -> some View {
        VCard2 {
            VCardHead(eyebrow: "这条记录", statement: entry.event, trailing: "行 " + shortKey(entry))
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "时刻", tagTint: V8.C.ink4, title: TimeDisplay.clock(entry.at), value: "")
                VDotRule()
                VDataRow(tag: "日期", tagTint: V8.C.ink4, title: TimeFormat.dayKey(entry.at), value: "")
                VDotRule()
                if entry.owner == nil, !claimableMembers.isEmpty {
                    Button {
                        // 归属认领入口：由弹层选择（保持 44pt 行高）
                        claimTarget = entry
                        showClaim = true
                    } label: {
                        VDataRow(tag: "归属", tagTint: V8.C.ink4, title: "未归属 · 点这里认人", value: "")
                    }
                    .buttonStyle(.plain)
                } else {
                    VDataRow(tag: "归属", tagTint: V8.C.ink4, title: entry.owner ?? "未归属", value: "")
                }
                VDotRule()
                VDataRow(tag: "距今", tagTint: V8.C.ink4, title: TimeFormat.ago(entry.at), value: "")
                if let detail = entry.detail, !detail.isEmpty {
                    VDotRule()
                    VDataRow(tag: "说明", tagTint: V8.C.ink4, title: detail, value: "")
                }
            }
            .padding(.top, V8.S.gapS)
            // 2026-11-05（图形化）：这一页原来全是文字行。加一条当天 24 小时分布，
            // 光标落在本条记录的小时上 —— 轴标签由 VSpark 自带，不再另写一行。
            VSpark(values: dayBuckets(entry), tint: V8.C.accentFill,
                   cursor: WeekCal.gregorian.component(.hour, from: TimeFormat.date(entry.at)),
                   axis: .hours24)
                .padding(.top, V8.S.gapM)
        }
        .confirmationDialog("把这条记录认给谁？", isPresented: $showClaim, titleVisibility: .visible) {
            ForEach(claimableMembers) { m in
                Button(m.name) { if let e = claimTarget { claim(e, to: m) } }
            }
            Button("取消", role: .cancel) { }
        }
    }

    @State private var claimTarget: LedgerEntry?
    @State private var showClaim = false

    private func shortKey(_ entry: LedgerEntry) -> String {
        entry.id.count > 8 ? String(entry.id.suffix(8)) : entry.id
    }

    private func alarmCard(_ entry: LedgerEntry) -> some View {
        let disposed = overlay.isDisposed(entry.id)
        return VCard2 {
            VCardHead(eyebrow: "处置", statement: disposed ? "已处置" : "未处置",
                      trailing: overlay.disposedAt(entry.id).map { TimeDisplay.clock($0) })
            VDivider2()
                .padding(.top, V8.S.gapM)
            if disposed {
                VNavRow(title: "撤销处置", detail: "恢复为未处置") {
                    withAnimation(reduceMotion ? nil : V8.M.snap) { overlay.undoDispose(entry.id) }
                }
            } else {
                VNavRow(title: "标记已处置", detail: "落本机，不改锁端日志") {
                    withAnimation(reduceMotion ? nil : V8.M.snap) {
                        overlay.dispose(entry.id, at: Int64(Date().timeIntervalSince1970 * 1000))
                    }
                }
            }
            Text("处置只落本机，作为「我看过了」的留痕；不改锁端日志，也不改这条记录的语义。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noteCard(_ entry: LedgerEntry) -> some View {
        VCard2 {
            VCardHead(eyebrow: "备注", statement: overlay.isFlagged(entry.id) ? "已标异常" : "本机附言")
            VDivider2()
                .padding(.top, V8.S.gapM)
            TextField("开门附言 / 备注", text: $noteDraft)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .autocorrectionDisabled()
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .onSubmit { save(entry) }
            HStack(spacing: V8.S.gapS) {
                Button { withAnimation(reduceMotion ? nil : V8.M.snap) { save(entry) } } label: {
                    Text("保存备注")
                        .font(V8.T.tab)
                        .foregroundStyle(savedNote == noteDraft.trimmingCharacters(in: .whitespacesAndNewlines) ? V8.C.ink4 : V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .buttonStyle(.plain)
                .disabled(savedNote == noteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                .accessibilityLabel("保存备注")
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func contextCard(_ entry: LedgerEntry) -> some View {
        let dayKey = TimeFormat.dayKey(entry.at)
        let sameDay = entries.filter { TimeFormat.dayKey($0.at) == dayKey }.sorted { $0.at > $1.at }
        let neighbors = Array(sameDay.filter { $0.id != entry.id }.prefix(4))
        return VCard2 {
            VCardHead(eyebrow: "同一天", statement: "\(sameDay.count) 条")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if neighbors.isEmpty {
                Text("这一天只有这一条记录。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .frame(minHeight: V8.H.min)
                    .padding(.top, V8.S.gapS)
            } else {
                VStack(spacing: 0) {
                    ForEach(neighbors) { item in
                        Button { route.focusID = item.id } label: {
                            VDataRow(tag: TimeDisplay.clock(item.at), tagTint: toneTint(item.tone),
                                     title: item.event, detail: CredentialOrg.ownerName(item.owner), value: "")
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("切到这条记录")
                        if item.id != neighbors.last?.id { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func jumpCard(_ entry: LedgerEntry) -> some View {
        VCard2 {
            VCardHead(eyebrow: "回到时间线", statement: "三个出口")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "在时间线里定位这条", detail: "滚到这一条并闪一下") {
                    back(toDay: nil, flash: entry.id)
                }
                VDotRule()
                VNavRow(title: "搜这类记录", detail: "用事件词作为检索词") {
                    route.searchSeed = entry.event
                    back(toDay: nil, flash: nil)
                }
                VDotRule()
                VNavRow(title: "查看当天全部", detail: "把显示范围收到这一天") {
                    back(toDay: TimeFormat.dayKey(entry.at), flash: nil)
                }
            }
            .padding(.top, V8.S.gapS)
            Text("前两个出口不改筛选条件；第三个只收窄显示范围，页顶有「看全部日子」可以退回来。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isAlarm(_ entry: LedgerEntry) -> Bool {
        entry.tone == .attention || entry.tone == .critical
    }

    private var claimableMembers: [MemberCard] {
        app.members.filter { !$0.archived }
    }

    private func claim(_ entry: LedgerEntry, to member: MemberCard) {
        guard !mac.isEmpty else { return }
        let key = entry.id.contains("#") ? String(entry.id.split(separator: "#").last ?? "") : entry.id
        MemberHub.claim(mac, logKey: String(key), memberId: member.id)
        reload()
    }

    private func reload() {
        guard !mac.isEmpty else { entries = []; return }
        overlay.hydrate(mac: mac)
        entries = RecordsSource.load(mac: mac, lockName: lockName, members: app.members).entries
    }

    private func load() {
        guard let entry else { return }
        let stored = overlay.note(for: entry.id)
        noteDraft = stored
        savedNote = stored
    }

    private func save(_ entry: LedgerEntry) {
        overlay.setNote(noteDraft, for: entry.id)
        savedNote = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func back(toDay dayKey: String?, flash id: String?) {
        route.dayFocus = dayKey
        route.flashID = id
        route.focusID = nil
        router.recordsPath = []
    }
}
