// R6 正控：函数**没有** `-> 返回类型` (= Void), 却被当 View 用 ⇒ 该响。
// 编译器报 `type '()' cannot conform to 'View'` (run 57 的 AlarmCenterView/contextSection 就是这个形状)。
//
// 两种形状都响 (只许减不许增):
//   ① 无 @ViewBuilder 也无 -> : 最直接那种, CI 明确报过。
//   ② 带 @ViewBuilder 但无 -> : 理论上靠隐式 opaque 推导, 本机无编译器。原有 ok/OkBuilderNoArrow
//      反控断言它合法, 但从未被 CI 证实 (run 58 只报重复 @ViewBuilder), 故已从 ok/ 移除,
//      此门统一要求写 `-> some View`, 见 tools/swiftshape.js 的 R6 头注释。
import SwiftUI

struct R6Fire: View {
    var show: Bool
    var body: some View {
        Section("容器") {
            noBuilderSection()
            if show {
                builderNoArrowSection()
            }
        }
    }

    // 形状 ①: 无 @ViewBuilder 也无返回类型 —— 最直接的那种
    private func noBuilderSection() {
        Section("前后事件") {
            Text("孤立事件")
        }
    }

    // 形状 ②: 带 @ViewBuilder 但也没有返回类型
    @ViewBuilder
    private func builderNoArrowSection() {
        HStack { Text("另一处") }
    }
}

