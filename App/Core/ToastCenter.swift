// 全局顶部提示条 —— 独立成一个 ObservableObject
//
// 2026-10-29 性能：`toast` 原来挂在 `AppState` 上（`@Published var toast`），而
// `RootView` 与 43 个视图都观察 `AppState` —— 于是**每弹一条提示就把整棵视图树重算一遍**。
// 提示是高频动作（每次保存/失败/校验都会弹），这条开销完全是白付的。
//
// 现在拆成独立的 ToastCenter：
//   · `AppState.showToast` 只往这里转发；
//   · UI 侧只有一个很小的 `ToastBannerHost` 观察它 —— 重算范围从"全 App"缩到"一条提示条"。
import SwiftUI

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var toast: String?
    private init() {}

    /// 2026-10-30 修复（第 73 轮）：**世代号**取代 `toast == msg` 判据。
    ///
    /// 原判据的漏洞：连续弹两条**相同文本**的提示（例如连点两次都失败）时，
    /// 第一条的延时任务先到期 —— 此时 `toast` 仍是同一个字符串（第二条刚设的），
    /// 于是它把**第二条**的显示提前抹掉，第二条本该停 1.8~3.4 秒却只显示了零点几秒。
    /// 用户看到的是"提示闪一下就没了"，且只在重复操作时复现，很难查。
    /// 现在每次 show 领一个世代号，**只有最新那次**有权清除。
    private var seq = 0

    /// 显示一条提示；长文案停留更久（保证读得完）。
    func show(_ msg: String) {
        seq &+= 1
        let mine = seq
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = msg }
        let stay: UInt64 = msg.count > 20 ? 3_400_000_000 : 1_800_000_000
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: stay)
            guard let self, self.seq == mine else { return }
            // 只有最新一次 show 有权清除 —— 期间又弹过（哪怕文本相同）就交给那一次去清。
            withAnimation(.easeIn(duration: DS.Duration.quick)) { self.toast = nil }
        }
    }
}

/// 只观察提示条的小宿主 —— 放在 `RootView.topBanners` 里，替代原先直接读 `app.toast`。
struct ToastBannerHost: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        if let t = center.toast {
            ToastView(text: t)
                .allowsHitTesting(false)   // 顶部提示不吃点击
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
