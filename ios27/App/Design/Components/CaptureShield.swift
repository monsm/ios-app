// CaptureShield.swift —— 截图/录屏遮罩：检测到屏幕被捕获时自动遮挡敏感内容。
//
// 判据：UIScreen.isCaptured（iOS 11+）。监听 UIScreen.capturedDidChangeNotification，不轮询。
// 挂在含敏感内容的视图上：KeyDetail 的码值卡、ShareToAndroid 的二维码。
//
// 2026-10-31 iOS 27 审核：不再使用已废弃的 UIScreen.main。屏幕实例从当前前台
// UIWindowScene 取（scene.screen），观察者也只跟这一块屏；SwiftUI 的 onReceive
// 直接驱动 @State，避免 ObservableObject 在 Sendable 闭包里捕获非 Sendable 的 self。
import SwiftUI
import UIKit

private struct CaptureShieldModifier: ViewModifier {
    let message: String
    @State private var isCaptured = false
    /// SEC-11：普通截图**不会**触发 isCaptured —— 只在按下快门那一刻发一个通知。
    /// 收到就遮一小段时间，让「截图里带上敏感内容」这条路也走不通。
    @State private var screenshotFlash = false
    @State private var flashTask: Task<Void, Never>?

    private var hidden: Bool { isCaptured || screenshotFlash }

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(hidden ? 0 : 1)
            if hidden {
                VStack(spacing: V.S.gapS) {
                    Image(systemName: "eye.slash.fill")
                        .font(V.F.icon22)
                        .foregroundStyle(V.C.text2)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                        .multilineTextAlignment(.center)
                }
                .padding(V.S.gap16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(V.C.card)
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            refresh()
        }
        // 普通截图：系统只发通知，不会把 isCaptured 置真。遮 3 秒再恢复。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            flashAfterScreenshot()
        }
        .onDisappear { flashTask?.cancel(); flashTask = nil }
    }

    private func flashAfterScreenshot() {
        flashTask?.cancel()
        screenshotFlash = true
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            screenshotFlash = false
        }
    }

    /// 只读当前激活的前台 WindowScene 的 screen；找不到时按未捕获处理（不误遮挡）。
    private func refresh() {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
        isCaptured = screen?.isCaptured ?? false
    }
}

extension View {
    /// 截图/录屏时遮挡敏感内容；停止后自动恢复。
    /// SEC-11：文案不再承诺"防截图"（做不到）—— 如实说：录屏时遮挡，截图会被检测并遮一下。
    func captureShield(_ message: String = "屏幕正在被录制或被截图\n敏感内容已遮挡，稍后自动恢复") -> some View {
        modifier(CaptureShieldModifier(message: message))
    }
}
