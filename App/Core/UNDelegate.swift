//
//  UNDelegate.swift
//  通知点按分派器 —— 2026-10-24 从已删的 BackupStudioKit.swift 独立出来
//
//  ## 为什么要单独成文件
//
//  它原来是 BackupStudioKit 里的一个 final class，而 BackupStudioKit（1434 行备份向导库）
//  在「备份精简为 iCloud 文件存取」时被删。删完才发现：**LockKeeperApp.init 里
//  `UNUserNotificationCenter.current().delegate = UNDelegate.shared` 仍指着它** ——
//  整个 App 编译不过。
//
//  它本来就不属于备份模块：职责是「用户点了本地通知，App 该落到哪一页」，
//  涉及凭证临期、每晚状态确认、保养到期三族通知。备份只是它服务的其中一族。
//
//  ## 与旧实现的差别（备份相关两条随向导一起移除）
//
//  · 移除「kf.bk.monthly → BackupStudio.onMonthlyTap()」—— 月度自动备份排程已随向导删除
//  · 移除「m4.care.<mac> → pendingCare」—— 保养到期待办页已按原版对照删除
//
//  保留两条**仍然活着**的分派：
//  · StatusCheckNotice.notifID → 设备页（963 每晚状态确认）
//  · CredentialOrg.handleNotificationAction → 凭证族通知（366/1013）
//
//  `@unchecked Sendable` 的依据是**没有可保护的状态**：本类零存储属性，
//  唯一职责是把点按转发成主 actor 上的路由动作（每个分支都已 Task { @MainActor in }）。
//  不是"把检查关掉"，是无锁可上。
//
import Foundation
import UserNotifications

final class UNDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = UNDelegate()

    // 方法名必须是 `withCompletionHandler:`。原写法 `completionHandler:` 与协议要求只差一个前缀，
    // 编译器给的是 nearly-matches 告警，而运行时这一支**永远不被调用** —— 通知点按等于没接。
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        // 963 每晚状态确认：点它就落到设备页（与深链/快速操作同一个 requestRoute 口，
        // 应用锁还锁着时只记 pendingRoute，不因为"是从通知进来的"就放行）。
        if r.notification.request.identifier == StatusCheckNotice.notifID {
            Task { @MainActor in
                var waited = 0
                while AppState.hostRef == nil && waited < 10 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    waited += 1
                }
                if let app = AppState.hostRef {
                    if app.appUnlocked && !app.decoyMode { app.requestRoute(.device) } else { app.pendingRoute = .device }
                }
            }
        }
        // 366/1013: 凭证族通知此前只排期不分派 —— handleNotificationAction 零调用，
        // 点"密码临期"通知落到系统默认行为（打开 App 停在原页面）。这里补上转发。
        if let act = CredentialOrg.handleNotificationAction(r.notification.request.identifier) {
            Task { @MainActor in CredentialOrg.applyNotification(act) }
        }
        completionHandler()
    }

    /// 前台展示：不实现 willPresent 时系统默认"前台完全静默"，用户正拿着手机反而看不到"密码临期"这类提醒。
    /// 夜间免扰（1031）时段仍静默，与 BatteryCare 的即时通知口径一致。
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                               withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        if CareSchedule.quietOn, CareSchedule.isQuietHour() {
            completion([])
        } else {
            completion([.banner, .sound])
        }
    }
}
