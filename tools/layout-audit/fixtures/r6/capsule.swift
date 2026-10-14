import SwiftUI

// R6 正控·胶囊玻璃: axGlassCapsule 必须与 axGlass 数进同一列 ——
// 若它没被认成玻璃, 这文件的 glass 会是 0, 严重度从 md 掉到 lo, 断言当场失败。
struct CapsuleGlass: View {
    var body: some View {
        VStack(spacing: DS.Space.m) {
            Text("切换门锁").axGlassCapsule()
            VStack { Text("实底那块") }
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
        }
    }
}
