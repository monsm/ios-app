// CaptureShield.swift —— 截图/录屏遮罩：检测到屏幕被捕获时自动遮挡敏感内容。
//
// 判据：UIScreen.main.isCaptured（iOS 11+）。监听 UIScreen.capturedDidChangeNotification，
// 不轮询。挂在含敏感内容的视图上：KeyDetail 的码值卡、ShareToAndroid 的二维码。
import SwiftUI
import UIKit

/// 监听 UIScreen.isCaptured 的观察者。
final class CaptureWatcher: ObservableObject {
    @Published private(set) var isCaptured: Bool = UIScreen.main.isCaptured

    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isCaptured = UIScreen.main.isCaptured
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}

private struct CaptureShieldModifier: ViewModifier {
    let message: String
    @StateObject private var watcher = CaptureWatcher()

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(watcher.isCaptured ? 0 : 1)
            if watcher.isCaptured {
                VStack(spacing: T.S.s) {
                    Image(systemName: "eye.slash.fill")
                        .font(T.F.icon(T.Icon.l, weight: .regular))
                        .foregroundStyle(Ink.inkSub)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(T.F.body)
                        .foregroundStyle(Ink.ink)
                        .multilineTextAlignment(.center)
                }
                .padding(T.S.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Ink.plate)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension View {
    /// 截图/录屏时遮挡敏感内容；停止后自动恢复。
    func captureShield(_ message: String = "屏幕正在被录制或被截图\n敏感内容已遮挡，停止后自动恢复") -> some View {
        modifier(CaptureShieldModifier(message: message))
    }
}
