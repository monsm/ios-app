// StateDot.swift —— 状态三通道：形状 + 颜色 + 文字。
// 色觉障碍用户靠形状与文字就能分辨；颜色只是第三通道，不是唯一通道。
import SwiftUI

/// 语义语气。Hashable 是必须的：LedgerEntry 等数据模型把它当字段并存进 Set/Dictionary。
enum Tone: Hashable {
    case ok, attention, critical, neutral, live

    var color: Color {
        switch self {
        case .ok: return State.ok
        case .attention: return State.attention
        case .critical: return State.critical
        case .neutral: return Ink.inkFaint
        case .live: return Signal.base
        }
    }
}

/// 状态点：形状随语义变（圆=正常 / 三角=注意 / 方块=危险），不靠颜色单通道。
struct StateDot: View {
    let tone: Tone
    /// 无障碍朗读用的语义词（「正常」「注意」「危险」）。
    let word: String

    var body: some View {
        // 不能用「返回 some View 的形状再 .fill()」—— .fill 只在 Shape 上有，
        // 而 @ViewBuilder 的 some View 已经不是 Shape 了。所以每个分支各自 fill 完再交给 Group。
        Group {
            switch tone {
            case .critical:
                // 方块 = 危险（最重的形状）
                RoundedRectangle(cornerRadius: 1.2, style: .continuous).fill(tone.color)
            case .attention:
                // 三角 = 注意
                Triangle().fill(tone.color)
            default:
                Circle().fill(tone.color)
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityLabel(word)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 状态条：状态点 + 文字。用于面板顶部的一行状态。
struct StatusLine: View {
    let tone: Tone
    let text: String

    var body: some View {
        HStack(spacing: T.S.s) {
            StateDot(tone: tone, word: text)
            Text(text)
                .font(T.F.caption)
                .foregroundStyle(tone == .neutral ? Ink.inkSub : tone.color)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 分段 / chip 行。选中 = signal 微光底 + 墨色文字；未选 = 透明 + 次墨。
struct ChipRow<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

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
                            .frame(height: T.H.chip)
                            .background(on ? Signal.wash : Color.clear, in: .capsule)
                            .overlay {
                                Capsule().strokeBorder(
                                    on ? Signal.edge : Ink.hairline,
                                    lineWidth: T.Stroke.hair
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
        .scrollIndicators(.hidden)
    }
}

/// 唯一主动作按钮。同屏只许一个。
struct PrimaryAction: View {
    let title: String
    var systemImage: String? = nil
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.s) {
                if busy {
                    ProgressView().controlSize(.small).tint(Signal.on)
                } else if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true).font(T.F.icon(T.Icon.m, weight: .medium))
                }
                Text(title).font(T.F.bodyStrong)
            }
            .foregroundStyle(Signal.on)
            .frame(maxWidth: .infinity)
            .frame(height: T.H.action)
            .background(Signal.base, in: .rect(cornerRadius: T.R.control))
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .accessibilityLabel(title)
    }
}

/// 次级动作：描边，不着色。
struct SecondaryAction: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.s) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true).font(T.F.icon(T.Icon.m, weight: .medium))
                }
                Text(title).font(T.F.bodyStrong)
            }
            .foregroundStyle(Ink.ink)
            .frame(maxWidth: .infinity)
            .frame(height: T.H.action)
            .overlay {
                RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }
}

/// 统一按压：只做 transform，不改 bounds。
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(T.M.snap, value: configuration.isPressed)
    }
}

/// 空态：系统 ContentUnavailableView + 出路按钮。空态必须给出下一步。
struct EmptyPanel: View {
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
            PrimaryAction(title: actionTitle, action: action)
                .frame(maxWidth: 240)
        }
    }
}

/// 统一加载态：菊花 + 禁用，杜绝重复触发。
struct BusyRow: View {
    let text: String

    var body: some View {
        HStack(spacing: T.S.s) {
            ProgressView().controlSize(.small)
            Text(text).font(T.F.caption).foregroundStyle(Ink.inkSub)
            Spacer(minLength: 0)
        }
        .frame(minHeight: T.Hit.min)
    }
}
