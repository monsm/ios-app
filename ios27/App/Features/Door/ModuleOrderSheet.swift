// ModuleOrderSheet.swift —— 设备页「模块排序与显隐」（原 DeviceHomeView.swift:354-460）。
//
// 这屏干什么：三槽排序（状态卡 / 快捷格 / 最近开门）+ 每模块显隐 + 快捷格勾选 + 恢复默认。
// 数据从哪来：DevLayout（kf_dev_order）、DevModuleStore（kf_dev_hidden）、QuickPool（kf_quick_ids）。
// 主动作：无 —— 每次点按即时落盘；底部「恢复默认」是破坏性动作，二次确认。
import SwiftUI

struct ModuleOrderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ModuleOrderPanel()
                .background(CanvasBackground())
                .navigationTitle("模块排序与显隐")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                            .accessibilityLabel("完成模块设置")
                    }
                }
        }
    }
}

/// 目的地页版本（Router 的 Dest .moduleOrder 用同一个面板）。
struct ModuleOrderScreen: View {
    var body: some View {
        ScrollView {
            ModuleOrderPanel()
                .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .navigationTitle("模块排序")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ModuleOrderPanel: View {
    @State private var order: [DevSlot] = DevLayout.order
    @State private var hidden: Set<String> = DevModuleStore.hidden
    @State private var quickIDs: Set<String> = Set(QuickPool.selected.map(\.id))
    @State private var resetConfirm = false

    var body: some View {
        VStack(spacing: V.S.gap16) {
            orderPanel
            modulePanel
            quickPanel
            resetPanel
        }
        .padding(.vertical, V.S.gap16)
        .confirmationDialog("恢复默认版面？", isPresented: $resetConfirm, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                DevLayout.reset()
                order = DevLayout.order
                hidden = DevModuleStore.hidden
                quickIDs = Set(QuickPool.selected.map(\.id))
                AppToast.shared.show("已恢复默认版面", tone: .ok)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("槽位顺序、模块显隐与快捷格勾选都会回到出厂默认；不动门锁、凭证与记录。")
        }
    }

    // MARK: 三槽排序

    private var orderPanel: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            VSectionLabel(text: "槽位顺序", trailing: "从上到下")
            VCard {
                VStack(spacing: 0) {
                    ForEach(Array(order.enumerated()), id: \.element) { pair in
                        if pair.offset > 0 { VDivider() }
                        HStack(spacing: V.S.gapM) {
                            Image(systemName: pair.element.symbol)
                                .font(V.F.icon18)
                                .foregroundStyle(V.C.text2)
                                .frame(width: V.Icon.xl, alignment: .leading)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                                Text("\(pair.offset + 1) · \(pair.element.title)")
                                    .font(V.F.rowTitle)
                                    .foregroundStyle(V.C.text1)
                                Text(pair.element.note)
                                    .font(V.F.rowDetail)
                                    .foregroundStyle(V.C.text3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: V.S.gapS)
                            Button("上移") { move(pair.element, by: -1) }
                                .font(V.F.footnote)
                                .foregroundStyle(pair.offset == 0 ? V.C.text4 : V.C.blue)
                                .frame(minHeight: V.Hit.min)
                                .disabled(pair.offset == 0)
                                .accessibilityLabel("把\(pair.element.title)上移")
                            Button("下移") { move(pair.element, by: 1) }
                                .font(V.F.footnote)
                                .foregroundStyle(pair.offset == order.count - 1 ? V.C.text4 : V.C.blue)
                                .frame(minHeight: V.Hit.min)
                                .disabled(pair.offset == order.count - 1)
                                .accessibilityLabel("把\(pair.element.title)下移")
                        }
                        .frame(minHeight: V.List.rowMinHeight)
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
            SettingsNote(text: "三个槽固定在页面上，只改先后。开锁圆盘与异常提醒不参与排序 —— 它们是安全动作，不该被藏起来。")
                .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 模块显隐

    private var modulePanel: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            VSectionLabel(text: "模块显隐")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    ForEach(DevModule.allCases) { module in
                        VToggleRow(
                            title: module.title,
                            detail: module.cost,
                            isOn: Binding(
                                get: { !hidden.contains(module.rawValue) },
                                set: { on in
                                    DevModuleStore.setHidden(module, !on)
                                    hidden = DevModuleStore.hidden
                                }
                            )
                        )
                        if module != DevModule.allCases.last { VDivider() }
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 快捷格

    private var quickPanel: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            VSectionLabel(text: "快捷格", trailing: "\(quickIDs.count) / \(QuickPool.all.count)")
            VCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V.S.gapS), count: 2), spacing: V.S.gapS) {
                    ForEach(QuickPool.all) { action in
                        quickToggle(action)
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
            SettingsNote(text: "勾选结果即时生效到「门」页。至少留 1 项 —— 一格都不留会让整块快捷区消失。")
                .padding(.horizontal, V.S.pageGutter)
        }
    }

    private func quickToggle(_ action: QuickAction) -> some View {
        let selected = quickIDs.contains(action.id)
        return Button {
            if selected {
                guard quickIDs.count > 1 else { return }
                quickIDs.remove(action.id)
            } else {
                quickIDs.insert(action.id)
            }
            QuickPool.setSelected(Array(quickIDs))
        } label: {
            HStack(spacing: V.S.gapS) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(V.F.icon15Medium)
                    .foregroundStyle(selected ? V.C.blue : V.C.text3)
                    .accessibilityHidden(true)
                Text(action.label)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text1)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, V.S.gapS)
            .frame(minHeight: V.Hit.min)
            .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.control))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var resetPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VOutlineButton(title: "恢复默认版面", systemImage: "arrow.uturn.backward") {
                    resetConfirm = true
                }
                SettingsNote(text: "只重置版面：槽位顺序、模块显隐、快捷格勾选。门锁、凭证、记录一项都不动。")
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func move(_ slot: DevSlot, by delta: Int) {
        DevLayout.move(slot, by: delta)
        order = DevLayout.order
    }
}

#Preview("ModuleOrderSheet") {
    ModuleOrderSheet()
        .environment(AppModel())
        .environment(Router())
}
