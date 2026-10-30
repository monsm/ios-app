// 截图 / 录屏遮罩 —— 检测到屏幕被捕获时自动遮挡敏感内容。
//
// 2026-10-27 新增（AUDIT-D D-40）：全仓原先 0 处截图保护。
// `ekey` 二维码 = 一把能开门的钥匙 —— `AndroidPair.swift:3-6` 自己就写着
// 「一旦截图外传就再也收不回来」。而它所在的界面可以随便截图、录屏、`ShareLink` 带走。
//
// 判据：`UIScreen.main.isCaptured`（iOS 11+）。为 true 时说明：
//   · 正在录屏（控制中心录屏 / AirPlay 镜像 / QuickTime 录制）
//   · 或刚截过图（该标志在截图瞬间也会短暂为 true）
//
// 用法：`.captureShield()` 挂在含敏感内容的视图上。
// 遮罩用不透明底色 + 一句说明，而不是模糊 —— 模糊在小尺寸下仍可能读出像素。
import SwiftUI
import Combine

/// 监听 `UIScreen.isCaptured` 的观察者。
/// 用 `NotificationCenter` 而不是轮询：`UIScreen.capturedDidChangeNotification` 是系统提供的变更通知。
@MainActor
final class CaptureWatcher: ObservableObject {
    @Published private(set) var isCaptured: Bool = UIScreen.main.isCaptured

    // 2026-10-27 修编译：不再手动持有 `NSObjectProtocol` token。
    // Swift 6 严格并发下 `deinit` 是 nonisolated 的，不能访问非 Sendable 的 token；
    // 而 `addObserver(forName:...)` 返回的 token 必须手动 remove —— 两者冲突。
    // 改用 `publisher(for:)` + Combine `sink`：订阅随 `cancellables` 释放自动取消，
    // deinit 里什么都不用做。
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default
            .publisher(for: UIScreen.capturedDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isCaptured = UIScreen.main.isCaptured
            }
            .store(in: &cancellables)
    }
}

private struct CaptureShieldModifier: ViewModifier {
    @StateObject private var watcher = CaptureWatcher()
    let message: String

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(watcher.isCaptured ? 0 : 1)
            if watcher.isCaptured {
                // 不透明底 + 文字：模糊/半透明在小尺寸下仍可能读出像素
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 28))
                    Text(message)
                        .vkFont(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.xl)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("屏幕正在被录制或被截图，敏感内容已遮挡")
            }
        }
    }
}

extension View {
    /// 检测到录屏/截图时遮挡本视图。用于含 ekey、密码、二维码的界面。
    ///
    /// 注意：`isCaptured` 在模拟器上恒为 false —— 效果只有真机能确认。
    func captureShield(_ message: String = "屏幕正在被录制或被截图\n敏感内容已遮挡，停止后自动恢复") -> some View {
        modifier(CaptureShieldModifier(message: message))
    }
}
