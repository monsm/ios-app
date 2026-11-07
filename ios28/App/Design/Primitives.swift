// Primitives.swift —— 内容层的语法：标签、读数、行、芯片、托盘、分段。
//
// 这些组件只负责"读"，不发起动作（动作在 Controls.swift）。
// 画法纪律：内容层不用玻璃；玻璃只属于会浮起来的东西（镜头、托盘、Tab bar、sheet）。
import SwiftUI

// MARK: - 小标签

struct Kicker: View {
    var text: String
    var dot: Bool = false
    var tint: Color = T.C.ink3

    var body: some View {
        HStack(spacing: 7) {
            if dot {
                Circle()
                    .fill(T.C.brass)
                    .frame(width: 4, height: 4)
            }
            Text(text)
                .type(T.F.kicker)
                .tracking(1.6)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

// MARK: - 徽标

struct Badge: View {
    enum Kind { case brass, danger, calm, ok }
    var text: String
    var kind: Kind = .brass

    private var fg: Color {
        switch kind {
        case .brass: return T.C.brass
        case .danger: return T.C.danger
        case .calm: return T.C.ink2
        case .ok: return T.C.ok
        }
    }

    private var bg: Color {
        switch kind {
        case .brass: return T.C.brassWash
        case .danger: return T.C.dangerWash
        case .calm: return T.C.hair
        case .ok: return T.C.ok.opacity(0.12)
        }
    }

    var body: some View {
        Text(text)
            .type(T.F.caption)
            .fontWeight(.semibold)
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}

// MARK: - 图标砖

enum TileTone { case brass, cool, danger }

struct Tile<Content: View>: View {
    var kind: TileTone = .brass
    var size: CGFloat = 40
    @ViewBuilder var content: () -> Content

    private var bg: Color {
        switch kind {
        case .brass: return T.C.brassWash
        case .cool: return T.C.glass
        case .danger: return T.C.dangerWash
        }
    }

    private var fg: Color {
        switch kind {
        case .brass: return T.C.brass
        case .cool: return T.C.ink2
        case .danger: return T.C.danger
        }
    }

    var body: some View {
        content()
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(fg)
            .frame(width: size, height: size)
            .background(bg, in: RoundedRectangle(cornerRadius: size * 0.45, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                    .strokeBorder(T.C.hair, lineWidth: 0.5)
            }
    }
}

struct GlyphTile: View {
    var symbol: String
    var kind: TileTone = .brass
    var size: CGFloat = 40

    var body: some View {
        Tile(kind: kind, size: size) {
            Image(systemName: symbol)
        }
    }
}

// MARK: - 读数

struct ReadingValue: View {
    var value: String
    var unit: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(T.C.ink)
                // F31：数字变化时**滚动**而不是跳变。
                // 系统自带的数字过渡在「减少动态效果」开启时会自动退化成直接替换 ——
                // 不需要我们自己判一次。
                .contentTransition(.numericText(value: Double(value) ?? 0))
                .animation(T.M.snap, value: value)
            if let unit {
                Text(unit)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
        }
    }
}

struct ReadingColumn: View {
    var label: String
    var value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .type(T.F.kicker)
                .tracking(1.2)
                .foregroundStyle(T.C.ink3)
            ReadingValue(value: value, unit: unit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReadingRow: View {
    var items: [(label: String, value: String, unit: String?)]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(T.C.hair)
                        .frame(width: 0.5)
                        .padding(.horizontal, 14)
                }
                ReadingColumn(label: items[index].label,
                              value: items[index].value,
                              unit: items[index].unit)
            }
        }
    }
}

// MARK: - 内容行

struct ContentRow<Trailing: View>: View {
    var symbol: String?
    var tone: TileTone
    var title: String
    var subtitle: String?
    var chevron: Bool
    @ViewBuilder var trailing: () -> Trailing

    init(symbol: String? = nil,
         tone: TileTone = .brass,
         title: String,
         subtitle: String? = nil,
         chevron: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol
        self.tone = tone
        self.title = title
        self.subtitle = subtitle
        self.chevron = chevron
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                GlyphTile(symbol: symbol, kind: tone, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .type(T.F.body)
                    .fontWeight(.medium)
                    .tracking(-0.2)
                    .foregroundStyle(T.C.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(T.C.ink4)
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

extension ContentRow where Trailing == EmptyView {
    init(symbol: String? = nil, tone: TileTone = .brass,
         title: String, subtitle: String? = nil, chevron: Bool = false) {
        self.init(symbol: symbol, tone: tone, title: title, subtitle: subtitle, chevron: chevron) { EmptyView() }
    }
}

// MARK: - 芯片

struct Chip: View {
    var title: String
    var symbol: String?
    var on: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? .white : T.C.brass)
            }
            Text(title)
                .type(T.F.footnote)
                .fontWeight(.medium)
                .foregroundStyle(on ? .white : T.C.ink)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(on ? T.C.brass : .clear, in: Capsule())
        .liquidGlass(in: Capsule(), tint: on ? nil : GlassMetrics.tint)
    }
}

// MARK: - 工具托盘

struct ToolTray: View {
    struct Item: Identifiable {
        let id: String
        var symbol: String
        var title: String
    }
    var items: [Item]
    var action: (Item) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    action(item)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(T.C.brass)
                        Text(item.title)
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                if item.id != items.last?.id {
                    Rectangle()
                        .fill(T.C.hair)
                        .frame(width: 0.5, height: 34)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        // 托盘同样是浮层：整块可点，用可交互玻璃。
        .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.trayRadius, style: .continuous),
                     tint: GlassMetrics.tint, interactive: true)
        .shadow(color: T.C.shadow, radius: 16, x: 0, y: 10)
    }
}

// MARK: - 分段

struct SegmentedBar: View {
    var items: [String]
    @Binding var selected: Int
    /// 不可用的分段不该还能点：`LockPolicyScreen` 在型号不支持布防时
    /// 只在下面写了一行提示，控件本身仍可点 —— 点了会发一条注定失败的命令。
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                segment(index)
            }
        }
        .padding(4)
        // 分段控件是"一片玻璃上的几格"，玻璃只铺底层；选中格仍是黄铜浅洗。
        .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous),
                     tint: GlassMetrics.tint, interactive: true)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    /// 单独抽出来：整个分段控件写在一个表达式里时，
    /// 编译器会在类型检查上超时（"unable to type-check this expression in reasonable time"）。
    private func segment(_ index: Int) -> some View {
        Button {
            withAnimation(T.M.snap) { selected = index }
        } label: {
            Text(items[index])
                .type(T.F.footnote)
                .fontWeight(.medium)
                .foregroundStyle(index == selected ? T.C.brass : T.C.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if index == selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(T.C.brassWash)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 语音语义：这几格是**一组选项**（不是三个孤零零的按钮）——
        // 读屏用户听到的是「密码，已选中」。
        .accessibilityLabel(items[index])
        .accessibilityAddTraits(index == selected ? [.isSelected] : [])
    }

}

// MARK: - 空态

struct EmptyNote: View {
    var line: String
    var detail: String
    var action: String? = nil
    var run: (() -> Void)? = nil
    /// F34：这一块的母题（光从窗口进来）。不同域给不同变体，
    /// 让空屏也认得出「这是哪一块」，而不是一片空白。
    var motif: EmptyMotif = .door

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EmptyMotifView(motif: motif, size: 44)
                .padding(.bottom, 2)
            DisplayLine(text: line, size: 30)
            Text(detail)
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
            if let action, let run {
                Button(action: run) {
                    Text(action)
                        .type(T.F.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(T.C.brass)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
    }
}

// MARK: - 按压缩放

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(T.M.snap, value: configuration.isPressed)
    }
}
