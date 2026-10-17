// 374 录屏遮罩 —— 屏幕录制/镜像时不显示口令明文
// 336 截图警示 —— 监 `UIApplication.userDidTakeScreenshotNotification` (公开 API, 已按 docs/API-VERIFY.md
// 撞过官方页: UIKit/UIApplication/userDidTakeScreenshotNotification = 200)。
// 用 UIScreen.isCaptured (公开 API, iOS 11+) + capturedDidChangeNotification。
// 取"正在采集的那块屏"走 scene 一侧 (key window 所在 scene 的 screen)。
// 历史上这里先用 UIScreen.main (iOS 16 起弃用), 又换成 UIScreen.screens.first (同样弃用) ——
// 多屏 (外接显示) 时"哪块屏在录"既不该由 main 猜, 也不该由数组顺序猜。
//
// 边界写清楚，不过度承诺：这个 API 只能告诉你"系统正在采集屏幕"，
// 不知道被谁采集、采集到哪；越狱/私有钩子绕过不可防。所以它挡的是"随手录屏留档"，不是硬对抗。
// 截图通知同理：**只知道发生过一次截图**，不知道拍到的是不是这一屏 (它可能在采集后才切走)，
// 所以 336 的话术是"可能已进那张图片"而不是"已拍到"。
import UIKit
import Combine
import SwiftUI   // 常亮修饰符 (ScreenAwakeWhile) 要用 View/ViewModifier —— 原文件只用 UIKit/Combine, 这里是本文件第一处 SwiftUI 依赖

@MainActor
final class ScreenCaptureWatch: ObservableObject {
    static let shared = ScreenCaptureWatch()
    @Published private(set) var recording = false   // 真值由 start() 末尾的 refresh() 落 (不在默认值里用弃用 API)
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
        // UIScreen.screens 自 iOS 16 弃用 (编译器点名改用 scene 一侧)。要的是"用户正在看的这块屏
        // 是否在录", 所以取 key window 所在 scene 的 screen —— 外接显示时这比 screens.first 那个
        // "数组里第一个"更有定义。取 key window 的写法仓库里早有先例 (AccessibilityKit:214)。
        let captured = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.screen.isCaptured ?? false
        shared.recording = captured
    }

    /// 提示文案统一口径：说清挡什么、不假装能挡什么 (本仓纪律: 不虚构能力)
    static let notice = "检测到屏幕录制/镜像，口令明文已收起 — 停止采集后可再点一次揭示"   // 374 检测到屏幕录制
    static let shotNotice = "刚检测到一次系统截图。这张卡上的码值**可能**已进那张图片 — 截图 API 只说发生过截图，不保证拍到的就是这一屏。不放心就换码。"   // 336 刚检测到一次系统截图
}

// ================= 常亮 (APK 对照: brightness.setKeepScreenOn) =================
// 原版在两页调 brightness 插件的 setKeepScreenOn (build/main.js: CheckfirmwareupdatePage.ionViewDidEnter/Leave
// 与 StartaddfpPage 同名回调 —— 本仓一度以为这个插件是装饰, 实际它就在这两条长任务上)。
// 为什么 iOS 上也要做: 升级要连续传输几分钟、录指纹要用户把手指按在锁上几十秒 ——
// 屏幕一旦自动锁定, 系统会把本进程挂起, 蓝牙链路跟着断, 传输死在半途而界面上还停在"正在传输"。
// 只覆写 isIdleTimerDisabled 这一个公开开关: 不碰亮度、不装后台任务、不申请任何权限。
@MainActor
struct ScreenAwakeWhile: ViewModifier {
    /// 条件为真时置常亮; 变假或页面消失即恢复
    /// (刻意不留全局开关: 长任务失败后忘记复位的代价是整机不再息屏, 比多写两行修饰符贵得多)
    var active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onDisappear { release() }
            .onChange(of: active) { _, _ in sync() }
    }

    private func sync() { UIApplication.shared.isIdleTimerDisabled = active }
    private func release() { UIApplication.shared.isIdleTimerDisabled = false }
}

extension View {
    /// 长任务期间不许自动锁屏。调用点: FirmwareView (升级中) / StartAddFpView (录入中)。
    func keepingScreenAwake(_ active: Bool) -> some View {
        modifier(ScreenAwakeWhile(active: active))
    }
}
