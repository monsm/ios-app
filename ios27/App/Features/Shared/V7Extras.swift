// V7Extras.swift —— 降级项接线用的 v7 补充控件。
//
// 来源：App/Design/V7/V7Components.swift 的令牌与卡片语言（V.C / V.F / V.S / VCard / VActionButton）。
// 这里只补「表单行 / 次级按钮 / 小标签」三个 v7 参考图没有覆盖到的通用零件；
// 不引入旧设计系统（T./Ink./Signal. 一律不用），也不改 Design/ 里的现有语义。
import SwiftUI

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
                        .font(V.F.sans(15, weight: .semibold))
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
                    .font(mono ? V.F.sans(14, weight: .semibold).monospacedDigit() : V.F.sans(14))
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
