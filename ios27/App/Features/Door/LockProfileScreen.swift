// LockProfileScreen.swift —— 锁档案（昵称 / 符号 / 色标 / 分组 / 解锁 PIN）。
//
// 来源：原 App/UI/LockProfileView.swift（锁档案：身份、符号、色标、电池、默认锁、PIN 选择）
//   与 App/Core/LockStats.swift 的 LockMeta（kf_lockmeta_）。
// 这屏干什么：编辑这把锁在本机的身份档案（不改锁端字节），并设定启动默认锁、翻页隐藏与开锁 PIN。
// 数据从哪来：DB.keychain(mac) / LockArchive.meta(mac) / LockArchive.symbols / swatches。
// 主动作：「保存档案」。
import SwiftUI

struct LockProfileScreen: View {
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

    private var mac: String { app.lock?.id ?? "" }
    private var kc: Keychain? { app.currentKeychain }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                if let kc {
                    identityCard(kc)
                    pinCard(kc)
                    symbolsCard
                    colorsCard
                    batteryCard
                    saveCard
                } else {
                    noLockCard
                }
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("锁档案")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("锁档案")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("档案只存本机，不写入门锁。")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有门锁").font(V.F.displayB).foregroundStyle(V.C.text1)
                Text("锁档案是给具体一把锁起的名字与外观。先添加门锁。")
                    .font(V.F.body).foregroundStyle(V.C.text2)
                VActionButton(title: "添加门锁", systemImage: "plus") { router.request(.dest(.addLock)) }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func identityCard(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "身份")
                HStack(spacing: V.S.gapM) {
                    Image(systemName: symbol.isEmpty ? "lock.fill" : symbol)
                        .font(V.F.sans(26))
                        .foregroundStyle(swatchColor)
                        .frame(width: V.List.iconSize * 2, height: V.List.iconSize * 2)
                        .background(V.C.cardAlt, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text(name.isEmpty ? "未命名" : name)
                            .font(V.F.sans(20, weight: .bold)).foregroundStyle(V.C.text1)
                        Text(place.isEmpty ? "未填场所" : place)
                            .font(V.F.footnote).foregroundStyle(V.C.text3)
                    }
                    Spacer(minLength: 0)
                }
                VTextFieldRow(label: "昵称", text: $name, placeholder: "如 婆婆家·入户门")
                VTextFieldRow(label: "场所副标题", text: $place, placeholder: "如 玄关 / 车库")
                VTextFieldRow(label: "分组名", text: $group, placeholder: "如 家用 / 仓库 / 办公（留空 = 未分组）")
                VTextFieldRow(label: "备注", text: $note, placeholder: "换电历史 / 安装细节 / 门锁脾气…", axisVertical: true)
                VRowDivider()
                VToggleRow(title: "在翻页里隐藏这把锁", detail: "只影响本机视图，不写门锁，也不影响凭证与日志。", isOn: $hidden)
                VToggleRow(title: "设为启动默认锁", detail: "冷启动直接落在这把锁；关掉则维持上次停留。", isOn: $isDefault)
                VValueRow(label: "MAC", value: kc.mac)
                VValueRow(label: "型号", value: PidMap.productName(kc.pid), mono: false)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func pinCard(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "开锁 PIN")
                if kc.pins.count > 1 {
                    Text("PIN 池有 \(kc.pins.count) 枚。选哪一枚决定开锁时用哪把钥匙签名。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                    ForEach(Array(kc.pins.enumerated()), id: \.offset) { pair in
                        Button {
                            pinIndex = pair.offset
                        } label: {
                            HStack {
                                Text(pair.offset == -1 ? "" : "第 \(pair.offset + 1) 枚 · …\(String(pair.element.suffix(3)))")
                                    .font(V.F.body).foregroundStyle(V.C.text1)
                                Spacer(minLength: 0)
                                if pinIndex == pair.offset {
                                    Image(systemName: "checkmark").foregroundStyle(V.C.blue)
                                }
                            }
                            .frame(minHeight: V.List.rowMinHeight)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        pinIndex = -1
                    } label: {
                        HStack {
                            Text("自动（第一枚）").font(V.F.body).foregroundStyle(V.C.text1)
                            Spacer(minLength: 0)
                            if pinIndex == -1 { Image(systemName: "checkmark").foregroundStyle(V.C.blue) }
                        }
                        .frame(minHeight: V.List.rowMinHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("这把锁只有一枚 PIN，或还没读到 PIN 池 —— 不需要选。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var symbolsCard: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("符号").font(V.F.section).foregroundStyle(V.C.text1)
            VCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V.S.gapS), count: 4), spacing: V.S.gapS) {
                    ForEach(LockArchive.symbols) { item in
                        Button { symbol = item.name } label: {
                            VStack(spacing: V.S.gapXXS) {
                                Image(systemName: item.name)
                                    .font(V.F.sans(18, weight: .medium))
                                    .foregroundStyle(symbol == item.name ? V.C.blue : V.C.text3)
                                    .frame(width: V.List.iconSize * 1.6, height: V.List.iconSize * 1.6)
                                    .background(symbol == item.name ? V.C.blue.opacity(0.14) : V.C.cardAlt, in: Circle())
                                Text(item.label).font(V.F.micro).foregroundStyle(V.C.text3)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("符号 \(item.label)")
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var colorsCard: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("色标").font(V.F.section).foregroundStyle(V.C.text1)
            VCard {
                HStack(spacing: V.S.gapM) {
                    ForEach(LockArchive.swatches) { item in
                        Button { colorKey = item.key } label: {
                            Circle()
                                .fill(swatchValue(item.key))
                                .frame(width: V.List.iconSize, height: V.List.iconSize)
                                .overlay {
                                    Circle().strokeBorder(colorKey == item.key ? V.C.text1 : V.C.hairline, lineWidth: colorKey == item.key ? 2 : V.S.hair)
                                }
                                .frame(width: V.List.rowMinHeight, height: V.List.rowMinHeight)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("色标 \(item.name)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var batteryCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "电池档案")
                VTextFieldRow(label: "电池型号", text: $batteryModel, placeholder: "如 CR123A × 2")
                VToggleRow(title: "记录换电日期", isOn: $hasBatteryDate)
                if hasBatteryDate {
                    DatePicker("换电日期", selection: $batteryDate, displayedComponents: .date)
                        .font(V.F.body).foregroundStyle(V.C.text1)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var saveCard: some View {
        VStack(spacing: V.S.gapS) {
            VActionButton(title: "保存档案", systemImage: "checkmark") { save() }
            if let outcome {
                Text(outcome).font(V.F.footnote)
                    .foregroundStyle(outcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var swatchColor: Color {
        swatchValue(colorKey)
    }

    private func swatchValue(_ key: String) -> Color {
        switch key {
        case "ok": return V.C.rewardGreen
        case "warn": return V.C.coral
        case "danger": return V.C.red
        case "neutral": return V.C.text3
        default: return V.C.blue
        }
    }

    private func load() {
        guard !loaded, let kc else { return }
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
        pinIndex = DB.store.getInt("kf_chosen_pin_" + kc.mac, -1)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let kc else {
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

#Preview("LockProfileScreen") {
    NavigationStack { LockProfileScreen() }
        .environment(AppModel())
        .environment(Router())
}
