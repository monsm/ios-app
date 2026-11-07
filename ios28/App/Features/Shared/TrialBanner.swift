// TrialBanner.swift —— 只读试验模式的常驻提示条。
//
// 用户第二天会忘了自己开过它，然后以为 App 坏了 —— 所以它必须一直挂在
// 主界面顶部，直到用户回安全页把它关掉。挂在 RootView 的 safeAreaInset 上，
// 门禁页与三个 Tab 都看得见。
import SwiftUI

struct TrialBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(T.C.danger)
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
            Text("只读试验模式 · 写入不会下发到门锁")
                .type(T.F.caption)
                .foregroundStyle(T.C.danger)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // 常驻条属于顶栏浮层：底色走玻璃唯一入口，红色只做染色；
        // 与 Tab 栏 / Toast 同一材质口径，「减少透明度」时一并退化。
        .liquidGlass(in: Rectangle(), tint: T.C.danger.opacity(0.10))
        .accessibilityElement(children: .combine)
    }
}
