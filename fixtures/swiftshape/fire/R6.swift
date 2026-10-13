// R6 正控：函数**没有** `-> 返回类型` (= Void)、却被当 View 用 ⇒ 该响。
// 编译器报的是 `type '()' cannot conform to 'View'`。
// 两种信号各来一个 (与 run 57 的 AlarmCenterView 两处同构)：
//   (a) 连 @ViewBuilder 都没有的 → contextSection 那种;
//   (b) 有 @ViewBuilder 但没写 -> 的 → detailSection 那种 (@ViewBuilder 只是把语句拼成 Void, 不改变返回类型)。
import SwiftUI

struct R6Fire: View {
    var show: Bool
    var body: some View {
        Section("容器") {
            oneLine()
            if show {
                noBuilderSection()
            }
            builderNoArrowSection()
        }
    }

    private func oneLine() -> some View { Text("占位") }

    // (a) 无 @ViewBuilder 也无返回类型 —— 最直接的那种
    private func noBuilderSection() {
        Section("前后事件") {
            Text("孤立事件")
        }
    }

    // (b) 有 @ViewBuilder 却漏了 `-> some View`
    @ViewBuilder
    private func builderNoArrowSection() {
        let n = 1
        Section("详情") {
            Text("条数 \(n)")
        }
    }
}
