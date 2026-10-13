// R8 正控: `Section("字符串字面量") { } footer: { }` —— 不是合法重载 ⇒ 该响。
// 编译器报 "missing argument label 'content:'" 与
// "cannot convert value of type 'String' to expected argument type '() -> Content'"。
// 合法写法是三段式: `Section { } header: { Text("标题") } footer: { }` (见 ok/Ok.swift 的反控)。
import SwiftUI

struct R8Fire: View {
    var body: some View {
        Form {
            Section("操作流水 (156)") {
                Text("记了没人读")
            } footer: {
                Text("只留最近若干条。")
                    .font(.caption)
            }
        }
    }
}
