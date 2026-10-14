import SwiftUI

// R6 正控·同屏混用: 一块玻璃面板 + 一块实底面板 ⇒ md (这才是"层感不统一"的成立条件)
struct MixedPanel: View {
    var body: some View {
        VStack(spacing: DS.Space.m) {
            VStack { Text("甲") }
                .axGlass(DS.Radius.card)
            VStack { Text("乙") }
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            Text("丙").background(DS.Palette.surfaceAlt, in: Capsule())
        }
    }
}
