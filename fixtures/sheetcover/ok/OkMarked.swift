// 反控 4: 被 sheet 端出来过、也确实没 dismiss()，但带具名销号（现网 SettingsView:451 就是这个情形）。
import SwiftUI
struct OkHostC: View {
    @State private var show = false
    var body: some View {
        Button("开") { show = true }
            .sheet(isPresented: $show) { OkMarked() }
    }
}
struct OkMarked: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Button("去设备页") {
            app.tabSelection = 0
            // 收摊口径：这一处的两种呈现要的处理不同，本机判不了 dismiss() 在 Tab 根上的副作用，挂真机卡。
        }
    }
}
