// ModuleOrderHomeScreen.swift —— 模块排序与显隐（V8 设计语言）
//
// 与 ModuleOrderScreen（原 ModuleOrderCard 面板）的能力对齐：三槽排序（原生拖拽 + 上移/下移双通道）、
// 每模块显隐、快捷格勾选（保序、至少留 1 项）、恢复默认版面（二次确认）。
// 只改渲染层：落盘仍是 DevLayout（kf_dev_order）/ DevModuleStore（kf_dev_hidden）/ QuickPool（kf_quick_ids）。
//
// 本页不向门锁下发任何命令，也不读任何锁档案 / 凭证 / 记录字段 —— 只读写三个版面键：
//   · 空壳（DB.isDecoy）不需要守卫：这里既没有 kc.name 也没有 LockArchive.meta()，藏无可藏。
//   · 只读试验模式（app.trialGuard）不影响本页：它拦的是「下发到门锁的写命令」与导入备份，
//     本机版面偏好仍可编辑（与「安全」页的说明同口径）。
import SwiftUI

struct ModuleOrderHomeScreen: View {
    @State private var order: [DevSlot] = DevLayout.order
    @State private var hidden: Set<String> = DevModuleStore.hidden
    // 有序数组而不是 Set：Array(Set) 的哈希序会把用户在快捷格编辑页排好的顺序整段冲掉。
    @State private var quickIDs: [String] = QuickPool.selected.map(\.id)
    @State private var resetConfirm = false

    private var visibleModules: Int { DevModule.allCases.count - hidden.count }

    private var judgement: String {
        if order.isEmpty { return "槽位顺序还没读到" }
        return order.map(\.title).joined(separator: " → ")
    }

    private var lead: String {
        "三个槽固定在页面上，只改先后。开锁圆盘与异常提醒不参与排序 —— 它们是安全动作，不该被藏起来。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            chipRow
        } content: {
            orderCard
            moduleCard
            quickCard
            resetCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("rectangle.3.group.fill"), label: "槽位", value: "\(order.count) 个")
                VChip2(icon: .ring(moduleFraction, V8.C.ok), label: "模块", value: "\(visibleModules) / \(DevModule.allCases.count)")
                VChip2(icon: .segmented([(Double(quickIDs.count), V8.C.okFill), (Double(QuickPool.all.count - quickIDs.count), V8.C.okTrack)]), label: "快捷格", value: "\(quickIDs.count) / \(QuickPool.all.count)")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var moduleFraction: Double {
        DevModule.allCases.isEmpty ? 0 : Double(visibleModules) / Double(DevModule.allCases.count)
    }

    // MARK: - 卡 1 槽位顺序

    private var orderCard: some View {
        VCard2 {
            VCardHead(eyebrow: "槽位顺序", statement: "从上到下就是门页的版面", trailing: "\(order.count) 个")
            VDivider2()
                .padding(.top, V8.S.gapM)
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
                    Text("\(idx + 1) · " + slot.title)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(slot.note)
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: V8.S.gapS)
                Button("上移") { move(slot, by: -1) }
                    .font(V8.T.footnote)
                    .foregroundStyle(idx == 0 ? V8.C.ink4 : V8.C.accent)
                    .frame(minHeight: V8.H.min)
                    .disabled(idx == 0)
                    .accessibilityLabel("把" + slot.title + "上移")
                Button("下移") { move(slot, by: 1) }
                    .font(V8.T.footnote)
                    .foregroundStyle(idx == order.count - 1 ? V8.C.ink4 : V8.C.accent)
                    .frame(minHeight: V8.H.min)
                    .disabled(idx == order.count - 1)
                    .accessibilityLabel("把" + slot.title + "下移")
            }
            .frame(minHeight: V8.H.min)
        }
    }

    // MARK: - 卡 2 模块显隐

    private var moduleCard: some View {
        VCard2 {
            VCardHead(eyebrow: "模块显隐", statement: "\(visibleModules) / \(DevModule.allCases.count) 个可见")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(DevModule.allCases) { module in
                    toggleRow(
                        module.title,
                        detail: module.cost,
                        isOn: Binding(
                            get: { !hidden.contains(module.rawValue) },
                            set: { on in
                                DevModuleStore.setHidden(module, !on)
                                hidden = DevModuleStore.hidden
                            }
                        )
                    )
                    if module != DevModule.allCases.last { VDotRule() }
                }
            }
        }
    }

    // MARK: - 卡 3 快捷格

    private var quickCard: some View {
        VCard2 {
            VCardHead(eyebrow: "快捷格", statement: "\(quickIDs.count) / \(QuickPool.all.count) 格已选")
            VDivider2()
                .padding(.top, V8.S.gapM)
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

    // MARK: - 卡 4 恢复默认

    private var resetCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "恢复默认", statement: "只重置版面")
            VDivider2()
                .padding(.top, V8.S.gapM)
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
            .padding(.top, V8.S.gapM)
            Text("只重置版面：槽位顺序、模块显隐、快捷格勾选。门锁、凭证、记录一项都不动。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 行构件

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
        .padding(.vertical, V8.S.gapS)
    }

    // MARK: - 真链路

    private func move(_ slot: DevSlot, by delta: Int) {
        DevLayout.move(slot, by: delta)
        order = DevLayout.order
    }

    private func resetAll() {
        DevLayout.reset()
        order = DevLayout.order
        hidden = DevModuleStore.hidden
        quickIDs = QuickPool.selected.map(\.id)
        AppToast.shared.show("已恢复默认版面", tone: .ok)
    }
}
