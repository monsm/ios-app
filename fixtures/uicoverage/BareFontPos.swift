import SwiftUI
struct BareFontPos: View {
  var body: some View {
    VStack {
      Text("a").font(.caption.weight(.semibold))
      Text("b").font(.system(.footnote, design: .monospaced))
    }
  }
}
