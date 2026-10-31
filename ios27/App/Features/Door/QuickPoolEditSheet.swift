// QuickPoolEditSheet.swift —— 快速操作池的编辑页（10 选 N + 智能排序开关）。
//
// 入口在 DoorScreen「快捷操作」卡右上角「编辑」。保存写 kf_quick_ids / kf_quick_smart。
import SwiftUI

struct QuickPoolEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = Set(QuickPool.selected.map(\.id))
    @State private var smart: Bool = QuickPool.smartFirst

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
                                        if on { picked.insert(a.id) } else { picked.remove(a.id) }
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

                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            VSectionLabel(text: "顺序")
                            Toggle(isOn: $smart) {
                                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                                    Text("按使用次数排前")
                                        .font(V.F.body)
                                        .foregroundStyle(V.C.text1)
                                    Text("开关关闭时按你在这里的勾选顺序；开启后点得多的格子排前面。")
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
                        QuickPool.setSelected(Array(picked))
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
