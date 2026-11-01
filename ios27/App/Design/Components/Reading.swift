// Reading.swift —— 定宽读数。
//
// 这是本设计的性格所在：所有数字右对齐 + 等宽 + 单位小字紧随其后。
// 换值不跳宽、不重排，眼睛不用重新找位置。
import SwiftUI

/// 一枚读数：数值 + 单位。数值走等宽，单位走 11pt 淡墨。
struct Reading: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 17
    var weight: Font.Weight = .medium
    var tint: Color = V.C.text1
    /// 变化时是否做数字滚动（reduceMotion 下自动关）。
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapXS) {
            Text(value)
                .font(V.F.sans(size, weight: weight))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(reduceMotion || !animated ? .identity : .numericText())
            if let unit {
                Text(unit)
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .tracking(0.6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 读数网格：2~3 列等宽读数，仪器面板式的读数区。
struct ReadingGrid: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var unit: String? = nil
        var tint: Color = V.C.text1
    }

    let items: [Item]
    var columns: Int = 2
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 无障碍字号下强制单列。
    ///
    /// 2026-11-01：读数是 `size: 22` 起的等宽数字，随 Dynamic Type 放大后
    /// 在 2–3 列里会被压成"两个字一行"甚至截断；而读数恰恰是**必须读准**的内容
    /// （电量 82% 与 8% 只差一位）。单列让每个读数都有整行宽度。
    /// 用原生 `DynamicTypeSize.isAccessibilitySize` 判定，不自己算缩放比。
    private var effectiveColumns: Int { typeSize.isAccessibilitySize ? 1 : max(columns, 1) }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: effectiveColumns).map {
            Array(items[$0 ..< min($0 + effectiveColumns, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(V.C.hairline)
                        .frame(height: V.S.hair)
                        .padding(.vertical, V.S.gapMS)
                }
                HStack(alignment: .top, spacing: V.S.gapMS) {
                    ForEach(row) { item in
                        VStack(alignment: .leading, spacing: V.S.gapXS) {
                            Text(item.label)
                                .font(V.F.unit)
                                .foregroundStyle(V.C.text3)
                                .tracking(0.6)
                            Reading(value: item.value, unit: item.unit, size: 22, tint: item.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.count < effectiveColumns {
                        ForEach(0 ..< (effectiveColumns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}
