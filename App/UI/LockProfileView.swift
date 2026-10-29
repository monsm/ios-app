// 锁档案（身份/符号/色标/电池/默认锁）
// 2026-10-29 从 Sheets.swift 拆出
import SwiftUI

struct LockProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var place = ""
    @State private var grp = ""      // 104/767 分组名 (与设备管理页同一字段)
    @State private var note = ""
    @State private var symbol = ""
    @State private var colorKey = ""
    @State private var batteryModel = ""
    /// 2026-10-28 补：`LockArchive.setDefaultMac` 全仓零调用 —— 而 `defaultMac` 有 2 处消费
    /// （冷启动落点 `AppState.loadDevices(preferDefault:)` + 设备排序首位）。
    /// 于是「启动默认锁」这个功能**永远设不了**，用户只能靠"上次停留"。
    @State private var isDefaultLock = false
    @State private var batteryHasDate = false
    @State private var batteryDate = Date()
    @State private var loaded = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View { vkBody.destined(.lockProfile) }
    var vkBody: some View {
        Form {
            // 预览: 与 Hero 卡同构的身份行, 编辑即所见
            Section {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: symbol.isEmpty ? "lock.fill" : symbol)
                        .font(.system(size: DS.Icon.lg, weight: .medium))
                        .foregroundStyle(LockArchive.swatchColor(colorKey))
                        .frame(width: 52, height: 52)
                        .background(DS.Palette.surfaceAlt, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(trimmed.isEmpty ? "未命名" : trimmed)
                            .vkFont(.headline)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(place.trimmingCharacters(in: .whitespaces).isEmpty ? "未填场所" : place)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("预览: \(trimmed.isEmpty ? "未命名" : trimmed)")
            } footer: {
                Text("符号与色标同步用于 Hero 卡、切换胶囊与记录行的时间线标签。")   // 105 符号与色标同步用于
            }
            Section("身份") {
                TextField("昵称 (如 婆婆家·入户门)", text: $name)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                // 920 安装位置字段 = 这一行 (原句的"玄关/车库"就是这里的占位例子)。
                // 它同时是 Hero 卡副标题与"全部锁总览"的行副标题; **Widget 那一半做不到** ——
                // 免费账号无 App Groups，组件读不到本机档案 (CONSTRAINTS ❌ 表)，所以那里只显示静态文案。
                TextField("场所副标题 (如 玄关 / 车库)", text: $place)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                // 104/767 分组名: 与"设备管理"页写的是同一个字段 (kf_lockmeta_.grp), 两处都能改、改完都生效。
                // 设备页上方会出现按组切换的胶囊; 建议名 (家用/仓库/办公) 在设备管理页的右键菜单里一键选。
                TextField("分组名 (如 家用 / 仓库 / 办公, 留空 = 未分组)", text: $grp)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                // 106 备注: 备忘录标题正文的双字段案
                TextField("备注 (换电历史/安装细节/门锁脾气…)", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
            // 2026-10-29 补（**后台有实现、前台零入口**）：`AppState.setChosenPinIndex` 零调用，
            // 而读侧 `chosenPinIndex` / `chosenPin` / `lock.unlock(pinDec:)` 都已在用。
            // PIN 池有多枚时，用户没法选「开锁用哪一枚」。
            Section {
                if let kc = app.current, kc.pins.count > 1 {
                    Picker("开锁用哪一枚", selection: Binding(
                        get: { app.chosenPinIndex(kc.mac) },
                        set: { app.setChosenPinIndex(kc.mac, $0) }
                    )) {
                        Text("自动（第一枚）").tag(-1)
                        ForEach(Array(kc.pins.enumerated()), id: \.offset) { i, _ in
                            Text("第 \(i + 1) 枚 · …\(String(kc.pins[i].suffix(3)))").tag(i)
                        }
                    }
                } else {
                    Text("这把锁只有一枚 PIN，或还没读到 PIN 池 —— 不需要选。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("开锁 PIN")
            } footer: {
                Text("PIN 池有多枚时，这里决定开锁用哪一枚。选「自动」= 用第一枚（与旧行为一致）。")
            }
            Section {
                // 108 手动隐藏这把锁: 只影响设备 Tab 的横滑翻页与胶囊主列表。
                // 判据刻意与"沉睡 (超 30 天未连接)"分开 —— 隐藏是用户明确说过的，沉睡是推断出来的。
                VariantToggle("在翻页里隐藏这把锁", isOn: Binding(   // 108 在翻页里隐藏这把锁
                    get: { LockArchive.isHidden(app.currentMac) },
                    set: { LockArchive.setHidden(app.currentMac, $0) }))
                Text("隐藏后它退出左右横滑，只在切换胶囊的「已隐藏」区里可达；回到这里取消即恢复。\n"
                     + "这是本机的视图设置：不写门锁，也不影响凭证、日志与备份。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("符号") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: 4),
                          spacing: DS.Space.s) {
                    ForEach(LockArchive.symbols) { s in
                        Button {
                            symbol = s.name
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            VStack(spacing: DS.Space.xxs) {
                                Image(systemName: s.name)
                                    .font(.system(size: DS.Icon.md, weight: .medium))
                                    .foregroundStyle(symbol == s.name ? DS.Palette.accentText : DS.Palette.textSub)
                                    .frame(width: 46, height: 46)
                                    .background(symbol == s.name ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt,
                                                in: Circle())
                                Text(s.label)
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("符号 \(s.label)")
                        .accessibilityAddTraits(symbol == s.name ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
            Section("色标") {
                HStack(spacing: DS.Space.m) {
                    ForEach(LockArchive.swatches) { s in
                        Button {
                            colorKey = s.key
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Circle()
                                .fill(LockArchive.swatchColor(s.key))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if colorKey == s.key {
                                        Circle().strokeBorder(DS.Palette.text, lineWidth: 2)
                                    } else {
                                        Circle().strokeBorder(DS.Palette.hairline, lineWidth: 0.5)
                                    }
                                }
                                // 色块 34pt 视觉 + 44pt 命中区分离
                                .frame(width: DS.Hit.min, height: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("色标 \(s.name)")
                        .accessibilityAddTraits(colorKey == s.key ? [.isSelected] : [])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Section("电池档案") {
                TextField("电池型号 (如 CR123A × 2)", text: $batteryModel)
                VariantToggle("记录换电日期", isOn: $batteryHasDate)
                if batteryHasDate {
                    DatePicker("换电日期", selection: $batteryDate, displayedComponents: .date)
                }
            }
            // 2026-10-28 补入口：「设为启动默认锁」—— `setDefaultMac` 此前零调用。
            Section {
                VariantToggle("设为启动默认锁", isOn: $isDefaultLock)
            } footer: {
                Text("开启后，冷启动（杀进程再打开）会直接落在这把锁；关掉则维持「上次停留的那把」。"
                     + " 只在本机生效，不写入门锁。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                BusyButton(title: "保存档案", systemImage: "checkmark", isBusy: false, disabled: trimmed.isEmpty) {
                    save()
                }
            } footer: {
                Text("昵称不能为空。档案只存本机, 不写入门锁。")
            }
        }
        .navigationTitle("锁档案")
        .variantList()
        .dsScreenBackground()
        .onAppear {
            guard !loaded, let kc = app.current else { return }
            loaded = true
            name = kc.name
            let m = LockArchive.meta(kc.mac)
            place = m.place; note = m.note
            grp = m.grp
            symbol = m.symbol; colorKey = m.colorKey
            batteryModel = m.batteryModel
            batteryHasDate = m.batteryChangedAt > 0
            isDefaultLock = LockArchive.defaultMac == kc.mac
            if m.batteryChangedAt > 0 { batteryDate = Date(timeIntervalSince1970: m.batteryChangedAt) }
        }
    }

    private func save() {
        let n = trimmed
        guard !n.isEmpty, let kc = app.current else { app.showToast("昵称不能为空"); return }
        var kc2 = kc
        kc2.name = n
        DB.saveKeychain(kc2)
        var m = LockArchive.meta(kc.mac)
        m.place = place.trimmingCharacters(in: .whitespaces)
        m.grp = LockArchive.normalizedGroup(grp)
        m.note = note
        m.symbol = symbol
        m.colorKey = colorKey
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        m.batteryChangedAt = batteryHasDate ? batteryDate.timeIntervalSince1970 : 0
        LockArchive.save(kc.mac, m)
        // 2026-10-28：默认锁与档案一起保存（`setDefaultMac` 会同时把它排到手工顺序首位，
        // 避免"顺序表说 A 在前、默认锁说 B 在前"两个真相）。
        if isDefaultLock {
            LockArchive.setDefaultMac(kc.mac)
        } else if LockArchive.defaultMac == kc.mac {
            LockArchive.setDefaultMac("")   // 关掉 = 清除，回到"上次停留"
        }
        app.loadDevices()
        app.showToast("档案已保存")
        dismiss()
    }
}