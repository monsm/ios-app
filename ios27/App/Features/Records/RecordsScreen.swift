// RecordsScreen.swift —— 台账（Tab 3）。本屏把门锁事件流读成一本可检索的仪器台账。
//
// 数据从锁内日志缓存 DB.readLogs(mac) 来（经 RecordsSource 映射成台账条目）；
// 真链路是 cmd16 翻页拉取，见 read() 的 TODO(engine)。
// 主动作：点一行进「记录详情」；读取与导出在工具栏。数字全走 Reading，时间全走 TimeFormat。
import SwiftUI

struct RecordsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private let overlay = RecordsOverlay.shared
    private let route = RecordsRoute.shared

    @State private var query = ""
    @State private var scope: LedgerScope = .all
    @State private var member = ""
    @State private var entries: [LedgerEntry] = []
    /// 锁端没回时刻、无法定位到某一天的条数。单独报，不混进时间线。
    @State private var untimed = 0
    @State private var readAt: Int64?
    @State private var reading = false
    @State private var readNote: String?
    @State private var flash: String?

    // MARK: - 派生（全部是纯函数，见 RecordsModels.swift）

    private var filtered: [LedgerEntry] {
        LedgerFilter.apply(entries,
                           scope: scope,
                           member: member,
                           query: LedgerQuery(query),
                           dayFocus: route.dayFocus)
    }

    /// 当前锁的 mac（台账缓存按锁分族）。没有锁就没有台账。
    private var mac: String { app.lock?.id ?? "" }

    private var groups: [LedgerDayGroup] {
        LedgerDayGroup.make(LedgerGrouping.group(filtered))
    }

    /// 生效条件数。刻意不含「只看某天」——那是显示范围，不是筛选条件。
    private var conditions: Int {
        var count = 0
        if scope != .all { count += 1 }
        if !member.isEmpty { count += 1 }
        if !LedgerQuery(query).isEmpty { count += 1 }
        return count
    }

    private var memberOptions: [String] {
        [""] + LedgerFilter.members(in: entries)
    }

    /// 读数区三项。告警数非零才染注意色 —— 状态色只随真实状态出现。
    private var readings: [ReadingGrid.Item] {
        let alarms = LedgerFilter.alarmCount(filtered)
        return [
            .init(label: "开门", value: String(LedgerFilter.opens(in: filtered).count), unit: "次"),
            .init(label: "告警", value: String(alarms), unit: "条",
                  tint: alarms > 0 ? State.attention : Ink.ink),
            .init(label: "覆盖", value: String(LedgerFilter.dayCount(filtered)), unit: "天")
        ]
    }

    private var lockName: String { app.lock?.name ?? "门锁" }

    // MARK: - 页

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: T.S.l) {
                    header
                    if app.lock == nil {
                        noLockBlock
                    } else {
                        filterPanel
                        chips
                        if let day = route.dayFocus { dayFocusBlock(day) }
                        if reading {
                            busyBlock
                        } else if entries.isEmpty {
                            emptyLedgerBlock
                        } else if filtered.isEmpty {
                            emptyFilteredBlock
                        } else {
                            densityPanel
                            timeline
                        }
                        if readNote != nil { noteBlock }
                        overlayBlock
                    }
                }
                .padding(.vertical, T.S.l)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onAppear {
                reload()
                consume()
            }
            .onChange(of: router.pending) { _, _ in consume() }
            .onChange(of: route.flashID) { _, new in
                guard let new else { return }
                flash = new
                withAnimation(T.M.move) { proxy.scrollTo(new, anchor: .center) }
            }
            .task(id: flash) {
                guard flash != nil else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                withAnimation(T.M.exit) { flash = nil }
                route.flashID = nil
            }
        }
        .navigationTitle("台账")
        .task { await app.reload(refreshStatus: false) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.recordExport))
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("导出记录")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await read() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(reading)
                .accessibilityLabel("重新读取锁内日志")
            }
        }
    }

    // MARK: - 页头：标题 + 一行状态（三通道：形状 + 色 + 文字）

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("台账")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: T.S.s) {
                StateDot(tone: statusTone, word: statusWord)
                Text(statusText)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
    }

    private var statusTone: Tone {
        guard let lock = app.lock else { return .neutral }
        return lock.isConnected ? .ok : .attention
    }

    private var statusWord: String {
        guard let lock = app.lock else { return "无门锁" }
        return lock.isConnected ? "已连接" : "未连接"
    }

    private var statusText: String {
        guard app.lock != nil else { return "还没有门锁，台账无处可读" }
        guard !entries.isEmpty else { return lockName + " · 还没有读到记录" }
        let days = LedgerFilter.dayCount(entries)
        let latest = entries.map { $0.at }.max() ?? 0
        let synced = readAt.map { " · 读于 " + TimeFormat.clock($0) } ?? ""
        let gap = untimed > 0 ? " · " + String(untimed) + " 条锁端无时刻未上时间线" : ""
        return lockName + " · " + String(entries.count) + " 条 · 覆盖 "
            + String(days) + " 天 · 最近 " + TimeFormat.ago(latest) + synced + gap
    }

    // MARK: - 检索与读数

    private var filterPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "检索", trailing: "命中 " + String(filtered.count) + " 条")
                Inset {
                    HStack(spacing: T.S.s) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: T.Icon.s, weight: .regular))
                            .foregroundStyle(Ink.inkFaint)
                            .accessibilityHidden(true)
                        TextField("成员 / 凭证 / +指纹 -临时码", text: $query)
                            .font(T.F.body)
                            .foregroundStyle(Ink.ink)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: T.Icon.s, weight: .regular))
                                    .foregroundStyle(Ink.inkFaint)
                            }
                            .accessibilityLabel("清空检索")
                        }
                    }
                    .frame(minHeight: T.Hit.min)
                }

                HStack(alignment: .firstTextBaseline, spacing: T.S.m) {
                    Reading(value: String(filtered.count), unit: "条", size: 22)
                    Spacer(minLength: T.S.s)
                    if conditions > 0 {
                        Text(String(conditions) + " 项条件")
                            .font(T.F.unit)
                            .foregroundStyle(Ink.inkSub)
                            .monospacedDigit()
                        Button("重置") { reset() }
                            .font(T.F.caption)
                            .foregroundStyle(Ink.ink)
                            .frame(minHeight: T.Hit.min)
                            .accessibilityLabel("重置检索与筛选")
                    }
                }

                Divider().overlay(Ink.hairline)

                ReadingGrid(items: readings, columns: 3)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 筛选 chip（同一套 ChipRow，选中只是 signal 微光，不是第二处强调色）

    private var chips: some View {
        VStack(spacing: T.S.s) {
            ChipRow(items: LedgerScope.allCases, title: { $0.rawValue }, selection: $scope)
            if memberOptions.count > 1 {
                ChipRow(items: memberOptions, title: { $0.isEmpty ? "全部成员" : $0 }, selection: $member)
            }
        }
    }

    private func dayFocusBlock(_ key: String) -> some View {
        Panel {
            HStack(spacing: T.S.s) {
                Image(systemName: "calendar")
                    .font(.system(size: T.Icon.s, weight: .regular))
                    .foregroundStyle(Ink.inkSub)
                    .accessibilityHidden(true)
                Text("只看 " + TimeFormat.dayTitle(key))
                    .font(T.F.body)
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: T.S.s)
                Button("看全部日子") { route.dayFocus = nil }
                    .font(T.F.caption)
                    .foregroundStyle(Ink.ink)
                    .frame(minHeight: T.Hit.min)
                    .accessibilityLabel("取消只看某一天")
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 近 7 日密度（刻度只量真东西：每天真有几条）

    /// 每根柱 = 那天在这个筛选下的条数；柱高按当周最大值归一。
    private var densityPanel: some View {
        let days = LedgerFilter.recentDays(filtered, span: 7)
        let peak = max(days.map { $0.count }.max() ?? 0, 1)
        return Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "近 7 日", trailing: "峰值 " + String(peak) + " 条")
                HStack(alignment: .bottom, spacing: T.S.s) {
                    ForEach(days) { day in
                        VStack(spacing: T.S.xs) {
                            Reading(value: String(day.count), size: 11, weight: .regular,
                                    tint: day.count == 0 ? Ink.inkFaint : Ink.ink, animated: false)
                            Capsule()
                                .fill(day.count == 0 ? Ink.plateAlt : Ink.ink.opacity(0.55))
                                .frame(height: barHeight(day.count, peak: peak))
                            Text(LedgerFilter.shortLabel(day.id))
                                .font(T.F.unit)
                                .foregroundStyle(Ink.inkFaint)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("近 7 日每天记录条数")
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func barHeight(_ count: Int, peak: Int) -> CGFloat {
        guard count > 0 else { return T.S.xs }
        return T.S.xs + T.S.xxl * CGFloat(count) / CGFloat(peak)
    }

    // MARK: - 主角：按自然日分组的时间线

    private var timeline: some View {
        ForEach(groups) { group in
            VStack(spacing: 0) {
                LedgerDayHeader(dayKey: group.dayKey, count: group.items.count)
                Panel(inset: 0) {
                    VStack(spacing: 0) {
                        ForEach(group.items.indices, id: \.self) { index in
                            let entry = group.items[index]
                            if index > 0 { rowDivider }
                            Button {
                                open(entry)
                            } label: {
                                LedgerRow(entry: entry)
                                    .padding(.horizontal, T.S.l)
                                    .background(flash == entry.id ? Signal.wash : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                            .accessibilityHint("打开这条记录的详情")
                        }
                    }
                }
                .padding(.horizontal, T.S.gutter)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: T.Stroke.hair)
            .padding(.horizontal, T.S.l)
    }

    // MARK: - 空态 / 加载态 / 错误态（空态一律给出路）

    private var emptyLedgerBlock: some View {
        Panel {
            EmptyPanel(
                title: "还没有台账记录",
                message: "台账是锁内日志读出来的。先把门锁连上，再到「门」页开一次门，记录就会落在这里。",
                actionTitle: "读取锁内日志",
                systemImage: "list.bullet.rectangle.portrait"
            ) {
                Task { await read() }
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var emptyFilteredBlock: some View {
        Panel {
            EmptyPanel(
                title: "这些条件下没有记录",
                message: "检索词或筛选把这一段时间的记录都筛掉了。放宽条件就能回到台账。",
                actionTitle: "清除条件",
                systemImage: "line.3.horizontal.decrease.circle"
            ) {
                reset()
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var busyBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "读取中")
                BusyRow(text: "正在从锁内翻页读取日志…")
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var noteBlock: some View {
        Panel {
            StatusLine(tone: readNoteTone, text: readNote ?? "")
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var readNoteTone: Tone {
        guard let note = readNote else { return .neutral }
        return note.hasPrefix("已") ? .ok : .attention
    }

    private var noLockBlock: some View {
        Panel {
            EmptyPanel(
                title: "还没有添加门锁",
                message: "开门与操作记录存在门锁内。先添加并配对门锁，再回到这里读取。",
                actionTitle: "添加门锁",
                systemImage: "door.left.hand.closed"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 本机标注读数（备注 / 标旗 / 处置只存在本机）

    private var overlayBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "本机标注")
                ReadingGrid(items: [
                    .init(label: "备注", value: String(overlay.notes.count), unit: "条"),
                    .init(label: "标旗", value: String(overlay.flagged.count), unit: "条"),
                    .init(label: "已处置", value: String(overlay.disposed.count), unit: "条")
                ], columns: 3)
                Text("备注、标旗与处置只落在本机，不写入门锁，也不进导出 CSV 的列。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 动作（全部真改状态或真跳转）

    /// 点一行 = 把这一条写进上下文，再推到详情页。
    /// 这里不能用 request(.record)：那个入口只切 Tab、不 push，点了会留在台账页。
    private func open(_ entry: LedgerEntry) {
        route.focusID = entry.id
        router.request(.dest(.recordDetail))
    }

    private func reset() {
        query = ""
        scope = .all
        member = ""
        route.dayFocus = nil
    }

    /// 从本机日志缓存装载台账（首屏、切锁、上下文落地都走它）。
    private func reload() {
        guard !mac.isEmpty else {
            entries = []
            untimed = 0
            readAt = nil
            return
        }
        let load = RecordsSource.load(mac: mac, lockName: lockName, members: app.members)
        entries = load.entries
        untimed = load.untimed
        readAt = RecordsSource.lastSync(mac: mac)
    }

    /// 读锁内日志。
    /// TODO(engine) 真链路：ensureConnected → getLogs(cmd16) 5 条/页、最多 20 页 100 条，
    /// 每页落 kf_logcache_，成功后写 kf_logsync_ 时间戳；失败回退缓存并如实播报。
    /// 已接的部分：缓存装载、时间戳落盘、未连接时不谎报「已读」。
    @MainActor
    private func read() async {
        guard !reading else { return }
        guard !mac.isEmpty else {
            readNote = "还没有门锁，没有可读的台账"
            return
        }
        reading = true
        readNote = nil
        // 真链路：ensureConnected → cmd16 逐页拉取（最多 20 页 × 5 条）→ 落 kf_logcache_。
        // 失败时 AppModel 会把原因放进 lastError；这里回退到缓存并如实播报，不谎报"已读"。
        await app.readLogs()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let err = app.lastError {
            reload()
            readNote = "读取失败 · " + err + "（下面是上次读到的那一份）"
            app.lastError = nil
        } else if app.lock?.isConnected == true {
            RecordsSource.markSynced(mac: mac, at: now)
            reload()
            readNote = untimed > 0
                ? "已读取 " + String(entries.count) + " 条（另 " + String(untimed) + " 条锁端未回时刻，无法定位到某一天）"
                : "已读取 " + String(entries.count) + " 条 · " + TimeFormat.clock(now)
        } else {
            reload()
            readNote = "门锁未连接 · 下面是上次读到的那一份"
        }
        reading = false
    }

    /// 消费 Router 带来的上下文（哪一条 / 哪一天 / 搜索词）。用完即清。
    private func consume() {
        reload()
        let context = router.consume()
        switch context {
        case .record(let id):
            route.focusID = id
            route.flashID = id
            route.dayFocus = nil
        case .day(let key):
            route.dayFocus = key
            route.focusID = nil
        default:
            break
        }
        if let seed = route.searchSeed {
            query = seed
            route.searchSeed = nil
        }
    }
}
