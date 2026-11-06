// ScreenAwake.swift —— 「开门时保持亮屏」。
//
// 只动一个公开开关（UIApplication.isIdleTimerDisabled）。
// 注意复位：上一版把复位放在 Task 收尾里，任务被取消那句话就没跑到，
// 屏幕一直亮着把电耗光。这里不用 Task，用页面出现/消失驱动。
import UIKit

@MainActor
enum ScreenAwake {
    /// 界面想要的态：true = 保持亮屏。
    /// 单独记一份，是为了让「回到前台」能把系统复位掉的开关补回来。
    private static var wanted = false

    /// 页面出现/开关变化时调。
    static func want(_ on: Bool) {
        wanted = on
        UIApplication.shared.isIdleTimerDisabled = on
    }

    /// 回到前台时调一次：系统在进后台时会把开关复位，这里按当前意愿补上。
    static func reapply() {
        UIApplication.shared.isIdleTimerDisabled = wanted
    }
}
