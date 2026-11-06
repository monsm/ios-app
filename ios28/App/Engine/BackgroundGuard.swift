// 后台任务保护 —— 让长操作在用户切走 App 时不被系统挂起。
//
// 2026-10-27 审核修复（AUDIT-D D-22）：全仓 0 处 `beginBackgroundTask`。
// 后果：配网 / 录指纹 / DFU 中途切后台（接电话、锁屏、误触 Home）会被系统立即挂起，
// 门锁留在**半完成态** —— 配网到一半、指纹录了一半、固件刷了一半。
//
// 注意与 BGTaskScheduler 的区别：
//   · BGTaskScheduler 需要 Info.plist 声明 permittedIdentifiers + UIBackgroundModes，
//     且是"系统在合适时机唤醒你"（不确定何时）；用户此前已决定删掉那套声明。
//   · beginBackgroundTask 只是"我要约 30 秒收尾时间"，**不需要任何声明**，也不保证唤醒。
//     这里要的正是后者：把已经在做的事做完，而不是开新的后台任务。
import UIKit

enum BackgroundGuard {
    /// 用 `withBackgroundGuard { ... }` 包住长操作。
    /// 结束时（含抛错）自动 endBackgroundTask —— 忘了 end 会被系统强杀。
    /// 2026-10-27 修编译：UIApplication.shared 是 main actor 隔离的，所以本函数必须 @MainActor。
    /// 调用点（配网/DFU）本来就在主 actor 上，加这个标注不改变任何调用方式。
    @MainActor
    static func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
        let app = UIApplication.shared
        var taskId: UIBackgroundTaskIdentifier = .invalid
        let exp = app.beginBackgroundTask(withName: name) {
            // 过期还没做完：系统马上要挂起我们了，主动结束（否则 App 会被杀）
            if taskId != .invalid { app.endBackgroundTask(taskId); taskId = .invalid }
        }
        taskId = exp
        defer {
            if taskId != .invalid {
                app.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }
        return try await body()
    }
}
