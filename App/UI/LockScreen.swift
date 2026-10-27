// 应用锁界面 —— 冷启动时的密码门禁。
//
// 2026-10-27 新增（AUDIT-D D-01 + D-48）：用户决策「恢复应用锁 + 完整实现伪装码」。
// 触发时机：**只在冷启动**（用户拍板，不打断日常切前台）。
//
// 这个界面同时是伪装码的入口：
//   · 输正常密码 → 正常进主界面
//   · 输胁迫码   → 进空壳模式（门能开、凭证与记录显示为空），不报警不阻止
//
// 为什么伪装模式“不报警”：被胁迫时任何异常反应（震动、红字、延迟）都可能让胁迫者升级手段。
// 隐藏的是**数据**，不是开锁能力 —— 门照样能开，这是保命前提。
import SwiftUI

struct LockScreen: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var lock = AppLock.shared

    @State private var input = ""
    @State private var errorText = ""
    @State private var shake = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DS.Space.l) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DS.Palette.accentText)
                .accessibilityHidden(true)

            Text("离线锁管家")
                .vkFont(.title2, weight: .semibold)
                .foregroundStyle(DS.Palette.text)

            Text("输入本机密码继续")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)

            // 密码框：数字键盘 + 圆点遮挡
            SecureField("本机密码", text: $input)
                .keyboardType(.numberPad)
                .textContentType(.password)
                .multilineTextAlignment(.center)
                .vkFont(.title3.monospacedDigit())
                .focused($focused)
                .frame(maxWidth: 220)
                .padding(.vertical, DS.Space.s)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Palette.surface)
                )
                .modifier(ShakeEffect(animatableData: CGFloat(shake)))
                .accessibilityLabel("本机密码输入框")
                .onSubmit(submit)

            if !errorText.isEmpty {
                Text(errorText)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.l)
            }

            BusyButton(title: "解锁", systemImage: "lock.open", isBusy: false) {
                submit()
            }
            .disabled(input.isEmpty || lock.cooldownRemaining() > 0)
            .frame(maxWidth: 220)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsScreenBackground()
        .onAppear { focused = true }
        // 冷却倒计时：每秒重算一次，让按钮的 disabled 状态与提示文字跟着走
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if lock.cooldownRemaining() > 0 {
                errorText = "尝试次数过多，请等 \(lock.cooldownRemaining()) 秒"
            } else if errorText.hasPrefix("尝试次数过多") {
                errorText = ""
            }
        }
    }

    private func submit() {
        let pw = input
        guard !pw.isEmpty else { return }
        switch lock.verify(pw) {
        case .success:
            input = ""; errorText = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .decoy:
            // 伪装模式：**不给任何可察觉的反馈** —— 不震动、不变色、不延迟。
            // 与正常解锁在观感上完全一致，否则被胁迫时等于当场暴露。
            input = ""; errorText = ""
        case .wrong(let remaining):
            input = ""
            withAnimation(.default) { shake += 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorText = remaining > 0
                ? "密码不正确；尝试次数过多，请等 \(remaining) 秒"
                : "密码不正确"
        case .cooling(let remaining):
            input = ""
            errorText = "尝试次数过多，请等 \(remaining) 秒"
        }
    }
}

/// 输错时抖一下。纯视觉反馈，不携带信息（伪装码成功时不抖）。
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
