import SwiftUI

// R6 正控·定性豁免: 带 @layout-allow 标记的实底面板不再算"混用缺陷", 改记一条"已定性"
// (标记挪走 ⇒ 立刻重新开火 —— 豁免必须能被机器撤掉, 否则就是永久盲点)
struct AllowedSolid: View {
    var body: some View {
        VStack(spacing: DS.Space.m) {
            VStack { Text("甲") }.axGlass(DS.Radius.card)
            VStack { Text("乙") }
                // 它在 List 的行组里, 行组已是玻璃面 ⇒ 玻璃叠玻璃
                // @layout-allow 面板实底
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
    }
}
