import SwiftUI

// R6 负控·盘中盘: surfaceAlt 是玻璃面上的盘子, 不是面板 ⇒ 不该因为它就报"层感不统一"
struct InnerPlate: View {
    var body: some View {
        VStack {
            Text("甲").background(DS.Palette.surfaceAlt, in: Capsule())
            Text("乙").background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .axGlass(DS.Radius.card)
    }
}
