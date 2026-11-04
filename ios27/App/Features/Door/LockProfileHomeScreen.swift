// LockProfileHomeScreen.swift —— 锁档案（V8 设计语言）
//
// 与 LockProfileScreen 的能力对齐：昵称 / 场所副标题 / 分组 / 备注 / 符号 / 色标 /
// 开锁 PIN 选择 / 翻页隐藏 / 启动默认锁 / 电池档案 / 保存。
// 只改渲染层：落盘仍走 DB.saveKeychain + LockArchive.save + kf_chosen_pin_<mac>。
//
// 与旧页的两处刻意差异：
//   ① 空壳模式（胁迫码）下**整页只读**：旧页会把真实锁名与档案摊在屏幕上，
//      且「保存」会用真实档案覆盖回去 —— 与「空壳只隐藏、不破坏」相反。
//   ② 保存失败分两种说法（没有钥匙串 / 昵称为空），不再合并成一句「昵称不能为空」。
import SwiftUI

struct LockProfileHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var name = ""
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
    @State private var loaded = false
    @State private var outcome: String?

    private var kc: Keychain? { app.currentKeychain }
    private var mac: String { kc?.mac ?? "" }
    private var pins: [String] { kc?.pins ?? [] }
    private var decoyed: Bool { DB.isDecoy }

    // MARK: - 判断句与副文

    private var display: String {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "未命名锁" }
        return raw
    }

    private var placeText: String {
        let raw = place.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "未填场所" : raw
    }

    private var modelName: String {
        PidMap.productName(kc?.pid ?? 0)
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示锁档案" }
        if kc == nil { return "还没有门锁" }
        return "「" + display + "」"
    }

    private var lead: String {
        if decoyed { return "空壳模式只隐藏数据，不改动数据。退出空壳后才能看这把锁的档案。" }
        if kc == nil { return "锁档案是给具体一把锁起的名字与外观，挂在钥匙串上。" }
        return "档案只存本机，不写入门锁。改完点「保存档案」。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed || kc == nil {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if kc == nil {
                VEmpty(
                    title: "还没有门锁",
                    reason: "锁档案是给具体一把锁起的名字与外观。先添加门锁，再回来改档案。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                identityCard
                symbolCard
                swatchCard
                pinCard
                batteryCard
                saveCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    // MARK: - 芯片行（四枚状态，不重复卡内读数）

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(identityFill, identityTint), label: "身份", value: identityText)
                VChip2(icon: .glyph(symbol.isEmpty ? "lock.fill" : symbol), label: "符号", value: symbolLabel)
                VChip2(icon: .ring(1, swatchColor), label: "色标", value: swatchLabel)
                VChip2(icon: .ring(pinFraction, pinTint), label: "开锁 PIN", value: pinText)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var filledCount: Int {
        var n = 0
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        if !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        if !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        return n
    }

    private var identityFill: Double { Double(filledCount) / 4.0 }

    private var identityTint: Color { filledCount == 0 ? V8.C.warn : V8.C.ok }

    private var identityText: String {
        filledCount == 0 ? "待填写" : "已填 \(filledCount)/4"
    }

    private var symbolLabel: String {
        LockArchive.symbols.first { $0.name == symbol }?.label ?? "默认"
    }

    private var swatchLabel: String {
        LockArchive.swatches.first { $0.key == colorKey }?.name ?? "主题色"
    }

    /// 色标键 → V8 语义色（值档）。旧页走的是 V7 的 VStateSwatch，
    /// 新页只认 V8 的五族三档，避免同一屏混两套色板。
    private func swatchTint(_ key: String) -> Color {
        switch key {
        case "ok": return V8.C.ok
        case "warn": return V8.C.warn
        case "danger": return V8.C.danger
        case "neutral": return V8.C.ink3
        default: return V8.C.accent
        }
    }

    private var swatchColor: Color {
        swatchTint(colorKey)
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
        return "固定用第 \(pinIndex + 1) 枚签名"
    }

    private var pinText: String {
        if pins.isEmpty { return "未读到" }
        if pins.count <= 1 { return "自动" }
        if pinIndex < 0 { return "自动" }
        return "第 \(pinIndex + 1) 枚"
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "锁档案", statement: "空壳模式只读")
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
        }
    }

    // MARK: - 卡 1 身份

    private var identityCard: some View {
        VCard2 {
            VCardHead(eyebrow: "身份", statement: placeText)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "型号", tagTint: V8.C.ink4, title: modelName, value: "")
                VDotRule()
                VDataRow(tag: "MAC", tagTint: V8.C.ink4, title: mac, value: "")
            }
            .padding(.top, V8.S.gapS)
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                fieldRow("昵称", text: $name, placeholder: "如 婆婆家·入户门")
                fieldRow("场所副标题", text: $place, placeholder: "如 玄关 / 车库")
                fieldRow("分组名", text: $group, placeholder: "如 家用 / 仓库（留空 = 未分组）")
                fieldRow("备注", text: $note, placeholder: "换电历史 / 安装细节", vertical: true)
            }
            .padding(.top, V8.S.gapL)
            VDivider2()
                .padding(.top, V8.S.gapL)
            toggleRow("在翻页里隐藏这把锁", detail: "只影响本机视图，不写门锁，也不影响凭证与日志。", isOn: $hidden)
            toggleRow("设为启动默认锁", detail: "冷启动直接落在这把锁；关掉则维持上次停留。", isOn: $isDefault)
        }
    }

    // MARK: - 卡 2 符号

    private var symbolCard: some View {
        VCard2 {
            VCardHead(eyebrow: "符号", statement: symbolLabel, trailing: "\(LockArchive.symbols.count) 个")
            VDivider2()
                .padding(.top, V8.S.gapM)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapS), count: 4),
                spacing: V8.S.gapS
            ) {
                ForEach(LockArchive.symbols) { item in
                    symbolCell(item)
                }
            }
            .padding(.top, V8.S.gapM)
        }
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

    // MARK: - 卡 3 色标

    private var swatchCard: some View {
        VCard2 {
            VCardHead(eyebrow: "色标", statement: swatchLabel)
            VDivider2()
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
        }
    }

    private func swatchCell(_ item: LockArchive.Swatch) -> some View {
        let on = colorKey == item.key
        return Button {
            colorKey = item.key
        } label: {
            VStack(spacing: V8.S.gapXS) {
                Circle()
                    .fill(swatchTint(item.key))
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

    // MARK: - 卡 4 开锁 PIN

    private var pinCard: some View {
        VCard2 {
            VCardHead(eyebrow: "开锁 PIN", statement: pinStatement, trailing: pins.isEmpty ? nil : "共 \(pins.count) 枚")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if pins.count > 1 {
                VStack(spacing: 0) {
                    pinRow(index: -1, title: "自动（第一枚）")
                    ForEach(Array(pins.enumerated()), id: \.offset) { pair in
                        VDotRule()
                        pinRow(index: pair.offset, title: "第 \(pair.offset + 1) 枚 · …\(String(pair.element.suffix(3)))")
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
        }
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

    // MARK: - 卡 5 电池档案

    private var batteryCard: some View {
        VCard2 {
            VCardHead(eyebrow: "电池档案", statement: batteryModel.isEmpty ? "未填型号" : batteryModel)
            VDivider2()
                .padding(.top, V8.S.gapM)
            fieldRow("电池型号", text: $batteryModel, placeholder: "如 CR123A × 2")
                .padding(.top, V8.S.gapM)
            toggleRow("记录换电日期", detail: "换电池后回来更新，续航估算才有基准。", isOn: $hasBatteryDate)
            if hasBatteryDate {
                DatePicker("换电日期", selection: $batteryDate, displayedComponents: .date)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .frame(minHeight: V8.H.min)
            }
        }
    }

    // MARK: - 卡 6 保存

    private var saveCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "保存", statement: saveStatement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Button {
                save()
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
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("只写本机的钥匙串与档案表；门锁端一个字节都不会改。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveStatement: String {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "昵称还空着" }
        return "改动只在本机生效"
    }

    // MARK: - 行构件

    private func fieldRow(
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

    // MARK: - 读写

    private func load() {
        guard !loaded, !decoyed, let kc else { return }
        loaded = true
        name = kc.name
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

    private func save() {
        guard !DB.isDecoy else {
            outcome = "空壳模式下不写入档案 —— 先退出空壳再来改。"
            return
        }
        guard let kc else {
            outcome = "还没有这把锁的钥匙串 —— 先去「门」页添加或恢复这把锁，再回来改档案。"
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            outcome = "昵称不能为空"
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
        outcome = "已保存锁档案"
    }
}
