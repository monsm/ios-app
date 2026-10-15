// 正控 2: 换成 requestTab 也不算修好 —— 它只过访客门禁，不收这一层 sheet。
import SwiftUI
struct FireHostB: View {
    @State private var show = false
    var body: some View {
        Button("开") { show = true }
            .sheet(isPresented: $show) { FireRequestTab() }
    }
}
struct FireRequestTab: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Button("去凭证") { app.requestTab(1); app.showToast("已排好") }
    }
}
