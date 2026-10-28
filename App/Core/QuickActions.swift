// 启动期系统职责的落点 (原 943「主屏长按快速操作」已随波 2 删除 —— 三项都只是跳转到已有页面)。
// 本文件现在只剩 QuickActionDelegate: UIApplicationDelegate 的两个启动职责 ——
//   ① 旧 plist 明文密钥搬进系统 Keychain;
//   ② 0x88 包络 MAC 字节序裁定灌回协议层。
// 这两件都**不能**放进 App 的 onLaunch(): 那个函数挂在 .task 上、可能多次调用。
import UIKit
import UserNotifications


/// 启动期系统职责。
final class QuickActionDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DB.migrateSecretsToKeychain()
        DB.hydrateMacOrders()   // 0x88 包络 MAC 字节序: 把已裁定的顺序灌回协议层 (2026-10-17)
        // 2026-10-28 修复：全仓**从未调用 requestAuthorization**，也没设过
        // UNUserNotificationCenterDelegate —— 于是 CredentialOrg.scheduleAlerts 排的 6 条
        // 到期通知即使送达也点不动（handleNotificationAction/applyNotification 零调用）。
        // 这里补上：启动即申请授权 + 设 delegate。
        let nc = UNUserNotificationCenter.current()
        nc.delegate = NotificationDelegate.shared
        nc.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
            if let err { CredentialOrg.notifyLog.error("通知授权失败: \(String(describing: err), privacy: .public)") }
            else if !granted { CredentialOrg.notifyLog.error("用户未授予通知权限：到期提醒不会送达") }
        }
        return true
    }

}


/// 2026-10-28：通知点按的 delegate —— **独立于 UIApplicationDelegate**。
///
/// 为什么不直接让 `QuickActionDelegate` 兼：Swift 6 严格并发下
/// `UNUserNotificationCenterDelegate` 的协议要求是 nonisolated 的，
/// 而 `UIApplicationDelegate` 的实现是 main-actor 隔离；两者混在同一个类上会报
/// 「conformance crosses into main actor-isolated code」。
/// 拆开之后：这个类整体 nonisolated，只在跳转那一步显式切回 MainActor。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // 2026-10-28：@unchecked Sendable 是**有据**的 —— 这个类没有任何存储属性，
    // 两个方法都是 nonisolated 的纯函数式实现（不读写实例状态）。
    // 缺了它，static let shared 会在 Swift 6 严格并发下报
    // 「non-Sendable type may have shared mutable state」。
    static let shared = NotificationDelegate()

    /// 点按通知 → 定位到那条凭证。
    /// `CredentialOrg` 早就有 `handleNotificationAction`（解析 id）与 `applyNotification`（落点），
    /// 但没有任何 delegate 调它们，等于整条链断在最后一米。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        if let action = CredentialOrg.handleNotificationAction(id) {
            Task { @MainActor in CredentialOrg.applyNotification(action) }
        }
        completionHandler()
    }

    /// 前台也显示：否则 App 在前台时用户看不到到期提醒。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}