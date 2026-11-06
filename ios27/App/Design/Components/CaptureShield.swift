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
    ///
    /// 2026-11-04（安全文案复核 · 过度承诺）：原文写「收到就遮一小段时间，让『截图里
    /// 带上敏感内容』这条路也走不通」—— **不成立**。`userDidTakeScreenshotNotification`
    /// 在**图片已经写进相册之后**才发出，此后的遮挡不可能把明文从那张图里去掉。
    /// 它真正的作用只有两个：① 让**紧接着**的下一次截屏/录屏前后是遮挡状态；
    /// ② 给用户一个明确提醒。文案与注释都按这个事实改写，不假装能救回已经拍下的图。
    @State private var screenshotFlash = false
    @State private var flashTask: Task<Void, Never>?
    /// 2026-11-01（Round 309）：**退到后台时的系统快照**。
    /// `isCaptured` 只反映「正在录屏/被别的进程捕获」，按 Home 键并不会把它置真 ——
    /// 于是 iOS 在应用切换器里留下的那张快照**照原样带着明文码值**（凭证详情/动态码/备份页都有）。
    /// 这与「装遮挡是为了不让码值出现在别人的屏幕上」这个初衷自相矛盾，所以补上：非 active 即遮。
    /// 用 `scenePhase` 而不是 `didEnterBackground` 通知：前者在 App 失活的第一时间就变，
    /// 快照拍的是失活后的画面，能赶在快照之前遮住。
    @Environment(\.scenePhase) private var scenePhase

    private var sceneHidden: Bool { scenePhase != .active }
    private var hidden: Bool { isCaptured || screenshotFlash || sceneHidden }
    /// 只因为「退到后台」而遮 ⇒ 换一句中性文案（此时并没有人在录屏）。
    private var sceneOnly: Bool { sceneHidden && !isCaptured && !screenshotFlash }

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(hidden ? 0 : 1)
            if hidden {
                VStack(spacing: V8.S.gapS) {
                    Image(systemName: sceneOnly ? "lock.fill" : "eye.slash.fill")
                        .font(V8.T.title2)
                        .foregroundStyle(V8.C.ink4)
                        .accessibilityHidden(true)
                    Text(screenshotFlash ? "刚刚的截图里可能带有明文码值 —— 请确认这张图只留在你自己的相册里。"
                     : (sceneOnly ? "已隐藏" : message))
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink1)
                        .multilineTextAlignment(.center)
                }
                .padding(V8.S.gapL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(V8.C.card)
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
