import SwiftUI
struct BareTogglePos: View {
  @State private var on = false
  var body: some View { Toggle("x", isOn: $on) }
}
