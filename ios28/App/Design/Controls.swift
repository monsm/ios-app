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
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle().fill(
                            RadialGradient(colors: [T.C.glassStrong, T.C.glass, T.C.glass],
                                           center: .init(x: 0.32, y: 0.18),
                                           startRadius: 2, endRadius: 120)
                        )
                    }
                    .overlay {
                        Circle().strokeBorder(T.C.glassEdge, lineWidth: 0.5)
                    }
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
                            .foregroundStyle(Color(uiColor: .white).opacity(0.95))
                    }

                if phase == .opened {
                    Circle()
                        .stroke(T.C.brassBright.opacity(0.35), lineWidth: 1)
                        .scaleEffect(1.28)
                        .opacity(0)
                }
            }
            .frame(width: 116, height: 116)
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
                    ProgressView().tint(.white).controlSize(.small)
                }
                Text(title)
                    .type(T.F.body)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
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
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(T.C.glass)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
            }
        }
        .buttonStyle(PressStyle())
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
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(T.C.glass)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
        }
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
        }
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(T.C.glassStrong)
                .background {
                    RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.ultraThinMaterial)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
        }
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
                        .background(T.C.hair, in: Circle())
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
