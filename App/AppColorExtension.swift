// Color 扩展（App 内语义色桥接）
// 2026-10-29 从 LockKeeperApp.swift 拆出。
import SwiftUI

extension Color {
    static var cardElevation: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(Color.white).withAlphaComponent(0.04)
                : UIColor(Color.black).withAlphaComponent(0.05)
        })
    }
}
