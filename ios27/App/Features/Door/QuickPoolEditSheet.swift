// QuickPoolEditSheet.swift —— 快速操作池的编辑页（10 选 N + 智能排序开关）。
//
// 入口在 DoorScreen「快捷操作」卡右上角「编辑」。保存写 kf_quick_ids / kf_quick_smart。
import SwiftUI

struct QuickPoolEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 2026-11-03（全功能点排查）：原来是 `Set<String>` —— 存进去顺序就没了，
    /// 保存时 `Array(picked)` 的顺序是哈希序，用户排的顺序永远到不了落地。（`QuickPool.setSelected`
    /// 那侧还有第二处丢序，已一并修。）现在用有序数组，并加一段「已选顺序」可上下调。
    @State private var picked: [String] = QuickPool.selected.map(\.id)
    @State private var smart: Bool = QuickPool.smartFirst

    private func move(_ index: Int, _ delta: Int) {
        let target = index + delta
        guard picked.indices.contains(index), picked.indices.contains(target) else { return }
        picked.swapAt(index, target)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: V.S.gap16) {
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            VSectionLabel(text: "显示哪些格子")
                            ForEach(QuickPool.all) { a in
                                Toggle(isOn: Binding(
                                    get: { picked.contains(a.id) },
                                    set: { on in
                                        if on { if !picked.contains(a.id) { picked.append(a.id) } }
                                        else { picked.removeAll { $0 == a.id } }
                                    }
                                )) {
                                    HStack(spacing: V.S.gapS) {
                                        Image(systemName: a.icon)
                                            .font(V.F.icon18)
                                            .foregroundStyle(V.C.text2)
                                            .frame(width: V.Icon.l)
                                            .accessibilityHidden(true)
                                        Text(a.label)
                                            .font(V.F.body)
                                            .foregroundStyle(V.C.text1)
                                    }
                                }
                                .tint(V.C.blue)
                                .frame(minHeight: V.Hit.min)
                            }
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)

                    // 2026-11-03：加了「已选顺序」—— 文案一直说"按你在这里的勾选顺序"，
                    // 但一个纯开关列表根本表达不出顺序。这里给已选项一个可上下调的有序列。
                    if picked.count > 1 {
                        VCard {
                            VStack(alignment: .leading, spacing: V.S.gapS) {
                                VSectionLabel(text: "已选顺序", trailing: "(picked.count) 个")
                                ForEach(Array(picked.enumerated()), id: \.element) { idx, id in
                                    if let a = QuickPool.all.first(where: { $0.id == id }) {
                                        HStack(spacing: V.S.gapS) {
                                            Text("\(idx + 1)")
                                                .font(V.F.stamp)
                                                .foregroundStyle(V.C.text3)
                                                .monospacedDigit()
                                                .frame(width: 22, alignment: .trailing)
                                            Image(systemName: a.icon)
                                                .font(V.F.icon18)
                                                .foregroundStyle(V.C.text2)
                                                .accessibilityHidden(true)
                                            Text(a.label)
                                                .font(V.F.body)
                                                .foregroundStyle(V.C.text1)
                                            Spacer(minLength: 0)
                                            Button { move(idx, -1) } label: {
                                                Image(systemName: "chevron.up")
                                                    .font(V.F.icon18)
                                                    .foregroundStyle(idx == 0 ? V.C.text4 : V.C.text2)
                                                    .frame(width: V.Hit.min, height: V.Hit.min)
                                                    .contentShape(.rect)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(idx == 0)
                                            .accessibilityLabel("上移 \(a.label)")
                                            Button { move(idx, 1) } label: {
                                                Image(systemName: "chevron.down")
                                                    .font(V.F.icon18)
                                                    .foregroundStyle(idx == picked.count - 1 ? V.C.text4 : V.C.text2)
                                                    .frame(width: V.Hit.min, height: V.Hit.min)
                                                    .contentShape(.rect)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(idx == picked.count - 1)
                                            .accessibilityLabel("下移 \(a.label)")
                                        }
                                        .frame(minHeight: V.Hit.min)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, V.S.pageGutter)
                    }

                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            VSectionLabel(text: "智能排序")
                            Toggle(isOn: $smart) {
                                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                                    Text("按使用次数排前")
                                        .font(V.F.body)
                                        .foregroundStyle(V.C.text1)
                                    Text("关闭时按上面「已选顺序」排；开启后点得多的格子自动排前面。")
                                        .font(V.F.footnote)
                                        .foregroundStyle(V.C.text2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(V.C.blue)
                            .frame(minHeight: V.Hit.min)
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)

                    VActionButton(title: "保存", systemImage: "checkmark") {
                        QuickPool.setSelected(picked)
                        QuickPool.setSmartFirst(smart)
                        dismiss()
                    }
                    .padding(.horizontal, V.S.pageGutter)
                }
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
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
}
