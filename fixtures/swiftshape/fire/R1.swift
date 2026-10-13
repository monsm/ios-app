// R1 正控：声明 some View、体内有顶层 if 而没有 else / return，又没写 @ViewBuilder ⇒ 该响。
// 这一份与 run 47 那次提交带进来的形状同构 (SettingsView 的 autoOpenSection)。
import SwiftUI

struct R1Fire: View {
    var mac: String
    var body: some View {
        VStack {
            risky
        }
    }

    private var risky: some View {
        if !mac.isEmpty {
            Text("有锁")
        }
    }
}
