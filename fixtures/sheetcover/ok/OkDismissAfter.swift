// 反控 1: sheet 里的换 Tab 紧跟一句 dismiss()（本仓的正解形状，参照 LockOverviewView 那两枚格子）。
import SwiftUI
struct OkHostA: View {
    @State private var show = false
    var body: some View {
        Button("开") { show = true }
            .sheet(isPresented: $show) { OkDismissAfter() }
    }
}
struct OkDismissAfter: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("去设备页") { app.tabSelection = 0; dismiss() }
    }
}
