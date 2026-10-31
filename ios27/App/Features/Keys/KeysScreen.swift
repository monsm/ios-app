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
    private var grouped: [(owner: String, items: [KeyItem])] {
        var order: [String] = []
        var buckets: [String: [KeyItem]] = [:]
        for key in filtered {
            let owner = (key.owner?.isEmpty == false) ? (key.owner ?? "") : "未归属"
            if buckets[owner] == nil { order.append(owner) }
            buckets[owner, default: []].append(key)
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
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                chips
                header
                if app.lock == nil {
                    noLockBlock
                } else if app.keys.isEmpty {
                    emptyBlock
                } else {
                    validityCard
                    familyCard
                    securityCard
                    filterBlock
                    ledgerBlock
                }
                shortcutsBlock
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.S.gapL)
        }
        .background(V.C.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await app.reload(refreshStatus: false) }
        .onAppear {
            now = KeysState.now()
            routeFromContext()
        }
    }

    // MARK: - 芯片行（R2：left 14.67 / 三档宽度）

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
                    title: "凭证",
                    value: "\(app.keys.count) 枚",
                    tint: V.C.blue,
                    style: .compact,
                    systemImage: "circle.hexagongrid.fill"
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

    // MARK: - 标题 + 导语（R2：left 29.67 / 29pt / 17:23）

    private var header: some View {
        VStack(alignment: .leading, spacing: V.Page.titleToBody) {
            Text("凭证")
                .font(V.F.displayB)
                .foregroundStyle(V.C.text1)
            Text("家人、临时客人与服务人员\n共用一把门锁；过期自动失效，\n随时可撤销。")
                .font(V.F.pageLead)
                .foregroundStyle(V.C.text9)
                .lineSpacing(V.Page.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.pageGutterB)
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
                        Text("凭证有效")
                            .font(V.F.chipValue)
                            .foregroundStyle(V.C.text1)
                        Text("总数")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
                        Text("\(app.keys.count) 枚")
                            .font(V.F.bedValue)
                            .foregroundStyle(V.C.text1)
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
                        Text("共 \(app.keys.count) 枚")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
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
        .padding(.horizontal, V.S.cardGutter)
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
                Text("今日已核验 \(validCount) 枚凭证，全部在本机核对。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
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

    // MARK: - 卡 3：本机安全

    private var securityCard: some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "本机安全")
                HStack(alignment: .center, spacing: V.S.gapM) {
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text("已启用")
                            .font(V.F.chipValue)
                            .foregroundStyle(V.C.text1)
                        Text("范围")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
                        Text("全量")
                            .font(V.F.bedValue)
                            .foregroundStyle(V.C.text1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.shield.fill")
                        .font(V.F.heroGlyph56)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [V.C.red.opacity(0.75), V.C.pink]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 筛选 + 凭证台账（保留原有数据绑定）

    private var filterBlock: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("全部凭证")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
            HStack(spacing: V.S.gapS) {
                Image(systemName: "magnifyingglass")
                    .font(V.F.icon15)
                    .foregroundStyle(V.C.text3)
                    .accessibilityHidden(true)
                TextField("搜名称 / 归属 / 类型", text: $search)
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("搜索凭证")
                    .onSubmit { CredentialOrg.pushSearchHistory(search) }
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(V.F.icon15)
                            .foregroundStyle(V.C.text3)
                    }
                    .accessibilityLabel("清空凭证搜索")
                }
            }
            .padding(.horizontal, V.S.gapM)
            .frame(minHeight: V.Metric.searchRow)
            .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.control))

            if search.isEmpty, !CredentialOrg.searchHistory().isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: V.S.gapS) {
                        Text("最近搜索")
                            .font(V.F.unit)
                            .foregroundStyle(V.C.text3)
                        ForEach(CredentialOrg.searchHistory(), id: \.self) { term in
                            Button { search = term } label: {
                                VTag(text: term, tint: V.C.text2, filled: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("搜索 \(term)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            ScrollView(.horizontal) {
                HStack(spacing: V.S.gapS) {
                    ForEach(KeysFilter.allCases.filter { !MemberHub.elderMode || $0 == .all || $0 == .password || $0 == .fingerprint }, id: \.self) { item in
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
        .padding(.horizontal, V.S.cardGutter)
        .padding(.top, V.S.gapL)
    }

    private func chipTitle(_ item: KeysFilter) -> String {
        let count = app.keys.filter { item.matches($0) }.count
        return "\(item.title) \(count)"
    }

    private var ledgerBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack {
                    Text(filter == .all ? "全部凭证" : filter.title)
                        .font(V.F.cardTitle)
                        .foregroundStyle(V.C.text6)
                    Spacer(minLength: 0)
                    Text("\(filtered.count) 枚")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                        .monospacedDigit()
                }
                if filtered.isEmpty {
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
                } else if groupByOwner {
                    VStack(alignment: .leading, spacing: V.S.gapM) {
                        ForEach(Array(grouped.enumerated()), id: \.offset) { pair in
                            VStack(alignment: .leading, spacing: V.S.gapS) {
                                HStack(spacing: V.S.gapS) {
                                    Text(pair.element.owner)
                                        .font(V.F.cardTitle)
                                        .foregroundStyle(V.C.text6)
                                    Spacer(minLength: 0)
                                    Text("\(pair.element.items.count) 枚")
                                        .font(V.F.unit)
                                        .foregroundStyle(V.C.text3)
                                        .monospacedDigit()
                                }
                                rows(pair.element.items)
                            }
                        }
                    }
                } else {
                    rows(filtered)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func rows(_ items: [KeyItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                if pair.offset > 0 { VDivider() }
                Button {
                    KeysRoute.openDetail(pair.element.id, router: router)
                } label: {
                    V7KeyRow(key: pair.element, now: now)
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开凭证详情")
            }
        }
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
        .padding(.horizontal, V.S.pageGutterB)
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
        .padding(.horizontal, V.S.pageGutterB)
        .padding(.top, V.S.gapL)
    }

    // MARK: - 次级入口（保留全部 Router 入口）

    private var shortcutsBlock: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("凭证工具")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
            VCard {
                VStack(spacing: 0) {
                    VListRow(
                        title: "新增凭证",
                        detail: "密码 / 指纹 / 临时码",
                        systemImage: "plus.circle.fill",
                        tint: V.C.rewardBlue
                    ) { router.request(.dest(.keyCreate)) }
                    VDivider()
                    // 来源：原 App/UI/CredentialOtp.swift（动态临时密码）+ CredentialCenterView（凭证整理）。
                    if !MemberHub.elderMode {
                        VListRow(
                            title: "凭证工作室",
                            detail: "批量 / 回收站 / 版本 / 预警 / 导出 / 检测",
                            systemImage: "wrench.and.screwdriver.fill",
                            tint: V.C.purple
                        ) { router.request(.dest(.credentialStudio)) }
                        VDivider()
                    }
                    VListRow(
                        title: "动态密码",
                        detail: "按锁端周期生成 6 位 ZOTP 码",
                        systemImage: "clock.badge.questionmark",
                        tint: V.C.miniBlue
                    ) { router.request(.dest(.zotp)) }
                    VDivider()
                    VListRow(
                        title: "到期月历",
                        detail: "看这个月哪天有凭证到期",
                        systemImage: "calendar",
                        tint: V.C.purple
                    ) { router.request(.dest(.keyCalendar)) }
                    VDivider()
                    VListRow(
                        title: "手机钥匙",
                        detail: "给家人的手机签一把钥匙",
                        systemImage: "iphone.gen3",
                        tint: V.C.rewardGreen
                    ) { router.request(.dest(.mobileKey)) }
                    if !MemberHub.elderMode {
                        VDivider()
                        VListRow(
                            title: "分享给安卓",
                            detail: "扫码把开锁凭证导到安卓手机",
                            systemImage: "qrcode",
                            tint: V.C.coral
                        ) { router.request(.dest(.shareToAndroid)) }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
        .padding(.top, V.S.gapL)
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
        if let owner = key.owner, !owner.isEmpty { bits.append(owner) }
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
        .frame(minHeight: V.List.rowMinHeight)
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
