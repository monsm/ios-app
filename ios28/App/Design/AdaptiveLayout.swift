// AdaptiveLayout.swift —— 宽窄两种版式（F12 / B64）。
//
// 这个 App 原本只给竖屏 iPhone 写：整个 DAYLIGHT 版式是**一条竖轴** ——
// 日光窗在上，读数与托盘在下，一路滑到底。把它摊到 iPad 上会得到一条
// **很长的窄列**，右边一大片空白 —— 那不是「适配」，是「没适配」。
//
// 现在分两种版式：
//   · 紧凑（iPhone 竖屏）：一条竖轴，不变。
//   · 宽版（iPad / 横屏）：日光窗占左半，读数与最近占右半。
//
// 判据用**尺寸类**（regular = iPad 全屏 / Plus 横屏），不是设备型号 ——
// 判设备型号会把「窗口大小」这件事漏掉（分屏、Stage Manager）。
import SwiftUI

enum LayoutMode {
    case compact
    case regular

    /// 宽版：左右两栏。
    static func isWide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular
    }
}

extension View {
    /// 宽版时把两个竖列并排放；紧凑时上下排。
    ///
    /// 判据由调用方给（尺寸类），不在这里猜 —— 猜宽度会在分屏拖动时抖。
    @ViewBuilder
    func twoColumns(_ wide: Bool,
                    @ViewBuilder leading: () -> some View,
                    @ViewBuilder trailing: () -> some View) -> some View {
        if wide {
            HStack(alignment: .top, spacing: T.S.l) {
                leading()
                    .frame(maxWidth: .infinity, alignment: .top)
                trailing()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                leading()
                trailing()
            }
        }
    }
}
