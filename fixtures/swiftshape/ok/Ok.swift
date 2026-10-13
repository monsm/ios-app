// R1/R2 的反控：四种"看起来像但其实合法"的形状，一个都不许响。
// 响了的闸门就会开始制造噪音，而噪音的闸门没人看 (本仓 apisweep 头注里写着这条教训)。
import SwiftUI

struct OkBodyNoBuilder: View {
    // `var body` 由 View 协议自带 @ViewBuilder，实现处不写也合法 ⇒ R1 必须放过
    var body: some View {
        VStack {
            if flag {
                Text("开")
            }
        }
    }
    var flag = false
}

struct OkAttributedAfterComment: View {
    // 属性在 /// 文档注释之前，但它落的下一个声明确实是 some View ⇒ 合法
    private var title: some View {
        Text("标题")
    }

    @ViewBuilder
    /// 一段说明
    private var cards: some View {
        if flag {
            Text("有")
        }
    }
    var flag = false
}

struct OkReturnPath: View {
    // 有显式 return 的成员不需要 builder
    private var maybe: some View {
        if flag {
            return Text("开")
        }
        return Text("关")
    }
    var flag = false
}

struct OkElsePath: View {
    // 有 else 的顶层 if 是二选一，同样不需要 builder 兜住"空分支"
    private var either: some View {
        if flag {
            Text("开")
        } else {
            Text("关")
        }
    }
    var flag = false
}

struct OkUntypedFunc: View {
    // 没写显式类型的 @ViewBuilder 函数：判不了 (隐式 opaque 返回类型)，按边界规则不报
    @ViewBuilder
    private func row(_ t: String) {
        Text(t)
    }
}
