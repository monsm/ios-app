import SwiftUI
struct BareToggleNeg: View {
  @State private var on = false
  var body: some View {
    // Toggle("x", isOn: $on) 是历史写法
    VariantToggle("x", isOn: $on)   // 原来写 Toggle("x", isOn: $on)
    chipToggle("y", on: $on)
  }
}
