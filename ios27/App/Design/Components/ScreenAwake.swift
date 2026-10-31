// ScreenAwake.swift —— 长任务常亮（DFU / 指纹录入）。
//
// 原版 APK 在「检查固件更新」与「添加指纹」两页调 brightness.setKeepScreenOn(true/false)。
// iOS 上这不是装饰：DFU 连续传输几分钟、录指纹要用户把手指按在锁上几十秒，屏幕一自动锁定
// 系统就挂起本进程，蓝牙链路当场断，而屏上还停在「正在传输」。
import UIKit

enum ScreenCare {
    /// 只覆写 isIdleTimerDisabled 一个公开开关；离开页面或任务结束必须复位。
    static func keepingAwake(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = active
    }
}
