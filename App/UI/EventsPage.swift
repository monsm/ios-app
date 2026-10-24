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
import UIKit

/// 记录页 —— 门里「事件」
struct EventsPage: View {
    @EnvironmentObject private var app: AppState

    /// 从门厅分时图点进来时带上的小时（0–23）。nil = 不按小时筛。
    var initialHour: Int? = nil

    @State private var recs: [Rec] = []
    /// 当前小时过滤。点了分时图的某一根柱子就落到这一根上。
    @State private var hourFilter: Int?
    /// 过滤组合（当前只有"只看告警"这一位，但 QueryFilters 支持更多）。
    ///
    /// 这套存取在 RecordSearch 里写得很完整 —— 含 kf_filter_default 三种开场策略
    /// （记住上次 / 每次空白 / 默认只看告警），注释一路标到 560/908。
    /// 但**全仓 UI 一次都没调过 load/save**：用户设了"只看告警"，离开再回来就回到全部。
    /// 这里把它接上。
    @State private var filters = QueryFilters()
    /// 过滤结果快照。
    ///
    /// 原来它是**计算属性**：每次 body 求值都重跑一遍 decode + parse + search。
    /// 这一页有同步遮罩、备注弹窗、命名视图、保存对话框等多个状态，
    /// 任何一个变化都会触发一次全量重算 —— 记录多的时候这就是主线程卡顿的来源。
    /// 现在只在 recs / 搜索词 / 只看告警 / 小时过滤变化时重算。
    @State private var filtered: [Rec] = []
    @State private var loaded = false
    @State private var search = ""
    @State private var searchActive = false
    @State private var alarmOnly = false
    /// 筛选视图（用户自己存下来的查询条件）与最近搜索。
    /// 这两份数据一直有读写 API，但全仓没有任何界面入口 —— 属于"功能存在、够不着"。
    @State private var namedViews: [NamedView] = []
    @State private var recentSearches: [String] = []
    @State private var saveName = ""
    /// 正在编辑备注的事件 / 草稿文本。
    /// 备注的读写 API（RecordSearch.note / setNote）一直都在，
    /// 但事件行既不显示也不允许编辑 —— 又一个"存得进去、看不见"的功能。
    @State private var noteTarget: Rec?
    @State private var noteDraft = ""
    /// 正在从门锁拉日志
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var syncing = false
    /// 同步详情 —— 只在"结果不对劲"时弹出，让用户能截给我看卡在哪一步。
    @State private var syncDetail: String?
    @State private var showSaveDialog = false
    /// 待确认删除的筛选视图名（不可逆动作必须先问一句）
    @State private var pendingDeleteView: String?

    private var mac: String { app.currentMac }

    var body: some View {
        VStack(spacing: 0) {
            // HTML 50-events 的页内标题区（胶囊行 + H1 + SUB）
            eventsHeader
            if let h = hourFilter {
                hourFilterBar(h)
            }
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
        .background(XPalette.canvasGradient)
        .onChange(of: search) { _, _ in filtered = computeFiltered() }
        .onChange(of: alarmOnly) { _, _ in filtered = computeFiltered() }
        .onChange(of: hourFilter) { _, _ in filtered = computeFiltered() }
        // ═══ 2026-10-24 逐页对齐：去掉重复标题 ═══
        //
        // 这一页是手写骨架（没用 XScreen），所以第 1 轮统一修 XScreen 时漏了它。
        // 原写法 .navigationTitle("事件") + .large = 导航栏画一个大标题，
        // 而 HTML 50-events 的标题在**页内**（H1 + SUB + 胶囊行 + 分段）。
        // 两者同时存在就是两行同名标题。
        //
        // 现在导航栏只留 inline 空标题（返回箭头仍在），标题交给页内。
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, isPresented: $searchActive, prompt: "搜索事件")
        // 删除筛选视图的二次确认。说清"删的是什么"——不是一个"确定吗"。
        .confirmationDialog(
            "删除这个筛选视图？",
            isPresented: Binding(get: { pendingDeleteView != nil },
                                 set: { if !$0 { pendingDeleteView = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeleteView
        ) { name in
            Button("删除「\(name)」", role: .destructive) {
                RecordSearch.deleteNamedView(name)
                namedViews = RecordSearch.namedViews()
                pendingDeleteView = nil
            }
            Button("取消", role: .cancel) { pendingDeleteView = nil }
        } message: { _ in
            Text("删掉的是这条保存下来的筛选条件，之后要重新设置一遍。\n已读到的事件记录不受影响。")
        }
        // ═══ 同步时的可见指示 ═══
        //
        // 同步入口在**菜单里**：点一下菜单就关闭了，所以 `Button(syncing ? "同步中…" : …)`
        // 这句文案用户**永远看不到**。而跨页拉日志要好几秒（最多 12 页 BLE 往返），
        // 期间屏幕上什么都没有 —— 用户会以为按钮没生效，于是再点一次。
        //
        // 这里给一条非阻塞的常驻指示：不挡点击、不弹窗，只是让"正在发生"可见。
        .overlay(alignment: .top) {
            if syncing {
                // 浮层 = **功能层**, 所以这里用玻璃, 不用实底 (规范 §6.1 三层模型)。
                // 旧写法是 surface 实底 + 一条描边 —— 那是卡片语汇, 贴在内容上方
                // 会和它下面真正的内容卡抢同一种"物质感", 层次反而塌掉。
                HStack(spacing: XSpace.s) {
                    ProgressView().controlSize(.small)
                    Text("正在从门锁同步…")
                        .xFont(.footnote, weight: .medium)
                        .foregroundStyle(XPalette.text)
                }
                .padding(.horizontal, XSpace.l)
                .padding(.vertical, XSpace.s)
                .xGlass(in: Capsule())
                .padding(.top, XSpace.s)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在从门锁同步日志")
            }
        }
        .animation(reduceMotion ? nil : XMotion.soft, value: syncing)
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
                    XToggle("只看告警", isOn: Binding(
                        get: { alarmOnly },
                        set: { v in
                            alarmOnly = v
                            filters.alarmOnly = v
                            filters.save(mac: mac)      // 记住这次选择
                            XHaptics.tick.impactOccurred()
                        }))
                    XHairline()
                    Button("刷新") { load() }
                    // ═══ 从门锁同步日志 ═══
                    //
                    // 这一页读的 DB.readLogs 底层是 kf_logcache_<mac>，
                    // 而**没有任何代码往里面写过**：
                    //   · LockService.getLogs（拉取）零调用
                    //   · Store.writeLogs（存储）零调用
                    // 两者本来是一对搭档，两头都没接上。
                    // 结果是事件页、统计、今日开门全跑在一个永远为空的缓存上。
                    Button(syncing ? "同步中…" : "从门锁同步日志") { syncLogs() }
                        .disabled(syncing || mac.isEmpty)
                    XHairline()
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
                    // ═══ 清除失败记录 ═══
                    //
                    // 开门失败记录会被 recordFailEvent 持续写入（LockKeeperApp 里
                    // 每次开锁失败都记一条），并合并进这一页的事件流。
                    // 但清除它的 DB.clearFailEvents **零调用** —— 也就是说这些记录
                    // 只进不出，用户没有任何办法让它们消失。
                    // 失败记录含时间与地点线索，属于"我不想要它一直留着"的那类数据。
                    Button("清除失败记录", role: .destructive) { clearFailLog() }
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
        .alert("同步详情", isPresented: Binding(get: { syncDetail != nil },
                                              set: { if !$0 { syncDetail = nil } })) {
            Button("复制") {
                UIPasteboard.general.string = syncDetail ?? ""
                syncDetail = nil
            }
            Button("关闭", role: .cancel) { syncDetail = nil }
        } message: {
            Text(syncDetail ?? "")
        }
        .alert("事件备注", isPresented: Binding(get: { noteTarget != nil }, set: { if !$0 { noteTarget = nil } })) {
            TextField("最多 60 字", text: $noteDraft)
            Button("保存") { commitNote() }
            Button("取消", role: .cancel) { noteTarget = nil }
        } message: {
            Text("这句备注只存在本机，方便你自己记住这条记录是怎么回事。")
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
        // 从门厅分时图点进来时，只在这一页首次加载时落到那一个小时；
        // 用户之后手动"看全部"，再刷新也不会把它加回来。
        if hourFilter == nil, let h = initialHour { hourFilter = h }
        // 读回上次的过滤组合（受 kf_filter_default 策略控制）
        filters = QueryFilters.load(mac: mac)
        alarmOnly = filters.alarmOnly
        recs = RecordSearch.buildRecs(macs: macs)
        filtered = computeFiltered()
        namedViews = RecordSearch.namedViews()
        recentSearches = RecordSearch.history()
        loaded = true
    }

    /// 与门厅分时图**同一套换算**（protoSecondsToUnix + WeekCal.gregorian），
    /// 否则点了 14 点却筛出别的时段。
    private func hourOf(_ r: Rec) -> Int {
        let d = Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(r.lockTime))
        return WeekCal.gregorian.component(.hour, from: d)
    }

    private func computeFiltered() -> [Rec] {
        var out = recs
        if alarmOnly { out = out.filter { $0.alarm } }
        // 小时过滤放在提前 return 之前 —— 搜索为空时它同样要生效。
        if let h = hourFilter { out = out.filter { hourOf($0) == h } }
        let raw = search.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return out }
        // ═══ 用仓里已经写好的查询引擎，不再自己手搓 substring ═══
        //
        // RecordSearch.search 支持「+必须词 / -排除词 / 时间短语 / 成员 / 凭证维度」，
        // 但此前**零调用** —— 这一页用的是四字段 substring，把那些能力全浪费了。
        // 空查询时 Query.parse 产生空 must/not，search 直接返回全部，
        // 所以"搜索框一空就把记录隐藏"这种反向故障不会发生（已核对实现）。
        var f = filters
        f.alarmOnly = alarmOnly
        return RecordSearch.search(recs: out,
                                   query: RecordSearch.parse(raw),
                                   filters: f)
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
                        // 删除筛选视图是**不可逆**的（它只是一条存下来的条件，删了就没了），
                        // 而它藏在长按菜单里 —— 长按 + 选删除，两个动作已经很不容易误触；
                        // 但「不容易误触」不等于「不必问」：用户长按常常只是想看看菜单。
                        // 本仓 D21 的四档递进里，这一档属于"取消 + 红色按钮 + 具体后果"。
                        Button(role: .destructive) {
                            pendingDeleteView = v.name
                        } label: { Label("删除这个视图", systemImage: "trash") }
                    }
                    .accessibilityLabel("筛选视图 \(v.name)")
                    // 长按菜单里有"删除这个视图"，而视觉上它只是一枚普通胶囊 ——
                    // 读屏用户至少要知道这条能长按（视觉侧不改：这排胶囊本来就密，
                    // 再加一枚省略号会把它们挤得更碎，代价大于收益）。
                    .accessibilityHint("长按可删除这个筛选视图")
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
                    .accessibilityHint("长按可从最近搜索里移除")
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
                .xFont(.caption, weight: .medium)
                .lineLimit(1)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, XSpace.m)
        .padding(.vertical, 7)
        .xPlate(XPalette.surface, .capsule)
        // 触达与视觉是**两个数**（规范 §7.7 对 MetricRow 的同一口径）：
        // 这枚胶囊视觉高约 30pt（7+14+7），够看不够点。
        // 不把它撑大（那会让这排胶囊挤成一团），而是**向下补透明命中区**到 44。
        .frame(minHeight: XHit.min)
        .contentShape(Rectangle())
    }

    /// 清掉本机所有门锁的「开门失败」记录。
    /// 与"清空最近搜索"同属本页的数据清理，放在同一处才发现得了。
    private func clearFailLog() {
        let macs = mac.isEmpty ? DB.keychains().map { $0.mac } : [mac]
        for m in macs { DB.clearFailEvents(m) }
        load()
        XHaptics.trigger.impactOccurred()
        app.showToast("已清除失败记录", tone: .done)
    }

    /// 从门锁分页拉取事件历史并写入本地缓存。
    ///
    /// 这是 DB.writeLogs 与 LockService.getLogs 的唯一接线处 ——
    /// 在此之前两者都只有定义、没人调用，所以本地日志缓存从来是空的。
    ///
    /// 分页约定：按 surplus（锁回报的"还剩多少条"）判断结束，
    /// startIdx 每次按本页实际条数前进。上限 12 页 —— 宁可少拉也不能
    /// 因为协议回包异常而无限循环把界面卡住。
    private func syncLogs() {
        guard !syncing, !mac.isEmpty else { return }
        syncing = true
        Task { @MainActor in
            defer { syncing = false }
            var trace: [String] = []
            let before = HotCache.recent(mac).count
            trace.append("本机缓存原有 \(before) 条")
            do {
                trace.append("① 连接门锁…")
                try await app.lock.ensureConnected(mac: mac)
                trace.append("① 已连接")

                var start: UInt32 = 0
                var collected: [LogEntry] = []
                for page in 1...12 {
                    let r = try await app.lock.getLogs(startIdx: start, pageSize: 20)
                    let surplusText = r.surplus.map(String.init) ?? "nil"
                    trace.append("② 第\(page)页 start=\(start) 返回\(r.logs.count)条 surplus=\(surplusText)")
                    if r.logs.isEmpty { break }
                    collected += r.logs
                    start += UInt32(r.logs.count)
                    if let sp = r.surplus, sp <= 0 { break }
                }
                trace.append("③ 合计拉取 \(collected.count) 条")

                DB.writeLogs(mac, collected)
                let after = HotCache.recent(mac).count
                trace.append("④ 写入后本机缓存 \(before) → \(after) 条")
                load()

                if collected.isEmpty {
                    // 锁里说"没有事件"和"协议没对上"在界面上长得一样，
                    // 所以这里把 trace 摊开，用户截一张图就能定位。
                    app.showToast("门锁里没有可读的事件", tone: .caution)
                    syncDetail = trace.joined(separator: "\n")
                } else if after <= before {
                    app.showToast("拉到 \(collected.count) 条，但本机没有新增", tone: .caution)
                    syncDetail = trace.joined(separator: "\n")
                } else {
                    // 触感已由 tone 统一发，这里不再手写一次（重复会震两下）
                    app.showToast("已同步 \(collected.count) 条（新增 \(after - before) 条）", tone: .done)
                }
            } catch {
                trace.append("✗ 失败: \(error.localizedDescription)")
                // 失败要说下一步：它就在菜单里那一条「从门锁同步日志」，再点一次就是重试。
                app.showToast("同步失败：" + ErrorText.human(error) + "。可在菜单里再点一次「从门锁同步日志」重试", tone: .failed)
                syncDetail = trace.joined(separator: "\n")
            }
        }
    }

    private func commitNote() {
        guard let rec = noteTarget else { return }
        RecordOverlay.setNote(rec.mac, rec.key, noteDraft)
        noteTarget = nil
        noteDraft = ""
        XHaptics.success()
    }

    private func saveView() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var f = QueryFilters()
        f.alarmOnly = alarmOnly
        RecordSearch.saveNamedView(name: name,
                                   text: search.trimmingCharacters(in: .whitespaces),
                                   filters: f,
                                   scopeAll: mac.isEmpty)
        namedViews = RecordSearch.namedViews()
        showSaveDialog = false
        // 触感已由 showToast(tone:) 统一发出 —— 这里再调一次会震两下
        app.showToast("已保存筛选视图「\(name)」", tone: .done)
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
                // 六图改造 (2026-10-23): 顶部加**图 5 的读数条**。
                //
                // 事件页是时间轴，本身形态已经对（不该再改成卡片流）。
                // 缺的是"一共多少条、其中几条告警"这个总量 —— 图 5 永远先把量给出来。
                // 用一条紧凑的读数行而不是一张大卡，避免压住下方的时间轴。
                overviewStrip
                ForEach(grouped, id: \.day) { group in
                    daySection(group)
                }
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.top, XSpace.s)
            .padding(.bottom, XSpace.xxl)
        }
        .background(XPalette.canvasGradient)
    }

    /// 图 5 的读数条：44px 总数 + 告警数 + 分组天数
    private var overviewStrip: some View {
        let alarmN = recs.filter { $0.alarm }.count
        return XPanel(kind: .group) {
            HStack(alignment: .center, spacing: XSpace.l) {
                VStack(alignment: .leading, spacing: 6) {
                    XHeroNumber(
                        text: String(recs.count),
                        color: XPalette.text,
                        unit: "条记录")
                    Text(alarmN > 0 ? "其中 \(alarmN) 条告警 —— 在下面标红"
                                    : "\(grouped.count) 天 · 没有告警")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                XGradientDial(
                    size: 62,
                    progress: recs.isEmpty ? 0.02 : min(1, Double(recs.count) / 40),
                    widthRatio: 0.14,
                    showsCursor: false,
                    showsTick: false,
                    gradient: alarmN > 0 ? XGradient.dial : XGradient.dialOK
                ) { EmptyView() }
                .accessibilityHidden(true)
            }
        }
        .padding(.bottom, XSpace.s)
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
                .xFontExact(.caption2.monospacedDigit())
                .foregroundStyle(XPalette.textSub)
            let alarms = group.items.filter { $0.alarm }.count
            if alarms > 0 {
                HStack(spacing: 2) {
                    // 规范 §10：图标最小 12pt。原 8pt 低于档位下限，
                    // 在 3x 屏上只有 24 物理像素，告警三角几乎糊成一个点。
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: XIcon.xs, weight: .semibold))
                    Text("\(alarms)")
                        .xFontExact(.caption2.monospacedDigit())
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
    /// 时间轴节点颜色 —— 与钥匙工坊四张卡一致
    ///
    /// 告警优先（红），保养次之（橙 = 需要注意），其余按凭证类型：
    ///   pwd 铜 / temp 金 / fp 青 / key 紫 / 未知 灰
    ///
    /// ⚠ 原来 `care` 与 `temp` **都返回 warn** —— 同一屏里一个颜色两个含义，
    /// 用户只看看不出是保养事件还是临时码事件。而且注释写的是
    /// "fp 青 / pwd 紫 / temp 黄 / key 蓝 / 未知 绿"，代码里却是
    /// pwd 灰 / key 绿 / 未知 也绿 —— 注释描述了一套从未实现的配色。
    /// 现在按工坊的四类色落地，未知用灰（不是绿：未知不等于正常）。
    private func nodeColor(_ rec: Rec) -> Color {
        if rec.alarm { return XPalette.danger }
        if rec.care { return XPalette.warn }
        switch rec.kind {
        case "fp":   return XPalette.kindFp
        case "pwd":  return XPalette.accent
        case "temp": return XPalette.kindTemp
        case "key":  return XPalette.kindOtp
        default:     return XPalette.textSub
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
        // 备注只读一次：原来在显示、菜单、无障碍标签里各调一次
        // RecordSearch.note，每行就是 5 次 DB 读取。列表滚动时这很浪费。
        let savedNote = RecordOverlay.note(rec.mac, rec.key)
        return HStack(alignment: .top, spacing: XSpace.m) {
            // 时间
            Text(shortTime(rec.timeStr))
                .xFontExact(.caption.monospacedDigit())
                .foregroundStyle(XPalette.textSub)
                .xScaledWidth(42, alignment: .trailing)
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
                            .foregroundStyle(XPalette.textSub)
                    }
                }
                if let sub = subText(rec) {
                    Text(sub)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
                if !savedNote.isEmpty {
                    Label(savedNote, systemImage: "text.bubble")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.accentText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, XSpace.l)
        .contentShape(Rectangle())
        // 长按给这条事件写一句备注（60 字上限，写库在 RecordSearch.setNote）
        .contextMenu {
            Button {
                noteDraft = savedNote
                noteTarget = rec
                XHaptics.tick.impactOccurred()
            } label: {
                Label(savedNote.isEmpty ? "添加备注" : "编辑备注",
                      systemImage: "text.bubble")
            }
            if !savedNote.isEmpty {
                Button(role: .destructive) {
                    RecordOverlay.setNote(rec.mac, rec.key, "")
                    XHaptics.trigger.impactOccurred()
                } label: { Label("删除备注", systemImage: "trash") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(rec)
            + (savedNote.isEmpty ? "" : "，备注 " + savedNote))
        // 长按菜单里有"加/改备注"与"删备注"，视觉上这条只是一行事件 ——
        // 不加 hint 的话读屏用户不会知道还能长按。
        .accessibilityHint(savedNote.isEmpty ? "长按可添加备注" : "长按可编辑或删除备注")
        .accessibilityAction(named: "添加或编辑备注") {
            noteDraft = savedNote
            noteTarget = rec
        }
    }

    /// 小时过滤的可见状态 + 一个撤掉的入口。
    /// 不显示它的话，用户会看着"只有 3 条"以为记录丢了。
    private func hourFilterBar(_ h: Int) -> some View {
        HStack(spacing: XSpace.s) {
            Image(systemName: "clock")
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.accentText)
                .accessibilityHidden(true)
            Text("只看今天 \(h):00 – \(h):59")
                .xFont(.footnote, weight: .medium)
                .foregroundStyle(XPalette.text)
            Spacer(minLength: 0)
            Button {
                hourFilter = nil
                XHaptics.tick.impactOccurred()
            } label: {
                Label("看全部", systemImage: "xmark.circle.fill")
                    .xFont(.caption, weight: .medium)
                    .foregroundStyle(XPalette.accentText)
            }
            .buttonStyle(.plain)
            .frame(minHeight: XHit.min)
            .accessibilityLabel("取消小时过滤，看今天全部记录")
        }
        .padding(.horizontal, XSpace.gutter)
        .padding(.vertical, XSpace.xs)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        // 空态是用户第一次看到这一页的样子，也是最需要"下一步"的地方。
        // 原来写的是"连上锁后读取门锁日志"——被动语态，而且读日志这件事
        // 界面上并没有按钮（我后来补的「从门锁同步」在筛选菜单里，很深的角落）。
        // 把这个动作直接放到空态上：这是唯一能让这页有内容的方式。
        XEmptyState(systemImage: "list.bullet.rectangle",
                    title: search.isEmpty ? "还没有记录" : "没有匹配的事件",
                    message: search.isEmpty
                        ? "本机还没有从门锁读过日志。连上门锁后点下面同步一次，之后按天浏览。"
                        : "换个关键词试试；也可以清掉搜索回到全部记录。",
                    actionTitle: search.isEmpty ? (syncing ? "同步中…" : "从门锁同步日志") : "清空搜索",
                    action: search.isEmpty ? { syncLogs() } : { search = "" })
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

    /// 时刻截取的唯一实现在 TimeFormat.shortClock。
    private func shortTime(_ full: String) -> String { TimeFormat.shortClock(full) }

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
