// 反控 2: dismiss() 写在动作**之前**（RecordsSampleGuideView 就是这个形状，所以窗口含前一行的代码）。
import SwiftUI
struct OkHostB: View {
    @State private var show = false
    var body: some View {
        Button("开") { show = true }
            .sheet(isPresented: $show) { OkDismissBefore() }
    }
}
struct OkDismissBefore: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("先去设备页再收") {
            dismiss()
            app.tabSelection = 0
        }
    }
}
