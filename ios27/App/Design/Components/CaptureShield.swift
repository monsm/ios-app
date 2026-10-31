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

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isCaptured ? 0 : 1)
            if isCaptured {
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
    func captureShield(_ message: String = "屏幕正在被录制或被截图\n敏感内容已遮挡，停止后自动恢复") -> some View {
        modifier(CaptureShieldModifier(message: message))
    }
}
