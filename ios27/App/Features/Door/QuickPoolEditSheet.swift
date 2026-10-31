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
                VStack(spacing: T.S.l) {
                    Panel {
                        VStack(alignment: .leading, spacing: T.S.s) {
                            SectionLabel(text: "显示哪些格子")
                            ForEach(QuickPool.all) { a in
                                Toggle(isOn: Binding(
                                    get: { picked.contains(a.id) },
                                    set: { on in
                                        if on { picked.insert(a.id) } else { picked.remove(a.id) }
                                    }
                                )) {
                                    HStack(spacing: T.S.s) {
                                        Image(systemName: a.icon)
                                            .font(T.F.icon(T.Icon.m, weight: .regular))
                                            .foregroundStyle(Ink.inkSub)
                                            .frame(width: T.Icon.l)
                                            .accessibilityHidden(true)
                                        Text(a.label)
                                            .font(T.F.body)
                                            .foregroundStyle(Ink.ink)
                                    }
                                }
                                .tint(Signal.base)
                                .frame(minHeight: T.Hit.min)
                            }
                        }
                    }
                    .padding(.horizontal, T.S.gutter)

                    Panel {
                        VStack(alignment: .leading, spacing: T.S.s) {
                            SectionLabel(text: "顺序")
                            Toggle(isOn: $smart) {
                                VStack(alignment: .leading, spacing: T.S.xxs) {
                                    Text("按使用次数排前")
                                        .font(T.F.body)
                                        .foregroundStyle(Ink.ink)
                                    Text("开关关闭时按你在这里的勾选顺序；开启后点得多的格子排前面。")
                                        .font(T.F.caption)
                                        .foregroundStyle(Ink.inkSub)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(Signal.base)
                            .frame(minHeight: T.Hit.min)
                        }
                    }
                    .padding(.horizontal, T.S.gutter)

                    PrimaryAction(title: "保存", systemImage: "checkmark") {
                        QuickPool.setSelected(Array(picked))
                        QuickPool.setSmartFirst(smart)
                        dismiss()
                    }
                    .padding(.horizontal, T.S.gutter)
                }
                .padding(.vertical, T.S.l)
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
