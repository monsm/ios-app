import SwiftUI

// R5 正控·ButtonStyle 托管: 样式在 makeBody 里自己 .frame(minHeight: DS.Hit.min + 6) (=50)
// ⇒ 命中区由样式给, 报"触达不足 16.5pt"就是假警报 (本仓 28 个 BusyButton 都靠这条活着)。
struct TallStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, DS.Space.m + 2)
            .frame(minHeight: DS.Hit.min + 6)
            .background(DS.Palette.accent, in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}

// 对照组: 样式里一个尺寸都不给 ⇒ 这颗必须照报 (豁免必须是可撤销的豁免)
struct FlatStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, DS.Space.s)
    }
}

// 两颗都写成 label 闭包 (label 只用 Button("标题"){…} 那种字符串参数时, 分析器拿不到文字节点,
// 本来就不会开火 —— 那不是"托管"判据在起作用, 断言会假过)。
struct StyledHits: View {
    var body: some View {
        VStack(spacing: DS.Space.m) {
            Button { go() } label: {
                Text("主操作")
                    .font(.caption)
            }
            .buttonStyle(TallStyle())
            Button { go() } label: {
                Text("次操作")
                    .font(.caption)
            }
            .buttonStyle(FlatStyle())
        }
    }
    func go() {}
}
