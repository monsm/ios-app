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
            ScrollView {
                ModuleOrderCard()
                    .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
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
            ModuleOrderCard()
                .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .navigationTitle("模块排序")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ModuleOrderCard: View {
    @State private var order: [DevSlot] = DevLayout.order
    @State private var hidden: Set<String> = DevModuleStore.hidden
    // 2026-11-03（全功能点排查）：这里也是 `Set` —— 在「模块排序与显隐」里点一下快捷格，
    // `Array(Set)` 的哈希序会把你之前在快捷格编辑页排好的顺序整段冲掉。
    // 顺序是用户能感知的设置（QuickPool.selected 明确保序），所以这里也必须是有序数组。
    @State private var quickIDs: [String] = QuickPool.selected.map(\.id)
    @State private var resetConfirm = false

    var body: some View {
        VStack(spacing: V.S.gap16) {
            orderPanel
            modulePanel
            quickPanel
            resetPanel
        }
        .padding(.vertical, V.S.gap16)
    }

    // MARK: 三槽排序

    private var orderPanel: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            VSectionLabel(text: "槽位顺序", trailing: "从上到下")
            VCard {
                VStack(spacing: 0) {
                    // 2026-11-01：改用 **iOS 27 原生拖拽排序**（`reorderable()` + `reorderContainer(for:)`）。
                    // 旧实现只有「上移 / 下移」两个按钮 —— 三个槽要挪到对面得点两次，
                    // 而且这套手势是自造的，VoiceOver 只能逐个按钮念。
                    // 原生排序自带拖起动画、自动滚动、以及与系统一致的朗读语义。
                    // **上移/下移按钮保留**：对不便做拖拽手势的人（运动障碍、单手持机）它们仍是必需路径 ——
                    // 原生拖拽是**新增**一条路，不是替换掉那条。
                    ForEach(order) { slot in
                        let idx = order.firstIndex(of: slot) ?? 0
                        if idx > 0 { VDivider() }
                        HStack(spacing: V.S.gapM) {
                            Image(systemName: slot.symbol)
                                .font(V.F.icon18)
                                .foregroundStyle(V.C.text2)
                                .frame(width: V.Icon.xl, alignment: .leading)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                                Text("\(idx + 1) · \(slot.title)")
                                    .font(V.F.rowTitle)
                                    .foregroundStyle(V.C.text1)
                                Text(slot.note)
                                    .font(V.F.rowDetail)
                                    .foregroundStyle(V.C.text3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: V.S.gapS)
                            Button("上移") { move(slot, by: -1) }
                                .font(V.F.footnote)
                                .foregroundStyle(idx == 0 ? V.C.text4 : V.C.blue)
                                .frame(minHeight: V.Hit.min)
                                .disabled(idx == 0)
                                .accessibilityLabel("把\(slot.title)上移")
                            Button("下移") { move(slot, by: 1) }
                                .font(V.F.footnote)
                                .foregroundStyle(idx == order.count - 1 ? V.C.text4 : V.C.blue)
                                .frame(minHeight: V.Hit.min)
                                .disabled(idx == order.count - 1)
                                .accessibilityLabel("把\(slot.title)下移")
                        }
                        .frame(minHeight: V.List.rowMinHeight)
                    }
                    .reorderable()
                }
                .reorderContainer(for: DevSlot.self) { change in
                    change.apply(to: &order)
                    DevLayout.setOrder(order)
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
                quickIDs.removeAll { $0 == action.id }
            } else if !quickIDs.contains(action.id) {
                quickIDs.append(action.id)
            }
            QuickPool.setSelected(quickIDs)
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
                // 2026-11-01：`confirmationDialog` 从根视图挪到**触发它的按钮**上。
                // 判据（`swiftui-pro` navigation.md）：挂在触发控件上，「液态玻璃才会从正确的位置展开」。
                // 挂在根视图上时，iPad / Liquid Glass 会从屏幕中部弹出，
                // 用户看不出"是哪颗按钮要重置什么"。
                .confirmationDialog("恢复默认版面？", isPresented: $resetConfirm, titleVisibility: .visible) {
                    Button("恢复默认", role: .destructive) {
                        DevLayout.reset()
                        order = DevLayout.order
                        hidden = DevModuleStore.hidden
                        quickIDs = QuickPool.selected.map(\.id)
                        AppToast.shared.show("已恢复默认版面", tone: .ok)
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("槽位顺序、模块显隐与快捷格勾选都会回到出厂默认；不动门锁、凭证与记录。")
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
