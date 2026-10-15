// 正控 1: 页面被 sheet 端出来，换 Tab 只写值、不收摊。
import SwiftUI
struct FireHostA: View {
    @State private var show = false
    var body: some View {
        Button("开") { show = true }
            .sheet(isPresented: $show) { FireBareTab() }
    }
}
struct FireBareTab: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Button("去设备页") { app.tabSelection = 0 }
    }
}
