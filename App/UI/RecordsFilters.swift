// 记录页 · 筛选 / 搜索 / 范围选择
// 2026-10-29 从 RecordsView.swift（1208 行）拆出。
// 是 RecordsView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension RecordsView {
    @ViewBuilder
    var searchBar: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                    // 551: 这句占位文案承诺的三段 (成员 / 凭证 / 备注) 由 `RecordSearch.searchFace`
                    // 一处定义、在 applyFilter 的检索块里落地 —— 少一段就是让用户搜一个搜不到的热区。
                    TextField("搜索: 成员 / 凭证 / 昨晚 告警 / +指纹 -临时码", text: $searchText)   // 551/554/555 搜索
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            parsedTags = []
                            highlightTokens = []
                            applyFilter()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .accessibilityLabel("清空搜索")
                        .frame(minWidth: DS.Hit.min, minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    }
                }
                .padding(DS.Space.s)
                // 2026-10-14 材质统一批次: 搜索框**保持实底**。它在 Section 里 (这一页是 List),
                // 行组本身已经是一层玻璃面 —— 再给行里的控件上玻璃就是玻璃叠玻璃, 接缝全在字底下。
                // @layout-allow 面板实底
                // @layout-allow VK豁免 控件可识别性: 带 hairline 的输入框底衬，同上
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))

                // 554/555 解析出的条件标签 (时间短语 / 加减词 / 告警 / 失败)
                if !parsedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.xs) {
                            ForEach(Array(parsedTags.enumerated()), id: \.offset) { _, tag in
                                Text(tag)
                                    .vkFont(.caption2, weight: .medium)
                                    .lineLimit(1)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .padding(.horizontal, DS.Space.xs + 2)
                                    .padding(.vertical, 2)
                                    .variantPlate(DS.Palette.accentText.opacity(0.10), .capsule)
                                    .frame(maxWidth: 160)
                            }
                        }
                        .padding(.vertical, DS.Space.xxs)
                    }
                }
                // 2026-10-26 精简：「我的过滤」（命名视图）已删（用户确认）。
            }
        } header: {
            HStack(spacing: DS.Space.s) {
                Text("搜索")   // 551 搜索
                Spacer(minLength: DS.Space.s)
            }
        }
    }
    // 2026-10-26 精简：命名视图保存（saveAsView）已删（用户确认）。

    /// 562 实时计数 "约 N 条" (归属口径标"约", 边输入边更新)
    @ViewBuilder
    var resultCount: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                // 2026-10-13 run 63: 原来把三段拼接 + 两个三元全内联进 Text, 报 type-check 超时。
                // 先算好再拼。
                let head = searchText.isEmpty ? "筛选后约 " : "命中约 "
                let tail = searchText.isEmpty ? "" : " · 实时"   // 562 实时
                let cap = capped ? " · 本页已加载 \(rows.count)" : ""
                Text(head + String(filteredTotal) + " 条" + tail + cap)
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer(minLength: DS.Space.s)
                // 573 条件计数与重置: 叠了几层过滤要说得出来，并一键回到空白起点。
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount) 项条件")
                        .vkFont(.caption2.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(DS.Palette.accentText)
                    Button("重置") {
                        sel = ""
                        searchText = ""
                        filters = QueryFilters()      // 其余联动靠既有 onChange(of: searchText/filters) 重算，不另起一次 applyFilter
                    }
                    .vkFont(.caption2, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                }
            }
                // 2026-10-26 精简：搜索建议下拉已删（suggestions 已移除）。
        }
    }
    @ViewBuilder
    var scopeRow: some View {
        // 2026-10-29 性能：`DB.keychains()` 原来在本块里调 3 次（判断 count、ForEach、还有一处），
        // 每次都是「整表取字典 + 逐把 Keychain.fromDict」。一次取、三处共用。
        let allLocks = DB.keychains()
        return Section {
            HStack(spacing: DS.Space.s) {
                Text("范围")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                Picker("搜索范围", selection: $scope) {   // 561 搜索范围
                    Text("当前锁").tag(0)
                    Text("全部锁").tag(1)   // 770 全部锁
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if scope == 0, allLocks.count > 1 {
                    // 191 按锁切换: 走 AppState.select (清实时状态 + 重读快照), 不自己改 currentMac
                    Menu {
                        ForEach(allLocks) { kc in
                            Button { app.select(kc.mac) } label: {
                                Label(LockArchive.displayName(kc) + (kc.mac == mac ? " · 当前" : ""),
                                      systemImage: kc.mac == mac ? "checkmark.circle.fill" : "lock")
                            }
                        }
                    } label: {
                        Label("换锁", systemImage: "arrow.left.arrow.right.circle")   // 191 换锁
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                    .accessibilityLabel("切换当前锁，当前为 \(app.displayName)")
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
        }
    }

    // 17 筛选 chips (原句"Spotify 式筛选 chips") = 下面这一整行 chip，与 564/571/572/567/568/569/570 同一处。
    // 不另建一套"chips 组件": 同一页两种筛选外观，用户会以为它们是两个功能、两套状态。
    // ---------- 包9: 筛选 chip 行 (564/571/572/567/568/569/570) ----------
    static let kindOptions: [(String, String)] = [("全部凭证", ""), ("指纹", "fp"), ("密码", "pwd"), ("临时码", "temp"), ("数字钥匙", "key")]

    /// 筛选区 —— 2026-10-18 按 PageGrammar 规则 3 重构。
    ///
    /// 重构前: **5 行筛选片全部常驻展开** (时段 / 工作日周末 / 凭证类型 / 告警四连 / 说明),
    /// 首屏被筛选占掉大半, 用户要看的"记录"被推到下面 —— 这就是截图里那堆 chip 的来源。
    ///
    /// 重构后:
    ///   · 默认只留**一行摘要**: 「全部记录」或「时段·工作日·密码·仅告警 (4)」+ 调整入口
    ///   · 点摘要才展开完整筛选面板 (原来那 5 行原样保留在里面, 判据一点没改)
    ///   · 有意向筛选时摘要会显示已启用项数, 不让人忘了自己筛过什么
    ///
    /// 为什么不是删掉低频筛选项: 它们是真功能 (567/565/570 都是拍板过的),
    /// 问题从来不是"有这些筛选", 而是"它们一直摊在首屏"。
    @ViewBuilder
    var filterChips: some View {
        Section {
            Button {
                withAnimation(DS.Motion.quick) { filtersExpanded.toggle() }
                DS.Haptics.tick.impactOccurred()
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .accessibilityHidden(true)
                    Text(filterSummary)
                        .vkFont(.subheadline, weight: activeFilterCount > 0 ? .semibold : .regular)
                        .lineLimit(1)
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .vkFont(.caption2, weight: .semibold)
                            .foregroundStyle(DS.Palette.onAccent)
                            .padding(.horizontal, DS.Space.xs)
                            .frame(minHeight: 18)
                            .background(DS.Palette.accentText, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSub)
                }
                .foregroundStyle(activeFilterCount > 0 ? DS.Palette.accentText : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("筛选: \(filterSummary), 点按\(filtersExpanded ? "收起" : "展开")全部筛选项")

            if filtersExpanded {
            // 2026-10-26 精简：仅告警 / 告警类型多选 / 失败筛选 / 正序回放 四枚 chip 已删（用户确认）。
            // 2026-10-26 精简：「失败筛选」整块（含清空失败标记）已删（用户确认）。
            // 676/672: 深夜区间的"可调"此前只写在注释里, 界面上没有任何入口 (两个键只有读没有写)。
            // 只在选了"深夜预设"这一档时出现 —— 它是这档的定义, 不该常驻在筛选行里。
            if filters.segment == 4 {
                HStack(spacing: DS.Space.s) {
                    Text("深夜区间").vkFont(.caption).foregroundStyle(DS.Palette.textSub)   // 676 深夜区间
                    Spacer(minLength: DS.Space.s)
                    Picker("起点", selection: Binding(get: { RecordSearch.nightFrom },
                                                      set: { RecordSearch.setNightFrom($0) })) {
                        ForEach(0..<24, id: \.self) { Text("\($0) 时").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 96)
                    Text("→").vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    Picker("终点", selection: Binding(get: { RecordSearch.nightTo },
                                                     set: { RecordSearch.setNightTo($0) })) {
                        ForEach(0..<24, id: \.self) { Text("\($0) 时").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 96)
                }
                .frame(minHeight: DS.Hit.min)
                if RecordSearch.nightWindowDegenerate {
                    Text("起点与终点相同 = 空区间, 这一档筛不出任何记录。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VariantToggle("节假日当日顺延 2 小时", isOn: Binding(get: { RecordSearch.holidayExtendOn },   // 672 节假日当日顺延
                                                                   set: { RecordSearch.setHolidayExtend($0) }))
                    .vkFont(.caption)
                    .frame(minHeight: DS.Hit.min)
                Text("顺延只影响深夜档的判定, 不改记录的归属日 (凌晨仍归前一晚)。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 复位按钮: 原来是 section header 里的附属品, 现在面板展开时放在顶部一行
            if activeFilters {
                HStack(spacing: DS.Space.s) {
                    Text("筛选")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Spacer(minLength: DS.Space.s)
                    Button("复位") {
                        filters = QueryFilters()
                        reversed = false
                    }
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            }
        }
        }
    }

    /// 一行摘要: 没筛选时是「全部记录」, 有筛选时列出已启用项。
    var filterSummary: String {
        var parts: [String] = []
        if filters.segment != 0 {
            let names = ["全部", "早 6-9", "午 10-14", "晚 15-21", "深夜"]
            parts.append(names.indices.contains(filters.segment) ? names[filters.segment] : "时段")
        }
        if filters.dayKind != 0 { parts.append(filters.dayKind == 1 ? "工作日" : "周末") }
        if !filters.kind.isEmpty {
            parts.append(Self.kindOptions.first { $0.1 == filters.kind }?.0 ?? "类型")
        }
        if filters.alarmOnly { parts.append("仅告警") }
        if !filters.alarmKinds.isEmpty { parts.append("告警 \(filters.alarmKinds.count) 类") }
        if reversed { parts.append("最早在前") }
        return parts.isEmpty ? "全部记录" : parts.joined(separator: " · ")
    }

    /// 低频区折叠入口 —— 2026-10-18 记录页重构新增。
    ///
    /// 生日条 / 成员筛选 chip / 门神 / 掉电观察 / 去年今日 这五块不是不重要,
    /// 而是不是每次进记录页都要看。原来全部常驻在列表前, 首屏被它们占满。
    /// 现在收进一个可展开区: 默认收起, 展开后与原来逐字一致。
    @ViewBuilder
    var secondaryRowsDisclosure: some View {
        Section {
            Button {
                withAnimation(DS.Motion.quick) { secondaryRowsExpanded.toggle() }
                DS.Haptics.tick.impactOccurred()
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .accessibilityHidden(true)
                    Text(secondaryRowsSummary)
                        .vkFont(.footnote)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: secondaryRowsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                }
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多记录视图")

            if secondaryRowsExpanded {
                memberChips
                lastYearTodayRow
            }
        }
    }

    /// 折叠行上的一行说明: 只列现在真有内容的那几块, 空的不占字。
    var secondaryRowsSummary: String {
        var parts: [String] = []
        if !DB.members().isEmpty { parts.append("成员筛选") }
        return parts.isEmpty ? "更多视图" : parts.joined(separator: " · ")
    }


    /// 716 选区导出: 按**天**整组勾选 → 合并成一份 CSV (进剪贴板, 与 698 同一通路)。
    /// 行级多选刻意不做: 时间线一页上千行, 逐行勾选的手势成本远高于"按天勾"这种整组选择 (原句的"整组"正是这一档);
    /// 凭证 Tab 那套多选 (1518) 是"列表行 + 批量动作", 与这里"导出选区"不是同一件事, 不硬搬。
    @ViewBuilder
    var rangePickSheet: some View {
        NavigationStack {
            List {
                Section {
                    let days = Array(Set(allRows.map { $0.dayKey })).sorted(by: >)
                    if days.isEmpty {
                        Text("当前没有可导出的记录行。")
                            .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(days, id: \.self) { d in
                        let n = allRows.filter { $0.dayKey == d }.count
                        VariantToggle("\(d) · \(n) 条", isOn: Binding(
                            get: { rangeSel.contains(d) },
                            set: { on in if on { rangeSel.insert(d) } else { rangeSel.remove(d) } }))
                            .frame(minHeight: DS.Hit.min)
                    }
                } header: {
                    Text("按天勾选")   // 716 按天勾选
                } footer: {
                    Text("只导出勾选那些天的行; CSV 走剪贴板, 不上传、不落盘。")
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                }
                Section {
                    Button("全选") { rangeSel = Set(allRows.map { $0.dayKey }) }
                    Button("清空") { rangeSel = [] }
                }
            }
            .navigationTitle("选区导出")   // 716 选区导出
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("复制 CSV") { copyRangeCSV() }.disabled(rangeSel.isEmpty)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { showRangePick = false }
                }
            }
        }
    }
    func applyFilter() {
        // 576/580/583/585 —— Rec 池是「点行开详情、详情上下翻页、引用深链定位」唯一的判据来源,
        // **两种范围都要喂**。`macs` 自己就按范围给出 [当前锁] / [全部锁], 所以一次拉取两路共用。
        let recs = RecordSearch.buildRecs(macs: macs, includeFails: true, includeCare: true)
        recPool = recs
        let pool = buildPool(recs)
        computeDayTotals(pool)
        var filtered = applyMemberFilter(pool)
        if !searchText.isEmpty { filtered = applyTextSearch(filtered) }
        if activeFilters { filtered = applyStructuredFilters(filtered) }
        // 570 正序回放: 整段反转 (时间线从最早逐条回放)
        if reversed { filtered = filtered.reversed() }
        // 598: 在**分组之前**截断 —— 分组本身是 O(n)，一次挂上千个 Section 才是滚动掉帧的主因。
        filteredTotal = filtered.count
        if shownCap <= 0 { shownCap = filtered.count > 600 ? 600 : filtered.count }
        capped = filtered.count > shownCap
        if capped { filtered = Array(filtered.prefix(shownCap)) }
        rows = filtered
        groups = fillGaps(groupByDay(filtered))
        // 596 同日一并算一次 (同一次 applyFilter 内的同一份日志缓存, 不另起一遍 IO)
        damageDays = RecordSearch.damageDays(macs: macs)
    }

    // ---------- applyFilter 的阶段拆分（2026-10-29：原 183 行 → 7 段，每段可单独测） ----------

    /// 770 全部锁: Rec 池 → RowVM（行首带锁名小标签，575 越界窗口小字）。单锁直接复用 allRows。
    func buildPool(_ recs: [Rec]) -> [RowVM] {
        var pool: [RowVM]
        if scope == 0 {
            pool = allRows
        } else {
            // 770 全部锁: Rec 池 → RowVM (行首带锁名小标签, 575 越界窗口小字)
            let outWins = RecordSearch.outOfWindow(macs: macs)
            var winMap = [String: String]()
            for w in outWins { winMap[RecordOverlay.oid(mac: w.rec.mac, rowKey: w.rec.key)] = w.window }
            pool = recs.map { r in
                let p = Self.rowParts(r.timeStr, todayKey: todayKey)
                return RowVM(key: RecordOverlay.oid(mac: r.mac, rowKey: r.key), time: p.time, dayKey: p.dayKey,
                             hour: p.hour, type: r.type,
                             title: Self.recTitle(r), whoId: r.whoId, whoKind: r.kind,
                             kind: r.kind, lockName: r.lockName, rowMac: r.mac,
                             credKey: Self.recCredNav(r),
                             winText: winMap[RecordOverlay.oid(mac: r.mac, rowKey: r.key)] ?? "",
                             warn: r.alarm, claim: false, care: r.care)
            }
        }
        return pool
    }

    /// 593 日界收尾口径: 一天条数与最晚时刻取自**未筛未截**的行池。
    func computeDayTotals(_ pool: [RowVM]) {
        var dayCount: [String: Int] = [:]
        var dayEndBy: [String: String] = [:]
        for r in pool {
            // 592 折起来的尾行也属于这一天: 条数连尾一起数。
            dayCount[r.dayKey, default: 0] += 1
            // 最晚时刻 = 这一天在池里**第一次出现**的那一行 —— 行池本身就是按锁端时刻倒序排好的
            // (render 与 buildRecs 各排一次, 用的都是 "yyyy-MM-dd HH:mm:ss" 串序 = 时间序, 跨年也成立;
            //  下面"按天分组: 日志本身已是时间倒序, 保持首现顺序即可"吃的是同一条前提)。
            // 刻意不用"把显示时刻串取字典序最大"当最晚 (旧写法): 日组是按 649 归过属的, 12-31 那一组里
            // 会混进元旦凌晨 00:xx 的行, 而 "12-31 …" 的字典序大于 "01-01 …" ⇒ 旧写法会在每个跨年日组
            // 把"当日最晚"说成前一晚的 23:47。倒序首现不需要比较, 也就不吃这个亏。
            if dayEndBy[r.dayKey] == nil, Self.isClockish(r.time) { dayEndBy[r.dayKey] = r.time }
        }
        dayFullCount = dayCount
        dayLatest = dayEndBy
    }

    /// 成员 / 未知 / 访客 / 保养 过滤（793 / 791 / 1028）。
    func applyMemberFilter(_ pool: [RowVM]) -> [RowVM] {
        var filtered = pool
        switch sel {
        case "": break
        case "__unknown": filtered = pool.filter { $0.whoId == nil && $0.whoKind != "temp" }
        case MemberHub.visitorId: filtered = pool.filter { $0.whoId == nil && $0.whoKind == "temp" }
        case "__care": filtered = pool.filter { $0.care }
        default: filtered = pool.filter { $0.whoId == sel }
        }
        return filtered
    }

    /// 551/554/555 文本检索: 正词全中 + 负词全不中 + 时间短语窗 + 告警/凭证类词。
    func applyTextSearch(_ pool: [RowVM]) -> [RowVM] {
        let q = RecordSearch.parse(searchText)
        // 551 搜索面补齐: 占位文案写着「成员 / 凭证 / 备注」, 而拼接只有 title + 锁名 + 成员名 ——
        // 186 备注与 568 凭证标签压根不在搜索面上, 等于界面承诺了一个检索不到东西的热区。
        //   · 备注的存储键本身就是 mac#行键 (RecordOverlay.setNote 写进去的就是 `oid`), 所以直接并表,
        //     不在这里二次换算;
        //   · 凭证标签 (含 310 别名) 只有 Rec 带得动, 出处就是刚喂好的 recPool —— 单锁模式现在也有池子,
        //     这正是本批补的那一条。
        // 两张表都在筛选循环**外面**各建一次: RecordOverlay.notes 每次调用都要解一遍 JSON,
        // 放进逐行判据里就是一千行解一千次。
        var noteByOid: [String: String] = [:]
        for m in macs { noteByOid.merge(RecordOverlay.notes(m)) { _, newest in newest } }
        var credByOid: [String: String] = [:]
        for x in recPool { credByOid[RecordOverlay.oid(mac: x.mac, rowKey: x.key)] = x.cred }
        // 2026-10-30 性能：`DB.member(id)` 原来在**每行**都调一次（各自解析一份成员字典）。
        // 搜索是边输入边重算的热路径，一次建表。
        let memberNames = Dictionary(DB.members().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return pool.filter { r in
            let whoStr = r.whoId.flatMap { memberNames[$0] } ?? ""
            let txt = RecordSearch.searchFace(title: r.title, lockName: r.lockName, whoName: whoStr,
                                              cred: credByOid[r.id] ?? "", note: noteByOid[r.id] ?? "")
            let memberHit = q.member.map { txt.localizedCaseInsensitiveContains($0) } ?? false
            let mustHit = q.must.isEmpty || q.must.allSatisfy { txt.localizedCaseInsensitiveContains($0) } || memberHit
            let notHit = q.not.allSatisfy { !txt.localizedCaseInsensitiveContains($0) }
            guard mustHit, notHit else { return false }
            if q.alarmOnly, !r.warn { return false }
            if let k = q.credKind, r.kind != k { return false }
            // 554 时间短语: 按 562 口径落在窗内 (行级时刻近似: 日 + 时分)
            if let rng = q.range, let d = rowDate(r) {
                if d < rng.from || d > rng.to { return false }
            }
            return true
        }
    }

    /// 564/571/572/567/568/569 结构化过滤（时段 / 周末 / 告警类型 / 凭证类型）。
    func applyStructuredFilters(_ pool: [RowVM]) -> [RowVM] {
        return pool.filter { r in
            let hour = r.hour >= 0 ? r.hour : -1
            if hour >= 0 {
                // 672: 传行的归属日键 (与 RecordSearch 内部判定同一口径, 凌晨已归前一晚)
                if filters.lateNight && !RecordSearch.isLateNight(hour, dayKey: r.dayKey) { return false }
                switch filters.segment {
                case 1: if !(6...9).contains(hour) { return false }
                case 2: if !(10...14).contains(hour) { return false }
                case 3: if !(15...21).contains(hour) { return false }
                case 4: if !RecordSearch.isLateNight(hour, dayKey: r.dayKey) { return false }
                default: break
                }
                if let d = RecordSearch.dateFromKey(r.dayKey) {
                    let wk = WeekCal.gregorian.component(.weekday, from: d)
                    let isWeekend = wk == 1 || wk == 7
                    if filters.dayKind == 1 && isWeekend { return false }
                    if filters.dayKind == 2 && !isWeekend { return false }
                }
            } else if filters.segment != 0 || filters.lateNight || filters.dayKind != 0 {
                return false   // 时刻未知行不进时段/周末口径
            }
            if filters.alarmOnly && !r.warn { return false }
            // 565 类型多选: 只留选中的告警类型 (选中集全是告警类, 天然只出告警行; 与 567 可叠加取交集)
            if !filters.alarmKinds.isEmpty, !filters.alarmKinds.contains(r.type) { return false }
            // ⚠569: 锁端仅记录告警级 (10/13/224) + 手机侧失败行, 无逐次失败明细
            if !filters.kind.isEmpty, r.kind != filters.kind { return false }
            return true
        }
    }

    /// 按天分组: 日志本身已是时间倒序, 保持首现顺序即可。
    func groupByDay(_ rows: [RowVM]) -> [DayGroup] {
        var order: [String] = []
        var buckets: [String: [RowVM]] = [:]
        for r in rows {
            if buckets[r.dayKey] == nil { order.append(r.dayKey) }
            buckets[r.dayKey, default: []].append(r)
        }
        return order.map { key in
            DayGroup(key: key, rows: buckets[key] ?? [])
        }
    }

    /// 657/675 补缺口行。三个前提都是「别把筛掉的痕迹说成空档」。
    func fillGaps(_ input: [DayGroup]) -> [DayGroup] {
        var groups = input
        var filled: [DayGroup] = []
        for i in 0..<groups.count {
            filled.append(groups[i])
            guard i + 1 < groups.count,
                  !groups[i].isNone, !groups[i + 1].isNone,
                  let newer = RecordSearch.dateFromKey(groups[i].key),
                  let older = RecordSearch.dateFromKey(groups[i + 1].key) else { continue }
            // 相隔天数要**就近取整**而不是截断：原本写的是 `(elapsed - 43_200) / 86_400`，
            // 减半天再截断 = 比"向下取整"还早一格 ⇒ 相隔 N 天算出 N-1，于是
            //   · 只缺一天时 gap = 1，被 `gap >= 2` 挡掉 ⇒ **空了一整天从来不补** (675 那行"缺口"永远少一段)；
            //   · 缺 N 天的那条汇总行报 `missing = N-1` ⇒ 「N 天无记录」恒定少说一天。
            // 改成 + 半天再截断：N=1 相邻 ⇒ 1、N=2 ⇒ 2 (missing 1) …；有夏令时的日子两天可能只差 23 小时，
            // 就近取整同样落对 (减半天那版会把 23 小时当成一天、把 47 小时当成两天)。见 §10.33。
            let gap = Int((newer.timeIntervalSince(older) + 43_200) / 86_400)
            guard gap >= 2 else { continue }
            let missing = gap - 1
            if missing > 7 {
                var hol: String? = nil
                for k in 1...min(missing, 45) where hol == nil {
                    hol = RecordSearch.holidayName(RecordSearch.dayKeyOf(WeekCal.shifted(older, days: k)))
                }
                filled.append(DayGroup(key: "gap-" + groups[i + 1].key, rows: [],
                                       isGap: true, gapDays: missing, gapHoliday: hol))
            } else {
                for k in 1...missing {
                    let dk = RecordSearch.dayKeyOf(WeekCal.shifted(older, days: k))
                    filled.append(DayGroup(key: "gap-" + dk, rows: [],
                                           isGap: true, gapDays: 1, gapHoliday: RecordSearch.holidayName(dk)))
                }
            }
        }
        groups = filled
        return groups
    }
}
