// Toast.swift —— 全局提示浮层。任何页面的动作回执都可以走 AppToast.shared.show，
// 由 ThresholdApp 在根部挂一次 ToastHost；各页不再自建 toast（原先同一句话
// 在凭证详情是玻璃胶囊、在记录详情是内联灰字，两层皮）。
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppToast {
    static let shared = AppToast()

    private(set) var text: String?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// 显示一条短提示。VoiceOver 开启时延长停留并主动播报 ——
    /// 读屏用户靠的就是这一句，两秒就消失等于没说。
    func show(_ text: String) {
        dismissTask?.cancel()
        withAnimation(T.M.snap) { self.text = text }
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        let lifetime: Duration = UIAccessibility.isVoiceOverRunning ? .seconds(6) : .seconds(2)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            withAnimation(T.M.snap) { self?.text = nil }
        }
    }
}

/// 挂在根部的提示层。它不接手势（提示不需要点），所以整块 allowsHitTesting(false)，
// 不然会挡住下面 Tab 栏边缘的点击。
struct ToastHost: View {
    private var toast = AppToast.shared

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let text = toast.text {
                Text(text)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    // 临时提示是"浮在内容之上"的一层，正是液态玻璃的场景。
                    .liquidGlass(in: Capsule(), tint: GlassMetrics.tint)
                    .padding(.bottom, 96)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}
