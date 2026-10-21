import SwiftUI

// ============================================================
// 纪念时刻卡层 (2026-10-16 从 mainTabsChrome 抽出；2026-10-16 晚变体清理后独立成文件)
// ------------------------------------------------------------
// 抽出来的唯一原因是原来有三套界面变体、各写一份条件就会漂移；变体已删，
// 这里就只剩「一次浮现」这一段行为，留在自己文件里最省事。
// ============================================================

struct MomentLayer: ViewModifier {
    @EnvironmentObject var app: AppState

    func body(content: Content) -> some View {
        content
            .overlay {
                if let m = app.moment {
                    MomentCardView(moment: m) { app.advanceMoment() }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(XMotion.soft, value: app.moment)
    }
}
