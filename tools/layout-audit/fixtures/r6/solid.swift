import SwiftUI

// R6 正控·面板级实底: 一处 Palette.surface ⇒ 必须开火 (这一页还没有面板玻璃)
struct SolidPanel: View {
    var body: some View {
        VStack { Text("甲") }
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
