import SwiftUI
struct BareTabNeg: View {
  var body: some View {
    // app.requestTab(1) 是历史写法
    Text("n").onTapGesture { app.requestRoute(.credentials) }   // 原来写 app.requestTab(3)
  }
}
