// 374 录屏遮罩 —— 屏幕录制/镜像时不显示口令明文
// 336 截图警示 —— 监 `UIApplication.userDidTakeScreenshotNotification` (公开 API, 已按 docs/API-VERIFY.md
// 撞过官方页: UIKit/UIApplication/userDidTakeScreenshotNotification = 200)。
// 用 UIScreen.isCaptured (公开 API, iOS 11+) + capturedDidChangeNotification。
// 刻意用 UIScreen.screens.first 而不是 UIScreen.main —— 后者 iOS 16 起已废弃，
// 而且多屏 (外接显示) 时"哪块屏在录"本来就不该由 main 猜。
//
// 边界写清楚，不过度承诺：这个 API 只能告诉你"系统正在采集屏幕"，
// 不知道被谁采集、采集到哪；越狱/私有钩子绕过不可防。所以它挡的是"随手录屏留档"，不是硬对抗。
// 截图通知同理：**只知道发生过一次截图**，不知道拍到的是不是这一屏 (它可能在采集后才切走)，
// 所以 336 的话术是"可能已进那张图片"而不是"已拍到"。
import UIKit
import Combine

@MainActor
final class ScreenCaptureWatch: ObservableObject {
    static let shared = ScreenCaptureWatch()
    @Published private(set) var recording = UIScreen.screens.first?.isCaptured ?? false
    /// 336：最近一次系统截图的 Unix 秒；0 = 本进程启动以来没观测到。
    /// 读侧比的是"本页打开时刻"，所以这个值只在同一进程内有意义 (不写盘、不进备份)。
    @Published private(set) var screenshotAt: Double = 0
    private var token: NSObjectProtocol?
    private var shotToken: NSObjectProtocol?

    /// 由 AppState.init() 装一次；重复调用无副作用。
    func start() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in ScreenCaptureWatch.refresh() }
            }
        // 两条通知各一个 token：旧写法只有一个 token 位，第二条会把它覆盖掉 ⇒ 观察者泄漏且取消订阅残缺。
        shotToken = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in ScreenCaptureWatch.shared.screenshotAt = Date().timeIntervalSince1970 }
            }
        // 2026-10-13 run 63: 原来只写 `refresh()` —— 在实例方法 start() 里裸调, 编译器优先找实例方法,
        // 找不到就报 "static member 'refresh' cannot be used on instance of type 'ScreenCaptureWatch'"。
        // 显式写类型名。
        ScreenCaptureWatch.refresh()
    }

    static func refresh() {
        shared.recording = UIScreen.screens.first?.isCaptured ?? false
    }

    /// 提示文案统一口径：说清挡什么、不假装能挡什么 (本仓纪律: 不虚构能力)
    static let notice = "检测到屏幕录制/镜像，口令明文已收起 — 停止采集后可再点一次揭示 (374)"
    static let shotNotice = "刚检测到一次系统截图 (336)。这张卡上的码值**可能**已进那张图片 — 截图 API 只说发生过截图，不保证拍到的就是这一屏。不放心就换码。"
}
