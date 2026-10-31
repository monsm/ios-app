// AlarmKindsSheet.swift —— 记录页「告警类型多选」（原 RecordsSheets.swift:9-62）。
//
// 这屏干什么：按锁端日志里**实际存在**的告警类型做多选筛选；不选 = 不限类型。
// 数据从哪来：StatsKit.alarmTypes（4 静态电量 / 10 多次密码失败锁定）+ RecordVerbs.alarmVerb 文案。
// 主动作：无保存按钮 —— 勾选即写 RecordsRoute.alarmKinds，记录页当场重算。
import SwiftUI

struct AlarmKindsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var route = RecordsRoute.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                AlarmKindsPanel(selection: Binding(
                    get: { route.alarmKinds },
                    set: { route.alarmKinds = $0 }
                ))
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("告警类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空") { route.alarmKinds.removeAll() }
                        .disabled(route.alarmKinds.isEmpty)
                        .accessibilityLabel("清空告警类型筛选")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("完成告警类型筛选")
                }
            }
        }
    }
}

/// 目的地页版本（Dest .alarmKinds）。与 sheet 共用同一个面板与同一份 route 状态。
struct AlarmKindsScreen: View {
    @State private var route = RecordsRoute.shared

    var body: some View {
        ScrollView {
            AlarmKindsPanel(selection: Binding(
                get: { route.alarmKinds },
                set: { route.alarmKinds = $0 }
            ))
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("告警类型")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AlarmKindsPanel: View {
    @Binding var selection: Set<Int>

    private var types: [Int] {
        Array(StatsKit.alarmTypes).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            VSectionLabel(text: "只看选中的类型", trailing: selection.isEmpty ? "不限" : "已选 \(selection.count) 项")
            VCard {
                VStack(spacing: 0) {
                    ForEach(Array(types.enumerated()), id: \.offset) { pair in
                        if pair.offset > 0 { VDivider() }
                        row(type: pair.element)
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
            SettingsNote(text: "列表按锁端日志里实际有的告警类型给出；协议没有「胁迫」类告警，所以这里不列。不选 = 不限类型。")
                .padding(.horizontal, V.S.pageGutter)
            if !selection.isEmpty {
                VOutlineButton(title: "清除类型筛选", systemImage: "line.3.horizontal.decrease.circle") {
                    selection.removeAll()
                }
                .padding(.horizontal, V.S.pageGutter)
            }
        }
    }

    private func row(type: Int) -> some View {
        let on = selection.contains(type)
        let label = RecordVerbs.alarmVerb[type] ?? StatusParser.logTypes[type] ?? "类型 \(type)"
        return Button {
            if on { selection.remove(type) } else { selection.insert(type) }
        } label: {
            HStack(spacing: V.S.gapM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(V.F.icon15)
                    .foregroundStyle(V.C.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    Text(label)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                    Text("锁端类型 \(type)")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                }
                Spacer(minLength: V.S.gapS)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(V.F.icon18)
                    .foregroundStyle(on ? V.C.blue : V.C.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V.List.rowMinHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("AlarmKindsSheet") {
    AlarmKindsSheet()
}
