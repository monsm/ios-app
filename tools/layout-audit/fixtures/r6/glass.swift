import SwiftUI

// R6 正控·玻璃面板: 链式 .axGlass(...) —— 旧实现数不到它, 会把这文件当"零材质"漏掉
struct GlassPanel: View {
    var body: some View {
        VStack { Text("甲") }
            .padding(DS.Space.l)
            .axGlass(DS.Radius.card)
    }
}

// R6 正控·胶囊玻璃: axGlassCapsule 必须与 axGlass 同列
struct GlassChip: View {
    var body: some View {
        Text("乙").axGlassCapsule()
    }
}
