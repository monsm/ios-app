// R7 正控：同一条声明上挂了两个 @ViewBuilder ⇒ 该响。
// 编译器报 "only one result builder attribute can be attached to a declaration"。
// 这一份与 run 58 那次提交的形状同构 —— 补 -> some View 时没数清上面已有的那个 @ViewBuilder。
import SwiftUI

struct R7Fire: View {
    var n: Int
    var body: some View {
        Section("容器") { card() }
    }

    @ViewBuilder
    @ViewBuilder
    private func card() -> some View {
        Section("详情") { Text("\(n)") }
    }
}
