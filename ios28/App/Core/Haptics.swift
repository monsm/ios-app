// Haptics.swift —— 触感反馈的总闸。
//
// 用户在「外观 · 手感」里关掉之后，全 App 不再震动 ——
// 开关必须真的连着执行链，否则它就是个装饰品。
//
// F30：把「一下」拆成一套**有语义的词汇**。以前只有按下与成败两种，
// 现在每一步都有它自己的手感：连上、下发、回执、成功、失败、警告。
// 触觉是这条链路上唯一不惊动人却能表达「进行到哪了」的通道。
import UIKit
import AVFoundation

@MainActor
enum Haptics {
    static var enabled: Bool { SettingsStore.shared.haptics }
    static var soundEnabled: Bool { SettingsStore.shared.sound }

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

    // MARK: - 词汇（F30）

    /// 开锁链上的每一步。
    enum Cue {
        /// 镜头被按下。
        case press
        /// 连上门锁。
        case connecting
        /// 命令已下发。
        case sent
        /// 收到门锁回执。
        case receipt
        /// 门开了。
        case opened
        /// 没打开。
        case failed
        /// 提醒（到期、低电）。
        case warning
    }

    /// 按词汇给触感。
    static func cue(_ cue: Cue) {
        guard enabled else { return }
        switch cue {
        case .press:
            impact(.light)
        case .connecting:
            impact(.soft)
        case .sent:
            impact(.rigid)
        case .receipt:
            impact(.medium)
        case .opened:
            notify(.success)
        case .failed:
            notify(.error)
        case .warning:
            notify(.warning)
        }
        play(cue)
    }

    // MARK: - 音效（F30）

    /// 极轻的一声（默认关）。门锁这个场景不该突然出声 ——
    /// 掏钥匙的时候手机响一声是很吓人的。
    private static func play(_ cue: Cue) {
        guard soundEnabled else { return }
        let id: SystemSoundID
        switch cue {
        case .press, .receipt: id = 1104
        case .connecting: id = 1103
        case .sent: id = 1105
        case .opened: id = 1057
        case .failed: id = 1053
        case .warning: id = 1073
        }
        AudioServicesPlaySystemSound(id)
    }
}
