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
        // SEC-01：旧版本把门锁密码明文写在 plist 的 kf_ledger_ 里。搬进 Keychain 之后
        // 才能把明文抹掉 —— 否则一份 iTunes/iCloud 备份就能读走全部开门口令。
        // 幂等：搬过的条目在 plist 里已经没有 pwd，再调是 no-op。
        DB.migrateLedgerSecrets()
        // SEC-01：手机钥匙的 pin/ekey 同样从 plist 搬进 Keychain。
        MobileKeyService.migrateSecrets()
        DB.hydrateMacOrders()   // 0x88 包络 MAC 字节序: 把已裁定的顺序灌回协议层 (2026-10-17)
        // delegate 必须在启动时设好（点按通知的路由）。
        let nc = UNUserNotificationCenter.current()
        nc.delegate = NotificationDelegate.shared
        // 2026-11-03（真机截图 + HIG《Notifications》）：**授权请求移出启动**。
        // 原来这里 didFinishLaunching 就 requestAuthorization ⇒ 用户第一眼看到的是系统弹窗
        // 而不是 App（CI 截图 6 张被子页全被它挡住）。HIG 要求在**上下文时机**请求 ——
        // 本仓的上下文就是「第一次真的排了一条到期提醒」：CredentialOrg.scheduleAlerts 现在先调
        // QuickActions.ensureNotificationAuthorization()，用户在"要收提醒"的那一刻才被问。
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
/// 通知授权状态（本地记一份，供健康检查与诊断包读）。
enum NotificationStatus {
    enum State: Int {
        case unknown = 0
        case authorized = 1
        case denied = 2
        case failed = 3

        /// 人话标签（属于**状态**，不是外层枚举）。
        var label: String {
            switch self {
            case .unknown: return "未询问"
            case .authorized: return "已授权"
            case .denied: return "已拒绝"
            case .failed: return "询问失败"
            }
        }
    }
    private static let key = "kf_notify_status"

    static func record(_ state: State) {
        DB.store.setInt(key, state.rawValue)
    }

    static var current: State {
        State(rawValue: DB.store.getInt(key, 0)) ?? .unknown
    }

    /// 当前状态的人话标签。
    static var label: String { current.label }
}

enum NotificationAuth {
    private static let asked = Locked(false)
    /// 幂等：一次会话只问一次；已授权时 requestAuthorization 立即返回 granted，无弹窗。
    static func ensure() {
        guard !asked.withLock({ $0 }) else { return }
        asked.withLock { $0 = true }
        let nc = UNUserNotificationCenter.current()
        nc.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
            // 把真实状态记下来：健康检查与诊断包要读它。
            // 以前没有任何地方记过这件事，于是「通知有没有授权」只能现场问系统
            // （那要等一个回调），诊断包就写不出结论。
            if let err {
                NotificationStatus.record(.failed)
                CredentialOrg.notifyLog.error("通知授权失败：\(String(describing: err), privacy: .public)")
            } else if !granted {
                NotificationStatus.record(.denied)
                CredentialOrg.notifyLog.error("用户未授予通知权限：到期提醒不会送达")
            } else {
                NotificationStatus.record(.authorized)
            }
        }
    }
}

/// 2026-11-03：通知授权移出启动 —— 在用户**第一次排到期提醒**时才问。
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
            Task { @MainActor in
                // 2026-11-01 修复：冷启动点通知时宿主还没 onAppear 注册，
                // 旧写法 `guard let host ... else { return }` 会**静默丢弃**这次点击 ——
                // 用户看到 App 打开了，但没跳到那条凭证。改走 `whenReady`：
                // 未就绪就排队，注册时立刻消费。
                EngineHostRegistry.whenReady { host in
                    CredentialOrg.applyNotification(action, host: host)
                }
            }
        }
        completionHandler()
    }

    /// 前台也显示：否则 App 在前台时用户看不到到期提醒。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}