// KeysHomeScreen.swift —— 凭证（Tab 2）· V8 设计语言
//
// 与 KeysScreen 的功能对齐（这是"换皮不换能力"的第一页）：
//   · 芯片行（四类凭证 + 分段环微图标）
//   · 判断句大标题 + 因果段（一屏一个英雄数：有效枚数只出现在分段环心）
//   · 卡 1 凭证台账（分段环 + 彩色分类行 + 点线）
//   · 卡 2 到期压力（最近到期 / 已过期）
//   · 检索 + 类型筛选 + 按归属分组
//   · 六个工具入口
//   · 台账损坏 / 无门锁 / 无凭证 三种阻断态
//
// 数据绑定与 KeysScreen 完全一致：AppModel.keys / KeysState / CredentialOrg / KeysRoute。
import SwiftUI

struct KeysHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) internal var router

    @State private var filter: KeysFilter = .all
    @State internal var now: Int64 = KeysState.now()
    @State private var search = ""
    @State private var groupByOwner = CredentialOrg.groupMode == .owner
    /// 只为"删除一条搜索历史"这种不在视图状态里的改动触发重绘（历史存在 UserDefaults）。
    @State private var historyTick = 0

    private var searchText: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filtered: [KeyItem] {
        app.keys.filter { key in
            guard filter.matches(key) else { return false }
            guard !searchText.isEmpty else { return true }
            let hay = [key.name, CredentialOrg.ownerName(key.owner), key.owner ?? "", key.kind.rawValue, key.code ?? ""]
                .joined(separator: " ")
                .lowercased()
            return hay.contains(searchText)
        }
    }

    private var grouped: [(owner: String, items: [KeyItem])] {
        var order: [String] = []
        var buckets: [String: [KeyItem]] = [:]
        for key in filtered {
            let resolved = CredentialOrg.ownerName(key.owner)
            let owner = resolved.isEmpty ? "未归属" : resolved
            if buckets[owner] == nil { order.append(owner) }
            buckets[owner, default: []].append(key)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var validCount: Int {
        app.keys.filter { !$0.disabled && !KeysState.expired($0, now: now) }.count
    }

    private var expiredCount: Int {
        app.keys.filter { KeysState.expired($0, now: now) }.count
    }

    private var nearestDays: Int? {
        app.keys
            .filter { !$0.disabled && !KeysState.expired($0, now: now) }
            .compactMap { KeysState.daysLeft($0, now: now) }
            .min()
    }

    private func count(of kind: KeyItem.Kind) -> Int {
        app.keys.filter { $0.kind == kind }.count
    }

    /// 判断句：**不许重复英雄数**（V8 铁律 R4）。只描述状态与压力。
    private var judgement: String {
        if expiredCount > 0 { return "有 \(expiredCount) 枚已经过期" }
        if let days = nearestDays, days <= 3 {
            return days <= 0 ? "今天有凭证到期" : "有凭证马上到期"
        }
        return "凭证都在有效期内"
    }

    private var lead: String {
        var bits: [String] = []
        if let days = nearestDays {
            bits.append(KeysState.daysWord(days))
        } else {
            bits.append("全部永久有效")
        }
        bits.append("凭证台账只在本机，不联网、不上传。")
        return bits.joined(separator: "。")
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            chipRow
        } content: {
            if app.ledgerCorrupt {
                // 2026-11-05（对抗审查 · 流程不合理）：这张卡原来**没有按钮** ——
                // 唯一的出路「去备份工作室恢复」只写在一句话里，用户得自己找路。
                // 现在把那条出路变成可点的动作（动作与原因匹配：这不是重试能解决的）。
                VFailure(
                    what: "本机凭证台账读不出来",
                    why: "当前会话里对凭证的改动不会保存（写入会被拒绝）。",
                    next: "请先到「备份工作室」从一份备份恢复，再继续操作。",
                    retry: { router.request(.dest(.backup)) },
                    actionTitle: "去备份工作室"
                )
            }
            if app.lock == nil {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "凭证是挂在某一把具体的锁上的。先把锁恢复出厂（长按 RESET 到三声嘀），再回来添加。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else if app.keys.isEmpty {
                VEmpty(
                    title: "这把锁还没有凭证",
                    reason: "先加一枚密码 —— 家人不用带钥匙，报一串数字就能开门。之后可以再录指纹、发临时码。",
                    actionTitle: "新增凭证"
                ) { router.request(.dest(.keyCreate)) }
            } else {
                ledgerCard
                expiryCard
                searchCard
                toolsCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.keyCreate))
                } label: {
                    Image(systemName: "plus")
                        .font(V8.T.chipValue)
                }
                .accessibilityLabel("新增凭证")
            }
        }
        .task {
            await app.reload()
            groupByOwner = CredentialOrg.groupMode == .owner
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                now = KeysState.now()
            }
        }
        .onAppear {
            now = KeysState.now()
            groupByOwner = CredentialOrg.groupMode == .owner
        }
        .onChange(of: router.pending) { _, _ in
            if case .key(let id) = router.consume(if: { ctx in
                if case .key = ctx { return true }
                return false
            }) {
                KeysRoute.openDetail(id, router: router)
            }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        VChipRow2(
            items: KeysFilter.allCases,
            label: { item in item.title },
            value: { item in "\(count(for: item)) 枚" },
            icon: { item in chipIcon(item) },
            selection: $filter
        )
    }

    private func count(for item: KeysFilter) -> Int {
        app.keys.filter { item.matches($0) }.count
    }

    private func chipIcon(_ item: KeysFilter) -> VChipIcon {
        let total = max(1, app.keys.count)
        if item == .all {
            return .segmented([
                (Double(count(of: .password)), V8.D.passwordFill),
                (Double(count(of: .fingerprint)), V8.D.fingerprintFill),
                (Double(count(of: .temp)), V8.D.tempFill),
                (Double(count(of: .mobile)), V8.D.mobileFill)
            ])
        }
        return .ring(Double(count(for: item)) / Double(total), tint(for: item))
    }

    private func tint(for item: KeysFilter) -> Color {
        switch item {
        case .all: return V8.C.accent
        case .password: return V8.D.password
        case .fingerprint: return V8.D.fingerprint
        case .temp: return V8.D.temp
        case .mobile: return V8.D.mobile
        }
    }

    private func kindTint(_ kind: KeyItem.Kind) -> Color {
        switch kind {
        case .password: return V8.D.password
        case .fingerprint: return V8.D.fingerprint
        case .temp: return V8.D.temp
        case .mobile: return V8.D.mobile
        }
    }

    // MARK: - 卡 1 凭证台账

    private var ledgerCard: some View {
        VCard2 {
            HStack(alignment: .top, spacing: V8.S.gapM) {
                VCardHead(
                    eyebrow: "凭证台账",
                    statement: filter == .all ? "按类型分组" : filter.title,
                    trailing: nil
                )
                Spacer(minLength: 0)
                VSegmentedRing2(
                    segments: segments,
                    center: "\(validCount)",
                    size: V8.G.segCompactOuter,
                    width: V8.G.segWidth * 0.6
                )
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                if groupByOwner {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { pair in
                        groupHeader(pair.element.owner, count: pair.element.items.count)
                        ForEach(pair.element.items) { key in
                            keyRow(key)
                            if key.id != pair.element.items.last?.id { VDotRule() }
                        }
                    }
                } else {
                    ForEach(filtered) { key in
                        keyRow(key)
                        if key.id != filtered.last?.id { VDotRule() }
                    }
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("码值在详情页逐位点开。列表只显示类型与剩余天数，不显示明文。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segments: [(Double, Color)] {
        [
            (Double(count(of: .password)), V8.D.passwordFill),
            (Double(count(of: .fingerprint)), V8.D.fingerprintFill),
            (Double(count(of: .temp)), V8.D.tempFill),
            (Double(count(of: .mobile)), V8.D.mobileFill)
        ]
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            Spacer(minLength: 0)
            Text("\(count) 枚")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .monospacedDigit()
        }
        .padding(.top, V8.S.gapM)
        .padding(.bottom, V8.S.gapXS)
    }

    private func keyRow(_ key: KeyItem) -> some View {
        let reading = KeysState.expiryReading(key, now: now)
        return Button {
            KeysRoute.openDetail(key.id, router: router)
        } label: {
            VDataRow(
                tag: key.kind.rawValue,
                tagTint: kindTint(key.kind),
                title: key.name,
                detail: CredentialOrg.ownerName(key.owner),
                value: reading.value,
                unit: reading.unit,
                interactive: true
            )
        }
        .buttonStyle(V8PressStyle())
    }

    // MARK: - 卡 2 到期压力

    private var expiryCard: some View {
        VCard2 {
            // 2026-11-05（全技能审核 · 值级重复）：卡头原来写「明天到期」，下面第一行
            // 「最近到期」又是「明天到期」—— 同一张卡里同一个值两遍。
            // 卡头改说**有多少枚**在临期窗口内（数量），行里保留**具体哪天**（时间）。
            VCardHead(eyebrow: "到期压力", statement: expiryStatement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "最近到期", value: nearestText),
                .init(label: "已过期", value: "\(expiredCount)", unit: "枚")
            ])
            .padding(.top, V8.S.gapM)
        }
    }

    /// 3 天内（含已过期）的枚数。
    private var soonCount: Int {
        app.keys.filter {
            guard !$0.disabled, let d = KeysState.daysLeft($0, now: now) else { return false }
            return d <= 3
        }.count
    }

    private var expiryStatement: String {
        guard nearestDays != nil else { return "全部永久有效" }
        if expiredCount > 0 { return "\(expiredCount) 枚已过期" }
        return "\(soonCount) 枚 3 天内到期"
    }

    private var nearestText: String {
        guard let days = nearestDays else { return "永久" }
        return KeysState.daysWord(days)
    }

    // MARK: - 检索 + 筛选

    private var searchCard: some View {
        VCard2 {
            HStack(spacing: V8.S.gapS) {
                Image(systemName: "magnifyingglass")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                TextField("搜名称 / 归属 / 类型", text: $search)
                    .font(V8.T.body)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { CredentialOrg.pushSearchHistory(search) }
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink4)
                    }
                    .buttonStyle(V8PressStyle())
                    .accessibilityLabel("清空凭证搜索")
                }
            }
            .frame(minHeight: V8.H.min)
            VDivider2()
                .padding(.vertical, V8.S.gapS)
            // 2026-11-05（截图审查 · 本页最大的一处冗余）：
            // 这里原来有**第二排筛选芯片**，与页头 chipRow 是同一个 filter 状态、同一批
            // KeysFilter.allCases、同一串数字（全部 13 / 密码 1 / 指纹 8 / 临时码 1 / 手机钥匙 1）。
            // 一屏两排一模一样的可点控件，用户不知道点哪一排才对 —— 两排还是联动的。
            // 页头那排保留（门页 / 记录页 / 家页的同一惯例），这里只留**只在此处出现**的「分组」芯片。
            HStack(spacing: V8.S.gapChip) {
                groupChip
            }
            // 同理删掉「命中 N 枚」：台账卡头写着当前筛选名，圆环中心就是命中数。
            if search.isEmpty && !recentSearches.isEmpty {
                recentSearchRow
            }
        }
    }

    private var recentSearches: [String] {
        _ = historyTick
        return CredentialOrg.searchHistory()
    }

    private var recentSearchRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                Text("最近搜索")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        search = term
                    } label: {
                        Text(term)
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .padding(.horizontal, V8.S.gapM)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                    }
                    .buttonStyle(V8PressStyle())
                    .accessibilityLabel("搜索 " + term)
                    .contextMenu {
                        Button(role: .destructive) {
                            CredentialOrg.removeSearchHistory(term)
                            historyTick += 1
                        } label: {
                            Text("删除这条搜索记录")
                        }
                    }
                }
            }
        }
        .padding(.top, V8.S.gapS)
    }

    private var groupChip: some View {
        Button {
            groupByOwner.toggle()
            CredentialOrg.setGroupMode(groupByOwner ? .owner : .type)
        } label: {
            Text(groupByOwner ? "按归属分组" : "按类型分组")
                .font(V8.T.tab)
                .foregroundStyle(V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(
                    Capsule(style: .continuous)
                        .fill(V8.C.chipOff)
                )
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(groupByOwner ? "当前按归属分组" : "当前按类型分组")
    }

    // MARK: - 工具入口

    private var toolsCard: some View {
        VCard2 {
            VCardHead(eyebrow: "凭证工具", statement: "六个入口")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "新增凭证", detail: "密码 / 指纹 / 临时码") {
                    router.request(.dest(.keyCreate))
                }
                VDotRule()
                VNavRow(title: "凭证工作室", detail: "批量 / 回收站 / 版本 / 预警 / 导出 / 检测") {
                    router.request(.dest(.credentialStudio))
                }
                VDotRule()
                VNavRow(title: "动态密码", detail: "按锁端周期生成 6 位动态码") {
                    router.request(.dest(.zotp))
                }
                VDotRule()
                VNavRow(title: "到期月历", detail: "看这个月哪天有凭证到期") {
                    router.request(.dest(.keyCalendar))
                }
                VDotRule()
                VNavRow(title: "手机钥匙", detail: "给家人的手机签一把钥匙") {
                    router.request(.dest(.mobileKey))
                }
                VDotRule()
                VNavRow(title: "分享给安卓", detail: "扫码把开锁凭证导到安卓手机") {
                    router.request(.dest(.shareToAndroid))
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }
}