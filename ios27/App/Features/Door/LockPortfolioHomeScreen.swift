// LockPortfolioHomeScreen.swift —— 我的锁（V8 设计语言 · 02 分册 IA 归并后的宿主页）
//
// 本页是 §3.1 归并的宿主：多锁主题全在这。
//   · 主体（原「全部锁」）：30 天总览、按分组筛选、三种排序、切当前锁、改分组、设为默认。
//   ·「锁身份」段（← lockProfile / LockProfileHomeScreen）：昵称 / 场所 / 分组 / 备注 / 符号 / 色标 /
//     开锁 PIN 选择 / 翻页隐藏 / 启动默认锁 / 电池型号 / 保存（DB.saveKeychain + LockArchive.save +
//     setHidden + setDefaultMac + kf_chosen_pin_<mac> 落盘链原样保留）。
//   ·「版面」段（← moduleOrder / ModuleOrderHomeScreen）：三槽排序（拖拽 + 上移/下移）、模块显隐、
//     快捷格勾选（保序、至少留 1 项）、恢复默认（二次确认）。落盘仍是 DevLayout / DevModuleStore / QuickPool。
// 空壳：版面段只读写版面键（无档案字段，藏无可藏，与来源页同口径）；
// 身份段读 LockArchive.meta 与 kc.name（空壳下 meta() 返回空档案、keychain(mac) 返回 nil）→
// 空壳下身份段不渲染、save() 拒写，避免用空档案覆盖真实数据。
import SwiftUI

struct LockPortfolioHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    enum Sort: String, CaseIterable, Identifiable {
        case name = "名称"
        case opens = "开门次数"
        case power = "电量"
        var id: String { rawValue }
    }

    // 2026-11-05（对抗审查 · 持久化不一致）：与凭证工作室同一处问题 —— 排序是刻意设的偏好，
    // 却只活在 @State 里，退出再进来又回到「名称」。落盘。
    @State private var sort: Sort = Sort(rawValue: DB.store.getString("kf_portfolio_sort")) ?? .name
    @State private var groupFilter = ""
    @State private var groupEditMac = ""
    @State private var groupDraft = ""
    @State private var showGroupEdit = false
    @State private var usage: [LockUsage] = []

    // 「锁身份」段状态（← lockProfile）。
    @State private var profileName = ""
    @State private var place = ""
    @State private var group = ""
    @State private var note = ""
    @State private var symbol = ""
    @State private var colorKey = ""
    @State private var batteryModel = ""
    @State private var batteryDate = Date()
    @State private var hasBatteryDate = false
    @State private var isDefault = false
    @State private var hidden = false
    @State private var pinIndex = -1
    @State private var profileLoaded = false
    @State private var profileOutcome: String?

    // 「版面」段状态（← moduleOrder）。
    @State private var order: [DevSlot] = DevLayout.order
    @State private var hiddenModules: Set<String> = DevModuleStore.hidden
    // 有序数组而不是 Set：Array(Set) 的哈希序会把用户在快捷格编辑页排好的顺序整段冲掉。
    @State private var quickIDs: [String] = QuickPool.selected.map(\.id)
    @State private var resetConfirm = false

    private var groups: [String] {
        Array(Set(usage.map { groupOf($0.mac) })).sorted()
    }

    private var shown: [LockUsage] {
        let list = usage.filter { groupFilter.isEmpty || groupOf($0.mac) == groupFilter }
        switch sort {
        case .name: return list.sorted { $0.name < $1.name }
        case .opens: return list.sorted { $0.opens30d > $1.opens30d }
        case .power: return list.sorted { $0.power > $1.power }
        }
    }

    private var kc: Keychain? { app.currentKeychain }
    private var mac: String { kc?.mac ?? "" }
    private var pins: [String] { kc?.pins ?? [] }
    private var decoyed: Bool { DB.isDecoy }

    private var visibleModules: Int { DevModule.allCases.count - hiddenModules.count }

    /// 2026-11-05（截图审查 · 按参考图的结构修正）：
    /// 原来这里写「1 把锁 · 30 天开了 9 次」，而紧接其下的统计卡又报同样两个数 ——
    /// 一屏之内同一组数字两遍。参考图（Apple Health）的做法是**标题叙述、卡片承载数字**，
    /// 这里对齐：标题说状态，数量与次数全部交给下面的统计卡。
    private var judgement: String {
        if usage.isEmpty { return "还没有门锁" }
        if usage.count == 1 { return "只有一把锁" }
        return "多把锁分开管"
    }

    var body: some View {
        VPage(title: judgement, lead: "多锁统计、分组与排序。点一行把该锁设为当前锁。锁身份与版面在下面的段里。") {
            EmptyView()
        } content: {
            if usage.isEmpty {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "多锁统计要在本机至少有一把锁之后才有读数。先添加门锁。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                summaryCard
                filterRow
                listCard
                identitySection
                layoutSection
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            loadProfile()
        }
        // 2026-11-05（对抗审查发现）：切换当前锁后 kc 变了，但 profileLoaded 守卫让
        // 锁身份段还显示旧锁的表单 —— 用户点保存会把旧锁档案写到新锁上。
        // 监听 currentMac 变化，换锁就清掉守卫重载。
        .onChange(of: app.currentMac) { _, _ in profileLoaded = false; loadProfile() }
        .alert("移动到分组", isPresented: $showGroupEdit) {
            TextField("分组名（留空 = 未分组）", text: $groupDraft)
            Button("取消", role: .cancel) { }
            Button("保存") { saveGroup() }
        } message: {
            Text("分组只存本机，不写门锁。")
        }
        .v8Confirm(
            isPresented: $resetConfirm,
            title: "恢复默认版面？",
            consequence: "槽位顺序、模块显隐与快捷格勾选都会回到出厂默认；不动门锁、凭证与记录。恢复后不能撤销，但可以再手动排回来。",
            confirmTitle: "恢复默认",
            isDestructive: true
        ) {
            resetAll()
        }
    }

    // MARK: - 30 天总览

    private var summaryCard: some View {
        VCard2 {
            // 2026-11-05（截图审查 · 本页重复密度最高的一屏）：
            // 页标题已经写着「1 把锁 · 30 天开了 9 次」，这张卡的卡头又写「9 次开门」——
            // 同一屏第一个和第三个信息是同一个数。卡头改成说统计口径。
            VCardHead(eyebrow: "30 天总览", statement: "全部锁合计")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "门锁", value: String(usage.count), unit: "把"),
                .init(label: "告警", value: String(usage.reduce(0) { $0 + $1.alarms30d }), unit: "条")
            ])
            .padding(.top, V8.S.gapM)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                filterChip("全部", on: groupFilter.isEmpty) { groupFilter = "" }
                ForEach(groups, id: \.self) { g in
                    filterChip(g, on: groupFilter == g) { groupFilter = g }
                }
                Menu {
                    ForEach(Sort.allCases) { option in
                        Button(option.rawValue) {
                            sort = option
                            DB.store.set("kf_portfolio_sort", option.rawValue)
                        }
                    }
                } label: {
                    Text("排序 · " + sort.rawValue)
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .accessibilityLabel("排序方式")
            }
            .padding(.horizontal, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private func filterChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var listCard: some View {
        VCard2 {
            // 同上：这张卡的卡头写「门锁 N 把」，而上面统计卡的第一格就是「门锁 N 把」——
            // 默认视图下（全部）两个数完全一样。锁总数由统计卡承载；
            // 这里说明列表当前处在哪个筛选下（筛选时才是这张卡独有的信息）。
            VCardHead(eyebrow: "门锁", statement: groupFilter.isEmpty ? "全部" : groupFilter)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { pair in
                    row(pair.element)
                    if pair.offset != shown.count - 1 { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func row(_ item: LockUsage) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            Button {
                DB.currentMac = item.mac
                app.overrideMac = item.mac
                Task { await app.reload(refreshStatus: true) }
            } label: {
                VDataRow(
                    tag: item.mac == app.currentMac ? "当前" : groupOf(item.mac),
                    tagTint: item.mac == app.currentMac ? V8.C.accent : V8.C.ink4,
                    title: item.name,
                    detail: item.sleeping ? "沉睡" : "固件 " + (item.fw.isEmpty ? "未知" : item.fw),
                    value: String(item.opens30d),
                    unit: "次"
                )
            }
            .buttonStyle(.plain)
            HStack(spacing: V8.S.gapL) {
                Button("改分组") {
                    groupEditMac = item.mac
                    groupDraft = groupOf(item.mac) == LockArchive.ungroupedLabel ? "" : groupOf(item.mac)
                    showGroupEdit = true
                }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                Button("设为默认") {
                    LockArchive.setDefaultMac(item.mac)
                }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                Spacer(minLength: 0)
                Text(item.power >= 0 ? String(item.power) + "%" : "电量未知")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: V8.H.min)
    }

    // MARK: - 段：锁身份（← lockProfile）

    private var identitySection: some View {
        VCard2 {
            if decoyed {
                VCardHead(eyebrow: "锁身份", statement: "空壳模式只读")
                VDivider2()
                    .padding(.top, V8.S.gapM)
                Text("空壳模式（胁迫码进入）下，锁档案既不显示也不写入 —— 否则一保存就会用空档案覆盖掉真实备注与场所。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .lineSpacing(V8.L.body - V8.T.body.size)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                Text("退出空壳请在本机密码界面输入正常密码。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else if kc == nil {
                VCardHead(eyebrow: "锁身份", statement: "还没有门锁")
            } else {
                VCardHead(eyebrow: "锁身份", statement: profilePlaceText)
                VDivider2()
                    .padding(.top, V8.S.gapM)
                // 2026-11-05（对抗审查）：符号与色标此前都是「写进 LockMeta 但没有任何界面显示」
                // 的死控件 —— symbolName / swatchColor 全仓零调用。这里给一个实时预览：
                // 选中的符号按选中的色标着色，用户选完立刻看得见。
                HStack(spacing: V8.S.gapM) {
                    Image(systemName: LockArchive.symbolName(LockArchive.meta(kc?.mac ?? "")))
                        .font(V8.T.title2)
                        .foregroundStyle(profileSwatchTint(colorKey))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: V8.S.gapXS) {
                        Text(profileName.isEmpty ? "未命名" : profileName)
                            .font(V8.T.value)
                            .foregroundStyle(V8.C.ink1)
                        Text(symbolLabel + " · " + colorLabel + " · " + (group.isEmpty ? LockArchive.ungroupedLabel : group))
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, V8.S.gapM)
                VStack(spacing: 0) {
                    VDataRow(tag: "型号", tagTint: V8.C.ink4, title: profileModelName, value: "")
                    VDotRule()
                    VDataRow(tag: "MAC", tagTint: V8.C.ink4, title: mac, value: "")
                }
                .padding(.top, V8.S.gapS)
                VStack(alignment: .leading, spacing: V8.S.gapM) {
                    profileFieldRow("昵称", text: $profileName, placeholder: "如 婆婆家·入户门")
                    profileFieldRow("场所副标题", text: $place, placeholder: "如 玄关 / 车库")
                    profileFieldRow("分组名", text: $group, placeholder: "如 家用 / 仓库（留空 = 未分组）")
                    profileFieldRow("备注", text: $note, placeholder: "换电历史 / 安装细节", vertical: true)
                }
                .padding(.top, V8.S.gapL)
                VDivider2()
                    .padding(.top, V8.S.gapL)
                VStack(spacing: 0) {
                    VDataRow(tag: "符号", tagTint: V8.C.ink4, title: symbolLabel, value: "可选 " + String(LockArchive.symbols.count) + " 个")
                    VDotRule()
                }
                .padding(.top, V8.S.gapS)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapS), count: 4),
                    spacing: V8.S.gapS
                ) {
                    ForEach(LockArchive.symbols) { item in
                        symbolCell(item)
                    }
                }
                .padding(.top, V8.S.gapM)
                HStack(spacing: V8.S.gapL) {
                    ForEach(LockArchive.swatches) { item in
                        swatchCell(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, V8.S.gapM)
                Text("色标只影响本机列表里的圆点，不改门锁上的任何设置。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                VStack(spacing: 0) {
                    VDataRow(tag: "开锁 PIN", tagTint: pinTint, title: pinStatement, value: pinText, unit: pins.isEmpty ? nil : "共 " + String(pins.count) + " 枚")
                    VDotRule()
                }
                .padding(.top, V8.S.gapS)
                if pins.count > 1 {
                    VStack(spacing: 0) {
                        pinRow(index: -1, title: "自动（第一枚）")
                        ForEach(Array(pins.enumerated()), id: \.offset) { pair in
                            VDotRule()
                            pinRow(index: pair.offset, title: "第 " + String(pair.offset + 1) + " 枚 · …" + String(pair.element.suffix(3)))
                        }
                    }
                    .padding(.top, V8.S.gapS)
                    Text("选哪一枚决定开锁时用哪把钥匙签名。开锁失败时本机会依次换池里的下一枚再试。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapFootnote)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("这把锁只有一枚 PIN，或还没读到 PIN 池 —— 不需要选。")
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                profileFieldRow("电池型号", text: $batteryModel, placeholder: "如 CR123A × 2")
                toggleRow("记录换电日期", detail: "换电池后回来更新，续航估算才有基准。", isOn: $hasBatteryDate)
                if hasBatteryDate {
                    DatePicker("换电日期", selection: $batteryDate, displayedComponents: .date)
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink1)
                        .frame(minHeight: V8.H.min)
                }
                VDivider2()
                    .padding(.top, V8.S.gapL)
                toggleRow("在翻页里隐藏这把锁", detail: "只影响本机视图，不写门锁，也不影响凭证与日志。", isOn: $hidden)
                toggleRow("设为启动默认锁", detail: "冷启动直接落在这把锁；关掉则维持上次停留。", isOn: $isDefault)
                VCard2(style: .well) {
                    VCardHead(eyebrow: "保存", statement: profileSaveStatement)
                    Button {
                        saveProfile()
                    } label: {
                        Text("保存档案")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.chipOn)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.accent))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("保存锁档案")
                    .padding(.top, V8.S.gapM)
                    if let profileOutcome {
                        Text(profileOutcome)
                            .font(V8.T.footnote)
                            .foregroundStyle(profileOutcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                            .padding(.top, V8.S.gapS)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("只写本机的钥匙串与档案表；门锁端一个字节都不会改。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink4)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, V8.S.gapL)
            }
        }
    }

    private var profilePlaceText: String {
        let raw = place.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? (profileName.isEmpty ? "锁身份" : profileName) : profileName + " · " + raw
    }

    private var profileModelName: String {
        PidMap.productName(kc?.pid ?? 0)
    }

    private var profileSaveStatement: String {
        if profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "昵称还空着" }
        return "改动只在本机生效"
    }

    private var symbolLabel: String {
        LockArchive.symbols.first { $0.name == symbol }?.label ?? "默认"
    }

    /// 色标键 → 设计令牌色。
    ///
    /// 2026-11-05（对抗审查）：原来这里是**第二份** key→语义词映射，与 Engine 的
    /// `LockArchive.swatchColor` 各写一遍 —— 结果后者全仓零调用（死代码），
    /// 改一处忘另一处就会让「色标」的语义漂。现在只在 UI 层做 ToneColor → Color 的翻译，
    /// key→语义的唯一一份留在 Engine。
    private func profileSwatchTint(_ key: String) -> Color {
        switch LockArchive.swatchColor(key) {
        case .ok: return V8.C.ok
        case .warn: return V8.C.warn
        case .danger: return V8.C.danger
        case .neutral: return V8.C.ink3
        case .accent: return V8.C.accent
        }
    }

    /// 色标键 → 用户看得懂的名字（与 `LockArchive.swatches` 同一份表）。
    private var colorLabel: String {
        LockArchive.swatches.first { $0.key == colorKey }?.name ?? "主题色"
    }

    private var pinFraction: Double {
        guard !pins.isEmpty else { return 0.02 }
        if pinIndex < 0 { return 1 }
        return Double(pinIndex + 1) / Double(pins.count)
    }

    private var pinTint: Color { pinIndex < 0 ? V8.C.ink3 : V8.C.accent }

    private var pinStatement: String {
        if pins.isEmpty { return "还没读到 PIN 池" }
        if pins.count <= 1 { return "只有一枚，不用选" }
        if pinIndex < 0 { return "自动挑第一枚签名" }
        return "固定用第 " + String(pinIndex + 1) + " 枚签名"
    }

    private var pinText: String {
        if pins.isEmpty { return "未读到" }
        if pins.count <= 1 { return "自动" }
        if pinIndex < 0 { return "自动" }
        return "第 " + String(pinIndex + 1) + " 枚"
    }

    private func symbolCell(_ item: LockArchive.SymbolOption) -> some View {
        let on = symbol == item.name
        return Button {
            symbol = item.name
        } label: {
            VStack(spacing: V8.S.gapXS) {
                Image(systemName: item.name)
                    .font(V8.T.chipValue)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink3)
                    .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
                    .background(on ? V8.C.accentTrack : V8.C.well, in: Circle())
                    .accessibilityHidden(true)
                Text(item.label)
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(1)
            }
            .frame(minWidth: V8.H.min, minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("符号 " + item.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func swatchCell(_ item: LockArchive.Swatch) -> some View {
        let on = colorKey == item.key
        return Button {
            colorKey = item.key
        } label: {
            VStack(spacing: V8.S.gapXS) {
                Circle()
                    .fill(profileSwatchTint(item.key))
                    .frame(width: V8.S.gapXL, height: V8.S.gapXL)
                    .overlay {
                        Circle().strokeBorder(
                            on ? V8.C.ink1 : V8.C.line,
                            lineWidth: on ? V8.E.selected : V8.E.hair
                        )
                    }
                    .accessibilityHidden(true)
                Text(item.name)
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(1)
            }
            .frame(minWidth: V8.H.min, minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("色标 " + item.name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func pinRow(index: Int, title: String) -> some View {
        let on = pinIndex == index
        return Button {
            pinIndex = index
        } label: {
            HStack(spacing: V8.S.gapS) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: V8.S.gapS)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(V8.T.chipValue)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func profileFieldRow(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        vertical: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Text(label)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            TextField(placeholder, text: text, axis: vertical ? .vertical : .horizontal)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                Text(detail)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: V8.H.min)
        .padding(.top, V8.S.gapS)
    }

    // MARK: - 段：版面（← moduleOrder）

    private var layoutSection: some View {
        VCard2 {
            VCardHead(eyebrow: "版面", statement: order.isEmpty ? "槽位顺序还没读到" : "三槽 + 模块显隐 + 快捷格")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("三个槽固定在页面上，只改先后。开锁圆盘与异常提醒不参与排序 —— 它们是安全动作，不该被藏起来。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(order) { slot in
                    slotRow(slot)
                }
                .reorderable()
            }
            .reorderContainer(for: DevSlot.self) { change in
                change.apply(to: &order)
                DevLayout.setOrder(order)
            }
            .padding(.top, V8.S.gapS)
            Text("可以长按拖动，也可以用每行的「上移 / 下移」—— 后者对不便做拖拽手势的人仍是必需路径。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VStack(alignment: .leading, spacing: 0) {
                VCardHead(eyebrow: "模块显隐", statement: String(visibleModules) + " / " + String(DevModule.allCases.count) + " 个可见")
                ForEach(DevModule.allCases) { module in
                    toggleRow(
                        module.title,
                        detail: module.cost,
                        isOn: Binding(
                            get: { !hiddenModules.contains(module.rawValue) },
                            set: { on in
                                DevModuleStore.setHidden(module, !on)
                                hiddenModules = DevModuleStore.hidden
                            }
                        )
                    )
                    if module != DevModule.allCases.last { VDotRule() }
                }
            }
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VCardHead(eyebrow: "快捷格", statement: String(quickIDs.count) + " / " + String(QuickPool.all.count) + " 格已选")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapS), count: 2),
                spacing: V8.S.gapS
            ) {
                ForEach(QuickPool.all) { action in
                    quickToggle(action)
                }
            }
            .padding(.top, V8.S.gapM)
            Text("勾选结果即时生效到「门」页。至少留 1 项 —— 一格都不留会让整块快捷区消失。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            Button {
                resetConfirm = true
            } label: {
                Text("恢复默认版面")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accentTrack))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("恢复默认版面")
            Text("只重置版面：槽位顺序、模块显隐、快捷格勾选。门锁、凭证、记录一项都不动。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func slotRow(_ slot: DevSlot) -> some View {
        let idx = order.firstIndex(of: slot) ?? 0
        return VStack(spacing: 0) {
            if idx > 0 { VDotRule() }
            HStack(spacing: V8.S.gapM) {
                Image(systemName: slot.symbol)
                    .font(V8.T.chipValue)
                    .foregroundStyle(V8.C.ink3)
                    .frame(width: V8.S.gapXXL, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text(String(idx + 1) + " · " + slot.title)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(slot.note)
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: V8.S.gapS)
                Button("上移") { moveSlot(slot, by: -1) }
                    .font(V8.T.footnote)
                    .foregroundStyle(idx == 0 ? V8.C.ink4 : V8.C.accent)
                    .frame(minHeight: V8.H.min)
                    .disabled(idx == 0)
                    .accessibilityLabel("把" + slot.title + "上移")
                Button("下移") { moveSlot(slot, by: 1) }
                    .font(V8.T.footnote)
                    .foregroundStyle(idx == order.count - 1 ? V8.C.ink4 : V8.C.accent)
                    .frame(minHeight: V8.H.min)
                    .disabled(idx == order.count - 1)
                    .accessibilityLabel("把" + slot.title + "下移")
            }
            .frame(minHeight: V8.H.min)
        }
    }

    private func quickToggle(_ action: QuickAction) -> some View {
        let selected = quickIDs.contains(action.id)
        return Button {
            if selected {
                guard quickIDs.count > 1 else { return }
                quickIDs.removeAll { $0 == action.id }
            } else if !quickIDs.contains(action.id) {
                quickIDs.append(action.id)
            }
            QuickPool.setSelected(quickIDs)
        } label: {
            HStack(spacing: V8.S.gapS) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(V8.T.chipValue)
                    .foregroundStyle(selected ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
                Text(action.label)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, V8.S.gapS)
            .frame(minHeight: V8.H.min)
            .background(V8.C.chipOff, in: .rect(cornerRadius: V8.R.inset))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 真链路

    private func groupOf(_ mac: String) -> String {
        let g = LockArchive.group(mac)
        return g.isEmpty ? LockArchive.ungroupedLabel : g
    }

    private func saveGroup() {
        guard !groupEditMac.isEmpty else { return }
        LockArchive.setGroup(groupEditMac, groupDraft)
        groupEditMac = ""
        reload()
    }

    private func reload() {
        usage = LockStats.usage()
    }

    /// 锁身份读（← lockProfile 的 load）：空壳不读（meta() 返回空档案，读了会拿空值盖掉表单）。
    private func loadProfile() {
        guard !profileLoaded, !decoyed, let kc else { return }
        profileLoaded = true
        profileName = kc.name
        let m = LockArchive.meta(kc.mac)
        place = m.place
        group = m.grp
        note = m.note
        symbol = m.symbol
        colorKey = m.colorKey
        batteryModel = m.batteryModel
        hasBatteryDate = m.batteryChangedAt > 0
        if m.batteryChangedAt > 0 { batteryDate = Date(timeIntervalSince1970: m.batteryChangedAt) }
        isDefault = LockArchive.defaultMac == kc.mac
        hidden = LockArchive.isHidden(kc.mac)
        let stored = DB.store.getInt("kf_chosen_pin_" + kc.mac, -1)
        // 存下的序号可能指向一个已经不存在的位（池被改小 / 换过锁）——
        // 越界就回落到「自动」，否则界面会说「固定用第 9 枚签名」而池里只有 3 枚。
        pinIndex = (stored >= 0 && stored < kc.pins.count) ? stored : -1
    }

    /// 锁身份写（← lockProfile 的 save）：落盘链逐字保留。
    private func saveProfile() {
        guard !DB.isDecoy else {
            profileOutcome = "空壳模式下不写入档案 —— 先退出空壳再来改。"
            return
        }
        guard let kc else {
            profileOutcome = "还没有这把锁的钥匙串 —— 先去「门」页添加或恢复这把锁，再回来改档案。"
            return
        }
        let trimmed = profileName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            profileOutcome = "昵称不能为空"
            return
        }
        var next = kc
        next.name = trimmed
        DB.saveKeychain(next)
        var m = LockArchive.meta(kc.mac)
        m.place = place.trimmingCharacters(in: .whitespaces)
        m.grp = LockArchive.normalizedGroup(group)
        m.note = note
        m.symbol = symbol
        m.colorKey = colorKey
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        m.batteryChangedAt = hasBatteryDate ? batteryDate.timeIntervalSince1970 : 0
        LockArchive.save(kc.mac, m)
        LockArchive.setHidden(kc.mac, hidden)
        if isDefault { LockArchive.setDefaultMac(kc.mac) }
        else if LockArchive.defaultMac == kc.mac { LockArchive.setDefaultMac("") }
        DB.store.set("kf_chosen_pin_" + kc.mac, pinIndex)
        Task { await app.reload(refreshStatus: false) }
        profileOutcome = "已保存锁档案"
    }

    /// 版面真链路（← moduleOrder）。
    private func moveSlot(_ slot: DevSlot, by delta: Int) {
        DevLayout.move(slot, by: delta)
        order = DevLayout.order
    }

    private func resetAll() {
        DevLayout.reset()
        order = DevLayout.order
        hiddenModules = DevModuleStore.hidden
        quickIDs = QuickPool.selected.map(\.id)
        AppToast.shared.show("已恢复默认版面", tone: .ok)
    }
}
