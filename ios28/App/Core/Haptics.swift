// Haptics.swift —— 触感反馈的总闸。
//
// 用户在「外观 · 手感」里关掉之后，全 App 不再震动 ——
// 开关必须真的连着执行链，否则它就是个装饰品。
import SwiftUI
import UIKit

@MainActor
enum Haptics {
    static var enabled: Bool { SettingsStore.shared.haptics }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard enabled else { return }
        UIImpactFeedbackGenerator().impactOccurred(style)
    }
}

extension View {
    /// SwiftUI 的 `sensoryFeedback` 没有「关掉」的重载，所以自己包一层：
    /// 用户关掉触感反馈后，这一处就不该再震。
    @MainActor
    @ViewBuilder
    func hapticFeedback(_ feedback: SensoryFeedback, trigger: some Equatable) -> some View {
        if SettingsStore.shared.haptics {
            self.sensoryFeedback(feedback, trigger: trigger)
        } else {
            self
        }
    }
}
