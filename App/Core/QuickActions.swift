// 启动期系统职责的落点 (原 943「主屏长按快速操作」已随波 2 删除 —— 三项都只是跳转到已有页面)。
// 本文件现在只剩 QuickActionDelegate: UIApplicationDelegate 的两个启动职责 ——
//   ① 旧 plist 明文密钥搬进系统 Keychain;
//   ② 0x88 包络 MAC 字节序裁定灌回协议层。
// 这两件都**不能**放进 App 的 onLaunch(): 那个函数挂在 .task 上、可能多次调用。
import UIKit


/// 启动期系统职责。
final class QuickActionDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DB.migrateSecretsToKeychain()
        DB.hydrateMacOrders()   // 0x88 包络 MAC 字节序: 把已裁定的顺序灌回协议层 (2026-10-17)
        return true
    }
}
