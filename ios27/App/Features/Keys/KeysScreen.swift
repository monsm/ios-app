// KeysScreen.swift —— 凭证（Tab 2）。v7 结构重写，参考 R2-credentials.html / TOKENS.md 参考 B。
//
// 实测来源：芯片行 left 14.67 / 芯片 53、102、120 三档宽 / 高 53.3 r14；大标题 29pt/700 left 29.67；
// 正文 17/23 #919096；卡片 #232227 r27 内边距 16.3；分段环 Ø92 环宽 20.3 段间 4–5°；
// 三环 Ø88 按 V.Ring.lineWidth = min(14, size*0.09) 自适应环宽；卡头 11pt/500 #A2A1A6。
// 数据绑定保持原口径：AppModel.keys / lock / members、KeysState、KeysRoute、Router 跳转不变。
import SwiftUI

struct KeysScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) internal var router
    @State private var filter: KeysFilter = .all
    @State internal var now: Int64 = KeysState.now()
    @State private var search = ""
    @State private var groupByOwner = CredentialOrg.groupMode == .owner
    /// 只为"删除一条搜索历史"这种**不在视图状态里**的改动触发重绘
    /// （搜索历史存在 UserDefaults，不由任何 @State 承载 —— 与其它页的 `tick` 同一用途）。
    @State private var tick = 0

    private var searchText: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filtered: [KeyItem] {
        app.keys.filter { key in
            guard filter.matches(key) else { return false }
            guard !searchText.isEmpty else { return true }
            let hay = [key.name, key.owner ?? "", key.kind.rawValue, key.code ?? ""]
                .joined(separator: " ")
                .lowercased()
            return hay.contains(searchText)
        }
    }

    /// 按成员分组（原 CredentialActions.swift:349-408）：没有归属的归到「未归属」，不猜。
    /// 2026-11-02：**先归一再加桶**。`key.owner` 历史上存过成员 id 与成员名字两种值，
    /// 直接拿原值当桶键会把同一个人拆成两组（"22C255CE" 一组、"张三" 一组）。
    /// 归一只走 `CredentialOrg.ownerName`（它已处理 id / 名字两种口径），空则「未归属」。
    private var grouped: [(owner: String, items: [KeyItem])] {
        var order: [String] = []
        var buckets: [String: [KeyItem]] = [:]
        for key in filtered {
            let resolved = CredentialOrg.ownerName(key.owner)
            let bucket = resolved.isEmpty ? "未归属" : resolved
            if buckets[bucket] == nil { order.append(bucket) }
            buckets[bucket, default: []].append(key)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var validCount: Int {
        app.keys.filter { !$0.disabled && !KeysState.expired($0, now: now) }.count
    }

    private var nearestDays: Int? {
        app.keys
            .filter { !$0.disabled && !KeysState.expired($0, now: now) }
            .compactMap { KeysState.daysLeft($0, now: now) }
            .min()
    }

    private var residentCount: Int {
        app.keys.filter { $0.kind == .password || $0.kind == .fingerprint }.count
    }

    private var tempCount: Int {
        app.keys.filter { $0.kind == .temp }.count
    }

    private var mobileCount: Int {
        app.keys.filter { $0.kind == .mobile }.count
    }

    var body: some View {
        // 全换系统：容器是系统 List，分组是系统 Section(header:)。
        // V7KeyRow 保留原样（凭证行有状态点、逐位打码与到期读数，不是普通列表行）。
        List {
            Section {
                chips
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                // 页头自带 pageGutterB 的缩进改由 `headerRow(gutter:)` 表达（视觉不变，
                // 但行对齐检查器能看见它）—— 否则它会被误判成「页头比卡片更靠边」。
                header.headerRow(gutter: V.S.pageGutterB)
                if app.ledgerCorrupt {
                    // 2026-11-01（Round 320）：台账读不出来时，写入会被静默拒绝 —— 必须让用户知道。
                    // 不写「损坏」这种吓人的词做断言（可能只是版本不兼容），只说清后果与出路。
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            Text("本机凭证台账读不出来")
                                .font(V.F.bodyStrong)
                                .foregroundStyle(V.C.critical)
                            SettingsNote(text: "当前会话里对凭证的改动**不会保存**（写入会被拒绝）。" +
                                         "请先到「备份工作室」从一份备份恢复，再继续操作。")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardGutter, bottom: 0, trailing: V.S.cardGutter))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }

            if app.lock == nil {
                Section {
                    noLockBlock
                        .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardGutter, bottom: 0, trailing: V.S.cardGutter))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else if app.keys.isEmpty {
                Section {
                    emptyBlock
                        .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardGutter, bottom: 0, trailing: V.S.cardGutter))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    validityCard
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    familyCard
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    // 2026-11-02（R7 收尾）：原「本机安全」卡（securityCard）已删。
                    // 它整张卡只有「已启用 / 范围 / 全量」三个**常量字面量** + 一个盾牌渐变图标 ——
                    // 没有数据源、没有动作、没有跳转，是 ui-ia.md §4.4 的 Z1「纯装饰卡片」。
                    // 真正的安全设置入口在「设置 → 安全中心」，那里有真开关与真读数。
                    filterBlock
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ledgerBlock
            }

            shortcutsBlock
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V.C.bg.ignoresSafeArea())
        // 全换系统：用系统导航栏 + 系统搜索，不再把大标题画在页面里、也不自绘搜索框。
        .navigationTitle("钥匙")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜名称 / 归属 / 类型")
        .onSubmit(of: .search) {
            // 函数内已挡空串；这里再挡一次是为了不产生"提交了但什么都没发生"的感觉。
            if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CredentialOrg.pushSearchHistory(search)
            }
        }
        .task { await app.reload(refreshStatus: false) }
        .onAppear {
            now = KeysState.now()
            // 2026-11-01（Round 239）：老人模式会**隐藏**「临时码 / 手机钥匙」两个芯片，
            // 而 `filter` 仍可能是它们（在开启老人模式之前选的）—— 于是列表被一个**看不见的筛选**卡住，
            // 用户只看到几条凭证却没有任何芯片是高亮的。回落到「全部」。
            if !visibleFilters.contains(filter) { filter = .all }
            routeFromContext()
        }
        // E-12：`now` 只在 onAppear 刷新 ⇒ 跨过零点后"还剩 N 天"的角标与颜色不更新
        // （App 在前台挂着过夜是很常见的）。这里按分钟重算一次，成本只有一次 Date()。
        .task(id: "clock") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                now = KeysState.now()
            }
        }
    }

    // MARK: - 芯片行（R2：left 14.67 / 三档宽度）

    /// 当前可见的筛选芯片（老人模式只留 全部/密码/指纹）。
    /// 芯片行与 `onAppear` 的回落都用它 —— 两处各写一遍那个过滤式必然会分叉。
    private var visibleFilters: [KeysFilter] {
        KeysFilter.allCases.filter { !MemberHub.elderMode || $0 == .all || $0 == .password || $0 == .fingerprint }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: V.S.chipGap) {
                VChip(
                    title: "",
                    value: "",
                    tint: V.C.text1,
                    style: .square,
                    systemImage: "line.3.horizontal"
                )
                VChip(
                    // R6：原来这里写「凭证 N 枚」—— 与环心（:255）和列表头计数是同一个数。
                    // 改成「有效 N」，是全页唯一一处「有效/总数」的对照读数（总数交给环心）。
                    title: "有效",
                    value: "\(validCount) 枚",
                    tint: V.C.blue,
                    style: .compact,
                    systemImage: "checkmark.seal.fill"
                )
                VChip(
                    title: "生物识别",
                    value: mobileCount > 0 ? "已开启" : "未开启",
                    tint: V.C.text1,
                    style: .wide,
                    systemImage: "faceid"
                )
                VChip(
                    title: "家庭组",
                    value: "\(app.members.count) 人",
                    tint: V.C.text1,
                    style: .standard,
                    systemImage: "person.2.fill"
                )
            }
            .padding(.horizontal, V.S.chipLeftB)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 导语（大标题交给系统导航栏，页内只留一句导语）

    private var header: some View {
        VStack(alignment: .leading, spacing: V.Page.titleToBody) {
            Text("家人、临时客人与服务人员共用一把门锁；过期自动失效，随时可撤销。")
                .font(V.F.pageLead)
                .foregroundStyle(V.C.text9)
                .lineSpacing(V.Page.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, V.Page.chipToTitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 卡 1：凭证有效（分段环）

    private var validityCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "门锁")
                HStack(alignment: .top, spacing: V.S.gapM) {
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        // R6（ui-ia §4.1）：原来这里还写了一遍「总数 N 枚」，与右侧环心（:256）
                        // 及下方「共 N 枚」是同一个数 —— 一页 5 次。现在只留环心 + 列表计数。
                        Text("凭证有效")
                            .font(V.F.chipValue)
                            .foregroundStyle(V.C.text1)
                        Text("含密码 / 指纹 / 临时码 / 手机钥匙")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
                    }
                    Spacer(minLength: 0)
                    VSegmentedRing(segments: kindSegments, center: "\(app.keys.count)")
                }
                .padding(.top, V.S.gapS)
                VDivider()
                HStack(alignment: .top, spacing: V.S.gapM) {
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text("有效")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
                        Text("\(validCount) 枚")
                            .font(V.F.bedValue)
                            .foregroundStyle(V.C.text1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text("最早到期")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
                        Text(nearestDays.map { "\($0) 天后" } ?? "永久")
                            .font(V.F.bedValue)
                            .foregroundStyle(V.C.text1)
                    }
                }
                .padding(.top, V.S.gapXXS)
                VDivider()
                Text("凭证台账来自本机存储，不联网、不上传。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var kindSegments: [(Double, Color)] {
        let total = max(app.keys.count, 1)
        let resident = Double(residentCount) / Double(total)
        let temp = Double(tempCount) / Double(total)
        let mobile = Double(mobileCount) / Double(total)
        return [
            (max(0.02, resident), V.C.mint),
            (max(0.02, temp), V.C.coral),
            (max(0.02, mobile), V.C.indigo)
        ]
    }

    // MARK: - 卡 2：家庭（三环 + 图例）

    private var familyCard: some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "家庭")
                HStack(alignment: .top, spacing: V.S.gapM) {
                    VStack(alignment: .leading, spacing: V.S.gapS) {
                        legendRow(title: "常驻", count: residentCount, color: V.C.pink)
                        legendRow(title: "临时", count: tempCount, color: V.C.rewardGreen)
                        legendRow(title: "服务", count: mobileCount, color: V.C.rewardBlue)
                    }
                    Spacer(minLength: 0)
                    VRingStack(rings: familyRings, size: 88)
                }
                .padding(.top, V.S.gapS)
                VDivider()
                VStatPair(items: [
                    ("最近使用", nearestDays.map { "\($0) 天后到期" } ?? "永久"),
                    ("最早到期", earliestExpiryText)
                ])
                .padding(.top, V.S.gapXXS)
                VDivider()
                // R6：原来这句又写一遍 validCount（已是本页第 3 次）。改写成不带数字的说明 ——
                // 计数统一由「芯片·有效」与「列表头·N 枚」承担。
                Text("全部在本机核对，不联网。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legendRow(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: V.S.gapS) {
            Circle()
                .fill(color)
                .frame(width: V.List.ringDotSize, height: V.List.ringDotSize)
            Text(title)
                .font(V.F.legendLabel)
                .foregroundStyle(V.C.text1)
            Text("\(count)")
                .font(V.F.displayC)
                .foregroundStyle(V.C.text1)
                .monospacedDigit()
            Text("枚")
                .font(V.F.micro)
                .foregroundStyle(V.C.text3)
        }
        .frame(minHeight: 20)
        .accessibilityElement(children: .combine)
    }

    private var familyRings: [(Double, Color)] {
        let total = max(app.keys.count, 1)
        return [
            (Double(residentCount) / Double(total), V.C.pink),
            (Double(tempCount) / Double(total), V.C.rewardGreen),
            (Double(mobileCount) / Double(total), V.C.rewardBlue)
        ]
    }

    private var earliestExpiryText: String {
        let candidates = app.keys.compactMap { $0.expiresAt }.sorted()
        guard let first = candidates.first else { return "永久" }
        return TimeFormat.dayShort(first)
    }


    private var filterBlock: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("全部凭证")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
            if search.isEmpty, !CredentialOrg.searchHistory().isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: V.S.gapS) {
                        Text("最近搜索")
                            .font(V.F.unit)
                            .foregroundStyle(V.C.text3)
                        // `searchHistory()` 读的是 UserDefaults，不由任何 @State 承载 ——
                        // 删除后视图不会自动重绘。在闭包首行读一次 `tick` 建立依赖（最小侵入）。
                        ForEach(CredentialOrg.searchHistory(), id: \.self) { term in
                            let _ = tick   // 读取以建立依赖
                            Button { search = term } label: {
                                VTag(text: term, tint: V.C.text2, filled: false)
                            }
                            .buttonStyle(.plain)
                            // 长按删除这一条 —— `CredentialOrg.removeSearchHistory` 早在 531 就写好了，
                            // 一直没有入口（记为「保留未接」）。这里接上，与 DoorScreen 快捷磁贴的
                            // "轻点执行、长按编辑"同一套手势约定。
                            .onLongPressGesture(minimumDuration: 0.5) {
                                CredentialOrg.removeSearchHistory(term)
                                tick += 1
                            }
                            .accessibilityLabel("搜索 \(term)")
                            .accessibilityHint("长按可删除这条搜索记录")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            ScrollView(.horizontal) {
                HStack(spacing: V.S.gapS) {
                    ForEach(visibleFilters, id: \.self) { item in
                        let selected = item == filter
                        Button {
                            filter = item
                        } label: {
                            Text(chipTitle(item))
                                .font(V.F.footnote)
                                .foregroundStyle(selected ? V.C.text1 : V.C.text3)
                                .padding(.horizontal, V.S.gapM)
                                .padding(.vertical, V.S.gapS)
                                .background(selected ? V.C.card : Color.clear, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(selected ? V.C.tabEdge : V.C.hairline, lineWidth: V.S.hair)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                    Button {
                        groupByOwner.toggle()
                        CredentialOrg.setGroupMode(groupByOwner ? .owner : .type)
                    } label: {
                        Text(groupByOwner ? "按成员分组" : "按类型分组")
                            .font(V.F.footnote)
                            .foregroundStyle(groupByOwner ? V.C.text1 : V.C.text3)
                            .padding(.horizontal, V.S.gapM)
                            .padding(.vertical, V.S.gapS)
                            .background(groupByOwner ? V.C.card : Color.clear, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(groupByOwner ? V.C.tabEdge : V.C.hairline, lineWidth: V.S.hair)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换为\(groupByOwner ? "按类型" : "按成员")分组")
                    .accessibilityAddTraits(groupByOwner ? [.isButton, .isSelected] : .isButton)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, V.S.gapL)
    }

    private func chipTitle(_ item: KeysFilter) -> String {
        let count = app.keys.filter { item.matches($0) }.count
        return "\(item.title) \(count)"
    }

    @ViewBuilder
    private var ledgerBlock: some View {
        if filtered.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: V.S.gapS) {
                    Text(searchText.isEmpty ? emptyFilterText : "没有找到「\(search)」")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !searchText.isEmpty {
                        VOutlineButton(title: "清空搜索", systemImage: "xmark.circle") { search = "" }
                        VOutlineButton(title: "改为按成员分组重搜", systemImage: "person.2") {
                            groupByOwner = true
                            CredentialOrg.setGroupMode(.owner)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardGutter, bottom: 0, trailing: V.S.cardGutter))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                Text(searchText.isEmpty ? (filter == .all ? "全部凭证" : filter.title) : "搜索结果")
            }
        } else if groupByOwner {
            ForEach(Array(grouped.enumerated()), id: \.offset) { pair in
                Section {
                    ForEach(Array(pair.element.items.enumerated()), id: \.offset) { row in
                        keyRow(row.element)
                    }
                } header: {
                    HStack(spacing: V.S.gapS) {
                        // 桶键已是归一后的显示名；这里再走一次 ownerName 兜底（别名开关改动后仍正确）。
                        Text(CredentialOrg.ownerName(pair.element.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(pair.element.owner))
                        Spacer(minLength: 0)
                        Text("\(pair.element.items.count) 枚")
                            .monospacedDigit()
                    }
                    .textCase(nil)
                }
            }
        } else {
            Section {
                ForEach(Array(filtered.enumerated()), id: \.offset) { row in
                    keyRow(row.element)
                }
            } header: {
                HStack(spacing: V.S.gapS) {
                    Text(filter == .all ? "全部凭证" : filter.title)
                    Spacer(minLength: 0)
                    Text("\(filtered.count) 枚")
                        .monospacedDigit()
                }
                .textCase(nil)
            }
        }
    }

    /// 单条凭证行：V7KeyRow 原样保留，只把外层从「VCard 里的 VStack」换成 List 行。
    @ViewBuilder
    private func keyRow(_ item: KeyItem) -> some View {
        Button {
            KeysRoute.openDetail(item.id, router: router)
        } label: {
            V7KeyRow(key: item, now: now)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开凭证详情")
    }

    private var emptyFilterText: String {
        switch filter {
        case .all: return "还没有凭证。用下面的「新增凭证」加一枚密码，家人就能用密码开门了。"
        case .password: return "还没有密码。新增凭证里第一步选「密码」就能加一枚 6~8 位数字。"
        case .fingerprint: return "还没有指纹。指纹要在门锁上按 8 次录入，进「新增凭证」选「指纹」。"
        case .temp: return "还没有临时码。给保洁、装修工发一张限期码，到期自动失效。"
        case .mobile: return "还没有手机钥匙。用手机开门要先签一把钥匙，进「手机钥匙」页。"
        }
    }

    // MARK: - 空态（保留原入口）

    private var noLockBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有添加门锁")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("凭证是挂在某一把具体的锁上的。先把锁恢复出厂（长按 RESET 到三声嘀），再回来添加。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
            }
        }
        .padding(.top, V.S.gapL)
    }

    private var emptyBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("这把锁还没有凭证")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("先加一枚密码 —— 家人不用带钥匙，报一串数字就能开门。之后可以再录指纹、发临时码。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "新增凭证", systemImage: "key.horizontal.fill") {
                    router.request(.dest(.keyCreate))
                }
            }
        }
        .padding(.top, V.S.gapL)
    }

    // MARK: - 次级入口（保留全部 Router 入口）

    private var shortcutsBlock: some View {
        Section {
            VListRow(
                title: "新增凭证",
                detail: "密码 / 指纹 / 临时码",
                systemImage: "plus.circle.fill",
                tint: V.C.rewardBlue
            ) { router.request(.dest(.keyCreate)) }
            // 来源：原 App/UI/CredentialOtp.swift（动态临时密码）+ CredentialCenterView（凭证整理）。
            if !MemberHub.elderMode {
                VListRow(
                    title: "凭证工作室",
                    detail: "批量 / 回收站 / 版本 / 预警 / 导出 / 检测",
                    systemImage: "wrench.and.screwdriver.fill",
                    tint: V.C.purple
                ) { router.request(.dest(.credentialStudio)) }
            }
            VListRow(
                title: "动态密码",
                detail: "按锁端周期生成 6 位 ZOTP 码",
                systemImage: "clock.badge.questionmark",
                tint: V.C.miniBlue
            ) { router.request(.dest(.zotp)) }
            VListRow(
                title: "到期月历",
                detail: "看这个月哪天有凭证到期",
                systemImage: "calendar",
                tint: V.C.purple
            ) { router.request(.dest(.keyCalendar)) }
            VListRow(
                title: "手机钥匙",
                detail: "给家人的手机签一把钥匙",
                systemImage: "iphone.gen3",
                tint: V.C.rewardGreen
            ) { router.request(.dest(.mobileKey)) }
            if !MemberHub.elderMode {
                VListRow(
                    title: "分享给安卓",
                    detail: "扫码把开锁凭证导到安卓手机",
                    systemImage: "qrcode",
                    tint: V.C.coral
                ) { router.request(.dest(.shareToAndroid)) }
            }
        } header: {
            Text("凭证工具")
        }
    }

    /// 别的 Tab 用 .key(id:) 跳过来时，Router 只切 Tab 不 push —— 这里接住，推进详情。
    private func routeFromContext() {
        guard case .key(let id) = router.pending else { return }
        KeysRoute.openDetail(id, router: router)
    }
}

// MARK: - v7 凭证行（保留原有 KeysState 语义）

private struct V7KeyRow: View {
    let key: KeyItem
    let now: Int64

    private var rowSubtitle: String {
        var bits: [String] = [key.kind.rawValue]
        // 内部值出屏：key.owner 可能是成员 id，先换成可读名字；空/解析不到就不占位。
        let owner = CredentialOrg.ownerName(key.owner)
        if !owner.isEmpty { bits.append(owner) }
        if let code = key.code, !code.isEmpty { bits.append(code) }
        return bits.joined(separator: " · ")
    }

    private var rowTint: Color {
        if key.disabled { return V.C.text4 }
        guard let days = KeysState.daysLeft(key, now: now) else { return V.C.rewardGreen }
        if days < 0 { return V.C.red }
        if days <= 3 { return V.C.coral }
        return V.C.rewardGreen
    }

    var body: some View {
        let read = KeysState.expiryReading(key, now: now)
        HStack(spacing: V.S.gapM) {
            Circle()
                .fill(rowTint)
                .frame(width: V.List.dotSize, height: V.List.dotSize)
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(key.name)
                    .font(V.F.rowTitle)
                    .foregroundStyle(key.disabled ? V.C.text3 : V.C.text1)
                    .lineLimit(1)
                Text(rowSubtitle)
                    .font(V.F.rowDetail)
                    .foregroundStyle(V.C.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: V.S.gapS)
            Text(read.value)
                .font(V.F.rowDetail)
                .foregroundStyle(read.tint)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(V.F.chevron)
                .foregroundStyle(V.C.text4)
                .accessibilityHidden(true)
        }
        .frame(minHeight: V.List.rowMinHeight + (SettingsStore.shared.rowHeight == "tall" ? V.List.rowTallExtra : 0))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.name)，\(key.kind.rawValue)，\(KeysState.word(key, now: now))")
    }
}

#Preview("KeysScreen") {
    NavigationStack {
        KeysScreen()
    }
    .environment(AppModel())
    .environment(Router())
}
