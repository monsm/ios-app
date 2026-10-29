// 色彩基元 · Color(hex:) / Color.adaptive(light:dark:)
// 2026-10-29 从 DesignSystem.swift 拆出。
import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
    /// 明暗自适应色。light / dark 为 6 位 RGB 十六进制
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}