import SwiftUI

// R5 正负控·菜单: Menu 的**内容项**由系统给行高 (撑 minHeight 不改命中区, 只会把菜单撑高) ⇒ 不判;
// Menu **触发器自己**没有 minHeight ⇒ 那才是真缺陷, 必须开火。
struct MenuHit: View {
    var body: some View {
        Menu {
            Button("甲") { pick(1) }
            Button("乙") { pick(2) }
            Section("分组") {
                Button("丙") { pick(3) }
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "line.3.horizontal")
                Text("筛选")
            }
            .font(.caption)
        }
    }
    func pick(_ i: Int) {}
}
