// 启动期系统职责的落点 (原 943「主屏长按快速操作」已随波 2 删除 —— 三项都只是跳转到已有页面)。
// 本文件现在只剩 QuickActionDelegate: UIApplicationDelegate 的三个启动职责 ——
//   ① 428 充电备份 BGTask 注册 (Apple 契约: 必须早于启动完成, 且每进程只注册一次);
//   ② 旧 plist 明文密钥搬进系统 Keychain;
//   ③ 0x88 包络 MAC 字节序裁定灌回协议层。
// 这三件都**不能**放进 App 的 onLaunch(): 那个函数挂在 .task 上、可能多次调用, 而
// BGTaskScheduler.register 晚于 applicationDidFinishLaunching 会抛 NSInternalInconsistencyException 直接崩进程。
import UIKit


/// 快捷项回调 + 启动期 BGTask 注册 (428)。
final class QuickActionDelegate: NSObject, UIApplicationDelegate {
    /// 428: `BGTaskScheduler.register` 必须在启动完成前调用 (Apple 契约) —— 晚于
    /// applicationDidFinishLaunching 会抛 NSInternalInconsistencyException 直接崩进程。
    /// 旧实现把它放在 App 的 onLaunch()(.task) 里, 且 onLaunch 可能被多次调用 ->
    /// 既有崩溃风险又有重复注册风险。挪到这里: 每进程恰好一次, 且在启动窗口内。
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 2026-10-14: 无条件注册 (注册须在启动窗口内且很轻); 排期由开关决定, 见 registerChargeBackup。
        BackupStudio.registerChargeBackup()
        DB.migrateSecretsToKeychain()
        DB.hydrateMacOrders()   // 0x88 包络 MAC 字节序: 把已裁定的顺序灌回协议层 (2026-10-17)
        return true
    }
}
