// QuickPoolEditSheet.swift —— 快速操作池的编辑页（V8 设计语言）
//
// 入口在门页「一按即开」卡右上角「编辑」。保存写 kf_quick_ids / kf_quick_smart。
// 只改渲染层：QuickPool.selected / setSelected / smartFirst / setSmartFirst 与
// SettingsStore.shared.quickGridCount 原样，落盘键不变。
//
// 2026-11-04（Round 16 · S4 复核）：这一页此前仍是 V7 渲染层，而门页（DoorHomeScreen）
// 已经迁到 V8 —— 同一个交互里外两套设计语言。它又是门页唯一的主功能 sheet，所以先迁它。
import SwiftUI

struct QuickPoolEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 2026-11-03（全功能点排查）：原来是 `Set<String>` —— 存进去顺序就没了，
    /// 保存时 `Array(picked)` 的顺序是哈希序，用户排的顺序永远到不了落地。
    /// 现在用有序数组，并给「已选顺序」可上下调。
    @State private var picked: [String] = QuickPool.selected.map(\.id)
    @State private var smart: Bool = QuickPool.smartFirst

    private var gridCount: Int { SettingsStore.shared.quickGridCount }

    private var judgement: String {
        if picked.isEmpty { return "一个格子都没选" }
        if picked.count > gridCount { return "选了 \(picked.count) 个，只显示前 \(gridCount) 个" }
        return "门页显示 \(picked.count) 个快捷格"
    }

    private func move(_ index: Int, _ delta: Int) {
        let target = index + delta
        guard picked.indices.contains(index), picked.indices.contains(target) else { return }
        picked.swapAt(index, target)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(judgement)
                        .font(V8.T.title2)
                        .foregroundStyle(V8.C.ink1)
                        .tracking(V8.G.heroNumberTracking / 3)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapSection)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("门页一次只显示前 \(gridCount) 个。要改上限：设置 → 外观 → 快捷格数量。")
                        .font(V8.T.bodyL)
                        .foregroundStyle(V8.C.ink3)
                        .lineSpacing(V8.L.bodyL - V8.T.bodyL.size)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapTitleBody)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: V8.S.gapCard) {
                        pickCard
                        if picked.count > 1 { orderCard }
                        smartCard
                        saveCard
                    }
                    .padding(.top, V8.S.gapBodyCard)
                }
                .padding(.horizontal, V8.S.gutterCard)
                .padding(.bottom, V8.S.gapXXL)
            }
            .scrollIndicators(.hidden)
            .background(V8.C.bg.ignoresSafeArea())
            .navigationTitle("编辑快捷操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .accessibilityLabel("取消")
                }
            }
        }
    }

    // MARK: - 卡 1 显示哪些格子

    private var pickCard: some View {
        VCard2 {
            VCardHead(
                eyebrow: "显示哪些格子",
                statement: picked.count > gridCount ? "勾多了，多的不会出现" : "勾几个就显示几个",
                trailing: "\(picked.count) / \(QuickPool.all.count)"
            )
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(QuickPool.all.enumerated()), id: \.element.id) { pair in
                    pickRow(pair.element)
                    if pair.offset != QuickPool.all.count - 1 { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func pickRow(_ action: QuickAction) -> some View {
        let on = picked.contains(action.id)
        return Button {
            if on { picked.removeAll { $0 == action.id } }
            else if !picked.contains(action.id) { picked.append(action.id) }
        } label: {
            HStack(spacing: V8.S.gapS) {
                Image(systemName: action.icon)
                    .font(V8.T.chipValue)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink3)
                    .frame(width: V8.S.gapXXL)
                    .accessibilityHidden(true)
                Text(action.label)
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
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 卡 2 已选顺序

    private var orderCard: some View {
        VCard2 {
            VCardHead(eyebrow: "已选顺序", statement: "排在前面的先显示", trailing: "\(picked.count) 个")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(picked.enumerated()), id: \.element) { pair in
                    if let action = QuickPool.all.first(where: { $0.id == pair.element }) {
                        orderRow(index: pair.offset, action: action)
                        if pair.offset != picked.count - 1 { VDotRule() }
                    }
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func orderRow(index: Int, action: QuickAction) -> some View {
        HStack(spacing: V8.S.gapS) {
            Text("\(index + 1)")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .monospacedDigit()
                .frame(width: V8.S.gapXXL, alignment: .trailing)
            Image(systemName: action.icon)
                .font(V8.T.chipValue)
                .foregroundStyle(V8.C.ink3)
                .accessibilityHidden(true)
            Text(action.label)
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
                .lineLimit(1)
            Spacer(minLength: V8.S.gapS)
            moveButton(action: action, index: index, delta: -1, symbol: "chevron.up", label: "上移")
            moveButton(action: action, index: index, delta: 1, symbol: "chevron.down", label: "下移")
        }
        .frame(minHeight: V8.H.min)
    }

    private func moveButton(action: QuickAction, index: Int, delta: Int, symbol: String, label: String) -> some View {
        let disabled = delta < 0 ? index == 0 : index == picked.count - 1
        return Button {
            move(index, delta)
        } label: {
            Image(systemName: symbol)
                .font(V8.T.chipValue)
                .foregroundStyle(disabled ? V8.C.ink4 : V8.C.ink1)
                .frame(width: V8.H.min, height: V8.H.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .disabled(disabled)
        .accessibilityLabel(label + action.label)
    }

    // MARK: - 卡 3 智能排序

    private var smartCard: some View {
        VCard2 {
            VCardHead(eyebrow: "智能排序", statement: smart ? "按使用次数排前" : "按上面的顺序排")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: $smart) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("按使用次数排前")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text("关闭时按上面「已选顺序」排；开启后点得多的格子自动排前面。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .padding(.top, V8.S.gapM)
        }
    }

    // MARK: - 卡 4 保存

    private var saveCard: some View {
        VCard2(style: .well) {
            Button {
                QuickPool.setSelected(picked)
                QuickPool.setSmartFirst(smart)
                dismiss()
            } label: {
                Text("保存")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(V8PressStyle())
            .accessibilityLabel("保存快捷操作")
            .disabled(picked.isEmpty)
            Text(picked.isEmpty
                 ? "至少勾一个格子，否则门页那块会空着。"
                 : "只改本机版面，不动门锁、凭证与记录。")
                .font(V8.T.footnote)
                .foregroundStyle(picked.isEmpty ? V8.C.warn : V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
