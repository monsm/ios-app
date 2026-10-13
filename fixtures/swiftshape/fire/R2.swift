// R2 正控：@ViewBuilder 挂在一段 /// 文档注释**之前**，于是属性落到了下一个声明身上 ——
// 而那个声明的显式类型是 String?，不是 some View ⇒ 该响。
// 这就是 RecordsTimeline 里 timeWords 那一处的形状 (属性本来想给上面那个 View 成员)。
import SwiftUI

struct R2Fire: View {
    var body: some View {
        Text(word ?? "—")
    }

    @ViewBuilder
    /// 时段词 —— 返回的是字符串，不是视图
    private var word: String? {
        let h = 9
        if h < 6 { return "凌晨" }
        return "白天"
    }
}
