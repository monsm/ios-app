// V7Extras.swift —— 降级项接线用的 v7 补充控件。
//
// 来源：App/Design/V7/V7Components.swift 的令牌与卡片语言（V.C / V.F / V.S / VCard / VActionButton）。
// 这里补「表单行 / 次级按钮 / 读数 / 空态 / chip 行」这些 v7 参考图没有覆盖到的通用零件；
// 不引入旧设计系统（旧令牌一律不用），也不改 Design/ 里的现有语义。
import SwiftUI
import Foundation

/// 描边次级按钮：与 VActionButton 同高同圆角，但不着色 —— 一屏只允许一个 VActionButton。
struct VOutlineButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = V.C.text1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: V.S.gapS) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(V.F.icon15Semibold)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(V.F.bodyStrong)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: V.Action.height)
            .overlay {
                RoundedRectangle(cornerRadius: V.R.action, style: .continuous)
                    .strokeBorder(V.C.tabEdge, lineWidth: V.S.hair)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 凹槽块：卡内次级分组（刻度底 / 读数条 / 内嵌列表）。
struct VInset<Content: View>: View {
    var inset: CGFloat = V.S.gapMS
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.inset))
    }
}

/// 一枚读数：数值 + 单位。数值走等宽，单位走 11pt 淡色。
struct VReading: View {
    let value: String
    var unit: String? = nil
    var font: VFont = V.F.number17
    var tint: Color = V.C.text1
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapXS) {
            Text(value)
                .font(font)
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

/// V7 台账行：等宽时刻在左、事件居中、状态点在右（LedgerRow 的 V7 版本）。
struct VLedgerRow: View {
    let entry: LedgerEntry
    var showDay: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapMS) {
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeFormat.clock(entry.at))
                    .font(V.F.stamp)
                    .foregroundStyle(V.C.text1)
                    .monospacedDigit()
                if showDay {
                    Text(TimeFormat.dayShort(entry.at))
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .monospacedDigit()
                }
            }
            .frame(width: showDay ? 58 : 48, alignment: .leading)

            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(entry.event)
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                if let owner = entry.owner, !owner.isEmpty {
                    Text(owner)
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text2)
                }
            }

            Spacer(minLength: V.S.gapS)
            VStateDot(tone: entry.tone, word: entry.event)
        }
        .frame(minHeight: V.Hit.min + V.S.gapS)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(TimeFormat.clock(entry.at)) \(entry.event)" +
            (entry.owner.map { "，\($0)" } ?? "")
        )
    }
}

/// 卡内读数行：左标签、右读数（等宽数字）。
struct VFieldRow: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = V.C.text1
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapMS) {
            Text(label)
                .font(V.F.body)
                .foregroundStyle(V.C.text2)
            Spacer(minLength: V.S.gapS)
            if mono {
                VReading(value: value, unit: unit, font: V.F.number15, tint: tint, animated: false)
            } else {
                Text(value)
                    .font(V.F.bodyStrong)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: V.List.searchRow)
        .accessibilityElement(children: .combine)
    }
}

/// 卡内读数行：左标签、右读数（等宽数字）。
struct VValueRow: View {
    let label: String
    let value: String
    var tint: Color = V.C.text1
    var mono: Bool = true
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                Text(label)
                    .font(V.F.rowDetail)
                    .foregroundStyle(V.C.text3)
                Spacer(minLength: V.S.gapS)
                Text(value)
                    .font(mono ? V.F.legendLabelStrong.monospacedDigit() : V.F.legendLabel)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: V.List.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

/// 读数网格：2~3 列等宽读数。
struct VReadingGrid: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var unit: String? = nil
        var tint: Color = V.C.text1
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
                            VReading(value: item.value, unit: item.unit, font: V.F.number22, tint: item.tint)
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

/// 卡内文本输入行（普通 / 密码两档）。
struct VTextFieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var secure: Bool = false
    var axisVertical: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text(label)
                .font(V.F.chipLabel)
                .foregroundStyle(V.C.text4)
            Group {
                if secure {
                    SecureField(placeholder.isEmpty ? label : placeholder, text: $text)
                } else if axisVertical {
                    TextField(placeholder.isEmpty ? label : placeholder, text: $text, axis: .vertical)
                        .lineLimit(2 ... 5)
                } else {
                    TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                }
            }
            .font(V.F.body)
            .foregroundStyle(V.C.text1)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            Rectangle().fill(V.C.hairline).frame(height: V.S.hair)
        }
        .frame(minHeight: V.List.rowMinHeight)
        .accessibilityElement(children: .contain)
    }
}

/// 小标签胶囊（分组 / 状态词）。形状 + 文字双通道，不单靠颜色。
struct VTag: View {
    let text: String
    var tint: Color = V.C.text1
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(V.F.footnote)
            .foregroundStyle(filled ? V.C.text1 : tint)
            .padding(.horizontal, V.S.gapM)
            .padding(.vertical, V.S.gapXS)
            .background(filled ? tint : Color.clear, in: Capsule())
            .overlay {
                Capsule().strokeBorder(filled ? Color.clear : V.C.tabEdge, lineWidth: V.S.hair)
            }
            .accessibilityLabel(text)
    }
}

/// 卡内分隔线间距统一版：V7 的 VDivider 无内外边距，这里只包一层呼吸。
struct VRowDivider: View {
    var body: some View {
        VDivider().padding(.vertical, V.S.gapXXS)
    }
}

// MARK: - 状态三通道（形状 + 颜色 + 文字）

/// 状态点：形状随语义变（圆=正常 / 三角=注意 / 方块=危险），不靠颜色单通道。
struct VStateDot: View {
    let tone: Tone
    let word: String

    var body: some View {
        Group {
            switch tone {
            case .critical:
                RoundedRectangle(cornerRadius: 1.2, style: .continuous).fill(tone.color)
            case .attention:
                VTriangle().fill(tone.color)
            default:
                Circle().fill(tone.color)
            }
        }
        .frame(width: V.List.stateDotSize, height: V.List.stateDotSize)
        .accessibilityLabel(word)
    }
}

struct VTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 状态条：状态点 + 文字。
struct VStatusLine: View {
    let tone: Tone
    let text: String

    var body: some View {
        HStack(spacing: V.S.gapS) {
            VStateDot(tone: tone, word: text)
            Text(text)
                .font(V.F.footnote)
                .foregroundStyle(tone == .neutral ? V.C.text2 : tone.color)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 分段 / chip 行。选中 = 蓝色微光底 + 白字；未选 = 透明 + 次文本。
struct VChipRow<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: V.S.gapS) {
                ForEach(items, id: \.self) { item in
                    let on = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(title(item))
                            .font(V.F.footnote)
                            .foregroundStyle(on ? V.C.text1 : V.C.text3)
                            .padding(.horizontal, V.S.gapMS)
                            .frame(height: V.H.chip)
                            .background(on ? V.C.blue.opacity(0.16) : Color.clear, in: .capsule)
                            .overlay {
                                Capsule().strokeBorder(
                                    on ? V.C.blue.opacity(0.75) : V.C.hairline,
                                    lineWidth: V.S.hair
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
        .scrollIndicators(.hidden)
    }
}

/// 空态：系统 ContentUnavailableView + 出路按钮。空态必须给出下一步。
struct VEmptyState: View {
    let title: String
    let message: String
    let actionTitle: String
    var systemImage: String = "tray"
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            VActionButton(title: actionTitle, action: action)
                .frame(maxWidth: 240)
        }
    }
}

/// 统一加载态：菊花 + 禁用，杜绝重复触发。
struct VBusyRow: View {
    let text: String

    var body: some View {
        HStack(spacing: V.S.gapS) {
            ProgressView().controlSize(.small)
            Text(text).font(V.F.footnote).foregroundStyle(V.C.text2)
            Spacer(minLength: 0)
        }
        .frame(minHeight: V.List.searchRow)
    }
}
