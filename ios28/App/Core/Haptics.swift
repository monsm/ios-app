// Haptics.swift —— 触感反馈的总闸。
//
// 用户在「外观 · 手感」里关掉之后，全 App 不再震动 ——
// 开关必须真的连着执行链，否则它就是个装饰品。
import UIKit

@MainActor
enum Haptics {
    static var enabled: Bool { SettingsStore.shared.haptics }

    /// 成败提示（成功 / 失败 / 警告）。
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// 轻触一下（按下、确认）。**风格在初始化时给** —— `impactOccurred()` 本身没有带风格的重载。
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
