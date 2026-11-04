// KeysScreen.swift —— 凭证（Tab 2）。v7 结构重写，参考 R2-credentials.html / TOKENS.md 参考 B。
//
// 实测来源：芯片行 left 14.67 / 芯片 53、102、120 三档宽 / 高 53.3 r14；大标题 29pt/700 left 29.67；
// 正文 17/23 #919096；卡片 #232227 r27 内边距 16.3；分段环 Ø92 环宽 20.3 段间 4–5°；
// 三环 Ø88 按 V.Ring.lineWidth = min(14, size*0.09) 自适应环宽；卡头 11pt/500 #A2A1A6。
// 数据绑定保持原口径：AppModel.keys / lock / members、KeysState、KeysRoute、Router 跳转不变。
import LocalAuthentication
import SwiftUI

struct KeysScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) internal var router
    @State private var filter: KeysFilter = .all
    @State internal var now: Int64 = KeysState.now()
    @State private var search = ""
    // 2026-11-03（信息架构 QA）：原来从全局单例**初始化一次**就再也不读 ——
    // 在凭证工作室切换分组方式后返回本页，chip 的文案与选中态仍停在旧值。
    // 改成在 onAppear 时与全局同步（见 .onAppear）。
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
            // 2026-11-03：原来 haystack 放的是 `key.owner`（成员 id），用户按**成员名**搜不到。
            let hay = [key.name, CredentialOrg.ownerName(key.owner), key.owner ?? "", key.kind.rawValue, key.code ?? ""]
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
            // 2026-11-02（真 bug）：`key.owner` 历史上存过「成员 id」与「成员名字」两种，
            // 直接当显示名会露出内部 id。统一过 `CredentialOrg.ownerName`（两口径都认）。
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

    /// 面容 / 指纹解锁是否**真的**生效（与 `SecurityScreen.biometricHardwareAvailable`、
    /// `LockKeeperApp` 的 `canUseBiometrics()` 同一组判据）。
    private var biometricUnlockEnabled: Bool {
        let store = SettingsStore.shared
        guard store.bioUnlock, !store.hasDuressCode else { return false }
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private var mobileCount: Int {
        app.keys.filter { $0.kind == .mobile }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                // 2026-11-02：同上 —— 标题（导航栏）→ 导语 → 控件。
                header
                chips
                if app.ledgerCorrupt {
                    // 2026-11-01（Round 320）：台账读不出来时，写入会被静默拒绝 —— 必须让用户知道。
                    // 不写「损坏」这种吓人的词做断言（可能只是版本不兼容），只说清后果与出路。
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            Text("本机凭证台账读不出来")
                                .font(V.F.bodyStrong)
                                .foregroundStyle(V.C.critical)
                            SettingsNote(text: "当前会话里对凭证的改动不会保存（写入会被拒绝）。" +
                                         "请先到「备份工作室」从一份备份恢复，再继续操作。")
                        }
                    }
                    .padding(.horizontal, V.S.cardGutter)
                }
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
            // 2026-11-03（真机截图）：同门页 —— 系统大标题自带视觉头部。
            .padding(.bottom, V.S.gapL)
        }
        .background(V.C.bg.ignoresSafeArea())
        .modifier(UITestScrollBottom())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("凭证")
        .navigationBarTitleDisplayMode(.large)
        // 2026-11-03（用户："原生液态玻璃质感太少"）：主行动放进**系统导航栏工具位** ——
        // 系统会给它原生玻璃材质（功能层），比内容里再画一颗实心按钮更贴 HIG，
        // 也让"新增凭证"在任何滚动位置都可达。
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.keyCreate))
                } label: {
                    Image(systemName: "plus")
                        .font(V.F.icon18Medium)
                }
                .accessibilityLabel("新增凭证")
            }
        }
        .task { await app.reload(refreshStatus: false) }
        .onAppear {
            now = KeysState.now()
            // 2026-11-01（Round 239）：老人模式会**隐藏**「临时码 / 手机钥匙」两个芯片，
            // 而 `filter` 仍可能是它们（在开启老人模式之前选的）—— 于是列表被一个**看不见的筛选**卡住，
            // 用户只看到几条凭证却没有任何芯片是高亮的。回落到「全部」。
            if !visibleFilters.contains(filter) { filter = .all }
            // 2026-11-03（信息架构 QA）：分组方式是**全局设置**，凭证工作室里也能切换。
            // 本页的 @State 只在初始化时读过一次，切回来仍是旧值 —— 每次出现时同步。
            let wantGroupByOwner = CredentialOrg.groupMode == .owner
            if groupByOwner != wantGroupByOwner { groupByOwner = wantGroupByOwner }
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
                    title: "凭证",
                    value: "\(app.keys.count) 枚",
                    tint: V.C.blue,
                    style: .compact,
                    systemImage: "circle.hexagongrid.fill"
                )
                VChip(
                    title: "生物识别",
                    // 2026-11-04（呈现复核 · 过度断言）：原来按 `mobileCount > 0`（有没有手机钥匙）
                    // 显示「已开启」—— 这与生物识别**毫无关系**。手机钥匙 1 枚 + 面容解锁关着，
                    // 芯片仍写「已开启」；反过来开了面容但没手机钥匙，又写「未开启」。
                    // 真值与「安全」页同一个判据：设置开着 + 硬件可用 + 没设胁迫码（设了会被强制停用）。
                    value: biometricUnlockEnabled ? "已开启" : "未开启",
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
            // 2026-11-02：标题改由系统导航栏的大标题承担 —— 自己再画一遍就是同一屏两个「凭证」，
            // 而且自绘标题拿不到随滚动折叠、导航栏液态玻璃、无障碍标题语义。
            // 2026-11-03（真机截图）：原来写死三处 \n —— 大字号/窄屏下固定换行会错位。
            // 改为自然流动（fixedSize(vertical) 保留，多行高度仍自适应）。
            Text("家人、临时客人与服务人员共用一把门锁；过期自动失效，随时可撤销。")
                .font(V.F.pageLead)
                .foregroundStyle(V.C.text3)
                .lineSpacing(V.Page.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.pageGutter)
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
                        // 2026-11-04（呈现复核）：这一行原本无条件显示「共 N 枚」——
                        // 而同一张卡里「总数」已经是 N、「环心」也是 N，**同一个数字出现三次**。
                        // 全部有效时它零信息量；只有存在失效凭证时，「有效 12 / 共 13」才是有用的对比。
                        if validCount != app.keys.count {
                            Text("共 \(app.keys.count) 枚")
                                .font(V.F.micro)
                                .foregroundStyle(V.C.text4)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text("最早到期")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
                        Text(nearestDays.map { KeysState.daysWord($0) } ?? "永久")
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
                // 2026-11-03（整页截图实测）：这一对读数是**标签与值对不上** ——
                // 标签写「最近使用」（过去），值却是「30 天后到期」（未来）。
                // 而且「最早到期」在同一屏出现两次、两种格式（上面卡片「30 天后」、这里「12-03」）。
                // 改成：左格说"最近到期"（与值一致），右格标明是日期形态。
                VStatPair(items: [
                    ("最近到期", nearestDays.map { KeysState.daysWord($0) } ?? "永久"),
                    ("最早到期日", earliestExpiryText)
                ])
                .padding(.top, V.S.gapXXS)
                VDivider()
                // 2026-11-03（整页截图实测 · 标签与值不符）：这里写「**今日已核验** N 枚」，
                // 而 `validCount` 数的是「未停用且未过期」的凭证 —— 那是**当前有效数**，
                // 与"今天核验过"没有关系（App 从不做每日核验，也没有这个记录）。
                // 标签跟着值走：说清它是有效数、核对是本机做的。
                Text("其中 \(validCount) 枚有效（未停用、未过期），全部在本机核对。")
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
                        // 2026-11-04（呈现复核 · 硬编码状态）：这一整块原来是**写死的**
                        // 「已启用 / 范围 全量」—— 没有任何数据源。没设本机密码的用户也会看到
                        // 「本机安全 已启用」，而实际上他连解锁密码都没有。
                        Text(SettingsStore.shared.hasPasscode ? "已启用" : "未启用")
                            .font(V.F.chipValue)
                            .foregroundStyle(V.C.text1)
                        Text("范围")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text4)
                        Text(SettingsStore.shared.hasPasscode ? "全量" : "无")
                            .font(V.F.bedValue)
                            .foregroundStyle(V.C.text1)
                    }
                    Spacer(minLength: 0)
                    // 未启用时不该给"安全已确认"的勾盾 —— 那是视觉上的过度断言。
                    Image(systemName: SettingsStore.shared.hasPasscode ? "checkmark.shield.fill" : "shield.slash")
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
            // 2026-11-03（整页截图暴露）：这里原来有个「全部凭证」section 标题，
            // 而下面的列表卡头**又叫「全部凭证 12 枚」** —— 同屏两遍。删这里，卡头留着（带计数）。
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
                    // 函数内已挡空串；这里再挡一次是为了不产生"提交了但什么都没发生"的感觉 ——
                    // 空搜索本来就没有可记的东西。
                    .onSubmit { if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { CredentialOrg.pushSearchHistory(search) } }
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(V.F.icon15)
                            .foregroundStyle(V.C.text3)
                            .accessibilityHidden(true)
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
                        // 2026-11-03：筛选芯片换成功能层玻璃（HIG：控制件用 Liquid Glass）。
                        GlassChip(title: chipTitle(item), selected: item == filter) {
                            filter = item
                        }
                    }
                    // 2026-11-03（材质一致）：分组切换也是控制件，与筛选芯片同用 GlassChip。
                    GlassChip(title: groupByOwner ? "按成员分组" : "按类型分组", selected: groupByOwner) {
                        groupByOwner.toggle()
                        CredentialOrg.setGroupMode(groupByOwner ? .owner : .type)
                    }
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
                                    // 桶键已是归一后的显示名；这里再兜一次，别名开关改动后仍正确。
                                    Text(CredentialOrg.ownerName(pair.element.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(pair.element.owner))
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
        .padding(.horizontal, V.S.pageGutter)
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
        .padding(.horizontal, V.S.pageGutter)
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
                        detail: "按锁端周期生成 6 位动态码",
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
        let ownerNameText = CredentialOrg.ownerName(key.owner)
        if !ownerNameText.isEmpty { bits.append(ownerNameText) }
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
            // 2026-11-03（整页截图实测）：这一行原来只渲染 `read.value`，把 `unit` 丢了 ——
            // 于是"还剩 30 天"显示成光秃秃的「30」，与旁边「永久 / 过期」并列时看不出量纲。
            // `expiryReading` 明确返回 (value: "30", unit: "天")，单位必须跟着走。
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapXXS) {
                Text(read.value)
                    .font(V.F.rowDetail)
                    .foregroundStyle(read.tint)
                    .monospacedDigit()
                if let unit = read.unit, !unit.isEmpty {
                    Text(unit)
                        .font(V.F.micro)
                        .foregroundStyle(V.C.text3)
                }
            }
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
