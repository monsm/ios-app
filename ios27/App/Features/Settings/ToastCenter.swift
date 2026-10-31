// ToastCenter.swift —— 全局提示条（原 App/Core/ToastCenter.swift 的等价实现）。
//
// 来源：原 App/Core/ToastCenter.swift + AppState.showToast（全 App 顶部一条轻提示）。
// 用法：任意页面动作完成后调 AppToast.shared.show("已保存")；RootView 顶部常驻挂 ToastHost。
// 边界：只提示「刚发生了什么」，不用它承载需要用户决策的信息（那些走页面内说明/弹窗）。
import SwiftUI

enum ToastTone {
    case info, ok, warn

    var color: Color {
        switch self {
        case .info: return V.C.blue
        case .ok: return V.C.rewardGreen
        case .warn: return V.C.pink
        }
    }
}

@MainActor
@Observable
final class AppToast {
    static let shared = AppToast()
    private init() {}

    private(set) var message: String?
    private(set) var tone: ToastTone = .info
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, tone: ToastTone = .info) {
        message = text
        self.tone = tone
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

/// 顶部悬浮提示条（v7 卡片语言；不遮导航标题，只压在上缘安全区内）。
struct ToastHost: View {
    @State private var toast = AppToast.shared

    var body: some View {
        VStack {
            if let message = toast.message {
                HStack(spacing: V.S.gapS) {
                    Circle()
                        .fill(toast.tone.color)
                        .frame(width: V.List.dotSize, height: V.List.dotSize)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text1)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, V.S.gapM)
                .padding(.vertical, V.S.gapS)
                .background(V.C.tabGlass, in: .rect(cornerRadius: V.R.action, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: V.R.action, style: .continuous)
                        .strokeBorder(V.C.tabEdge, lineWidth: V.S.hair)
                }
                .padding(.horizontal, V.S.cardGutter)
                .padding(.top, V.S.gapS)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(message)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }
}
