// Controls.swift —— 会动的东西：镜头、按钮、输入、开关、导航、Tab。
//
// 只有一个动作被允许拥有"仪式感"：开锁。其余动作一律用系统节奏（T.M.snap）。
import SwiftUI
import UIKit

// MARK: - 解锁镜头

/// 镜头用真正的 `Button`，不用「手势 + 点击」两套并行。
/// 原因：`DragGesture(minimumDistance: 0)` 会在手指落下那一刻就赢下手势仲裁，
/// 同挂的 `.onTapGesture` 便再也不会触发 —— 而开锁正是这个 App 唯一不能失灵的动作。
/// 按压反馈交给 `ButtonStyle`（`configuration.isPressed`），没有仲裁歧义。
struct LensPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(T.M.snap, value: configuration.isPressed)
    }
}

struct UnlockLens: View {
    var phase: UnlockPhase
    var enabled: Bool = true
    var action: () -> Void

    private var ringProgress: Double {
        switch phase {
        case .idle: return 0
        case .reaching: return 0.26
        case .sending: return 0.62
        case .waiting: return 0.86
        case .opened: return 1
        case .failed: return 0
        }
    }

    private var glyph: String {
        switch phase {
        case .waiting: return "dot.radiowaves.left.and.right"
        case .opened: return "checkmark"
        case .failed: return "xmark"
        default: return "lock.open"
        }
    }

    private var caption: String {
        switch phase {
        case .idle: return enabled ? "轻点开锁" : "不可用"
        case .reaching: return "连接中"
        case .sending: return "已下发"
        case .waiting: return "等回执"
        case .opened: return "已打开"
        case .failed: return "没打开"
        }
    }

    private var ringColor: Color {
        switch phase {
        case .failed: return T.C.danger
        case .opened: return T.C.ok
        default: return T.C.brass
        }
    }

    var body: some View {
        Button {
            if enabled { action() }
        } label: {
            ZStack {
                // 镜头是整页唯一的仪式感动作，也是浮在日光窗上的功能控件：
                // 真玻璃让背后的窗景参与折射，比材料模糊更像"一片厚玻璃"。
                Circle()
                    .fill(.clear)
                    .liquidGlass(in: Circle(), tint: GlassMetrics.tint)
                    .shadow(color: T.C.shadow, radius: 20, x: 0, y: 14)

                Circle()
                    .strokeBorder(T.C.brassBright.opacity(0.28), lineWidth: 1.5)
                    .padding(5)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                    .animation(T.M.settle, value: ringProgress)

                Circle()
                    .fill(
                        RadialGradient(colors: [T.C.brassBright, T.C.brass],
                                       center: .init(x: 0.34, y: 0.26),
                                       startRadius: 1, endRadius: 26)
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: T.C.brassWash, radius: 14)
                    .overlay {
                        Image(systemName: glyph)
                            .font(.system(size: 18, weight: .medium))
                            // 深色模式的黄铜是亮色实底：白字形只有 1.9:1，
                            // 换自适应前景色（浅色白 / 深色近黑）才看得清。
                            .foregroundStyle(T.C.onAccent.opacity(0.95))
                    }

                if phase == .opened {
                    Circle()
                        .stroke(T.C.brassBright.opacity(0.35), lineWidth: 1)
                        .scaleEffect(1.28)
                        .opacity(0)
                }
            }
            .frame(width: 116, height: 116)
            // 玻璃层已不参与命中；镜头整圆都该是开锁键，不能只剩中间 44pt 的盘面。
            .contentShape(Circle())
            .overlay(alignment: .bottom) {
                Text(caption)
                    .type(T.F.kicker)
                    .tracking(1.8)
                    .foregroundStyle(T.C.ink3)
                    .offset(y: 26)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(LensPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel("开锁")
        .accessibilityHint("连接门锁并下发开锁命令")
        .accessibilityValue(caption)
    }
}

// MARK: - 按钮

struct PrimaryButton: View {
    var title: String
    var busy: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(T.C.onAccent).controlSize(.small)
                }
                Text(title)
                    .type(T.F.body)
                    .fontWeight(.semibold)
            }
            // 实底按钮的文字必须跟着实底走：深色模式的黄铜是亮色，
            // 白字压上去只有 1.9:1（WCAG 要 4.5:1）。
            .foregroundStyle(T.C.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(colors: [T.C.brassBright, T.C.brass],
                               startPoint: .topLeading, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: T.C.brass.opacity(0.22), radius: 18, x: 0, y: 12)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct GhostButton: View {
    var title: String
    var symbol: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                }
                Text(title).type(T.F.footnote).fontWeight(.medium)
            }
            .foregroundStyle(T.C.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous),
                         tint: GlassMetrics.tint, interactive: true)
            // 玻璃只把「画出来的字」算进命中区：不补 contentShape 时，整宽按钮
            // 只有中间那行字能点，点左右两边的玻璃等于没点。
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - 选择胶囊

/// 可点的选择胶囊。选中态用黄铜实底（品牌语义），未选中态是真玻璃。
/// 所有「多选一」的胶囊都走这里 —— 圆角、描边、染色不再各写一份。
struct ChoiceChip: View {
    var title: String
    var symbol: String? = nil
    var on: Bool
    var height: CGFloat = 38
    var fillWidth: Bool = false
    /// 选中态的实底颜色。默认黄铜；危险语义（如「待查」）可传 `T.C.danger`。
    var onColor: Color = T.C.brass
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .type(T.F.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(on ? T.C.onAccent : T.C.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .frame(height: height)
            .modifier(ChoiceSurface(on: on, onColor: onColor))
            // 未选中态是玻璃：命中区默认只到文字；选中态是实底胶囊，整块可点。
            // 补上胶囊形状，两种状态的触达范围才一致（整个胶囊都能点）。
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

private struct ChoiceSurface: ViewModifier {
    var on: Bool
    var onColor: Color

    func body(content: Content) -> some View {
        if on {
            content.background(onColor, in: Capsule())
        } else {
            content.liquidGlass(in: Capsule(), tint: GlassMetrics.tint, interactive: true)
        }
    }
}

struct TextAction: View {
    var title: String
    var destructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .type(T.F.footnote)
                .fontWeight(.medium)
                .foregroundStyle(destructive ? T.C.danger : T.C.brass)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 输入

struct FieldInput: View {
    var placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var symbol: String? = nil
    /// 父视图想让输入框被程序化聚焦时注入（例如页面顶部的放大镜按钮）。
    /// 不传就是普通输入框，现有的所有调用点都不受影响。
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(T.C.ink3)
            }
            if secure {
                focusable(
                    SecureField(placeholder, text: $text)
                        .type(T.F.callout)
                        .foregroundStyle(T.C.ink)
                )
            } else {
                focusable(
                    TextField(placeholder, text: $text)
                        .type(T.F.callout)
                        .foregroundStyle(T.C.ink)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                )
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous),
                     tint: GlassMetrics.tint)
    }

    @ViewBuilder
    private func focusable<V: View>(_ field: V) -> some View {
        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }
}

// MARK: - 开关行

struct SwitchLine: View {
    var title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .type(T.F.body)
                    .foregroundStyle(T.C.ink)
                if let detail {
                    Text(detail)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(T.C.brass)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - 页面骨架

struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 118)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct NavRow<Trailing: View>: View {
    var kicker: String
    var subtitle: String?
    var dot: Bool = true
    var back: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(T.C.ink2)
                        .frame(width: 30, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
            }
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: kicker, dot: dot)
                if let subtitle {
                    Text(subtitle)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink2)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 44)
        .padding(.top, 8)
    }
}

extension NavRow where Trailing == EmptyView {
    init(kicker: String, subtitle: String? = nil, dot: Bool = true, back: (() -> Void)? = nil) {
        self.init(kicker: kicker, subtitle: subtitle, dot: dot, back: back) { EmptyView() }
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @Binding var selection: Int
    /// 第 4 个按钮：设置。浮岛胶囊形态下它不是 Tab（不参与选中态），
    /// 点它是拉起独立的设置栈 sheet；原生系统栏形态（I6）下它才是真 Tab。
    var onSettings: () -> Void

    private let items: [(symbol: String, title: String)] = [
        ("sun.max", "今日"),
        ("key", "通行"),
        ("list.bullet", "记录"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    withAnimation(T.M.snap) { selection = index }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[index].symbol)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(index == selection ? T.C.brass : T.C.ink3)
                        Text(items[index].title)
                            .type(T.F.caption)
                            .foregroundStyle(index == selection ? T.C.ink : T.C.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .overlay(alignment: .bottom) {
                        if index == selection {
                            Circle()
                                .fill(T.C.brass)
                                .frame(width: 3, height: 3)
                                .offset(y: -4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[index].title)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }

            // 设置入口：与三个 Tab 同一排、同一尺寸。它不是「第四个目的地」，
            // 所以没有选中态和底部圆点 —— 按下即拉起设置 sheet。
            Button(action: onSettings) {
                VStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(T.C.ink3)
                    Text("设置")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 8)
        // Tab 栏是浮在内容之上、每个标签都可点的功能层 —— 原生液态玻璃最合适的位置。
        .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.barRadius, style: .continuous),
                     tint: GlassMetrics.tint, interactive: true)
        .shadow(color: T.C.shadow, radius: 26, x: 0, y: 14)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Sheet 骨架

struct SheetChrome<Content: View>: View {
    var title: String
    var subtitle: String?
    var close: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(T.C.ink4.opacity(0.5))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    DisplayLine(text: title, size: 30)
                    if let subtitle {
                        Text(subtitle)
                            .type(T.F.footnote)
                            .foregroundStyle(T.C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(T.C.ink2)
                        .frame(width: 32, height: 32)
                        .liquidGlass(in: Circle(), tint: GlassMetrics.tint, interactive: true)
                        // 与头像同一处置：玻璃改变命中区域，补 44pt 的明确触达区。
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            .padding(.bottom, 18)

            content()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 28)
    }
}
