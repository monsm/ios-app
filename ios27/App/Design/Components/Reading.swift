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
    var tint: Color = Ink.ink
    /// 变化时是否做数字滚动（reduceMotion 下自动关）。
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: T.S.xs) {
            Text(value)
                .font(T.F.reading(size, weight: weight))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(reduceMotion || !animated ? .identity : .numericText())
            if let unit {
                Text(unit)
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .tracking(0.6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 左标签 / 右读数的表单行。仪器面板的骨架：标签靠左，读数贴右。
struct FieldRow: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = Ink.ink
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: T.S.m) {
            Text(label)
                .font(T.F.body)
                .foregroundStyle(Ink.inkSub)
            Spacer(minLength: T.S.s)
            if mono {
                Reading(value: value, unit: unit, size: 15, tint: tint, animated: false)
            } else {
                Text(value)
                    .font(T.F.bodyStrong)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: T.Hit.min - T.S.s)
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
        var tint: Color = Ink.ink
    }

    let items: [Item]
    var columns: Int = 2

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0 ..< min($0 + columns, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Ink.hairline)
                        .frame(height: T.Stroke.hair)
                        .padding(.vertical, T.S.m)
                }
                HStack(alignment: .top, spacing: T.S.m) {
                    ForEach(row) { item in
                        VStack(alignment: .leading, spacing: T.S.xs) {
                            Text(item.label)
                                .font(T.F.unit)
                                .foregroundStyle(Ink.inkFaint)
                                .tracking(0.6)
                            Reading(value: item.value, unit: item.unit, size: 22, tint: item.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.count < columns {
                        ForEach(0 ..< (columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}
