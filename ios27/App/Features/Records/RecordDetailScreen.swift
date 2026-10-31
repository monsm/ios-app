// RecordDetailScreen.swift —— 一条台账记录的全字段面（record.detail）。
//
// 数据从锁内日志缓存 DB.readLogs(mac) 来（经 RecordsSource），用 RecordsRoute.focusID
// 定位到那一条（由时间线点行带过来）。
// 主动作：把这条标为已处置（告警行）或写备注；底部三个出口真跳转（定位 / 搜这类 / 看当天）。
import SwiftUI

struct RecordDetailScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let overlay = RecordsOverlay.shared
    private let route = RecordsRoute.shared

    @State private var noteDraft = ""
    @State private var savedNote = ""
    @State private var entries: [LedgerEntry] = []

    private var entry: LedgerEntry? {
        guard let id = route.focusID else { return entries.first }
        return entries.first { $0.id == id }
    }

    private var lockName: String { app.lock?.name ?? "门锁" }

    private var mac: String { app.lock?.id ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if let entry {
                    momentBlock(entry)
                    if isAlarm(entry) { alarmBlock(entry) }
                    noteBlock(entry)
                    contextBlock(entry)
                    jumpBlock(entry)
                } else {
                    missingBlock
                }
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            load()
        }
        .onChange(of: route.focusID) { _, _ in
            reload()
            load()
        }
    }

    // MARK: - 页头：事件 + 一行状态

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text(entry?.event ?? "记录")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let entry {
                HStack(spacing: T.S.s) {
                    StateDot(tone: entry.tone, word: toneWord(entry))
                    Text(statusLine(entry))
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
    }

    private func statusLine(_ entry: LedgerEntry) -> String {
        let owner = entry.owner ?? "未归属"
        return lockName + " · " + owner + " · " + TimeFormat.ago(entry.at)
    }

    private func toneWord(_ entry: LedgerEntry) -> String {
        switch entry.tone {
        case .ok, .live: return "正常"
        case .attention: return "注意"
        case .critical: return "危险"
        case .neutral: return "记录"
        }
    }

    // MARK: - 时刻与归属（全字段区，数字走 Reading）

    private func momentBlock(_ entry: LedgerEntry) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "这条记录", trailing: "行 " + shortKey(entry))
                FieldRow(label: "时刻", value: TimeDisplay.clock(entry.at), unit: "HH:mm")
                divider
                FieldRow(label: "日期", value: TimeFormat.dayKey(entry.at))
                divider
                FieldRow(label: "归属", value: entry.owner ?? "未归属",
                         tint: entry.owner == nil ? Ink.inkSub : Ink.ink, mono: false)
                divider
                FieldRow(label: "距今", value: TimeFormat.ago(entry.at), mono: false)
                if let detail = entry.detail, !detail.isEmpty {
                    divider
                    FieldRow(label: "说明", value: detail, mono: false)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func shortKey(_ entry: LedgerEntry) -> String {
        entry.id.count > 8 ? String(entry.id.suffix(8)) : entry.id
    }

    private var divider: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: T.Stroke.hair)
    }

    // MARK: - 告警段：严重级 + 处置留痕（真实写入覆盖层）

    private func alarmBlock(_ entry: LedgerEntry) -> some View {
        let disposed = overlay.isDisposed(entry.id)
        return Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "处置")
                HStack(spacing: T.S.s) {
                    StateDot(tone: disposed ? .ok : .critical, word: disposed ? "已处置" : "未处置")
                    Text(disposed ? "已处置" : "未处置")
                        .font(T.F.bodyStrong)
                        .foregroundStyle(disposed ? Ink.ink : State.critical)
                    Spacer(minLength: T.S.s)
                    if let at = overlay.disposedAt(entry.id) {
                        Text(TimeDisplay.clock(at))
                            .font(T.F.stamp)
                            .foregroundStyle(Ink.inkSub)
                            .monospacedDigit()
                    }
                }
                if disposed {
                    SecondaryAction(title: "撤销处置", systemImage: "arrow.uturn.backward") {
                        withAnimation(reduceMotion ? nil : T.M.snap) {
                            overlay.undoDispose(entry.id)
                        }
                    }
                } else {
                    PrimaryAction(title: "标记已处置", systemImage: "checkmark.circle") {
                        withAnimation(reduceMotion ? nil : T.M.snap) {
                            overlay.dispose(entry.id, at: Int64(Date().timeIntervalSince1970 * 1000))
                        }
                    }
                }
                Text("处置只落本机，作为「我看过了」的留痕；不改锁端日志，也不改这条记录的语义。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 备注 / 标旗（与时间线共用同一份本机覆盖层）

    private func noteBlock(_ entry: LedgerEntry) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "备注", trailing: overlay.isFlagged(entry.id) ? "已标异常" : nil)
                Inset {
                    TextField("开门附言 / 备注", text: $noteDraft)
                        .font(T.F.body)
                        .foregroundStyle(Ink.ink)
                        .autocorrectionDisabled()
                        .frame(minHeight: T.Hit.min)
                        .onSubmit { save(entry) }
                }
                HStack(spacing: T.S.s) {
                    Button {
                        withAnimation(reduceMotion ? nil : T.M.snap) { save(entry) }
                    } label: {
                        Text("保存备注")
                            .font(T.F.caption)
                            .foregroundStyle(Ink.ink)
                            .frame(minHeight: T.Hit.min)
                            .padding(.horizontal, T.S.m)
                            .overlay {
                                RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                                    .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines) == savedNote)
                    .accessibilityLabel("保存备注")

                    Toggle(isOn: Binding(
                        get: { overlay.isFlagged(entry.id) },
                        set: { _ in withAnimation(reduceMotion ? nil : T.M.snap) { overlay.toggleFlag(entry.id) } }
                    )) {
                        Text("标为异常")
                            .font(T.F.caption)
                            .foregroundStyle(Ink.ink)
                    }
                    .frame(minHeight: T.Hit.min)
                }
                Text("备注与标旗都是本机标注，不写入门锁，也不进导出 CSV 的列。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 上下文：同一天前后各两条（record.detail 的前后上下文）

    private func contextBlock(_ entry: LedgerEntry) -> some View {
        let dayKey = TimeFormat.dayKey(entry.at)
        let sameDay = entries
            .filter { TimeFormat.dayKey($0.at) == dayKey }
            .sorted { $0.at > $1.at }
        let neighbors = Array(sameDay.filter { $0.id != entry.id }.prefix(4))
        return Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "同一天", trailing: String(sameDay.count) + " 条")
                if neighbors.isEmpty {
                    Text("这一天只有这一条记录。")
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .frame(minHeight: T.Hit.min)
                } else {
                    ForEach(neighbors.indices, id: \.self) { index in
                        if index > 0 { divider }
                        Button {
                            route.focusID = neighbors[index].id
                        } label: {
                            LedgerRow(entry: neighbors[index])
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("切到这条记录")
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 三个回到时间线的出口（真跳转，不是摆样子）

    private func jumpBlock(_ entry: LedgerEntry) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "回到时间线")
                jumpRow("在时间线里定位这条", "scope", "滚到这一条并闪一下") {
                    back(toDay: nil, flash: entry.id)
                }
                divider
                jumpRow("搜这类记录", "magnifyingglass", "用事件词作为检索词") {
                    route.searchSeed = entry.event
                    back(toDay: nil, flash: nil)
                }
                divider
                jumpRow("查看当天全部", "calendar", "把显示范围收到这一天") {
                    back(toDay: TimeFormat.dayKey(entry.at), flash: nil)
                }
                Text("前两个出口不改筛选条件；第三个只收窄显示范围，页顶有「看全部日子」可以退回来。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func jumpRow(_ title: String, _ symbol: String, _ note: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: T.S.m) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.m, weight: .regular))
                    .foregroundStyle(Ink.inkSub)
                    .frame(width: T.Icon.xl, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    Text(title)
                        .font(T.F.body)
                        .foregroundStyle(Ink.ink)
                    Text(note)
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                }
                Spacer(minLength: T.S.s)
                Image(systemName: "chevron.right")
                    .font(T.F.icon(T.Icon.s, weight: .medium))
                    .foregroundStyle(Ink.inkFaint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - 找不到那一条（空态必须给出路）

    private var missingBlock: some View {
        Panel {
            EmptyPanel(
                title: "没有定位到这条记录",
                message: "它可能已经被新的读取覆盖掉了。回台账重新选一条就能看到详情。",
                actionTitle: "回到台账",
                systemImage: "list.bullet.rectangle.portrait"
            ) {
                router.recordsPath = []
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 动作

    private func isAlarm(_ entry: LedgerEntry) -> Bool {
        entry.tone == .attention || entry.tone == .critical
    }

    /// 从锁内日志缓存装载（与台账页同一份来源、同一条行身份）。
    private func reload() {
        guard !mac.isEmpty else {
            entries = []
            return
        }
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

    /// 回台账根并带上落点（定位 / 收窄到某天）。
    /// 先清掉本 Tab 的导航栈再写上下文：request(.dest(.records)) 会把 records 压到栈顶，
    /// 那等于从详情页再压一层详情页，不是「回到时间线」。
    private func back(toDay dayKey: String?, flash id: String?) {
        route.dayFocus = dayKey
        route.flashID = id
        route.focusID = nil
        router.recordsPath = []
    }
}
