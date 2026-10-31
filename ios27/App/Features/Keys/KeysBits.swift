// KeysBits.swift —— 钥匙域里的交互小件（打码 / 归属行 / 入口行 / 分步点 / 提示 / 本地码值工具）。
//
// 与 KeysParts.swift 分开的理由：那边是「读数与台账行」，这边是「能点的控件」。
// 纪律：不改 Design/Components；样式全部走 T./Ink./Signal./State.。
import SwiftUI

// MARK: - 打码码值

/// 逐位打码。默认圆点，点一位揭示一位；离开页面时由页面清空 revealed。
struct KeysMaskedCode: View {
    let value: String
    var size: CGFloat = 22
    @Binding var revealed: Set<Int>

    var body: some View {
        HStack(spacing: T.S.xs) {
            ForEach(Array(value.enumerated()), id: \.offset) { item in
                let index = item.offset
                let char = item.element
                let on = revealed.contains(index)
                Button {
                    if on {
                        revealed.remove(index)
                    } else {
                        revealed.insert(index)
                    }
                } label: {
                    Text(on ? String(char) : "•")
                        .font(T.F.reading(size, weight: .medium))
                        .foregroundStyle(on ? Ink.ink : Ink.inkSub)
                        .frame(minWidth: T.S.xxl, minHeight: T.Hit.min)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(on ? "第 \(index + 1) 位，\(String(char))" : "第 \(index + 1) 位，点按显示")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 面板内分段

/// 面板内分段：与 ChipRow 同一套选中语法（signal 微光底 + 墨色文字），
/// 但**不带页面边距** —— ChipRow 自带 gutter，放进 Panel 里会二次缩进、和上面的小节标题错开。
struct KeysChips<T: Hashable>: View {
    let items: [T]
    let title: (T) -> String
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: T.S.s) {
                ForEach(items, id: \.self) { item in
                    let on = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(title(item))
                            .font(T.F.caption)
                            .foregroundStyle(on ? Ink.ink : Ink.inkSub)
                            .padding(.horizontal, T.S.m)
                            .frame(height: T.Hit.min - T.S.m)
                            .background(on ? Signal.wash : Color.clear, in: .capsule)
                            .overlay {
                                Capsule().strokeBorder(
                                    on ? Signal.base.opacity(0.35) : Ink.hairline,
                                    lineWidth: T.Stroke.hair
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 归属行

/// 归属成员选择行（就地选，不跳页）。选中 = signal 微光底（与 ChipRow 同一语法），不是第二个填充按钮。
struct KeysOwnerRow: View {
    let name: String
    let keyCount: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.m) {
                Text(name)
                    .font(T.F.body)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                Spacer(minLength: T.S.s)
                Reading(value: "\(keyCount)", unit: "枚", size: 13, weight: .regular, tint: Ink.inkFaint, animated: false)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: T.Icon.m, weight: .medium))
                    .foregroundStyle(selected ? Ink.ink : Ink.inkFaint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, T.S.s)
            .frame(minHeight: T.Hit.min)
            .background(selected ? Signal.wash : Color.clear, in: .rect(cornerRadius: T.R.control))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("归属 \(name)" + (selected ? "，已选" : ""))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - 次级入口 / 动作行

/// 次级入口行：图标 + 标题 + 一行说明 + chevron。面板内一行一条。
struct KeysShortcutRow: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.m) {
                Image(systemName: symbol)
                    .font(.system(size: T.Icon.m, weight: .regular))
                    .foregroundStyle(Ink.inkSub)
                    .frame(width: T.Icon.xl, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    Text(title)
                        .font(T.F.body)
                        .foregroundStyle(Ink.ink)
                    Text(detail)
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkSub)
                        .lineLimit(1)
                }
                Spacer(minLength: T.S.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: T.Icon.s, weight: .medium))
                    .foregroundStyle(Ink.inkFaint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

/// 动作行：图标 + 标题，tint 决定语义（危险动作用 State.critical）。右侧可带一枚读数。
struct KeysActionRow: View {
    let title: String
    let symbol: String
    var tint: Color = Ink.ink
    var value: String? = nil
    var unit: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.m) {
                Image(systemName: symbol)
                    .font(.system(size: T.Icon.m, weight: .regular))
                    .foregroundStyle(tint == Ink.ink ? Ink.inkSub : tint)
                    .frame(width: T.Icon.xl, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(T.F.body)
                    .foregroundStyle(tint)
                Spacer(minLength: T.S.s)
                if let value {
                    Reading(value: value, unit: unit, size: 13, weight: .regular, tint: Ink.inkFaint, animated: false)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: T.Icon.s, weight: .medium))
                    .foregroundStyle(Ink.inkFaint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - 分步圆点

/// 分步进度：只在真序列（四步工坊）用，不做装饰编号。
struct KeysStepDots: View {
    let total: Int
    let index: Int
    let labels: [String]

    var body: some View {
        HStack(spacing: T.S.xs) {
            ForEach(0 ..< total, id: \.self) { i in
                Circle()
                    .fill(i <= index ? Signal.base : Ink.hairline)
                    .frame(width: T.S.s, height: T.S.s)
                    .accessibilityHidden(true)
            }
            Text("第 \(index + 1) 步 · \(labels.indices.contains(index) ? labels[index] : "")")
                .font(T.F.caption)
                .foregroundStyle(Ink.inkSub)
                .padding(.leading, T.S.xs)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("表单进度：第 \(index + 1) 步，共 \(total) 步")
    }
}

// MARK: - 行内提示

/// 行内提示：状态点 + 一句话。用于字段错误、重复拦截、链路未接等真状态，不作装饰。
struct KeysInlineNote: View {
    let tone: Tone
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: T.S.s) {
            StateDot(tone: tone, word: text)
                .padding(.top, T.S.xs)
            Text(text)
                .font(T.F.caption)
                .foregroundStyle(tone == .neutral ? Ink.inkSub : tone.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 本机小工具

/// 本地生成数字码（系统 CSPRNG）。只在本机算，不碰协议。
enum KeysCode {
    static func digits(_ count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        var out = ""
        for _ in 0 ..< count {
            out += String(Int.random(in: 0 ... 9, using: &generator))
        }
        return out
    }

    /// 密码强度三格条：全同位 / 顺子 / 位数偏短会降级。纯本地推断，不做承诺。
    static func strength(_ code: String) -> (score: Int, hint: String) {
        guard !code.isEmpty else { return (0, "") }
        let unique = Set(code).count
        var score = 1
        if unique >= 4 { score += 1 }
        if code.count >= 8 { score += 1 }
        if sequential(code) { score -= 1 }
        if unique <= 1 { score = 0 }
        let hint: String
        if unique <= 1 {
            hint = "全是同一个数字，一眼就猜中"
        } else if sequential(code) {
            hint = "顺子（如 123456），不建议"
        } else if code.count < 6 {
            hint = "位数偏短"
        } else {
            hint = "位数与重复度正常"
        }
        return (max(score, 0), hint)
    }

    private static func sequential(_ code: String) -> Bool {
        let digits = code.compactMap { $0.wholeNumberValue }
        guard digits.count >= 4 else { return false }
        let step = digits[1] - digits[0]
        guard step != 0 else { return false }
        for i in 2 ..< digits.count where digits[i] - digits[i - 1] != step { return false }
        return true
    }

    /// 4 位分段（转述/分段复制用）。
    static func segments(_ code: String, size: Int = 4) -> [String] {
        var rest = Array(code)
        var out: [String] = []
        while !rest.isEmpty {
            out.append(String(rest.prefix(size)))
            rest = Array(rest.dropFirst(size))
        }
        return out
    }
}