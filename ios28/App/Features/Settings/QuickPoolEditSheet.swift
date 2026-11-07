// QuickPoolEditSheet.swift —— 快捷池编辑器（E4）。
//
// 入口在外观页「今日的托盘」。保存写 kf_quick_ids / kf_quick_smart，
// 与 ios27 同一份落盘 —— 两台设备各自排各自的池子，备份互通。
// 引擎侧 QuickPool.setSelected（保序去重）/ setSmartFirst 原样，这里只做渲染层。
import SwiftUI

@MainActor
struct QuickPoolEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 有序数组而不是 Set —— 存进 Set 顺序就没了，哈希序永远到不了落盘。
    /// 引擎 `setSelected` 按传入顺序去重保序；这里排出的就是用户看到的顺序。
    @State private var picked: [String] = QuickPool.selected.map(\.id)
    @State private var smart = QuickPool.smartFirst

    private var gridCount: Int { SettingsStore.shared.quickGridCount }

    private var judgement: String {
        if picked.isEmpty { return "一个格子都没选。" }
        if picked.count > gridCount { return "选了 \(picked.count) 个，托盘只显示前 \(gridCount) 个。" }
        return "「今日」会显示 \(picked.count) 个快捷动作。"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(judgement)
                        .type(T.F.title2)
                        .foregroundStyle(T.C.ink)
                        .lineSpacing(3)
                        .padding(.top, 18)
                    Text("托盘一次只显示前 \(gridCount) 个。要改上限：设置 → 外观 → 工具数量。")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .padding(.top, 6)

                    SectionHead(index: "01", title: "显示哪些")
                    VStack(spacing: 0) {
                        ForEach(Array(QuickPool.all.enumerated()), id: \.element.id) { pair in
                            pickRow(pair.element)
                            if pair.offset != QuickPool.all.count - 1 { hair() }
                        }
                    }

                    SectionHead(index: "02", title: "已选顺序")
                    if picked.count > 1 {
                        VStack(spacing: 0) {
                            ForEach(Array(picked.enumerated()), id: \.element) { pair in
                                if let action = QuickPool.all.first(where: { $0.id == pair.element }) {
                                    orderRow(index: pair.offset, action: action)
                                    if pair.offset != picked.count - 1 { hair() }
                                }
                            }
                        }
                        Text("排在前面的先显示。智能排序开着时这一节只是默认顺序。")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                            .padding(.top, 6)
                    } else {
                        Text("至少勾两个才能谈顺序。")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                            .padding(.vertical, 8)
                    }

                    SectionHead(index: "03", title: "智能排序")
                    SwitchLine(title: "按使用次数排前",
                               detail: "关闭时按上面的顺序排；开启后点得多的动作自动排前面。",
                               isOn: $smart)

                    PrimaryButton(title: "保存", enabled: !picked.isEmpty) {
                        QuickPool.setSelected(picked)
                        QuickPool.setSmartFirst(smart)
                        dismiss()
                    }
                    .padding(.top, 22)
                    Text(picked.isEmpty
                         ? "至少勾一个动作，否则托盘那块会空着。"
                         : "只改本机版面，不动门锁、凭证与记录。")
                        .type(T.F.caption)
                        .foregroundStyle(picked.isEmpty ? T.C.danger : T.C.ink3)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
            .background(T.C.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func hair() -> some View {
        Rectangle().fill(T.C.hair).frame(height: 0.5)
    }

    private func pickRow(_ action: QuickAction) -> some View {
        // 不用集合成员判断的简写 —— 用显式的 firstIndex 查找，两个分支共用。
        let on = picked.firstIndex(of: action.id) != nil
        return Button {
            if on {
                picked.removeAll { $0 == action.id }
            } else {
                picked.append(action.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(on ? T.C.brass : T.C.ink3)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(action.label)
                    .type(T.F.callout)
                    .foregroundStyle(T.C.ink)
                    .lineLimit(1)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(on ? T.C.brass : T.C.ink3)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label + (on ? "，已选" : ""))
    }

    private func orderRow(index: Int, action: QuickAction) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
            Image(systemName: action.icon)
                .font(.system(size: 16))
                .foregroundStyle(T.C.ink3)
                .accessibilityHidden(true)
            Text(action.label)
                .type(T.F.callout)
                .foregroundStyle(T.C.ink)
                .lineLimit(1)
            Spacer()
            moveButton(index: index, delta: -1, symbol: "chevron.up", label: "上移")
            moveButton(index: index, delta: 1, symbol: "chevron.down", label: "下移")
        }
        .padding(.vertical, 8)
    }

    private func moveButton(index: Int, delta: Int, symbol: String, label: String) -> some View {
        let disabled = delta < 0 ? index == 0 : index == picked.count - 1
        return Button {
            let target = index + delta
            guard picked.indices.contains(index), picked.indices.contains(target) else { return }
            picked.swapAt(index, target)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? T.C.ink3 : T.C.ink)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
