import SwiftUI
struct BareFontNeg: View {
  var body: some View {
    // 历史写法: Text("a").font(.caption)
    Text("b").vkFont(.caption)          // 原来写 .font(.caption)
    Image(systemName: "lock").font(.system(size: DS.Icon.sm, weight: .medium))
    let gf = VKTypography.font(.caption2, weight: nil)
    ctx.draw(Text(stamp).font(gf), at: .zero)
  }
}
