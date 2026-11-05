// RecordsHomeScreen.swift —— 记录（Tab 3）· V8 设计语言
//
// 与 RecordsScreen 的功能对齐（数据绑定完全一致：RecordsSource / LedgerFilter / RecordsRoute / RecordsOverlay）。
// 一屏一个英雄数：今日开锁次数只出现在大数字里；芯片行只放「今天/本周/告警/失败」的条数。
//
// 结构（对应参考图 P3 型）：
//   芯片行 → 判断句 → 因果段 → 英雄数（VHeroNumber）→ 范围标（VRangeCaption）→ 24h 波形（VSpark）
//          → 卡 1 时间线（VDataRow × N）→ 卡 2 检索 → 工具入口
import SwiftUI

struct RecordsHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private let overlay = RecordsOverlay.shared
    private let route = RecordsRoute.shared

    @State private var query = ""
    @State private var scope: LedgerScope = .all
    @State private var member = ""
    @State private var lockScope: RecordLockScope = .current
    @State private var selectedMac = ""
    @State private var entries: [LedgerEntry] = []
    @State private var untimed = 0
    @State private var readAt: Int64?
    @State private var readNote: String?

    private var mac: String {
        if lockScope == .all { return "" }
        return selectedMac.isEmpty ? (app.lock?.id ?? "") : selectedMac
    }

    private var filtered: [LedgerEntry] {
        LedgerFilter.apply(entries,
                           scope: scope,
                           member: member,
                           query: LedgerQuery(query),
                           dayFocus: route.dayFocus,
                           alarmKinds: route.alarmKinds,
                           visitorOnly: route.visitorOnly)
    }

    private var todayEntries: [LedgerEntry] {
        let start = TimeFormat.calendar.startOfDay(for: Date())
        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        return entries.filter { $0.at >= startMillis }
    }

    private var todayOpenCount: Int {
        todayEntries.filter { $0.tone == .ok || $0.tone == .live }.count
    }

    private var todayAlarmCount: Int {
        todayEntries.filter { $0.tone == .attention || $0.tone == .critical }.count
    }

    private var weekOpenCount: Int {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(7 * 24 * 3600 * 1000)
        return entries.filter { $0.at >= cutoff && ($0.tone == .ok || $0.tone == .live) }.count
    }

    private var judgement: String {
        if app.lock == nil { return "还没有门锁" }
        if entries.isEmpty { return "还没有台账记录" }
        if todayAlarmCount > 0 { return "今天有 \(todayAlarmCount) 条告警" }
        if todayOpenCount == 0 { return "今天还没有开门" }
        return "今天的往来都正常"
    }

    private var lead: String {
        if entries.isEmpty {
            return "台账是锁内日志读出来的。先把门锁连上，再到门页开一次门，记录就会落在这里。"
        }
        var bits: [String] = []
        if let first = todayEntries.max(by: { $0.at < $1.at }) {
            bits.append("最近一次 " + TimeDisplay.clock(first.at))
        }
        if untimed > 0 {
            bits.append("另有 \(untimed) 条锁端没回时刻")
        }
        bits.append("只统计本机读到的锁内日志")
        return bits.joined(separator: "，") + "。"
    }

    /// 24 小时波形：每小时的开锁次数（0–23 时）。
    private var hourly: [Double] {
        var buckets = [Double](repeating: 0, count: 24)
        let cal = TimeFormat.calendar
        let dayStart = Int64(cal.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
        for entry in todayEntries where entry.tone == .ok || entry.tone == .live {
            let hour = cal.component(.hour, from: TimeFormat.date(entry.at))
            if hour >= 0 && hour < 24 { buckets[hour] += 1 }
        }
        _ = dayStart
        return buckets
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            chipRow
        } content: {
            if app.lock == nil {
                VEmpty(
                    title: "还没有添加门锁",
                    reason: "开门与操作记录存在门锁内。先添加并配对门锁，再回到这里读取。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else if entries.isEmpty {
                VEmpty(
                    title: "还没有台账记录",
                    reason: "台账是锁内日志读出来的。先把门锁连上，再到门页开一次门，记录就会落在这里。",
                    actionTitle: "去门页"
                ) { router.select(.door) }
            } else {
                heroBlock
                timelineCard
                searchCard
                toolsCard
            }
            if let note = readNote {
                VFailure(what: "读取失败", why: note, next: "下面是上次读到的那一份。走近门锁再试一次。")
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { router.request(.dest(.recordsStudio)) } label: {
                        Label("台账工作室", systemImage: "magnifyingglass")
                    }
                    Button { router.request(.dest(.recordExport)) } label: {
                        Label("导出记录", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(V8.T.chipValue)
                }
                .accessibilityLabel("记录页操作")
            }
        }
        .onAppear { reload() }
        .onChange(of: app.lock?.id) { _, _ in reload() }
        .onChange(of: app.currentMac) { _, _ in reload() }
        .task { await app.reload(refreshStatus: false) }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                // 2026-11-05（对抗审查 · 设计冗余）：这一格原来写「今天 N 条」，
                // 而本页**已经有两处**在讲今天：英雄数（N 次·今天）与台账卡标题。
                // 三个数字说的是同一件事，用户一眼扫到三个「今天」。删掉芯片这一格。
                VChip2(icon: .ring(0.7, V8.C.accent), label: "本周", value: "\(weekOpenCount) 次")
                VChip2(icon: .ring(todayAlarmCount > 0 ? 0.4 : 0.02, V8.C.danger),
                       label: "告警", value: "\(todayAlarmCount) 条")
                VChip2(icon: .ring(0.02, V8.C.warn),
                       label: "失败", value: "\(entries.filter { $0.tone == .critical }.count) 条")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 英雄数 + 波形

    private var heroBlock: some View {
        VCard2 {
            VHeroNumber(
                value: "\(todayOpenCount)",
                unit: "次 · 今天",
                tint: V8.C.accent,
                font: V8.T.heroL
            )
            .frame(maxWidth: .infinity, alignment: .center)
            VRangeCaption(text: "0–24 时")
                .padding(.top, V8.S.gapM)
            VSpark(values: hourly, tint: V8.C.accentFill, cursor: currentHour, axis: .hours24)
                .padding(.top, V8.S.gapS)
        }
    }

    private var currentHour: Int? {
        let hour = TimeFormat.calendar.component(.hour, from: Date())
        return (hour >= 0 && hour < 24) ? hour : nil
    }

    // MARK: - 卡 1 时间线

    private var timelineCard: some View {
        VCard2 {
            // 标题改成「共 N 条」：与英雄数的「今天 N 次」不同口径（这里是当前范围的全部条目，
            // 含告警/失败等非开门行），不再重复同一个数字。
            VCardHead(eyebrow: "台账", statement: "共 \(entries.count) 条",
                      trailing: readAt.map { TimeFormat.dayShort($0) })
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(filtered.prefix(8))) { entry in
                    Button {
                        router.request(.dest(.recordDetail))
                        route.focusID = entry.id
                    } label: {
                        VDataRow(
                            tag: TimeDisplay.clock(entry.at),
                            tagTint: toneTint(entry.tone),
                            title: entry.event,
                            detail: CredentialOrg.ownerName(entry.owner),
                            value: ""
                        )
                    }
                    .buttonStyle(.plain)
                    if entry.id != filtered.prefix(8).last?.id { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text(untimed > 0
                 ? "另有 \(untimed) 条锁端没回时刻，未进时间线（不是丢失，是锁钟未读到）。"
                 : "全部记录都能定位到某一天。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 记录域统一走 V8.D 数据色：只编码"类别"，不编码"重要"。
    /// 2026-11-04（跨页复核）：同一语义（开锁）在记录页用 V8.C.accent、在记录详情用 V8.C.ok ——
    /// 同一条记录在两个页面两个颜色。收口到 V8.D.openEvent（两页同一个来源）。
    private func toneTint(_ tone: Tone) -> Color {
        switch tone {
        case .ok, .live: return V8.D.openEvent
        case .attention: return V8.D.failure
        case .critical: return V8.D.alarm
        case .neutral: return V8.D.system
        }
    }

    // MARK: - 卡 2 检索

    private var searchCard: some View {
        VCard2 {
            HStack(spacing: V8.S.gapS) {
                Image(systemName: "magnifyingglass")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                TextField("搜事件 / 归属 / +必须 -排除", text: $query)
                    .font(V8.T.body)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空检索")
                }
            }
            .frame(minHeight: V8.H.min)
            VDivider2()
                .padding(.vertical, V8.S.gapS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(LedgerScope.allCases) { item in
                        scopeChip(item)
                    }
                }
            }
            Text("命中 \(filtered.count) 条")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
        }
    }

    private func scopeChip(_ item: LedgerScope) -> some View {
        let selected = scope == item
        let count = entries.filter { item.matches($0) }.count
        return Button {
            scope = item
        } label: {
            Text(item.rawValue + " " + "\(count)")
                .font(V8.T.tab)
                .foregroundStyle(selected ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(selected ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 卡 3 工具

    private var toolsCard: some View {
        VCard2 {
            VCardHead(eyebrow: "台账工具", statement: "两个入口")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "台账工作室", detail: "检索语法 / 统计 / 原始帧") {
                    router.request(.dest(.recordsStudio))
                }
                VDotRule()
                VNavRow(title: "导出记录", detail: "CSV / 成员名册 / 上周小结") {
                    router.request(.dest(.recordExport))
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 数据

    private func reload() {
        if !selectedMac.isEmpty, DB.keychain(selectedMac) == nil { selectedMac = "" }
        guard lockScope == .all || !mac.isEmpty else {
            entries = []
            untimed = 0
            readAt = nil
            return
        }
        let targets: [Keychain] = lockScope == .all
            ? DB.keychains()
            : DB.keychains().filter { DB.normalizeMac($0.mac) == DB.normalizeMac(mac) }
        overlay.hydrate(macs: targets.map(\.mac))
        var merged: [LedgerEntry] = []
        var untimedTotal = 0
        var syncTimes: [Int64] = []
        for kc in targets {
            let load = RecordsSource.load(mac: kc.mac,
                                          lockName: LockArchive.displayName(kc),
                                          members: app.members)
            merged.append(contentsOf: load.entries)
            untimedTotal += load.untimed
            if let t = RecordsSource.lastSync(mac: kc.mac) { syncTimes.append(t) }
        }
        entries = merged.sorted { $0.at > $1.at }
        untimed = untimedTotal
        readAt = syncTimes.min()
    }
}