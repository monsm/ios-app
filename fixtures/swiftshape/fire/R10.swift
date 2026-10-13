// R10 正控: `.frame(minHeight:maxWidth:)` 参数次序反了 ⇒ 该响。
// 编译器报 "argument 'maxWidth' must precede argument 'minHeight'"。
// 签名次序: minWidth/idealWidth/maxWidth 在前, minHeight/idealHeight/maxHeight 在后。
import SwiftUI

struct R10Fire: View {
    var body: some View {
        Button("重来一遍") { }
            .frame(minHeight: 44, maxWidth: .infinity, alignment: .leading)
    }
}
