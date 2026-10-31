// MemberCreateParts.swift —— 建档向导的私有零件（步骤刻度 / emoji 代号 / 角色行 / 临时码块）。
//
// 为什么单独成文件：MemberCreateScreen 超过 400 行；这些块只吃绑定与回调，拆开后向导本体只剩流程。
import SwiftUI

// MARK: - 真序列刻度（01/02/03/04；数字走 Reading，等宽对齐）

struct HHCreationStepScale: View {
    let steps: [String]
    let current: Int

    var body: some View {
        HStack(spacing: V.S.gapMS) {
            ForEach(steps.indices, id: \.self) { index in
                tick(index)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tick(_ index: Int) -> some View {
        let on = index == current
        let past = index < current
        return VStack(alignment: .leading, spacing: V.S.gapXS) {
            VReading(
                value: steps[index],
                size: HHMetric.readingStep,
                tint: on ? V.C.text1 : (past ? V.C.text2 : V.C.text3),
                animated: false
            )
            Rectangle()
                .fill(on ? V.C.text1 : (past ? V.C.text2 : V.C.hairline))
                .frame(height: on ? V.Stroke.focus : V.S.hair)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps[index] + (on ? "，当前步骤" : ""))
    }
}

// MARK: - emoji 代号

struct HHEmojiPicker: View {
    @Binding var emoji: String
    static let options = ["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"]

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("emoji 代号")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .tracking(0.6)
            ScrollView(.horizontal) {
                HStack(spacing: V.S.gapS) {
                    ForEach(Self.options.indices, id: \.self) { index in
                        chip(Self.options[index])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(_ e: String) -> some View {
        let on = emoji == e
        return Button {
            emoji = e
        } label: {
            Text(e.isEmpty ? "首字" : e)
                .font(e.isEmpty ? V.F.unit : V.F.body)
                .foregroundStyle(on ? V.C.text1 : V.C.text2)
                .frame(width: V.Hit.min, height: V.Hit.min)
                .background(on ? V.C.blue.opacity(0.16) : V.C.cardAlt, in: .circle)
                .overlay {
                    Circle().strokeBorder(on ? V.C.blue.opacity(0.75) : V.C.hairline,
                                          lineWidth: V.S.hair)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(e.isEmpty ? "默认首字" : "代号 \(e)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 角色单选行（副标题由权限矩阵现算）

struct HHRoleOptionRow: View {
    let role: MemberCard.Role
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: V.S.gapMS) {
                HHRoleMark(role: role)
                    .frame(width: V.Hit.min + V.S.gapMS, alignment: .leading)
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    Text(role.rawValue)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                    Text(HHPerm.hint(role) + " · " + HHPerm.scene(role))
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: V.S.gapS)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon18)
                    .foregroundStyle(selected ? V.C.text1 : V.C.text3)
            }
            .frame(minHeight: V.Hit.min + V.S.gapS)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("角色 \(role.rawValue)，\(HHPerm.hint(role))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 校验提示（状态三通道里的「注意」）

struct HHFieldNote: View {
    let text: String

    var body: some View {
        HStack(spacing: V.S.gapS) {
            VStateDot(tone: .attention, word: text)
            Text(text)
                .font(V.F.unit)
                .foregroundStyle(V.C.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 第四步：临时码（6~8 位纯数字）

struct HHCodePanel: View {
    @Binding var makeCode: Bool
    @Binding var code: String
    let codeOK: Bool
    let expiryText: String

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "临时码", trailing: makeCode ? "10 分钟" : "未启用")
                if makeCode {
                    HHTextField(label: "6~8 位纯数字", text: $code, placeholder: "例如 482913", keyboard: .numberPad)
                    if !code.isEmpty && !codeOK {
                        HHFieldNote(text: "临时码要 6~8 位纯数字；现在这串不会被下发。")
                    }
                    VFieldRow(label: "有效期至", value: expiryText, mono: true)
                    Text("到期后锁端自动失效，不需要再回来删。")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                } else {
                    Text("不建码也能完成建档 —— 之后到「钥匙」页新建一枚，归属选这个成员即可。")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }
}
