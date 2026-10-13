// R12 正控: View 扩展方法**从不引用 self** ⇒ 该响。
// 症状不是编译错误, 而是"编译全绿、装到手机打开 App 一片空白":
// `X.f()` 的结果是函数体返回的那个视图, X 整个不见了。
// 真身: DesignSystem.dsScreenBackground() 曾这么写, 全仓 99 处调用点 ⇒ 每页只剩底色。
import SwiftUI

extension View {
    func r12FireBackground() -> some View {
        Group {
            LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}
