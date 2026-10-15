// 正控 3: dismiss() 在，但落在窗口之外（动作行后第 8 行）=> 判"没配套"，因为窗口只到 +6。
import SwiftUI
struct FireHostC: View {
    @State private var show = false
    var body: some View {
        Button("开") { show = true }
            .fullScreenCover(isPresented: $show) { FireTooFar() }
    }
}
struct FireTooFar: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("去记录页") {
            app.tabSelection = 2
            app.showToast("稍后")
            print("a")
            print("b")
            print("c")
            print("d")
            print("e")
            print("f")
            dismiss()
        }
    }
}
