// Toast.swift —— 全局提示浮层。任何页面的动作回执都可以走 AppToast.shared.show，
// 由 ThresholdApp 在根部挂一次 ToastHost；各页不再自建 toast（原先同一句话
// 在凭证详情是玻璃胶囊、在记录详情是内联灰字，两层皮）。
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppToast {
    static let shared = AppToast()

    /// 提示上的可选动作（F21 的「撤销」）。
    struct Action {
        var title: String
        var run: () -> Void
    }

    private(set) var text: String?
    private(set) var action: Action?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// 显示一条短提示。VoiceOver 开启时延长停留并主动播报 ——
    /// 读屏用户靠的就是这一句，两秒就消失等于没说。
    ///
    /// 带 `action` 时（撤销一类），停留时间更长 —— 人的反应速度没那么快，
    /// 2 秒够读完但不够点。
    func show(_ text: String, action: Action? = nil) {
        dismissTask?.cancel()
        withAnimation(T.M.snap) {
            self.text = text
            self.action = action
        }
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        var lifetime: Duration = UIAccessibility.isVoiceOverRunning ? .seconds(6) : .seconds(2)
        if action != nil { lifetime = .seconds(6) }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            withAnimation(T.M.snap) {
                self?.text = nil
                self?.action = nil
            }
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
                HStack(spacing: 12) {
                    Text(text)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink)
                        .multilineTextAlignment(.center)
                        // 极端数据审查：提示内容里可能拼进文件名（「已读入 <超长文件名>」），
                        // 不限行会撑出一个盖住半个屏幕的胶囊；三行后截断，语义仍可读。
                        .lineLimit(3)
                    if let action = toast.action {
                        Button {
                            action.run()
                            AppToast.shared.show("已撤销")
                        } label: {
                            Text(action.title)
                                .type(T.F.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(T.C.brass)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.title)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // 临时提示是"浮在内容之上"的一层，正是液态玻璃的场景。
                .liquidGlass(in: Capsule(), tint: GlassMetrics.tint)
                .padding(.bottom, 96)
                // 从下往上弹一小段：提示是"发生了一件事"，不是一块自己浮现的雾。
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                // 只有胶囊本身接手势 —— 外面那层空白必须穿透，
                // 否则整块浮层会把下面的 Tab 栏挡住。
                .allowsHitTesting(true)
            }
        }
        .allowsHitTesting(false)
    }
}
