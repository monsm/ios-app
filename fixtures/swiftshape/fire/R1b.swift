// R1b 正控：声明 some View、体内**顶层以 let/var 绑定起头**、末尾一个表达式、又没写 return、
// 也没写 @ViewBuilder ⇒ 该响。编译器报的正是
//   "function declares an opaque return type, but has no return statements in its body"。
// 这一份与 run 56 那次提交里 LockCompareView/rhythmSection 的形状同构：
//   let la = …; let lb = …; Section("…") { … }
// 为什么与 R1 分开编号：R1 抓的是"顶层 if 没有 else"，这一条压根没有 if —— 靠 if 判据永远看不见它。
import SwiftUI

struct R1bFire: View {
    var leftModel: Int?
    var rightModel: Int?

    private var rhythmSection: some View {
        let la = leftModel ?? 0
        let lb = rightModel ?? 0
        Section("工作日首次开门时刻 (780)") {
            Text("左 \(la) · 右 \(lb)")
        }
    }
}
