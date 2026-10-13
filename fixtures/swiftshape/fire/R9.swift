// R9 正控: `Section(isExpanded:) { } header: { } footer: { }` —— 该重载**没有 footer 参数** ⇒ 该响。
// 编译器报 "extra trailing closure passed in call" (run 59 的 DeviceManageView:62 就是这个形状)。
import SwiftUI

struct R9Fire: View {
    @State private var open = true
    var body: some View {
        Form {
            Section(isExpanded: $open) {
                Text("一组锁")
            } header: {
                Text("未分组")
            } footer: {
                Text("「未分组」不是一个组。")
            }
        }
    }
}
